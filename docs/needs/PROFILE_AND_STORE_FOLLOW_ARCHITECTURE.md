# SoleVision — Profile Screen & Store Follow Architecture

**Version:** 1.0.0  
**Last Updated:** July 16, 2026  
**Purpose:** Detailed architecture reference for the customer profile screen and store follow/unfollow feature.

---

## Table of Contents

1. [Profile Screen Architecture](#1-profile-screen-architecture)
2. [Navigation Flow](#2-navigation-flow)
3. [State Management](#3-state-management)
4. [Features Breakdown](#4-features-breakdown)
5. [Store Follow/Unfollow Architecture](#5-store-followunfollow-architecture)
6. [Store Profile Screen](#6-store-profile-screen)
7. [Store Discovery Screen](#7-store-discovery-screen)
8. [Database Schema](#8-database-schema)
9. [Data Flow Diagrams](#9-data-flow-diagrams)
10. [Known Issues](#10-known-issues)

---

## 1. Profile Screen Architecture

### File Location

```
lib/screens/shared/profile_screen.dart
```

### Component Diagram

```
ProfileScreen (StatefulWidget)
│
├── AppBar
│   └── Title: "My Profile"
│
└── SingleChildScrollView
    │
    ├── _buildHeader(auth)
    │   ├── CircleAvatar (radius: 44)
    │   │   ├── NetworkImage (if avatar exists)
    │   │   ├── Initials text (if no avatar)
    │   │   └── CircularProgressIndicator (while uploading)
    │   ├── Camera overlay button → _uploadAvatar()
    │   ├── Name + edit toggle icon
    │   ├── Email text
    │   └── SoleBadge (role: Customer/Seller/Admin)
    │
    ├── _buildEditPanel(auth)
    │   └── AnimatedSize (collapsible)
    │       ├── Full Name TextField
    │       ├── Email (locked, grey background)
    │       ├── Phone TextField
    │       └── "Save Changes" button → _handleSave()
    │
    ├── _buildNotificationsPanel()
    │   ├── "My Orders" header + "View all" link
    │   └── SoleCard with 5 notification category icons
    │       ├── Unpaid → MyOrdersScreen(filter: 'unpaid')
    │       ├── Processing → MyOrdersScreen(filter: 'processing')
    │       ├── Shipped → MyOrdersScreen(filter: 'shipped')
    │       ├── Review → MyOrdersScreen(filter: 'review')
    │       └── Returns → MyOrdersScreen(filter: 'returns')
    │
    ├── _buildSettingsCard(auth)
    │   ├── Change Password → _sendReset()
    │   ├── Terms & Privacy → placeholder
    │   └── About SoleVision → placeholder
    │
    ├── _buildSellerSection(auth) [IF seller role]
    │   └── SoleCard with FutureBuilder
    │       ├── Store → StoreProfileScreen or CreateStoreScreen
    │       ├── Seller Status → SoleStatusChip
    │       └── Member Since → formatted date
    │
    └── _buildLogoutButton(auth)
        └── OutlinedButton → _confirmLogout()
```

### Profile Screen Features

| Feature | Implementation | Status |
|---------|---------------|--------|
| View profile (avatar, name, email, role) | `AuthProvider` state | ✅ Working |
| Edit profile (name, phone) | Collapsible panel with TextFields | ✅ Working |
| Upload avatar | `ProfileService.pickAvatarImage()` → `uploadAvatar()` | ✅ Working |
| Role badge | Color-coded SoleBadge (Customer/Seller/Admin) | ✅ Working |
| Order status shortcuts | 5-category icon row with counts | ✅ Working |
| Change password | `AuthProvider.resetPassword()` → email | ✅ Working |
| Terms & Privacy | Placeholder screen | ⚠️ Stub |
| About SoleVision | Placeholder screen | ⚠️ Stub |
| Seller section | Shows store link + status + member date | ✅ Working (sellers only) |
| Logout | Confirmation dialog → `AuthProvider.logout()` | ✅ Working |

### Profile Screen State

```dart
class _ProfileScreenState {
  // Edit state
  bool _isEditing = false;        // Toggle edit panel visibility
  bool _isSaving = false;         // Loading state for save
  bool _isUploadingAvatar = false; // Loading state for avatar upload
  String? _loadedProfileId;       // Prevent re-syncing controllers

  // Controllers
  TextEditingController _nameController;
  TextEditingController _phoneController;

  // Seller state
  Future<Map<String, dynamic>?>? _sellerStoreFuture; // Lazy-loaded store data
}
```

### Key Methods

| Method | Purpose | Side Effects |
|--------|---------|-------------|
| `_syncControllers(auth)` | Sync TextEditingControllers with auth profile | Prevents re-sync with same profile ID |
| `_toggleEdit(auth)` | Toggle edit panel / revert on cancel | Sets `_isEditing` |
| `_handleSave(auth)` | Save profile changes | Calls `auth.updateProfile()`, shows snackbar |
| `_uploadAvatar(auth)` | Pick image + upload + update profile | Shows loading, uploads to Supabase Storage |
| `_sendReset(auth)` | Send password reset email | Calls `auth.resetPassword()` |
| `_confirmLogout(auth)` | Show confirmation dialog | Calls `auth.logout()` on confirm |

---

## 2. Navigation Flow

### From Profile Screen

```
ProfileScreen
│
├── "View all" (My Orders) → MyOrdersScreen
│   └── Order card → OrderTrackingScreen
│
├── Unpaid icon → MyOrdersScreen(initialFilter: 'unpaid')
├── Processing icon → MyOrdersScreen(initialFilter: 'processing')
├── Shipped icon → MyOrdersScreen(initialFilter: 'shipped')
├── Review icon → MyOrdersScreen(initialFilter: 'review')
├── Returns icon → MyOrdersScreen(initialFilter: 'returns')
│
├── Change Password → sends reset email
├── Terms & Privacy → placeholder
├── About SoleVision → placeholder
│
├── Store (seller only) → StoreProfileScreen or CreateStoreScreen
│
└── Log Out → confirmation → signs out
```

### To Profile Screen (Entry Points)

| Entry Point | Tab/Index |
|-------------|-----------|
| CustomerShell Tab 3 (Profile icon) | Bottom nav |
| SellerShell Tab 4 (Profile icon) | Bottom nav |
| AdminShell Tab 4 (Profile icon) | Bottom nav |

**Note:** The profile screen is **shared** across all three roles (Customer, Seller, Admin). It conditionally shows the seller section based on `auth.userRole`.

---

## 3. State Management

### Providers Used

| Provider | Data Used | How |
|----------|-----------|-----|
| `AuthProvider` | `displayName`, `displayEmail`, `displayPhone`, `avatarUrl`, `userRole`, `sellerStatus`, `profile` | `context.watch<AuthProvider>()` |
| `NotificationProvider` | `unreadCounts` | `context.watch<NotificationProvider>()` |

### Data Source: AuthProvider

```dart
class AuthProvider {
  // Profile data
  Map<String, dynamic>? get profile;     // Raw profile from Supabase
  String get displayName;                // profile['full_name'] ?? 'User'
  String get displayEmail;               // profile['email'] ?? ''
  String get displayPhone;               // profile['phone'] ?? ''
  String? get avatarUrl;                 // profile['avatar_url']
  String get userRole;                   // profile['role'] ?? 'customer'
  String get sellerStatus;               // profile['seller_status'] ?? 'none'

  // Methods
  Future<bool> updateProfile({String? fullName, String? phone, String? newAvatarUrl});
  Future<bool> resetPassword(String email);
  Future<void> logout();
}
```

### Data Source: NotificationProvider

```dart
class NotificationProvider {
  // Order status counts
  Map<NotificationCategory, int> get unreadCounts;
  // Returns: {unpaid: 2, processing: 1, shipped: 0, review: 0, returns: 0}
}
```

---

## 4. Features Breakdown

### 4.1 Profile Header

```
┌─────────────────────────────────────┐
│                                     │
│         ┌──────────────┐            │
│         │   👤 Avatar  │            │
│         │  (or initials)│           │
│         └──────┬───────┘            │
│                │ 📷 (camera btn)    │
│                                     │
│       John Doe  ✏️ (edit toggle)    │
│       john@example.com              │
│       ┌──────────┐                  │
│       │ Customer │ (role badge)     │
│       └──────────┘                  │
│                                     │
└─────────────────────────────────────┘
```

**Avatar Logic:**
1. If `avatarUrl` exists → show `NetworkImage`
2. If uploading → show `CircularProgressIndicator`
3. If no avatar → show initials (first letter of first + last name)

### 4.2 Edit Panel (Collapsible)

```
┌─────────────────────────────────────┐
│  FULL NAME                          │
│  ┌─────────────────────────────────┐│
│  │ John Doe                        ││
│  └─────────────────────────────────┘│
│                                     │
│  EMAIL (locked)                     │
│  ┌─────────────────────────────────┐│
│  │ john@example.com          🔒    ││
│  └─────────────────────────────────┘│
│                                     │
│  PHONE NUMBER                       │
│  ┌─────────────────────────────────┐│
│  │ 09XX-XXX-XXXX                   ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │        Save Changes             ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

**Animation:** `AnimatedSize` with 220ms ease-in-out for smooth expand/collapse.

### 4.3 Order Status Shortcuts

```
┌─────────────────────────────────────┐
│  My Orders              View all →  │
│  ┌─────────────────────────────────┐│
│  │  💳    📦    🚚    💬    📋   ││
│  │ Unpaid Proc. Ship. Review Ret.  ││
│  │  (2)   (1)   (0)   (0)   (0)   ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

Each icon is tappable and navigates to `MyOrdersScreen` with the appropriate filter.

### 4.4 Settings Card

```
┌─────────────────────────────────────┐
│  🔒 Change Password           →    │
│  ─────────────────────────────────  │
│  📄 Terms & Privacy           →    │
│  ─────────────────────────────────  │
│  ℹ️ About SoleVision          →    │
└─────────────────────────────────────┘
```

### 4.5 Seller Section (Conditional)

```
┌─────────────────────────────────────┐
│  SELLER INFO                        │
│  ┌─────────────────────────────────┐│
│  │ Store    Valladolid Leather  →  ││
│  │ ─────────────────────────────── ││
│  │ Status   [Approved]             ││
│  │ ─────────────────────────────── ││
│  │ Member   Jul 2026               ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

Only shown when `auth.userRole == 'seller'`. Uses `FutureBuilder` to lazy-load store data.

### 4.6 Logout Button

```
┌─────────────────────────────────────┐
│  🚪 Log Out                         │
│  (outlined red button)              │
└─────────────────────────────────────┘
```

Shows confirmation dialog before signing out.

---

## 5. Store Follow/Unfollow Architecture

### Overview

The follow feature allows customers to follow/unfollow artisan stores. Followed stores appear in the customer's feed and notifications.

### Database Table: `store_follows`

```sql
CREATE TABLE store_follows (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, store_id)
);
```

**RLS Policies:**
- Customers can INSERT/DELETE their own follows (`auth.uid() = user_id`)
- Everyone can SELECT follows (to show follower counts)

### Service Layer: StoreService

**File:** `lib/services/store_service.dart`

| Method | Purpose | Returns |
|--------|---------|---------|
| `followStore(storeId)` | Insert follow record | `Future<void>` |
| `unfollowStore(storeId)` | Delete follow record | `Future<void>` |
| `isFollowingAsync(storeId)` | Check if current user follows store | `Future<bool>` |
| `toggleFollow(storeId)` | Auto-detect and toggle follow state | `void` (fire-and-forget) |
| `isFollowing(storeId)` | **STUB** — always returns `false` | `bool` |

### Implementation Details

#### `followStore(storeId)`
```dart
Future<void> followStore(String storeId) async {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be logged in to follow a store.');
  
  await _client.from('store_follows').upsert({
    'user_id': userId,
    'store_id': storeId,
  });
}
```

#### `unfollowStore(storeId)`
```dart
Future<void> unfollowStore(String storeId) async {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be logged in to unfollow a store.');
  
  await _client
      .from('store_follows')
      .delete()
      .eq('user_id', userId)
      .eq('store_id', storeId);
}
```

#### `isFollowingAsync(storeId)`
```dart
Future<bool> isFollowingAsync(String storeId) async {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) return false;
  
  final data = await _client
      .from('store_follows')
      .select('store_id')
      .eq('user_id', userId)
      .eq('store_id', storeId)
      .maybeSingle();
  
  return data != null;
}
```

#### `toggleFollow(storeId)`
```dart
void toggleFollow(String storeId) {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) return;
  
  isFollowingAsync(storeId).then((following) {
    if (following) {
      unfollowStore(storeId);
    } else {
      followStore(storeId);
    }
  });
}
```

### ⚠️ Known Issues

| Issue | Details |
|-------|---------|
| `isFollowing()` is a stub | Always returns `false`. Only `isFollowingAsync()` works. |
| `toggleFollow()` is fire-and-forget | No error handling, no UI feedback on failure |
| Optimistic UI without rollback | `store_profile_screen.dart` toggles `_isFollowing` immediately but doesn't rollback on API failure |

---

## 6. Store Profile Screen

### File Location

```
lib/screens/store/store_profile_screen.dart
```

### Component Diagram

```
StoreProfileScreen (StatefulWidget)
│
├── SliverAppBar (expandedHeight: 220, pinned)
│   ├── FlexibleSpaceBar
│   │   ├── Banner image (or gradient fallback)
│   │   ├── Dark gradient overlay
│   │   ├── Stitch overlay (decorative)
│   │   └── Content:
│   │       ├── Tagline
│   │       ├── Stats row (products, rating, location)
│   │       ├── Message Seller button → _messageSeller()
│   │       └── Follow button → toggleFollow()
│   └── Actions: [CartIconButton]
│
├── "Shop by Collection" horizontal scroll
│   └── Category cards → CollectionScreen
│
├── "Featured Picks" PageView
│   └── Featured products carousel → ProductDetailScreen
│
├── "Our Story" section
│   └── Story entries from story_entries table
│
├── "All Products" grid
│   ├── Sort chips (Newest, Price Low-High, Price High-Low)
│   └── MasonryGridView of SoleProductCard
│
└── RefreshIndicator (pull-to-refresh)
```

### Follow Button Implementation

**Location:** Inside `SliverAppBar` → `FlexibleSpaceBar` → `Content` → `Row`

```dart
// Follow button
GestureDetector(
  onTap: () {
    _storeService.toggleFollow(widget.storeId);  // API call (fire-and-forget)
    setState(() {
      _isFollowing = !_isFollowing;              // Optimistic UI update
    });
  },
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: _isFollowing ? AppConstants.surfaceLight : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppConstants.surfaceLight, width: 1.5),
    ),
    child: Text(
      _isFollowing ? 'Following ✓' : 'Follow',
      style: AppConstants.bodyStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: _isFollowing ? store.color : AppConstants.surfaceLight,
      ),
    ),
  ),
),
```

### Follow Button States

| State | Background | Border | Text | Text Color |
|-------|-----------|--------|------|------------|
| Not Following | Transparent | White 1.5px | "Follow" | White |
| Following | White | White 1.5px | "Following ✓" | Store brand color |

### Data Loading Flow

```
_loadData()
  │
  ├── ProductProvider.loadProducts()     // Refresh all products
  ├── StoreService.fetchStoreById()      // Get store details
  ├── StoreService.getStoryEntriesForStore() // Get story entries
  └── StoreService.isFollowingAsync()    // Check follow status
       │
       └── setState() with all data
```

### Message Seller Button

```dart
Future<void> _messageSeller() async {
  final customerId = Supabase.instance.client.auth.currentUser?.id;
  if (customerId == null) return;

  // Get or create conversation
  final conversation = await MessageService.instance.getOrCreateConversation(
    storeId: widget.storeId,
    customerId: customerId,
  );

  if (!mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatView(
        conversationId: conversation.id,
        viewerRole: 'customer',
        otherPartyName: _store?.name ?? 'Store',
      ),
    ),
  );
}
```

---

## 7. Store Discovery Screen

### File Location

```
lib/screens/store/store_screen.dart
```

### Component Diagram

```
StoreScreen (StatefulWidget)
│
├── AppBar: "Stores" + CartIconButton
│
└── SingleChildScrollView
    ├── StoreHeroCarousel
    │   └── PageView of store cards (viewportFraction: 0.85)
    │
    ├── StoreFocusedInfo
    │   └── Info strip for currently focused store
    │
    └── CrossStoreProductRow
        └── Products from focused store
```

### Store Discovery Flow

```
StoreScreen
  │
  ├── _loadStores()
  │   └── StoreService.fetchAllStores()
  │       └── SELECT * FROM stores WHERE is_active = true
  │
  ├── _onStoreChanged(index)
  │   └── Updates _focusedIndex
  │       └── Products filter to focused store
  │
  └── Store card tap → StoreProfileScreen(storeId: store.id)
```

---

## 8. Database Schema

### `store_follows` Table

```sql
CREATE TABLE IF NOT EXISTS public.store_follows (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, store_id)
);
```

### RLS Policies

```sql
-- Customers can follow/unfollow stores
CREATE POLICY "Customers can follow stores"
  ON public.store_follows FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Customers can unfollow stores"
  ON public.store_follows FOR DELETE
  USING (auth.uid() = user_id);

-- Everyone can see follow counts
CREATE POLICY "Anyone can view follows"
  ON public.store_follows FOR SELECT
  USING (true);
```

### Useful Queries

```sql
-- Check if user follows a store
SELECT EXISTS (
  SELECT 1 FROM store_follows
  WHERE user_id = 'USER_ID' AND store_id = 'STORE_ID'
) AS is_following;

-- Get follower count for a store
SELECT COUNT(*) AS follower_count
FROM store_follows
WHERE store_id = 'STORE_ID';

-- Get all stores a user follows
SELECT s.*
FROM stores s
INNER JOIN store_follows sf ON s.id = sf.store_id
WHERE sf.user_id = 'USER_ID'
ORDER BY sf.created_at DESC;

-- Get stores with follower counts (for discovery)
SELECT s.*, COUNT(sf.user_id) AS follower_count
FROM stores s
LEFT JOIN store_follows sf ON s.id = sf.store_id
WHERE s.is_active = true
GROUP BY s.id
ORDER BY follower_count DESC, s.created_at DESC;
```

---

## 9. Data Flow Diagrams

### Follow Store Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    FOLLOW STORE                              │
│                                                             │
│  Customer taps "Follow" button on StoreProfileScreen        │
│       │                                                     │
│       ├── 1. Optimistic UI update                          │
│       │    setState(() => _isFollowing = true)              │
│       │    Button changes: "Follow" → "Following ✓"         │
│       │                                                     │
│       └── 2. API call (fire-and-forget)                     │
│            StoreService.toggleFollow(storeId)               │
│                │                                            │
│                ├── isFollowingAsync(storeId)                │
│                │    └── SELECT FROM store_follows           │
│                │                                            │
│                └── If not following:                        │
│                     followStore(storeId)                    │
│                         └── INSERT INTO store_follows       │
│                             (user_id, store_id)             │
│                                                             │
│  Result: UI updates immediately, API syncs in background    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Unfollow Store Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    UNFOLLOW STORE                            │
│                                                             │
│  Customer taps "Following ✓" button                         │
│       │                                                     │
│       ├── 1. Optimistic UI update                          │
│       │    setState(() => _isFollowing = false)             │
│       │    Button changes: "Following ✓" → "Follow"         │
│       │                                                     │
│       └── 2. API call (fire-and-forget)                     │
│            StoreService.toggleFollow(storeId)               │
│                │                                            │
│                ├── isFollowingAsync(storeId)                │
│                │    └── SELECT FROM store_follows           │
│                │                                            │
│                └── If following:                            │
│                     unfollowStore(storeId)                  │
│                         └── DELETE FROM store_follows       │
│                             WHERE user_id = ?               │
│                             AND store_id = ?                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Profile Edit Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    EDIT PROFILE                              │
│                                                             │
│  User taps edit icon (✏️)                                   │
│       │                                                     │
│       └── _toggleEdit(auth)                                │
│            └── setState(() => _isEditing = true)            │
│                 └── Edit panel expands (AnimatedSize)        │
│                                                             │
│  User modifies name/phone                                   │
│       │                                                     │
│  User taps "Save Changes"                                   │
│       │                                                     │
│       └── _handleSave(auth)                                │
│            ├── setState(() => _isSaving = true)             │
│            ├── auth.updateProfile(                          │
│            │     fullName: _nameController.text,            │
│            │     phone: _phoneController.text,              │
│            │   )                                            │
│            │    └── Supabase UPDATE profiles SET ...        │
│            │                                                 │
│            ├── setState(() => _isSaving = false)            │
│            ├── setState(() => _isEditing = false)           │
│            └── SnackBar: "Profile updated"                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Avatar Upload Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    UPLOAD AVATAR                             │
│                                                             │
│  User taps camera icon on avatar                            │
│       │                                                     │
│       └── _uploadAvatar(auth)                              │
│            │                                                │
│            ├── ProfileService.pickAvatarImage()             │
│            │    └── ImagePicker.pickImage(source: gallery)  │
│            │                                                │
│            ├── setState(() => _isUploadingAvatar = true)    │
│            │                                                │
│            ├── ProfileService.uploadAvatar(                 │
│            │     userId: userId,                            │
│            │     filePath: picked.path,                     │
│            │   )                                            │
│            │    └── Supabase Storage upload                 │
│            │        bucket: 'avatars'                       │
│            │        path: '{userId}/avatar.jpg'             │
│            │    └── Returns public URL                      │
│            │                                                │
│            ├── auth.updateProfile(newAvatarUrl: avatarUrl)  │
│            │    └── Supabase UPDATE profiles SET avatar_url │
│            │                                                │
│            ├── setState(() => _isUploadingAvatar = false)   │
│            └── SnackBar: "Profile photo updated"            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 10. Known Issues

### Profile Screen

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | "Terms & Privacy" is a placeholder | Low | Shows "Coming soon" |
| 2 | "About SoleVision" is a placeholder | Low | Shows "Coming soon" |
| 3 | No email change functionality | Low | Email field is locked |
| 4 | No delete account option | Medium | Common user expectation |
| 5 | No notification preferences | Medium | Can't opt in/out of specific notifications |

### Store Follow

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | `isFollowing()` always returns `false` | Medium | Synchronous stub; only `isFollowingAsync()` works |
| 2 | `toggleFollow()` has no error handling | Medium | Fire-and-forget with no rollback on failure |
| 3 | No follower count display | Low | Store profile doesn't show how many followers |
| 4 | No "Following" filter in store discovery | Low | Can't filter to only followed stores |
| 5 | Optimistic UI without rollback | Medium | If API fails, UI stays in wrong state |

### Suggested Fixes

#### Fix 1: Add error handling to `toggleFollow()`

```dart
// Current (no error handling):
void toggleFollow(String storeId) {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) return;
  isFollowingAsync(storeId).then((following) {
    if (following) {
      unfollowStore(storeId);
    } else {
      followStore(storeId);
    }
  });
}

// Fixed (with error handling + callback):
Future<void> toggleFollow(String storeId, {VoidCallback? onError}) async {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) {
    onError?.call();
    return;
  }
  try {
    final following = await isFollowingAsync(storeId);
    if (following) {
      await unfollowStore(storeId);
    } else {
      await followStore(storeId);
    }
  } catch (e) {
    onError?.call();
  }
}
```

#### Fix 2: Add rollback to store profile screen

```dart
GestureDetector(
  onTap: () async {
    final previousState = _isFollowing;
    setState(() => _isFollowing = !_isFollowing); // Optimistic
    
    try {
      await _storeService.toggleFollow(widget.storeId);
    } catch (e) {
      // Rollback on failure
      if (mounted) {
        setState(() => _isFollowing = previousState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update follow status')),
        );
      }
    }
  },
  // ...
)
```

#### Fix 3: Add follower count to store profile

```dart
// In _loadData():
final followerCount = await _client
    .from('store_follows')
    .select('user_id')
    .eq('store_id', widget.storeId)
    .count();

setState(() {
  _followerCount = followerCount;
});
```

---

*SoleVision Profile & Store Follow Architecture v1.0.0 — July 16, 2026*
