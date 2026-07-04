# SoleVision — Project Handoff Documentation

**Version:** 1.1.0
**Last Updated:** July 2, 2026
**Status:** Functional MVP with critical bugs resolved; ready for feature expansion

---

## 1. Project Overview

### What is this project?

**SoleVision** is a multi-role marketplace platform connecting three types of users in the artisan footwear industry of **Carcar City, Cebu, Philippines**:

| Role | Description | Primary Use |
|------|-------------|-------------|
| **Customer** | End users who browse and buy shoes | Browse products, place orders, track deliveries, request custom footwear |
| **Seller** | Artisan shoe makers/shops | Manage store, products, inventory, process orders, run POS for walk-in sales |
| **Admin** | Platform administrators | Approve sellers, monitor products, view analytics, manage users |

### Target Market
- **Geography:** Carcar City, Cebu, Philippines (known for artisan shoemaking heritage)
- **Industry:** Handcrafted/artisan footwear retail
- **Currency:** Philippine Peso (₱)

### Core Value Proposition
- **For customers:** Browse and purchase handcrafted shoes from multiple local artisans, track orders in real time, request bespoke custom footwear
- **For sellers:** Manage a digital storefront with inventory tracking, process both online orders and in-person POS sales, view sales analytics and reports
- **For admins:** Oversee the platform — approve new sellers, monitor product listings, view platform-wide analytics

---

## 2. Current State / What's Been Built

### Completed Features

#### Customer Features (all ✅)
- User registration with email/password
- Biometric login (fingerprint/face via `local_auth` + `FlutterSecureStorage`)
- First-time onboarding screen
- Product browsing with category filtering and search
- Store discovery and follow/unfollow functionality
- Product details with image gallery, size selection (EU sizes), add to cart
- Shopping cart with quantity controls, per-store grouping, ₱100 flat delivery fee
- Checkout with payment method selection (Cash / GCash / Card)
- Order tracking with status timeline (pending → placed → preparing → ready → received)
- Custom shoe orders (color, material, special requests)
- Profile management (name, phone, avatar)
- Password reset via email
- Offline detection and connection retry

#### Seller Features (all ✅)
- Store creation with full branding (name, tagline, location, brand color, logo, banner)
- Store profile editing and open/closed toggle
- Product CRUD with multi-image upload to Supabase Storage
- Product variants (size + color + stock + additional price + SKU)
- Product customizations (monogram, material choice, etc.)
- Inventory management per product/size
- Auto-deactivation/activation based on stock levels
- Hard delete of products (with history preservation via FK SET NULL)
- Order management with status updates
- Point-of-Sale (POS) for walk-in transactions (cash, GCash, card)
- Sales tracking (today's revenue, weekly trends, monthly trends)
- Sales reports (weekly/monthly toggle, top 5 products, week-over-week comparison, CSV export stub)
- Store stories (workshop stories on store profile)
- Seller dashboard with real-time metrics

#### Admin Features (Mobile App — all ✅)
- Platform-wide dashboard with stats
- User management with role changes
- Seller application approval/rejection workflow
- Product catalog monitoring

#### Admin Features (Web Portal — all ✅)
- Responsive sidebar navigation with mobile support
- Protected routes with auth guard
- Dashboard with stat cards, recent applications, recent orders, sparkline
- Interactive analytics charts (Recharts): orders over time, revenue, users, order status pie, top products, seller application trends
- User management with role-separated tabs (All/Customers/Sellers/Admins), search, detail modals
- Seller application management (approve/reject with reason)
- Product catalog grouped by store with banners
- Order management with status updates
- Admin settings (profile, password)

### Tech Stack

#### Mobile App (Flutter)
| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | Flutter (Dart) | SDK ^3.12.1 |
| State Management | Provider | ^6.1.2 |
| Backend Client | Supabase Flutter SDK | ^2.10.3 |
| Typography | Google Fonts | ^6.2.1 (Playfair Display, DM Sans, JetBrains Mono) |
| Image Handling | `cached_network_image`, `image_picker` | ^3.4.1, ^1.1.2 |
| SVG | `flutter_svg` | ^2.0.10 |
| Loading States | `shimmer` | ^3.0.0 |
| Local Storage | `shared_preferences`, `flutter_secure_storage` | ^2.2.3, ^9.0.0 |
| Biometrics | `local_auth` | ^2.2.0 |
| Unique IDs | `uuid` | ^4.5.1 |

#### Admin Portal (React Web)
| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | React | ^18.3.1 |
| Bundler | Vite | ^6.2.2 |
| Routing | React Router DOM | ^6.30.0 |
| State/Data Fetching | TanStack React Query | ^5.67.2 |
| Backend Client | Supabase JS SDK | ^2.49.1 |
| Styling | Tailwind CSS | ^3.4.17 |
| Charts | Recharts | ^2.15.1 |
| Icons | Lucide React | ^1.21.0 |

#### Backend (Supabase)
| Component | Technology |
|-----------|-----------|
| Database | PostgreSQL with Row Level Security (RLS) |
| Authentication | Supabase Auth (email/password, JWT) |
| Storage | Supabase Storage (public buckets) |
| Realtime | Supabase Realtime (available, not yet integrated) |
| Edge Functions | Available but unused |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Supabase Cloud                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐ │
│  │   Auth   │  │ Postgres │  │  Storage   │  │ Realtime │ │
│  │ (JWT)   │  │   (RLS)  │  │ (images)   │  │          │ │
│  └────┬─────┘  └────┬─────┘  └─────┬──────┘  └──────────┘ │
└───────┼──────────────┼──────────────┼───────────────────────┘
        │              │              │
   ┌────┴────┐    ┌────┴────┐    ┌───┴────┐
   │ Flutter │    │ React   │    │ Admin  │
   │ Mobile  │    │  Web    │    │ Portal │
   └─────────┘    └─────────┘    └────────┘
```

**Key architectural decisions:**
- Both Flutter app and React admin portal connect to the **same Supabase project**
- All data access governed by **Row Level Security (RLS)**
- Supabase manages JWT auth for both clients
- Storage buckets (`avatars`, `product-images`, `store-assets`) are all **public** for simplicity

### Folder Structure

```
app/
├── admin-portal/              # React admin dashboard (Vite + React + Tailwind)
│   ├── src/
│   │   ├── components/
│   │   │   ├── layout/       # AppLayout, ProtectedRoute, Sidebar, TopBar
│   │   │   ├── products/     # AddProductModal, ProductCard, ProductDetailModal, etc.
│   │   │   ├── ui/           # Badge, DataTable, Modal, Skeleton, StatCard, Toast, etc.
│   │   │   └── users/        # UserDetailModal, UserRow, UserSection
│   │   ├── hooks/            # React Query hooks (useAuth, useDashboard, useOrders, etc.)
│   │   ├── lib/              # constants.js, supabase.js
│   │   └── pages/            # Dashboard, Users, SellerApplications, Products, Orders, Analytics, Settings, Login
│   ├── package.json
│   └── vite.config.js
│
├── lib/                       # Flutter mobile app
│   ├── constants/
│   │   └── app_constants.dart # Supabase creds, color palette, typography, visual rules
│   ├── models/
│   │   ├── product_models.dart # ProductVariant, ProductCustomization
│   │   ├── seller_report_data.dart # SellerReportData (weekly/monthly reports)
│   │   └── store.dart         # Store model with fromMap/toMap
│   ├── providers/
│   │   ├── auth_provider.dart  # Auth state (login, logout, profile, session restore)
│   │   ├── cart_provider.dart  # Cart logic (add/remove, delivery fee)
│   │   ├── order_provider.dart # Orders & customizations
│   │   └── product_provider.dart # Product browsing, categories
│   ├── screens/
│   │   ├── admin/             # admin_dashboard_screen, manage_users_screen, etc.
│   │   ├── auth/              # splash_screen, login_screen, register_screen, onboarding_screen, auth_gate
│   │   ├── customer/          # customer_home_screen, product_detail_screen, cart_screen, checkout_screen, orders_screen, etc.
│   │   ├── seller/            # seller_dashboard_screen, pos_screen, manage_products_screen, reports_screen, etc.
│   │   ├── shared/            # profile_screen
│   │   └── store/             # store_screen, store_profile_screen, collection_screen, widgets/
│   ├── services/
│   │   ├── auth_service.dart   # Supabase Auth wrapper (sign in, sign up, profile fetch with retry)
│   │   ├── biometric_service.dart # Biometric auth + FlutterSecureStorage
│   │   ├── order_service.dart  # Order placement, store order filtering, recent orders
│   │   ├── product_service.dart # Full product CRUD, image upload, variants, inventory sync
│   │   ├── profile_service.dart # Avatar upload
│   │   ├── sales_service.dart  # POS transactions, weekly/monthly reports, dashboard metrics
│   │   ├── store_service.dart  # Store CRUD, follow/unfollow, story entries
│   │   ├── supabase_service.dart # Legacy/general CRUD (being superseded by focused services)
│   │   └── upload_service.dart # Generic file upload/delete for Supabase Storage
│   ├── widgets/
│   │   ├── seller/            # SellerMetricCard, SellerProductRow, SellerOrderCard, etc.
│   │   └── *.dart             # SoleCard, SolePrimaryButton, SoleTextField, SoleBottomNav, etc.
│   └── main.dart              # Entry point, MultiProvider setup, Material 3 theme
│
├── supabase/
│   └── schema.sql             # Original database schema (NOTE: live DB has evolved beyond this file)
│
├── docs/
│   ├── SoleVision_Project_Documentation.md      # Full documentation v1.0
│   ├── SoleVision_Project_Documentation2.md     # Full documentation v1.1 (with schema corrections)
│   ├── SoleVision_Project_Documentation_Concise.md # Condensed reference
│   ├── product_delete_and_auto_deactivation.md  # Feature changelog
│   └── debug/                  # Session logs, reference file copies, SQL migrations
│       ├── SESSION_LOG_JUNE_30_2026.md
│       ├── SESSION_LOG_JULY_2_2026.md
│       └── inventory_backfill.sql
│
├── pubspec.yaml               # Flutter dependencies
├── analysis_options.yaml      # Dart lint rules
└── CHANGELOG.md               # Development session changelog
```

---

## 3. Decisions & Rationale

### Database & Backend

| Decision | Rationale |
|----------|-----------|
| **Supabase (PostgreSQL + Auth + Storage)** over Firebase/Custom Backend | Rapid prototyping with built-in RLS, Auth, and Storage. PostgreSQL gives full SQL power. No server to maintain. |
| **RLS on all tables** | Security at the database level — even if application code has bugs, data access is enforced by Postgres. Critical for multi-role system. |
| **Email/password auth** (not OAuth) | Simplicity for initial MVP. Target market may not have Google/Apple accounts for all users. Biometric added as secondary convenience. |
| **Public storage buckets** | Simplicity — all product images, avatars, and store assets are publicly readable. Tradeoff: anyone can guess URLs, but content is not sensitive (product photos). |
| **`store_id` as direct column on `orders`** | Orders need to know which store they belong to for seller filtering. Originally planned to join via products, but direct column is simpler and avoids extra joins for RLS. |

### Inventory & Product Architecture

| Decision | Rationale |
|----------|-----------|
| **Two-tier inventory: `product_variants` + `inventory`** | `product_variants` holds granular stock per size+color. `inventory` holds aggregated stock per size (summed across colors). Customer size selector reads from `inventory`; seller manages via `product_variants`. |
| **`_syncInventoryFromVariants()`** | Automatically keeps `inventory` in sync whenever variants are created/updated. One row per unique size. Prevents stale data. |
| **`is_active` auto-managed by stock** | Product visibility auto-toggles based on whether any stock exists. Sellers don't have to manually deactivate out-of-stock products. |
| **FK SET NULL for history tables** | When a product is deleted, `order_items`, `sales_transaction_items`, and `customization_requests` keep their rows with `product_id` set to NULL. Preserves order/transaction history. |

### Auth & Session

| Decision | Rationale |
|----------|-----------|
| **Profile fetch with 5 retries + exponential backoff** | Supabase DB trigger may be slow to create profile after signup. Retries handle race conditions. |
| **Force sign-out before new sign-in** | Prevents session bleed when switching accounts. Without this, Supabase silently rejects the new sign-in. |
| **Return widgets directly from `build()` (not Navigator.pushReplacement)** | Prevents LoginScreen from becoming a disconnected stack layer that can't be popped by StreamBuilder. |
| **Biometric credentials cleared on logout** | Prevents Account A's credentials from interfering with Account B's login. |

### Mobile Architecture

| Decision | Rationale |
|----------|-----------|
| **Provider for state management** | Simple, well-understood pattern for a medium-sized app. No need for Bloc/Riverpod complexity at this stage. |
| **Singleton services** | All services (`AuthService`, `ProductService`, etc.) use private constructors with static instances. Simple DI without a framework. |
| **Services throw, Providers catch** | Clean separation — services are pure data access, providers handle loading/error states for the UI. |
| **`AuthGate` StreamBuilder pattern** | Listens to Supabase auth state changes and routes to the correct shell (Customer/Seller/Admin/Pending) automatically. |

### Admin Portal

| Decision | Rationale |
|----------|-----------|
| **TanStack React Query** | Automatic caching, refetching, and optimistic updates. Much better DX than manual state management for server data. |
| **Tailwind CSS** | Rapid styling without CSS-in-JS overhead. Consistent design system via utility classes. |
| **Vite over CRA** | Faster dev server, ESM-native, better DX. |
| **Separate from Flutter app** | Admin portal is a web-only tool for internal use. React/Vite is lighter to develop and deploy than Flutter web. |

### Tradeoffs & Constraints Accepted

- **No push notifications yet** — relies on users checking the app
- **No real-time updates** — Supabase Realtime is available but not yet integrated; users must pull-to-refresh
- **No payment gateway** — checkout records intent only; actual payment (GCash/card) handled outside the app
- **Flat ₱100 delivery fee** — no distance-based calculation
- **No offline mode** — app requires internet connection (but detects and reports offline state)
- **Schema drift** — `supabase/schema.sql` is the original schema; the live database has evolved (added tables, changed PKs to UUID, removed `story_entries.title`). The docs in `docs/` are more accurate than the schema file.

---

## 4. Known Issues / Incomplete Work

### Bugs / Limitations

| Issue | Severity | Notes |
|-------|----------|-------|
| **Schema drift between `supabase/schema.sql` and live DB** | Medium | The `schema.sql` file still shows `BIGINT` PKs and missing tables. Live DB has `UUID` PKs, `order_items`, `product_variants`, `inventory`, etc. **Always refer to the docs, not `schema.sql`.** |
| **`story_entries.title` column referenced in schema.sql but doesn't exist in live DB** | Low | Code correctly avoids this column, but the SQL file is misleading. |
| **CSV export is a stub** | Low | Reports screen has a "Download Sales Report (CSV)" button that shows a SnackBar — actual file export not implemented. |
| **AR fitting screen is a placeholder** | Low | `ArViewPlaceholder` widget exists but no real AR functionality. |
| **No error boundary for admin portal** | Low | React app has no global error boundary — unhandled errors crash the page. |
| **`SupabaseService` is a legacy catch-all** | Low | Being gradually superseded by focused services (`ProductService`, `OrderService`, `SalesService`), but still used for some CRUD operations (e.g., `fetchProducts`, `fetchOrders`, `createOrder`). |

### Technical Debt

| Item | Impact | Priority |
|------|--------|----------|
| **`supabase/schema.sql` is outdated** | Misleads developers; new contributors will be confused | Should be updated or deleted |
| **`SupabaseService` duplicates logic** | Some CRUD exists in both `SupabaseService` and focused services (e.g., `createOrder` in both `SupabaseService` and `OrderService`) | Medium |
| **`isFollowing` always returns `false` in `StoreService`** | The synchronous `isFollowing()` method is a stub that always returns `false`. The async `isFollowingAsync()` is the real implementation. | Medium |
| **No unit tests** | `test/widget_test.dart` is the default Flutter template — no actual tests exist | High for production |
| **No `.env` for admin portal** | Supabase credentials are in `.env` but no `.env.example` exists for onboarding | Low |
| **Debug prints in some files** | Some `debugPrint` statements from debugging sessions may still be in production code | Low |

### Features Partially Built / Stubbed

- **Custom orders**: The `customizations` table and `customization_requests` table exist, and customers can submit requests, but seller-side management of custom orders is limited
- **Store stories**: `story_entries` table and read queries exist, but seller-side CRUD for stories is not fully wired
- **Notifications**: `notifications` table exists in schema but no push notification system is implemented
- **Search**: Basic category filtering exists; fuzzy search and advanced filters are not implemented

---

## 5. What's Next

### High Priority (Discussed / Planned)

| Feature | Status | Notes |
|---------|--------|-------|
| **Real-time order updates** | Not started | Supabase Realtime subscriptions on `orders` table — customers and sellers see status changes live |
| **Push notifications** | Not started | Firebase Cloud Messaging or Supabase Edge Functions + web push |
| **Payment gateway integration** | Not started | GCash API, card processing (e.g., PayMongo for Philippines) |
| **Product image gallery with zoom/carousel** | Not started | Currently shows images but no zoom or swipe carousel |
| **Search with filters** | Not started | Category, price range, store, size filters |

### Medium Priority

- AR shoe fitting with real 3D models (currently placeholder)
- Detailed seller analytics dashboard
- Customer reviews and ratings system
- Wishlist / favorites feature
- Store following feed with product updates

### Low Priority

- Multi-language support (Filipino, Cebuano)
- Offline mode with local caching
- Seller-to-customer chat
- Admin role delegation
- PDF/CSV export for reports

### Open Questions

- **Payment handling**: Should payment be handled entirely in-app, or is the current "record intent + pay in person" model sufficient for the Carcar market?
- **Delivery**: Flat ₱100 fee or distance-based? The current model assumes all customers are local to Carcar City.
- **Single store per seller**: Currently enforced (one store per seller). Should sellers be allowed multiple stores?
- **Admin portal deployment**: Where should the admin portal be hosted? (Vercel, Netlify, or self-hosted?)
- **Flutter web**: Should the admin portal be rebuilt in Flutter for code sharing, or is React fine as a separate tool?

---

## 6. Key Files & Configuration

### Critical Configuration Files

| File | Purpose |
|------|---------|
| `lib/constants/app_constants.dart` | **Contains Supabase URL and anon key.** Also defines the entire color palette, typography, visual language (shadows, radii), and role/status constants. |
| `admin-portal/src/lib/supabase.js` | React admin portal Supabase client initialization (reads from `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` env vars) |
| `admin-portal/src/lib/constants.js` | Admin portal constants: roles, statuses, formatting utilities (`formatDate`, `formatCurrency`, `getInitials`, `shortId`) |
| `supabase/schema.sql` | **OUTDATED** — original schema. Live DB has evolved. See docs for accurate schema. |

### Key Service Files (Flutter)

| File | Responsibility |
|------|---------------|
| `lib/services/auth_service.dart` | Auth: sign in (with session-clear), sign up, profile fetch (5 retries), password reset |
| `lib/services/product_service.dart` | Full product CRUD, image upload to Storage, variants, customizations, inventory sync, product deletion, `syncProductActiveStatus()` |
| `lib/services/order_service.dart` | Order placement, store order filtering (products → order_items chain), recent orders, order status updates |
| `lib/services/sales_service.dart` | POS transactions, today/weekly/monthly revenue (combining online + POS), weekly/monthly reports, top products |
| `lib/services/store_service.dart` | Store CRUD, image upload, follow/unfollow, story entries |
| `lib/services/supabase_service.dart` | Legacy general CRUD — still used for some operations |
| `lib/providers/auth_provider.dart` | Auth state management with login/logout/profile/updateProfile/resetPassword |

### Key Data Flow Patterns

**Revenue calculation** (critical — don't break):
- Revenue ALWAYS combines **both** `orders` (online, `payment_status = 'paid'`, `status != 'cancelled'`) **and** `sales_transactions` (POS)
- Neither source alone is complete

**Store order filtering** (3-step chain):
1. `products` WHERE `store_id = X` → get product IDs
2. `order_items` WHERE `product_id IN [product IDs]` → get order IDs
3. `orders` WHERE `id IN [order IDs]` → final orders

**Inventory sync**:
- `product_variants` = source of truth for stock per size+color
- `inventory` = derived/aggregated table, one row per size (stock summed across colors)
- `_syncInventoryFromVariants()` runs after every variant create/update

### Environment Variables / Setup

| Variable | Location | Description |
|----------|----------|-------------|
| `AppConstants.url` | `lib/constants/app_constants.dart` | Supabase project URL (hardcoded) |
| `AppConstants.anonKey` | `lib/constants/app_constants.dart` | Supabase anon key (hardcoded) |
| `VITE_SUPABASE_URL` | `admin-portal/.env` | Same Supabase URL |
| `VITE_SUPABASE_ANON_KEY` | `admin-portal/.env` | Same anon key |

### Setup Instructions

**Flutter Mobile App:**
```bash
cd app
flutter pub get
flutter run
# Credentials are hardcoded in lib/constants/app_constants.dart
```

**React Admin Portal:**
```bash
cd admin-portal
npm install
# Create .env with VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm run dev
# Opens at http://localhost:5173
```

**Database:**
1. Create Supabase project
2. **Do NOT use `supabase/schema.sql` directly** — it's outdated. Use the schema from `docs/SoleVision_Project_Documentation2.md` as reference
3. Create storage buckets: `avatars`, `product-images`, `store-assets` (all public)
4. Run `docs/debug/inventory_backfill.sql` once to populate inventory for existing products
5. Add RLS DELETE policies for `products` table (see docs)

### Seed Data

3 stores are seeded in the database:
1. **Valladolid Leather Co.** — "Handcrafted footwear since 1992" (Valladolid, Carcar City)
2. **Carcar Sole Works** — "Where tradition meets comfort" (Poblacion, Carcar City)
3. **Cebu Heritage Shoes** — "Crafted with Cebuano pride" (Carcar City, Cebu) — initially closed

### Database Tables Summary

| Table | Purpose | Key Relationships |
|-------|---------|-------------------|
| `profiles` | Users with roles and seller_status | FK → `auth.users` |
| `stores` | Artisan stores with branding | `owner_id` → `profiles` |
| `products` | Products with price, category, flags | `store_id` → `stores`, `seller_id` → `profiles` |
| `product_variants` | Stock per size+color with pricing | `product_id` → `products` (CASCADE) |
| `inventory` | Aggregated stock per size | `product_id` → `products` (CASCADE) |
| `product_images` | Product photos with display order | `product_id` → `products` (CASCADE) |
| `product_customizations` | Customization options per product | `product_id` → `products` (CASCADE) |
| `orders` | Online orders with status, payment | `store_id` → `stores`, `customer_id` → `profiles` |
| `order_items` | Line items per order | `order_id` → `orders` (CASCADE), `product_id` → `products` (SET NULL) |
| `sales_transactions` | POS in-person transactions | `store_id` → `stores`, `seller_id` → `profiles` |
| `sales_transaction_items` | Line items per POS transaction | `transaction_id` → `sales_transactions` (CASCADE), `product_id` → `products` (SET NULL) |
| `customization_requests` | Bespoke footwear requests | `customer_id` → `profiles`, `store_id` → `stores` |
| `store_follows` | Customer store follows | `user_id` + `store_id` (composite PK) |
| `story_entries` | Store workshop stories | `store_id` → `stores` (CASCADE) |
| `notifications` | User notifications | (not yet wired) |

### FK Delete Rules (Critical — Don't Change)

| Table | Column | Rule |
|-------|--------|------|
| `order_items` | `product_id` | SET NULL |
| `sales_transaction_items` | `product_id` | SET NULL |
| `customization_requests` | `base_product_id` | SET NULL |
| `inventory` | `product_id` | CASCADE |
| `product_variants` | `product_id` | CASCADE |
| `product_images` | `product_id` | CASCADE |
| `product_customizations` | `product_id` | CASCADE |

### RLS Policy Matrix

| Table | Customer | Seller | Admin |
|-------|----------|--------|-------|
| `profiles` | Read all, Update own | Read all, Update own | Read all, Update any |
| `products` | Read all | Read all, CRUD own store | Read all, CRUD any |
| `orders` | Read/Insert own | Read all, Update status | Read all, Update status |
| `customizations` | Read/Insert own | Read all, Update status | Read all, Update any |
| `stores` | Read all | CRUD own store | CRUD any |
| `store_follows` | Read/Insert/Delete own | — | — |
| `story_entries` | Read all | — | CRUD any |
| `products` DELETE | — | `auth.uid() = seller_id` | `current_user_role() = 'admin'` |

### Design System Quick Reference

| Token | Value | Usage |
|-------|-------|-------|
| Primary (Burnished Clay) | `#8B5A2B` | Buttons, active states, brand accent |
| Secondary (Carob Dark) | `#3B2314` | Text, icons, sidebar background |
| Accent (Celadon Teal) | `#4ECDC4` | AR mode, CTAs, highlights |
| Surface Light (Off-White Suede) | `#F5F0EB` | Backgrounds |
| Success (Olive Stitch) | `#6B8F47` | Success states |
| Error (Crimson Welt) | `#D64545` | Error states |
| Border Gray | `#D2C7BC` | Borders, dividers |
| Headlines | Playfair Display | Titles, headings |
| Body | DM Sans | Body text, labels, buttons |
| Monospace | JetBrains Mono | Codes, IDs, timestamps |
| Card radius | 16px | Cards |
| Button radius | 12px | Buttons and chips |

---

## Appendix: Bug Fix History

### June 28, 2026
- Product hard delete & auto-deactivation implemented
- Seller dashboard wired to real Supabase data
- Reports screen wired to real data
- Product delete silently failing fixed (missing RLS DELETE policy + FK constraints + missing await)

### June 30, 2026
- **Login freeze when switching accounts** — 5 root causes fixed together (AuthProvider state reset, AuthService session-clear, AuthGate routing, biometric clear, isLoading flag)
- **Navigator stack conflict** — LoginScreen pushed via Navigator.pushReplacement created disconnected stack layer; fixed by returning widgets directly from build()
- **Product size selector empty** — inventory table was never written; added `_syncInventoryFromVariants()`, added `inventory(*)` to read queries, added `_buildSizesMap()` helper
- Profile fetch timeout (12s) added
- Offline detection added
- Size selector loading skeleton added

### July 2, 2026
- **Product variants missing from main query** — added `product_variants(size, stock)` to `fetchProducts()`
- **Poor error messages on size selector** — distinguishes "loading" vs "no sizes available"
- **Blank white cart screen** — `SolePrimaryButton` used `SizedBox(width: double.infinity)` inside a `Row` without `Expanded`, causing RenderBox layout failure. Added `expandToFill` parameter.

---

*SoleVision v1.1.0 — Handoff documentation created July 2, 2026*
