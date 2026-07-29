/// A single point on any trend chart — carries both channel-separated and combined revenue.
class SalesDataPoint {
  final DateTime date;
  final double onlineRevenue;   // online orders only
  final double inStoreRevenue;  // POS / in-person sales only
  final double revenue;         // combined: online + inStore
  final int orderCount; // combined count
  final bool isProjected; // true only for "today" if day is incomplete

  const SalesDataPoint({
    required this.date,
    this.onlineRevenue = 0,
    this.inStoreRevenue = 0,
    this.revenue = 0,
    this.orderCount = 0,
    this.isProjected = false,
  });
}

/// The result of a trend query — includes data points, totals, and comparison.
class SalesTrendResult {
  final List<SalesDataPoint> points;
  final double totalRevenue;
  final double previousPeriodRevenue; // same length window, immediately prior
  final double percentChange; // (total - previous) / previous * 100
  final String unit; // "PHP" — pass explicitly, never assume
  final String periodLabel; // e.g., "This Week", "Last 6 Months"

  const SalesTrendResult({
    required this.points,
    required this.totalRevenue,
    required this.previousPeriodRevenue,
    required this.percentChange,
    this.unit = '₱',
    this.periodLabel = '',
  });

  /// Whether we have valid previous period data for comparison.
  bool get hasComparison => previousPeriodRevenue > 0;

  /// Whether the entire window has zero revenue.
  bool get isEmpty => points.every((p) => p.revenue == 0);
}

/// Channel filter for chart data.
enum SalesChannelFilter { all, online, inStore }
