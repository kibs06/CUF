import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants/app_constants.dart';
import '../../models/sales_trend_data.dart';

/// Stacked area chart for revenue data, showing Online vs In-Store channels.
/// Matches shadcn/ui + Recharts stacked area chart visual pattern.
class SellerStackedAreaChart extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SalesDataPoint> points;
  final List<String>? labels; // Optional labels for X-axis (e.g., ['Mon', 'Tue', ...])
  final SalesTrendResult? trendResult;
  final bool isWeekly;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const SellerStackedAreaChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.points,
    this.trendResult,
    this.isWeekly = true,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.labels,
  });

  // Chart colors matching shadcn/ui design tokens. Public so other
  // revenue visuals (e.g. the doughnut card) reuse the same channel colors.
  static const Color onlineColor = Color(0xFF2563EB);   // blue-600
  static const Color inStoreColor = Color(0xFFD97706);  // amber-600

  // Delta uses the app's brand success/error (olive / crimson) so the
  // growth chip reads as part of the product, not a generic material color.
  static const double _lowBaselineFloor = 500;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: title + legend, then headline number + delta line
        _buildHeader(),
        const SizedBox(height: 16),
        // Chart content
        _buildChartContent(),
        const SizedBox(height: 12),
        // Footer: scope note only (trend lives under the headline)
        Text(
          'Combined online + in-store revenue',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppConstants.bodyStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildLegend(),
          ],
        ),
        if (trendResult != null) ...[
          const SizedBox(height: 14),
          // Headline number — the key figure at a glance
          Text(
            _formatCurrency(trendResult!.totalRevenue),
            style: AppConstants.headlineStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 2),
          _buildDeltaLine(trendResult!),
        ],
      ],
    );
  }

  /// Delta chip directly beneath the headline. Softens low-sample
  /// baselines so a tiny/no prior period doesn't read as a crisis.
  Widget _buildDeltaLine(SalesTrendResult trend) {
    final prev = trend.previousPeriodRevenue;
    final total = trend.totalRevenue;

    if (prev <= 0) {
      return _buildDeltaPill(
        icon: Icons.remove,
        iconColor: Colors.grey.shade400,
        text: 'No previous-period data',
        textColor: Colors.grey.shade500,
      );
    }

    // Low baseline (e.g. a brand-new store or first week): the swing is
    // noise, not signal — muted styling, no red "-100%" alarm.
    if (prev < _lowBaselineFloor) {
      return _buildDeltaPill(
        icon: Icons.auto_graph,
        iconColor: Colors.grey.shade400,
        text: total <= 0
            ? 'No orders yet this period'
            : 'Early days — trend will firm up',
        textColor: Colors.grey.shade500,
      );
    }

    final change = trend.percentChange;
    final isUp = change >= 0;
    final color = isUp ? AppConstants.success : AppConstants.error;
    final arrow = isUp ? Icons.arrow_upward : Icons.arrow_downward;
    final periodWord = isWeekly ? 'last week' : 'last month';

    return _buildDeltaPill(
      icon: arrow,
      iconColor: color,
      text: '${change.abs().toStringAsFixed(1)}% ${isUp ? "up" : "down"}',
      textColor: color,
      suffix: 'vs ${_formatCurrency(prev)} $periodWord',
      tint: color,
    );
  }

  /// Rounded, tinted "chip" pill — the signature modern-dashboard element.
  Widget _buildDeltaPill({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    String? suffix,
    Color? tint,
  }) {
    final base = tint ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppConstants.bodyStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(
              suffix,
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartContent() {
    if (isLoading) return _buildLoadingState();
    if (error != null) return _buildErrorState();
    if (points.isEmpty || points.every((p) => p.revenue == 0)) {
      return _buildEmptyState();
    }
    return _buildChart();
  }

  Widget _buildChart() {
    final maxY = points.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    final yInterval = _calculateYInterval(maxY > 0 ? maxY * 1.2 : 100.0);
    // Snap the top of the axis UP to an exact multiple of the interval so
    // every tick sits on a ladder rung. Without this, fl_chart also labels
    // the (non-aligned) maxY, squeezing two labels together at the top
    // (the "₱10.0k rendered twice" overlap).
    final yMax = (maxY > 0 ? maxY * 1.2 : 100.0) / yInterval;
    final yMaxAligned = (yMax.ceil() * yInterval).toDouble();

    // Build stacked spots: online on bottom, inStore on top
    final onlineSpots = <FlSpot>[];
    final inStoreSpots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      final x = i.toDouble();
      onlineSpots.add(FlSpot(x, points[i].onlineRevenue));
      // Stack: inStore sits on top of online
      inStoreSpots.add(FlSpot(x, points[i].onlineRevenue + points[i].inStoreRevenue));
    }

    // Soft halo behind each line (Linear-style glow). Drawn first so the
    // areas/lines render on top of it. Purely decorative.
    LineChartBarData glowBar(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      color: color.withValues(alpha: 0.09),
      barWidth: 10,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
    );

    return SizedBox(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.only(left: 48, right: 16, top: 8, bottom: 24),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yInterval,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.withValues(alpha: 0.07),
                strokeWidth: 1,
                // Hairline dashed grid — shadcn modern-dashboard signature
                dashArray: [4, 6],
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              // Y-axis: real currency values
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: yInterval,
                  getTitlesWidget: (value, meta) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        _formatCurrencyShort(value),
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    );
                  },
                ),
              ),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              // X-axis: show every label (use provided labels or generate from date)
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= points.length) return const SizedBox();
                    final label = (labels != null && idx < labels!.length)
                        ? labels![idx]
                        : _monthAbbrev(points[idx].date);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        label,
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            minY: 0,
            maxY: yMaxAligned,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppConstants.secondary,
                tooltipRoundedRadius: 14,
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                maxContentWidth: 200,
                tooltipBorder: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                getTooltipItems: (touchedSpots) {
                  if (touchedSpots.isEmpty) return [];
                  final idx = touchedSpots.first.x.toInt();
                  if (idx < 0 || idx >= points.length) return [];
                  final point = points[idx];
                  final dateLabel = _formatDateLabel(point.date);

                  return [
                    LineTooltipItem(
                      '$dateLabel\n',
                      TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withAlpha(230),
                      ),
                      children: [
                        TextSpan(
                          text: 'Online: ',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            color: Colors.white.withAlpha(200),
                          ),
                        ),
                        TextSpan(
                          text: _formatCurrency(point.onlineRevenue),
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const TextSpan(text: '\n'),
                        TextSpan(
                          text: 'In-Store: ',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            color: Colors.white.withAlpha(200),
                          ),
                        ),
                        TextSpan(
                          text: _formatCurrency(point.inStoreRevenue),
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const TextSpan(text: '\n'),
                        TextSpan(
                          text: 'Total: ',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            color: Colors.white.withAlpha(200),
                          ),
                        ),
                        TextSpan(
                          text: _formatCurrency(point.revenue),
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ];
                },
              ),
              handleBuiltInTouches: true,
              touchSpotThreshold: 20,
              // Stripe-style vertical guide line on touch — the tooltip
              // carries the values, so no per-point dots are needed.
              getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
                  .map((index) => TouchedSpotIndicatorData(
                        const FlLine(color: Color(0x2E3B2314), strokeWidth: 1),
                        FlDotData(show: false),
                      ))
                  .toList(),
            ),
            lineBarsData: [
              // Glow halos (behind everything)
              glowBar(inStoreSpots, inStoreColor),
              glowBar(onlineSpots, onlineColor),
              // In-Store area (stacked on top: its spots already include online)
              LineChartBarData(
                spots: inStoreSpots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: inStoreColor,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    // Emphasize the latest data point — the fintech
                    // "current" marker on the most recent value.
                    if (index != points.length - 1) {
                      return FlDotCirclePainter(
                        color: Colors.transparent,
                        radius: 0,
                      );
                    }
                    return FlDotCirclePainter(
                      color: inStoreColor,
                      radius: 4,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      inStoreColor.withValues(alpha: 0.32),
                      inStoreColor.withValues(alpha: 0.14),
                      inStoreColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              // Online area (bottom)
              LineChartBarData(
                spots: onlineSpots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: onlineColor,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      onlineColor.withValues(alpha: 0.32),
                      onlineColor.withValues(alpha: 0.14),
                      onlineColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Slow, deliberate draw-in — feels premium vs an instant pop-in.
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendItem(onlineColor, 'Online'),
        const SizedBox(width: 8),
        _legendItem(inStoreColor, 'In-Store'),
      ],
    );
  }

  /// Pill-style legend chips (tinted capsule with a colored dot).
  Widget _legendItem(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading chart data...',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              'Failed to load chart data',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: AppConstants.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 32, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              'No sales yet this period',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sales will appear here once you make a sale',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────

  double _calculateYInterval(double maxY) {
    if (maxY <= 0) return 100;
    if (maxY <= 500) return 100;
    if (maxY <= 1000) return 200;
    if (maxY <= 5000) return 1000;
    if (maxY <= 10000) return 2000;
    if (maxY <= 50000) return 10000;
    if (maxY <= 100000) return 20000;
    return 50000;
  }

  String _formatCurrency(double amount) {
    final whole = amount.floor();
    final formatted = whole.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '₱$formatted';
  }

  String _formatCurrencyShort(double amount) {
    if (amount >= 1000000) return '₱${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '₱${(amount / 1000).toStringAsFixed(1)}k';
    return '₱${amount.floor()}';
  }

  String _formatDateLabel(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _monthAbbrev(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[date.month - 1];
  }
}
