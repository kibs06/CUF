# SoleVision — Complete Project Documentation

**Version:** 1.2.0  
**Last Updated:** July 3, 2026  
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
15. [Bug Fix History (June 28 – July 3, 2026)](#15-bug-fix-history)
16. [Critical Technical Debt](#16-critical-technical-debt)
17. [Future Roadmap](#17-future-roadmap)
18. [Setup & Installation](#18-setup--installation)
19. [Key Files Reference](#19-key-files-reference)
20. [Appendix: API Examples](#20-appendix-api-examples)

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

**⚠️ Schema Drift Warning:** `supabase/schema.sql` is the original schema. The live database has evolved significantly (UUID PKs, additional tables, removed columns). **Always refer to the docs, not `schema.sql`.** The schema in Section 4 of this document reflects the live database.

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
- `cart_items` has **NO `size` column** — size is only recoverable via `product_variants` LEFT JOIN (known data model gap)
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

Both normalize size via `regexp_replace(size, '\D', '', 'g')` before comparing against `inventory.size` (to handle "EU40" vs "40" format mismatch). Size normalization fix deployed July 3, 2026. **SECURITY DEFINER fix deployed July 4, 2026** — without it, the trigger's UPDATE is blocked by RLS when called by a customer.

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

### Key Service Files (Flutter)

| File | Responsibility |
|------|---------------|
| `lib/services/auth_service.dart` | Auth: sign in (with session-clear before new sign-in), sign up, profile fetch (5 retries + exponential backoff), password reset |
| `lib/services/product_service.dart` | Full product CRUD, image upload to Storage, variants, customizations, `_syncInventoryFromVariants()`, `syncProductActiveStatus()`, hard delete with history preservation |
| `lib/services/order_service.dart` | Order placement, store order filtering (3-step chain: products → order_items → orders), recent orders, order status updates |
| `lib/services/sales_service.dart` | POS transactions (`recordSale()`), today/weekly/monthly revenue (combining online + POS), weekly/monthly reports, top products, size normalization for POS inserts |
| `lib/services/cart_service.dart` | `fetchCart()` with inventory fallback for null variants, `addOrUpdateItem()`, `removeItem()`, `clearCart()`, `validateCartForCheckout()` with inventory as authoritative stock source |
| `lib/services/store_service.dart` | Store CRUD, image upload, follow/unfollow, story entries |
| `lib/services/supabase_service.dart` | Legacy general CRUD — still used for `createOrder()`, `fetchProducts()`, `fetchOrders()`, profile operations |

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

This same logic is currently duplicated in 3 places and should be extracted to a shared helper.

---

## 9. State Management

### Provider Architecture (Mobile)

| Provider | Scope | Key State |
|----------|-------|-----------|
| `AuthProvider` | App-wide | `_currentUser`, `_profile`, `_isLoading`, `_errorMessage` |
| `ProductProvider` | Product browsing | `_products[]`, `_selectedCategory`, `categories` |
| `CartProvider` | Shopping cart | `_items{}` (keyed by `productId-size-color`), `_selectedKeys`, `subtotal`, `deliveryFee` |
| `OrderProvider` | Orders & admin | `_orders[]`, `_customizations[]`, `_profiles[]`, `_stockError` |

### React Query (Admin Portal)

| Hook | Queries | Mutations |
|------|---------|-----------|
| `useDashboardStats` | Dashboard counts | — |
| `useRecentPendingApplications` | Recent pending sellers | — |
| `useRecentOrders` | Recent orders | — |
| `useOrdersSparkline` | 7-day order counts | — |
| `useApproveSeller` | — | Approve seller |
| `useRejectSeller` | — | Reject seller |
| `useAnalytics(days)` | Revenue, orders, users, trends | — |
| `useUsers` | User list | Update roles |
| `useOrders` | Order list | Update status |
| `useProducts` | Product list | CRUD |

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
  → cart_items has NO size column (known gap)
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

**Known issue:** `product_variants.stock` can be 0 while `inventory.stock` is 100+. `validateCartForCheckout()` was fixed to use `inventory` as authoritative source (July 3, 2026).

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
- **Force sign-out before new sign-in** — prevents session bleed on account switch
- **Return widgets directly from `build()`** — prevents LoginScreen from becoming a disconnected stack layer

### Storage Buckets (all public)
| Bucket | Contents |
|--------|----------|
| `avatars` | User profile pictures |
| `product-images` | Product photos |
| `store-assets` | Store logos and banners |

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
| **Non-numeric sizes break trigger normalization** | ⚠️ UNVERIFIED (verification query ready) | The DB triggers use `regexp_replace(size, '\D', '', 'g')` which strips all non-digits. If any product uses "S"/"M"/"L"/"One Size", this breaks. Verification query exists in `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql` but has NOT been run. |
| **Duplicate product_variants rows** | ✅ Verified + cleanup script ready | Classic Derby Oxford confirmed to have duplicate rows. Cleanup script in `CHECKOUT_HARD_FIX_CLEANUP.sql` Step 2. |
| **Orphaned inventory rows** | ⚠️ UNVERIFIED (backfill script ready) | Backfill script in `CHECKOUT_HARD_FIX_CLEANUP.sql` Step 4. |
| **Order creation non-atomic → orphaned 0-item orders** | ✅ Root cause identified + fix deployed | `createOrder()` inserts `orders` row first, then `order_items` in separate calls. If `order_items` insert fails (e.g., DB trigger P0001), the `orders` row is orphaned with 0 items. Fix: `_cleanupOrphanedOrder()` deletes orphaned rows on failure. Requires DELETE RLS policy (migration `20260704_add_orders_delete_policy.sql`). |
| **False "is no longer available" error = RLS blocks trigger UPDATE** | ✅ Fixed (migration ready) | The `decrement_inventory_on_order()` trigger runs without `SECURITY DEFINER`, so it executes as the customer. RLS on `inventory` only allows sellers/admins to UPDATE — the customer's UPDATE is silently blocked, matching 0 rows, raising 'Insufficient stock'. App's SELECT works ("viewable by everyone" policy) but UPDATE fails. Fix: `SECURITY DEFINER` on both trigger functions (`20260704_fix_trigger_security_definer.sql`). |

### 🟡 Medium Priority

| Issue | Status | Notes |
|-------|--------|-------|
| **`cart_items` has no `size` column** | ✅ Fixed | Migration `20260703_add_cart_items_size.sql` adds the column and backfills from `product_variants`. `addOrUpdateItem()` now stores size on every insert. `fetchCart()` reads it. |
| **Schema drift: `supabase/schema.sql` is outdated** | Known | Live DB has evolved beyond the file. Always refer to docs, not `schema.sql`. |
| **`isFollowing()` always returns `false`** | Stub | Synchronous method is a stub. Async `isFollowingAsync()` works. |
| **`SupabaseService` duplicates logic** | Tech debt | Some CRUD exists in both `SupabaseService` and focused services (e.g., `createOrder`). |
| **CSV export is a stub** | Stub | Reports screen "Download" button shows SnackBar only. |
| **No unit tests** | Gap | `test/widget_test.dart` is default Flutter template — no actual tests exist. |
| **Size resolution logic duplicated 3x** | ✅ Partially resolved | Extracted to shared `resolveInventoryStock()` + `normalizeSize()` in `cart_helpers.dart`. Used by `validateCartForCheckout()` and `createOrder()`. `recordSale()` still has inline logic (follow-up). |

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

## 15. Bug Fix History

### June 28, 2026
- **Product hard delete & auto-deactivation** — sellers can permanently delete products; `is_active` auto-manages based on stock
- **Seller dashboard wired to real Supabase data** — all metrics real, revenue combines online + POS
- **Reports screen wired to real data** — weekly sales, top products, bar chart
- **Product delete silently failing fixed** — missing RLS DELETE policy + FK constraints set to NO ACTION + missing `await`

### June 30, 2026
- **Login freeze when switching accounts** — 5 root causes fixed together (AuthProvider state reset, AuthService session-clear, AuthGate routing, biometric clear, isLoading flag)
- **Navigator stack conflict** — LoginScreen pushed via Navigator.pushReplacement created disconnected stack layer; fixed by returning widgets directly from build()
- **Product size selector empty** — inventory table was never written; added `_syncInventoryFromVariants()`, `inventory(*)` to read queries, `_buildSizesMap()` helper
- Profile fetch timeout (12s), offline detection, size selector loading skeleton

### July 2, 2026
- Product variants missing from main query
- Blank white cart screen fix (SolePrimaryButton layout)
- **Checkout flow overhaul** — multi-item order creation, correct pricing, auto-selection, real order IDs, working navigation
- **Error handling & stock validation** — `StockUnavailableException` with friendly messages, pre-submission validation banners, "Go to Cart" action button

### July 3, 2026
- **DB trigger exact-match bug fixed** — `decrement_inventory_on_order` and `decrement_inventory_on_sale` now normalize size via regexp
- **App-layer size resolution** — `createOrder()` and `recordSale()` resolve size from inventory before inserting
- **Batched N+1 inventory queries** — single query instead of per-item
- **`validateCartForCheckout()` fixed** — now uses `inventory` as authoritative stock source
- **AR fitting variant lookup fixed** — added missing `variantId` lookup, extracted shared `resolveVariant()` helper to `lib/utils/cart_helpers.dart`
- **Cart clearing after successful order** — confirmed already implemented in `_submitCheckout()`
- **False "no longer available" error fixed (v6)** — `_itemValidations` was never cleared on re-validation or item removal, causing stale entries to falsely block the order button. Now cleared before each validation pass.
- **Cart not deleted from DB after order fixed (v6)** — `removeFromCart()` depended on `server_id` which could be null for items whose background sync hadn't completed. Replaced with `CartService.removeItems()` (awaited, scoped to ordered items only) with `clearCart()` fallback when `server_id` is unavailable.

### July 4, 2026
- **Order creation atomicity fix** — `createOrder()` was non-atomic: `orders` row inserted first, then `order_items` in separate calls. When `order_items` insert failed (DB trigger P0001), the `orders` row was orphaned with 0 items. Fix: added `_cleanupOrphanedOrder()` that deletes the orphaned `orders` row on failure, with batch rollback of successfully inserted `order_items`. Comprehensive logging now captures exact payloads and raw PostgrestException details (code, message, details, hint).
- **⚠️ TRUE ROOT CAUSE IDENTIFIED: RLS blocks trigger UPDATE on inventory** — The `decrement_inventory_on_order()` trigger function runs WITHOUT `SECURITY DEFINER`, meaning it executes as the calling user (the customer). The `inventory` table has RLS policies that only allow sellers and admins to UPDATE rows. When a customer places an order, the trigger's UPDATE on inventory is silently blocked by RLS (matching 0 rows), causing the function to raise 'Insufficient stock' — even when the app correctly sees stock=46. The app's SELECT succeeds because there's a "viewable by everyone" SELECT policy, but the customer has no UPDATE policy. **Fix: add `SECURITY DEFINER` to both `decrement_inventory_on_order()` and `decrement_inventory_on_sale()`** (migration `20260704_fix_trigger_security_definer.sql`).
- **Why prior fixes missed this** — Five prior fix attempts targeted `validateCartForCheckout()`, app-layer inventory logic, size normalization, and order creation atomicity. All were red herrings: the app's stock validation was always correct. The error came from the database trigger, which appeared to be a stock problem but was actually an RLS permission problem. The trigger's UPDATE was blocked by RLS, not by actual insufficient stock.
- **DELETE RLS policy added to orders table** — Migration `20260704_add_orders_delete_policy.sql` adds `DELETE USING (auth.uid() = customer_id AND status = 'pending')` so orphaned pending orders can be cleaned up.
- **Diagnostic elimination test infrastructure** — Added and reverted diagnostic instrumentation (forced `isAvailable: true` in validation, P0001 catch-without-throw in `createOrder()`) to prove the validation logic was not the source. All diagnostic artifacts removed.

---

## 16. Critical Technical Debt

### Must Fix Before Production

| Item | Impact | Effort |
|------|--------|--------|
| **Run verification SQL queries** | Non-numeric sizes could silently break all orders | Small (run queries, interpret results) |
| **Add `size` column to `cart_items`** | Eliminates entire class of size-mismatch bugs | Medium (SQL migration + code changes) |
| **Extract shared size-resolution helper** | 3 copies of same logic = maintenance nightmare | Small |
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

### Open Questions
- **Payment handling:** In-app or current "record intent + pay in person" model?
- **Delivery:** Flat ₱100 or distance-based? Current model assumes local Carcar City.
- **Single store per seller:** Currently enforced. Allow multiple?
- **Admin portal hosting:** Vercel, Netlify, or self-hosted?
- **Flutter web:** Rebuild admin portal in Flutter for code sharing, or keep React?

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
7. Deploy the updated DB triggers for size normalization

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
| `lib/services/supabase_service.dart` | `createOrder()`, `fetchProducts()`, legacy CRUD |
| `lib/services/product_service.dart` | Product CRUD, `_syncInventoryFromVariants()`, `syncProductActiveStatus()` |
| `lib/services/order_service.dart` | Order placement, store order filtering |
| `lib/services/sales_service.dart` | POS transactions, revenue calculations |
| `lib/services/cart_service.dart` | Cart CRUD, `validateCartForCheckout()`, `fetchCart()` |

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
| `lib/utils/cart_helpers.dart` | Shared `resolveVariant()` helper (new) |

### Documentation Files
| File | Purpose |
|------|---------|
| `docs/project_doc.md` | **This document** — comprehensive project reference |
| `docs/PROJECT_HANDOFF.md` | Project handoff with decisions, rationale, known issues |
| `docs/SESSION_DOCUMENTATION_JULY_3_2026.md` | Full investigation narrative for checkout bugs |
| `docs/SESSION_LOG_JULY_2_3_2026.md` | Session log with all July 2-3 changes |
| `docs/createOrder_function_reference.md` | Annotated `createOrder()` with flow diagram |
| `docs/addToCart_and_fetchCart_reference.md` | Add-to-cart flow + fetchCart inventory fallback |
| `docs/ar_fitting_addToCart_reference.md` | AR fitting `_addToCart()` analysis |
| `docs/checkout_submit_analysis.md` | `_submitCheckout()` analysis for v5 spec |
| `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql` | SQL verification queries — Steps 2-8 for post-fix data audit |
| `docs/FIX_false_error_and_cart_clear_v6.md` | v6 fix spec — root cause analysis for both checkout bugs |

### Fix Specs (Investigation History)
| File | Finding | Status |
|------|---------|--------|
| `FIX_complete_order_stock_mismatch.md` | v1 — DB trigger exact-match investigation | ✅ Fixed (deployed) |
| `FIX_complete_order_stock_mismatch_v2.md` | v2 — Confirms trigger fix, verification steps | ✅ Fixed |
| `FIX_checkout_validation_stock_source_v3.md` | v3 — Validation reads wrong stock source | ✅ Fixed (inventory as authoritative) |
| `FIX_ar_fitting_variant_id_v4.md` | v4 — AR fitting missing variant lookup | ✅ Fixed (shared helper extracted) |
| `FIX_false_error_and_cart_clear_v5.md` | v5 — False banner + cart clearing | ❌ Was marked implemented but bugs persisted — superseded by v6 |
| `FIX_false_error_and_cart_clear_v6.md` | v6 — Stale `_itemValidations` + `server_id` race in cart clear | ✅ Fixed (deployed) |
| `FIX_false_error_and_cart_clear_v6.md` | v6 — Stale `_itemValidations` + `server_id` race in cart clear | ✅ Fixed (deployed) |
| `CHECKOUT_HARD_FIX_CLEANUP.sql` | Phase 2 hard fix: duplicate variants cleanup + orphaned inventory backfill | ✅ Script ready |
| Order creation atomicity fix (July 4) | Non-atomic order creation → orphaned 0-item orders + false stock error | ✅ Fixed (deployed) — see Section 15 July 4 entry |

---

## 20. Appendix: API Examples

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

*SoleVision v1.2.0 — Comprehensive project documentation generated July 3, 2026.*
*Synthesized from: PROJECT_HANDOFF.md, SoleVision_Project_Documentation2.md, SoleVision_Project_Documentation_Concise.md, SESSION_LOG_JULY_2_3_2026.md, SESSION_DOCUMENTATION_JULY_3_2026.md, all FIX spec files, createOrder/addToCart/AR reference docs, and codebase analysis.*
