import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/sales_trend_data.dart';

/// Revenue trend as **stacked columns** — one column per bucket (a weekday on
/// the weekly card, a month on the monthly one), each column being the two
/// channels stacked: online at its base, in-store on top.
///
/// This replaces the old stacked *area* card, which told the same story with
/// two translucent bands and a line through each. Reading it meant judging the
/// gap between two curves and guessing where the upper band started, and the
/// two fills blended into brown wherever in-store was small. Columns turn both
/// questions into lengths: the column's height is the period's total, the
/// column is one flat colour per channel stacked bottom-up, and no two channels
/// ever overlap.
///
/// The card around the plot is unchanged — same title/legend row, headline
/// figure, delta pill, states and scope footer — because the dashboard's Blocks
/// 5 and 6 are the only callers and they pass the same contract.
class SellerRevenueColumnsChart extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SalesDataPoint> points;
  final List<String>? labels; // Optional labels for X-axis (e.g., ['Mon', 'Tue', ...])
  final SalesTrendResult? trendResult;
  final bool isWeekly;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const SellerRevenueColumnsChart({
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

  // Colours come from the theme, not from here: the doughnut splits the same
  // two channels and both cards have to agree about which one is rust.
  static const Color onlineColor = SellerTheme.channelOnline;
  static const Color inStoreColor = SellerTheme.channelInStore;

  /// Delta uses the app's brand success/error (olive / crimson) so the
  /// growth chip reads as part of the product, not a generic material color.
  static const double _lowBaselineFloor = 500;

  /// Sizing, shared by the plot and the space reserved for it in the states
  /// below, so the card never changes height as data arrives. The rod width is
  /// a fraction of the bucket's own cell (see `_buildChart`) rather than this
  /// figure, so a two-month window draws columns instead of slabs.
  static const double _plotHeight = 220;
  static const double _barMaxWidth = 26;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildChartContent(),
        const SizedBox(height: 12),
        Text(
          'Combined online + in-store revenue',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: SellerTheme.textMuted,
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
                      color: SellerTheme.textMuted,
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
            style: AppConstants.monoStyle(
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
        iconColor: SellerTheme.textMuted,
        text: 'No previous-period data',
        textColor: SellerTheme.textMuted,
      );
    }

    // Low baseline (e.g. a brand-new store or first week): the swing is
    // noise, not signal — muted styling, no red "-100%" alarm.
    if (prev < _lowBaselineFloor) {
      return _buildDeltaPill(
        icon: Icons.auto_graph,
        iconColor: SellerTheme.textMuted,
        text: total <= 0
            ? 'No orders yet this period'
            : 'Early days — trend will firm up',
        textColor: SellerTheme.textMuted,
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
                color: SellerTheme.textMuted,
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
    final peak = points.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    final headroom = peak > 0 ? peak * 1.2 : 100.0;
    final yInterval = _calculateYInterval(headroom);
    // Snap the top of the axis UP to an exact multiple of the interval so
    // every tick sits on a ladder rung. Without this, fl_chart also labels
    // the (non-aligned) maxY, squeezing two labels together at the top
    // (the "₱10.0k rendered twice" overlap).
    final yMaxAligned = (headroom / yInterval).ceil() * yInterval;

    return SizedBox(
      height: _plotHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 48, right: 16, top: 8, bottom: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // `spaceAround` divides the plot into one cell per bucket, so the
            // column width is a fraction of that cell — capped, or a two-month
            // window would draw slabs instead of columns.
            final cellWidth = constraints.maxWidth / points.length;
            final barWidth = (cellWidth * 0.5).clamp(4.0, _barMaxWidth);

            return BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: yMaxAligned,
                gridData: _gridData(yInterval),
                titlesData: _titlesData(yInterval),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppConstants.secondary,
                    tooltipRoundedRadius: 14,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    maxContentWidth: 200,
                    tooltipBorder: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    // One rod per column, so this is called once for the
                    // touched bucket — no need for the line chart's
                    // null-padding, which existed because a touch between two
                    // stacked *lines* catches both series.
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final idx = group.x;
                      if (idx < 0 || idx >= points.length) return null;
                      final point = points[idx];
                      return BarTooltipItem(
                        '${_formatDateLabel(point.date)}\n',
                        TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withAlpha(230),
                        ),
                        children: [
                          _tooltipRow('Online', point.onlineRevenue),
                          _tooltipRow('In-Store', point.inStoreRevenue),
                          _tooltipRow('Total', point.revenue),
                        ],
                      );
                    },
                  ),
                ),
                // One column per bucket: the two channels are *segments* of
                // the same rod (`rodStackItems`), not two rods side by side —
                // that is what makes the column's height the period's total.
                barGroups: [
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 0,
                      barRods: [
                        BarChartRodData(
                          toY: points[i].revenue,
                          width: barWidth,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          rodStackItems: [
                            BarChartRodStackItem(
                              0,
                              points[i].onlineRevenue,
                              onlineColor,
                            ),
                            BarChartRodStackItem(
                              points[i].onlineRevenue,
                              points[i].revenue,
                              inStoreColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
              // Slow, deliberate draw-in — feels premium vs an instant pop-in.
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
            );
          },
        ),
      ),
    );
  }

  FlGridData _gridData(double interval) => FlGridData(
    show: true,
    drawVerticalLine: false,
    horizontalInterval: interval,
    getDrawingHorizontalLine: (value) => FlLine(
      color: Colors.grey.withValues(alpha: 0.07),
      strokeWidth: 1,
      // Hairline dashed grid — shadcn modern-dashboard signature
      dashArray: [4, 6],
    ),
  );

  FlTitlesData _titlesData(double interval) => FlTitlesData(
    show: true,
    // Y-axis: real currency values
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 44,
        interval: interval,
        getTitlesWidget: (value, meta) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            _formatCurrencyShort(value),
            style: AppConstants.bodyStyle(
              fontSize: 10,
              color: SellerTheme.textMuted,
            ),
          ),
        ),
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
                color: SellerTheme.textMuted,
              ),
            ),
          );
        },
      ),
    ),
  );

  TextSpan _tooltipRow(String label, double value) => TextSpan(
    children: [
      TextSpan(
        text: '$label: ',
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          color: Colors.white.withAlpha(200),
        ),
      ),
      TextSpan(
        text: _formatCurrency(value),
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const TextSpan(text: '\n'),
    ],
  );

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
              color: SellerTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: _plotHeight,
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
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: SellerTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SizedBox(
      height: _plotHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              'Failed to load chart data',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: SellerTheme.textMuted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  'Retry',
                  style: AppConstants.bodyStyle(
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
      height: _plotHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 32, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              'No sales yet this period',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: SellerTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sales will appear here once you make a sale',
              style: AppConstants.bodyStyle(
                fontSize: 10,
                color: SellerTheme.textMuted,
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _monthAbbrev(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[date.month - 1];
  }
}
