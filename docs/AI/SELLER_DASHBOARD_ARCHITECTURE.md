# Seller — Dashboard Architecture

> **Purpose:** Describe the **Seller Dashboard** (`SellerDashboardScreen`) — the Tab 0 landing screen of the seller app — its data flow, UI blocks, and the services/providers it depends on, so AI agents can work on it without re-reading the whole screen.
> **Last updated:** September 18, 2026

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
| Screen | `lib/screens/seller/seller_dashboard_screen.dart` | The dashboard: `_DashboardData` :44, `didChangeDependencies` (re-entry hook) :161, `_loadDashboard` :221, `_fetchDashboardData` :261, `_fetchDashboardDataInner` :270, `_buildDashboardBody` :656, `_PaymentsToConfirmCard` :1513 |
| Shell | `lib/screens/seller/seller_shell.dart` | 5-tab host; Dashboard is Tab 0. **`PageView` + `KeepAlivePage`** — a visited tab stays mounted, so state survives tab switches and re-entry does NOT re-run `initState`. The nav bar and the tab host are both handed to **`HideOnScrollBottomBar`** (the same wrapper the customer shell uses), so the bar collapses out of the layout on a downward scroll and hands its 65px back to the page — the briefing is readable full-bleed without the dashboard asking for it. Its trailing `SizedBox(height: 80)` is therefore breathing room only: the bar occupies real layout space above the page, never overlapping it |
| Widget | `lib/widgets/keep_alive_page.dart` | Makes a lazily-built `PageView` page survive being scrolled out of view (the tab host's keep-alive mechanism) |
| Widget | `lib/widgets/active_tab.dart` | Publishes the on-screen tab index. The ONLY re-entry signal a kept-alive page gets, since it is no longer rebuilt on a switch |
| Widget | `lib/widgets/seller/seller_metric_card.dart` | Block 1 metric cards (large/small variants) |
| Widget | `lib/widgets/seller/seller_sparkline.dart` | Mini line chart inside the sales metric cards |
| Widget | `lib/widgets/seller/seller_alert_chip.dart` | Block 2 alert chips |
| Widget | `lib/widgets/seller/seller_order_card.dart` | Block 4 order cards |
| Widget | `lib/widgets/seller/seller_revenue_columns_chart.dart` | Blocks 5 & 6 revenue trend — one stacked column per bucket (fl_chart `BarChart`) |
| Widget | `lib/widgets/seller/seller_revenue_doughnut.dart` | Block 7 online vs in-store doughnut (both read `SellerTheme.channelOnline` / `channelInStore`) |
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
1. StoreService.getMyStore()            → storeId; null → "no store" prompt
                                          (new sellers have no store row yet
                                          until they run CreateStoreScreen);
                                          throw → error card with retry
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

- **Block 5** Weekly `SellerRevenueColumnsChart` — `weeklyTrend.points`, labels `['Mon'…'Sun']`, subtitle = week date range (`_getWeekDateRange` :936).
- **Block 6** Monthly `SellerRevenueColumnsChart` — `monthlyTrend.points`, month-abbrev x-labels from point dates.

Both are the same widget: **stacked columns**, one per bucket, height = the bucket's total, split online (base) / in-store (top) by `rodStackItems`. Replaced the stacked*area* card, which needed two curves to be read against each other and blended into brown where in-store was small. `isWeekly` only changes the delta chip's wording. See `REVENUE_ARCHITECTURE.md` §7 for the chart internals and `test/widgets/seller_revenue_columns_chart_test.dart` for the stacking contract.
- **Block 7** `SellerRevenueDoughnutChart` — online vs in-store split of `monthlyTrend`. The ring is an **extruded (3D) doughnut** painted by `Doughnut3DPainter` (same file) instead of fl_chart's `PieChart`: a squashed top face, a dark front wall `depth: 26` px tall, and the far inner wall of the hole blurred into a shadow. `DoughnutSlice` carries one channel's value + colour; `_ExtrudedRing` owns three controllers and two gestures:

- **Draw-in** — 900ms `easeOutCubic`, `progress` 0…1 so the sweep and the extrusion rise together.
- **Held** — a `Listener` (not the tap callbacks: the pointer is the only thing that cannot be left stuck on when the arena goes to a scroll) raises the ring to the same pose a hop peaks at, and sets it down on up/cancel. One `_offCard` (0…1) composes the hold with the hop's sine arc, capped at 1, so a tap on a held ring rises once and neither can drop the ring out from under the other. Reduced motion gets the pose, not the travel (`PressSink`'s rule).
- **Tap → hop** — `hopDuration` 1100ms, one `_pose()` record the painter and the figure in the hole both read, so they cannot disagree: `spin` a full revolution through the seam, `lift` 13px, `depth` 26→33, `flatness` 0.55→0.47. Skipped under `MediaQuery.disableAnimations`, and **also skipped when the ring is already off the card** (`_offCard > 0.5`) — letting go of a picked-up ring is a set-down, not a tap; playing the hop on top of the descending hold makes the ring dip, jump back to the top of the hop and land.
- **Slide → turn** — 1:1 with the finger at `turnPerPixel` (one revolution per 320px, the card's own content width), then `FrictionSimulation(0.16, …)` coasts a flick to a stop, capped at 10 rad/s. `_slide` is an *unbounded* controller, and the painter's `spin` is `_slide.value + hop turn` so the two gestures add instead of restarting each other. A slide stays live under reduced motion — it is direct manipulation, like scroll physics.

Both gestures are `excludeFromSemantics`: they are paint only, with the legend rows carrying the numbers. Public `ringKey` marks the `RepaintBoundary` around the canvas (cheap animation + the hook the geometry tests capture).

**Testing note:** an `AnimationController`'s first frame reports zero elapsed, so a test that starts an animation and then pumps once sees the *start* pose — every hold/hop assertion needs a `pump()` to start the ticker before the `pump(duration)` that advances it. See `test/widgets/seller_revenue_doughnut_3d_test.dart` for the pixel contracts, and mind the trap documented on the painter: **`Path.arcTo(rect, angle, 2π)` fills as nothing at all**, so the lone-slice case is drawn as two ovals under even-odd.

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
4. **Refresh paths:** pull-to-refresh, init, offline→online reconnect, and a **staleness refresh on tab re-entry** (`didChangeDependencies` → `_refreshIfStale`, only when the cached briefing is older than 60s — re-selecting the tab is never on its own a reason to fetch). `OrderProvider` updates from other screens still won't refresh the dashboard (no `listen`/`watch` on it — only `read`).
5. **GCash count is a separate live poll** (30s) with its own `_loading` state — it does not participate in `_DashboardData`. It **pauses while the dashboard is off screen** and sweeps once on the way back in, so it can't keep hitting the backend while the seller works in another tab.
6. **Stale-order notification is fire-and-forget** — errors are silently swallowed by design; it runs on every dashboard load.
7. **Revenue lag for POS GCash:** revenue queries require `payment_status = 'paid'`; POS GCash orders stay `pending` until the confirmation poller flips them, so they appear in revenue later than cash.
8. **Tabs are kept alive, so nothing here is rebuilt on a switch.** `SellerShell` hosts its 5 pages in a `PageView` where each page is wrapped in `KeepAlivePage`. A visited page stays mounted: `initState` runs **once per session**, and returning to the tab does NOT re-run it or re-fetch. Two consequences to know before editing this screen:
   - A kept-alive page's `build` does not re-run on re-entry either (the widget instance is unchanged, so `Element.updateChild` short-circuits). The tab-visibility hook in `didChangeDependencies` via `ActiveTab` is therefore the *only* re-entry signal — that is what `_refreshIfStale` hangs off.
   - Timers inside a kept-alive page run for the **whole session** unless they pause themselves when off screen. The GCash poll does; so does the Products tab's 4s alert ticker (`manage_products_screen.dart`). Any new `Timer.periodic` added here needs the same treatment.

   Unvisited tabs are still built lazily — the host does NOT use a bare `IndexedStack`, which would construct all five pages (and fire all five screens' fetches) on the first frame. The `AdminShell` switches by index rather than by scrolling, and wraps its six tabs in `LazyIndexedStack` (`lib/widgets/lazy_indexed_stack.dart`) for that same reason: a slot renders nothing until its index has been visited once, then keeps the page mounted exactly like an `IndexedStack` would.

   The two hosts therefore use different primitives for the same guarantee — `KeepAlivePage` for the `PageView`-based seller/customer shells, `LazyIndexedStack` for the index-based admin shell. If you add a tab to either, it inherits laziness; nothing extra is needed on the screen itself.

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
