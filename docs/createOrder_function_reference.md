# `createOrder()` — Full Function Reference

**File:** `lib/services/supabase_service.dart`  
**Lines:** ~234–345  
**Last updated:** July 3, 2026  

---

## How it works (annotated)

```
createOrder(orderData)
  │
  ├─ 1. Extract userId + items list from orderData
  │
  ├─ 2. Look up store_id from the first product
  │     → SELECT id, store_id, price FROM products WHERE id = items[0].product_id
  │
  ├─ 3. Insert the order row
  │     → INSERT INTO orders (customer_id, store_id, status, total_amount, ...)
  │
  ├─ 4. Batch-fetch ALL inventory for every product in the order (single query)
  │     → SELECT product_id, size, stock FROM inventory
  │       WHERE product_id IN (product1, product2, ...) AND stock > 0
  │     → Builds: invByProduct = { productId → [{size, stock}, ...] }
  │
  ├─ 5. For EACH item in the order:
  │     ├─ a. Get cartSize from item['size']
  │     ├─ b. Resolve size from invByProduct:
  │     │     1) Exact match   (cartSize == invRow.size)
  │     │     2) Numeric match (strip "EU"/"US" prefix → compare)
  │     │     3) Fallback      (first available invRow.size)
  │     ├─ c. INSERT INTO order_items (order_id, product_id, size, quantity, unit_price)
  │     └─ d. If P0001 "insufficient stock" → throw StockUnavailableException
  │
  └─ 6. Return mapped order with all order_items
```

---

## Full Function Code

```dart
Future<Map<String, dynamic>> createOrder(
  Map<String, dynamic> orderData,
) async {
  final userId = _requiredUserId();
  final items = orderData['items'] as List<Map<String, dynamic>>? ?? [];
  if (items.isEmpty) throw Exception('No items to order.');

  // Look up store_id from the first product
  Map<String, dynamic> productMap;
  try {
    final firstProduct = await _client
        .from('products')
        .select('id, store_id, price')
        .eq('id', items.first['product_id'].toString())
        .single();
    productMap = Map<String, dynamic>.from(firstProduct);
  } catch (e) {
    throw Exception('Product lookup failed for ${items.first['product_id']}: $e');
  }

  final method = _normalizePaymentMethod(orderData['payment_method']);

  // Create the order
  Map<String, dynamic> orderMap;
  try {
    final order = await _client
        .from('orders')
        .insert({
          'customer_id': userId,
          'store_id': productMap['store_id'],
          'status': 'pending',
          'fulfillment': 'pickup',
          'total_amount': orderData['total_amount'],
          'payment_method': method,
          'payment_status': method == 'cash' ? 'unpaid' : 'paid',
          'notes': orderData['delivery_address'],
        })
        .select()
        .single();
    orderMap = Map<String, dynamic>.from(order);
  } catch (e) {
    throw Exception('Order insert failed: $e');
  }

  // Batch-fetch all inventory rows for every product in this order
  // in a single query (eliminates N+1 per-item queries).
  final productIds = items
      .map((item) => item['product_id'].toString())
      .toSet()
      .toList();
  final Map<String, List<Map<String, dynamic>>> invByProduct = {};
  if (productIds.isNotEmpty) {
    final allInvRows = await _client
        .from('inventory')
        .select('product_id, size, stock')
        .inFilter('product_id', productIds)
        .gt('stock', 0);
    for (final row in (allInvRows as List)) {
      final pid = row['product_id'].toString();
      invByProduct.putIfAbsent(pid, () => []).add({
        'size': row['size']?.toString() ?? '',
        'stock': (row['stock'] as num?)?.toInt() ?? 0,
      });
    }
  }

  // Create an order_item for each selected product
  for (final item in items) {
    // Resolve size: always look up from inventory to match the DB trigger's
    // stock check format (inventory uses raw sizes like '40', not 'EU40').
    final cartSize = (item['size']?.toString().isNotEmpty ?? false)
        ? item['size'].toString()
        : '';
    final productId = item['product_id'].toString();

    // Resolve size from the pre-fetched inventory rows
    String size = cartSize;
    final invRows = invByProduct[productId] ?? [];

    if (invRows.isNotEmpty) {
      // 1) Try exact match first
      String? matchedSize;
      for (final row in invRows) {
        if (row['size'] == cartSize) {
          matchedSize = row['size'];
          break;
        }
      }
      // 2) Try numeric match (strip 'EU'/'US' prefix from cart size)
      if (matchedSize == null && cartSize.isNotEmpty) {
        final numeric = cartSize.replaceAll(RegExp(r'^[A-Za-z]+'), '');
        for (final row in invRows) {
          if (row['size'] == numeric) {
            matchedSize = row['size'];
            break;
          }
        }
      }
      // 3) Fallback: first available size
      size = matchedSize ?? invRows.first['size'] ?? cartSize;
    }

    try {
      await _client.from('order_items').insert({
        'order_id': orderMap['id'],
        'product_id': productId,
        'size': size,
        'quantity': item['quantity'] ?? 1,
        'unit_price': item['unit_price'] ?? 0,
      });
    } catch (e) {
      // Translate the DB-level stock check (P0001) into a friendly exception
      if (e is PostgrestException &&
          e.code == 'P0001' &&
          e.message.toLowerCase().contains('insufficient stock')) {
        throw StockUnavailableException(
          productName: item['product_name']?.toString() ?? 'Product',
          size: size,
          requestedQty: (item['quantity'] as num?)?.toInt() ?? 1,
        );
      }
      // Re-throw as-is for other errors — provider will show generic message
      rethrow;
    }
  }

  return _mapOrder({
    ...orderMap,
    'order_items': items
        .map((item) => {
              'product_id': item['product_id'],
              'size': item['size'] ?? '',
              'quantity': item['quantity'] ?? 1,
              'unit_price': item['unit_price'] ?? 0,
            })
        .toList(),
  });
}
```

---

## What each `order_items` row looks like on insert

| Column | Source | Example |
|--------|--------|---------|
| `order_id` | `orderMap['id']` (just-created order UUID) | `"a1b2c3d4-..."` |
| `product_id` | `item['product_id']` (from cart) | `"5d2dadf8-..."` |
| `size` | Resolved from inventory (see resolution logic above) | `"40"` (not `"EU40"`) |
| `quantity` | `item['quantity']` (from cart, defaults to 1) | `1` |
| `unit_price` | `item['unit_price']` (from cart) | `1299.00` |

---

## Size Resolution Logic (step by step)

The DB trigger `decrement_inventory_on_order` checks stock by `(product_id, size)` against the `inventory` table. The `inventory` table stores sizes as bare numbers (`"38"`, `"40"`), while the app/cart may store prefixed sizes (`"EU40"`).

To ensure the `order_items.size` always matches `inventory.size`:

1. **Exact match** — if cart size `"40"` matches an inventory row `"40"` → use it
2. **Numeric match** — strip leading letters (`"EU40"` → `"40"`) and check inventory
3. **Fallback** — use the first available inventory size for this product

This ensures the DB trigger can always find the matching row and decrement stock correctly.
