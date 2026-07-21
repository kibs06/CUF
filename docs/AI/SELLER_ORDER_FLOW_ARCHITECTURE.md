# Seller Order Flow — Complete Architecture & Bug Analysis

> **Purpose:** Provide a comprehensive reference for an AI agent to plan and generate fixes for the seller order acceptance-through-delivery pipeline.
> **Last updated:** July 18, 2026
> **Audience:** AI agents tasked with debugging and fixing the order flow.

---

## Table of Contents

1. [Order Lifecycle Overview](#1-order-lifecycle-overview)
2. [Status State Machine & Value Mapping](#2-status-state-machine--value-mapping)
3. [File Map — All Order-Related Files](#3-file-map--all-order-related-files)
4. [Data Flow Diagrams](#4-data-flow-diagrams)
5. [Database Schema & Triggers](#5-database-schema--triggers)
6. [RLS Policies for Orders](#6-rls-policies-for-orders)
7. [Identified Bugs & Errors](#7-identified-bugs--errors)
8. [Constants Reference](#8-constants-reference)
9. [Key Service Methods](#9-key-service-methods)

---

## 1. Order Lifecycle Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ORDER LIFECYCLE                                       │
│                                                                             │
│  CUSTOMER SIDE                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│  │  Browse   │───▶│   Cart   │───▶│ Checkout │───▶│  Order   │             │
│  │  & Select │    │  Review  │    │  Confirm │    │ Placed!  │             │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘             │
│       │               │               │               │                    │
│  ProductDetail    CartScreen     CheckoutScreen   Supabase                │
│  screen           (validation)   (address, pay)   createOrder              │
│                                                                             │
│  SELLER SIDE (status transitions driven by seller)                         │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│  │  Pending  │───▶│Confirmed │───▶│  Ready   │───▶│ Delivered │             │
│  │  (new)    │    │(prepare) │    │(pickup/  │    │(received) │             │
│  │           │    │          │    │ delivery)│    │           │             │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘             │
│                                                                             │
│  DB values:  pending → preparing → ready → received                        │
│  UI labels:  Pending → Confirmed → Ready   → Delivered                     │
│                                                                             │
│  ⚠️ CRITICAL: UI labels ≠ DB values (mapping layer in SupabaseService)     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Status State Machine & Value Mapping

### The Two-Layer Status Problem

This is the **root cause of most bugs** in the order flow. There are TWO sets of status values:

| DB Value (`orders.status`) | Seller UI Label | Customer UI Label |
|---------------------------|-----------------|-------------------|
| `pending` | "Pending" | "Processing" tab |
| `placed` | (legacy, not used) | "Processing" tab |
| `preparing` | "Confirmed" | Timeline step 2 |
| `ready` | "Ready" | Timeline step 3 |
| `received` | "Delivered" | Timeline step 4 |
| `cancelled` | "Cancelled" | "Returns" tab |

### The Mapping Layer

`SupabaseService.updateOrderStatus()` translates UI labels → DB values:

```dart
// In lib/services/supabase_service.dart
final statusMap = <String, String>{
  'confirmed': 'preparing',   // UI → DB
  'delivered': 'received',    // UI → DB
};
final dbStatus = statusMap[newStatus.toLowerCase()] ?? newStatus.toLowerCase();
```

### Status Flow Diagram

```
                    ┌─────────────────┐
                    │   createOrder() │
                    │ status=pending  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     PENDING     │◄──────────── Seller can cancel
                    │  (new order)    │             from here to "cancelled"
                    └────────┬────────┘
                             │
                    Seller taps "Confirm"
                    UI sends: 'confirmed'
                    DB stores: 'preparing'
                    ┌────────▼────────┐
                    │   PREPARING     │
                    │  (confirmed)    │
                    └────────┬────────┘
                             │
                    Seller taps "Ready"
                    ┌────────▼────────┐
                    │     READY       │
                    │ (ready for      │
                    │  pickup/delivery)│
                    └────────┬────────┘
                             │
                    Seller taps "Delivered"
                    UI sends: 'delivered'
                    DB stores: 'received'
                    ┌────────▼────────┐
                    │    RECEIVED     │
                    │  (completed)    │
                    └─────────────────┘
```

---

## 3. File Map — All Order-Related Files

### Seller Side (Order Management)

| File | Purpose |
|------|---------|
| `lib/screens/seller/manage_orders_screen.dart` | **Main seller order list** with tab filters (All/Pending/Confirmed/Ready/Delivered/Cancelled). Contains `_updateStatus()` which drives the transition dialog. |
| `lib/screens/seller/order_detail_screen.dart` | Single order detail view for seller (items, timeline, customer info, status action button). |
| `lib/screens/seller/seller_orders_screen.dart` | **Alternative** order list screen (simpler, no tabs). Uses DB status constants directly. |
| `lib/screens/seller/seller_dashboard_screen.dart` | Dashboard with pending order count, recent orders, stale order alerts. |
| `lib/widgets/seller/seller_order_card.dart` | Card widget showing order info + primary action button. |
| `lib/widgets/seller/seller_status_chip.dart` | Colored chip displaying the current status label. |

### Customer Side (Order Viewing)

| File | Purpose |
|------|---------|
| `lib/screens/customer/checkout_screen.dart` | Checkout form — address, payment, validation, submit. |
| `lib/screens/customer/my_orders_screen.dart` | Customer order list with tab-based filtering. |
| `lib/screens/customer/tracking_screen.dart` | Single order timeline view with status history. |

### Provider Layer

| File | Purpose |
|------|---------|
| `lib/providers/order_provider.dart` | Order state — `placeOrder()`, `loadOrders()`, `loadMyOrders()`, `updateOrderStatus()`. |

### Service Layer

| File | Purpose |
|------|---------|
| `lib/services/supabase_service.dart` | Core DB — `createOrder()`, `updateOrderStatus()` with status mapping. |
| `lib/services/order_service.dart` | Order queries — `fetchStoreOrders()`, `fetchMyOrders()`, `getRecentOrders()`. |
| `lib/services/seller_notification_service.dart` | Creates seller notifications on order events. |

### Database Migrations

| File | Purpose |
|------|---------|
| `supabase/migrations/20260702_notifications.sql` | Notifications table + triggers (`trg_notify_on_order_status_change`). |
| `supabase/migrations/20260704_add_orders_delete_policy.sql` | DELETE policy on orders (pending only). |
| `supabase/migrations/20260720_order_status_history.sql` | `order_status_history` table + trigger for timeline. |
| `supabase/migrations/20260721_fix_order_status_history_fk.sql` | FK fix for order_status_history. |
| `supabase/migrations/20260722_fix_orders_status_check_constraint.sql` | Fixes CHECK constraint to include all statuses. |

### Shared

| File | Purpose |
|------|---------|
| `lib/constants/app_constants.dart` | Status constants, colors, typography. |
| `lib/widgets/sole_status_chip.dart` | Customer-facing status chip. |
| `lib/widgets/sole_timeline.dart` | Vertical timeline component. |

---

## 4. Data Flow Diagrams

### Flow 1: Customer Places Order

```
┌─────────────────────────────────────────────────────────────────────┐
│  CHECKOUT SCREEN                                                    │
│  ───────────────                                                    │
│  User taps "Complete Order"                                         │
│       │                                                             │
│       ▼                                                             │
│  OrderProvider.placeOrder()                                         │
│    └─ SupabaseService.createOrder()                                 │
│        ├─ Looks up store_id from FIRST product only (BUG #8)        │
│        ├─ STEP 1: INSERT into orders table                          │
│        │   - status='pending', payment_method, total_amount         │
│        ├─ Batch-fetch inventory for all products in order           │
│        ├─ STEP 2: INSERT each order_item row                        │
│        │   - Resolves size via resolveInventoryStock()              │
│        │   - If ANY insert fails → ROLLBACK:                        │
│        │     delete orphaned orders row + inserted items            │
│        │     throw StockUnavailableException                        │
│        └─ Fire-and-forget: SellerNotificationService.createNewOrder │
│                                                                     │
│  DB Triggers that fire:                                             │
│    ├─ trg_notify_on_order_insert → creates customer notification    │
│    └─ (no inventory trigger on INSERT — only on order_items)        │
│                                                                     │
│  Post-order: Cart cleared, confirmation shown                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Flow 2: Seller Confirms Order (status: pending → preparing)

```
┌─────────────────────────────────────────────────────────────────────┐
│  MANAGE ORDERS SCREEN                                               │
│  ────────────────────                                               │
│  Seller taps "Confirm Order" button on SellerOrderCard              │
│       │                                                             │
│       ▼                                                             │
│  _updateStatus(orderId, 'pending')                                  │
│    ├─ Determines nextStatus: 'pending' → 'confirmed'                │
│    ├─ Shows AlertDialog with transition chips                       │
│    ├─ Seller taps "Confirm"                                         │
│    │                                                                │
│    ▼                                                                │
│  OrderProvider.updateOrderStatus(orderId, 'confirmed')              │
│    │                                                                │
│    ▼                                                                │
│  SupabaseService.updateOrderStatus(orderId, 'confirmed')            │
│    ├─ Maps: 'confirmed' → 'preparing' (via statusMap)               │
│    ├─ UPDATE orders SET status = 'preparing' WHERE id = orderId     │
│    │                                                                │
│    │  DB Triggers that fire:                                        │
│    │  ├─ trg_record_order_status_change → order_status_history row  │
│    │  └─ trg_notify_on_order_status_change → customer notification  │
│    │                                                                │
│    ▼                                                                │
│  Returns updated order map → UI refreshes                           │
└─────────────────────────────────────────────────────────────────────┘
```

### Flow 3: Seller Marks Ready (status: preparing → ready)

```
Same pattern as Flow 2:
  _updateStatus() → 'confirmed' (nextStatus from 'confirmed' = 'ready')
  SupabaseService maps: 'ready' → 'ready' (no mapping needed)
  DB: UPDATE orders SET status = 'ready'
  Triggers: status_history + customer notification
```

### Flow 4: Seller Marks Delivered (status: ready → received)

```
Same pattern as Flow 2:
  _updateStatus() → 'delivered' (nextStatus from 'ready' = 'delivered')
  SupabaseService maps: 'delivered' → 'received'
  DB: UPDATE orders SET status = 'received'
  Triggers: status_history + customer notification
  Customer sees: "Order delivered" notification + timeline step 4
```

---

## 5. Database Schema & Triggers

### Orders Table (relevant columns)

```sql
CREATE TABLE public.orders (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id        UUID REFERENCES public.stores(id),
    status          TEXT NOT NULL DEFAULT 'placed'
                        CHECK (status IN ('pending', 'placed', 'preparing', 'ready', 'received', 'cancelled')),
    total_amount    NUMERIC NOT NULL CHECK (total_amount >= 0),
    payment_method  TEXT NOT NULL DEFAULT 'cash',
    payment_status  TEXT NOT NULL DEFAULT 'unpaid'
                        CHECK (payment_status IN ('paid', 'unpaid')),
    fulfillment     TEXT NOT NULL DEFAULT 'pickup'
                        CHECK (fulfillment IN ('pickup', 'delivery')),
    notes           TEXT,                         -- delivery address text
    shipping_address JSONB,                       -- full address snapshot
    -- LEGACY columns (do not use for new orders):
    size            TEXT,
    color           TEXT,
    quantity        INTEGER,
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```

### Order Items Table

```sql
CREATE TABLE public.order_items (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    order_id    BIGINT REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id  TEXT REFERENCES public.products(id) ON DELETE SET NULL,
    size        TEXT,
    quantity    INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price  NUMERIC NOT NULL DEFAULT 0 CHECK (unit_price >= 0)
);
```

### Order Status History Table

```sql
CREATE TABLE public.order_status_history (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    order_id    BIGINT NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    status      TEXT NOT NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Key DB Triggers

| Trigger | Table | Event | Purpose |
|---------|-------|-------|---------|
| `trg_record_order_status_change` | `orders` | AFTER UPDATE OF status | Inserts row into `order_status_history` |
| `trg_notify_on_order_status_change` | `orders` | AFTER UPDATE OF status | Creates customer notification in `notifications` table |
| `trg_notify_on_order_insert` | `orders` | AFTER INSERT | Creates "payment pending" notification for customer |
| `decrement_inventory_on_order` | `order_items` | INSERT | Decrements `inventory.stock` (SECURITY DEFINER) |

### Notification Trigger Mapping

| New Status | Notification Category | Title |
|------------|----------------------|-------|
| `pending` | `unpaid` | "Payment pending" |
| `placed` | `unpaid` | "Order placed" |
| `preparing` | `processing` | "Order confirmed" |
| `ready` | `shipped` | "Order ready" |
| `received` | `review` | "Order delivered" |
| `cancelled` | (no notification) | — |

---

## 6. RLS Policies for Orders

### Orders Table

| Operation | Policy |
|-----------|--------|
| SELECT (customer) | `auth.uid() = customer_id` |
| SELECT (seller) | `EXISTS (SELECT 1 FROM stores WHERE id = store_id AND owner_id = auth.uid())` |
| SELECT (admin) | `EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')` |
| INSERT | `auth.uid() = customer_id` |
| UPDATE | `EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (role = 'seller' OR role = 'admin'))` |
| DELETE | `auth.uid() = customer_id AND status = 'pending'` |

### Order Items Table

| Operation | Policy |
|-----------|--------|
| SELECT | Follows order access (customer owns order, or seller/admin role) |
| INSERT | `EXISTS (SELECT 1 FROM orders WHERE id = order_id AND customer_id = auth.uid())` |

---

## 7. Identified Bugs & Errors

### 🔴 BUG #1: `ManageOrdersScreen` Tab Filtering Uses UI Labels Instead of DB Values

**File:** `lib/screens/seller/manage_orders_screen.dart`

**Problem:** The tab filter compares against UI labels (`'confirmed'`, `'delivered'`) but the DB stores `'preparing'` and `'received'`. Orders will never appear in the "Confirmed" or "Delivered" tabs.

```dart
// Current code (BROKEN):
filteredOrders = allOrders
    .where((o) => (o['status'] ?? '').toLowerCase() == statusFilter)
    .toList();
// statusFilter = 'confirmed' but DB has 'preparing'
// statusFilter = 'delivered' but DB has 'received'
```

**Impact:** Sellers cannot see orders in the "Confirmed" or "Delivered" tabs. Orders only appear in "Pending" and "Ready" tabs (which happen to match DB values).

**Fix needed:** Map UI labels to DB values before filtering, OR use DB values for the tab labels.

---

### 🔴 BUG #2: `OrderDetailScreen` Timeline Checks for `'delivered'` Instead of `'received'`

**File:** `lib/screens/seller/order_detail_screen.dart`

**Problem:** The timeline completion check uses `'delivered'` but the DB stores `'received'`.

```dart
// Current code (BROKEN):
_timelineStep('Delivered', status == 'delivered')
// But status in DB is 'received', not 'delivered'
```

**Impact:** The "Delivered" timeline step never shows as complete on the seller order detail screen.

**Fix needed:** Change to `status == 'received'`.

---

### 🔴 BUG #3: `SellerOrdersScreen` Sends Raw DB Values Without Mapping

**File:** `lib/screens/seller/seller_orders_screen.dart`

**Problem:** This screen calls `updateOrderStatus()` with raw DB values (`statusPlaced`, `statusPreparing`, `statusReady`, `statusReceived`) instead of UI labels. The mapping layer in `SupabaseService` expects `'confirmed'` and `'delivered'` as inputs.

```dart
// Current code (BROKEN):
String nextStatus = AppConstants.statusPlaced;  // = 'placed'
if (currentStatus == AppConstants.statusPlaced) {
  nextStatus = AppConstants.statusPreparing;    // = 'preparing'
} else if (currentStatus == AppConstants.statusPreparing) {
  nextStatus = AppConstants.statusReady;        // = 'ready'
} else if (currentStatus == AppConstants.statusReady) {
  nextStatus = AppConstants.statusReceived;     // = 'received'
}
// These raw DB values bypass the mapping layer, potentially causing
// CHECK constraint violations if the values don't match exactly.
```

**Impact:** Status updates from this screen may fail or produce inconsistent state.

**Fix needed:** Either use UI labels (`'confirmed'`, `'delivered'`) or skip the mapping layer for this screen.

---

### 🔴 BUG #4: `OrderDetailScreen` Action Button Label Doesn't Match DB State

**File:** `lib/screens/seller/order_detail_screen.dart`

**Problem:** The `_nextStatus` getter returns UI labels but the DB stores different values. The action button logic is:

```dart
String? get _nextStatus {
  switch (_currentStatus.toLowerCase()) {
    case 'pending': return 'confirmed';    // → DB: preparing ✓
    case 'confirmed': return 'ready';      // ← But DB has 'preparing', not 'confirmed'!
    case 'ready': return 'delivered';      // → DB: received ✓
    case 'cancelled': return 'pending';    // ✓
    default: return null;
  }
}
```

When the order is in `preparing` state (DB value), `_currentStatus` is `'preparing'`, which doesn't match any case → returns `null` → no action button shown.

**Impact:** Once an order is confirmed (status=`preparing`), the seller sees no action button to advance it to "Ready".

**Fix needed:** Add `case 'preparing': return 'ready';` to the switch.

---

### 🟡 BUG #5: Multi-Store Orders Assigned to Wrong Store

**File:** `lib/services/supabase_service.dart` — `createOrder()`

**Problem:** `createOrder()` looks up `store_id` from only the **first product** in the order. If a customer orders from multiple stores, all items get assigned to one store.

```dart
// Current code (BUG):
final firstProduct = await _client
    .from('products')
    .select('id, store_id, price')
    .eq('id', items.first['product_id'].toString())
    .single();
// Only looks up store_id from first product!
```

**Impact:** Seller can only see orders from their store if their product happens to be first. Orders from other stores are invisible to the correct seller.

**Fix needed:** Group items by `store_id` and create separate orders per store.

---

### 🟡 BUG #6: `_mapOrder()` Flattens First Item Into Order-Level Fields

**File:** `lib/services/supabase_service.dart` — `_mapOrder()`

**Problem:** For multi-item orders, `_mapOrder()` takes the first item's `product_id`, `size`, `quantity` and puts them at the order level. Other screens read these order-level fields thinking they represent the whole order.

```dart
Map<String, dynamic> _mapOrder(Map<String, dynamic> row) {
  final items = row['order_items'] is List ? row['order_items'] as List : [];
  final firstItem = items.isNotEmpty ? Map<String, dynamic>.from(items.first as Map) : {};
  return {
    ...row,
    'product_id': firstItem['product_id']?.toString(),  // Only first item!
    'size': firstItem['size'] ?? '',                      // Only first item!
    'quantity': (firstItem['quantity'] as num?)?.toInt() ?? 1,  // Only first item!
    // ...
  };
}
```

**Impact:** Multi-item orders show incorrect product/size/quantity in seller cards and detail screens.

**Fix needed:** Remove the flattening or aggregate across all items.

---

### 🟡 BUG #7: `SellerOrderCard` Uses `'confirmed'` for Status Chip

**File:** `lib/widgets/seller/seller_order_card.dart`

**Problem:** The card's status chip receives the raw status from the DB (`'preparing'`), but the `SellerStatusChip` widget may display it as-is. The primary action button logic uses UI labels:

```dart
case 'confirmed':  // ← DB never has 'confirmed', it has 'preparing'
  primaryLabel = 'Mark Ready';
```

Since the DB status is `'preparing'`, this case never matches. The button falls through to the default case.

**Impact:** The "Mark Ready" button may not show for orders in `preparing` state.

**Fix needed:** Add `case 'preparing':` alongside `case 'confirmed':`.

---

### 🟡 BUG #8: `SellerStatusChip` Displays Raw DB Values

**File:** `lib/widgets/seller/seller_status_chip.dart`

**Problem:** The chip displays the raw DB status string. When status is `'preparing'`, it shows "preparing" instead of the seller-friendly "Confirmed".

**Impact:** Seller sees technical DB values instead of user-friendly labels.

**Fix needed:** Map DB values to display labels in the chip widget.

---

### 🟡 BUG #9: No Cancel Functionality in `ManageOrdersScreen`

**File:** `lib/screens/seller/manage_orders_screen.dart`

**Problem:** The `_updateStatus()` method has a case for `'cancelled'` → `'pending'` (restore), but there's no way to transition TO `'cancelled'` from any status. The switch only handles: pending→confirmed, confirmed→ready, ready→delivered, cancelled→pending.

**Impact:** Sellers cannot cancel orders from the manage orders screen.

**Fix needed:** Add a cancel action (separate from the primary action flow).

---

### 🟢 BUG #10: `OrderDetailScreen` SnackBar Always Says "confirmed"

**File:** `lib/screens/seller/order_detail_screen.dart`

**Problem:** The success message is hardcoded:

```dart
SnackBar(
  content: Text('Order #$shortId confirmed'),  // Always says "confirmed"
  // Should say "Marked Ready" or "Marked Delivered" depending on transition
)
```

**Impact:** Misleading feedback to seller.

**Fix needed:** Use a dynamic message based on the actual transition.

---

### 🟢 BUG #11: `ManageOrdersScreen` SnackBar Shows Raw Status Value

**File:** `lib/screens/seller/manage_orders_screen.dart`

**Problem:**

```dart
SnackBar(
  content: Text('Order #$orderId updated to $nextStatus'),
  // Shows "updated to confirmed" or "updated to delivered"
  // But DB stores 'preparing'/'received'
)
```

**Impact:** Minor UX confusion.

**Fix needed:** Show the human-readable label, not the internal status value.

---

### 🟢 BUG #12: Stale Order Data in `ManageOrdersScreen`

**File:** `lib/screens/seller/manage_orders_screen.dart`

**Problem:** After a successful status update, the screen calls `loadOrders()` which fetches ALL orders again. But the `_updateStatus()` method shows a SnackBar with the OLD order ID, and the list may reorder. There's no optimistic UI update — the user sees a loading spinner.

**Impact:** Poor UX — seller has to wait for full reload after each status change.

**Fix needed:** Optimistically update the order in the local list before the server round-trip.

---

## 8. Constants Reference

### Order Status Constants (`lib/constants/app_constants.dart`)

```dart
static const String statusPlaced = 'placed';       // Legacy initial status
static const String statusPreparing = 'preparing';  // Seller confirmed
static const String statusReady = 'ready';           // Ready for pickup
static const String statusReceived = 'received';     // Customer received
static const String statusPending = 'pending';       // New order awaiting action
```

### Status Colors

```dart
static const Color statusPendingColor = Color(0xFFF59E0B);    // amber
static const Color statusConfirmedColor = Color(0xFF3B82F6);  // blue
static const Color statusReadyColor = Color(0xFF8B5A2B);      // primary brand
static const Color statusDeliveredColor = Color(0xFF6B8F47);  // green
static const Color statusCancelledColor = Color(0xFFD64545);  // red
```

### DB CHECK Constraint (after migration 20260722)

```sql
CHECK (status IN ('pending', 'placed', 'preparing', 'ready', 'received', 'cancelled'))
```

---

## 9. Key Service Methods

### `SupabaseService.updateOrderStatus()`

```dart
Future<Map<String, dynamic>> updateOrderStatus(dynamic orderId, String newStatus) async {
  // Maps UI labels → DB values
  final statusMap = <String, String>{
    'confirmed': 'preparing',
    'delivered': 'received',
  };
  final dbStatus = statusMap[newStatus.toLowerCase()] ?? newStatus.toLowerCase();

  // UPDATE orders SET status = $dbStatus WHERE id = $orderId RETURNING *
  // Triggers fire: trg_record_order_status_change, trg_notify_on_order_status_change
}
```

### `OrderProvider.updateOrderStatus()`

```dart
Future<String?> updateOrderStatus(dynamic orderId, String newStatus) async {
  // Calls SupabaseService.updateOrderStatus()
  // Then calls loadOrders() to refresh the list
  // Returns null on success, error message on failure
}
```

### `ManageOrdersScreen._updateStatus()`

```dart
Future<void> _updateStatus(dynamic orderId, String currentStatus, {Map<String, dynamic>? orderData}) async {
  // 1. Determine nextStatus from currentStatus (UI labels)
  // 2. Show confirmation dialog
  // 3. Call OrderProvider.updateOrderStatus(orderId, nextStatus)
  // 4. Show success/error SnackBar
}
```

---

## 10. Recommended Fix Priority

| Priority | Bug | Effort | Impact |
|----------|-----|--------|--------|
| 🔴 P0 | #1 — Tab filtering broken | Low | Seller can't find orders |
| 🔴 P0 | #4 — No action button after confirm | Low | Seller stuck at "preparing" |
| 🔴 P0 | #7 — Status chip doesn't match DB | Low | Wrong button labels |
| 🔴 P1 | #2 — Timeline check for 'delivered' | Low | Timeline never completes |
| 🔴 P1 | #8 — Status chip shows raw DB value | Low | Confusing labels |
| 🟡 P2 | #5 — Multi-store order assignment | Medium | Wrong seller sees order |
| 🟡 P2 | #6 — _mapOrder flattening | Medium | Multi-item order display |
| 🟡 P2 | #9 — No cancel functionality | Medium | Seller can't cancel |
| 🟡 P3 | #3 — SellerOrdersScreen raw values | Low | May cause failures |
| 🟢 P4 | #10 — Hardcoded "confirmed" message | Low | Minor UX |
| 🟢 P4 | #11 — Raw status in SnackBar | Low | Minor UX |
| 🟢 P4 | #12 — Stale data after update | Medium | Performance UX |

---

## 11. Testing Checklist

- [ ] Place order → verify status is 'pending' in DB
- [ ] Seller taps "Confirm" → verify status changes to 'preparing' in DB
- [ ] Seller taps "Mark Ready" → verify status changes to 'ready' in DB
- [ ] Seller taps "Mark Delivered" → verify status changes to 'received' in DB
- [ ] Verify "Confirmed" tab shows orders with status='preparing'
- [ ] Verify "Delivered" tab shows orders with status='received'
- [ ] Verify action button appears for all intermediate states
- [ ] Verify timeline shows correct completion for each status
- [ ] Verify customer receives notification on each status change
- [ ] Verify order_status_history records each transition
- [ ] Verify status chip shows human-readable labels
- [ ] Test multi-item orders display correctly
- [ ] Test order cancellation flow
- [ ] Test offline → online status update sync
