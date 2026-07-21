import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants/app_constants.dart';
import '../../models/revenue_point.dart';

/// Line chart widget for weekly and monthly revenue data.
/// Uses fl_chart with smooth curves, gradient fill, and tap tooltips.
class SellerRevenueLineChart extends StatelessWidget {
  final List<RevenuePoint> data;
  final bool isWeekly;

  const SellerRevenueLineChart({
    super.key,
    required this.data,
    this.isWeekly = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((p) => p.revenue == 0)) {
      return _buildEmptyState();
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].revenue));
    }

    final maxY = data.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    final yMax = maxY > 0 ? maxY * 1.2 : 100.0;

    return SizedBox(
      height: 180,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 16, top: 8, bottom: 4),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yMax / 3,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.withValues(alpha: 0.12),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
                    // Show every label for weekly (7 items), skip some for monthly (6 items)
                    if (!isWeekly && idx % 2 != 0 && idx != data.length - 1) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        data[idx].label,
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
                        fontFamily: 'JetBrainsMono',
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
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppConstants.primary,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    // Only show dot on the last point (current day/month)
                    final isLast = index == spots.length - 1;
                    if (!isLast) return FlDotCirclePainter(
                      radius: 0,
                      color: Colors.transparent,
                    );
                    return FlDotCirclePainter(
                      radius: 5,
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
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 180,
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
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    final whole = amount.floor();
    final formatted = whole.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '₱$formatted';
  }
}
