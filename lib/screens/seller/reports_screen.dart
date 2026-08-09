import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../models/seller_report_data.dart';
import '../../services/sales_service.dart';
import '../../services/store_service.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/seller/seller_weekly_bar.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<SellerReportData> _reportFuture;
  String? _storeId;
  bool _isMonthly = false;

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
    setState(() {
      _storeId = id;
      _reportFuture = _fetchReport(id);
    });
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
        backgroundColor: AppConstants.secondary,
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CSV export coming soon!'),
                  backgroundColor: AppConstants.primary,
                ),
              );
            },
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
                          });
                        },
                      ),
                    ),
                  );
                }
                final data = snapshot.data!;
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
        setState(() => _reportFuture = future);
        await future;
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

            // Section 2: Top Products
            _buildSectionLabel('TOP PRODUCTS'),
            const SizedBox(height: 12),
            _buildTopProducts(data.topProducts),
            const SizedBox(height: 20),

            // Section 3: Export
            _buildSectionLabel('EXPORT'),
            const SizedBox(height: 12),
            _buildExportButton(),
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

  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV export coming soon!'),
              backgroundColor: AppConstants.primary,
            ),
          );
        },
        icon: const Icon(Icons.download, color: AppConstants.primary),
        label: Text(
          'Download Sales Report (CSV)',
          style: AppConstants.bodyStyle(
            fontWeight: FontWeight.w500,
            color: AppConstants.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppConstants.borderGray),
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
