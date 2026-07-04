# SoleVision — Changelog

## June 28, 2026

---

### 1. Products Page Redesign — Store-Grouped Card Browser

**Files changed:**
- `admin-portal/src/hooks/useProducts.js` — Refactored to fetch stores first, then products with `product_images` and `inventory` relations, grouped by store with computed fields (`isActive`, `totalStock`, `thumbnail`)
- `admin-portal/src/pages/Products.jsx` — Full rewrite from flat table to store-grouped layout with search, category/status filters, Grid/List view toggle, shimmer skeletons, and empty states
- `admin-portal/src/components/products/StoreGroup.jsx` — Collapsible store sections with gradient banner headers (h-64), store logo, name, location, product count, and open/closed status
- `admin-portal/src/components/products/ProductCard.jsx` — Grid view cards with hover overlay actions (View/Deactivate/Delete), status and featured badges, image zoom on hover
- `admin-portal/src/components/products/ProductListRow.jsx` — Compact list rows with thumbnail, name, price, stock, status, and icon-only hover actions
- `admin-portal/src/components/products/ProductDetailModal.jsx` — Full detail modal with image gallery, details grid, description, size/stock breakdown, and action buttons
- `admin-portal/src/components/products/AddProductModal.jsx` — Admin modal form with store selector wired to Supabase insert

---

### 2. Products Page Fixes (6 Issues)

**Files changed:**
- `admin-portal/src/pages/Products.jsx` — Removed duplicate "Products" heading, grammar fix ("1 store" not "1 stores"), Grid/List pill toggle with divider, wired Add Product button to modal
- `admin-portal/src/components/products/StoreGroup.jsx` — Increased banner height from `h-24` → `h-40` → `h-64` with improved gradient overlay, larger logo (`w-20 h-20`), rating chip, better text sizing
- `admin-portal/src/components/products/ProductCard.jsx` — Stacked hover action buttons vertically at card bottom with gradient overlay (`from-black/70 via-black/20 to-transparent`)
- `admin-portal/src/components/products/AddProductModal.jsx` — Created modal with store selector, product fields, Supabase insert, loading/error states

---

### 3. Remove Duplicate Headers

**Files changed:**
- `admin-portal/src/pages/Products.jsx` — Removed duplicate "Products" heading, subtitle, and Add Product button block; cleaned up dead code (`showAddModal` state, `AddProductModal` import/render, `allStores` variable, unused `Plus` import)
- `admin-portal/src/pages/Users.jsx` — Removed duplicate "Users" heading, subtitle, and stats chips row; cleaned up unused `total`/`all` variables
- `admin-portal/src/hooks/useProducts.js` — Removed dead `allStores` computation and return property

---

### 4. Users Page Redesign — Role-Separated Tab Layout

**Files changed:**
- `admin-portal/src/hooks/useUsers.js` — Rewritten to remove `suspended` column (doesn't exist in DB), returns `{ all, customers, sellers, admins }` grouped by role, new `useChangeRole` mutation
- `admin-portal/src/pages/Users.jsx` — Full rewrite with role-separated tab layout (All/Customers/Sellers/Admins), real-time search, side-by-side sections on desktop, loading skeleton
- `admin-portal/src/components/users/UserRow.jsx` — Individual user row with deterministic avatar colors, hover actions (View profile), joined date in JetBrains Mono
- `admin-portal/src/components/users/UserSection.jsx` — Role-colored section container with icon, count badge, and empty state
- `admin-portal/src/components/users/UserDetailModal.jsx` — Role-colored header with avatar, info grid (Member Since, User ID, Phone, Seller Status), and Customer/Seller role toggle buttons

---

### 5. Login Freeze Fix — Account Switch Freeze

**Bug:** When a user logs out and attempts to log in with a **different account**, the app freezes on the login screen. The only recovery was to fully close and reopen the app.

**Root causes addressed:**
1. Stale auth state in `AuthProvider` after logout
2. Profile cache not resetting for new user
3. `_isLoading` flag not properly reset in all code paths
4. Biometric credentials not cleared on logout

**Files changed:**

| File | Change |
|------|--------|
| `lib/providers/auth_provider.dart` | `logout()` now clears all state (`_currentUser`, `_profile`, `_isLoading`, `_errorMessage`) *before* calling Supabase signOut, then clears biometric credentials. `login()` clears stale `_currentUser`/`_profile` at the start and uses `try/catch/finally` to guarantee `_isLoading` resets. `signUp()` also upgraded to `finally` pattern. |
| `lib/services/auth_service.dart` | Removed pre-signOut in `signIn()` (was causing auth stream race condition that could re-route to login mid-login). |
| `lib/screens/auth_gate.dart` | Added `_resetProfileCache()` to clear stale profile future/userId when the auth stream emits a null user, ensuring the next sign-in always fetches the new user's profile. |
| `lib/screens/auth/login_screen.dart` | `_submit()` cleaned up with early returns, `mounted` guard at top, and proper `Future<void>` return type. |

---

### Build Status

- **Admin portal (Vite):** ✅ Compiles successfully (0 errors)
- **Flutter app (Dart analyze):** ✅ 0 compilation errors (pre-existing warnings/infos only)
