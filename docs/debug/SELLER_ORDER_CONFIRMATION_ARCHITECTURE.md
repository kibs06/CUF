# Seller Order Confirmation — Architecture Overview

> **Purpose:** Quick-reference for AI agents working on the seller order flow. Covers the full
> lifecycle from order creation through delivery, including the critical status-value mapping
> between the seller UI and the database.

---

## Status State Machine

The seller UI displays 5 statuses that map to 5 DB-allowed values:

```
Seller UI Label     DB Value (orders.status)     Triggered By
─────────────────   ──────────────────────────   ──────────────────
Pending             pending                       Customer places order
Confirmed           preparing  ← (mapped)        Seller taps "Confirm Order"
Ready               ready                         Seller taps "Mark Ready"
Delivered           received  ← (mapped)          Seller taps "Mark Delivered"
Cancelled           cancelled                     Seller taps "Cancel"
```

⚠️ **CRITICAL MAPPING:** The seller UI uses `confirmed`/`delivered` but the DB CHECK constraint
only allows `preparing`/`received`. The translation happens in `SupabaseService.updateOrderStatus()`:

```dart
final statusMap = <String, String>{
  'confirmed': 'preparing',
  'delivered': 'received',
};
final dbStatus = statusMap[newStatus.toLowerCase()] ?? newStatus.toLowerCase();
```

**Never write `confirmed` or `delivered` to the DB — always use `preparing`/`received`.**

---

## File Map

| File | Role |
|------|------|
| `lib/screens/seller/manage_orders_screen.dart` | Main orders list with tab filters (All/Pending/Confirmed/Ready/Delivered/Cancelled). Contains `_updateStatus()` which drives the transition dialog and calls the provider. |
| `lib/widgets/seller/seller_order_card.dart` | Card widget showing order info + primary action button. Labels: "Confirm Order" → "Mark Ready" → "Mark Delivered". |
| `lib/widgets/seller/seller_status_chip.dart` | Colored chip displaying the current status label. |
| `lib/screens/seller/order_detail_screen.dart` | Full order detail view (items, timeline, customer info). |
| `lib/providers/order_provider.dart` | State management — `loadOrders()`, `updateOrderStatus()`. |
| `lib/services/supabase_service.dart` | DB layer — `fetchOrders()`, `createOrder()`, `updateOrderStatus()` with status mapping. |
| `lib/services/seller_notification_service.dart` | Creates seller-facing notifications (`new_order`, `stale_order`). |

---

## Data Flow: Seller Confirms an Order

```
Seller taps "Confirm Order" button on SellerOrderCard
        │
        ▼
_manage_orders_screen.dart → _updateStatus(orderId, 'pending')
        │
        ├─ Determines nextStatus: 'pending' → 'confirmed'
        ├─ Shows AlertDialog with transition chips (Pending → Confirmed)
        ├─ Seller taps "Confirm"
        │
        ▼
OrderProvider.updateOrderStatus(orderId, 'confirmed')
        │
        ▼
SupabaseService.updateOrderStatus(orderId, 'confirmed')
        │
        ├─ Maps: 'confirmed' → 'preparing' (DB value)
        ├─ UPDATE orders SET status = 'preparing' WHERE id = orderId
        ├─ DB trigger trg_record_order_status_change → inserts into order_status_history
        ├─ DB trigger trg_notify_on_order_status_change → creates customer notification
        │
        ▼
Returns updated order map → UI refreshes
```

---

## Database Triggers (Automatic — No App-Layer Code Needed)

Two triggers fire on every `orders.status` UPDATE:

1. **`trg_record_order_status_change`** — Inserts a row into `order_status_history`
   (`order_id BIGINT`, `status TEXT`, `changed_at TIMESTAMPTZ`). Powers the customer timeline.

2. **`trg_notify_on_order_status_change`** — Creates a row in `notifications` for the customer:

   | New Status | Notification Category | Title |
   |------------|----------------------|-------|
   | `preparing` | `processing` | "Order confirmed" |
   | `ready` | `shipped` | "Out for Delivery" / "Ready for Pickup" |
   | `received` | `review` | "Order delivered" |
   | `cancelled` | `cancelled` | "Order cancelled" |

---

## `_updateStatus()` Flow (manage_orders_screen.dart)

```
1. Guard: skip if orderId null or already updating
2. Switch on currentStatus → determine nextStatus
3. Build context (customer name, item count, total)
4. Show AlertDialog with transition chips + "Confirm" button
5. If confirmed → OrderProvider.updateOrderStatus(orderId, nextStatus)
6. Show SnackBar success/failure
```

**Transition table:**
| Current Status | Next Status |
|---------------|-------------|
| `pending` | `confirmed` → DB: `preparing` |
| `confirmed` | `ready` |
| `ready` | `delivered` → DB: `received` |
| `cancelled` | `pending` (restore) |

---

## Known Issues

1. **Seller status labels differ from DB values** — Handled by `statusMap` in `updateOrderStatus()`.
   If you add new statuses, update both the map AND the DB CHECK constraint.

2. **`_mapOrder()` flattens first item** — Top-level `size`, `quantity`, `product_id` come from the
   first `order_item` only. Multi-item orders lose this data at the top level.

3. **`fetchOrders()` batch-fetches profiles** — Avoids PostgREST join issues by fetching profiles
   separately and merging into the order map as `order['profiles']`.

4. **Notifications are DB-triggered, not app-triggered** — The `updateOrderStatus()` method does NOT
   create notifications in Dart. The DB triggers handle it. If you need different notification copy,
   update the trigger function in the migration, not the Dart code.
