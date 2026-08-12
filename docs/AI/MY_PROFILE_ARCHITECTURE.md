# My Profile — Architecture Reference

> **Purpose:** Give AI agents a working mental model of the customer/seller **My Profile** screen: state, sections, flows, and gotchas. Not exhaustive — read the files for detail.
> **Last updated:** August 5, 2026

---

## 1. Overview

`ProfileScreen` is the **4th tab** of all three shells (`CustomerShell`, `SellerShell`, `AdminShell`) — it is role-aware and renders different content depending on `auth.userRole`.

```
CustomerShell / SellerShell / AdminShell
  └─ IndexedStack → ProfileScreen (shared/profile_screen.dart)
        ├─ Header: avatar + name + email + role badge (+ "Following" stat for non-sellers)
        ├─ Collapsible edit panel (name/phone)
        ├─ [seller only] Seller section: store card (open/closed toggle), seller status, member since
        ├─ [non-seller] "My Orders" notification panel (5 category shortcuts w/ badge counts)
        ├─ Settings card: Foot size, Change Password, Terms, Help, What's New, About
        └─ Log Out button
```

**Key facts:**
- **One screen, three roles.** `lib/screens/customer/profile_screen.dart` is just `export '../shared/profile_screen.dart';` — everything lives in `lib/screens/shared/profile_screen.dart`.
- **No separate profile state.** Profile data lives in `AuthProvider` (a `ChangeNotifier`), not a dedicated provider. The screen is a consumer of it.
- **Inline editing** (expand/collapse panel), NOT a separate edit screen. `lib/screens/auth/edit_profile_screen.dart` (`EditProfileScreen`) is **dead code** — defined, never instantiated anywhere.

---

## 2. File Map

| Layer | File | Role |
|-------|------|------|
| Screen | `lib/screens/shared/profile_screen.dart` | The whole screen (1120 lines, all sections inline) |
| Shim | `lib/screens/customer/profile_screen.dart` | `export '../shared/profile_screen.dart';` |
| State | `lib/providers/auth_provider.dart` | `profile`, `currentUser`, `userRole`, `sellerStatus`, `updateProfile()`, `logout()` |
| State | `lib/providers/order_provider.dart` | `myOrdersCounts` → My Orders panel badges (real per-tab order counts) |
| State | `lib/providers/follow_provider.dart` | `followingCount` → Following stat |
| State | `lib/providers/update_provider.dart` | `installedVersion`, `hasUnviewedUpdate` → What's New dot |
| Service | `lib/services/profile_service.dart` | Avatar pick + upload (storage bucket `avatars`) + `profiles.avatar_url` update |
| Service | `lib/services/supabase_service.dart` | `getProfile()`, `updateProfile()`, `resetPassword()`, `signOut()`, auth |
| Service | `lib/services/auth_service.dart` | Low-level auth (signIn/signUp/signOut via Supabase) |
| Service | `lib/services/store_service.dart` | `getMyStore()`, `toggleStoreOpen()` (seller section) |
| Widgets | `lib/widgets/sole_badge.dart`, `sole_card.dart`, `sole_status_chip.dart`, `sole_switch.dart` | Styling primitives |
| Shells | `customer_shell.dart:25`, `seller_shell.dart:31`, `admin_shell.dart:25` | Tab placement |
| DB | `supabase/schema.sql:18-66` | `profiles` table + RLS |

---

## 3. State Layer — AuthProvider (`lib/providers/auth_provider.dart`)

### What it holds
- `_currentUser` (auth user map: id/email), `_profile` (row from `profiles` table) — set on login/signup/session restore.
- Getters the screen uses: `userRole` (`profiles.role`, default `customer`), `sellerStatus`, `displayName`, `displayEmail`, `displayPhone`, `avatarUrl`.
- `onLoginHook` / `onLogoutHook` — set by app root (`main.dart`); fires side effects (e.g. refreshing dependent providers) on login/logout.

### Methods used by the screen
| Method | Behavior |
|--------|----------|
| `updateProfile({fullName, phone, newAvatarUrl})` | Calls `SupabaseService.updateProfile()` (UPDATE `profiles` SET `full_name`, `phone`, `avatar_url`) then replaces `_profile` with the returned row. Returns `bool`. |
| `resetPassword(email)` | `auth.resetPasswordForEmail()` — the "Change Password" action just sends a reset email. |
| `logout()` | Clears all state **first**, then `signOut()` + `BiometricService.clearCredentials()` (best-effort). |

### Providers consumed inline by ProfileScreen (context.watch)
- `OrderProvider.myOrdersCounts` — per-tab **real order counts** computed from the customer's loaded orders with the same predicates as the My Orders tabs (`order_provider.dart` → `matchesMyOrdersFilter` / `computeMyOrdersCounts`), so badges always match the tabs. A one-shot `loadMyOrders()` is triggered from `initState` if orders haven't been fetched yet.
- `FollowProvider.followingCount` / `isLoaded`.
- `UpdateProvider.installedVersion` / `hasUnviewedUpdate`.

---

## 4. Screen Sections (`profile_screen.dart`)

| Section | Method | Details |
|---------|--------|---------|
| Header | `_buildHeader` :317 | CircleAvatar (network image or initials), camera overlay → `_uploadAvatar`, name + edit toggle icon, email, `SoleBadge` role, `_buildFollowingStat` (non-sellers) |
| Edit panel | `_buildEditPanel` :427 | Collapsible via `_isEditing`; Full Name field, **email locked** (greyed w/ lock icon), Phone field, Save Changes button. Animated with `AnimatedSize`. |
| Orders panel | `_buildNotificationsPanel` :529 | "My Orders" + View all → `MyOrdersScreen()`. 5 items (Unpaid/Processing/Shipped/Review/Returns), each a `_NotifItem(icon, label, filter)`; badge = `orderProvider.myOrdersCounts[filter]`; tap → `MyOrdersScreen(initialFilter: item.filter)` |
| Settings | `_buildSettingsCard` :659 | 6 `_settingsRow` ListTiles (see §1) |
| Seller section | `_buildSellerSection` :760 | `FutureBuilder` on `_sellerStoreFuture` (`StoreService.getMyStore()`); store name + Open/Closed pill + toggle switch (`_toggleStoreOpen` → `StoreService.toggleStoreOpen`); tapping row → `StoreProfileScreen(store)` or `CreateStoreScreen` if none; `SoleStatusChip(sellerStatus)`; Member Since (`profiles.created_at`) |
| Logout | `_buildLogoutButton` :903 | Confirm dialog → `auth.logout()` |

---

## 5. Key Flows

### Edit profile (inline)
```
_toggleEdit() → _isEditing flips (cancel reverts controllers from auth)
_handleSave() → auth.updateProfile(fullName, phone)
             → snackbar success/failure → _isEditing = false
```
Controllers are synced in `_syncControllers(auth)` (called from `build`): compares `_loadedProfileId` to the current profile id so switching accounts resets the fields.

### Avatar upload (`_uploadAvatar` :159)
```
ProfileService.pickAvatarImage()  → ImagePicker (gallery, ≤1000px, q85)
ProfileService.uploadAvatar(userId, filePath)
  1. UploadService.uploadFile(bucket: 'avatars', folder: userId, filename: 'avatar.jpg', upsert: true)
  2. URL gets ?t=<millis> cache-buster (same path every upload → stale image otherwise)
  3. UPDATE profiles SET avatar_url = cacheBustedUrl
  4. auth.updateProfile(newAvatarUrl: ...) to refresh in-memory profile
```

### Seller store load
`_syncControllers` (once per profile id) sets `_sellerStoreFuture = StoreService.instance.getMyStore()` only when `userRole == seller`; else null. Store open/close toggle patches the in-memory map optimistically after the API call.

---

## 6. DB + RLS (`supabase/schema.sql:18-66`)

`profiles` columns: `id` (UUID, FK auth.users, PK), `full_name` (NOT NULL), `email` (UNIQUE), `phone`, `role` CHECK (`customer|seller|admin`), `seller_status` CHECK (`none|pending|approved|rejected`), `avatar_url`, `suspended`, `rejection_reason`, `created_at`.

RLS: everyone can SELECT; user can INSERT/UPDATE own row (`auth.uid() = id`); admins can read/update all.

**⚠️ Gotcha:** `profiles` RLS blocks sellers from reading customer rows — several migrations exist to work around this for conversations (`20260715090200_fix_profiles_rls_for_conversations.sql`, `20260715090300_add_customer_name_to_conversations.sql`). Don't write queries that join profiles to customer data for sellers without checking these.

---

## 7. Gotchas for AI Agents

1. **The "My Orders" panel badges are REAL per-tab ORDER counts** (`profile_screen.dart:529` → `orderProvider.myOrdersCounts`, computed from the same loaded orders + predicates as the tabs). They previously showed unread-notification counts and drifted (reading notifications dropped badges, multiple notifications per order inflated them). If a task says "badge count doesn't match the tab", check `OrderProvider.myOrdersCounts` stays in sync with `_applyMyOrdersFilter` — both must use `matchesMyOrdersFilter`. See `docs/AI/MY_ORDERS_ARCHITECTURE.md`.
2. **Don't create a separate edit screen** — the pattern is inline editing on the profile screen (`_isEditing` state). `EditProfileScreen` is dead code; don't revive it without a reason.
3. **`_syncControllers` is called from `build`** — it's idempotent (guarded by `_loadedProfileId`) but be careful adding heavy work there.
4. **Email is not editable** in the app (locked field); password changes go through a reset email, not a change-password form.
5. **Seller section only renders for `role == seller`**; admin sees the plain profile (used for the tester role changer).
6. **Avatar URL cache-busting is required** — same storage path + `upsert` means the URL never changes; the `?t=` timestamp is what makes the new photo show.
7. **logout() clears state before calling Supabase signOut** — hooks (`onLogoutHook`) fire before sign-out completes; dependent providers must not assume the session is gone at that point.
8. **Providers are wired once in `main.dart`** (`MultiProvider`, `main.dart:101-115`) — AuthProvider, NotificationProvider, FollowProvider, UpdateProvider are all app-scoped singletons here.
