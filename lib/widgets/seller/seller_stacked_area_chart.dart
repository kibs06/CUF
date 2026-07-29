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

  // Chart colors matching shadcn/ui design tokens
  static const Color _onlineColor = Color(0xFF2563EB);   // blue-600
  static const Color _inStoreColor = Color(0xFFD97706);  // amber-600

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _buildHeader(),
        const SizedBox(height: 16),
        // Chart content
        _buildChartContent(),
        const SizedBox(height: 12),
        // Footer with trend
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
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
    final yMax = maxY > 0 ? maxY * 1.2 : 100.0;
    final yInterval = _calculateYInterval(yMax);

    // Build stacked spots: online on bottom, inStore on top
    final onlineSpots = <FlSpot>[];
    final inStoreSpots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      final x = i.toDouble();
      onlineSpots.add(FlSpot(x, points[i].onlineRevenue));
      // Stack: inStore sits on top of online
      inStoreSpots.add(FlSpot(x, points[i].onlineRevenue + points[i].inStoreRevenue));
    }

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
                color: Colors.grey.withValues(alpha: 0.1),
                strokeWidth: 1,
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
                          color: Colors.grey.shade600,
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
                          color: Colors.grey.shade500,
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
            maxY: yMax,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppConstants.secondary,
                tooltipRoundedRadius: 12,
                tooltipPadding: const EdgeInsets.all(12),
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
            ),
            lineBarsData: [
              // In-Store area (on top, drawn second for correct stacking)
              LineChartBarData(
                spots: inStoreSpots,
                isCurved: false,
                color: _inStoreColor,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _inStoreColor.withValues(alpha: 0.4),
                      _inStoreColor.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
              // Online area (on bottom, drawn first)
              LineChartBarData(
                spots: onlineSpots,
                isCurved: false,
                color: _onlineColor,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _onlineColor.withValues(alpha: 0.4),
                      _onlineColor.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trend line
        if (trendResult != null && trendResult!.hasComparison)
          _buildTrendLine(trendResult!),
        if (trendResult != null && trendResult!.hasComparison)
          const SizedBox(height: 6),
        // Scope subtitle
        Text(
          'Combined online + in-store revenue',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 8),
        // Legend
        _buildLegend(),
      ],
    );
  }

  Widget _buildTrendLine(SalesTrendResult trend) {
    final change = trend.percentChange;
    final isUp = change >= 0;
    final icon = isUp ? Icons.trending_up : Icons.trending_down;
    final color = isUp ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final label = isWeekly ? 'this week' : 'this month';

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          'Trending ${isUp ? "up" : "down"} by ${change.abs().toStringAsFixed(1)}% $label',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendItem(_onlineColor, 'Online'),
        const SizedBox(width: 16),
        _legendItem(_inStoreColor, 'In-Store'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
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
