# SoleVision — Profile Architecture

> **Purpose:** This document gives another AI agent everything it needs to understand, navigate, and modify profile-related code in the SoleVision Flutter app. Read this before touching any profile file.

---

## 1. Database Schema — `profiles` table

**File:** `supabase/schema.sql` (lines 18–30)

```sql
CREATE TABLE IF NOT EXISTS public.profiles (
    id              UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    full_name       TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    phone           TEXT,
    role            TEXT NOT NULL DEFAULT 'customer'
                        CHECK (role IN ('customer', 'seller', 'admin')),
    seller_status   TEXT NOT NULL DEFAULT 'pending'
                        CHECK (seller_status IN ('none', 'pending', 'approved', 'rejected')),
    avatar_url      TEXT,
    suspended       BOOLEAN DEFAULT false,
    rejection_reason TEXT,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
```

### Key columns

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `id` | UUID (PK) | — | Matches `auth.users.id`. Cascade-deletes on user removal. |
| `full_name` | TEXT | — | Display name. |
| `email` | TEXT | — | Unique. Set on signup, never changed after. |
| `phone` | TEXT | NULL | Optional. Editable via profile screen. |
| `role` | TEXT | `'customer'` | One of: `customer`, `seller`, `admin`. |
| `seller_status` | TEXT | `'pending'` | One of: `none`, `pending`, `approved`, `rejected`. |
| `avatar_url` | TEXT | NULL | Public URL in the `avatars` storage bucket. |
| `suspended` | BOOLEAN | `false` | Admin-only flag. |
| `rejection_reason` | TEXT | NULL | Set when seller application is rejected. |
| `created_at` | TIMESTAMPTZ | `now()` | Used for "Member Since" display. |

### RLS Policies

```sql
-- Everyone can read profiles (public profile data)
CREATE POLICY "Public profiles are viewable by everyone"
    ON public.profiles FOR SELECT USING (true);

-- Users can insert their own profile (signup trigger + manual upsert)
CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Admins can update any profile (role changes, seller approval)
CREATE POLICY "Admins can update any profile"
    ON public.profiles FOR UPDATE USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    );

-- Admins can read all profiles
CREATE POLICY "Admins can read all profiles"
    ON public.profiles FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    );
```

---

## 2. Auth & Profile Lifecycle

### Signup Flow

```
User taps "Sign Up"
  → AuthService.signUp(fullName, email, password, sellerStatus)
    → Supabase auth.signUp(email, password, data: {full_name})
    → Upsert into profiles table with: id, full_name, email, role='customer', seller_status
    → AuthService.getProfile(userId) — retries up to 5 times (trigger may lag)
  → AuthProvider receives { user, profile }
  → onLoginHook fires (sets up providers that need userId)
```

### Login Flow

```
User taps "Login"
  → AuthService.signIn(email, password)
    → Force sign-out any existing session
    → Supabase auth.signInWithPassword(email, password)
    → AuthService.getProfile(userId) — retries up to 5 times, auto-creates if missing
  → AuthProvider receives { user, profile }
  → onLoginHook fires
```

### Session Restore (App Launch)

```
AuthProvider() constructor
  → _restoreSession()
    → Check Supabase currentUser
    → If exists: fetch profile from DB, set _currentUser + _profile
    → notifyListeners()
```

---

## 3. State Management — `AuthProvider`

**File:** `lib/providers/auth_provider.dart`

### Properties

```dart
Map<String, dynamic>? _currentUser;  // { id, email }
Map<String, dynamic>? _profile;      // Full row from profiles table
bool _isLoading;
String? _errorMessage;
```

### Computed Getters (derived from `_profile`)

```dart
String get userRole      => _profile?['role'] ?? 'customer';
String get sellerStatus  => _profile?['seller_status'] ?? 'approved';
String get displayName   => _profile?['full_name'] ?? 'User';
String get displayEmail  => _profile?['email'] ?? '';
String get displayPhone  => _profile?['phone'] ?? '';
String? get avatarUrl    => _profile?['avatar_url'];
```

### Key Methods

| Method | What it does |
|--------|-------------|
| `login(email, password)` | Clears state → signIn → sets `_currentUser` + `_profile` → calls `onLoginHook` |
| `signUp(...)` | Creates auth user + profile row → auto-login → calls `onLoginHook` |
| `updateProfile(fullName, phone?, newAvatarUrl?)` | Calls `SupabaseService.updateProfile()` → replaces `_profile` with returned row |
| `resetPassword(email)` | Sends Supabase password-reset email |
| `logout()` | Clears all state → signOut → clears biometric creds → calls `onLogoutHook` |

---

## 4. Service Layer

### `ProfileService` (singleton)

**File:** `lib/services/profile_service.dart`

Responsible for **avatar operations only**:

```dart
class ProfileService {
  static final ProfileService instance = ProfileService._();

  // Pick image from gallery (max 1000x1000, quality 85)
  Future<XFile?> pickAvatarImage();

  // Upload to Supabase Storage 'avatars' bucket → updates profiles.avatar_url
  Future<String> uploadAvatar({required String userId, required String filePath});
}
```

**Upload flow:**
1. `UploadService.uploadFile(bucket: 'avatars', folder: userId, filename: 'avatar.jpg', upsert: true)`
2. `profiles.update({ avatar_url: publicUrl }).eq('id', userId)`
3. Returns the public URL

### `SupabaseService` (singleton)

**File:** `lib/services/supabase_service.dart`

Contains `updateProfile()`:

```dart
Future<Map<String, dynamic>> updateProfile(
  String id,
  String fullName, {
  String? phone,
  String? avatarUrl,
}) async {
  final update = <String, dynamic>{
    'full_name': fullName.trim(),
    'phone': phone,
  };
  if (avatarUrl != null) update['avatar_url'] = avatarUrl;

  return await _client
      .from('profiles')
      .update(update)
      .eq('id', id)
      .select()
      .single();
}
```

### `AuthService` (singleton)

**File:** `lib/services/auth_service.dart`

Handles auth + profile creation. Key method:

```dart
// getProfile with retry logic (trigger may lag after signup)
Future<Map<String, dynamic>?> getProfile(String userId) async {
  for (int attempt = 1; attempt <= 5; attempt++) {
    final data = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    if (data != null) return data;
    await Future.delayed(Duration(seconds: attempt));
  }
  // Fallback: manually create profile if trigger didn't fire
  await _client.from('profiles').upsert({...});
  return await _client.from('profiles').select().eq('id', userId).maybeSingle();
}
```

---

## 5. UI Screens

### 5a. Shared Profile Screen (Primary)

**File:** `lib/screens/shared/profile_screen.dart`
**Re-exported by:** `lib/screens/customer/profile_screen.dart`

This is the **main profile screen** used by customers. It is a `StatefulWidget` with inline editing.

#### Sections (top to bottom):

1. **Header** — Avatar (with camera overlay for upload) + Name + Edit toggle + Email + Role badge + Following count
2. **Collapsible Edit Panel** — AnimatedSize toggle showing:
   - Full Name (editable TextField)
   - Email (locked, grey background)
   - Phone Number (editable TextField)
   - Save Changes button
3. **Notifications Panel** — "My Orders" row with 5 category icons (Unpaid, Processing, Shipped, Review, Returns) showing unread badge counts
4. **Settings Card** — Change Password, Terms & Privacy, Help & Support, About SoleVision
5. **Seller Section** (if `userRole == 'seller'`) — Store link, Seller Status chip, Member Since
6. **Logout Button** — Confirmation dialog → `auth.logout()`

#### Key state variables:

```dart
bool _isEditing = false;       // toggles edit panel
bool _isSaving = false;        // loading state for save
bool _isUploadingAvatar = false; // loading state for avatar
String? _loadedProfileId;      // prevents re-syncing controllers
late TextEditingController _nameController;
late TextEditingController _phoneController;
Future<Map<String, dynamic>?>? _sellerStoreFuture; // loaded if seller
```

#### Key methods:

| Method | What it does |
|--------|-------------|
| `_syncControllers(auth)` | Syncs text controllers with `auth.displayName` / `auth.displayPhone`. Only runs when profile ID changes. |
| `_toggleEdit(auth)` | Toggles `_isEditing`. On cancel, reverts controllers to current values. |
| `_handleSave(auth)` | Calls `auth.updateProfile(fullName, phone)` → shows success/error snackbar |
| `_uploadAvatar(auth)` | `ProfileService.pickAvatarImage()` → `ProfileService.uploadAvatar()` → `auth.updateProfile(..., newAvatarUrl)` |

### 5b. Edit Profile Screen (Legacy / Alternate)

**File:** `lib/screens/auth/edit_profile_screen.dart`

A simpler, standalone edit screen with a `Form` + validation. Uses mock avatar selection (hardcoded URL). This appears to be an older/alternate version — the shared profile screen has replaced it as the primary.

### 5c. Store Profile Screen

**File:** `lib/screens/seller/store_profile_screen.dart`

Seller-facing view of their own store. Not a user-profile screen — it displays store info, products, etc.

---

## 6. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Supabase Backend                       │
│                                                           │
│  auth.users ──────┐                                       │
│                   │ FK                                    │
│  profiles ◄───────┘                                       │
│     │                                                     │
│     │  RLS: public read, self-update, admin-update        │
│     │                                                     │
│     ├── avatar_url ──► Storage: avatars/{userId}/         │
│     │                                                     │
│     └── role, seller_status ──► controls UI sections      │
└──────────────────────────────────────────────────────────┘
                        ▲
                        │ SupabaseClient.from('profiles')
                        │
┌───────────────────────┴──────────────────────────────────┐
│                   Flutter App                             │
│                                                           │
│  AuthService ──► signIn / signUp / getProfile (with retry)│
│       │                                                   │
│       ▼                                                   │
│  AuthProvider ──► _currentUser, _profile (in-memory)      │
│       │           displayName, displayEmail, avatarUrl,   │
│       │           userRole, sellerStatus                  │
│       │                                                   │
│       ├── updateProfile() ──► SupabaseService.updateProfile()
│       │                                                   │
│       ▼                                                   │
│  ProfileScreen ──► reads auth.displayName, avatarUrl, etc.│
│       │                                                   │
│       ├── _uploadAvatar() ──► ProfileService.pickAvatarImage()
│       │                     ──► ProfileService.uploadAvatar()
│       │                     ──► auth.updateProfile(newAvatarUrl)
│       │                                                   │
│       ├── _handleSave() ──► auth.updateProfile(fullName, phone)
│       │                                                   │
│       └── Seller section ──► StoreService.getMyStore()
└──────────────────────────────────────────────────────────┘
```

---

## 7. Storage Bucket

**Bucket:** `avatars`
- Path: `{userId}/avatar.jpg`
- Public read access
- Upserts on re-upload (same path overwrites)
- 1000×1000 max, 85% JPEG quality

---

## 8. How Other Screens Access Profile Data

Almost every screen accesses profile data through `AuthProvider`:

```dart
final auth = context.watch<AuthProvider>();

// User ID (for queries, order creation, etc.)
final userId = auth.currentUser?['id'] ?? auth.profile?['id'];

// Display
auth.displayName    // "John Doe"
auth.displayEmail   // "john@example.com"
auth.avatarUrl      // URL or null
auth.userRole       // 'customer' | 'seller' | 'admin'
```

### Key usage patterns:

| Screen | How it uses profile |
|--------|-------------------|
| Checkout | `auth.profile?['id']` as `customerId` |
| Cart | `auth.profile?['id']` for cart operations |
| POS | `auth.profile?['id']` as seller reference |
| Order tracking | `auth.profile?['id']` for order queries |
| Notifications | `auth.currentUser?['id']` for Realtime filter |
| Address book | `auth.profile?['id']` for address queries |
| Admin screens | `orderProvider.profiles` (fetched separately) |

---

## 9. Admin Profile Operations

Admins can modify any profile through `SupabaseService`:

```dart
// Change role
await SupabaseService.instance.updateProfileRole(userId, 'customer');

// Approve seller
await SupabaseService.instance.approveSellerApplication(userId);
// Sets: role='seller', seller_status='approved'

// Reject seller
await SupabaseService.instance.rejectSellerApplication(userId);
// Sets: seller_status='rejected'
```

---

## 10. Address Book (Profile-Adjacent)

**Files:**
- `lib/screens/customer/address_book_screen.dart` — Lists saved addresses for a user
- `lib/screens/customer/add_edit_address_screen.dart` — Add/edit a single address
- `lib/providers/address_provider.dart` — State management for addresses
- `lib/services/address_service.dart` — Supabase CRUD for `customer_addresses` table

**Database:** `customer_addresses` table (migration `20260705`)
- `id`, `user_id` (FK → profiles), `label`, `recipient_name`, `phone`, `street`, `barangay`, `city`, `province`, `zip_code`, `is_default`
- RLS: users can only read/write their own addresses

**Usage:** Addresses are used at checkout (`CheckoutScreen`) for delivery orders.

---

## 11. File Inventory

| File | Purpose |
|------|---------|
| `lib/providers/auth_provider.dart` | State management for auth + profile data |
| `lib/services/auth_service.dart` | Supabase auth operations + profile creation |
| `lib/services/supabase_service.dart` | `updateProfile()`, `getProfile()`, admin ops |
| `lib/services/profile_service.dart` | Avatar pick + upload |
| `lib/services/upload_service.dart` | Generic file upload to Supabase Storage |
| `lib/screens/shared/profile_screen.dart` | Primary profile screen (inline edit) |
| `lib/screens/auth/edit_profile_screen.dart` | Legacy standalone edit screen |
| `lib/screens/customer/profile_screen.dart` | Re-exports shared profile screen |
| `supabase/schema.sql` | Database schema + RLS policies |

---

## 11. Gotchas & Important Notes

1. **Profile creation retry:** `AuthService.getProfile()` retries 5 times because the Supabase trigger that creates profiles may lag after signup. If it still fails, it manually upserts.

2. **Email is read-only:** The email field is locked in the UI and never updated after signup. It's set from `auth.users.email`.

3. **Controller sync:** The profile screen uses `_loadedProfileId` to prevent re-syncing text controllers on every rebuild. Only re-syncs when the profile ID changes.

4. **Avatar upload is two-step:** First uploads to Storage, then updates the `profiles.avatar_url` column. Both happen in `ProfileService.uploadAvatar()`.

5. **`updateProfile` returns the updated row:** The Supabase `.update().select().single()` pattern returns the full updated row, which `AuthProvider` uses to replace `_profile`.

6. **Role-based UI:** The profile screen conditionally shows the "Seller Info" section only when `auth.userRole == 'seller'`. The role is derived from `_profile['role']`.

7. **Following count:** Loaded separately via `FollowProvider`, not from the profile data itself.
