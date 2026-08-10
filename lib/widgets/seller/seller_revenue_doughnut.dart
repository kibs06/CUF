import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/sales_trend_data.dart';
import 'seller_stacked_area_chart.dart';

/// Revenue breakdown doughnut (fl_chart `PieChart`) — "how is this period's
/// revenue split between online and in-store."
///
/// Complements — never replaces — the monthly trend line chart: the trend
/// answers "how did revenue move over the last 6 months," this answers "how
/// is the current month split." Reuses the same data already fetched for the
/// trend chart (`SalesTrendResult.points.last`) so both cards always agree.
class SellerRevenueDoughnutChart extends StatelessWidget {
  final String title;
  final String periodLabel;
  final SalesTrendResult? trendResult;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const SellerRevenueDoughnutChart({
    super.key,
    required this.title,
    required this.periodLabel,
    this.trendResult,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  // Same low-baseline floor as the trend chart's delta pill — a tiny/no
  // prior period shouldn't render as a stark red "% down" claim.
  static const double _lowBaselineFloor = 500;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildChartContent(),
        if (trendResult != null && _hasData) ...[
          const SizedBox(height: 12),
          _buildLegendRows(),
          const SizedBox(height: 12),
          _buildTrendFooter(trendResult!),
        ],
      ],
    );
  }

  bool get _hasData {
    final points = trendResult?.points ?? [];
    return points.isNotEmpty && points.last.revenue > 0;
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          periodLabel,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: SellerTheme.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: AppConstants.bodyStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ─── Chart content: loading / error / empty / doughnut ──────────
  Widget _buildChartContent() {
    if (isLoading) return _buildLoadingState();
    if (error != null) return _buildErrorState();
    if (!_hasData) return _buildEmptyState();
    final last = trendResult!.points.last;
    return _buildDoughnut(last.onlineRevenue, last.inStoreRevenue);
  }

  Widget _buildDoughnut(double online, double inStore) {
    final total = online + inStore;
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 64,
              startDegreeOffset: -90,
              sections: [
                PieChartSectionData(
                  value: online,
                  color: SellerStackedAreaChart.onlineColor,
                  showTitle: false,
                ),
                PieChartSectionData(
                  value: inStore,
                  color: SellerStackedAreaChart.inStoreColor,
                  showTitle: false,
                ),
              ],
            ),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatCurrencyShort(total),
                style: AppConstants.monoStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'this month',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: SellerTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Legend rows: channel · amount + percent ────────────────────
  Widget _buildLegendRows() {
    final last = trendResult!.points.last;
    final total = last.revenue;
    return Column(
      children: [
        _legendRow(
          color: SellerStackedAreaChart.onlineColor,
          label: 'online',
          amount: last.onlineRevenue,
          total: total,
        ),
        const SizedBox(height: 8),
        _legendRow(
          color: SellerStackedAreaChart.inStoreColor,
          label: 'in-store',
          amount: last.inStoreRevenue,
          total: total,
        ),
      ],
    );
  }

  Widget _legendRow({
    required Color color,
    required String label,
    required double amount,
    required double total,
  }) {
    final percent = total > 0 ? (amount / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SellerTheme.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          _formatCurrency(amount),
          style: AppConstants.monoStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· $percent%',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: SellerTheme.textMuted,
          ),
        ),
      ],
    );
  }

  // ─── Trend footer — mirrors SellerStackedAreaChart's delta logic ─
  Widget _buildTrendFooter(SalesTrendResult trend) {
    final prev = trend.previousPeriodRevenue;
    final total = trend.totalRevenue;

    if (prev <= 0) {
      return _buildFooterRow(
        icon: Icons.remove,
        iconColor: SellerTheme.textMuted,
        text: 'No previous-period data',
        textColor: SellerTheme.textMuted,
      );
    }

    // Low baseline (new store / first month): the swing is noise, not signal.
    if (prev < _lowBaselineFloor) {
      return _buildFooterRow(
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
    return _buildFooterRow(
      icon: isUp ? Icons.arrow_upward : Icons.arrow_downward,
      iconColor: color,
      text: '${change.abs().toStringAsFixed(1)}% ${isUp ? "up" : "down"}',
      textColor: color,
      suffix: 'vs ${_formatCurrency(prev)} last month',
    );
  }

  Widget _buildFooterRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    String? suffix,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
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

  // ─── States ─────────────────────────────────────────────────────
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
      height: 200,
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
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Neutral gray placeholder ring — reads as an empty doughnut,
            // not a fully-colored circle implying "100% of nothing."
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No sales yet this period',
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

  // ─── Helpers ────────────────────────────────────────────────────
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
}
