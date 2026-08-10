# Seller — Recent Orders Architecture

> **Purpose:** Describe the **Recent Orders** feature on the seller side (the dashboard block) and how it connects to the wider seller order surfaces, so AI agents can work on it without re-reading the whole flow.
> **Last updated:** August 5, 2026

---

## 1. Overview

"Recent Orders" is **Block 4 of the Seller Dashboard** (`SellerDashboardScreen`) — a glanceable list of the 5 most recent orders for the seller's store, with a "View All Orders →" link into the full management screen.

```
SellerDashboardScreen (lib/screens/seller/seller_dashboard_screen.dart)
  └─ _buildRecentOrders(data) :760   ← Block 4
       ├─ 5 × SellerOrderCard (showPrimaryAction: false → full-width "View Details")
       ├─ tap card → OrderDetailScreen(order: <enriched map>)
       └─ "View All Orders →" → ManageOrdersScreen
```

**Key facts:**

- **Read-only summary.** Status changes deliberately do NOT happen from the dashboard — `onPrimaryAction: () {}` is a no-op; the comment at `:789-791` says status changes belong in the Orders tab / Order Detail screen.
- **Two completely separate order-fetch paths exist.** The dashboard block uses `OrderService.getRecentOrders()` (lean, store-scoped, limit 5). The Orders tab and stale-order alerts use `OrderProvider.loadOrders()` → `SupabaseService.fetchOrders()` (fat, all orders, joined). They can disagree — never assume they're the same data.
- **No provider, no cache-busting.** Recent orders live inside a one-shot `Future<_DashboardData>` (`_dashboardFuture`) rebuilt only on screen init or reconnect after being offline. There is no refresh from OrderProvider updates.

---

## 2. File Map

| Layer | File | Role |
|-------|------|------|
| Screen | `lib/screens/seller/seller_dashboard_screen.dart` | Dashboard; Block 4 `_buildRecentOrders` :760, data loading `_fetchDashboardData` :135, `_timeAgo` :273 |
| Widget | `lib/widgets/seller/seller_order_card.dart` | Reusable order card (also used by ManageOrders) |
| Screen | `lib/screens/seller/order_detail_screen.dart` | Tap target — full order detail + status actions |
| Screen | `lib/screens/seller/manage_orders_screen.dart` | "View All Orders →" target; the full orders queue |
| Service | `lib/services/order_service.dart` | `getRecentOrders()` :149, `getOrderCountByStatus()` :231, `_getOrderIdsForStore()` :22, `fetchStoreOrders()` :63 |
| Service | `lib/services/supabase_service.dart` | `fetchOrders()` :283 (the OTHER path), `updateOrderStatus()` :553 |
| State | `lib/providers/order_provider.dart` | `loadOrders()` :38 (feeds ManageOrders + dashboard alerts, NOT recent orders) |

---

## 3. Data Flow

### 3.1 Loading (`_fetchDashboardData`, seller_dashboard_screen.dart:135-223)

On `initState` (post-frame) `_loadDashboard()` resolves `StoreService.getMyStore()` → store id → `_fetchDashboardData`. Recent orders come from a 12-way `Future.wait` (index **1**):

```
Future.wait([
  0  SalesService.getTodayRevenue(storeId)
  1  OrderService.getRecentOrders(storeId, limit: 5)   ← recent orders
  2  OrderService.getOrderCountByStatus(storeId)
  3  StoreService.getMyStore()
  4-9  charts + trends
  10 ProductProvider.loadSellerProducts()   (low-stock computation)
  11 OrderProvider.loadOrders()             (stale-order alerts)
])
```

After the wait, `results[1]` is stored in `_DashboardData.recentOrders`.

### 3.2 The query — `OrderService.getRecentOrders(storeId, limit)` (order_service.dart:149-228)

Because `orders` has **no `store_id`-based RLS filter** that the seller can rely on for arbitrary stores, orders are resolved through the **products → order_items → orders chain**:

```
Step 1  _getOrderIdsForStore(storeId, limit)
        products(id) WHERE store_id = storeId
        → order_items(order_id) WHERE product_id ∈ ids
        → orders(id) WHERE id ∈ ids ORDER BY created_at DESC LIMIT n

Step 2  orders(id, customer_id, total_amount, status, created_at)
        WHERE id ∈ orderIds ORDER BY created_at DESC

Step 3  profiles(id, full_name) WHERE id ∈ customerIds   → order['customer_name']

Step 4  order_items(order_id, product_id, quantity) WHERE order_id ∈ orderIds
        + products(id, name) → order['product_name'] (first item only), order['quantity']
```

Result: each order map has the base columns plus `customer_name`, `product_name`, `quantity`. **No status filter** — cancelled orders are included.

### 3.3 Rendering (seller_dashboard_screen.dart:761-825)

```dart
final enriched = Map<String, dynamic>.from(order);
enriched['time_ago'] = _timeAgo(order['created_at']);   // "5m ago" / "2d ago"
enriched['fulfillment_type'] = 'Walk-in';               // ← hardcoded
SellerOrderCard(order: enriched, onPrimaryAction: () {}, showPrimaryAction: false, onViewDetails: → OrderDetailScreen)
```

`SellerOrderCard` (lib/widgets/seller/seller_order_card.dart):
- Row 1: `Order #<8-char id>` · `SellerStatusChip(status)` · time-ago
- Row 2: customer name (+ phone icon, `onTap: () {}` — **dead**)
- Row 3: `N items · ₱total  Walk-in`
- With `showPrimaryAction: false`: single full-width "View Details" outlined button (status label mapping in the card is irrelevant on the dashboard)

### 3.4 Tap target — `OrderDetailScreen(order: enriched)`

Status-driven (order_detail_screen.dart:26-71). **Note the UI→DB mapping** — UI labels go through `SupabaseService._mapUiStatusToDb()`:

| Current (UI) | Action | Sent value → DB |
|--------------|--------|-----------------|
| `pending` | (no action label; Reject available) | — |
| `preparing` | Mark Ready | `ready` |
| `ready` | Mark Delivered | `delivered` |
| `cancelled` | Restore | `pending` |

Status machine (shared with customer side): `pending → preparing → ready → delivered → received`, plus `cancelled` (instant or approved cancellation request).

---

## 4. Adjacent surfaces (don't confuse them)

| Surface | Entry | Data source | Purpose |
|---------|-------|-------------|---------|
| **Recent Orders** (dashboard Block 4) | `_buildRecentOrders` | `OrderService.getRecentOrders` (limit 5) | Glanceable summary, read-only |
| **ManageOrdersScreen** | "View All Orders →" | `OrderProvider.orders` ← `SupabaseService.fetchOrders()` (ALL orders, joined, sorted by id desc) | Full queue with per-card status actions + Slidable reject (cancelled only) |
| **Stale-order alerts** | `_fetchDashboardData` :174-192 | `orders` where status == `placed`, take 2 → `SellerNotificationService.createStaleOrder` | Fire-and-forget seller notification |

---

## 5. Gotchas for AI Agents

1. **`fulfillment_type` is hardcoded `'Walk-in'`** (`seller_dashboard_screen.dart:787`) even though `getRecentOrders` includes online AND POS orders — a known imprecision, not real data.
2. **Two fetch paths, no sync.** The dashboard's recent orders are fetched once and never reloaded when `OrderProvider` refreshes or a status changes on another screen. If a task needs fresh data after a status update, recent orders must be reloaded explicitly (e.g. `_loadDashboard()` or a pull-to-refresh).
3. **Cancelled orders appear in Recent Orders** — `getRecentOrders` has no status filter (contrast: `getOrderCountByStatus` excludes `cancelled` at order_service.dart:239).
4. **3 sequential round trips + chain** for 5 orders — fine at limit 5, but raising the limit multiplies latency; the chain (`_getOrderIdsForStore`) also means orders whose products were deleted are invisible.
5. **OrderProvider sorts by numeric `id` desc** (order_provider.dart:45), recent orders sort by `created_at` desc — same-ish result but not guaranteed identical ordering.
6. **`SellerOrderCard` is shared** with ManageOrdersScreen — changing its layout affects both surfaces; the `showPrimaryAction` flag is the difference.
7. **The phone icon is a no-op** (seller_order_card.dart:120) — don't wire it to anything without checking the design intent.
8. **Profiles SELECT is broad** — `20260715090200_fix_profiles_rls_for_conversations.sql` sets `USING (true)`, so the customer-name lookups in `getRecentOrders` work, but never add sensitive data to `profiles`.
