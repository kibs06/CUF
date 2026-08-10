import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/revenue_point.dart';
import '../../models/sales_trend_data.dart';

/// Line chart widget for weekly and monthly revenue data.
/// Uses fl_chart with linear segments, Y-axis labels, tappable dots, and comparison pill.
class SellerRevenueLineChart extends StatelessWidget {
  final List<RevenuePoint> data;
  final bool isWeekly;
  final SalesTrendResult? trendResult;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const SellerRevenueLineChart({
    super.key,
    required this.data,
    this.isWeekly = true,
    this.trendResult,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (isLoading) {
      return _buildLoadingState();
    }

    // Error state
    if (error != null) {
      return _buildErrorState();
    }

    // Empty state
    if (data.isEmpty || data.every((p) => p.revenue == 0)) {
      return _buildEmptyState();
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].revenue));
    }

    final maxY = data.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    final yMax = maxY > 0 ? maxY * 1.2 : 100.0;

    // Round Y-axis values to clean increments
    final yInterval = _calculateYInterval(yMax);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Comparison pill
        if (trendResult != null && trendResult!.hasComparison)
          _buildComparisonPill(trendResult!),
        if (trendResult != null && trendResult!.hasComparison)
          const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 4),
            child: Semantics(
              label: _buildAccessibilityLabel(data, trendResult),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.12),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              _formatCurrencyShort(value),
                              style: AppConstants.bodyStyle(
                                fontSize: 9,
                                color: SellerTheme.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= data.length) return const SizedBox();
                          // Show every label for weekly and monthly
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              data[idx].label,
                              style: AppConstants.bodyStyle(
                                fontSize: 10,
                                color: SellerTheme.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (data.length - 1).toDouble(),
                  minY: 0,
                  maxY: yMax,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => AppConstants.secondary,
                      tooltipRoundedRadius: 10,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final idx = spot.x.toInt();
                          final label = idx < data.length
                              ? (data[idx].tooltipLabel ?? data[idx].label)
                              : '';
                          final formatted = _formatCurrency(spot.y);
                          return LineTooltipItem(
                            '$formatted\n',
                            const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            children: [
                              TextSpan(
                                text: label,
                                style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 10,
                                  color: Colors.white.withAlpha(180),
                                ),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                    touchSpotThreshold: 20,
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false, // Linear segments instead of heavy spline
                      color: AppConstants.primary,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: AppConstants.primary,
                            strokeColor: Colors.white,
                            strokeWidth: 2,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppConstants.primary.withValues(alpha: 0.25),
                            AppConstants.primary.withValues(alpha: 0.02),
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
          ),
        ),
      ],
    );
  }

  /// Build comparison pill showing percent change vs previous period.
  Widget _buildComparisonPill(SalesTrendResult trend) {
    final change = trend.percentChange;
    final isUp = change >= 0;
    final color = isUp ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final label = isWeekly ? 'vs last week' : 'vs last month';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${change.abs().toStringAsFixed(1)}%',
            style: AppConstants.monoStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: SellerTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Build accessibility label for screen readers.
  String _buildAccessibilityLabel(List<RevenuePoint> data, SalesTrendResult? trend) {
    final buffer = StringBuffer('Revenue chart. ');
    for (int i = 0; i < data.length; i++) {
      buffer.write('${data[i].label}: ${_formatCurrency(data[i].revenue)}. ');
    }
    if (trend != null && trend.hasComparison) {
      final direction = trend.percentChange >= 0 ? 'up' : 'down';
      buffer.write('Total ${_formatCurrency(trend.totalRevenue)}, '
          '$direction ${trend.percentChange.abs().toStringAsFixed(1)}% from previous period.');
    }
    return buffer.toString();
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: 200,
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
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 32,
              color: Colors.red.shade300,
            ),
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
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart,
              size: 32,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              isWeekly ? 'No sales this week' : 'No sales trend yet',
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

  /// Calculate clean Y-axis interval based on max value.
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
    if (amount >= 1000000) {
      return '₱${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '₱${(amount / 1000).toStringAsFixed(1)}k';
    }
    return '₱${amount.floor()}';
  }
}
