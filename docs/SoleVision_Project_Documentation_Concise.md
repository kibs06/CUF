# SoleVision — Condensed Project Reference

**Version:** 1.1.0 | **Last Updated:** June 30, 2026
**Platform:** Flutter (Mobile) + React (Admin Portal) | **Backend:** Supabase (PostgreSQL + Auth + Storage)
**Target Market:** Artisan footwear retail — Carcar City, Cebu, Philippines

---

## 1. What SoleVision Is

A multi-role marketplace for handcrafted shoes connecting **customers**, **sellers** (artisans), and **admins** through a mobile app and web admin dashboard.

**Core features:**
- Multi-store marketplace with follow/unfollow
- Point-of-Sale (POS) for in-person transactions (cash, GCash, card)
- Custom shoe orders (color, material, special requests)
- Real-time order tracking (pending → placed → preparing → ready → received)
- Biometric login (fingerprint/face)
- Admin analytics dashboard (revenue, orders, trends, top products)

---

## 2. Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter 3.x (Dart), Provider state management, Supabase Flutter SDK |
| Admin Web | React 18, Vite, React Router 6, TanStack React Query, Tailwind CSS, Recharts |
| Backend | Supabase (PostgreSQL + RLS, Auth/JWT, Storage, Realtime) |
| Fonts | Playfair Display (headlines), DM Sans (body), JetBrains Mono (code/IDs) |

---

## 3. Architecture

Both Flutter app and React admin portal connect to the **same Supabase project**. All data access governed by **Row Level Security (RLS)**. Storage buckets: `avatars`, `product-images`, `store-assets` (all public).

---

## 4. Database Schema (Summary)

| Table | Purpose | Key Relationships |
|-------|---------|-------------------|
| `profiles` | Users with roles (customer/seller/admin) and seller_status | FK to `auth.users` |
| `stores` | Artisan stores with branding (name, tagline, color, logo, banner) | owner_id → profiles |
| `products` | Products with price, category, is_active, is_featured | store_id → stores, seller_id → profiles |
| `product_variants` | Stock per size+color with optional price/SKU overrides | product_id → products (CASCADE) |
| `inventory` | Aggregated stock per size (summed from variants) | product_id → products (CASCADE) |
| `product_images` | Product photos with display order | product_id → products (CASCADE) |
| `product_customizations` | Customization options per product | product_id → products (CASCADE) |
| `orders` | Online orders with status, payment, fulfillment | store_id → stores, customer_id → profiles |
| `order_items` | Line items per order | order_id → orders (CASCADE), product_id → products (SET NULL) |
| `sales_transactions` | POS in-person transactions | store_id → stores, seller_id → profiles |
| `sales_transaction_items` | Line items per POS transaction | transaction_id → sales_transactions (CASCADE), product_id → products (SET NULL) |
| `customizations` | Legacy customization requests | customer_id → profiles |
| `customization_requests` | Bespoke footwear requests | customer_id → profiles, store_id → stores, base_product_id → products (SET NULL) |
| `store_follows` | Customer store follows | user_id + store_id (composite PK) |
| `story_entries` | Store workshop stories (no `title` column) | store_id → stores (CASCADE) |
| `notifications` | User notifications | recipient fields |

**Important schema notes:**
- `story_entries` has NO `title` column (removed from live DB)
- `orders.store_id` is a direct column (not joined via products)
- `inventory` is synced from `product_variants` — one row per unique size, stock summed across colors
- `is_active` on products is auto-managed based on inventory levels

**Seed data:** 3 stores — Valladolid Leather Co., Carcar Sole Works, Cebu Heritage Shoes

---

## 5. User Roles & Permissions

| Role | Access |
|------|--------|
| **Customer** | Browse/purchase, follow stores, order tracking, custom requests |
| **Seller** | CRUD own store/products, POS, order fulfillment, sales reports |
| **Admin** | Full platform oversight, approve/reject sellers, analytics |

**RLS Policy Matrix:**

| Table | Customer | Seller | Admin |
|-------|----------|--------|-------|
| profiles | Read all, Update own | Read all, Update own | Read all, Update any |
| products | Read all | Read all, CRUD own store | Read all, CRUD any |
| orders | Read/Insert own | Read all, Update status | Read all, Update status |
| customizations | Read/Insert own | Read all, Update status | Read all, Update any |
| stores | Read all | CRUD own store | CRUD any |
| store_follows | Read/Insert/Delete own | — | — |
| story_entries | Read all | — | CRUD any |
| products DELETE | — | `auth.uid() = seller_id` | `current_user_role() = 'admin'` |

**FK Delete Rules (hard-won, don't change):** `order_items.product_id` → SET NULL, `sales_transaction_items.product_id` → SET NULL, `customization_requests.base_product_id` → SET NULL, `inventory.product_id` → CASCADE, `product_variants.product_id` → CASCADE, `product_images.product_id` → CASCADE, `product_customizations.product_id` → CASCADE

**Seller Approval Flow:** Register → pending status → admin approves → role becomes 'seller'

---

## 6. Mobile App Structure

### Navigation
```
SplashScreen → AuthGate (StreamBuilder on auth state)
  ├→ OnboardingScreen (first-time)
  ├→ LoginScreen / RegisterScreen
  ├→ CustomerShell (customer)
  ├→ SellerShell (seller, approved)
  ├→ AdminShell (admin)
  └→ PendingApprovalScreen (pending seller)
```

### Key Screens by Role

**Customer:** Home (products, categories, search), Store discovery, Product detail (sizes, cart, customization), Cart, Checkout, Orders/tracking, Profile

**Seller:** Dashboard (today's sales, weekly chart, metrics), POS, Products (CRUD + images + variants), Orders, Reports, Store management, Inventory

**Admin:** Dashboard (platform stats), Users, Seller applications, Products, Orders, Analytics (charts), Settings

### Services (Singletons in `lib/services/`)
`AuthService`, `ProductService`, `OrderService`, `StoreService`, `ProfileService`, `UploadService`, `SalesService`, `BiometricService`, `SupabaseService`

### State Management
- **Flutter:** Provider (`AuthProvider`, `ProductProvider`, `CartProvider`, `OrderProvider`)
- **React Admin:** TanStack React Query (hooks in `admin-portal/src/hooks/`)

### Cart Logic
Items keyed by `productId-size-color`. Flat ₱100 delivery fee. Auto-removal at quantity 0.

---

## 7. Admin Portal Structure

**Routes:** `/login`, `/` (Dashboard), `/users`, `/seller-applications`, `/products`, `/orders`, `/analytics`, `/settings`

**Key components:** `AppLayout` (sidebar + topbar), `ProtectedRoute` (auth guard), `DataTable`, `Modal`, `Toast`, `Skeleton`, `Badge`, `StatCard`

**Hooks:** `useAuth`, `useDashboard`, `useUsers`, `useOrders`, `useProducts`, `useSellerApplications`, `useAnalytics`

**Analytics charts (Recharts):** Orders over time, Revenue over time, Users over time, Orders by status (pie), Top products (bar), Seller application trends (stacked bar)

---

## 8. Design System

**Colors:** Primary `#8B5A2B` (Burnished Clay), Secondary `#3B2314` (Carob Dark), Accent `#4ECDC4` (Celadon Teal), Surface `#F5F0EB` (Off-White Suede), Error `#D64545`, Success `#6B8F47`, Border `#D2C7BC`

**Reusable widgets:** `SoleCard`, `SolePrimaryButton`, `SoleTextField`, `SoleBottomNav`, `SoleBadge`, `SoleStatusChip`, `SoleMetricCard`, `SoleProductCard`, `SoleTimeline`, `ShimmerBox`, `EmptyStateWidget`, `ErrorRetryWidget`, `CartIconButton`

**Seller widgets:** `SellerMetricCard`, `SellerProductRow`, `SellerOrderCard`, `SellerInventoryRow`, `SellerWeeklyBar`, `SellerSparkline`

---

## 9. Authentication & Security

- Registration → Supabase Auth → Profile created via DB trigger or manual upsert
- Login → JWT → Profile fetch with retry (up to 5 attempts, exponential backoff)
- Session restore via `AuthGate` StreamBuilder on `currentSession`
- Biometric login via `local_auth` + `FlutterSecureStorage` for credential storage
- RLS on all tables, JWT auto-refresh, admin-only policy checks

---

## 10. All Features — Status

**All features listed are ✅ (implemented):**

Customer: Registration, biometric login, onboarding, product browsing, store discovery, product details, cart, checkout, order tracking, custom orders, profile management, password reset

Seller: Store creation/management, product CRUD with images/variants, inventory, order management, POS, sales tracking, reports, store stories

Admin (Mobile): Dashboard, user management, seller applications, product monitoring

Admin (Web): Responsive sidebar, protected routes, dashboard stats, interactive charts, data tables, modals, toasts, skeleton loading

---

## 11. Bugs Fixed & Improvements (June 28–30, 2026)

### Critical Bugs Resolved

**1. Login Freeze When Switching Accounts** (5 root causes, all fixed together)
- Stale AuthProvider state not cleared on logout → Clear all state in `signOut()` and at start of `login()`
- Supabase auth stream not re-emitting for account switch → Force sign-out existing session before new `signIn()`
- Profile fetch retry counter not resetting → Reset before each new `signIn()`
- Biometric credentials from Account A bleeding into Account B → Clear `FlutterSecureStorage` on logout
- `_isLoading` flag stuck true → `try/catch/finally` guarantees reset
- **Files:** `auth_provider.dart`, `auth_service.dart`, `auth_gate.dart`, `biometric_service.dart`

**2. Navigator Stack Conflict on Account Switch**
- `LoginScreen` was pushed via `Navigator.pushReplacement` creating a disconnected stack layer
- Fix: Return widgets directly from `_FirstTimeOrLoginRouter.build()` instead of using navigator push
- `PendingApprovalScreen` logout changed to use `AuthProvider.logout()` instead of `AuthService.signOut()`
- **File:** `auth_gate.dart`

**3. Product Size Selector Empty — Inventory Never Written**
- `product_detail_screen.dart` read non-existent `widget.product['sizes']` key
- `product_service.dart` never wrote to `inventory` table during create/update
- Fix: Added `_syncInventoryFromVariants()` helper that groups variants by size, sums stock, replaces inventory rows
- Added `inventory(*)` to all product read queries
- Added `_buildSizesMap()` in product detail screen reading from both `inventory` and `product_variants`
- Added `_fetchInventory()` fallback with shimmer loading skeleton
- **Files:** `product_service.dart`, `product_detail_screen.dart`

**4. Product Delete Silently Failing**
- Missing DELETE RLS policy on `products` table (Supabase silently rejects)
- FK constraints set to `NO ACTION` blocking deletes → Changed to `SET NULL` for history tables, `CASCADE` for child tables
- Missing `await` on `_removeStorageFile()` → Added await
- **SQL:** Added DELETE policies for sellers (own products) and admins (any product)
- **File:** `product_service.dart`

### Features Wired to Real Data

**5. Seller Dashboard** — All metrics (today's revenue, weekly trends, bar chart, recent orders, store rating) now use real Supabase data. Revenue combines both `orders` (paid, non-cancelled) + `sales_transactions` (POS).

**6. Reports Screen** — Weekly sales total, 7-day bar chart, top 5 products by units sold — all real data via `SellerReportData` model.

**7. Product Hard Delete & Auto-Deactivation** — Sellers can permanently delete products (with history preservation via SET NULL). `is_active` auto-manages based on inventory levels.

### UX Improvements

**8. Profile Fetch Timeout** — 12-second timeout on profile fetch in `AuthGate` with retry button

**9. Offline Detection** — Checks internet connectivity, shows "No Internet Connection" screen with retry

**10. Size Selector Loading Skeleton** — Shimmer placeholder while inventory data loads

### SQL Migration Required
Run `docs/debug/inventory_backfill.sql` once in Supabase SQL Editor to backfill inventory from existing product_variants.

---

## 12. Project File Structure

```
app/
├── admin-portal/          # React admin dashboard (Vite + React + Tailwind)
│   └── src/
│       ├── components/    # UI components (layout, products, users, ui/)
│       ├── hooks/         # React Query hooks
│       ├── lib/           # Constants, Supabase client
│       └── pages/         # Route pages
├── lib/                   # Flutter mobile app
│   ├── constants/         # AppConstants (Supabase creds, colors, styles)
│   ├── models/            # ProductVariant, ProductCustomization, Store
│   ├── providers/         # AuthProvider, ProductProvider, CartProvider, OrderProvider
│   ├── screens/           # Organized by role (admin/, auth/, customer/, seller/, shared/, store/)
│   ├── services/          # Singleton services (auth, product, order, store, profile, upload, sales, biometric)
│   ├── widgets/           # Reusable widgets + seller/ subfolder
│   └── main.dart          # Entry point
├── supabase/schema.sql    # Database schema + RLS policies
└── docs/debug/            # Setup SQL scripts + historical docs (snapshots removed 2026-08-09)
```

---

## 13. Future Enhancements

**High Priority:** Real-time order updates (Supabase Realtime), push notifications, payment gateway integration (GCash API, card processing), product image gallery with zoom, fuzzy search with filters

**Medium Priority:** AR shoe fitting with real 3D models, detailed seller analytics, customer reviews/ratings, wishlist, store following feed

**Low Priority:** Multi-language (Filipino/Cebuano), offline mode, seller-to-customer chat, admin role delegation, PDF/CSV export

---

## 14. Data Models (Key Types)

- **ProductVariant**: `id`, `size` (EU string), `color?`, `stock`, `additionalPrice`, `sku?`
- **ProductCustomization**: `id`, `optionName`, `optionType` (text/select/color), `options[]`, `isRequired`, `additionalPrice`
- **Store**: `id`, `name`, `tagline?`, `location`, `brandColor` (hex), `bannerUrl?`, `logoUrl?`, `rating`, `isOpen`, `isActive`, `ownerId?`

---

*Condensed from SoleVision Project Documentation v1.1.0. For full details, see `SoleVision_Project_Documentation2.md`.*
