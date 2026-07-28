# Seller Profile Architecture

> **Purpose:** Enough context for an AI agent to understand the seller's profile
> and store management system — data models, services, screens, navigation flow,
> and database schema.

---

## 1. High-Level Overview

The seller profile module handles two distinct layers:

1. **User Profile** — the seller's personal account (name, email, phone, avatar,
   role). Managed via `AuthProvider` and `ProfileService`.
2. **Store Profile** — the seller's artisan shop (name, tagline, location, brand
   color, banner/logo, open/closed status). Managed via `StoreService`.

A seller can own **exactly one store** (enforced by `StoreService.getMyStore()`
checking for an existing record before allowing creation). If a seller has no
store yet, the app prompts them to create one via `CreateStoreScreen`.

---

## 2. File Map

```
lib/
├── models/
│   ├── store.dart                        # Store data model
│   ├── followed_store.dart               # FollowedStore model (for customers following stores)
│   └── address_model.dart                # Address model (customer addresses, not seller addresses)
│
├── services/
│   ├── profile_service.dart              # Avatar upload (pick + upload to Supabase Storage)
│   ├── store_service.dart                # CRUD for stores, follow/unfollow, store assets
│   └── auth_service.dart                 # Supabase Auth wrapper (signup, login, session)
│
├── providers/
│   └── auth_provider.dart                # Auth state, profile data, updateProfile(), sellerStatus
│
├── screens/
│   ├── shared/
│   │   ├── profile_screen.dart           # Shared "My Profile" screen (both sellers & customers)
│   │   └── following_list_dialog.dart    # Dialog showing followed stores
│   │
│   ├── seller/
│   │   ├── store_profile_screen.dart     # Store profile view (banner, logo, stats, edit button)
│   │   ├── edit_store_screen.dart        # Edit store form (name, tagline, location, color, images)
│   │   ├── create_store_screen.dart      # First-time store setup (same form as edit, no pre-fill)
│   │   └── seller_more_screen.dart       # "More" menu (inventory, custom orders, reports, settings)
│   │
│   └── auth/
│       └── edit_profile_screen.dart      # Legacy profile edit screen (avatar + name only)
```

---

## 3. Data Models

### 3.1 `Store` (lib/models/store.dart)

```dart
class Store {
  final String id;           // UUID, primary key
  final String name;         // Store name (e.g. "Carcar Footwear Co.")
  final String? tagline;     // Optional tagline
  final String location;     // City/municipality string
  final String brandColor;   // Hex string, e.g. '#8B5A2B'
  final String? bannerUrl;   // Supabase Storage URL
  final String? logoUrl;     // Supabase Storage URL
  final double rating;       // Average rating (default 5.0)
  final bool isOpen;         // Whether the store accepts orders
  final bool isActive;       // Whether the store is visible to customers
  final String? ownerId;     // FK to profiles.id
  final DateTime createdAt;
}
```

**Derived properties:**
- `color` → parsed `Color` from `brandColor` via `AppConstants.parseBrandColor()`
- `initials` → first letters of first two words in store name
- `cardGradient` → gradient using `color` for card backgrounds

### 3.2 `profiles` table (Supabase)

```sql
CREATE TABLE profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  full_name       TEXT NOT NULL,
  email           TEXT NOT NULL UNIQUE,
  phone           TEXT,
  role            TEXT NOT NULL DEFAULT 'customer'  -- 'customer' | 'seller' | 'admin'
  seller_status   TEXT NOT NULL DEFAULT 'pending'   -- 'none' | 'pending' | 'approved' | 'rejected'
  avatar_url      TEXT,
  suspended       BOOLEAN DEFAULT false,
  rejection_reason TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

### 3.3 `stores` table (Supabase)

```sql
CREATE TABLE stores (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  tagline     TEXT,
  location    TEXT NOT NULL,
  brand_color TEXT DEFAULT '#8B5A2B',
  banner_url  TEXT,
  logo_url    TEXT,
  rating      NUMERIC(2,1) DEFAULT 5.0,
  is_open     BOOLEAN DEFAULT true,
  is_active   BOOLEAN DEFAULT true,
  owner_id    UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ DEFAULT now()
);
```

**RLS policies:**
- `stores` are viewable by everyone (public storefront)
- Only the store owner (`owner_id = auth.uid()`) can insert/update
- Admins can manage all stores

---

## 4. Services

### 4.1 `ProfileService` (lib/services/profile_service.dart)

Singleton (`ProfileService.instance`). Handles **avatar management only**.

| Method | Description |
|--------|-------------|
| `pickAvatarImage()` | Opens image picker (gallery, 1000×1000, 85% quality) |
| `uploadAvatar({userId, filePath})` | Uploads to `avatars` bucket as `{userId}/avatar.jpg` (upsert), updates `profiles.avatar_url` with cache-busted URL, returns public URL |

**Storage bucket:** `avatars` (public read, per-user folder)

### 4.2 `StoreService` (lib/services/store_service.dart)

Singleton (`StoreService.instance`). Handles all store CRUD + follow system.

#### Seller Store Methods

| Method | Description |
|--------|-------------|
| `getMyStore()` | Fetches the current seller's store (by `owner_id`). Returns `null` if no store exists. |
| `createStore({name, tagline, location, brandColor, logoImage, bannerImage})` | Creates a new store. **Enforces one store per seller** — throws if one exists. Uploads optional logo/banner to `store-assets` bucket. |
| `updateStoreSeller({storeId, name, tagline, location, brandColor, isOpen, newLogoImage, newBannerImage, removeLogo, removeBanner})` | Full update of store fields. Handles image upload/removal. |
| `toggleStoreOpen(storeId, isOpen)` | Toggles the `is_open` flag. |

#### Customer-Facing Store Methods

| Method | Description |
|--------|-------------|
| `fetchAllStores()` | All active stores, ordered by creation date |
| `fetchStoreById(storeId)` | Single store by ID |
| `followStore(storeId)` / `unfollowStore(storeId)` | Upsert/delete on `store_follows` |
| `toggleFollow(storeId)` | Idempotent toggle |
| `isFollowingAsync(storeId)` | Check follow status |
| `getFollowedStores(userId)` | Full list with store details + follower counts (uses join query with fallback) |
| `getFollowerCounts(storeIds)` | Batched follower counts for multiple stores |
| `getFollowingCount(userId)` | Total stores a user follows |
| `getFollowerCount(storeId)` | Follower count for a single store |

**Storage bucket:** `store-assets` (public read, path: `{ownerId}/{storeId}/logo.jpg` or `banner.jpg`)

### 4.3 `AuthProvider` (lib/providers/auth_provider.dart)

Manages authentication state and profile data. Relevant to seller profile:

| Getter/Method | Description |
|---------------|-------------|
| `userRole` | `'customer'`, `'seller'`, or `'admin'` |
| `sellerStatus` | `'none'`, `'pending'`, `'approved'`, or `'rejected'` |
| `displayName` | From `profiles.full_name` |
| `displayEmail` | From `profiles.email` or Supabase auth email |
| `displayPhone` | From `profiles.phone` |
| `avatarUrl` | From `profiles.avatar_url` |
| `updateProfile({fullName, phone, newAvatarUrl})` | Updates `profiles` table |
| `resetPassword(email)` | Sends Supabase password reset email |

---

## 5. Screens & Navigation Flow

### 5.1 Profile Screen Flow (Shared)

```
Bottom Nav "Profile" tab
  └── ProfileScreen (lib/screens/shared/profile_screen.dart)
       ├── Header: Avatar (with camera upload), Name, Email, Role Badge
       ├── Edit Panel (animated expand/collapse): Full Name, Email (locked), Phone, Save
       ├── Notifications Panel: Order status categories (Unpaid, Processing, Shipped, etc.)
       ├── Settings Card: Change Password, Terms, Help, About
       ├── Seller Section (if role == 'seller'):
       │    ├── Store → StoreProfileScreen (if store exists) or CreateStoreScreen (if not)
       │    ├── Seller Status → SoleStatusChip
       │    └── Member Since → formatted date
       └── Logout Button
```

### 5.2 Store Profile Flow (Seller)

```
ProfileScreen → "Store" tap
  └── StoreProfileScreen (lib/screens/seller/store_profile_screen.dart)
       ├── Banner (full-width, 200px, brand-colored gradient fallback)
       ├── Logo (64×64 circle, overlapping banner bottom-left)
       ├── Store Name + Open/Closed status indicator
       ├── Info Card: Tagline (italic), Location, Brand Color swatch, Open/Closed toggle
       ├── Stats Row: Products count, Orders count, Rating
       └── "Edit Store" button → EditStoreScreen
```

### 5.3 Store Creation/Edit Flow

```
CreateStoreScreen (first-time setup)
  └── Form: Banner & Logo upload → Store Name (*) → Tagline → Location (*) → Brand Color picker → "Create My Store"

EditStoreScreen (edit existing)
  └── Same form layout, pre-filled with existing data
       └── Additional: Remove banner/logo buttons, Open/Closed toggle
```

**Brand Color Options (preset):**
| Color | Hex | Name |
|-------|-----|------|
| 🟤 | `#8B5A2B` | Burnished Clay (default) |
| 🟫 | `#3B2314` | Carob Dark |
| 🟢 | `#4ECDC4` | Celadon Teal |
| 🟡 | `#E8A020` | Amber |
| 🔴 | `#D64545` | Crimson |
| 🟢 | `#2C5F2E` | Forest Green |

---

## 6. Image Upload Architecture

All images are stored in Supabase Storage (public read access):

| Bucket | Path Pattern | Used For |
|--------|-------------|----------|
| `avatars` | `{userId}/avatar.jpg` (upsert) | User profile photos |
| `store-assets` | `{ownerId}/{storeId}/logo.jpg` | Store logos |
| `store-assets` | `{ownerId}/{storeId}/banner.jpg` | Store banners |
| `product-images` | Various | Product photos |

**Cache-busting:** Profile avatars append `?t={timestamp}` to the URL after upload to force `Image` widgets to reload (since the storage path is always the same for upserted files).

**Upload flow:**
1. `ImagePicker.pickImage()` → local file
2. `UploadService.uploadFile()` or `Supabase.storage.from().uploadBinary()` → public URL
3. Update corresponding DB column (`avatar_url`, `logo_url`, or `banner_url`)

---

## 7. Store Follow System

Customers can follow/unfollow stores. The `store_follows` table is a join table:

```sql
CREATE TABLE store_follows (
  user_id   UUID REFERENCES profiles(id) ON DELETE CASCADE,
  store_id  UUID REFERENCES stores(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, store_id)
);
```

**RLS:** Users can only see/manage their own follows.

**Key methods in StoreService:**
- `followStore()` / `unfollowStore()` — direct DB operations
- `toggleFollow()` — idempotent (checks current state first)
- `getFollowedStores()` — returns `List<FollowedStore>` with store details + follower counts (uses join query with separate-query fallback if FK is missing)

---

## 8. Visual Language Constants

The seller profile screens use these shared constants (from `AppConstants`):

| Constant | Value | Used For |
|----------|-------|----------|
| `AppConstants.primary` | Brown | Icons, buttons, accents |
| `AppConstants.secondary` | Dark brown | Text, app bars |
| `AppConstants.sellerSurface` | Light beige | Seller screen backgrounds |
| `AppConstants.sellerCardBg` | White | Card backgrounds in seller screens |
| `AppConstants.success` | Green | Open status, success toasts |
| `AppConstants.error` | Red | Closed status, error toasts |
| `AppConstants.warmShadow` | Subtle brown shadow | Card elevation |
| `AppConstants.cardRadius` | Rounded corners | All card containers |
| `AppConstants.bodyStyle()` | Font style | Body text throughout |

---

## 9. Key Relationships Diagram

```
auth.users (Supabase Auth)
    │
    │ 1:1
    ▼
profiles (id = auth.users.id)
    │
    ├── role: 'customer' | 'seller' | 'admin'
    ├── seller_status: 'none' | 'pending' | 'approved' | 'rejected'
    │
    │ 1:1 (owner_id → profiles.id)
    ▼
stores
    │
    ├── store_follows ← customers follow stores
    ├── products ← seller's products (store_id → stores.id)
    ├── orders ← customer orders for this store
    ├── sales_transactions ← POS sales
    ├── story_entries ← workshop stories
    ├── customization_requests ← custom order requests
    └── reviews ← store-level reviews
```

---

## 10. RLS (Row Level Security) Summary

| Table | Who Can Read | Who Can Write |
|-------|-------------|---------------|
| `profiles` | Everyone (public) | Owner, Admins |
| `stores` | Everyone (public) | Owner, Admins |
| `store_follows` | Own follows only | Own follows only |
| `products` | Everyone | Sellers/Admins |
| `orders` | Customer (own), Seller (own store), Admin | Customer (insert), Seller/Admin (update status) |
| `sales_transactions` | Seller (own store), Admin | Seller (own store) |

---

## 11. Known Patterns & Conventions

1. **Singleton services** — `ProfileService.instance`, `StoreService.instance`, `ProductService.instance`
2. **No dedicated provider for stores** — `StoreService` is called directly from screens (no `StoreProvider` exists)
3. **Store data passed as `Map<String, dynamic>`** — screens receive store data as raw maps, not `Store` model instances (the `Store` model is only used by `fetchAllStores()` / `fetchStoreById()` for customer-facing screens)
4. **One store per seller** — enforced in `createStore()` with an `getMyStore()` guard
5. **Brand color** — hex string stored in DB, parsed to Flutter `Color` via `AppConstants.parseBrandColor()`
6. **Image handling** — gallery picker only (no camera), 85% JPEG quality, max 1920×1080 for banners, 512×512 for logos
