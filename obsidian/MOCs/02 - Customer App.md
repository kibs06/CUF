# 📱 Customer App

> The Flutter customer experience: home, product detail, cart, checkout, tracking, customization, AR. **#moc**

---

## 📌 Overview

Customer shell has a **4-tab bottom nav** (`IndexedStack`, state preserved): **Home** (featured products, category filter, search), **Store** (multi-store discovery, follow/unfollow), **Notifications** (order-status feed), **Profile** (account, avatar, notification panel, settings). State mgmt: Provider (`ChangeNotifier`); data via singleton services → Supabase. All product data flows as `Map<String, dynamic>` — **don't refactor to typed models unless a task requires it**.

---

## 🧩 Screens

| Screen | File | Highlights |
|--------|------|------------|
| Customer Home | `lib/screens/customer/customer_home_screen.dart` | Featured products, category chips, search (`ProductProvider.getFilteredProducts`), masonry/standard grid, store cards, CUFMAI AppBar, foot-profile reminder banner placement |
| Product Detail | `lib/screens/customer/product_detail_screen.dart` | Swipeable image gallery (`PageController`, full-screen viewer), size selector via `_buildSizesMap()` (merges `inventory` + `product_variants`), "Only X left" (stock ≤ 5), Add to Cart (variant lookup via `resolveVariant()`), Buy Now (direct checkout), **AR Fitting button**, store link, loading skeleton |
| Cart | `lib/screens/customer/cart_screen.dart` | **Per-store grouping**, Select All / per-item selection, quantity controls, delete w/ confirmation, ₱100 flat delivery, sticky checkout bar, empty state |
| Checkout | `lib/screens/customer/checkout_screen.dart` | Two-step (Details → Confirmation), pre-submit stock validation banners (red out-of-stock / yellow insufficient), `_canSubmitOrder()` blocks invalid, payment radio (GCash / Cash on Pickup), address book picker, Model B fee line, submit → GCash intent or `createOrder()` |
| GCash Payment | `lib/screens/customer/gcash_payment_screen.dart` | See [[obsidian/MOCs/01 - Checkout, Orders & Payments\|💳 Checkout MOC]] — attempt #6 hosted-checkout flow |
| Order Tracking | `lib/screens/customer/tracking_screen.dart` | Vertical `SoleTimeline`: Order Placed → Being Prepared → Ready for Pickup → Received; artisan-specific copy; `awaiting_payment` + `payment_conflict` banners |
| Customization | `lib/screens/customer/customization_screen.dart` | 5-step vertical stepper (Base design → Color/dye → Upper material → Special request → Submit → `customization_requests`) |
| AR Fitting | `lib/screens/customer/ar_fitting_screen.dart` | **Simulated AR** — particle painter, size availability check vs `inventory`, variant lookup, pulse "tracking" animation; ⚠️ placeholder, no real AR |
| Notifications | `lib/screens/notifications_screen.dart` | Category tabs (Unpaid/Processing/Shipped/Review/Returns), read/unread, tap → tracking |
| Profile | `lib/screens/shared/profile_screen.dart` | Avatar upload, edit panel (email locked), notification panel w/ unread badges, settings (change password, Terms & Privacy, About CUFMAI, Business Verification entry for sellers), seller section, logout (clears state + biometrics) |
| Shared | `lib/screens/shared/terms_privacy_screen.dart` | CUFMAI Terms & Privacy — draft policy pending legal review |

---

## 🗺️ Data flow: Add to Cart → Checkout → Order

```
PRODUCT DETAIL → _addToCart() looks up variantId → CartProvider.addToCart()
  → background sync to cart_items (server-side cart, has size column)

CHECKOUT → _validateCart() → CartService.validateCartForCheckout()
  → batch-fetches INVENTORY as authoritative stock source
  → banners for out-of-stock / insufficient-stock items

SUBMIT → re-validates → OrderProvider.placeOrder() → SupabaseService.createOrder()
  1. INSERT INTO orders
  2. Batch-fetch inventory for all products
  3. Per item: resolve size from inventory → INSERT INTO order_items
  4. DB trigger decrements inventory.stock
  5. On failure: _cleanupOrphanedOrder() + batch rollback
  6. StockUnavailableException with friendly message (never raw PostgrestException)

POST-ORDER → cart cleared → confirmation screen (real order ID, Track My Order)
```

---

## 🗄️ Data model (customer-relevant)

- `cart_items` — server-side cart, `user_id → profiles`, **has `size` column** (added July 4 2026), `product_id` CASCADE.
- `customer_addresses` — address book; RLS CRUD own (fixed July 8 — policies from `20260705` migration were never applied, causing 42501 on INSERT).
- `customization_requests` — bespoke shoe requests, `customer_id`/`store_id`, `base_product_id` SET NULL.
- `store_follows` — `(user_id, store_id)` composite PK.
- `foot_measurements` / profiles foot fields — see [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth MOC]].
- `reviews` / `product_reviews` / `store_reviews` — see [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products MOC]].

## 🔐 Security / RLS

- Customers: CRUD own `cart_items`, `customer_addresses`; read all products/inventory; CRUD own orders (writes blocked while suspended via `AND NOT is_suspended()`).
- `orders` UPDATE policy tightened — store-scoped or admin; customers act via RPC/trigger-adjacent code.

## ⚠️ Gotchas

1. **Stock source of truth is `inventory`** — `product_variants` may be stale/0; checkout validates against `inventory` (missing match ⇒ out of stock).
2. `validateCartForCheckout()` was proven correct — **do not modify app-level stock logic**; the checkout bug was in the DB trigger (SECURITY DEFINER, July 4).
3. Products PK is TEXT; size resolution shared via `resolveInventoryStock()` in `lib/utils/cart_helpers.dart`.
4. Reuse `Sole*` widgets (`SoleCard`, `SolePrimaryButton`, …) and `AppConstants` style getters — don't introduce raw Material where a Sole equivalent exists.
5. Flat ₱100 delivery fee (Cebu-local assumption) — `subtotal > 0 ? 100 : 0`; delivery estimate text lives in `AppConstants.deliveryEstimateText` (3–5 business days).
6. Cart keeps items while GCash payment is awaiting; removed only on server-confirmed paid/conflict.

## 📚 Deep-dive docs

- [[docs/AI_PROJECT_SUMMARY|⚡ AI Project Summary — "Customer Experience"]] — screen-by-screen
- [[docs/CUSTOMER_MODULE_DOCUMENTATION|Customer module documentation]]
- [[docs/CUSTOMER_ARCHITECTURE|Customer architecture]]
- [[docs/AI/CUSTOMER_MODULE_CONTEXT|Customer module context]]
- [[docs/AI/CUSTOMER_HOME_ARCHITECTURE|Customer home architecture]]
- [[docs/AI/HOME_MASONRY_GRID_WIDGETS|Home masonry grid widgets]]
- [[docs/AI/HOME_ON_SALE_ARCHITECTURE|Home "On Sale" architecture]]
- [[docs/AI/MY_ORDERS_ARCHITECTURE|My Orders architecture]] — real order badges
- [[docs/AI/DELIVERY_FEE_AND_MAP_ARCHITECTURE|Delivery fee & map architecture]]
- [[docs/AI/AR_TRY_ON_ARCHITECTURE|AR try-on architecture]] (simulated)
- [[docs/ar_fitting_addToCart_reference|AR fitting add-to-cart reference]]
- [[docs/AI/PRODUCT_REVIEWS_ROADMAP|Product reviews roadmap]] · [[docs/AI/PRODUCT_REVIEWS_ROADMAP_v2|v2]]
- [[docs/needs/PROFILE_AND_STORE_FOLLOW_ARCHITECTURE|Profile & store follow architecture]]
- [[docs/AI/feature_file_lookup_guide|🔍 Feature file lookup guide]] — 8 customer-facing features mapped to files

## 🔗 Related

- [[obsidian/MOCs/01 - Checkout, Orders & Payments|💳 Checkout, Orders & Payments]]
- [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products, Stores & Features]]
- [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Notifications & Messaging]]
