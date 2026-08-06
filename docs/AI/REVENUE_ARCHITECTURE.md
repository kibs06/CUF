# Revenue — Architecture Reference

> **Purpose:** Give AI agents a working mental model of how **revenue is computed, modeled, and charted** in the seller dashboard + reports. Read this before touching any revenue graph.
> **Last updated:** August 5, 2026

---

## 1. Big Picture

Revenue = **Online orders** + **POS / in-store sales**. There are **two live channels**, and — critically — **two different DB tables** that have carried POS revenue over the app's life:

```
Revenue
├── ONLINE  → orders table        (customer checkout; linked to store via products → order_items chain)
└── POS     → orders table WHERE source='pos'   ← THE LIVE PATH (POS screen writes here)
            → sales_transactions table          ← LEGACY path — NOT written anymore
```

**⚠️ THE single most important fact:** the POS screen (`lib/screens/seller/pos_screen.dart`) records in-person sales by creating **`orders` rows with `source='pos'`** (via `OrderProvider.placeOrder(source: 'pos')` for cash, or a direct `orders` insert + `order_items` for GCash). **It does NOT call `SalesService.recordSale`**, so `sales_transactions` / `sales_transaction_items` are effectively **dead tables** (empty for new sales). Any revenue query still reading `sales_transactions` will report **zero POS revenue** for new stores.

---

## 2. File Map

| Layer | File | Role |
|-------|------|------|
| Service | `lib/services/sales_service.dart` | ALL revenue queries (today/weekly/monthly/trend/report). Single source of truth for the app's revenue math. |
| Model | `lib/models/sales_trend_data.dart` | `SalesDataPoint`, `SalesTrendResult`, `SalesChannelFilter` — the chart data contract. |
| Model | `lib/models/seller_report_data.dart` | `SellerReportData` — Reports screen contract (`weeklyTotal`, `previousPeriodTotal`, `dailyRevenue`, `topProducts`). |
| Widget | `lib/widgets/seller/seller_stacked_area_chart.dart` | Stacked area chart (fl_chart) used on the dashboard. Online (blue) + In-Store (amber). |
| Screen | `lib/screens/seller/seller_dashboard_screen.dart` | Consumes `getWeeklyTrend` + `getMonthlyTrend` (Block 6 & 7). |
| Screen | `lib/screens/seller/reports_screen.dart` | Consumes `getWeeklyReport` (bar chart + top products + comparison). |
| DB | `supabase/schema.sql` | `orders`, `order_items`, `sales_transactions`, `sales_transaction_items` (§10–13). |

---

## 3. Data Sources (DB)

### 3.1 Online revenue — `orders`
- Online orders are scoped to a store **indirectly**: `products.store_id` → `order_items.product_id` → `orders.id` (see `_getOrderIds` below). `orders` has a `store_id` column, but online queries deliberately go through the product chain.
- Filters used: `status != 'cancelled'` **and `payment_status = 'paid'`** (all trend queries).
- `created_at` is the time bucket key.

### 3.2 POS revenue — `orders WHERE source='pos'`
- The live POS path. POS orders carry `store_id` directly, so POS queries filter `orders.store_id = X AND source = 'pos' AND status != 'cancelled'` — **no product chain needed**.
- POS cash orders go through `OrderProvider.placeOrder(...)`; POS GCash orders are inserted directly with `payment_status='pending'` then flipped to `paid` by a poller.

### 3.3 Legacy POS — `sales_transactions` (+ `sales_transaction_items`)
- Written only by `SalesService.recordSale()`, which **no caller invokes** today. Treat as deprecated; do not build new charts on it.
- `getWeeklyReport` reads POS from the live `orders source='pos'` path (was `sales_transactions`).

---

## 4. Store→Order ID Resolution

```dart
Future<List<dynamic>> _getOrderIds(String storeId)
// products(id) WHERE store_id=X
//   → order_items(order_id) WHERE product_id IN (...)
//   → distinct order ids
```

Used by every online-revenue query. Costs **2 round trips** per call, and several trend methods call it twice (current + previous period). When optimizing the graphs, consider a single SQL query with a join instead.

---

## 5. Models

```dart
class SalesDataPoint {
  DateTime date;
  double onlineRevenue;    // online only
  double inStoreRevenue;   // POS only
  double revenue;          // combined
  int orderCount;          // ⚠️ declared but NEVER populated — always 0
  bool isProjected;        // true only for "today" if hour < 18 (partial day)
}

class SalesTrendResult {
  List<SalesDataPoint> points;
  double totalRevenue;
  double previousPeriodRevenue; // same-length window immediately before
  double percentChange;         // (total - prev) / prev * 100
  String unit;                  // defaults '₱'
  String periodLabel;           // "This Week", "Last 6 Months"
  bool hasComparison;           // previousPeriodRevenue > 0
  bool isEmpty;                 // all points zero
}

enum SalesChannelFilter { all, online, inStore }
```

---

## 6. SalesService — Revenue Methods

### 6.1 Dashboard trends (the graph you're improving)

| Method | Buckets | Channel split | Prev-period compare |
|--------|---------|---------------|---------------------|
| `getWeeklyTrend(storeId, channel)` | 7 (Mon=0…Sun=6) | ✅ online vs inStore | ✅ last 7 days |
| `getMonthlyTrend(storeId, channel, monthsBack: 6)` | 6 months | ✅ online vs inStore | ✅ prior 6 months |

Both funnel into `_fetchTrend(...)` — the shared engine:
1. **Current period** fetched in parallel: online (`_getOrderIds` + `orders` chain) and POS (`orders` with `source='pos'`).
2. **Previous period** totals fetched in parallel (same 2 queries, `total_amount` only).
3. Rows bucketed by `slotByDate` (weekday-1 or month offset), split into `onlineDaily[]` and `inStoreDaily[]`.
4. `percentChange = (total − prevTotal) / prevTotal * 100` (**0 when prev is 0**).
5. `points[i].isProjected = (i == slotCount-1 && now.hour < 18)`.

**Filters used here:** `status != 'cancelled'` **AND `payment_status = 'paid'`** — applied consistently everywhere (dashboard trends, KPI cards, monthly, Reports). This is now THE revenue definition app-wide: money actually received, excluding cancelled/unpaid/pending orders. Reports and dashboard agree.

### 6.2 Reports screen
`getWeeklyReport(storeId, {weekStart, weekEnd, monthly})` → `SellerReportData`:
- Online: orders via chain, `status != 'cancelled'`, `payment_status = 'paid'`.
- POS: `orders source='pos'`, same filters (migrated off legacy `sales_transactions`).
- `dailyRevenue` = 7 weekday slots, or days-in-month when `monthly: true`.
- Top products aggregated from `order_items` + `sales_transaction_items` (units × unit_price), sorted by units, top 5.
- `previousPeriodTotal` for the comparison chip.

### 6.3 KPI one-offs
| Method | Online source | POS source |
|--------|--------------|------------|
| `getTodayRevenue` | `getOnlineTodayRevenue` (orders chain, neq cancelled, paid) | `fetchTodaySales` (orders `source='pos'`, paid) ✅ live |
| `getWeeklyRevenue` | `getOnlineWeeklyRevenue` | `getPosWeeklyRevenue` (orders `source='pos'`, paid) ✅ live |
| `getMonthlyRevenue` | orders chain, neq cancelled, paid | `orders source='pos'`, paid ✅ live (migrated off legacy) |
| `getTotalOrderCount` / `getPendingOrderCount` | orders chain | n/a |

All KPI methods now agree: live POS path (`orders source='pos'`) + `payment_status='paid'` everywhere. The legacy `sales_transactions` inconsistency is resolved.

### 6.4 Label helpers
- `monthlyLabels()` → `['Jan', …]` (6, rolling).
- `monthlyFullLabels()` → `['February 2026', …]` (handles year rollover).

---

## 7. Chart Widget (`SellerStackedAreaChart`)

fl_chart `LineChart`, 220px tall. Layout: **header row** (title/subtitle left, pill legend right) → **headline** (28pt bold, formatted total) → **delta pill chip** → chart → **footer** (scope note only). Modern Stripe/shadcn "Area Chart Gradient Fill" style: smooth curves, soft halo glow, dashed hairline grid.

**Stacking:** Online drawn first (bottom), In-Store drawn second **on top** — `inStoreSpots[i] = (online + inStore)` so the amber area sits above the blue one. Both series use `isCurved: true, curveSmoothness: 0.35`.

- Colors: Online `0xFF2563EB` (blue-600), In-Store `0xFFD97706` (amber-600). Area fills are 3-stop gradients `0.32 → 0.14 → 0.0` alpha. Each line has a decorative halo behind it (`barWidth: 10`, alpha `0.09`).
- Y axis: `maxY = (maxPoint*1.2)` snapped **up to the next interval multiple** (`yMaxAligned` — kills overlapping top tick label), interval from a ladder (`_calculateYInterval`): ≤500→100, ≤1k→200, ≤5k→1000, ≤10k→2000, ≤50k→10k, ≤100k→20k, else 50k.
- Grid: horizontal-only, **dashed** (`dashArray: [4, 6]`), alpha `0.07` — the shadcn hairline signature.
- X axis labels: `labels` param if provided; otherwise **month abbreviations from `points[i].date`** (`_monthAbbrev`). The dashboard passes `['Mon',…,'Sun']` for the weekly chart and month labels for monthly.
- Latest-point marker: the top (in-store) series shows a white-ringed dot on its **last** point — the fintech "current value" marker.
- Touch: vertical guide line (`getTouchedSpotIndicator`) + dark tooltip (rounded 14, soft shadow) with `Online:` / `In-Store:` / `Total:` amounts.
- Delta pill (`_buildDeltaPill`): rounded tinted chip — arrow + `% up/down` in **`AppConstants.success` (olive) / `AppConstants.error` (crimson)**, plus muted "vs ₱prev last week/month" suffix. `_lowBaselineFloor = 500`: prev ≤ 0 → grey "No previous-period data" chip; prev < 500 → muted "Early days" chip (no misleading %).
- Legend: pill chips (tinted capsule + colored dot).
- Draw-in animation: 800ms `Curves.easeOutCubic` (premium vs instant).
- States: loading / error (with `onRetry`) / empty ("No sales yet this period").

**Dashboard wiring** (`seller_dashboard_screen.dart`): `_fetchDashboardData` runs `getWeeklyTrend` + `getMonthlyTrend` (both `channel: all`) inside the same `Future.wait` as the rest of the dashboard; Block 6 renders the weekly chart, Block 7 the monthly chart. Charts use cached data on refresh errors. Both chart cards use `clipBehavior: Clip.antiAlias` (prevents the y-axis bleed through the header in dark mode); dashboard AppBar is hardened with `scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent`.

---

## 8. Gotchas for AI Agents

1. **`sales_transactions` is legacy/dead.** The POS screen writes `orders source='pos'`, NOT `sales_transactions`. **All revenue queries now use the live path** — if you see a query touching `sales_transactions`, it's a regression.
2. **`SalesDataPoint.orderCount` is never populated** — a natural candidate to wire up if you add order-count annotations to the chart.
3. **Revenue definition (fixed):** every revenue query filters `status != 'cancelled'` **and `payment_status = 'paid'`** — dashboard trends, KPI cards, monthly, and Reports all agree. Note POS cash is `paid` at insert; POS GCash starts `pending` until the poller flips it (so GCash revenue appears slightly late).
4. **`_getOrderIds` = N+1-style chain (2 queries)**; trend methods run it for current AND previous periods → 4+ queries per chart load. If you optimize, prefer a single joined query and keep the store scope via `products`/`order_items`.
5. **Weekly X labels:** the dashboard passes `['Mon',…,'Sun']`; monthly passes month labels. Only if a caller omits `labels` will the chart fall back to month abbrevs from `points[i].date`.
6. **`isProjected` only marks the last slot when `now.hour < 18`** — the "today is partial" heuristic. If you add projected/forecast styling, this is the hook.
7. **POS GCash orders** are `payment_status='pending'` until polled to `paid` — they appear in revenue slightly late; cancelled-at-creation orders (`_cancelGcashPayment` deletes them) are removed.
8. **Weekly buckets are `weekday - 1` (Mon=0)**, not Sunday-start. Monthly buckets are month offsets from the window start; out-of-window rows are dropped.
9. **`percentChange` is 0 when the previous period had no revenue** — but the delta line now hides the % (shows "No previous-period data to compare", or muted "Early days" below `_lowBaselineFloor = 500`) instead of rendering "0%".
10. **Dashboard KPI cards and the charts** compute revenue from the same method family (`getTodayRevenue`/`getWeeklyRevenue`/`getMonthlyRevenue` vs `getWeeklyTrend`/`getMonthlyTrend`), all using the paid filter; keep them consistent when you change the definition.
