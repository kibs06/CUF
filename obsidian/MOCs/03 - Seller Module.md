# 👞 Seller Module

> The artisan side: dashboard, POS, product & inventory management, orders, reports, business verification. **#moc**

---

## 📌 Overview

The seller app lives in `SellerShell` — a 5-tab host (`IndexedStack`, state survives tab switches). Tab 0 is the **Seller Dashboard** ("morning briefing": sales, attention, orders, stock). Sellers are CUFMAI member artisans; access is gated by `profiles.seller_status = 'approved'` + role flip to `seller` on admin approval. Revenue ALWAYS combines online `orders` + POS `sales_transactions`, filtered `status != 'cancelled'` AND `payment_status = 'paid'`.

---

## 🗺️ Seller Dashboard — architecture

```
SellerShell → Tab 0: SellerDashboardScreen
  ├─ AppBar (CUFMAI brand + greeting + message bell + notification bell)
  ├─ Block 1    Today's Snapshot — 4 metric cards (Today Sales / Week / Low Stock / Custom Orders)
  ├─ Block 1.5  GCash Payments to Confirm card (live count, 30s poll)
  ├─ Block 2    "Needs Attention" alert strip (low stock + stale orders + customs)
  ├─ Block 3    Order Status Summary (placed / preparing / ready / received)
  ├─ Block 4    Recent Orders (limit 3) → OrderDetailScreen
  ├─ Block 5    Weekly stacked-area chart (Online + In-Store)
  ├─ Block 6    Monthly stacked-area chart
  ├─ Block 7    Revenue breakdown doughnut (online vs in-store)
  └─ Block 8    "View Full Sales Report" CTA → ReportsScreen
```

**Key mechanics:**
- **One-shot future, not a provider** — all data in a single `Future<_DashboardData>` from `_fetchDashboardData()` (initState post-frame, pull-to-refresh, offline→online reconnect). No periodic polling except Block 1.5.
- **12-way `Future.wait`** — fires 12 fetches concurrently (today revenue, recent orders limit 3, order counts by status, store, weekly/monthly online+POS revenue, weekly/monthly trends, `ProductProvider.loadSellerProducts()`, `OrderProvider.loadOrders()`). Index order matters — keep in sync when editing.
- **Two order-fetch paths can disagree** — Recent Orders uses `OrderService.getRecentOrders()` (lean, limit 3); stale-order alerts use `OrderProvider.loadOrders()` (fat, all orders).
- **Read-only dashboard** — status changes are deliberately NOT possible here (`onPrimaryAction: () {}`); they belong in Orders tab / Order Detail.
- **Stale orders** = first 2 with `status == 'placed'`; fire-and-forget `SellerNotificationService.createStaleOrder()`.
- **Low stock** = every product/size with `0 < qty <= 5` (from `products.sizes` map).

---

## 🧩 Key screens & files

| File | Role |
|------|------|
| `lib/screens/seller/seller_shell.dart` | 5-tab host (Dashboard, Orders, Products, POS, More/Profile) |
| `lib/screens/seller/seller_dashboard_screen.dart` | The dashboard above (`_DashboardData` :37, `_fetchDashboardData` :138, `_buildDashboardBody` :423, `_PaymentsToConfirmCard` :1054) |
| `lib/screens/seller/seller_orders_screen.dart` | Order management (status updates) |
| `lib/screens/seller/manage_products_screen.dart` | Product grid, "Low Stock" filter entry |
| `lib/screens/seller/pos_screen.dart` | POS with `_CheckoutSheet` (Cash / static-QR GCash); barcode scanner (`pos_barcode_scanner.dart`) |
| `lib/screens/seller/reports_screen.dart` | Weekly/monthly toggle, top-5 products, WoW comparison, CSV export stub |
| `lib/screens/seller/seller_business_verification_screen.dart` | Tier 2 DTI/BIR/permit uploads (post-approval, optional) |
| `lib/screens/seller/seller_notification_center_screen.dart` | Seller notification feed |
| `lib/screens/seller/seller_inbox_screen.dart` | Message inbox (`ChatView` viewerRole: 'seller') |
| `lib/screens/seller/store_profile_screen.dart` | Store branding, stories, ratings |
| `lib/screens/seller/store_schedule_screen.dart` | Open/closed toggle + schedule |
| `lib/screens/seller/store_reviews_screen.dart` | Store review list + seller replies |
| `lib/screens/seller/create_store_screen.dart` | Create new store |
| `lib/screens/seller/edit_store_screen.dart` | Edit store details |
| `lib/screens/seller/store_location_picker_screen.dart` | Map-based store location picker |
| `lib/screens/seller/pos_history_screen.dart` | POS transaction history |
| `lib/screens/seller/pos_receipt_detail_screen.dart` | POS receipt detail view |
| `lib/screens/seller/gcash_ref_scanner_screen.dart` | GCash reference number scanner |
| `lib/screens/seller/order_detail_screen.dart` | Individual order detail view |
| `lib/services/sales_service.dart` | Revenue/today/weekly/monthly/trend queries (online+POS combined) |
| `lib/services/order_service.dart` | `getRecentOrders`, `getOrderCountByStatus`, store order filtering |
| `lib/services/product_service.dart` | Product CRUD, images, variants, `_syncInventoryFromVariants()`, `syncProductActiveStatus()` |
| `lib/services/store_service.dart` | Store CRUD, follow/unfollow, stories |
| `lib/providers/product_provider.dart` / `order_provider.dart` | Shared seller state |

---

## 💳 POS (Point of Sale)

- Walk-in transactions: `sales_transactions` + `sales_transaction_items` (`product_id` SET NULL on delete).
- Cash: `payment_status='paid'` at insert. GCash: static seller QR → `status='received'`, `payment_status='pending'` → seller taps "Payment Received" → `paid` (+ optional reference number).
- Barcode/QR scanner (`pos_barcode_scanner.dart`, mobile_scanner) for quick checkout.
- POS is **untouched** by the online GCash redesigns.

## 🛍️ Products & inventory

- **Two stock tables that must never drift**: `product_variants` (per size+color, authoritative for the edit form) ↔ `inventory` (aggregated per size, **authoritative for checkout/customer browse/Adjust Stock**).
- Two sync directions: seller form edits variants → `_syncInventoryFromVariants()` regenerates inventory; **Adjust Stock** writes inventory → `_syncVariantStock()` distributes onto variant rows. Breaking the loop silently wipes adjustments.
- `is_active` auto-synced to stock levels; products hide from customer browse exactly when unpurchasable (`purchasableProducts()` in `lib/utils/product_stock.dart`).
- Delete is hard with FK SET NULL on history tables (`order_items`, `sales_transaction_items`, `customization_requests`).
- Store rating: `stores.rating` maintained by trigger `refresh_store_rating()` (SECURITY DEFINER) from `reviews` + `product_reviews` + `store_reviews` — see [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products MOC]].

## 🗄️ Data model

- `stores` — `owner_id → profiles`, branding, `gcash_qr_url`/`gcash_number`/`gcash_account_name`, `rating` (`NUMERIC(2,1)`), `is_open`. ⚠️ `products.store_id`/`orders.store_id` FKs have **NO cascade** — only sales_transactions, story_entries, store_follows, seller_notifications, conversations, reviews, store_reviews cascade. Deleting a store requires reassigning children first (`20260709_one_store_per_seller.sql`).
- `sales_transactions` / `sales_transaction_items` — POS rows; trigger `decrement_inventory_on_sale()`.
- `products` — `id TEXT` PK (gen_random_uuid()::text), `sale_price`/`sale_starts_at`/`sale_ends_at`, `is_published`, `seller_id` **nullable**.
- `customization_requests` — custom orders, seller processes via `CustomOrdersScreen`.

## ⚠️ Gotchas

1. **Revenue must combine online + POS** — never one alone; filters `status != 'cancelled'` AND `payment_status = 'paid'`. POS GCash revenue appears slightly late (pending until poller flips it).
2. **`seller_id` nullable on products** — legacy/unassigned rows exist.
3. **Store order filtering** is a 3-step chain: products WHERE store_id → order_items → orders.
4. `isFollowing()` (sync) in `StoreService` is a stub that always returns false — use `isFollowingAsync()`.
5. CSV export on Reports is a **stub** (SnackBar only).
6. Full rebuild after service-layer changes — hot reload insufficient.

## 📚 Deep-dive docs

- [[docs/SELLER_MODULE_GUIDE|Seller module guide]] — module-wide reference
- [[docs/AI/SELLER_DASHBOARD_ARCHITECTURE|Seller dashboard architecture]] — the dashboard in full detail
- [[docs/AI/SELLER_ARCHITECTURE_GRAPH|Seller architecture graph]]
- [[docs/AI/SELLER_RECENT_ORDERS_ARCHITECTURE|Seller recent orders architecture]]
- [[docs/AI/SELLER_ORDER_FLOW_ARCHITECTURE|Seller order flow architecture]]
- [[docs/seller-order-flow-architecture|Seller order flow (top-level copy)]]
- [[docs/AI/SELLER_POS_ARCHITECTURE|Seller POS architecture]]
- [[docs/AI/POS_ARCHITECTURE|POS architecture]] · [[docs/AI/POS_ARCHITECTURE_BRIEF|POS brief]] · [[docs/AI/POS_ADD_TO_ORDER_SOURCE|POS add-to-order source]]
- [[docs/AI/seller_products_architecture|Seller products architecture]]
- [[docs/AI/seller_profile_architecture|Seller profile architecture]]
- [[docs/AI/PRODUCT_ARCHITECTURE|Product architecture]] — stock system + Adjust Stock deep dive
- [[docs/AI/REVENUE_ARCHITECTURE|Revenue architecture]]
- [[docs/product_delete_and_auto_deactivation|Product delete & auto-deactivation]]

## 🔗 Related

- [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products, Stores & Features]]
- [[obsidian/MOCs/01 - Checkout, Orders & Payments|💳 Checkout, Orders & Payments]]
- [[obsidian/MOCs/05 - Database & Supabase|🗄️ Database & Supabase]] — inventory, triggers
