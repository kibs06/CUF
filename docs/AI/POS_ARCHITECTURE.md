# SoleVision — POS Architecture

> **Concise reference for AI agents working on the Point of Sale system.**
> **Last updated:** July 25, 2026
> **Revisions:** Added POS history feature, `source` column, `fetchPosHistory()` query pattern.

---

## Quick Facts

| Item | Value |
|------|-------|
| **Stack** | Flutter + Supabase (PostgreSQL) |
| **State management** | ChangeNotifier + Provider |
| **Currency** | Philippine Peso (₱) |
| **Payment methods** | Cash, GCash (Card disabled/coming soon) |
| **Product scoping** | Seller-scoped via `loadSellerProducts()` → `fetchProducts(storeId:)` |

---

## File Map

| File | Role |
|------|------|
| `lib/screens/seller/pos_screen.dart` | Main POS screen — product grid, order panel, checkout |
| `lib/providers/product_provider.dart` | `loadSellerProducts()` scopes products to current seller's store |
| `lib/providers/order_provider.dart` | `placeOrder()` delegates to `SupabaseService.createOrder()` |
| `lib/providers/auth_provider.dart` | Current user profile (used for `customerId`) |
| `lib/services/supabase_service.dart` | `fetchProducts(storeId:)`, `createOrder()`, `_mapProduct()` |
| `lib/services/product_service.dart` | `getSellerStoreId()`, `syncProductActiveStatus()` |
| `lib/services/sales_service.dart` | Revenue queries (online + POS combined) |
| `lib/screens/seller/pos_history_screen.dart` | POS transaction history with date range filtering |
| `lib/widgets/seller/payment_method_pill.dart` | Cash/GCash/Card selector pills |

---

## POS Transaction Flow

```
┌──────────────────────────────────────────────────────────────┐
│  1. Product Grid (Panel 0)                                    │
│     • Loads via ProductProvider.loadSellerProducts()          │
│     • Scoped server-side: fetchProducts(storeId: sellerStore) │
│     • Searchable by name/SKU, filterable by category          │
│     • Out-of-stock products dimmed (opacity 0.48)             │
│                                                              │
│  2. Tap Product → Size/Qty Bottom Sheet                       │
│     • Shows available sizes from product['sizes'] map         │
│     • Quantity +/- controls                                   │
│     • "Add to Order ₱XXX" button                             │
│                                                              │
│  3. Order Panel (Panel 1)                                     │
│     • Line items in _orderItems map (key: 'productId_size')   │
│     • Quantity adjust per item, delete per item               │
│     • Subtotal summary                                        │
│                                                              │
│  4. Checkout → Payment Sheet                                  │
│     • Cash: tendered input → calculates change                │
│     • GCash: no tendered input                                │
│     • "Confirm Payment ₱XXX" button                          │
│                                                              │
│  5. _completePOSTransaction()                                 │
│     a. OrderProvider.placeOrder(source: 'pos')                │
│        └─ SupabaseService.createOrder()                       │
│           ├─ INSERT orders (status='received', source='pos')  │
│           ├─ INSERT order_items (triggers inventory decrement) │
│           └─ SellerNotificationService.createNewOrder()       │
│     b. ProductService.syncProductActiveStatus() per product   │
│     c. Clear order, show success overlay (3s)                 │
└──────────────────────────────────────────────────────────────┘
```

---

## Key Data Model

```dart
// In-memory line item (not persisted until checkout)
class _POSLineItem {
  final Map<String, dynamic> product;  // Full product map from Supabase
  final String size;
  int quantity;
}

// Product map shape (after _mapProduct transformation):
{
  'id': 'uuid-text',
  'name': 'Carcar Heritage Oxford',
  'price': 1299.0,
  'category': 'Formal',
  'store_id': 'uuid',
  'store_name': 'Valladolid Leather Co.',
  'images': ['url1', 'url2'],           // Flattened URLs
  'sizes': {'8': 10, '9': 5, '10': 0}, // size → stock map
  'sku': 'CHO-001',
  'is_active': true,
}
```

---

## Database Tables Involved

| Table | POS writes? | Notes |
|-------|-------------|-------|
| `orders` | ✅ INSERT | POS: `status='received'`, `payment_status='paid'`, `source='pos'`. Online: `status='pending'`. |
| `order_items` | ✅ INSERT | Triggers `decrement_inventory_on_order` |
| `inventory` | ⚠️ Trigger | Stock decremented by DB trigger on order_items INSERT |
| `products` | ❌ Read-only | Products loaded via `fetchProducts(storeId:)` |
| `product_variants` | ❌ Read-only | Read for size/stock info |
| `product_images` | ❌ Read-only | Read for display |
| `sales_transactions` | ❌ Not used by POS screen | Used by `SalesService` for POS reporting |
| `seller_notifications` | ⚠️ Fire-and-forget | `createNewOrder()` after order creation |
| `order_status_history` | ✅ INSERT (POS only) | Written explicitly for POS orders since they skip the UPDATE trigger |

---

## Product Scoping (Critical)

The POS screen uses `ProductProvider.loadSellerProducts()` which:
1. Gets `storeId` via `ProductService.getSellerStoreId()`
2. Calls `SupabaseService.fetchProducts(storeId: storeId)`
3. Server-side filter: `.eq('store_id', storeId)` on the products query

**This ensures each seller only sees their own products.** Customer-facing screens use `loadProducts()` (no scoping) to show all products.

```dart
// ProductProvider — seller-scoped loading
Future<void> loadSellerProducts() async {
  final storeId = await ProductService.instance.getSellerStoreId();
  _products = await _db.fetchProducts(storeId: storeId);  // server-side filter
}

// SupabaseService — optional store filter
Future<List<Map<String, dynamic>>> fetchProducts({String? storeId}) async {
  var query = _client.from('products').select('*, ...');
  if (storeId != null) {
    query = query.eq('store_id', storeId);  // ← scoping happens here
  }
  return (await query.order('created_at', ascending: false))
      .map((row) => _mapProduct(Map<String, dynamic>.from(row)))
      .toList();
}
```

---

## Dual Status Problem

**Online orders** start with `status='pending'`. The seller then progresses through:

| DB Value | Seller UI Label | Customer UI Label |
|----------|-----------------|-------------------|
| `pending` | "Pending" | "Processing" tab |
| `preparing` | "Confirmed" | Timeline step 2 |
| `ready` | "Ready" | Timeline step 3 |
| `received` | "Delivered" | Timeline step 4 |
| `cancelled` | "Cancelled" | "Returns" tab |

**Mapping layer** in `SupabaseService.updateOrderStatus()`:
```dart
'confirmed' → 'preparing'  // UI → DB
'delivered' → 'received'   // UI → DB
```

---

## Inventory Decrement

When order_items are inserted, a PostgreSQL trigger fires:

```sql
-- Trigger: decrement_inventory_on_order
-- Fires: AFTER INSERT on order_items
-- Decrements inventory.stock for the matching (product_id, size)
```

After a POS sale, `syncProductActiveStatus(productId)` is called for each product to auto-set `is_active` based on whether any size still has stock > 0.

---

## Revenue Calculation

Revenue ALWAYS combines both sources:
```dart
getTodayRevenue(storeId) = getOnlineTodayRevenue(storeId) + fetchTodaySales(storeId)
//                          ↑ from orders table              ↑ from sales_transactions table
```

The 3-step chain to find a store's orders:
```sql
-- Step 1: products → product IDs
SELECT id FROM products WHERE store_id = 'STORE_ID';
-- Step 2: order_items → order IDs
SELECT DISTINCT order_id FROM order_items WHERE product_id IN (...);
-- Step 3: orders
SELECT * FROM orders WHERE id IN (...) ORDER BY created_at DESC;
```

---

## POS History Feature

The history icon (clock icon in POS header) opens `PosHistoryScreen` — a pushed screen showing past **POS-only** transactions scoped to the current seller's store.

### Source Column

The `orders` table has a `source` column (`TEXT NOT NULL DEFAULT 'online'`) that distinguishes order origin:
- `'pos'` — in-person sale made through the POS screen
- `'online'` — customer checkout from the app

POS orders are also created with `status='received'` and `payment_status='paid'` directly (skipping the `pending → preparing → ready → received` pipeline used by online orders).

### Query Pattern: `fetchPosHistory()`

Located in `lib/services/order_service.dart`. Queries orders **directly** by `store_id` + `source='pos'` (no 3-step chain needed since `orders.store_id` is reliably set during order creation):

```dart
Future<List<Map<String, dynamic>>> fetchPosHistory(String storeId) async {
  final data = await _client
      .from('orders')
      .select('id, customer_id, status, total_amount, payment_method, '
              'payment_status, notes, created_at, source')
      .eq('store_id', storeId)
      .eq('source', 'pos')
      .order('created_at', ascending: false);
  // ... then fetches order_items + product names for display
}
```

### Screen Features

- **Date range filtering**: All / Today / This Week / This Month (client-side via `_filteredTransactions` getter)
- **Revenue summary bar**: Shows count + total for the selected range (hidden for "All")
- **Date section headers**: "Today" / "Yesterday" / "Jul 25, 2026" group cards when scrolling multi-day ranges
- **Transaction card fields**: Order ID (truncated), date/time, items summary, payment method pill, total, status chip
- **States**: Loading spinner, empty state (no POS sales yet), error state with retry button
- **Refresh**: Pull-to-refresh + refresh button in app bar
- **Connectivity**: Automatically reloads when coming back online

### Key Files

| File | Role |
|------|------|
| `lib/screens/seller/pos_history_screen.dart` | History screen with date filtering and date-grouped list |
| `lib/services/order_service.dart` | `fetchPosHistory(storeId)` — direct query by store_id + source='pos' |
| `lib/screens/seller/pos_screen.dart` | History icon `onPressed` pushes `PosHistoryScreen` |

---

## RLS Policies (POS Scope)

| Table | Operation | Policy |
|-------|-----------|--------|
| `products` | SELECT | Anyone can read (RLS allows all) |
| `orders` | INSERT | `auth.uid() = customer_id` |
| `order_items` | INSERT | `auth.uid() = customer_id` of parent order |
| `inventory` | UPDATE | Trigger-managed (SECURITY DEFINER) |

**Note:** The `products` table RLS allows anyone to read — the POS scoping is enforced at the **application layer** via `fetchProducts(storeId:)`, not at the RLS level. This is by design (customers need to see all products).

---

## Gotchas

| Gotcha | Detail |
|--------|--------|
| **POS creates orders, not just transactions** | `OrderProvider.placeOrder()` creates `orders` + `order_items` rows |
| **POS orders skip the pending pipeline** | POS orders are created with `status='received'` and `payment_status='paid'` directly. Online orders start at `pending`.
| **Order source tracking** | `orders.source` column: `'pos'` for in-person, `'online'` for customer checkout. Used to distinguish order origin.
| **Inventory is derived** | `inventory` table is synced from `product_variants` via `_syncInventoryFromVariants()` |
| **Stock validation** | Uses `inventory.stock` as authoritative, not `product_variants.stock` |
| **Price is `num`** | Supabase returns `int` for whole numbers, `double` for decimals — always cast via `(x as num?)?.toDouble()` |
| **Success overlay** | Shows for 3 seconds, includes change amount for cash payments |
| **No receipt printing** | Receipt button is a stub |
| **POS history is live** | History icon opens `PosHistoryScreen` — shows POS-only transactions scoped to seller's store, with date range filtering (Today / This Week / This Month). |
