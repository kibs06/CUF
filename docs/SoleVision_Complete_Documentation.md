# SoleVision — Complete Project Documentation

**Version:** 2.0.0  
**Last Updated:** July 4, 2026  
**Platform:** Flutter (Mobile) + React (Admin Portal)  
**Backend:** Supabase (PostgreSQL + Auth + Storage + RLS)  
**Target Market:** Artisan footwear retail — Carcar City, Cebu, Philippines  
**Currency:** Philippine Peso (₱)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Tech Stack](#2-tech-stack)
3. [Architecture](#3-architecture)
4. [Database Schema](#4-database-schema)
5. [User Roles & Permissions](#5-user-roles--permissions)
6. [Mobile App (Flutter)](#6-mobile-app-flutter)
7. [Admin Portal (React)](#7-admin-portal-react)
8. [Services Layer](#8-services-layer)
9. [State Management](#9-state-management)
10. [Data Flow Patterns](#10-data-flow-patterns)
11. [Authentication & Security](#11-authentication--security)
12. [UI Design System](#12-ui-design-system)
13. [Feature Status](#13-feature-status)
14. [Known Bugs & Open Issues](#14-known-bugs--open-issues)
15. [Complete Bug Fix History (Chronological)](#15-complete-bug-fix-history)
16. [Critical Technical Debt](#16-critical-technical-debt)
17. [Future Roadmap](#17-future-roadmap)
18. [Setup & Installation](#18-setup--installation)
19. [Key Files Reference](#19-key-files-reference)
20. [SQL Migrations Reference](#20-sql-migrations-reference)
21. [Investigation Narratives](#21-investigation-narratives)
22. [Appendix: API Examples](#22-appendix-api-examples)

---

## 1. Project Overview

SoleVision is a multi-role marketplace connecting **customers**, **sellers** (artisans), and **admins** for handcrafted shoe retail in Carcar City, Cebu.

| Role | Primary Use |
|------|-------------|
| **Customer** | Browse products, place orders, track deliveries, request custom footwear |
| **Seller** | Manage store/inventory, process orders, run POS for walk-in sales |
| **Admin** | Approve sellers, monitor products, view analytics, manage users |

**Core Features:**
- Multi-store marketplace with follow/unfollow
- Point-of-Sale (POS) for in-person transactions (cash, GCash, card)
- Custom shoe orders (color, material, special requests)
- Real-time order tracking (pending → placed → preparing → ready → received)
- Biometric login (fingerprint/face)
- Admin analytics dashboard (revenue, orders, trends, top products)
- AR shoe fitting (placeholder — not yet functional)

---

## 2. Tech Stack

### Mobile App (Flutter)
| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | Flutter (Dart) | SDK ^3.12.1 |
| State Management | Provider | ^6.1.2 |
| Backend | Supabase Flutter SDK | ^2.10.3 |
| Typography | Google Fonts | ^6.2.1 (Playfair Display, DM Sans, JetBrains Mono) |
| Image Handling | cached_network_image, image_picker | ^3.4.1, ^1.1.2 |
| SVG | flutter_svg | ^2.0.10 |
| Loading | shimmer | ^3.0.0 |
| Local Storage | shared_preferences, flutter_secure_storage | ^2.2.3, ^9.0.0 |
| Biometrics | local_auth | ^2.2.0 |

### Admin Portal (React)
| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | React | ^18.3.1 |
| Bundler | Vite | ^6.2.2 |
| Routing | React Router DOM | ^6.30.0 |
| State/Data | TanStack React Query | ^5.67.2 |
| Backend | Supabase JS SDK | ^2.49.1 |
| Styling | Tailwind CSS | ^3.4.17 |
| Charts | Recharts | ^2.15.1 |
| Icons | Lucide React | ^1.21.0 |

### Backend (Supabase)
| Component | Technology |
|-----------|-----------|
| Database | PostgreSQL with Row Level Security (RLS) |
| Auth | Supabase Auth (email/password, JWT) |
| Storage | Supabase Storage (avatars, product-images, store-assets) |
| Realtime | Available but NOT yet integrated |
| Edge Functions | Available but unused |

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Supabase Cloud                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐ │
│  │   Auth   │  │ Postgres │  │  Storage   │  │ Realtime │ │
│  │ (JWT)   │  │   (RLS)  │  │ (images)   │  │ (unused) │ │
│  └────┬─────┘  └────┬─────┘  └─────┬──────┘  └──────────┘ │
└───────┼──────────────┼──────────────┼───────────────────────┘
        │              │              │
   ┌────┴────┐    ┌────┴────┐    ┌───┴────┐
   │ Flutter │    │ React   │    │ Admin  │
   │ Mobile  │    │  Web    │    │ Portal │
   └─────────┘    └─────────┘    └────────┘
```

Both Flutter app and React admin portal connect to the **same Supabase project**. All data access governed by **Row Level Security (RLS)**.

**Key Architectural Decisions:**
- `store_id` is a direct column on `orders` (not joined via products) — simpler and avoids extra joins for RLS
- Two-tier inventory: `product_variants` (granular per size+color) + `inventory` (aggregated per size)
- Services throw exceptions; Providers catch and set `_errorMessage` for the UI
- All storage buckets are public (product images, avatars, store assets are not sensitive)

**⚠️ Schema Drift Warning:** `supabase/schema.sql` is the original schema. The live database has evolved significantly (UUID PKs, additional tables, removed columns). **Always refer to the docs, not `schema.sql`.**

---

## 4. Database Schema

### 4.1 Table Overview

| Table | Purpose | Key Relationships |
|-------|---------|-------------------|
| `profiles` | Users with roles + seller_status | FK → `auth.users` (CASCADE) |
| `stores` | Artisan stores with branding | `owner_id` → `profiles` |
| `products` | Products with price, category, flags | `store_id` → `stores`, `seller_id` → `profiles` |
| `product_variants` | Stock per size+color with pricing | `product_id` → `products` (CASCADE) |
| `inventory` | Aggregated stock per size | `product_id` → `products` (CASCADE), PK: `(product_id, size)` |
| `product_images` | Product photos with display order | `product_id` → `products` (CASCADE) |
| `product_customizations` | Customization options per product | `product_id` → `products` (CASCADE) |
| `orders` | Online orders with status, payment | `store_id` → `stores`, `customer_id` → `profiles` |
| `order_items` | Line items per order | `order_id` → `orders` (CASCADE), `product_id` → `products` (SET NULL) |
| `sales_transactions` | POS in-person transactions | `store_id` → `stores`, `seller_id` → `profiles` |
| `sales_transaction_items` | Line items per POS transaction | `transaction_id` → `sales_transactions` (CASCADE), `product_id` → `products` (SET NULL) |
| `cart_items` | Persistent server-side cart | `user_id` → `profiles` (CASCADE), `product_id` → `products` (CASCADE), `variant_id` → `product_variants` (SET NULL) |
| `customization_requests` | Bespoke footwear requests | `customer_id` → `profiles`, `store_id` → `stores`, `base_product_id` → `products` (SET NULL) |
| `store_follows` | Customer store follows | Composite PK: `(user_id, store_id)` |
| `story_entries` | Store workshop stories | `store_id` → `stores` (CASCADE) |
| `notifications` | User notifications | (not yet wired) |

### 4.2 Important Schema Notes

- `story_entries` has **NO `title` column** (removed from live DB — do not reference in queries)
- `orders.store_id` is a direct column (not joined via products)
- `inventory` is synced from `product_variants` via `_syncInventoryFromVariants()` — one row per unique size, stock summed across colors
- `is_active` on products is auto-managed based on inventory levels
- `cart_items` has a `size` column (added July 4, 2026 via migration)
- Products table PK is `TEXT` (UUID stored as text, not native UUID)

### 4.3 FK Delete Rules (CRITICAL — Do Not Change)

| Table | Column | Rule | Reason |
|-------|--------|------|--------|
| `order_items` | `product_id` | SET NULL | Preserve order history when product deleted |
| `sales_transaction_items` | `product_id` | SET NULL | Preserve POS history when product deleted |
| `customization_requests` | `base_product_id` | SET NULL | Preserve request history when product deleted |
| `inventory` | `product_id` | CASCADE | Clean up when product deleted |
| `product_variants` | `product_id` | CASCADE | Clean up when product deleted |
| `product_images` | `product_id` | CASCADE | Clean up when product deleted |
| `product_customizations` | `product_id` | CASCADE | Clean up when product deleted |
| `cart_items` | `product_id` | CASCADE | Clean up when product deleted |

### 4.4 DB Triggers

Two Postgres trigger functions automatically decrement inventory on order/sale:

- **`decrement_inventory_on_order()`** — fires on `order_items` INSERT
- **`decrement_inventory_on_sale()`** — fires on `sales_transaction_items` INSERT

Both normalize size via `regexp_replace(size, '\\D', '', 'g')` before comparing against `inventory.size` (to handle "EU40" vs "40" format mismatch). Both have `SECURITY DEFINER` (added July 4, 2026) to bypass RLS when the calling user is a customer.

### 4.5 Seed Data

Three initial stores:
1. **Valladolid Leather Co.** — "Handcrafted footwear since 1992" (Valladolid, Carcar City)
2. **Carcar Sole Works** — "Where tradition meets comfort" (Poblacion, Carcar City)
3. **Cebu Heritage Shoes** — "Crafted with Cebuano pride" (Carcar City, Cebu) — initially closed

---

## 5. User Roles & Permissions

### RLS Policy Matrix

| Table | Customer | Seller | Admin |
|-------|----------|--------|-------|
| `profiles` | Read all, Update own | Read all, Update own | Read all, Update any |
| `products` | Read all | Read all, CRUD own store | Read all, CRUD any |
| `products` DELETE | — | `auth.uid() = seller_id` | `current_user_role() = 'admin'` |
| `orders` | Read/Insert own | Read all, Update status | Read all, Update status |
| `orders` DELETE | `auth.uid() = customer_id AND status = 'pending'` | — | — |
| `order_items` | Follow order access | Follow order access | Follow order access |
| `customizations` | Read/Insert own | Read all, Update status | Read all, Update any |
| `stores` | Read all | CRUD own store | CRUD any |
| `store_follows` | Read/Insert/Delete own | — | — |
| `story_entries` | Read all | — | CRUD any |
| `cart_items` | CRUD own | — | — |
| `sales_transactions` | — | Read/Create own store | Read all |
| `inventory` | Read all | CRUD own store | CRUD any |
| `product_variants` | Read all | CRUD own store | CRUD any |

### Seller Approval Flow

1. User registers with "Apply as a seller" toggle → `seller_status = 'pending'`
2. User sees "Pending Approval" screen
3. Admin reviews in admin portal → Approve or Reject
4. On approval: `role` → `seller`, `seller_status` → `approved`

---

## 6. Mobile App (Flutter)

### 6.1 Navigation Flow

```
SplashScreen (2s animated logo)
  └→ AuthGate (StreamBuilder on auth state)
      ├→ OnboardingScreen (first-time users)
      ├→ LoginScreen / RegisterScreen
      ├→ CustomerShell (customer role)
      ├→ SellerShell (seller role, approved)
      ├→ AdminShell (admin role)
      └→ PendingApprovalScreen (seller_status = 'pending')
```

### 6.2 Screen Architecture

#### Customer Shell
| Tab | Screen | Description |
|-----|--------|-------------|
| Home | `CustomerHomeScreen` | Featured products, category filtering, search |
| Store | `StoreScreen` | Multi-store discovery, follow/unfollow |
| Product Detail | `ProductDetailScreen` | Images, size selection, add to cart, customization |
| Cart | `CartScreen` | Quantity controls, per-store grouping, ₱100 delivery |
| Checkout | `CheckoutScreen` | Order summary, delivery details, payment, stock validation |
| Orders | `OrdersScreen` | Order history with status tracking |
| Profile | `ProfileScreen` | Account settings, avatar, logout |

#### Seller Shell
| Tab | Screen | Description |
|-----|--------|-------------|
| Dashboard | `SellerDashboardScreen` | Today's sales, weekly/monthly trends, store metrics |
| POS | `POSScreen` | Quick product selection, size/quantity, payment processing |
| Products | `ManageProductsScreen` | Add/edit/delete products with images + variants |
| Orders | `ManageOrdersScreen` | View and update order statuses |
| Reports | `ReportsScreen` | Weekly/monthly sales, top products, week-over-week comparison |
| More | `SellerMoreScreen` | Store management, inventory, custom orders |

#### Admin Shell
| Tab | Screen | Description |
|-----|--------|-------------|
| Dashboard | `AdminDashboardScreen` | Platform-wide stats |
| Users | `ManageUsersScreen` | User management & role changes |
| Requests | `SellerApprovalScreen` | Approve/reject seller applications |
| Monitor | `MonitorProductsScreen` | Product catalog oversight |
| Profile | `ProfileScreen` | Account settings |

### 6.3 Services (Singletons)

| Service | File | Responsibility |
|---------|------|---------------|
| `SupabaseService` | `supabase_service.dart` | Legacy general CRUD, `createOrder()`, `fetchProducts()` |
| `AuthService` | `auth_service.dart` | Auth: sign in (with session-clear), sign up, profile fetch (5 retries) |
| `ProductService` | `product_service.dart` | Product CRUD, image upload, variants, inventory sync, `syncProductActiveStatus()` |
| `OrderService` | `order_service.dart` | Order placement, store order filtering, recent orders |
| `StoreService` | `store_service.dart` | Store CRUD, image upload, follow/unfollow, story entries |
| `SalesService` | `sales_service.dart` | POS transactions, daily/weekly/monthly revenue, dashboard metrics |
| `CartService` | `cart_service.dart` | Cart CRUD, `validateCartForCheckout()`, `fetchCart()` |
| `ProfileService` | `profile_service.dart` | Avatar picking and upload |
| `UploadService` | `upload_service.dart` | Generic file upload/delete for Supabase Storage |
| `BiometricService` | `biometric_service.dart` | Biometric auth, credential storage |

**Pattern:** Services throw exceptions → Providers catch and set `_errorMessage` for UI.

---

## 7. Admin Portal (React)

### 7.1 Routes

| Route | Page | Description |
|-------|------|-------------|
| `/login` | Login | Admin-only authentication |
| `/` | Dashboard | Stats cards, recent applications, recent orders, sparkline |
| `/users` | Users | Role-separated tabs (All/Customers/Sellers/Admins), search, detail modals |
| `/seller-applications` | Seller Applications | Approve/reject with optional reason |
| `/products` | Products | Grouped by store with banners |
| `/orders` | Orders | Status updates |
| `/analytics` | Analytics | 6 charts: orders, revenue, users (line), status (pie), top products (bar), seller trends (stacked bar) |
| `/settings` | Settings | Admin profile & password |

### 7.2 Component Architecture

```
src/
├── components/
│   ├── layout/    → AppLayout, ProtectedRoute, Sidebar, TopBar
│   ├── products/  → AddProductModal, ProductCard, ProductDetailModal, StoreGroup
│   ├── ui/        → Badge, DataTable, Modal, Skeleton, StatCard, Toast
│   └── users/     → UserDetailModal, UserRow, UserSection
├── hooks/         → useAuth, useDashboard, useUsers, useOrders, useProducts, useSellerApplications, useAnalytics
├── lib/           → constants.js, supabase.js
└── pages/         → Dashboard, Users, SellerApplications, Products, Orders, Analytics, Settings, Login
```

### 7.3 Key Patterns

- **TanStack React Query** for all server data (automatic caching, refetching, optimistic updates)
- **ProtectedRoute** wraps all routes except `/login`
- **Recharts** for all analytics charts
- **Tailwind CSS** for styling (no CSS-in-JS)

---

## 8. Services Layer

### Key Data Flow Patterns

#### Revenue Calculation (CRITICAL — don't break)
Revenue ALWAYS combines **both** `orders` (online, `payment_status = 'paid'`, `status != 'cancelled'`) **and** `sales_transactions` (POS). Neither source alone is complete.

#### Store Order Filtering (3-step chain)
1. `products` WHERE `store_id = X` → get product IDs
2. `order_items` WHERE `product_id IN [product IDs]` → get order IDs
3. `orders` WHERE `id IN [order IDs]` → final orders

#### Inventory Sync
- `product_variants` = source of truth for stock per size+color
- `inventory` = derived/aggregated table, one row per size (stock summed across colors)
- `_syncInventoryFromVariants()` runs after every variant create/update in `ProductService`

#### Size Resolution (used in createOrder, recordSale, validateCartForCheckout)
1. **Exact match** — cart size matches inventory size
2. **Numeric match** — strip "EU"/"US" prefix, then compare
3. **Fallback** — first available inventory size

This logic is shared via `resolveInventoryStock()` in `lib/utils/cart_helpers.dart`.

---

## 9. State Management

### Provider Architecture (Mobile)

| Provider | Scope | Key State |
|----------|-------|-----------|
| `AuthProvider` | App-wide | `_currentUser`, `_profile`, `_isLoading`, `_errorMessage` |
| `ProductProvider` | Product browsing | `_products[]`, `_selectedCategory`, `categories` |
| `CartProvider` | Shopping cart | `_items{}` (keyed by `productId-size-color`), `_selectedKeys`, `subtotal`, `deliveryFee` |
| `OrderProvider` | Orders & admin | `_orders[]`, `_customizations[]`, `_profiles[]`, `_stockError` |

### Cart Logic
- Items keyed by `productId-size-color`
- Flat ₱100 delivery fee for local Cebu area
- Auto-select new items for checkout
- Background Supabase sync (optimistic updates with rollback on failure)
- `clearCart()` available for post-order cleanup

---

## 10. Data Flow Patterns

### 10.1 Add to Cart → Checkout → Order

```
PRODUCT DETAIL SCREEN
  _buildSizesMap() merges inventory + product_variants → shows size chips
  _addToCart() → looks up variantId from product_variants by size+color
  → calls cart.addToCart(size, variantId, additionalPrice)

CART PROVIDER
  addToCart() stores locally + background sync to Supabase cart_items
  → cart_items stores size column directly
  → variant_id may be null for AR-fitting or legacy products

CHECKOUT SCREEN
  _validateCart() → CartService.validateCartForCheckout()
    → fetchCart() with inventory fallback for null variants
    → batch-fetches inventory for authoritative stock
    → shows banners for out-of-stock / insufficient-stock items
  _submitCheckout() → re-validates → orderProvider.placeOrder()

ORDER CREATION (createOrder in SupabaseService)
  1. Look up store_id from first product
  2. INSERT INTO orders
  3. Batch-fetch ALL inventory for every product in order (single query)
  4. For EACH item: resolve size from inventory → INSERT INTO order_items
  5. DB trigger fires on order_items INSERT → decrements inventory.stock
  6. If trigger fails → StockUnavailableException with friendly message
  7. On failure: orphaned orders row + inserted order_items are rolled back

POST-ORDER
  Cart items removed from cart (local + server-side)
  Confirmation screen shown (step 1)
  "Track My Order" → OrderTrackingScreen
  "Back to Home" → popUntil first route
```

### 10.2 POS Sale Flow

```
POSSCREEN
  Seller selects product → size → quantity → payment method
  → calls orderProvider.placeOrder() for the order record
  → calls salesService.recordSale() for the POS transaction record

recordSale (sales_service.dart)
  1. Resolves sizes from inventory (same normalization as createOrder)
  2. INSERT INTO sales_transactions
  3. INSERT INTO sales_transaction_items (fires decrement_inventory_on_sale trigger)
```

### 10.3 The Two Stock Tables

| Table | Primary Key | Used By | Notes |
|-------|-------------|---------|-------|
| `inventory` | `(product_id, size)` | DB triggers, `createOrder()`, `validateCartForCheckout()`, `_buildSizesMap()` | Aggregated stock by size (summed across colors). **Authoritative source.** |
| `product_variants` | `(id)` with `(product_id, size, color)` | `fetchCart()` JOIN, `addToCart()` variant lookup, seller dashboard | Per-variant stock with color. May have stale/0 values. |

**Known issue:** `product_variants.stock` can be 0 while `inventory.stock` is 100+. `validateCartForCheckout()` uses `inventory` as authoritative source (fixed July 3, 2026).

---

## 11. Authentication & Security

### Authentication Flow
1. **Registration:** Email/password → Supabase Auth → Profile row created via DB trigger or manual upsert
2. **Login:** Email/password → Supabase Auth JWT → Profile fetch with retry (5 attempts, exponential backoff)
3. **Session restore:** `AuthGate` checks `currentSession` on app start
4. **Account switching:** Force sign-out of existing session before new `signIn()` (prevents silent rejection)

### Biometric Authentication
- `LocalAuthentication.canCheckBiometrics` + `isDeviceSupported()`
- Credentials stored in `FlutterSecureStorage` (encrypted)
- Cleared on logout to prevent cross-account bleed

### Security Measures
- **RLS on all tables** — data access enforced at database level
- **JWT-based auth** — Supabase manages token refresh
- **Admin-only policies** — gated by `role = 'admin'` check in RLS
- **FORCE sign-out before new sign-in** — prevents session bleed on account switch
- **Return widgets directly from `build()`** — prevents LoginScreen from becoming a disconnected stack layer

---

## 12. UI Design System

### Color Palette
| Name | Hex | Usage |
|------|-----|-------|
| Primary (Burnished Clay) | `#8B5A2B` | Buttons, active states, brand accent |
| Secondary (Carob Dark) | `#3B2314` | Text, icons, sidebar background |
| Accent (Celadon Teal) | `#4ECDC4` | AR mode, CTAs, highlights |
| Surface Light (Off-White Suede) | `#F5F0EB` | Backgrounds |
| Surface Dark (Midnight Canvas) | `#1A1208` | Dark mode / AR overlay |
| Success (Olive Stitch) | `#6B8F47` | Success states |
| Error (Crimson Welt) | `#D64545` | Error states |
| Border Gray | `#D2C7BC` | Borders, dividers |

### Typography
| Style | Font | Usage |
|-------|------|-------|
| Headlines | Playfair Display | Titles, headings, wordmarks |
| Body & Labels | DM Sans | Body text, labels, buttons |
| Monospace | JetBrains Mono | Codes, IDs, timestamps, size chips, prices |

### Visual Language
- Card radius: 16px
- Button radius: 12px
- Warm shadow: Primary-colored, 8% opacity, 12px blur
- Noise overlay: Organic texture via custom `_NoisePainter`

### Reusable Widgets (`lib/widgets/`)
`SoleCard`, `SolePrimaryButton`, `SoleTextField`, `SoleBottomNav`, `SoleBadge`, `SoleStatusChip`, `SoleMetricCard`, `SoleProductCard`, `SoleTimeline`, `ShimmerBox`, `EmptyStateWidget`, `ErrorRetryWidget`, `CartIconButton`, `ArViewPlaceholder`

### Seller Widgets (`lib/widgets/seller/`)
`SellerMetricCard`, `SellerProductRow`, `SellerOrderCard`, `SellerInventoryRow`, `SellerWeeklyBar`, `SellerSparkline`, `SellerStatusChip`, `SellerPaymentMethodPill`, `SellerAlertChip`

---

## 13. Feature Status

### Customer Features (all ✅)
- Registration, biometric login, onboarding
- Product browsing with category filtering and search
- Store discovery and follow/unfollow
- Product details with image gallery, size selection, add to cart
- Shopping cart with quantity controls, per-store grouping, ₱100 delivery
- Checkout with payment method selection + stock validation
- Order tracking with status timeline
- Custom shoe orders (color, material, special requests)
- Profile management, password reset
- Offline detection and connection retry
- Size selector with loading skeleton and "Only X left" low-stock labels

### Seller Features (all ✅)
- Store creation/editing with full branding
- Product CRUD with multi-image upload, variants, customizations
- Inventory management per product/size
- Auto-deactivation/activation based on stock
- Hard delete of products (with history preservation)
- Order management with status updates
- POS for walk-in transactions (cash, GCash, card)
- Sales tracking (today, weekly, monthly trends)
- Sales reports (weekly/monthly toggle, top 5 products, week-over-week comparison)
- Store stories

### Admin Features — Mobile (all ✅)
- Platform dashboard, user management, seller applications, product monitoring

### Admin Features — Web Portal (all ✅)
- Responsive sidebar, protected routes
- Dashboard with stat cards + sparkline
- Interactive analytics charts (6 chart types)
- User management with role-separated tabs
- Seller application management
- Product catalog grouped by store
- Order management

---

## 14. Known Bugs & Open Issues

### 🔴 Critical / High Priority

| Issue | Status | Notes |
|-------|--------|-------|
| **Non-numeric sizes break trigger normalization** | ⚠️ UNVERIFIED | The DB triggers use `regexp_replace(size, '\\D', '', 'g')` which strips all non-digits. If any product uses "S"/"M"/"L"/"One Size", this breaks. Verification query exists but has NOT been run. |
| **Duplicate product_variants rows** | ✅ Verified + cleanup script ready | Classic Derby Oxford confirmed to have duplicate rows. Cleanup script in `CHECKOUT_HARD_FIX_CLEANUP.sql` Step 2. |
| **Orphaned inventory rows** | ⚠️ UNVERIFIED | Backfill script in `CHECKOUT_HARD_FIX_CLEANUP.sql` Step 4. |
| **No git repository** | ⚠️ No version control | All changes are raw file modifications with no audit trail. |

### 🟡 Medium Priority

| Issue | Status | Notes |
|-------|--------|-------|
| **Schema drift: `supabase/schema.sql` is outdated** | Known | Live DB has evolved beyond the file. Always refer to docs. |
| **`isFollowing()` always returns `false`** | Stub | Synchronous method is a stub. Async `isFollowingAsync()` works. |
| **`SupabaseService` duplicates logic** | Tech debt | Some CRUD exists in both `SupabaseService` and focused services. |
| **CSV export is a stub** | Stub | Reports screen "Download" button shows SnackBar only. |
| **No unit tests** | Gap | `test/widget_test.dart` is default Flutter template — no actual tests exist. |

### 🟢 Low Priority

| Issue | Notes |
|-------|-------|
| AR fitting screen is a placeholder | `ArViewPlaceholder` widget exists, no real AR |
| No error boundary for admin portal | React app has no global error boundary |
| Debug prints may still be in production code | From debugging sessions |
| `story_entries.title` referenced in `schema.sql` but doesn't exist in live DB | Code correctly avoids it, but SQL file is misleading |
| `RadioListTile` deprecation warnings | 16 places in `product_detail_screen.dart` |
| `.withOpacity()` deprecation | Should use `.withValues()` |

---

## 15. Complete Bug Fix History (Chronological)

### June 28, 2026 — Product Hard Delete & Admin Data Wiring

**Problem:** Sellers couldn't delete products. Dashboard showed mock data. Reports were stubs.

**Root Causes & Fixes:**
1. **Product delete silently failing** — Missing DELETE RLS policy on `products` table. Supabase silently rejects deletes when no policy matches. FK constraints were `NO ACTION` blocking cascading deletes.
   - **Fix:** Added DELETE policies for sellers (`auth.uid() = seller_id`) and admins (`current_user_role() = 'admin'`). Changed FK constraints to `SET NULL` for history tables, `CASCADE` for child tables. Added missing `await` on `_removeStorageFile()`.
   - **Files:** `product_service.dart`, SQL policy additions

2. **Product hard delete & auto-deactivation** — Implemented permanent product deletion with history preservation. `is_active` auto-manages based on inventory levels.
   - **Files:** `product_service.dart`

3. **Seller dashboard wired to real Supabase data** — All metrics (today's revenue, weekly trends, bar chart, recent orders, store rating) now use real data. Revenue combines both `orders` (paid, non-cancelled) + `sales_transactions` (POS).
   - **Files:** `sales_service.dart`, `order_service.dart`, `seller_dashboard_screen.dart`

4. **Reports screen wired to real data** — Weekly sales total, 7-day bar chart, top 5 products by units sold — all real data via `SellerReportData` model.
   - **Files:** `seller_report_data.dart`, `sales_service.dart`, `reports_screen.dart`

---

### June 30, 2026 — Login Freeze & Size Selector

**Problem:** Login screen froze when switching accounts. Product size selector was empty. No offline detection.

**Root Causes & Fixes (5 root causes fixed together for login freeze):**
1. **Stale AuthProvider state** — `_currentUser` and `_profile` not cleared on logout, causing stale data on next login.
   - **Fix:** `logout()` clears all state + biometric credentials before signOut. `login()` clears stale state at start, uses `try/catch/finally` to guarantee `_isLoading` resets.
   - **Files:** `auth_provider.dart`

2. **Supabase auth stream race condition** — `signIn()` called `signOut()` first, which emitted a null auth state before the new sign-in completed, causing the auth stream to briefly show "logged out" and trigger navigation to login.
   - **Fix:** Removed pre-signOut in `signIn()` to avoid auth stream race condition.
   - **Files:** `auth_service.dart`

3. **AuthGate stale profile cache** — When auth stream emitted null user (during account switch), the profile cache retained the old user's data.
   - **Fix:** Added `_resetProfileCache()` to clear stale profile when auth stream emits null user.
   - **Files:** `auth_gate.dart`

4. **Biometric credentials cross-account bleed** — `FlutterSecureStorage` retained credentials from Account A when logging into Account B.
   - **Fix:** Cleared biometric credentials on logout.
   - **Files:** `biometric_service.dart`

5. **`_isLoading` flag stuck true** — If `signIn()` threw before the `finally` block, `_isLoading` remained true, preventing any further login attempts.
   - **Fix:** `try/catch/finally` pattern guarantees `_isLoading` resets.
   - **Files:** `auth_provider.dart`

**Navigator Stack Conflict:**
- `LoginScreen` was pushed via `Navigator.pushReplacement` creating a disconnected stack layer that couldn't be popped by StreamBuilder.
- **Fix:** Return widgets directly from `_FirstTimeOrLoginRouter.build()` instead of using navigator push.
- **Files:** `auth_gate.dart`

**Product Size Selector Empty:**
- `product_detail_screen.dart` read non-existent `widget.product['sizes']` key. `product_service.dart` never wrote to `inventory` table during create/update.
- **Fix:** Added `_syncInventoryFromVariants()` helper that groups variants by size, sums stock, replaces inventory rows. Added `inventory(*)` to all product read queries. Added `_buildSizesMap()` in product detail screen reading from both `inventory` and `product_variants`. Added `_fetchInventory()` fallback with shimmer loading skeleton.
- **Files:** `product_service.dart`, `product_detail_screen.dart`

**Other Improvements:**
- Profile fetch timeout (12s) with retry button
- Offline detection with "No Internet Connection" screen
- Size selector loading skeleton

---

### July 2, 2026 — Checkout Flow Overhaul

**Problem:** Checkout had multiple critical bugs — only first item received an order_items row, wrong pricing, fake order IDs, items vanished on checkout.

**Root Causes & Fixes:**
1. **Only first item received `order_items` row** — Old code called `placeOrder` per item in a loop but order creation only inserted one item.
   - **Fix:** Changed `placeOrder()` to accept a `List<Map<String, dynamic>> items` parameter. Order created ONCE with multiple `order_items` rows.
   - **Files:** `order_provider.dart`

2. **Wrong `unit_price`** — Calculated as `total / quantity` instead of using the actual item price.
   - **Fix:** Each `order_item` gets the correct `unit_price` from the item data.
   - **Files:** `supabase_service.dart`

3. **`cart.total` used instead of `selectedTotal`** — Selected items' total wasn't isolated.
   - **Fix:** `_submitCheckout()` uses `selectedTotal` for the order.
   - **Files:** `checkout_screen.dart`

4. **Items started deselected** — Customers had to manually re-select everything.
   - **Fix:** New cart items are auto-selected (`_selectedKeys.add(cartKey)`).
   - **Files:** `cart_provider.dart`

5. **Confirmation showed fake order ID** — Used a local variable instead of the real DB-generated ID.
   - **Fix:** Confirmation screen shows real order ID from DB.
   - **Files:** `checkout_screen.dart`

6. **"Track My Order" went nowhere** — Navigation to tracking screen was broken.
   - **Fix:** Working navigation to `OrderTrackingScreen` with real order data.
   - **Files:** `checkout_screen.dart`

7. **Products vanished on checkout** — Validation auto-removed items from cart.
   - **Fix:** Validation shows warnings instead of auto-removing items.
   - **Files:** `checkout_screen.dart`

**Additional Fixes:**
- Blank white cart screen — `SolePrimaryButton` used `SizedBox(width: double.infinity)` inside a `Row` without `Expanded`, causing RenderBox layout failure. Added `expandToFill` parameter.
- Product variants missing from main query — added `product_variants(size, stock)` to `fetchProducts()`.

---

### July 3, 2026 — Stock Validation & Error Handling

**Problem:** Raw PostgrestException shown to customers. Stock problems only caught at DB level after customer filled entire checkout form. No visual indication of low/out-of-stock items.

**Root Causes & Fixes:**

1. **Custom Exception** — Created `StockUnavailableException` with `productName`, `size`, `requestedQty`, `availableStock` fields and `friendlyMessage` getter.
   - **File:** `lib/exceptions/stock_unavailable_exception.dart` (NEW)

2. **Service Layer** — `createOrder()` catches `PostgrestException` with code `P0001` and throws `StockUnavailableException` instead. Size resolution overhaul: always resolves size from `inventory` table.
   - **File:** `lib/services/supabase_service.dart`

3. **Provider Layer** — Added `_stockError` field. `placeOrder()` catches `StockUnavailableException` separately with friendly messages. Never surfaces raw technical details.
   - **File:** `lib/providers/order_provider.dart`

4. **Pre-submission Validation** — `_validateCart()` checks live stock for every cart item on load. Shows out-of-stock and insufficient-stock banners. `_canSubmitOrder()` blocks button when items fail validation.
   - **File:** `lib/screens/customer/checkout_screen.dart`

5. **Cart Validation** — `validateCartForCheckout()` now passes `cartQuantity` and computes `insufficientStock`. Added inventory fallback for products without `product_variants` entries.
   - **File:** `lib/services/cart_service.dart`

6. **Product Detail** — Size chips show "Only X left" when stock ≤ 5.
   - **File:** `lib/screens/customer/product_detail_screen.dart`

**DB Trigger Exact-Match Bug (Finding #1):**
Two Postgres trigger functions did exact string equality on size. `inventory.size` stores bare numbers (`"40"`), while other parts of the system use prefixed sizes (`"EU40"`).
- **Fix:** Rewrote both trigger functions to normalize size via `regexp_replace(size, '\\D', '', 'g')` before comparing.
- **Deployed:** ✅ Live in production DB via `CREATE OR REPLACE FUNCTION`.

**Checkout Validation Stock Source (Finding #2):**
`validateCartForCheckout()` read stock from `product_variants.stock` instead of `inventory.stock`. When `variant_id` was null, `fetchCart()` substituted an arbitrary fallback size.
- **Fix:** `validateCartForCheckout()` now uses `inventory` as authoritative stock source via `resolveInventoryStock()` helper.
- **File:** `lib/utils/cart_helpers.dart` (NEW)

**AR Fitting Missing Variant Lookup (Finding #3):**
AR fitting screen's `_addToCart()` never performed variant lookup — called `cart.addToCart()` without `variantId` for every item.
- **Fix:** Added variant-lookup loop to `ar_fitting_screen.dart`'s `_addToCart()`, mirroring `product_detail_screen.dart`. Extracted shared `resolveVariant()` helper to `cart_helpers.dart`.
- **Files:** `lib/screens/customer/ar_fitting_screen.dart`, `lib/utils/cart_helpers.dart`

**Shared Helpers Extracted:**
- `resolveVariant()` — variant lookup by size+color
- `resolveInventoryStock()` — inventory stock resolution with logging
- `normalizeSize()` — strip alpha prefix from size strings
- **File:** `lib/utils/cart_helpers.dart` (NEW)

---

### July 4, 2026 — Root Cause Identification & True Fix

**Problem:** Five prior fix attempts targeted stock validation, size normalization, and order creation atomicity. The error persisted identically.

#### Phase 1: Diagnostic Elimination Test

**Method:** Created a diagnostic build that disabled both stock check paths:
- Path A: `validateCartForCheckout()` forced `isAvailable: true, stock=999` for all items
- Path B: `createOrder()` caught P0001 and continued instead of throwing
- Added comprehensive logging to capture exact payloads and raw PostgrestException details

**Result:** Error STILL appeared even with both paths disabled, proving the issue was in the DB trigger, not app logic.

#### Phase 2: Order Creation Atomicity Fix

**Problem:** `createOrder()` was non-atomic — `orders` row inserted first, then `order_items` in separate calls. When `order_items` insert failed, the `orders` row was orphaned with 0 items.

**Fix:**
- Added `_cleanupOrphanedOrder()` helper that deletes the orphaned `orders` row on failure
- Wrapped `order_items` insert loop in try/catch with batch rollback of inserted items
- Tracks `failingItem` for accurate `StockUnavailableException` (not `items.first`)
- Comprehensive logging: exact payload, raw PostgrestException details (code, message, details, hint)
- **File:** `lib/services/supabase_service.dart`

#### Phase 3: Verification Audit

**Finding:** Four consecutive fix attempts all failed because:
1. SQL migrations were NEVER executed against the live database
2. No fresh build was ever deployed (app running old binary)
3. No git repository existed — changes untrackable

**SQL migrations that were never applied:**
- Orphaned orders cleanup
- DELETE RLS policy on orders table
- `cart_items.size` column migration

#### Phase 4: TRUE ROOT CAUSE — RLS Blocks Trigger UPDATE

**Console Log Evidence:**
```
[STOCK-RESOLVE] ✅ Exact match: "41" → stock=46
[CHECKOUT-VALIDATE] → Classic Derby Oxford: stock=46, isActive=true, isAvailable=true
[ORDER-CREATE] Orders row inserted: id=f8adaf22-...
[ORDER-CREATE] Inserting order_item: {product_id: ..., size: 41, quantity: 1, unit_price: 1299.0}
[ORDER-CREATE] order_item INSERT FAILED: PostgrestException(message: Insufficient stock for product ... size 41, code: P0001)
```

**Root Cause:** The `decrement_inventory_on_order()` trigger function ran WITHOUT `SECURITY DEFINER`, meaning it executed as the calling user (the customer). The `inventory` table has RLS policies that only allow sellers and admins to UPDATE rows. When a customer places an order, the trigger's UPDATE on inventory is silently blocked by RLS (matching 0 rows), causing the function to raise 'Insufficient stock' — even when the app correctly sees stock=46 via its SELECT query (which has a "viewable by everyone" policy).

**Why prior fixes missed this:** Five fix attempts targeted `validateCartForCheckout()`, app-layer inventory logic, size normalization, and order creation atomicity. All were red herrings. The app's stock validation was always correct. The error came from the database trigger, which appeared to be a stock problem but was actually an RLS permission problem.

**Fix:** Added `SECURITY DEFINER` to both `decrement_inventory_on_order()` and `decrement_inventory_on_sale()`.
- **File:** `supabase/migrations/20260704_fix_trigger_security_definer.sql`

#### Phase 5: Add-to-Cart Fix

**Problem:** After the SECURITY DEFINER fix, adding products to cart failed with: `Could not find the 'size' column of 'cart_items' in the schema cache`

**Root Cause:** The `cart_items` table was missing the `size` column. The migration `20260703_add_cart_items_size.sql` existed on disk but was never applied to the live database.

**Fix:** User ran the migration in Supabase SQL Editor:
```sql
ALTER TABLE public.cart_items ADD COLUMN IF NOT EXISTS size TEXT;
```

#### Phase 6: Documentation

- Updated `docs/project_doc.md` Sections 14 and 15 with the true root cause
- Created `docs/VERIFICATION_AUDIT_JULY_4_2026.md` with full audit report
- Created `supabase/migrations/20260704_fix_trigger_security_definer.sql`
- Created `supabase/migrations/20260704_add_orders_delete_policy.sql`
- Created `docs/CLEANUP_orphaned_zero_item_orders.sql`
- Created this document: `docs/SoleVision_Complete_Documentation.md`

---

## 16. Critical Technical Debt

### Must Fix Before Production

| Item | Impact | Effort |
|------|--------|--------|
| **Set up git repository** | No version control — changes untrackable, no audit trail | Small |
| **Run all pending SQL migrations** | Schema drift between code and live DB | Small |
| **Run verification SQL queries** | Non-numeric sizes could silently break all orders | Small |
| **Add unit tests** | No test coverage at all | Large |
| **Update `supabase/schema.sql`** | Misleads every new contributor | Small |

### Should Fix Soon

| Item | Impact |
|------|--------|
| Fix duplicate `product_variants` rows | Data integrity, confusing seller dashboard |
| Fix `isFollowing()` stub | Always returns false synchronously |
| Remove debug prints from production code | Noise in logs |
| Add `.env.example` for admin portal | Onboarding friction |
| Integrate Supabase Realtime | Users must pull-to-refresh for order updates |

---

## 17. Future Roadmap

### High Priority
- [ ] Real-time order updates via Supabase Realtime subscriptions
- [ ] Push notifications for order status changes
- [ ] Payment gateway integration (GCash API, PayMongo for Philippines)
- [ ] Product image gallery with zoom and carousel
- [ ] Search with fuzzy matching and filters (category, price, store, size)

### Medium Priority
- [ ] AR shoe fitting with real 3D models (currently placeholder)
- [ ] Detailed seller analytics dashboard
- [ ] Customer reviews and ratings system
- [ ] Wishlist / favorites feature
- [ ] Store following feed with product updates

### Low Priority
- [ ] Multi-language support (Filipino, Cebuano)
- [ ] Offline mode with local caching
- [ ] Seller-to-customer chat
- [ ] Admin role delegation
- [ ] PDF/CSV export for reports

---

## 18. Setup & Installation

### Prerequisites
- Flutter SDK 3.x
- Node.js 18+
- Supabase account and project
- Google Chrome (for admin portal)

### Flutter Mobile App
```bash
cd app
flutter pub get
# Credentials hardcoded in lib/constants/app_constants.dart
flutter run
```

### React Admin Portal
```bash
cd admin-portal
npm install
# Create .env with VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm run dev
# Opens at http://localhost:5173
```

### Database Setup
1. Create Supabase project
2. **Do NOT use `supabase/schema.sql` directly** — it's outdated
3. Use the schema from Section 4 of this document as reference
4. Create storage buckets: `avatars`, `product-images`, `store-assets` (all public)
5. Run `docs/debug/inventory_backfill.sql` once to populate inventory for existing products
6. Add RLS DELETE policies for `products` table
7. Deploy the updated DB triggers for size normalization + SECURITY DEFINER
8. Run `supabase/migrations/20260703_add_cart_items_size.sql` to add `size` column to `cart_items`
9. Run `supabase/migrations/20260704_add_orders_delete_policy.sql` for orphan cleanup
10. Run `supabase/migrations/20260704_fix_trigger_security_definer.sql` for trigger RLS fix

### Environment Variables

| Variable | Location | Description |
|----------|----------|-------------|
| `AppConstants.url` | `lib/constants/app_constants.dart` | Supabase project URL (hardcoded) |
| `AppConstants.anonKey` | `lib/constants/app_constants.dart` | Supabase anon key (hardcoded) |
| `VITE_SUPABASE_URL` | `admin-portal/.env` | Same Supabase URL |
| `VITE_SUPABASE_ANON_KEY` | `admin-portal/.env` | Same anon key |

---

## 19. Key Files Reference

### Critical Configuration
| File | Purpose |
|------|---------|
| `lib/constants/app_constants.dart` | Supabase creds, color palette, typography, visual rules, role/status constants |
| `admin-portal/src/lib/supabase.js` | Admin portal Supabase client |
| `admin-portal/src/lib/constants.js` | Admin portal roles, statuses, formatting utilities |

### Key Service Files
| File | Purpose |
|------|---------|
| `lib/services/supabase_service.dart` | `createOrder()` with orphan cleanup, `fetchProducts()`, legacy CRUD |
| `lib/services/product_service.dart` | Product CRUD, `_syncInventoryFromVariants()`, `syncProductActiveStatus()` |
| `lib/services/order_service.dart` | Order placement, store order filtering |
| `lib/services/sales_service.dart` | POS transactions, revenue calculations |
| `lib/services/cart_service.dart` | Cart CRUD, `validateCartForCheckout()`, `fetchCart()` |

### Key Helper Files
| File | Purpose |
|------|---------|
| `lib/utils/cart_helpers.dart` | Shared `resolveVariant()`, `resolveInventoryStock()`, `normalizeSize()` |

### Key Provider Files
| File | Purpose |
|------|---------|
| `lib/providers/auth_provider.dart` | Auth state with login/logout/profile |
| `lib/providers/cart_provider.dart` | Cart logic with optimistic updates |
| `lib/providers/order_provider.dart` | Orders with stock error handling |

### Key Screen Files
| File | Purpose |
|------|---------|
| `lib/screens/customer/checkout_screen.dart` | Full checkout with validation, error handling, cart clearing |
| `lib/screens/customer/product_detail_screen.dart` | Product detail with `_buildSizesMap()`, `_addToCart()` |
| `lib/screens/customer/ar_fitting_screen.dart` | AR fitting with shared `resolveVariant()` helper |
| `lib/screens/seller/pos_screen.dart` | Point-of-sale for in-person transactions |

### Documentation Files
| File | Purpose |
|------|---------|
| `docs/SoleVision_Complete_Documentation.md` | **This document** — comprehensive project reference |
| `docs/project_doc.md` | Project documentation v1.2.0 with fix history |
| `docs/PROJECT_HANDOFF.md` | Project handoff with decisions, rationale, known issues |
| `docs/SESSION_DOCUMENTATION_JULY_3_2026.md` | Full investigation narrative for checkout bugs |
| `docs/SESSION_LOG_JULY_2_3_2026.md` | Session log with all July 2-3 changes |
| `docs/VERIFICATION_AUDIT_JULY_4_2026.md` | Verification audit proving fixes were never deployed |
| `docs/createOrder_function_reference.md` | Annotated `createOrder()` with flow diagram |
| `docs/addToCart_and_fetchCart_reference.md` | Add-to-cart flow + fetchCart inventory fallback |
| `docs/ar_fitting_addToCart_reference.md` | AR fitting `_addToCart()` analysis |
| `docs/checkout_submit_analysis.md` | `_submitCheckout()` analysis |
| `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql` | SQL verification queries |
| `docs/CLEANUP_orphaned_zero_item_orders.sql` | Cleanup script for broken orders |

### SQL Migrations
| File | Purpose | Applied? |
|------|---------|----------|
| `supabase/migrations/20260702_notifications.sql` | Notifications table, RLS, triggers | ✅ Live |
| `supabase/migrations/20260703_add_cart_items_size.sql` | Add `size` column to `cart_items` | ✅ Applied July 4 |
| `supabase/migrations/20260704_add_orders_delete_policy.sql` | DELETE RLS policy on `orders` | ✅ Applied July 4 |
| `supabase/migrations/20260704_fix_trigger_security_definer.sql` | SECURITY DEFINER on trigger functions | ✅ Applied July 4 |

---

## 20. SQL Migrations Reference

### All Migrations (Chronological)

| # | File | Date | Purpose | Status |
|---|------|------|---------|--------|
| 1 | `20260702_notifications.sql` | July 2 | Notifications table + RLS + triggers | ✅ Live |
| 2 | `20260703_add_cart_items_size.sql` | July 3 | Add `size TEXT` column to `cart_items` + backfill | ✅ Applied July 4 |
| 3 | `20260704_add_orders_delete_policy.sql` | July 4 | DELETE RLS policy on `orders` for pending orders | ✅ Applied July 4 |
| 4 | `20260704_fix_trigger_security_definer.sql` | July 4 | Add `SECURITY DEFINER` to inventory trigger functions | ✅ Applied July 4 |

### Manual SQL (One-time cleanup)

| File | Purpose |
|------|---------|
| `docs/CLEANUP_orphaned_zero_item_orders.sql` | Delete orphaned 0-item orders from failed attempts |
| `docs/debug/inventory_backfill.sql` | Populate inventory from existing product_variants |
| `docs/debug/cart_items_migration.sql` | Cart items table setup |
| `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql` | Post-fix verification queries |

---

## 21. Investigation Narratives

### The Checkout Bug Investigation (July 3-4, 2026)

This section provides the detailed narrative of the most complex investigation in the project — the false "is no longer available" error that persisted across five fix attempts.

#### Timeline

| Date | Action | Result |
|------|--------|--------|
| July 3 (morning) | Fix #1: DB trigger exact-match normalization | Trigger fixed, but error persisted |
| July 3 (midday) | Fix #2: `validateCartForCheckout()` reads from inventory | Validation fixed, but error persisted |
| July 3 (afternoon) | Fix #3: AR fitting variant lookup + shared helpers | AR bug fixed, but error persisted |
| July 3 (evening) | Fix #4: False banner + cart clearing | UI fixed, but error persisted |
| July 4 (morning) | Fix #5: Order creation atomicity + orphan cleanup | Atomicity fixed, but error persisted |
| July 4 (midday) | Verification Audit | **Found: SQL never run, no fresh build** |
| July 4 (afternoon) | SQL applied + fresh build | Error STILL persisted |
| July 4 (evening) | Diagnostic elimination test | **Found: Error is from DB trigger, not app** |
| July 4 (night) | Trigger function source retrieved | **ROOT CAUSE: RLS blocks trigger UPDATE** |
| July 4 (night) | SECURITY DEFINER fix applied | ✅ **FIXED** |

#### Key Learnings

1. **Verify deployments, not just code changes.** Four fix attempts failed because the changes were never compiled, deployed, or applied to the database. The verification audit proved this.

2. **RLS affects triggers.** Trigger functions without `SECURITY DEFINER` run as the calling user. If the calling user lacks RLS permissions for the trigger's operations, the operations silently fail.

3. **"Insufficient stock" can mean "insufficient permissions."** The error message from the trigger was accurate — the UPDATE matched 0 rows. But the reason was RLS blocking, not actual stock shortage.

4. **App-level validation can be a red herring.** The app's stock check was always correct (stock=46). The trigger's stock check was also correct in theory. The difference was RLS permissions.

5. **Console logging is essential.** The comprehensive `[ORDER-CREATE]` logging added in the atomicity fix was what finally revealed the exact error flow and proved the trigger was the source.

---

## 22. Appendix: API Examples

### Fetch all active products with store info
```dart
final data = await client
    .from('products')
    .select('*, stores(name), product_images(image_url, display_order), inventory(size, stock), product_variants(*)')
    .eq('is_active', true)
    .order('created_at', ascending: false);
```

### Place an order (multi-item)
```dart
// 1. Insert order
final order = await client.from('orders').insert({
    'customer_id': userId,
    'store_id': storeId,
    'status': 'pending',
    'total_amount': totalAmount,
    'payment_method': 'gcash',
    'payment_status': 'paid',
}).select().single();

// 2. Insert order items (one per product, triggers handle inventory)
for (final item in items) {
    await client.from('order_items').insert({
        'order_id': order['id'],
        'product_id': item['product_id'],
        'size': resolvedSize,
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
    });
}
```

### Follow a store
```dart
await client.from('store_follows').upsert({
    'user_id': userId,
    'store_id': storeId,
});
```

### Admin: Approve seller
```dart
await client.from('profiles').update({
    'role': 'seller',
    'seller_status': 'approved',
}).eq('id', userId);
```

---

## Appendix: Constants Reference

### Order Statuses
| Status | Description |
|--------|-------------|
| `pending` | Order received, awaiting confirmation |
| `placed` | Order confirmed |
| `preparing` | Being prepared/crafted |
| `ready` | Ready for pickup/delivery |
| `received` | Customer has received the order |
| `cancelled` | Order cancelled |

### Seller Statuses
| Status | Description |
|--------|-------------|
| `pending` | Application submitted, awaiting review |
| `approved` | Seller access granted |
| `rejected` | Application denied |
| `none` | Not applied as seller |

### Payment Methods
| Method | Description |
|--------|-------------|
| `cash` | In-person cash payment |
| `gcash` | GCash mobile wallet |
| `card` | Credit/debit card |

---

*SoleVision v2.0.0 — Complete project documentation compiled July 4, 2026.*  
*Sources: SESSION_LOG_JULY_2_3_2026.md, SESSION_DOCUMENTATION_JULY_3_2026.md, VERIFICATION_AUDIT_JULY_4_2026.md, PROJECT_HANDOFF.md, CHANGELOG.md, all FIX spec files, createOrder/addToCart/AR reference docs, project_doc.md v1.2.0, and codebase analysis.*
