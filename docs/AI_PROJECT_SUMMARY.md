# SoleVision — AI Project Summary

**Purpose:** This document gives another AI agent everything it needs to understand, navigate, and work on the SoleVision project. It is a self-contained brief — not exhaustive, but sufficient to plan and execute tasks.

**Date compiled:** July 8, 2026 (updated)

---

## Quick Facts

| Field | Value |
|-------|-------|
| **Project** | SoleVision — multi-role artisan footwear marketplace |
| **Market** | Carcar City, Cebu, Philippines |
| **Currency** | Philippine Peso (₱) |
| **Mobile app** | Flutter (Dart) — `lib/` |
| **Admin portal** | React (Vite + Tailwind) — `admin-portal/` |
| **Backend** | Supabase (PostgreSQL + RLS + Auth + Storage) |
| **Supabase project** | `psczvbfoybqhjeqssimw.supabase.co` |
| **State management** | Provider (Flutter), TanStack React Query (React) |
| **Git** | ⚠️ **No git repository exists.** All changes are untracked files on disk. |

---

## Project Structure (Key Paths)

```
app/
├── lib/                          # Flutter mobile app
│   ├── constants/app_constants.dart   # Supabase creds, colors, typography
│   ├── services/                 # Data access layer (singletons)
│   │   ├── supabase_service.dart      # createOrder(), fetchProducts(), legacy CRUD
│   │   ├── cart_service.dart          # Cart CRUD, validateCartForCheckout()
│   │   ├── product_service.dart       # Product CRUD, inventory sync
│   │   ├── order_service.dart         # Order placement, store order filtering
│   │   ├── sales_service.dart         # POS, revenue, reports
│   │   ├── auth_service.dart          # Auth with retry/backoff
│   │   ├── notification_service.dart  # User notifications (fetch, read)
│   │   ├── profile_service.dart       # Avatar upload
│   │   ├── upload_service.dart        # Generic file upload/delete
│   │   ├── biometric_service.dart     # Biometric auth + credential storage
│   │   └── store_service.dart         # Store CRUD, follow/unfollow
│   ├── providers/                # State management
│   │   ├── auth_provider.dart
│   │   ├── cart_provider.dart
│   │   ├── order_provider.dart
│   │   └── product_provider.dart
│   ├── screens/
│   │   ├── customer/             # Home, product detail, cart, checkout, orders
│   │   ├── seller/               # Dashboard, POS, manage products/orders
│   │   ├── admin/                # Admin dashboard (mobile)
│   │   └── auth/                 # Login, register, onboarding, auth gate
│   ├── utils/cart_helpers.dart   # Shared resolveVariant(), resolveInventoryStock(), normalizeSize()
│   ├── widgets/                  # Reusable UI (SoleCard, SolePrimaryButton, etc.)
│   └── exceptions/stock_unavailable_exception.dart
├── admin-portal/                 # React admin portal
│   └── src/
│       ├── pages/                # Dashboard, Users, Products, Orders, Analytics, Settings
│       ├── components/           # UI components (layout/, products/, users/, ui/)
│       ├── hooks/                # React Query hooks (useAuth, useDashboard, etc.)
│       └── lib/supabase.js       # Supabase client init
├── supabase/
│   ├── schema.sql                # ⚠️ OUTDATED — do not use as source of truth
│   └── migrations/               # SQL migration files
├── docs/                         # All documentation (see below)
├── dart_defines.json             # ⚠️ SECRET — MAPTILER_API_KEY (gitignored)
├── run_debug.sh                  # Debug build helper (Linux/Mac)
├── run_debug.bat                 # Debug build helper (Windows)
├── run_release.sh                # Release build helper (Linux/Mac)
├── run_release.bat               # Release build helper (Windows)
└── pubspec.yaml                  # Flutter dependencies
```

---

## Documentation Index

**Always read these first before starting any task:**

| File | Purpose |
|------|---------|
| `docs/SoleVision_Complete_Documentation.md` | **Master reference** — 22 sections covering everything: schema, RLS, architecture, services, bug history, setup |
| `docs/project_doc.md` | Earlier version of master doc (v1.2.0) — still accurate for most things |
| `docs/PROJECT_HANDOFF.md` | Decisions & rationale, known issues, what's next |
| `docs/SESSION_DOCUMENTATION_JULY_3_2026.md` | Investigation narrative for checkout bugs |
| `docs/SESSION_LOG_JULY_2_3_2026.md` | Session log with July 2-3 changes |
| `docs/VERIFICATION_AUDIT_JULY_4_2026.md` | Audit proving prior fixes were never deployed |
| `docs/CHANGELOG.md` | Feature changelog |
| `docs/createOrder_function_reference.md` | Annotated createOrder() with flow diagram |
| `docs/addToCart_and_fetchCart_reference.md` | Add-to-cart flow + fetchCart inventory fallback |
| `docs/CLEANUP_orphaned_zero_item_orders.sql` | SQL cleanup script for broken orders |
| `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql` | Post-fix verification queries |
| `docs/SESSION_LOG_JULY_8_2026.md` | Session log for July 8 (map location, dart-define config) |
| `docs/AI_PROJECT_SUMMARY.md` | This document — quick reference for AI agents |

---

## Database Schema (Essentials)

### Tables

| Table | Purpose | Key Relationships |
|-------|---------|-------------------|
| `profiles` | Users with roles (customer/seller/admin) + seller_status | FK → `auth.users` |
| `stores` | Artisan stores | `owner_id` → `profiles` |
| `products` | Products with price, category, is_active, is_featured | `store_id` → `stores`, `seller_id` → `profiles` |
| `product_variants` | Per-variant stock (size+color+price) | `product_id` → `products` (CASCADE) |
| `inventory` | Aggregated stock per size (summed across colors) | PK: `(product_id, size)` |
| `orders` | Online orders | `store_id` → `stores`, `customer_id` → `profiles` |
| `order_items` | Line items per order | `order_id` → `orders` (CASCADE) |
| `sales_transactions` | POS transactions | `store_id` → `stores` |
| `sales_transaction_items` | POS line items | `transaction_id` → `sales_transactions` (CASCADE) |
| `cart_items` | Server-side cart | `user_id` → `profiles`, has `size` column |
| `customization_requests` | Bespoke shoe requests | `customer_id` → `profiles` |

### Critical Schema Notes

- **Products PK is TEXT** (UUID stored as text, not native UUID)
- **`story_entries` has NO `title` column** (removed from live DB)
- **`cart_items` has a `size` column** (added July 4, 2026)
- **Two stock tables exist**: `inventory` (authoritative, used by triggers + app) and `product_variants` (may have stale data)
- **`inventory` is synced from `product_variants`** via `_syncInventoryFromVariants()` in `product_service.dart`

### FK Delete Rules (Do Not Change)

| Table | Column | Rule |
|-------|--------|------|
| `order_items` | `product_id` | SET NULL (preserve order history) |
| `sales_transaction_items` | `product_id` | SET NULL |
| `inventory` | `product_id` | CASCADE |
| `product_variants` | `product_id` | CASCADE |
| `cart_items` | `product_id` | CASCADE |

### DB Triggers

Two trigger functions auto-decrement inventory on insert:

- `decrement_inventory_on_order()` — fires on `order_items` INSERT
- `decrement_inventory_on_sale()` — fires on `sales_transaction_items` INSERT

Both normalize size via `regexp_replace(size, '\D', '', 'g')` before comparing. Both have `SECURITY DEFINER` (added July 4, 2026).

### RLS Policy Matrix

| Table | Customer | Seller | Admin |
|-------|----------|--------|-------|
| `profiles` | Read all, Update own | Read all, Update own | Read all, Update any |
| `products` | Read all | CRUD own store | CRUD any |
| `orders` | CRUD own | Read all, Update status | Read all, Update status |
| `inventory` | Read all | CRUD own store | CRUD any |
| `cart_items` | CRUD own | — | — |
| `customer_addresses` | CRUD own | — | — |

---

## Data Flow: Add to Cart → Checkout → Order

```
PRODUCT DETAIL → _addToCart() looks up variantId → CartProvider.addToCart()
  → background sync to cart_items (with size column)

CHECKOUT → _validateCart() → CartService.validateCartForCheckout()
  → batch-fetches inventory as authoritative stock source
  → shows banners for out-of-stock / insufficient-stock items

SUBMIT → re-validates → OrderProvider.placeOrder() → SupabaseService.createOrder()
  1. INSERT INTO orders
  2. Batch-fetch inventory for all products
  3. For each item: resolve size from inventory → INSERT INTO order_items
  4. DB trigger fires → decrements inventory.stock
  5. On failure: _cleanupOrphanedOrder() + batch rollback
  6. StockUnavailableException with friendly message

POST-ORDER → cart cleared → confirmation screen
```

---

## Key Architectural Patterns

1. **Services throw, Providers catch** — services are pure data access; providers handle loading/error for UI
2. **Singleton services** — all services use private constructors with static instances
3. **Revenue always combines online + POS** — `orders` (paid, non-cancelled) + `sales_transactions`
4. **Inventory sync** — `product_variants` is source of truth; `inventory` is derived/aggregated
5. **Size resolution** — shared via `resolveInventoryStock()` in `lib/utils/cart_helpers.dart`
6. **Auth flow** — `AuthGate` StreamBuilder routes to correct shell based on role

---

## Customer Experience (Detailed)

### Bottom Navigation (4 tabs, IndexedStack state preservation)

| Tab | Screen | Description |
|-----|--------|-------------|
| Home | `CustomerHomeScreen` | Featured products, category filtering, search, product cards |
| Store | `StoreScreen` | Multi-store discovery, follow/unfollow stores |
| Notifications | `NotificationsScreen` | Order status updates (Unpaid, Processing, Shipped, Review, Returns) |
| Profile | `ProfileScreen` | Account settings, avatar, notifications panel, logout |

### Customer Home Screen
- **Product browsing** with category filtering and search
- **Featured products** section with highlighted items
- **Product cards** showing image, name, price, store name
- **Tap → ProductDetailScreen** for full product view
- **Store cards** for store discovery and navigation

### Product Detail Screen (`product_detail_screen.dart`)
- **Image gallery** with `PageController` — swipeable product images, full-screen viewer
- **Size selector** via `_buildSizesMap()` — merges `inventory` + `product_variants` for accurate stock
- **"Only X left"** low-stock labels when stock ≤ 5
- **Add to Cart** — looks up `variantId` from `product_variants` by size+color, calls `CartProvider.addToCart()`
- **Buy Now** — direct checkout bypassing cart
- **AR Fitting button** — navigates to `ARVirtualFitScreen`
- **Store link** — tap to view store profile
- **Loading skeleton** while inventory fetches

### Cart Screen (`cart_screen.dart`)
- **Per-store grouping** — items grouped by `storeId` with store name header
- **Select All / Deselect All** — toggle entire cart or individual stores
- **Individual item selection** — checkbox per item for partial checkout
- **Quantity controls** — increment/decrement buttons per item
- **Delete with confirmation** — swipe or tap delete, confirmation dialog
- **Delivery fee** — flat ₱100 for local Cebu area
- **Subtotal calculation** — per-item `price × quantity`, grand total with delivery
- **Sticky checkout bar** — always visible at bottom, shows selected count and total
- **Empty state** — `EmptyStateWidget` when cart is empty

### Checkout Screen (`checkout_screen.dart`)
- **Two-step flow**: Step 0 (Details/Payment) → Step 1 (Confirmation)
- **Pre-submission validation** — `_validateCart()` checks live stock for every cart item
  - Shows out-of-stock banners (red) and insufficient-stock banners (yellow)
  - `_canSubmitOrder()` blocks button when items fail validation
- **Payment method selection** — Cash / GCash / Card
- **Delivery details** — address, phone, notes
- **Order summary** — shows all selected items with images, sizes, quantities, prices
- **Submit** — `OrderProvider.placeOrder()` → `SupabaseService.createOrder()`
- **Confirmation screen** — shows real order ID, "Track My Order" button, "Back to Home"
- **Cart clearing** — removes ordered items from cart (local + server-side) after success
- **Error handling** — `StockUnavailableException` with friendly message (never raw PostgrestException)

### Order Tracking Screen (`tracking_screen.dart`)
- **Vertical timeline** using `SoleTimeline` widget
- **4 statuses**: Order Placed → Being Prepared → Ready for Pickup → Received
- **Status descriptions**: Artisan-specific copy (e.g., "Leather cutting & welt stitching active at Carcar studio")
- **Header card** — order ID, product name, size, total amount
- **Active indicator** — highlights current status in timeline

### Customization Screen (`customization_screen.dart`)
- **5-step vertical stepper** for custom shoe orders:
  1. **Base Shoe Design** — Carcar Classic Oxford / Suede Artisan Loafer / Kabanhawan Boot
  2. **Color & Dye Scheme** — Burnished Clay / Carob Dark / Celadon Teal / Olive Stitch / Crimson Welt / Tuscan Gold
  3. **Upper Material** — Full-Grain Calfskin Leather / Premium Roughout Suede / Organic Cebuano Canvas
  4. **Special Request** — free-text field for sizing adjustments, initials, stitching preferences
  5. **Submit Design** — submits `customization_requests` to database
- **Success feedback** — SnackBar confirmation, navigation back

### AR Fitting Screen (`ar_fitting_screen.dart`)
- **Simulated AR** with particle rendering (`_ARParticlePainter`)
- **Product switching** — cycle through available products
- **Size availability check** — `_checkSizeAvailability()` against inventory
- **Add to Cart** — with variant lookup (shared `resolveVariant()` helper)
- **Tracking animation** — pulse effect, lock-on after 2.5s delay
- **Status text** — "Tracking your feet..." → "Fit looks good!" on lock
- **⚠️ Placeholder** — no real AR, uses simulated particle effects

### Profile Screen (`lib/screens/shared/profile_screen.dart`)
- **Avatar** — circular with camera overlay for upload, loading spinner during upload
- **Edit profile** — collapsible panel with name, email (locked), phone number
- **Notifications panel** — 5 order status categories with unread count badges:
  - Unpaid, Processing, Shipped, Review, Returns
  - Tapping navigates to `NotificationsScreen` with category filter
- **Settings card** — Change Password (sends reset email), Terms & Privacy (placeholder), About (placeholder)
- **Seller section** (if role=seller) — store link, seller status chip, member since date
- **Logout** — confirmation dialog, clears all state + biometric credentials
- **Noise overlay** — organic texture via `_NoisePainter` for visual depth

### Notifications Screen (`notifications_screen.dart`)
- **Category tabs** — Unpaid / Processing / Shipped / Review / Returns
- **Order cards** — tapping marks as read, navigates to `OrderTrackingScreen`
- **Read/unread state** — visual distinction for notification status

---

## Current State (July 8, 2026)

### What's Working

- ✅ Full customer flow: browse → add to cart → checkout → order tracking
- ✅ Full seller flow: dashboard → POS → manage products/orders → reports
- ✅ Full admin flow: mobile app + web portal with analytics
- ✅ Biometric login, offline detection, profile management
- ✅ Stock validation with friendly error messages
- ✅ DB trigger SECURITY DEFINER fix (checkout error resolved)
- ✅ cart_items.size column migration applied
- ✅ Custom shoe orders (5-step customization flow)
- ✅ AR fitting screen (simulated, not real AR)
- ✅ Notifications with category-based order status tracking
- ✅ Permanent dart-define config for MAPTILER_API_KEY (dart_defines.json + helper scripts)

### What's Broken / Not Done

| Issue | Status | Priority |
|-------|--------|----------|
| No git repository | ⚠️ No version control | Critical |
| Non-numeric sizes may break triggers | ⚠️ Unverified (query ready) | High |
| Duplicate product_variants rows | ⚠️ Cleanup script ready | High |
| `supabase/schema.sql` is outdated | Known | Medium |
| No unit tests | Default template only | Medium |
| AR fitting is a placeholder | No real AR | Low |
| CSV export is a stub | Shows SnackBar only | Low |
| No push notifications | Not started | Future |
| No real-time updates | Not integrated | Future |
| ~~customer_addresses RLS policies missing~~ | ✅ Fixed July 8 — applied missing CRUD policies | Resolved |
| MAPTILER_API_KEY not set | Needs API key in dart_defines.json | Medium |

---

## SQL Migrations (All Applied)

| File | Purpose | Status |
|------|---------|--------|
| `supabase/migrations/20260702_notifications.sql` | Notifications table + RLS | ✅ Live |
| `supabase/migrations/20260703_add_cart_items_size.sql` | Add `size` column to cart_items | ✅ Applied July 4 |
| `supabase/migrations/20260704_add_orders_delete_policy.sql` | DELETE RLS on orders | ✅ Applied July 4 |
| `supabase/migrations/20260704_fix_trigger_security_definer.sql` | SECURITY DEFINER on triggers | ✅ Applied July 4 |
| `supabase/migrations/20260705_add_customer_addresses.sql` | customer_addresses table + RLS | ⚠️ Table created, RLS policies NOT applied |
| `supabase/migrations/20260708_fix_customer_addresses_rls.sql` | Fix customer_addresses RLS (add all 4 CRUD policies) | ✅ Applied July 8 |

---

## Bug Fix History (Summary)

| Date | Fix | Root Cause |
|------|-----|------------|
| June 28 | Product hard delete + auto-deactivation | Missing RLS DELETE policy + FK constraints |
| June 30 | Login freeze on account switch | 5 root causes: stale state, race condition, biometric bleed |
| June 30 | Empty size selector | inventory table never written to |
| July 2 | Checkout flow overhaul | Multi-item orders broken, wrong pricing, fake IDs |
| July 3 | Stock validation + friendly errors | Raw PostgrestException shown to users |
| July 3 | DB trigger exact-match fix | Size format mismatch ("EU40" vs "40") |
| July 3 | validateCartForCheckout reads inventory | Was reading stale product_variants |
| July 4 | Order creation atomicity | Orphaned 0-item orders on failure |
| July 4 | **SECURITY DEFINER on triggers** | **True root cause: RLS blocked trigger UPDATE** |
| July 4 | cart_items.size column | Migration existed but never applied |
| July 8 | Permanent dart-define config for MAPTILER_API_KEY | Created dart_defines.json + helper scripts |
| July 8 | Updated .gitignore for secrets | Added dart_defines.json and *.env patterns |
| July 8 | **customer_addresses RLS fix** | **Policies from 20260705 migration never applied to live DB — 42501 on INSERT** |

**Key lesson:** The checkout bug persisted across 5 fix attempts because (1) SQL migrations were never run against the live database, (2) no fresh build was deployed, and (3) the true root cause was RLS blocking the trigger's UPDATE — not an app-level stock check issue.

---

## Setup & Running

### Flutter App
```bash
cd app
flutter pub get

# Option 1: Use helper scripts (recommended — uses dart_defines.json)
# Linux/Mac: ./run_debug.sh
# Windows: run_debug.bat

# Option 2: Manual flag
flutter run --dart-define=MAPTILER_API_KEY=your_key

# Credentials are hardcoded in lib/constants/app_constants.dart
# MapTiler API key goes in dart_defines.json (gitignored)
```

### Admin Portal
```bash
cd admin-portal
npm install
# Create .env with VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm run dev
# Opens at http://localhost:5173
```

### Database
- Supabase project URL: `psczvbfoybqhjeqssimw.supabase.co`
- Do NOT use `supabase/schema.sql` — it's outdated
- Use `docs/SoleVision_Complete_Documentation.md` Section 4 as schema reference
- Storage buckets: `avatars`, `product-images`, `store-assets` (all public)

---

## Constants & Design System

### Colors
| Name | Hex | Usage |
|------|-----|-------|
| Primary (Burnished Clay) | `#8B5A2B` | Buttons, active states |
| Secondary (Carob Dark) | `#3B2314` | Text, icons |
| Accent (Celadon Teal) | `#4ECDC4` | AR mode, CTAs |
| Surface (Off-White Suede) | `#F5F0EB` | Backgrounds |
| Success (Olive Stitch) | `#6B8F47` | Success states |
| Error (Crimson Welt) | `#D64545` | Error states |

### Typography
- Headlines: Playfair Display
- Body: DM Sans
- Monospace: JetBrains Mono

### Reusable Widgets
`SoleCard`, `SolePrimaryButton`, `SoleTextField`, `SoleBottomNav`, `SoleBadge`, `SoleStatusChip`, `SoleMetricCard`, `SoleProductCard`, `ShimmerBox`, `EmptyStateWidget`, `ErrorRetryWidget`

---

## ⚠️ Critical Warnings for Any AI Working on This Project

1. **DO NOT use `supabase/schema.sql` as source of truth.** It's outdated. Use the docs or query the live DB.

2. **DO NOT modify `validateCartForCheckout()` or app-level stock logic.** It was proven correct. The bug was in the DB trigger.

3. **Always verify SQL migrations are applied to the live database.** This was the #1 cause of failed fixes — code was written but never deployed.

4. **Always do a full rebuild** (`flutter clean && flutter pub get && flutter run`) after code changes. Hot reload is not sufficient for service-layer changes.

5. **Revenue calculation must combine online + POS.** Never use only `orders` or only `sales_transactions`.

6. **The `inventory` table is the authoritative stock source.** `product_variants` may have stale/0 values.

7. **Products PK is TEXT, not UUID.** Be careful with type comparisons.

8. **No git repo exists.** There is no version control. All changes are raw file modifications.

9. **MAPTILER_API_KEY must be set.** The map requires a MapTiler API key. Get a free key at https://maptiler.com/cloud and add it to `dart_defines.json`.

---

*SoleVision AI Project Summary — compiled July 8, 2026 (updated).*
*Primary source: `docs/SoleVision_Complete_Documentation.md`*
*Session log: `docs/SESSION_LOG_JULY_8_2026.md`*
