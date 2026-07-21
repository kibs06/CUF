# Seller Order Flow Architecture

## Overview

This document describes the order flow from seller confirmation to delivery, including the architecture, status transitions, and known bugs.

**Architecture Pattern**: Provider-based MVVM

**Layers**:
- Screens (Flutter StatefulWidget) - View layer
- Providers (ChangeNotifier) - ViewModel layer
- Services (Dart classes) - Data access layer
- Supabase (PostgreSQL) - Database layer with RLS policies

**Key Insight**: The system uses a dual status vocabulary. The seller UI displays friendlier labels (e.g., "confirmed", "delivered") that differ from the database values (e.g., "preparing", "received"). This mapping is performed only in `SupabaseService.updateOrderStatus()`.

---

## Order Status States

### DB-Level Statuses (Stored in `orders.status`)

Constrained by: `CHECK (status IN ('pending', 'placed', 'preparing', 'ready', 'received', 'cancelled'))`

- **pending** - Order just created, awaiting seller action
- **placed** - Order confirmed by system (legacy status)
- **preparing** - Seller has confirmed the order
- **ready** - Order is ready for pickup/delivery
- **received** - Customer has received the order
- **cancelled** - Order cancelled by customer or seller

### UI-Level Statuses (Seller-Facing Labels)

- **pending** - Awaiting seller confirmation
- **confirmed** - Seller has confirmed (maps to DB: `preparing`)
- **ready** - Order ready for pickup/delivery
- **delivered** - Customer received (maps to DB: `received`)
- **cancelled** - Order cancelled

### Status Mapping Table

| UI Label | DB Value | Description |
|----------|----------|-------------|
| `pending` | `pending` | No mapping needed |
| `confirmed` | `preparing` | Seller confirmed the order |
| `ready` | `ready` | No mapping needed |
| `delivered` | `received` | Customer received the order |
| `cancelled` | `cancelled` | No mapping needed |

### Customer-Facing Filter Mapping

| Customer Tab | Matches Status(es) |
|--------------|-------------------|
| `unpaid` | payment_status == 'unpaid' && status != 'cancelled' |
| `processing` | `pending`, `placed`, `preparing` |
| `shipped` | `ready` |
| `review` | `received` |
| `returns` | `cancelled` |

---

## Seller Flow: Confirmation to Delivery

### Step 1: Pending to Confirmed

**Trigger**: Seller taps "Confirm Order" button

**Flow**:
1. `ManageOrdersScreen._updateStatus()` (manage_orders_screen.dart:86) determines next status is `confirmed`
2. Confirmation dialog shown with order context
3. `OrderProvider.updateOrderStatus(orderId, 'confirmed')` called (order_provider.dart:101)
4. `SupabaseService.updateOrderStatus()` called (supabase_service.dart:469)
5. Status mapped: `confirmed` -> `preparing`
6. DB update: `orders.status = 'preparing'`
7. DB triggers fire:
   - `trg_record_order_status_history` - Records status change in `order_status_history`
   - `trg_notify_on_order_status_change` - Creates customer notification

### Step 2: Confirmed to Ready

**Trigger**: Seller taps "Mark Ready" button

**Flow**:
1. `ManageOrdersScreen._updateStatus()` determines next status is `ready`
2. Confirmation dialog shown
3. `OrderProvider.updateOrderStatus(orderId, 'ready')` called
4. `SupabaseService.updateOrderStatus()` called
5. Status passed through: `ready` -> `ready`
6. DB update: `orders.status = 'ready'`
7. DB triggers fire (same as Step 1)

### Step 3: Ready to Delivered

**Trigger**: Seller taps "Mark Delivered" button

**Flow**:
1. `ManageOrdersScreen._updateStatus()` determines next status is `delivered`
2. Confirmation dialog shown
3. `OrderProvider.updateOrderStatus(orderId, 'delivered')` called
4. `SupabaseService.updateOrderStatus()` called
5. Status mapped: `delivered` -> `received`
6. DB update: `orders.status = 'received'`
7. DB triggers fire (same as Step 1)
8. Additional: `ProductService.syncProductActiveStatus()` called to update product active status

---

## Status Mapping Layer

The status mapping is implemented in `SupabaseService.updateOrderStatus()`:

```dart
final statusMap = <String, String>{
  'confirmed': 'preparing',
  'delivered': 'received',
};
final dbStatus = statusMap[newStatus.toLowerCase()] ?? newStatus.toLowerCase();
```

**Key Observations**:
- Mapping is only performed in this single location
- No centralized enum or state machine exists
- Some screens bypass this mapping by using DB-level labels directly
- This is the root cause of multiple bugs documented below

---

## Bugs

### Bug 1: Admin Portal Sends Invalid Status Values (HIGH)

**File**: `admin-portal/src/hooks/useOrders.js:40-43`

**Issue**: The admin portal's `useUpdateOrderStatus` sends the status value directly from its dropdown without any mapping:

```javascript
.update({ status: status.toLowerCase() })
```

The admin portal's status list (`constants.js:24-34`) includes `confirmed`, `shipped`, and `delivered` -- all of which are NOT valid DB values.

**Impact**: If an admin selects `confirmed` or `delivered`, the DB will reject it with a CHECK constraint violation (error 23514).

**Valid DB Statuses**: `pending`, `placed`, `preparing`, `ready`, `received`, `cancelled`

**Invalid Statuses Sent by Admin Portal**: `confirmed`, `shipped`, `delivered`

---

### Bug 2: Dual Status Vocabulary Confusion (HIGH)

**Files**: `supabase_service.dart:469-480`, `seller_status_chip.dart:14-38`, `sole_status_chip.dart`

**Issue**: The seller UI uses labels (`confirmed`, `delivered`) that differ from DB values (`preparing`, `received`). This mapping is only done in `SupabaseService.updateOrderStatus()`.

**Impact**:
- `SellerStatusChip` displays `confirmed` and `delivered` (UI labels)
- `SoleStatusChip` displays `placed`, `preparing`, `received` (DB labels)
- `ManageOrdersScreen` tabs use UI labels: `All`, `Pending`, `Confirmed`, `Ready`, `Delivered`, `Cancelled`
- Dashboard status summary uses DB labels: `placed`, `preparing`, `ready`, `received`
- Visual inconsistency across the application
- Code confusion and maintenance burden

---

### Bug 3: Custom Orders Screen Wrong Function Call (MEDIUM)

**File**: `custom_orders_screen.dart:95-103`

**Issue**: The Approve button on custom order requests shows "not yet implemented" but the comment indicates someone previously attempted to call `updateOrderStatus` with a customization request ID (which is a different table).

**Documented TODO/BUG**:
```dart
// TODO: This incorrectly calls order updateStatus on a customization ID.
// Should use a dedicated customization status update method.
debugPrint('[CustomOrdersScreen] BUG: updateOrderStatus called with customization id=${c['id']}, not an order id');
```

**Impact**: Custom order approval/rejection flow is broken.

---

### Bug 4: Non-Atomic Order Creation (MEDIUM)

**File**: `supabase_service.dart:307-440`

**Issue**: Order creation is NOT transactional:
1. First inserts the `orders` row (committed immediately)
2. Then inserts `order_items` rows one-by-one in a loop
3. If any `order_items` insert fails, it manually deletes the orphaned `orders` row

**Impact**: Race condition where orphaned order (with no items) could be visible to seller between step 1 and cleanup. The cleanup also relies on an RLS DELETE policy (migration `20260704`) which may not be applied in all environments.

---

### Bug 5: seller_orders_screen Uses Different Status Labels (LOW)

**File**: `seller_orders_screen.dart:26-35`

**Issue**: This screen uses `AppConstants.statusPlaced`, `statusPreparing`, `statusReady`, `statusReceived` -- which are the DB-level values. It sends these directly to `updateOrderStatus()`.

**Impact**: Creates a code path that bypasses the mapping layer's intent and uses a different status vocabulary than `ManageOrdersScreen`. Works but is inconsistent.

---

### Bug 6: Hardcoded Fake Data in ManageOrdersScreen (LOW)

**File**: `manage_orders_screen.dart:401-402`

**Issue**: The `time_ago` and `fulfillment_type` are computed from the list index (fake) rather than from actual order data:

```dart
order['time_ago'] = '${(index + 1) * 5} min ago';
order['fulfillment_type'] = 'Walk-in';
```

**Impact**: Incorrect metadata displayed to seller.

---

### Bug 7: OrderDetailScreen SnackBar Always Says "Confirmed" (LOW)

**File**: `order_detail_screen.dart:206`

**Issue**: The confirmation message is hardcoded as "confirmed" regardless of the actual status transition:

```dart
content: Text('Order #$shortId confirmed'),
```

**Impact**: Misleading user feedback when performing transitions like "Mark Ready" or "Mark Delivered".

---

## Key Files Reference

### Core Services (Backend Logic)

| File | Purpose |
|------|---------|
| `lib/services/order_service.dart` | High-level order service (fetch, status count, place) |
| `lib/services/supabase_service.dart` | Low-level Supabase DB operations including status mapping |
| `lib/services/seller_notification_service.dart` | Seller notifications for new orders, stale orders |
| `lib/services/sales_service.dart` | Revenue/order counts, pending order counts |
| `lib/services/product_service.dart` | Product active status sync |

### Providers (State Management)

| File | Purpose |
|------|---------|
| `lib/providers/order_provider.dart` | ChangeNotifier managing order state and business logic |

### Seller Screens

| File | Purpose |
|------|---------|
| `lib/screens/seller/seller_dashboard_screen.dart` | Dashboard with metrics, recent orders |
| `lib/screens/seller/manage_orders_screen.dart` | Primary order management with tab filtering |
| `lib/screens/seller/order_detail_screen.dart` | Single order detail with status timeline |
| `lib/screens/seller/seller_orders_screen.dart` | Legacy "Workshop Orders Queue" screen |
| `lib/screens/seller/custom_orders_screen.dart` | Custom order requests (has documented bug) |

### Customer Screens

| File | Purpose |
|------|---------|
| `lib/screens/customer/my_orders_screen.dart` | Customer "My Orders" with tabs |
| `lib/screens/customer/tracking_screen.dart` | Customer order tracking with timeline |
| `lib/screens/customer/order_review_screen.dart` | Post-delivery rating/review |

### Widgets

| File | Purpose |
|------|---------|
| `lib/widgets/seller/seller_order_card.dart` | Reusable order card with status-based actions |
| `lib/widgets/seller/seller_status_chip.dart` | Status chip using UI-level labels |
| `lib/widgets/sole_status_chip.dart` | Customer-facing status chip using DB-level labels |
| `lib/widgets/sole_timeline.dart` | Timeline progress widget |

### Database

| File | Purpose |
|------|---------|
| `supabase/schema.sql` | Full database schema with CHECK constraint |
| `supabase/migrations/` | Database migrations including status fixes |

### Admin Portal

| File | Purpose |
|------|---------|
| `admin-portal/src/pages/Orders.jsx` | Admin order management page |
| `admin-portal/src/hooks/useOrders.js` | React Query hooks for order operations |
| `admin-portal/src/lib/constants.js` | Admin portal order status list |
