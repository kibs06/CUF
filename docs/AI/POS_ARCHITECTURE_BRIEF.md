# SoleVision POS — Architecture Brief

> Concise, code-verified reference for AI agents working on the Point of Sale system.
> **Last updated:** August 6, 2026 — verified against `pos_screen.dart`, `supabase_service.dart`, `order_service.dart`.

---

## Stack & Pattern

- Flutter + Supabase (PostgreSQL). MVVM: `Screen → Provider (ChangeNotifier) → Service → Supabase`.
- Currency: ₱ (Philippine Peso). Payment methods: **Cash**, **GCash** (PayMongo QR Ph). Card: disabled/coming soon.
- Entry: `SellerShell` tab 1 → `PosScreen` (`lib/screens/seller/pos_screen.dart`).

## Key Files

| File | Role |
|---|---|
| `lib/screens/seller/pos_screen.dart` | Main screen: product grid, order panel, checkout, GCash QR flow |
| `lib/screens/seller/pos_barcode_scanner.dart` | Full-screen barcode/QR scanner (mobile_scanner) |
| `lib/screens/seller/pos_history_screen.dart` | Past POS transactions, date-range filtered |
| `lib/screens/seller/pos_receipt_detail_screen.dart` | VAT breakdown receipt view |
| `lib/providers/order_provider.dart` | `placeOrder(source: 'pos')` |
| `lib/services/supabase_service.dart` | `createOrder()` — the single order writer |
| `lib/services/order_service.dart` | `fetchPosHistory(storeId)` |

## Critical: POS writes to `orders`, NOT `sales_transactions`

The `sales_transactions` table is **legacy/dead**. POS creates an `orders` row via `createOrder()`:

- `status = 'received'` (POS skips the pending→preparing→ready pipeline)
- `payment_status = 'paid'`, `source = 'pos'` (`'online'` for customer checkout)
- `order_status_history` row written explicitly (skips the UPDATE trigger)
- `order_items` INSERT fires the DB trigger `decrement_inventory_on_order` → `inventory.stock` (authoritative stock source is `inventory`, derived from `product_variants`)
- Cash: persists `amount_tendered` + `change_amount`. GCash: persists `gcash_reference_number`
- After sale: `syncProductActiveStatus()` per product (auto-hides products with 0 stock)

## Flow

1. **Product grid**: seller-scoped via `ProductProvider.loadSellerProducts()` → `fetchProducts(storeId:)` (app-layer filter, RLS allows all reads). Search by name/SKU/barcode; out-of-stock dimmed (opacity 0.48); ≤5 stock shows "Low (X)".
2. **Barcode**: camera scan → matches product `barcode` field → variant SKUs → product SKU; 10-entry scan history.
3. **Tap product** → bottom sheet (size + qty) → line items in `_orderItems` map keyed `'productId_size'`.
4. **Cash checkout**: tendered input → change calc → `_completePOSTransaction()` → `placeOrder(source:'pos')` → success overlay 3s.
5. **GCash checkout** (`_CheckoutSheet`): creates order upfront with `payment_status='pending'`, invokes `create-gcash-payment` edge function (PayMongo), shows QR Ph for customer to scan, waits for webhook to mark paid, then completes. Cancel deletes the pending order + items.

## Revenue Queries (must know)

- POS revenue = `orders WHERE store_id=X AND source='pos' AND status != 'cancelled' AND payment_status='paid'`.
- Online revenue = `orders` found via the **3-step chain** (`products` by store_id → `order_items` → `order_ids`), same paid/non-cancelled filter.
- Dashboard/Reports always combine both. Trend charts (`SalesService._fetchTrend`) bucket by weekday/month.

## Gotchas

- **Dual status vocabulary**: seller UI labels `confirmed`/`delivered` map to DB `preparing`/`received` — only in `SupabaseService.updateOrderStatus()`.
- Products → orders lookup needs the 3-step chain; POS history queries `orders` **directly** by `store_id + source='pos'` (no chain).
- Supabase returns `num` for prices (int when whole) — always cast `(x as num?)?.toDouble()`.
- GCash orders exist with `payment_status='pending'` between QR display and webhook — don't count them as revenue yet.
- RLS: `orders` INSERT policy is `auth.uid() = customer_id`; POS works because the seller's own auth is used as `customer_id` for walk-ins.
