import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/sales_trend_data.dart';
import '../../models/seller_report_data.dart';
import '../../services/sales_service.dart';
import '../../services/store_service.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/seller/seller_revenue_columns_chart.dart';
import '../../widgets/seller/seller_revenue_doughnut.dart';
import '../../widgets/seller/seller_weekly_bar.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<SellerReportData> _reportFuture;
  late Future<SalesTrendResult> _weeklyTrendFuture;
  late Future<SalesTrendResult> _monthlyTrendFuture;
  String? _storeId;
  bool _isMonthly = false;
  bool _isExporting = false;
  SellerReportData? _latestData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReport();
    });
  }

  Future<void> _loadReport() async {
    final store = await StoreService.instance.getMyStore();
    if (store == null || !mounted) return;
    final id = store['id'] as String;
    final service = SalesService();
    setState(() {
      _storeId = id;
      _reportFuture = _fetchReport(id);
      // Revenue charts moved here from the dashboard — same queries the
      // dashboard blocks used, so the numbers agree everywhere.
      _weeklyTrendFuture = service.getWeeklyTrend(
        storeId: id,
        channel: SalesChannelFilter.all,
      );
      _monthlyTrendFuture = service.getMonthlyTrend(
        storeId: id,
        channel: SalesChannelFilter.all,
      );
    });
  }

  void _loadTrends(String storeId) {
    final service = SalesService();
    _weeklyTrendFuture = service.getWeeklyTrend(
      storeId: storeId,
      channel: SalesChannelFilter.all,
    );
    _monthlyTrendFuture = service.getMonthlyTrend(
      storeId: storeId,
      channel: SalesChannelFilter.all,
    );
  }

  Future<SellerReportData> _fetchReport(String storeId) async {
    final service = SalesService();
    final now = DateTime.now();
    if (_isMonthly) {
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      return service.getWeeklyReport(storeId, weekStart: start, weekEnd: end, monthly: true);
    }
    return service.getWeeklyReport(storeId);
  }

  String _formatPeso(double amount) {
    final whole = amount.floor();
    final formatted = whole.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '₱$formatted';
  }

  String _weekLabel(DateTime start, DateTime end) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    if (_isMonthly) {
      return '${months[start.month - 1]} ${start.year}';
    }
    const short = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${short[start.month - 1]} ${start.day} – ${short[end.month - 1]} ${end.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.chrome,
        elevation: 0,
        title: Text(
          'Reports',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: () => _exportCsv(_latestData),
          ),
        ],
      ),
      body: _storeId == null
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            )
          : FutureBuilder<SellerReportData>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingSkeleton();
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ErrorRetryWidget(
                        message:
                            'Failed to load report data.\n${snapshot.error}',
                        onRetry: () {
                          setState(() {
                            _reportFuture = _fetchReport(_storeId!);
                            _loadTrends(_storeId!);
                          });
                        },
                      ),
                    ),
                  );
                }
                final data = snapshot.data!;
                _latestData = data;
                return _buildReportBody(data);
              },
            ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: double.infinity, height: 180, borderRadius: 16),
          const SizedBox(height: 20),
          ShimmerBox(width: double.infinity, height: 60, borderRadius: 16),
          const SizedBox(height: 8),
          ShimmerBox(width: double.infinity, height: 60, borderRadius: 16),
          const SizedBox(height: 8),
          ShimmerBox(width: double.infinity, height: 60, borderRadius: 16),
        ],
      ),
    );
  }

  Widget _buildReportBody(SellerReportData data) {
    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: () async {
        final future = _fetchReport(_storeId!);
        setState(() {
          _reportFuture = future;
          _loadTrends(_storeId!);
        });
        await Future.wait([future, _weeklyTrendFuture, _monthlyTrendFuture]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Sales Overview
            _buildSectionLabel('SALES OVERVIEW'),
            const SizedBox(height: 16),
            _buildSalesOverview(data),
            const SizedBox(height: 20),

            // Section 2: Revenue — weekly + monthly charts and the
            // online vs in-store breakdown, moved here from the dashboard
            // so tapping a sale opens the charts behind it.
            _buildSectionLabel('REVENUE'),
            const SizedBox(height: 16),
            _buildRevenueSection(data),
            const SizedBox(height: 20),

            // Section 3: Top Products
            _buildSectionLabel('TOP PRODUCTS'),
            const SizedBox(height: 12),
            _buildTopProducts(data.topProducts),
            const SizedBox(height: 20),

            // Section 4: Export
            _buildSectionLabel('EXPORT'),
            const SizedBox(height: 12),
            _buildExportButton(data),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesOverview(SellerReportData data) {
    // Period toggle + labels
    final now = DateTime.now();
    final barLabels = _isMonthly
        ? List.generate(
            DateTime(now.year, now.month + 1, 0).day,
            (i) => '${i + 1}',
          )
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // Pad or trim dailyRevenue to match bar count
    final barData = _isMonthly
        ? List<double>.generate(barLabels.length, (i) {
            if (i < data.dailyRevenue.length) return data.dailyRevenue[i];
            return 0;
          })
        : data.dailyRevenue;

    return Container(
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SellerTheme.cardBorder),
        boxShadow: AppConstants.sellerShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period selector
          Row(
            children: [
              _periodChip('This Week', !_isMonthly),
              const SizedBox(width: 8),
              _periodChip('This Month', _isMonthly),
            ],
          ),
          const SizedBox(height: 12),
          // Date range label
          Text(
            _weekLabel(data.weekStart, data.weekEnd),
            style: AppConstants.bodyStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          // Total revenue
          Text(
            'Total: ${_formatPeso(data.weeklyTotal)}',
            style: AppConstants.monoStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(height: 12),
          // Revenue comparison
          _buildComparisonChip(data),
          const SizedBox(height: 16),
          // Bar chart
          SizedBox(
            height: 140,
            child: SellerWeeklyBar(
              dailySales: barData,
              dayLabels: barLabels,
              todayIndex: _isMonthly ? now.day - 1 : now.weekday - 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonChip(SellerReportData data) {
    final change = data.percentChange;
    if (change == null) {
      return const SizedBox.shrink();
    }
    final isUp = change >= 0;
    final color = isUp ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final label = _isMonthly ? 'vs last month' : 'vs last week';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${change.abs().toStringAsFixed(1)}%',
            style: AppConstants.monoStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
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
      ),
    );
  }

  /// Revenue charts moved here from the dashboard: the weekly stacked
  /// columns, the monthly trend, and the online vs in-store doughnut.
  /// Same cards, same queries — so tapping a sale opens the charts behind it.
  Widget _buildRevenueSection(SellerReportData data) {
    return Column(
      children: [
        _trendCard(
          future: _weeklyTrendFuture,
          child: (trend) => SellerRevenueColumnsChart(
            title: 'Revenue — This Week',
            subtitle: _weekLabel(data.weekStart, data.weekEnd),
            points: trend.points,
            trendResult: trend,
            isWeekly: true,
            labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          ),
        ),
        const SizedBox(height: 16),
        _trendCard(
          future: _monthlyTrendFuture,
          child: (trend) => SellerRevenueColumnsChart(
            title: 'Revenue — Monthly Trend',
            subtitle: SalesService.monthlyFullLabels().last,
            points: trend.points,
            trendResult: trend,
            isWeekly: false,
          ),
        ),
        const SizedBox(height: 16),
        _trendCard(
          future: _monthlyTrendFuture,
          child: (trend) => SellerRevenueDoughnutChart(
            title: 'Revenue breakdown',
            periodLabel: SalesService.monthlyFullLabels().last,
            trendResult: trend,
          ),
        ),
      ],
    );
  }

  /// Card chrome shared by the three revenue cards above, matching the
  /// sales-overview card on this screen.
  Widget _trendCard({
    required Future<SalesTrendResult> future,
    required Widget Function(SalesTrendResult trend) child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SellerTheme.cardBorder),
        boxShadow: AppConstants.sellerShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<SalesTrendResult>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ShimmerBox(
              width: double.infinity,
              height: 220,
              borderRadius: 12,
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: ErrorRetryWidget(
                message: 'Failed to load revenue chart.',
                onRetry: () {
                  setState(() => _loadTrends(_storeId!));
                },
              ),
            );
          }
          return child(snapshot.data!);
        },
      ),
    );
  }

  Widget _periodChip(String label, bool selected) {
    return GestureDetector(
      onTap: () {
        if (_isMonthly != (label == 'This Month')) {
          setState(() {
            _isMonthly = label == 'This Month';
            _reportFuture = _fetchReport(_storeId!);
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primary
              : AppConstants.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppConstants.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildTopProducts(List<Map<String, dynamic>> products) {
    if (products.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SellerTheme.cardBorder),
          boxShadow: AppConstants.sellerShadow,
        ),
        child: Center(
          child: Text(
            'No products sold this ${_isMonthly ? 'month' : 'week'}.',
            style: AppConstants.bodyStyle(color: Colors.grey.shade400),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SellerTheme.cardBorder),
        boxShadow: AppConstants.sellerShadow,
      ),
      child: Column(
        children: [
          for (int i = 0; i < products.length; i++) ...[
            _productRankRow(i + 1, products[i]),
            if (i < products.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }

  Widget _productRankRow(int rank, Map<String, dynamic> product) {
    final name = product['name'] as String? ?? 'Unknown';
    final units = product['units'] as int? ?? 0;
    final revenue = product['revenue'] as double? ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? AppConstants.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: AppConstants.monoStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$units units',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text(
              _formatPeso(revenue),
              textAlign: TextAlign.right,
              style: AppConstants.monoStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _escCsv(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _csvDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Build a CSV of the loaded report (summary + daily revenue + top
  /// products) and save it straight into the shared Downloads folder —
  /// no share sheet. Plain ASCII throughout (no BOM, no smart dashes)
  /// so phone spreadsheet viewers render it cleanly.
  Future<void> _exportCsv(SellerReportData? data) async {
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report is still loading — try again in a moment.'),
          backgroundColor: AppConstants.primary,
        ),
      );
      return;
    }
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const shortMonths = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      String dayLabel(DateTime d) =>
          '${weekdays[d.weekday - 1]}, ${shortMonths[d.month - 1]} ${d.day}';

      var bestIdx = 0;
      for (var i = 1; i < data.dailyRevenue.length; i++) {
        if (data.dailyRevenue[i] > data.dailyRevenue[bestIdx]) bestIdx = i;
      }
      final bestDay = data.weeklyTotal > 0
          ? '${dayLabel(data.weekStart.add(Duration(days: bestIdx)))} '
              '(${data.dailyRevenue[bestIdx].toStringAsFixed(2)})'
          : 'n/a';

      final rows = <List<Object?>>[
        ['Seller Sales Report'],
        [
          'Period',
          '${_csvDate(data.weekStart)} to ${_csvDate(data.weekEnd)}',
        ],
        ['Generated', _csvDate(DateTime.now())],
        [],
        ['Summary'],
        ['Total Revenue (PHP)', data.weeklyTotal.toStringAsFixed(2)],
        [
          'Previous Period (PHP)',
          data.previousPeriodTotal.toStringAsFixed(2)
        ],
        [
          'Change (%)',
          data.percentChange == null
              ? 'n/a'
              : data.percentChange!.toStringAsFixed(1),
        ],
        ['Best Day', bestDay],
        [],
        ['Daily Revenue'],
        ['Day', 'Date', 'Revenue (PHP)'],
        for (int i = 0; i < data.dailyRevenue.length; i++)
          [
            dayLabel(data.weekStart.add(Duration(days: i))),
            _csvDate(data.weekStart.add(Duration(days: i))),
            data.dailyRevenue[i].toStringAsFixed(2),
          ],
        ['Total', '', data.weeklyTotal.toStringAsFixed(2)],
        [],
        ['Top Products'],
        ['Rank', 'Product', 'Units Sold', 'Revenue (PHP)', 'Share'],
        for (int i = 0; i < data.topProducts.length; i++)
          [
            i + 1,
            data.topProducts[i]['name'] ?? 'Unknown',
            data.topProducts[i]['units'] ?? 0,
            ((data.topProducts[i]['revenue'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(2),
            data.weeklyTotal > 0
                ? '${((((data.topProducts[i]['revenue'] as num?)?.toDouble() ?? 0) / data.weeklyTotal) * 100).toStringAsFixed(1)}%'
                : 'n/a',
          ],
      ];
      final csv = rows.map((r) => r.map(_escCsv).join(',')).join('\n');

      // System save picker (Storage Access Framework) — the seller picks
      // the destination, defaulting to Downloads. The file is written
      // there directly: downloaded, not sent through the share sheet.
      final fileName = 'sales-report-${_csvDate(DateTime.now())}';
      final savedPath = await FileSaver.instance.saveAs(
        name: fileName,
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'Download cancelled — no file was saved.'
                : 'Saved to $savedPath',
          ),
          backgroundColor: AppConstants.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildExportButton(SellerReportData data) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _isExporting ? null : () => _exportCsv(data),
        icon: _isExporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download, color: AppConstants.primary),
        label: Text(
          _isExporting
              ? 'Preparing CSV…'
              : 'Download Sales Report (CSV)',
          style: AppConstants.bodyStyle(
            fontWeight: FontWeight.w500,
            color: AppConstants.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppConstants.borderGray),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Row(
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          ).copyWith(letterSpacing: 1.0),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
      ],
    );
  }
}
