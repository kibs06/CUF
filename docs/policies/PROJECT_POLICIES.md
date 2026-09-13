# SoleVision Project Policies

**Version:** 1.0.0  
**Last Updated:** September 9, 2026  
**Status:** Living Document — Update with every architectural decision

---

## Table of Contents

1. [Architecture & Design Policies](#1-architecture--design-policies)
2. [Database Policies](#2-database-policies)
3. [Security Policies](#3-security-policies)
4. [Code Quality Policies](#4-code-quality-policies)
5. [State Management Policies](#5-state-management-policies)
6. [Service Layer Policies](#6-service-layer-policies)
7. [UI/UX Policies](#7-uiux-policies)
8. [Testing Policies](#8-testing-policies)
9. [Deployment & Release Policies](#9-deployment--release-policies)
10. [Data Integrity Policies](#10-data-integrity-policies)
11. [Error Handling Policies](#11-error-handling-policies)
12. [Documentation Policies](#12-documentation-policies)
13. [Contribution & Workflow Policies](#13-contribution--workflow-policies)

---

## 1. Architecture & Design Policies

### 1.1 Backend Architecture
- **Single Supabase Project**: Both Flutter mobile app and React admin portal connect to the same Supabase project.
- **RLS-First Design**: All data access governed by Row Level Security policies at the database level. Application code assumes RLS is the source of truth for permissions.
- **No Realtime (Yet)**: Supabase Realtime is available but NOT integrated. All data fetching is pull-based (manual refresh or scheduled).

### 1.2 Service Architecture
- **Singleton Services**: All services are singletons instantiated once per app lifecycle.
- **Focused Responsibility**: Each service has a single domain (Auth, Product, Order, Store, Sales, Cart, Profile, Upload, Biometric).
- **Legacy SupabaseService**: Still used for `createOrder()`, `fetchProducts()`, `fetchOrders()`, and profile operations. New code should prefer focused services.
- **Exception-Throwing Services**: Services throw exceptions; Providers catch and set `_errorMessage` for UI display.

### 1.3 Data Flow Patterns
- **Revenue = Online + POS**: Revenue calculations ALWAYS combine `orders` (online, `payment_status='paid'`, `status!='cancelled'`) AND `sales_transactions` (POS). Neither source alone is complete.
- **Store Order Filtering (3-Step Chain)**:
  1. `products` WHERE `store_id = X` → get product IDs
  2. `order_items` WHERE `product_id IN [product IDs]` → get order IDs
  3. `orders` WHERE `id IN [order IDs]` → final orders
- **Inventory Sync**: `product_variants` = source of truth (per size+color). `inventory` = derived table (aggregated per size, stock summed across colors). `_syncInventoryFromVariants()` runs after every variant create/update.
- **Size Resolution (3-Tier Fallback)**:
  1. Exact match — cart size matches inventory size
  2. Numeric match — strip "EU"/"US" prefix, then compare
  3. Fallback — first available inventory size

---

## 2. Database Policies

### 2.1 Schema Management
- **Live DB is Source of Truth**: `supabase/schema.sql` is OUTDATED. The live database has evolved (UUID PKs as TEXT, additional tables, removed columns). Always refer to documentation, not `schema.sql`.
- **Migrations Only**: All schema changes via Supabase migrations. No direct SQL in production.
- **Naming Conventions**: 
  - Tables: snake_case, plural (`product_variants`, `store_follows`)
  - Columns: snake_case (`store_id`, `created_at`, `is_active`)
  - Primary Keys: `id` (TEXT for UUIDs) or composite
  - Foreign Keys: `{table}_id` (e.g., `store_id`, `product_id`)

### 2.2 Foreign Key Delete Rules (IMMUTABLE)
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

**NEVER CHANGE THESE RULES** — they preserve audit trails for orders/sales.

### 2.3 Triggers
- **Two Inventory Decrement Triggers**:
  - `decrement_inventory_on_order()` — fires on `order_items` INSERT
  - `decrement_inventory_on_sale()` — fires on `sales_transaction_items` INSERT
- **Size Normalization**: Both triggers normalize size via `regexp_replace(size, '\D', '', 'g')` to handle "EU40" vs "40" mismatch.
- **SECURITY DEFINER Required**: Both triggers MUST have `SECURITY DEFINER` so they execute as the definer (bypassing RLS on UPDATE). Without this, customer orders fail with false "Insufficient stock" errors because RLS blocks the trigger's UPDATE on `inventory`.

### 2.4 RLS Policy Matrix
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

### 2.5 Seller Approval Flow
1. User registers with "Apply as seller" toggle → `seller_status = 'pending'`
2. User sees "Pending Approval" screen
3. Admin reviews in admin portal → Approve or Reject
4. On approval: `role` → `seller`, `seller_status` → `approved`

### 2.6 Storage Buckets (All Public)
| Bucket | Contents |
|--------|----------|
| `avatars` | User profile pictures |
| `product-images` | Product photos |
| `store-assets` | Store logos and banners |

---

## 3. Security Policies

### 3.1 Authentication
- **Supabase Auth**: Email/password with JWT tokens. Supabase manages token refresh.
- **Session Clear on Account Switch**: `AuthService.signIn()` MUST clear existing session before new sign-in to prevent silent rejection.
- **Profile Fetch with Retry**: 5 attempts with exponential backoff on profile fetch.
- **Biometric Auth**: 
  - `LocalAuthentication.canCheckBiometrics` + `isDeviceSupported()`
  - Credentials stored in `FlutterSecureStorage` (encrypted)
  - Cleared on logout to prevent cross-account bleed

### 3.2 Authorization
- **RLS Enforcement**: All authorization at database level via RLS policies.
- **Admin Gates**: Admin-only policies gated by `role = 'admin'` check in RLS.
- **Seller Gates**: Seller policies gated by `auth.uid() = seller_id` or `store_id` ownership.

### 3.3 Data Protection
- **No Secrets in Code**: Supabase URL and anon key are in `app_constants.dart` (not ideal — should move to env).
- **No PII in Logs**: Debug prints removed from production builds.
- **Secure Storage**: Biometric credentials and sensitive tokens in `FlutterSecureStorage`.

---

## 4. Code Quality Policies

### 4.1 Flutter/Dart Standards
- **No Comments Unless Asked**: Code should be self-documenting.
- **Return Widgets Directly from `build()`**: Prevents `LoginScreen` from becoming a disconnected stack layer (Navigator.pushReplacement issue).
- **Deprecation Handling**: 
  - Replace `.withOpacity()` with `.withValues()`
  - Replace `RadioListTile` with `Radio` + `ListTile`
- **Error Handling**: Use custom exceptions (`StockUnavailableException`) with friendly messages.

### 4.2 React/TypeScript Standards (Admin Portal)
- **TanStack Query for All Server Data**: Automatic caching, refetching, optimistic updates.
- **ProtectedRoute Wrapper**: All routes except `/login` wrapped in `ProtectedRoute`.
- **Tailwind CSS Only**: No CSS-in-JS, no custom CSS files.
- **Recharts for Analytics**: All charts use Recharts library.

### 4.3 File Organization
```
lib/
├── constants/          → App-wide constants (colors, roles, statuses)
├── services/           → Singleton services (one per domain)
├── providers/          → Provider state management
├── screens/            → Screen widgets (customer/, seller/, admin/)
├── widgets/            → Reusable UI components
├── utils/              → Shared helpers (cart_helpers.dart)
└── main.dart           → App entry point
```

---

## 5. State Management Policies

### 5.1 Mobile (Provider)
| Provider | Scope | Key State |
|----------|-------|-----------|
| `AuthProvider` | App-wide | `_currentUser`, `_profile`, `_isLoading`, `_errorMessage` |
| `ProductProvider` | Product browsing | `_products[]`, `_selectedCategory`, `categories` |
| `CartProvider` | Shopping cart | `_items{}` (keyed by `productId-size-color`), `_selectedKeys`, `subtotal`, `deliveryFee` |
| `OrderProvider` | Orders & admin | `_orders[]`, `_customizations[]`, `_profiles[]`, `_stockError` |

**Patterns**:
- Providers catch service exceptions → set `_errorMessage` for UI
- Optimistic updates with background Supabase sync + rollback on failure
- Cart items keyed by `productId-size-color`
- Flat ₱100 delivery fee for local Cebu area

### 5.2 Admin Portal (TanStack React Query)
- All server data via React Query hooks (`useDashboardStats`, `useUsers`, `useOrders`, `useProducts`, `useAnalytics`, `useSellerApplications`)
- Mutations for write operations (`useApproveSeller`, `useRejectSeller`, `useUpdateOrderStatus`)
- Automatic cache invalidation on mutations

---

## 6. Service Layer Policies

### 6.1 Service Responsibilities (Flutter)
| Service | File | Responsibility |
|---------|------|---------------|
| `SupabaseService` | `supabase_service.dart` | Legacy CRUD, `createOrder()`, `fetchProducts()`, `fetchOrders()` |
| `AuthService` | `auth_service.dart` | Auth: sign in (with session-clear), sign up, profile fetch (5 retries) |
| `ProductService` | `product_service.dart` | Product CRUD, image upload, variants, inventory sync, `syncProductActiveStatus()` |
| `OrderService` | `order_service.dart` | Order placement, store order filtering, recent orders |
| `StoreService` | `store_service.dart` | Store CRUD, image upload, follow/unfollow, story entries |
| `SalesService` | `sales_service.dart` | POS transactions, daily/weekly/monthly revenue, dashboard metrics |
| `CartService` | `cart_service.dart` | Cart CRUD, `validateCartForCheckout()`, `fetchCart()` |
| `ProfileService` | `profile_service.dart` | Avatar picking and upload |
| `UploadService` | `upload_service.dart` | Generic file upload/delete for Supabase Storage |
| `BiometricService` | `biometric_service.dart` | Biometric auth, credential storage |

### 6.2 Critical Service Rules
- **`createOrder()` Atomicity**: 
  - Inserts `orders` row first, then `order_items` in batch
  - On failure: `_cleanupOrphanedOrder()` deletes orphaned `orders` row + rolls back inserted `order_items`
  - Requires DELETE RLS policy on `orders` (`auth.uid() = customer_id AND status = 'pending'`)
- **`validateCartForCheckout()` Uses `inventory` as Authoritative Source**: NOT `product_variants` (which can have stale/0 values).
- **`recordSale()` (POS) Uses Same Size Resolution**: Same 3-tier fallback as `createOrder()`.
- **`_syncInventoryFromVariants()` Runs After Every Variant Write**: Keeps aggregated `inventory` table in sync.

---

## 7. UI/UX Policies

### 7.1 Design System
**Color Palette**:
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

**Typography**:
| Style | Font | Usage |
|-------|------|-------|
| Headlines | Playfair Display | Titles, headings, wordmarks |
| Body & Labels | DM Sans | Body text, labels, buttons |
| Monospace | JetBrains Mono | Codes, IDs, timestamps, size chips, prices |

**Visual Rules**:
- Card radius: 16px
- Button radius: 12px
- Warm shadow: Primary-colored, 8% opacity, 12px blur
- Noise overlay: Organic texture via custom `_NoisePainter`

### 7.2 Reusable Widgets
**Core** (`lib/widgets/`): `SoleCard`, `SolePrimaryButton`, `SoleTextField`, `SoleBottomNav`, `SoleBadge`, `SoleStatusChip`, `SoleMetricCard`, `SoleProductCard`, `SoleTimeline`, `ShimmerBox`, `EmptyStateWidget`, `ErrorRetryWidget`, `CartIconButton`, `ArViewPlaceholder`

**Seller** (`lib/widgets/seller/`): `SellerMetricCard`, `SellerProductRow`, `SellerOrderCard`, `SellerInventoryRow`, `SellerWeeklyBar`, `SellerSparkline`, `SellerStatusChip`, `SellerPaymentMethodPill`, `SellerAlertChip`

### 7.3 Screen Architecture
- **Customer Shell**: Home, Store, Product Detail, Cart, Checkout, Orders, Profile
- **Seller Shell**: Dashboard, POS, Products, Orders, Reports, More
- **Admin Shell (Mobile)**: Dashboard, Users, Requests, Monitor, Profile
- **Admin Portal (Web)**: Dashboard, Users, Seller Applications, Products, Orders, Analytics, Settings

---

## 8. Testing Policies

### 8.1 Current State
- **No Unit Tests**: `test/widget_test.dart` is default Flutter template — no actual tests exist.
- **No Integration Tests**: None.
- **No E2E Tests**: None.

### 8.2 Required Before Production
- Unit tests for all services (especially `CartService`, `OrderService`, `ProductService`, `SalesService`)
- Widget tests for critical screens (Checkout, POS, Product Detail)
- Integration tests for order flow (Cart → Checkout → Order)
- RLS policy testing via Supabase CLI

### 8.3 Testing Standards
- Test files mirror `lib/` structure under `test/`
- Mock Supabase client for unit tests
- Use `flutter_test` for widget tests
- Run tests in CI pipeline before merge

---

## 9. Deployment & Release Policies

### 9.1 Mobile App Releases
- **In-App Update Checker**: Self-hosted JSON manifest (not Play Store API).
- **Manifest URLs**: Configured in `lib/constants/app_constants.dart` (`updateManifestUrl`, `updateChangelogUrl`).
- **Auto-Release via GitHub Actions**: `.github/workflows/release.yml` triggers on `vX.Y.Z` tag push:
  1. Builds release APK (debug-signed)
  2. Rewrites `releases/version.json` + prepends `releases/changelog.json` on `main`
  3. Creates GitHub Release with APK attached
- **Local Release Script**: `releases/publish.sh` (or `.bat`) — bumps version, builds APK, updates JSON, commits, creates release.

### 9.2 Versioning
- **Semantic Versioning**: `MAJOR.MINOR.PATCH` (e.g., `1.4.0`)
- **Build Number**: Incremented in `pubspec.yaml` (e.g., `1.4.0+8`)
- **Tag Format**: `vX.Y.Z` (annotated tags with release notes)

### 9.3 Admin Portal Deployment
- **Hosting**: TBD (Vercel, Netlify, or self-hosted)
- **Build**: `npm run build` → static assets
- **Env Variables**: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` in `.env`

---

## 10. Data Integrity Policies

### 10.1 Inventory Integrity
- **`inventory` Table is Authoritative**: Stock validation, checkout, and triggers use `inventory` (aggregated per size), NOT `product_variants`.
- **Sync After Every Variant Change**: `_syncInventoryFromVariants()` must run after every `product_variants` INSERT/UPDATE/DELETE.
- **Duplicate Variants Prohibited**: Cleanup script exists (`CHECKOUT_HARD_FIX_CLEANUP.sql` Step 2). Must run before production.
- **Orphaned Inventory Rows**: Backfill script exists (`CHECKOUT_HARD_FIX_CLEANUP.sql` Step 4). Must run before production.

### 10.2 Cart Integrity
- **`cart_items.size` Column Required**: Migration `20260703_add_cart_items_size.sql` adds column and backfills. `addOrUpdateItem()` stores size on every insert.
- **Clear Cart After Order**: `CartService.removeItems()` (awaited, scoped to ordered items) + `clearCart()` fallback when `server_id` unavailable.
- **Validation State Cleared on Re-check**: `_itemValidations` cleared before each validation pass to prevent stale errors.

### 10.3 Order Integrity
- **Atomic Order Creation**: `createOrder()` with `_cleanupOrphanedOrder()` rollback on failure.
- **DELETE Policy on Orders**: `auth.uid() = customer_id AND status = 'pending'` for orphan cleanup.
- **Trigger Reliability**: Both triggers have `SECURITY DEFINER` to bypass RLS on UPDATE.

---

## 11. Error Handling Policies

### 11.1 Exception Hierarchy
- Services throw typed exceptions (`StockUnavailableException`, `AuthException`, etc.)
- Providers catch → set `_errorMessage` (string) for UI
- UI shows `ErrorRetryWidget` or inline banners with action buttons

### 11.2 Stock Validation Errors
- **Pre-Submission**: `validateCartForCheckout()` shows banners for out-of-stock / insufficient-stock items with "Go to Cart" action.
- **At Submission**: Re-validates → throws `StockUnavailableException` with friendly message listing problematic items.
- **Trigger Errors**: DB trigger raises `P0001` → caught in `createOrder()` → mapped to `StockUnavailableException`.

### 11.3 Logging
- **Comprehensive Logging**: `createOrder()` logs exact payloads and raw `PostgrestException` details (code, message, details, hint).
- **No Debug Prints in Production**: Remove all `print()`/`debugPrint()` before release.

---

## 12. Documentation Policies

### 12.1 Required Documentation
- **`docs/project_doc.md`**: Comprehensive project reference (this document's source)
- **`docs/PROJECT_HANDOFF.md`**: Decisions, rationale, known issues for handoff
- **Session Logs**: `docs/SESSION_LOG_*.md` for each major work session
- **Fix Specs**: `docs/fixes/FIX_*.md` for each bug fix investigation
- **SQL References**: Verification queries, cleanup scripts in `docs/debug/` and `docs/`

### 12.2 Documentation Standards
- **Markdown Only**: All docs in `.md` format.
- **Date-Stamped**: Session logs and fix specs include dates.
- **Cross-Referenced**: Fix specs reference each other (v1→v2→v3...).
- **Code References**: Use `file_path:line_number` pattern for code references.

### 12.3 Policies Document Maintenance
- This file (`docs/policies/PROJECT_POLICIES.md`) updated with every architectural decision.
- Version bumped on policy changes.
- Reviewed quarterly for relevance.

---

## 13. Contribution & Workflow Policies

### 13.1 Branching
- **Main Branch**: `main` — protected, deployable
- **Feature Branches**: `feature/<short-description>`
- **Fix Branches**: `fix/<issue-description>`
- **Release Tags**: `vX.Y.Z` (annotated)

### 13.2 Commit Standards
- **Conventional Commits**: `type(scope): description`
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
- **Single Logical Change**: One commit per logical change.
- **No Secrets**: Never commit credentials, keys, or `.env` files.

### 13.3 Pull Requests
- **Required**: All changes to `main` via PR.
- **Review**: At least one approval (when team > 1).
- **CI Checks**: Lint, typecheck, tests must pass.
- **Documentation Updated**: If behavior changes, update relevant docs.

### 13.4 Code Review Checklist
- [ ] RLS policies correct for new/modified tables
- [ ] Triggers have `SECURITY DEFINER` if they UPDATE
- [ ] Size resolution uses shared helper (not duplicated)
- [ ] Inventory sync called after variant changes
- [ ] Cart validation uses `inventory` table
- [ ] Error messages user-friendly (no raw Postgres errors)
- [ ] No debug prints
- [ ] Deprecation warnings addressed
- [ ] Tests added/updated

---

## Appendix: Key Constants Reference

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

### User Roles
| Role | Description |
|------|-------------|
| `customer` | Browse, buy, track orders |
| `seller` | Manage store, products, POS, orders |
| `admin` | Platform oversight, approvals, analytics |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-09 | AI Assistant | Initial creation from project documentation |

---

*This document is the single source of truth for project policies. All contributors must read and follow these policies. Update this file when making architectural decisions.*