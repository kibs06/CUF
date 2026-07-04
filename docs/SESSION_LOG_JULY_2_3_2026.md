# SoleVision — Session Log: July 2–3, 2026

**Date Range:** July 2, 2026 → July 3, 2026  
**Focus:** Checkout flow overhaul, stock validation, error handling, stock mismatch fix, and multiple bug fixes  
**Status:** ✅ **DB trigger fixed + app-layer hardened — awaiting end-to-end verification**

---

## Table of Contents

1. [Session Overview](#session-overview)
2. [July 2 — Checkout Flow Overhaul](#july-2--checkout-flow-overhaul)
3. [July 3 — Error Handling & Stock Validation](#july-3--error-handling--stock-validation)
4. [Files Changed](#files-changed)
5. [Known Issues & Open Bugs](#known-issues--open-bugs)
6. [Technical Deep Dives](#technical-deep-dives)
7. [Next Steps](#next-steps)

---

## Session Overview

Over two days of intensive debugging and feature work, we tackled the entire checkout and order placement pipeline in SoleVision. The session started with fundamental issues in how orders were created (only first item getting an order_item, wrong pricing, fake order IDs) and evolved into a comprehensive overhaul of error handling, stock validation, and customer-facing messaging.

### Key Themes
- **Data flow integrity:** Cart items lose critical data (size, stock) during server sync due to missing columns and broken JOINs
- **DB trigger vs. app data mismatch:** A Postgres function checks stock in the `inventory` table, but the app sometimes inserts sizes in a different format (e.g., "EU40" vs "40")
- **Error surfacing:** Raw `PostgrestException` objects were being displayed directly to customers
- **Pre-submission validation:** Stock problems were only caught at the DB level, after the customer filled in the entire checkout form

---

## July 2 — Checkout Flow Overhaul

### Problem Statement
The original checkout flow had multiple critical bugs:

1. **Only first item received an `order_items` row** — the old code called `placeOrder` per item in a loop but the order creation only inserted one item
2. **Wrong `unit_price`** — calculated as `total / quantity` instead of using the actual item price
3. **`cart.total` used instead of `selectedTotal`** — selected items' total wasn't isolated
4. **Items started deselected** — customers had to manually re-select everything
5. **Confirmation showed fake order ID** — used a local variable instead of the real DB-generated ID
6. **"Track My Order" went nowhere** — navigation to tracking screen was broken
7. **Products vanished on checkout** — validation auto-removed items from cart

### Changes Made

#### `lib/providers/order_provider.dart`
- Changed `placeOrder()` to accept a `List<Map<String, dynamic>> items` parameter instead of individual product fields
- Order is now created ONCE with multiple `order_items` rows

#### `lib/services/supabase_service.dart`
- `createOrder()` now loops through the items list and inserts one `order_item` per product
- Each `order_item` gets the correct `unit_price` from the item data (not calculated)
- Added per-step try/catch blocks with descriptive error messages for debugging

#### `lib/screens/customer/checkout_screen.dart`
- **Complete rewrite** of the checkout screen:
  - Added Order Summary section showing all selected items with images, sizes, colors, quantities
  - Validation now shows warnings instead of auto-removing items
  - `_submitCheckout()` builds a multi-item order and uses `selectedTotal`
  - Confirmation screen shows real order ID from DB
  - "Track My Order" navigates to `OrderTrackingScreen` with real order data

#### `lib/providers/cart_provider.dart`
- New cart items are **auto-selected** (`_selectedKeys.add(cartKey)`) so they're ready for checkout
- `_syncFromServer()` now preserves `size` and `color` from existing local items when server returns empty (handles the `product_variants` LEFT JOIN returning null)

#### `lib/models/cart_item_with_details.dart`
- Added `cartQuantity` and `insufficientStock` fields to `CartValidationResult`

### Bugs Fixed
- ✅ Multi-item order creation
- ✅ Correct unit pricing
- ✅ Selected item total isolation
- ✅ Auto-selection of new cart items
- ✅ Real order ID in confirmation
- ✅ Working "Track My Order" navigation
- ✅ No more auto-removal of cart items during validation

---

## July 3 — Error Handling & Stock Validation

### Problem Statement
The DB-level stock check (a Postgres function/trigger with `RAISE EXCEPTION` using code `P0001`) was firing correctly but:

1. **Raw `PostgrestException` was shown to customers** — including Dart class names, Postgres error codes, and internal hint/details fields
2. **Stock problems were only caught at DB insert time** — after the customer filled in address, phone, and payment method
3. **No visual indication of low/out-of-stock items** in the checkout summary

### Task: Fix Raw Error Exposure + Add Stock Validation

Based on a detailed task specification (`# Task Fix Raw Error Exposure at Ch.md`), we implemented a three-part solution:

### Changes Made

#### 1. Custom Exception — `lib/exceptions/stock_unavailable_exception.dart` (NEW)
- Created `StockUnavailableException` with:
  - `productName`, `size`, `requestedQty`, `availableStock` fields
  - `friendlyMessage` getter that returns clean, customer-safe text
  - Example: *"Demo Sandals (size 10) only has 2 left in stock. Please reduce the quantity to continue."*

#### 2. Service Layer — `lib/services/supabase_service.dart`
- `createOrder()` catches `PostgrestException` with code `P0001` and `insufficient stock` in the message
- Throws `StockUnavailableException` instead of letting raw errors propagate
- Other errors rethrow for the provider to handle with a generic message
- **Size resolution overhaul:** Always resolves size from the `inventory` table to match the DB trigger's expected format:
  1. Exact match first (e.g., "EU40" == "EU40")
  2. Numeric match — strips "EU"/"US" prefix (e.g., "EU40" → "40" matches inventory "40")
  3. Fallback to first available size from inventory

#### 3. Provider Layer — `lib/providers/order_provider.dart`
- Added `_stockError` field and `stockError` getter
- `placeOrder()` catches `StockUnavailableException` separately:
  - Stores `friendlyMessage` in `_errorMessage`
  - Stores the exception in `_stockError` for the checkout screen to detect
- All other exceptions show a generic: *"Something went wrong placing your order. Please try again."*
- **Never surfaces raw technical details to the customer**

#### 4. Checkout Screen — `lib/screens/customer/checkout_screen.dart`
- **Pre-submission validation:**
  - `_validateCart()` now checks live stock for every cart item on load
  - Shows **out-of-stock banners** (red, with error icon) for unavailable items
  - Shows **insufficient-stock banners** for items where cart quantity > available stock
  - `_canSubmitOrder()` blocks "Complete Order" button when any item fails validation
  - `_submitCheckout()` re-validates stock immediately before submission (race-condition guard)
- **Error handling on failure:**
  - Shows `stockErr.friendlyMessage` for stock errors (not generic text)
  - Shows *"Something went wrong placing your order..."* for other errors
  - Stock errors include a **"Go to Cart"** action button that navigates back
  - Never shows `e.message` or `e.toString()` in the UI

#### 5. Cart Validation — `lib/services/cart_service.dart`
- `validateCartForCheckout()` now:
  - Passes `cartQuantity` from the current cart items
  - Computes `insufficientStock` (`cartQty > serverItem.stock`)
  - **Inventory fallback:** When `product_variants` LEFT JOIN returns null (no variant entries), batch-fetches stock from the `inventory` table

#### 6. Cart Service — `lib/services/cart_service.dart` (fetchCart)
- Added inventory fallback for products without `product_variants` entries:
  - Collects product IDs where variant is null
  - Batch-fetches from `inventory` table with `gt('stock', 0)`
  - Resolves `size` from inventory when variant is null
  - Resolves `stock` from inventory when variant stock is 0

#### 7. Product Detail Screen — `lib/screens/customer/product_detail_screen.dart`
- Size chips now show **"Only X left"** label when stock ≤ 5
- Helps customers make informed decisions before adding to cart

### Bugs Fixed
- ✅ Raw exceptions no longer shown to customers
- ✅ Stock problems caught before "Place Order" is tapped
- ✅ Out-of-stock items visually flagged and block submission
- ✅ Low stock warnings on product detail screen
- ✅ Friendly error messages with actionable "Go to Cart" button
- ✅ Generic fallback for non-stock errors

---

## Files Changed

| File | Status | Summary |
|------|--------|---------|
| `lib/exceptions/stock_unavailable_exception.dart` | **NEW** | Custom exception with `friendlyMessage` getter |
| `lib/services/supabase_service.dart` | Modified | P0001 → `StockUnavailableException`, size resolution from inventory, batched N+1 queries |
| `lib/providers/order_provider.dart` | Modified | `stockError` field, separate catch for stock vs other errors, generic fallback messages |
| `lib/screens/customer/checkout_screen.dart` | **Rewritten** | Full checkout UI with order summary, stock validation banners, pre-submission re-validation, friendly error snackbar |
| `lib/services/cart_service.dart` | Modified | `validateCartForCheckout` adds `cartQuantity`/`insufficientStock`, `fetchCart` adds inventory fallback for null variants |
| `lib/models/cart_item_with_details.dart` | Modified | Added `cartQuantity` and `insufficientStock` to `CartValidationResult` |
| `lib/providers/cart_provider.dart` | Modified | Auto-select new items, preserve size/color during server sync |
| `lib/screens/customer/product_detail_screen.dart` | Modified | "Only X left" low-stock labels on size chips |

---

## Known Issues & Open Bugs

### ✅ RESOLVED — Complete Order Stock Mismatch (July 3, v2 fix spec)

**Original Symptom:** Tapping "Complete Order" failed for ALL products with:
> *"Insufficient stock for product [id] size [size]"*

Despite the seller dashboard showing plenty of stock.

**Confirmed Root Cause:**
Two Postgres trigger functions — `decrement_inventory_on_order` and `decrement_inventory_on_sale` — did an **exact string match** on `size`. `inventory` stores bare numbers (`"38"`, `"40"`), while `product_variants`/the app stores prefixed sizes (`"EU40"`, "EU41""). Exact match never found a row → `P0001: Insufficient stock` for every order.

**Fix Applied:**
- ✅ **DB layer (deployed):** Both `decrement_inventory_on_order()` and `decrement_inventory_on_sale()` now normalize size via `regexp_replace(size, '\D', '', 'g')` before comparing
- ✅ **App layer (this session):** `createOrder()` resolves size from inventory (exact → numeric strip → fallback) with batched queries
- ✅ **POS layer (this session):** `recordSale()` in `sales_service.dart` now also resolves size from inventory for `sales_transaction_items` inserts
- ✅ **Pre-submission validation:** Checkout blocks "Place Order" for out-of-stock / insufficient-stock items
- ✅ **Friendly error handling:** `StockUnavailableException` with customer-safe messages, never raw PostgrestException

**Still Needs Verification (run the SQL in `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql`):**
1. Place a real test order for `demo_2` / EU40 and confirm inventory decremented
2. Rule out non-numeric sizes (Step 2 queries)
3. Check for orphaned inventory rows (Step 3 queries)
4. Backfill if needed (Step 4 queries — only if Step 3 finds orphans)

### 🟡 Minor — Data Model Gap
- `cart_items` table has no `size` column — size is only available through `product_variants` LEFT JOIN
- When variant is null, size is lost during server sync (partially mitigated by `_syncFromServer` preserving local sizes)
- **Recommended:** Add `size TEXT` column to `cart_items` table via SQL migration

### ℹ️ Pre-existing — Deprecation Warnings
- `RadioListTile.groupValue` and `onChanged` are deprecated (use `RadioGroup`)
- `.withOpacity()` is deprecated in 16 places in `product_detail_screen.dart` (use `.withValues()`)

---

## Technical Deep Dives

### The Cart Data Flow Problem

```
User selects size "EU40" on product detail
  → addToCart(size: "EU40", variantId: "123")
  → Cart stored locally with size: "EU40"
  → Background sync to Supabase: cart_items.variant_id = "123"

Server sync (on app start or auth change):
  → fetchCart() does: cart_items LEFT JOIN product_variants ON variant_id
  → If variant exists: size = "EU40" (from variant) ✓
  → If variant is null: size = "" (lost!) ✗
  → If variant exists but inventory has "40": size = "EU40" (mismatch!) ✗

Order creation:
  → createOrder() inserts order_items with size = "EU40"
  → DB trigger: SELECT stock FROM inventory WHERE size = "EU40"
  → inventory has "40" not "EU40" → no match → "Insufficient stock" ✗
```

### The Two Stock Tables

SoleVision has **two** stock-tracking tables:

| Table | Primary Key | Used By | Notes |
|-------|-------------|---------|-------|
| `inventory` | `(product_id, size)` | `addProduct`, `_upsertInventory`, DB trigger | Aggregated stock by size |
| `product_variants` | `(id)` with `(product_id, size, color)` | Variant system, `fetchCart` JOIN | Per-variant stock with color |

The DB trigger checks `inventory`. The app sometimes reads from `product_variants`. When these have different size formats or stock values, orders fail.

### The `fetchCart` Inventory Fallback

When `product_variants` LEFT JOIN returns null (no variant entry for the product):

```dart
// 1. Collect products needing fallback
fallbackProductIds = {products where variant is null}

// 2. Batch-fetch from inventory
invRows = SELECT product_id, size, stock FROM inventory 
          WHERE product_id IN (fallbackProductIds) AND stock > 0

// 3. For each cart item:
size = variant?['size'] ?? inventorySizes[productId]  // prefer variant, fallback inventory
stock = variant?['stock'] ?? inventoryStock[key]       // prefer variant, fallback inventory
```

---

## Next Steps

1. **Run end-to-end verification** — Place a real test order for `demo_2` and run the SQL in `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql`
2. **Rule out non-numeric sizes** — Run Step 2 queries in Supabase SQL editor
3. **Check for orphaned inventory rows** — Run Step 3 queries; if found, run Step 4 backfill
4. **Add `size` column to `cart_items`** — SQL migration to store size directly, eliminating the LEFT JOIN dependency
5. **Extract shared size-resolution helper** — Code reviewer noted the exact→numeric→fallback logic is duplicated in `createOrder()`, `recordSale()`, and `fetchCart()` — extract to a shared utility method
6. **POS pre-submission stock validation** — Seller-side POS screen currently has no stock check before completing a sale

---

*Document generated by Buffy (Codebuff AI assistant) on July 3, 2026*
