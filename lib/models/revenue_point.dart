/// A single data point for revenue charts.
/// Shared by both weekly and monthly line charts.
class RevenuePoint {
  final String label;
  final double revenue;
  /// Optional richer label shown in the tooltip (e.g. "July 2026").
  /// Falls back to [label] when null.
  final String? tooltipLabel;

  const RevenuePoint({
    required this.label,
    required this.revenue,
    this.tooltipLabel,
  });
}
