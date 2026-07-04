# SoleVision — Changelog

## Session 2: Seller Dashboard Real Data + Users Redesign + Login Freeze Fix

### Reports Screen — Replace Mock Data with Real Supabase Data
- **`lib/models/seller_report_data.dart`** — New data class: `SellerReportData` with `weeklyTotal`, `dailyRevenue` (7 doubles, Mon=0 Sun=6), `topProducts` list, `weekStart`/`weekEnd`.
- **`lib/services/sales_service.dart`** — Added `getWeeklyReport(storeId)` that fetches online orders (filtered by `status != 'cancelled'` AND `payment_status = 'paid'`) + POS transactions, aggregates daily revenue by weekday, aggregates top products from `order_items` + `sales_transaction_items`, fetches product names. All queries use the 3-step products→order_items→orders pattern.
- **`lib/screens/seller/reports_screen.dart`** — Full rewrite from `StatelessWidget` to `StatefulWidget` with `FutureBuilder`. Added shimmer loading skeleton, `ErrorRetryWidget` on failure, pull-to-refresh, real top products list with rank badges and revenue formatting, CSV export stub with snackbar, empty state for zero-sales weeks.
- **Period selector toggle** — Added `This Week` / `This Month` segmented chip toggle to the reports screen. `getWeeklyReport` accepts a `monthly` flag that aggregates revenue by day-of-month (28-31 bars) instead of weekday (7 bars). Bar labels dynamically switch to day numbers for monthly view. Date label shows full month name + year (e.g., "June 2026") for monthly. `SellerWeeklyBar` accepts an optional `todayIndex` parameter.
- **Revenue comparison card** — Added week-over-week / month-over-month percentage change indicator below the total revenue. `SellerReportData` now includes `previousPeriodTotal` and a `percentChange` getter. The service fetches the previous period's online + POS revenue in parallel with the current period. UI shows an up/down arrow with colored percentage (green for positive, red for negative) and context label ("vs last week" / "vs last month"). Hidden when previous period has no data.

### Seller Dashboard — Monthly Revenue Trend Chart
- **`lib/services/sales_service.dart`** — Added `getMonthlyRevenueTrend(storeId)` that fetches online orders + POS transactions for the past 6 months, aggregates by month index. Added static `monthlyLabels()` that generates abbreviated month labels.
- **`lib/screens/seller/seller_dashboard_screen.dart`** — Added `monthlySalesChart` to `_DashboardData`, fetched via `Future.wait`, rendered as a `SellerWeeklyBar` chart below the weekly bar chart.

### Seller Dashboard — Optimize getRecentOrders Query
- **`lib/services/order_service.dart`** — Added `limit` parameter to `_getOrderIdsForStore` helper. The database now applies `.limit()` after `.order()` so only N order IDs are fetched instead of all IDs + Dart slicing. `getRecentOrders` passes `limit` through to the helper.

### Seller Dashboard — Pull-to-Refresh Fix
- **`lib/screens/seller/seller_dashboard_screen.dart`** — Added `_cachedData` field to preserve last-loaded data. FutureBuilder now only shows the shimmer skeleton on initial load; on pull-to-refresh, existing data stays visible while the spinner animates. Error during refresh silently falls back to cached data instead of replacing the UI.

### Seller Dashboard — Replace Mock Data with Real Supabase Data
- **`lib/services/sales_service.dart`** — Extended with: `getOnlineTodayRevenue`, `getTodayRevenue` (online + POS), `getOnlineWeeklySales`, `getWeeklyRevenue` (7-day weekday aggregation combining online + POS), `getMonthlyRevenue`, `getTotalOrderCount`, `getPendingOrderCount`. Product/order lookups use a products→order_items chain to avoid PostgREST join syntax issues.
- **`lib/services/order_service.dart`** — Extended with: `getRecentOrders` (customer name + product name via separate queries), `getOrderCountByStatus`, `fetchStoreOrders` rewritten to filter server-side instead of fetching all orders. Added `SupabaseClient` constructor parameter.
- **`lib/screens/seller/seller_dashboard_screen.dart`** — Full rewrite: `FutureBuilder` pattern with `_DashboardData` model, shimmer loading skeleton, `ErrorRetryWidget` on failure, pull-to-refresh, order status summary section (placed/preparing/ready/received), store rating in today's sales subtitle, real weekly bar chart data, correct status transitions (placed→preparing→ready→received), `_emptyDashboard()` fallback for unmounted widgets, `mounted` check after async operations, removed dead `weeklyRevenue`/`totalOrders` fields.

### Users Page Redesign
- **`lib/hooks/useUsers.js`** — Rewritten to remove `suspended` column, return `{ all, customers, sellers, admins }` grouped by role.
- **`lib/pages/Users.jsx`** — Full rewrite with role-separated tab layout (All/Customers/Sellers/Admins), stats chips, real-time search, side-by-side sections.
- **`lib/components/users/UserRow.jsx`** — Individual user row with deterministic avatar colors, hover actions.
- **`lib/components/users/UserSection.jsx`** — Role-colored section container with icon and count.
- **`lib/components/users/UserDetailModal.jsx`** — Role-colored header, info grid, role change buttons.

### Admin Products Page Cleanup
- **`admin-portal/src/pages/Products.jsx`** — Removed duplicate heading/subtitle/Add Product button, cleaned up dead code.
- **`admin-portal/src/components/products/StoreGroup.jsx`** — Enlarged banner from h-40 to h-64, added store rating chip, larger logo, improved gradient.
- **`admin-portal/src/hooks/useProducts.js`** — Added `rating` to store query, removed dead `allStores`.

### Login Freeze Fix
- **`lib/providers/auth_provider.dart`** — `logout()` clears all state + biometric credentials before signOut. `login()` clears stale `_currentUser`/`_profile` at start, uses try/catch/finally to guarantee `_isLoading` resets. `signUp()` also upgraded to finally pattern.
- **`lib/services/auth_service.dart`** — Removed pre-signOut in `signIn()` to avoid auth stream race condition.
- **`lib/screens/auth_gate.dart`** — Added `_resetProfileCache()` to clear stale profile when auth stream emits null user.
- **`lib/screens/auth/login_screen.dart`** — `_submit()` cleaned up with early returns, `mounted` guard, proper `Future<void>` return type.
