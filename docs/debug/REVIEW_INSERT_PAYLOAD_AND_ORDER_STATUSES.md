# Debug: Review Insert Payload & Order Status Values

## 1. Client-Side Insert Payload

Both `submitReview()` and `submitOrderItemReview()` route through a single payload builder:

```dart
// review_service.dart — _buildReviewPayload()
static Map<String, dynamic> _buildReviewPayload({
  required String orderId,
  required String orderItemId,
  required String productId,
  required String customerId,
  required String storeId,
  required int rating,
  String? comment,
}) {
  // Validates all UUIDs are non-empty before building
  final fields = <String, String>{
    'orderId': orderId,
    'orderItemId': orderItemId,
    'productId': productId,
    'customerId': customerId,
    'storeId': storeId,
  };
  for (final entry in fields.entries) {
    if (entry.value.isEmpty) {
      throw Exception(
        'submitReview: ${entry.key} is empty — cannot submit review. '
        'orderId=$orderId, orderItemId=$orderItemId, productId=$productId, '
        'storeId=$storeId',
      );
    }
  }
  if (rating < 1 || rating > 5) {
    throw Exception('submitReview: rating must be 1–5, got $rating');
  }

  return {
    'order_id': orderId,        // UUID (orders.id)
    'order_item_id': orderItemId, // UUID (order_items.id)
    'product_id': productId,    // TEXT (products.id — not UUID)
    'customer_id': customerId,  // UUID (auth user id)
    'store_id': storeId,        // UUID (stores.id)
    'rating': rating,           // INT 1–5
    'comment': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
  };
}
```

The actual Supabase call:

```dart
final review = await _client
    .from('reviews')
    .insert(payload)    // ← the Map above
    .select()
    .single();
```

### How each field is sourced

| Field | Source (order-item path) | Source (per-product legacy path) |
|-------|--------------------------|----------------------------------|
| `order_id` | `widget.orderId!` (from OrderReviewScreen → `_order['id'].toString()`) | Fetched from DB: orders WHERE customer_id = current user AND status IN reviewable |
| `order_item_id` | `widget.orderItemId!` (from `item['id'].toString()`) | Fetched from DB: order_items WHERE product_id = given AND order_id IN user's orders |
| `product_id` | `widget.productId` (from `item['product_id'].toString()`) | Passed as parameter (from WriteReviewScreen constructor) |
| `customer_id` | `_client.auth.currentUser!.id` | Same |
| `store_id` | `widget.storeId!` (from `_order['store_id']?.toString()`) | Fetched from DB: `order['store_id']?.toString()` from matched order |
| `rating` | `int` from star selector | Same |
| `comment` | `String?` from text field | Same |

---

## 2. Order Status Values

Based on codebase analysis (constants + usage), `orders.status` uses these values:

| Status | Constant | Reviewable? | Notes |
|--------|----------|-------------|-------|
| `pending` | `AppConstants.statusPending` | No | Initial state after order placement |
| `placed` | `AppConstants.statusPlaced` | No | Order confirmed by seller |
| `preparing` | `AppConstants.statusPreparing` | No | Seller is preparing the order |
| `ready` | `AppConstants.statusReady` | **Yes** | Order ready for pickup/delivery |
| `delivered` | *(no constant, used as literal)* | **Yes** | Seller marked as delivered |
| `received` | `AppConstants.statusReceived` | **Yes** | Customer confirmed receipt (Part D) |
| `cancelled` | *(no constant, used as literal)* | No | Order cancelled |

### Review-eligible filter (used in review_service.dart)

```dart
.inFilter('status', ['ready', 'received', 'delivered'])
```

### Order status flow

```
pending → placed → preparing → ready → delivered → received
                                                  ↑
                                          (customer confirms receipt)
```

### SQL to verify actual DB values

Run in Supabase SQL editor:

```sql
SELECT DISTINCT status FROM orders ORDER BY status;
```

This will confirm whether `delivered` is actually stored in the DB (the codebase uses it as a literal string, not a constant).
