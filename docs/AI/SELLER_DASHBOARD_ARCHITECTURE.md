# Seller — Dashboard Architecture

> **Purpose:** Describe the **Seller Dashboard** (`SellerDashboardScreen`) — the Tab 0 landing screen of the seller app — its data flow, UI blocks, and the services/providers it depends on, so AI agents can work on it without re-reading the whole screen.
> **Last updated:** August 10, 2026

---

## 1. Overview

The dashboard is the seller's "morning briefing": it answers four questions at a glance — **sales, attention, orders, stock** — with live data pulled from Supabase.

```
SellerShell (lib/screens/seller/seller_shell.dart)
  └─ Tab 0: SellerDashboardScreen   ← this document
       ├─ AppBar (CUFMAI brand + greeting + message bell + notification bell)
       ├─ Block 1   Today's Snapshot — 4 metric cards (Sales / Week / Low Stock / Custom)
       ├─ Block 1.5 GCash Payments to Confirm card (live count, 30s poll)
       ├─ Block 2   "Needs Attention" alert strip (low stock + stale orders + customs)
       ├─ Block 3   Order Status Summary (placed / preparing / ready / received)
       ├─ Block 4   Recent Orders (limit 3) → ManageOrdersScreen / OrderDetailScreen
       ├─ Block 5   Weekly stacked-area chart (Online + In-Store)
       ├─ Block 6   Monthly stacked-area chart
       ├─ Block 7   Revenue breakdown doughnut (online vs in-store)
       └─ Block 8   "View Full Sales Report" CTA → ReportsScreen
```

**Key facts:**

- **One-shot future, not a provider.** All data lives in a single `Future<_DashboardData>` (`_dashboardFuture`) created by `_fetchDashboardData()` on `initState` (post-frame), on pull-to-refresh, and on reconnect after being offline. There is **no periodic polling** except the GCash card (Block 1.5, 30s).
- **12-way `Future.wait`.** The dashboard fires 12 fetches concurrently and assembles `_DashboardData` from the indexed results. It also **mutates shared state**: `ProductProvider.loadSellerProducts()` and `OrderProvider.loadOrders()` are called inside `_fetchDashboardData` to compute low-stock and stale orders.
- **Two order-fetch paths can disagree.** Recent Orders uses `OrderService.getRecentOrders()` (lean, store-scoped, limit 3). Stale-order alerts use `OrderProvider.loadOrders()` → `SupabaseService.fetchOrders()` (fat, all orders). See `SELLER_RECENT_ORDERS_ARCHITECTURE.md`.
- **Revenue definition (app-wide):** every revenue query filters `status != 'cancelled'` **AND** `payment_status = 'paid'` — money actually received. POS cash is `paid` at insert; POS GCash starts `pending` until the poller flips it (GCash revenue appears slightly late). See `REVENUE_ARCHITECTURE.md`.
- **Read-only dashboard.** Status changes are deliberately NOT possible from the dashboard (`onPrimaryAction: () {}` no-op) — they belong in the Orders tab / Order Detail screen.

---

## 2. File Map

| Layer | File | Role |
|-------|------|------|
| Screen | `lib/screens/seller/seller_dashboard_screen.dart` | The dashboard: `_DashboardData` :37, `_loadDashboard` :115, `_fetchDashboardData` :138, `_buildDashboardBody` :423, `_PaymentsToConfirmCard` :1054 |
| Shell | `lib/screens/seller/seller_shell.dart` | 5-tab host; Dashboard is Tab 0 (`IndexedStack`, so state survives tab switches) |
| Widget | `lib/widgets/seller/seller_metric_card.dart` | Block 1 metric cards (large/small variants) |
| Widget | `lib/widgets/seller/seller_sparkline.dart` | Mini line chart inside the sales metric cards |
| Widget | `lib/widgets/seller/seller_alert_chip.dart` | Block 2 alert chips |
| Widget | `lib/widgets/seller/seller_order_card.dart` | Block 4 order cards |
| Widget | `lib/widgets/seller/seller_stacked_area_chart.dart` | Blocks 5 & 6 revenue charts (fl_chart) |
| Widget | `lib/widgets/seller/seller_revenue_doughnut.dart` | Block 7 online vs in-store doughnut |
| Service | `lib/services/sales_service.dart` | Revenue/today/weekly/monthly/trend queries :199-368, :627-700 |
| Service | `lib/services/order_service.dart` | `getRecentOrders` :154, `getOrderCountByStatus` :241 |
| Service | `lib/services/store_service.dart` | `getMyStore` :19 (store id + rating) |
| Service | `lib/services/direct_gcash_service.dart` | `expireOverdue()` for the Block 1.5 sweep |
| Service | `lib/services/seller_notification_service.dart` | `createStaleOrder` (fire-and-forget) |
| State | `lib/providers/product_provider.dart` | `loadSellerProducts()` :low-stock source |
| State | `lib/providers/order_provider.dart` | `loadOrders()` :stale orders + counts source |
| State | `lib/providers/seller_notification_provider.dart` | `init(storeId)` + `unreadBadge` (bell) |
| State | `lib/providers/message_provider.dart` | `subscribeToInbox(storeId:)` + `unreadBadge` (message bell) |
| Model | `lib/models/sales_trend_data.dart` | `SalesTrendResult` consumed by charts/doughnut |

---

## 3. Data Flow

### 3.1 Bootstrap (`_loadDashboard`, seller_dashboard_screen.dart:115-136)

On `initState` (post-frame) and on offline→online reconnect (`ConnectivityService.isOnlineStream`):

```
1. StoreService.getMyStore()            → storeId (or bail, no store)
2. setState: _dashboardFuture = _fetchDashboardData(auth, storeId)
3. _dashboardFuture.then → _cachedData (serves as fallback when refresh fails)
4. SellerNotificationProvider.init(storeId)   ← idempotent per store
5. MessageProvider.subscribeToInbox(storeId:)
   MessageProvider.loadConversationsForStore(storeId)
```

### 3.2 Loading (`_fetchDashboardData`, seller_dashboard_screen.dart:138-226)

A 12-way `Future.wait`. **Index order matters — keep it in sync when editing:**

```
Future.wait([
  0  SalesService.getTodayRevenue(storeId)                        → todayRevenue
  1  OrderService.getRecentOrders(storeId, limit: 3)              → recentOrders
  2  OrderService.getOrderCountByStatus(storeId)                  → ordersByStatus
  3  StoreService.getMyStore()                                    → store (rating, review_count)
  4  SalesService.getOnlineWeeklyRevenue(storeId)                 → onlineWeeklyChart
  5  SalesService.getPosWeeklyRevenue(storeId)                    → posWeeklyChart
  6  SalesService.getOnlineMonthlyRevenueTrend(storeId)           → onlineMonthlyChart
  7  SalesService.getPosMonthlyRevenueTrend(storeId)              → posMonthlyChart
  8  SalesService.getWeeklyTrend(storeId, channel: all)           → weeklyTrend
  9  SalesService.getMonthlyTrend(storeId, channel: all)          → monthlyTrend
  10 ProductProvider.loadSellerProducts()                          → low-stock (side effect)
  11 OrderProvider.loadOrders()                                    → stale orders (side effect)
])
```

After the wait (guard with `mounted`):

- `weeklySalesChart[i] = onlineWeekly[i] + posWeekly[i]` (7 days, Mon=0…Sun=6)
- `monthlySalesChart[i] = onlineMonthly[i] + posMonthly[i]` (6 months)
- `lowStockItems` = every product/size with `0 < qty <= 5` (from `products.sizes` map, `_getLowStockItems` :246)
- `pendingCustoms` = `OrderProvider.customizations` where `status == 'pending'`
- `staleOrders` = first 2 orders where `status == 'placed'`
- Fire-and-forget: for each stale order, `SellerNotificationService.createStaleOrder(...)` (never awaited)

If `!mounted`, returns `_emptyDashboard()` (all zeros).

### 3.3 Rendering (seller_dashboard_screen.dart:423-533)

`FutureBuilder<_DashboardData>` with three states:

| Snapshot state | Render |
|---|---|
| `waiting` + no cache | `_buildLoadingSkeleton()` (shimmer boxes mirroring the layout) |
| `hasError` + no cache | `ErrorRetryWidget` (retry rebuilds `_dashboardFuture`) |
| `hasData` (or cache fallback) | `_buildDashboardBody(data)` |

Body is a `RefreshIndicator` + `SingleChildScrollView`; on refresh the future is replaced and `_cachedData` is updated on success (errors keep showing stale data).

---

## 4. UI Blocks

### 4.1 AppBar (seller_dashboard_screen.dart:306-343)

- `AppConstants.secondary` background, `scrolledUnderElevation: 0`, `surfaceTintColor: transparent`.
- Title: `CUFMAI` brand + time-based greeting (`Good morning/afternoon/evening`, first name from `AuthProvider.displayName`).
- Actions: message icon with `MessageProvider.unreadBadge` (refresh-then-navigate to `SellerInboxScreen`), notification bell with `SellerNotificationProvider.unreadBadge` (refresh-then-navigate to `SellerNotificationCenterScreen`).

### 4.2 Block 1 — Metrics Grid (`_buildMetricsGrid` :536)

2×2 asymmetric grid (58/42 flex ratio):

| Card | Data | Tap target |
|---|---|---|
| TODAY'S SALES (large) | `todayRevenue`, subtitle = `{rating} ★` only if `review_count > 0`, sparkline of weekly | — |
| THIS WEEK (small) | sum of `weeklySalesChart`, week date range subtitle, sparkline | `ReportsScreen` |
| LOW STOCK (small) | `lowStockCount`, green/amber color | `ManageProductsScreen(initialFilter: 'Low Stock')` |
| CUSTOM ORDERS (large) | `pendingCustoms` | `CustomOrdersScreen` |

### 4.3 Block 1.5 — GCash Payments to Confirm (`_PaymentsToConfirmCard` :1054-1199)

Self-contained `StatefulWidget`:

- `Timer.periodic(30s)` → `_refresh()`: fires `DirectGcashService().expireOverdue()` (unawaited) then counts `orders` with `store_id` + `status == 'awaiting_payment_confirmation'`.
- Tapping pushes `GcashPaymentQueueScreen`. Red badge count when `> 0`.
- **This is the only self-refreshing part of the dashboard** — it polls independently of `_dashboardFuture`.

### 4.4 Block 2 — Alert Strip (`_buildAlertStrip` :640)

Horizontal `ListView` of `SellerAlertChip`s, only rendered when anything needs attention:

- Low-stock items (max 3) → `ManageProductsScreen(initialFilter: 'Low Stock')`
- Stale orders → `ManageOrdersScreen(initialFilter: 'pending')`
- Pending customs → `CustomOrdersScreen`

### 4.5 Block 3 — Order Status Summary (`_buildStatusSummary` :700)

Card with counts for `placed → preparing → ready → received` (fixed order, `_statusColor` :767) + total.

### 4.6 Block 4 — Recent Orders (`_buildRecentOrders` :783)

Read-only, limit **3** (note: `SELLER_RECENT_ORDERS_ARCHITECTURE.md` documents an older limit of 5 — the live code passes `limit: 3` at :147). Each order is enriched with `time_ago` (from `_timeAgo` :276) then rendered as `SellerOrderCard(showPrimaryAction: false)` → tap opens `OrderDetailScreen`. "View All Orders →" → `ManageOrdersScreen`.

### 4.7 Blocks 5-7 — Charts

- **Block 5** Weekly `SellerStackedAreaChart` — `weeklyTrend.points`, labels `['Mon'…'Sun']`, subtitle = week date range (`_getWeekDateRange` :936).
- **Block 6** Monthly `SellerStackedAreaChart` — `monthlyTrend.points`, month-abbrev x-labels from point dates.
- **Block 7** `SellerRevenueDoughnutChart` — online vs in-store split of `monthlyTrend`.

All three cards use `clipBehavior: Clip.antiAlias` (stops y-axis bleed-through in dark mode). Charts use cached trend data on refresh errors.

### 4.8 Block 8 — Full Report CTA (`_buildFullReportCta` :849)

Highlighted card → `ReportsScreen` ("Daily revenue, top products & CSV export").

---

## 5. Services Contract (what the dashboard actually queries)

| Method | Source | Filters | Shape |
|---|---|---|---|
| `SalesService.getTodayRevenue` :199 | online today + `fetchTodaySales` (POS) | `status != cancelled`, `payment_status = paid` | `double` |
| `SalesService.getOnlineWeeklyRevenue` :238 | `orders` (6 days back) | same paid filter | `List<double>` 7 (Mon=0) |
| `SalesService.getPosWeeklyRevenue` :250 | `fetchWeeklySales` (POS) | paid filter | `List<double>` 7 |
| `SalesService.getOnlineMonthlyRevenueTrend` :321 | `orders` (6 months back) | paid filter | `List<double>` 6 |
| `SalesService.getPosMonthlyRevenueTrend` :339 | POS orders | paid filter | `List<double>` 6 |
| `SalesService.getWeeklyTrend` :627 | `_fetchTrend` :703 | paid filter, current vs previous week | `SalesTrendResult` |
| `SalesService.getMonthlyTrend` :655 | `_fetchTrend` | paid filter, 6mo vs prior 6mo | `SalesTrendResult` |
| `OrderService.getRecentOrders` :154 | `orders` + `profiles` + `order_items` + `products` | statuses `['pending','placed']`, store-scoped, limit 3 | `List<Map>` |
| `OrderService.getOrderCountByStatus` :241 | `orders` | not `cancelled` | `Map<String, int>` |
| `StoreService.getMyStore` :19 | `stores` | current seller's store | `Map?` (id, rating, review_count) |

> ⚠️ `_getOrderIds(storeId)` is an internal chain (products → store products → order ids); `_getPosOrderIds` reads `source = 'pos'` directly. If you change order ownership logic, verify both paths.

---

## 6. Known Pitfalls / Gotchas

1. **Future.wait index coupling.** Adding/removing a fetch at :145-159 breaks every index cast at :201-224. Keep a comment next to the array.
2. **Two order paths, no sync.** Recent Orders (lean, `getRecentOrders`) vs alerts/status summary (fat, `OrderProvider`). They're fetched in the same `Future.wait` but can still disagree (different filters, different limits).
3. **Side effects inside a "fetch".** `_fetchDashboardData` calls `loadSellerProducts()` and `loadOrders()` — these write shared provider state. `loadOrders()` is NOT store-scoped, so the dashboard's `ordersByStatus`/`staleOrders` derive from the same provider data as the Orders tab.
4. **No periodic refresh of the main data.** Only pull-to-refresh, init, and reconnect reload. `OrderProvider` updates from other screens won't refresh the dashboard (no `listen`/`watch` on it — only `read`).
5. **GCash count is a separate live poll** (30s) with its own `_loading` state — it does not participate in `_DashboardData`.
6. **Stale-order notification is fire-and-forget** — errors are silently swallowed by design; it runs on every dashboard load.
7. **Revenue lag for POS GCash:** revenue queries require `payment_status = 'paid'`; POS GCash orders stay `pending` until the confirmation poller flips them, so they appear in revenue later than cash.
8. **`IndexedStack` keeps dashboard alive** across tab switches (SellerShell :92) — init only runs once; returning to the tab does NOT re-fetch.

---

## 7. Modification Guide

### Adding a new metric card
1. Add the field to `_DashboardData` (:37) + `_emptyDashboard` (:228).
2. Add the fetch to the `Future.wait` (:145) and map the new index in the return (:208).
3. Add the card in `_buildMetricsGrid` (:536) and, if it needs attention, an alert chip in `_buildAlertStrip` (:640).

### Adding a new chart
1. Add the query to `SalesService` (or reuse `getWeeklyTrend`/`getMonthlyTrend`).
2. Insert a card container with `clipBehavior: Clip.antiAlias` in `_buildDashboardBody` (:423) between Blocks 5-7.
3. See `REVENUE_ARCHITECTURE.md` for revenue definition rules — charts and KPI cards must agree.

### Changing the revenue definition
Every revenue query in `SalesService` (today/weekly/monthly/trends) applies `neq('status','cancelled')` + `eq('payment_status','paid')`. Update them **all** — dashboard trends, KPI cards, monthly, and Reports share the same method family. See `REVENUE_ARCHITECTURE.md` §6.1.

### Related docs
- `SELLER_RECENT_ORDERS_ARCHITECTURE.md` — Block 4 deep-dive
- `SELLER_ORDER_FLOW_ARCHITECTURE.md` — order lifecycle + stale alerts
- `REVENUE_ARCHITECTURE.md` — revenue definition + charts
- `SELLER_ARCHITECTURE_GRAPH.md` — full seller module graph + screen routing
- `CHECKOUT_AND_GCASH_ARCHITECTURE.md` — Block 1.5 GCash card context
- `SELLER_POS_ARCHITECTURE.md` — POS + dashboard metrics interplay
- `STORE_ARCHITECTURE_AND_RATINGS.md` — `stores.rating` display rules
