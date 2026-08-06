# My Orders — Complete Architecture Reference

> **Purpose:** Provide a comprehensive reference for AI agents working on the customer-facing **My Orders** feature (list + all 6 tabs + the shared order detail/tracking screen).
> **Scope:** Covers the full customer order lifecycle visible from My Orders: loading, tab filtering, detail navigation, cancellation, receipt confirmation, and review.
> **Last updated:** August 5, 2026

---

## 1. Overview

`MyOrdersScreen` is the customer's order history screen with **6 filter tabs**:

```
All orders | Unpaid | Processing | Shipped | Review | Returns
```

Key architectural facts:

- **One fetch, six filters.** The screen loads ALL of the customer's orders once (`OrderService.fetchMyOrders()`) and each tab is a **client-side filter** over the in-memory list. Switching tabs never re-queries Supabase.
- **No order detail page of its own.** Tapping any order card pushes `OrderTrackingScreen` — the same screen used by order notifications and post-checkout.
- **Tabs are pseudo-categories**, not DB queries. Each tab maps to a predicate on `orders.status` / `orders.payment_status`.
- **"Returns" is not a separate table/feature** — it is the `status == 'cancelled'` filter (see §6 for how orders get there).

```
┌────────────────────────────── MY ORDERS (customer) ──────────────────────────────┐
│                                                                                  │
│  Entry points:                                                                   │
│   • Profile → "My Orders"                                                        │
│   • Profile → notification setting items (Returns/Review/etc. deep-links)        │
│   • Post-checkout "View Order"                                                   │
│   • Order push notification tap                                                  │
│                                                                                  │
│  MyOrdersScreen (6 tabs)                                                         │
│      │  tap card / action button                                                 │
│      ▼                                                                           │
│  OrderTrackingScreen — status-driven detail: timeline, info cards,               │
│      cancel / confirm receipt / review buttons, status banners                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. File Map

| Layer | File | Role |
|-------|------|------|
| Screen | `lib/screens/customer/my_orders_screen.dart` | Tab bar + order list UI (cards, pills, stepper, states) |
| Screen | `lib/screens/customer/tracking_screen.dart` | Shared order detail — timeline, actions, banners, cancellation |
| Screen | `lib/screens/customer/order_review_screen.dart` | Rating/review flow launched from tracking (Review tab) |
| Widget | `lib/widgets/order_cancellation_sheet.dart` | Reason-picker bottom sheet (returns `CancellationResult`) |
| State | `lib/providers/order_provider.dart` | `myOrders`, filter state, `cancelOrder()`, `updateOrderStatus()`, `placeOrder()` |
| Service | `lib/services/order_service.dart` | `fetchMyOrders()` Supabase query (customer orders + items join) |
| Service | `lib/services/supabase_service.dart` | `updateOrderStatus()` + `order_status_history` writes + notifications |
| Deep-link | `lib/screens/shared/profile_screen.dart` | Notification-category items → `MyOrdersScreen(initialFilter: ...)` |
| Deep-link | `lib/screens/notifications_screen.dart` | Order notification tap → `OrderTrackingScreen` |
| Deep-link | `lib/screens/customer/checkout_screen.dart` | Post-checkout → `OrderTrackingScreen(_placedOrder)` |
| Constants | `lib/constants/app_constants.dart` | Status values (`statusCancellationRequested`), cancel window hours |
| DB | `supabase/schema.sql` + `supabase/migrations/*` | `orders`, `order_items`, `order_status_history`, notification triggers |

---

## 3. Entry Points & Navigation Graph

```
PROFILE SCREEN (lib/screens/shared/profile_screen.dart)
 ├─ "My Orders" list item ────────────────► MyOrdersScreen()                 [tab: all]
 ├─ Notif item "Returns" ('returns') ─────► MyOrdersScreen(initialFilter: 'returns')
 └─ Other notif items (unpaid/processing/
    shipped/review) ─────────────────────► MyOrdersScreen(initialFilter: <filter>)

NOTIFICATIONS SCREEN (lib/screens/notifications_screen.dart:220)
 └─ tap order notification ──────────────► OrderTrackingScreen(order: <fetched row>)

CHECKOUT (lib/screens/customer/checkout_screen.dart:804)
 └─ after placeOrder success ────────────► OrderTrackingScreen(order: _placedOrder)

MY ORDERS SCREEN
 └─ tap card / "Track" / "Review" ───────► OrderTrackingScreen(order: <cached row>)

ORDER TRACKING SCREEN
 ├─ "Cancel" button ──► OrderCancellationSheet ──► OrderProvider.cancelOrder()
 ├─ "Confirm Receipt" ──► OrderProvider.updateOrderStatus(id, 'received')
 └─ "Rate & Review" ──► OrderReviewScreen(order: _order)
```

`initialFilter` valid values (`my_orders_screen.dart:28-29`): `all | unpaid | processing | shipped | review | returns`.

---

## 4. State Layer — OrderProvider (`lib/providers/order_provider.dart`)

### My-Orders-specific state

| Member | Type | Purpose |
|--------|------|---------|
| `_myOrders` | `List<Map>` | Raw unfiltered orders from `fetchMyOrders()` |
| `_filteredMyOrders` | `List<Map>` | Orders after active tab filter (exposed as `myOrders`) |
| `_myOrdersFilter` | `String` | Active tab: `all/unpaid/processing/shipped/review/returns` |
| `_isLoadingMyOrders` | `bool` | Loading flag for list UI |
| `_myOrdersError` | `String?` | Error message shown with Retry button |

### Key methods

| Method | What it does |
|--------|--------------|
| `loadMyOrders()` | Sets loading → `_orderService.fetchMyOrders()` → `_applyMyOrdersFilter()` → notify. On error clears lists and sets `_myOrdersError`. |
| `setMyOrdersFilter(filter)` | Sets `_myOrdersFilter`, re-runs `_applyMyOrdersFilter()`, notifies. **No network call.** |
| `_applyMyOrdersFilter()` | The only place tab predicates live (see §5). |
| `cancelOrder({orderId, newStatus, reason, details})` | Writes cancellation columns, then `updateOrderStatus`, then reloads both `loadOrders()` + `loadMyOrders()`. |
| `updateOrderStatus(id, status)` | Delegates to `SupabaseService.updateOrderStatus()` then `loadOrders()`. Used for confirm receipt. |
| `placeOrder(...)` | Creates order (also used by checkout); `source: 'online'` or `'pos'`. |
| `loadOrders()` | Seller/admin-oriented full order list (sorted by id desc) — separate from myOrders. |

---

## 5. Tab Filter Reference (exact predicates)

`lib/providers/order_provider.dart:228-253` — `status` and `payment_status` are lowercased before matching:

| Tab | Predicate | Notes |
|-----|-----------|-------|
| `all` | (no filter) | Every order, newest first |
| `unpaid` | `payment_status == 'unpaid' && status != 'cancelled'` | Awaiting payment |
| `processing` | `status ∈ {pending, placed, preparing}` | New → confirmed |
| `shipped` | `status == 'ready'` | Ready for pickup/delivery |
| `review` | `status == 'received'` | Delivered + receipt confirmed |
| `returns` | `status == 'cancelled'` | Cancelled orders only |

---

## 6. Order Status State Machine

DB values on `orders.status` (CHECK constraint, `supabase/schema.sql:360` + migrations):

```
pending → preparing → ready → delivered → received
                        └─────────────► cancelled        (instant cancel: pending/placed)
pending → preparing ──► cancellation_requested ─► cancelled   (seller-approval path)
```

| DB status | Timeline step (tracking) | My Orders tab | Notes |
|-----------|--------------------------|---------------|-------|
| `pending` | 0 | Processing | New order, awaiting seller |
| `placed` | 0 | Processing | Legacy value, treated like pending |
| `preparing` | 1 | Processing | Cancellation window countdown applies |
| `ready` | 2 | Shipped | "Track" action |
| `delivered` | 3 | — (not matched by any tab) | Push notification sent; customer must confirm |
| `received` | 4 | Review | "Review" action; set by customer confirm receipt |
| `cancellation_requested` | — | — | **Matches no tab** — pending seller decision |
| `cancelled` | -1 (banner) | Returns | Instant or seller-approved cancellation |

**⚠️ Critical:** `delivered` and `cancellation_requested` do NOT appear in any My Orders tab. `delivered` requires customer action (confirm receipt → `received`); `cancellation_requested` requires seller approval → `cancelled`.

### Status transitions & who performs them

| Transition | Actor | Code path |
|------------|-------|-----------|
| → `preparing`, `ready` | Seller | `manage_orders_screen.dart` → `updateOrderStatus` |
| → `delivered` | Seller | same as above |
| → `received` | Customer | `OrderTrackingScreen._confirmReceipt()` (tracking_screen.dart:243) |
| → `cancelled` (instant) | Customer | `cancelOrder(newStatus: 'cancelled')` — pending/placed |
| → `cancellation_requested` | Customer | `cancelOrder(newStatus: statusCancellationRequested)` — preparing |
| → `cancelled` (approved) | Seller | seller approves `cancellation_requested` |

---

## 7. OrderTrackingScreen — the shared detail screen

`lib/screens/customer/tracking_screen.dart` — content is fully **status-driven**.

### Init
- Deep-copies `widget.order` into `_order`.
- `_loadStatusHistory()` — reads `order_status_history` (status + `changed_at`) to render real timestamps on the timeline.
- `_startCountdownIfNeeded()` — only for `preparing`; countdown from the time the order entered `preparing` until `AppConstants.processingCancelWindowHours`, disabling the cancel button when expired.

### Cancellation eligibility (`tracking_screen.dart:94-106`)
- `_canCancel`: status ∈ {pending, placed, preparing}
- `_isPreparing`: status == preparing (drives countdown + request-vs-instant path)
- `_hasCancellationRequested`: status == `cancellation_requested` OR `cancellation_reason` is set

### Cancel flow (detailed)
```
_requestCancellation()
 1. showCancellationSheet()          → CancellationResult {reason, details} or null
 2. Confirm dialog ("cannot be undone")
 3. newStatus = _isPreparing ? 'cancellation_requested' : 'cancelled'
 4. provider.cancelOrder(orderId, newStatus, reason, details)
      a. UPDATE orders SET cancellation_reason, cancellation_details, cancelled_at
         ← written FIRST so notification trigger can read the reason
      b. SupabaseService.updateOrderStatus(id, newStatus)
           - UPDATE orders.status
           - INSERT order_status_history(status, changed_at)
           - create DB notification + push for customer (category: processing)
      c. reload loadOrders() + loadMyOrders()
 5. Optimistic local patch: _order['status'] = newStatus, banners update
 6. Snackbar: "Cancelled successfully" OR "request submitted, waiting approval"
```

### Confirm receipt flow
- Button shown when status == `delivered` (and not cancelled).
- `updateOrderStatus(id, 'received')` → triggers the `review` notification category.

### Review flow
- "Rate & Review" button (`tracking_screen.dart:846`) when `received` → `OrderReviewScreen(order: _order)`.

### Status banners (top of screen)
- `cancelled` → red banner "This order was cancelled." + reason
- `cancellation_requested` → amber banner "Cancellation request pending seller approval." + reason

---

## 8. Data Layer

### 8.1 `OrderService.fetchMyOrders()` (`lib/services/order_service.dart:335`)

```dart
SELECT id, customer_id, status, total_amount, payment_method,
       payment_status, created_at, store_id,
       order_items(id, product_id, size, quantity, unit_price,
         products(name, category,
           product_images(image_url, display_order)))
FROM orders
ORDER BY created_at DESC
```

- **No status filter, no RLS filter** (RLS scopes rows to the calling user) — all filtering is client-side.
- Nested joins are what power the card thumbnail/name (first image by `display_order`, `my_orders_screen.dart:516-527`).

### 8.2 Tables

| Table | Role |
|-------|------|
| `orders` | Order header. Status CHECK + payment fields + cancellation columns |
| `order_items` | Line items: `product_id, size, quantity, unit_price` |
| `order_status_history` | `order_id (BIGINT), status, changed_at` — timeline timestamps |
| `products` / `product_images` | Joined for name + image |

Cancellation columns (migration `20260721120000_add_order_cancellation_fields.sql`): `cancelled_at`, `cancellation_reason`, `cancellation_details`.

### 8.3 `SupabaseService.updateOrderStatus()` side effects (`supabase_service.dart:553`)
1. UPDATE `orders.status` (via `_mapUiStatusToDb`)
2. INSERT `order_status_history` row (BIGINT order_id)
3. Customer notification + push, category by status:
   - `delivered` → category `review` ("Tap to confirm receipt")
   - `received` → category `review` ("Order confirmed")
   - others → `processing`-style updates; `cancelled`/unmapped → none (per `20260702_notifications.sql`)

---

## 9. Notifications Integration

- **Categories:** `unpaid, processing, shipped, review, returns` (migration `20260702_notifications.sql:14`).
- `NotificationCategory.returns` → label "Returns" (`lib/models/notification_category.dart:20`) → profile deep-link to Returns tab.
- **Deep-link routing:** notifications with `screen: 'order_tracking'` open `OrderTrackingScreen` with the order row fetched by reference ID (`customer_home_screen.dart:155-168`, `notifications_screen.dart:220`).

---

## 10. UI Component Breakdown (`my_orders_screen.dart`)

| Component | Location | Details |
|-----------|----------|---------|
| `_OrderTab` | :479 | label + filter value pair |
| `_OrderCard` | :489 | Card layout below; tap → tracking |
| `_StatusPill` | :788 | Icon + label; cancelled = red `cancel_outlined` |
| `_OrderProgressStepper` | :885 | 4 dots + connecting lines; hidden when cancelled |
| `_OrderActionButton` | :944 | Status-aware: Cancel (outline/red) for pending/placed/preparing; Track/Review (filled) for ready/received |
| `_ChatIconButton` | :1015 | Opens order chat via `MessageService.getOrCreateConversation` (quick-message sheet if no messages yet) |

### `_OrderCard` layout
1. Row: `Order #<8-char id>` + status pill
2. Row: 64×64 thumbnail (first image by `display_order`) + product name + `Size · Qty`
3. Progress stepper (unless cancelled)
4. Row: date · `₱total` · action button (none when cancelled)
5. Overlay: chat icon top-right

### Screen states
- Loading → shimmer skeleton (`_buildLoading`)
- Error → `_buildError` (message + Retry)
- Empty → `EmptyStateWidget` ("It is empty here :-(")
- Dismissible promo banner (SMS opt-in, currently a "coming soon" snackbar)
- Offline: `NoInternetView` when loading fails offline; auto-reload on reconnect (connectivity subscription, `my_orders_screen.dart:76-83`)

---

## 11. Gotchas for AI Agents

1. **`delivered` orders disappear from all tabs.** They only exist in the card list until the customer confirms receipt. If a test expects a `delivered` order under "Processing"/"Shipped", that is wrong — tabs map to `pending/placed/preparing`, `ready`, `received`, `cancelled` only.
2. **`cancellation_requested` is tab-invisible** until the seller approves it to `cancelled`. Return requests "disappear" from Returns tab in the meantime.
3. **Tab switching is pure client-side** — never call `loadMyOrders()` on tab change; only `setMyOrdersFilter()`.
4. **`cancellation_reason` must be written BEFORE `updateOrderStatus`** (`order_provider.dart:129-141`) because the notification trigger reads it.
5. **`order_status_history.order_id` is BIGINT** — always parse the string id with `int.tryParse` before inserting (`supabase_service.dart:569`).
6. **Two separate order lists in the provider:** `orders` (all orders, seller/admin) vs `myOrders`/`_filteredMyOrders` (customer). `cancelOrder` refreshes both.
7. **POS orders** (`source = 'pos'`) land directly in `received`, skipping the pipeline — they go straight to the Review tab and can never be cancelled or appear in Returns.
8. **Status normalization:** UI compares lowercased strings; `SupabaseService._mapUiStatusToDb` maps UI labels → DB values. Keep both mappings in sync when adding statuses.
9. **Cancellation is a windowed feature** — `processingCancelWindowHours` / `MaxHours` countdown on `preparing`; past window the button disappears entirely (no disabled state).
10. **The card shows only the first product** (name, size, qty, image) even for multi-item orders — totals are still order-wide.
