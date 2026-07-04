/// Holds all report data for the seller reports screen.
class SellerReportData {
  final double weeklyTotal;
  final double previousPeriodTotal;
  final List<double> dailyRevenue; // length 7 (Mon=0 Sun=6) or days-in-month
  final List<Map<String, dynamic>> topProducts; // [{name, units, revenue}]
  final DateTime weekStart;
  final DateTime weekEnd;

  const SellerReportData({
    required this.weeklyTotal,
    required this.previousPeriodTotal,
    required this.dailyRevenue,
    required this.topProducts,
    required this.weekStart,
    required this.weekEnd,
  });

  /// Percentage change from previous period. Returns null if previous was 0.
  double? get percentChange {
    if (previousPeriodTotal == 0) return null;
    return ((weeklyTotal - previousPeriodTotal) / previousPeriodTotal) * 100;
  }
}
