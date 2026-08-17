import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import 'admin_helpers.dart';

/// Admin Analytics — port of admin-portal/src/pages/Analytics.jsx.
///
/// 7/30/90-day period selector with charts for orders, revenue, order
/// status mix, top products, new users, and seller application trend.
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  int _days = 30;
  bool _loading = true;
  String? _error;

  // Chart series
  List<({String date, int orders})> _ordersOverTime = [];
  List<({String date, double revenue})> _revenueOverTime = [];
  List<({String date, int users})> _usersOverTime = [];
  List<({String name, int value})> _ordersByStatus = [];
  List<({String name, int count})> _topProducts = [];
  List<({String month, int pending, int approved, int rejected})> _sellerTrend = [];

  static const _chartColors = [
    Color(0xFF8B5A2B),
    Color(0xFF4ECDC4),
    Color(0xFFE8A020),
    Color(0xFFD64545),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ];

  static const _statusColors = {
    'pending': Color(0xFFE8A020),
    'placed': Color(0xFFE8A020),
    'confirmed': Color(0xFF3B82F6),
    'preparing': Color(0xFF3B82F6),
    'ready': Color(0xFF8B5A2B),
    'shipped': Color(0xFF8B5CF6),
    'received': Color(0xFF4ECDC4),
    'delivered': Color(0xFF4ECDC4),
    'cancelled': Color(0xFFD64545),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final since = DateTime.now()
          .subtract(Duration(days: _days - 1));
      final sinceDay = DateTime(since.year, since.month, since.day);

      final ordersRes = await client
          .from('orders')
          .select('id, status, total_amount, created_at')
          .gte('created_at', sinceDay.toUtc().toIso8601String());
      final profilesRes = await client
          .from('profiles')
          .select('id, seller_status, created_at')
          .gte('created_at', sinceDay.toUtc().toIso8601String());

      final orders = List<Map<String, dynamic>>.from(ordersRes);
      final profiles = List<Map<String, dynamic>>.from(profilesRes);

      // Day buckets
      final dayKeys = <String>[];
      for (var i = _days - 1; i >= 0; i--) {
        final d = DateTime.now().subtract(Duration(days: i));
        dayKeys.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }
      final ordersByDay = {for (final k in dayKeys) k: 0};
      final revenueByDay = {for (final k in dayKeys) k: 0.0};
      final usersByDay = {for (final k in dayKeys) k: 0};

      for (final o in orders) {
        final key = (o['created_at'] ?? '').toString().substring(0, 10);
        if (ordersByDay.containsKey(key)) {
          ordersByDay[key] = ordersByDay[key]! + 1;
          revenueByDay[key] = revenueByDay[key]! + ((o['total_amount'] as num?)?.toDouble() ?? 0);
        }
      }
      for (final p in profiles) {
        final key = (p['created_at'] ?? '').toString().substring(0, 10);
        if (usersByDay.containsKey(key)) usersByDay[key] = usersByDay[key]! + 1;
      }

      _ordersOverTime = dayKeys
          .map((k) => (date: k.substring(5), orders: ordersByDay[k]!))
          .toList();
      _revenueOverTime = dayKeys
          .map((k) => (date: k.substring(5), revenue: revenueByDay[k]!))
          .toList();
      _usersOverTime = dayKeys
          .map((k) => (date: k.substring(5), users: usersByDay[k]!))
          .toList();

      // Orders by status
      final statusCounts = <String, int>{};
      for (final o in orders) {
        final s = (o['status'] ?? 'unknown').toString();
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
      }
      _ordersByStatus = statusCounts.entries
          .map((e) => (name: e.key, value: e.value))
          .toList();

      // Top products (from order items in range)
      final productCounts = <String, int>{};
      final orderIds = orders.map((o) => (o['id'] ?? '').toString()).where((id) => id.isNotEmpty).toList();
      if (orderIds.isNotEmpty) {
        final itemsRes = await client
            .from('order_items')
            .select('product_id, quantity, products(name)')
            .inFilter('order_id', orderIds);
        for (final item in (itemsRes as List?) ?? []) {
          final name = (item?['products']?['name'] ?? 'Unknown').toString();
          productCounts[name] = (productCounts[name] ?? 0) + ((item?['quantity'] as num?)?.toInt() ?? 1);
        }
      }
      final sortedProducts = productCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _topProducts = sortedProducts
          .take(10)
          .map((e) => (name: e.key, count: e.value))
          .toList();

      // Seller application trend (monthly)
      final trend = <String, ({int pending, int approved, int rejected})>{};
      for (final p in profiles) {
        final status = (p['seller_status'] ?? '').toString();
        if (status != 'pending' && status != 'approved' && status != 'rejected') continue;
        final month = (p['created_at'] ?? '').toString().substring(0, 7);
        final entry = trend.putIfAbsent(month, () => (pending: 0, approved: 0, rejected: 0));
        switch (status) {
          case 'pending':
            trend[month] = (pending: entry.pending + 1, approved: entry.approved, rejected: entry.rejected);
          case 'approved':
            trend[month] = (pending: entry.pending, approved: entry.approved + 1, rejected: entry.rejected);
          case 'rejected':
            trend[month] = (pending: entry.pending, approved: entry.approved, rejected: entry.rejected + 1);
        }
      }
      final months = trend.keys.toList()..sort();
      _sellerTrend = [
        for (final m in months)
          (
            month: m,
            pending: trend[m]!.pending,
            approved: trend[m]!.approved,
            rejected: trend[m]!.rejected,
          ),
      ];

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Analytics', style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Column(
            children: [
              // Period pills
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    for (final d in [7, 30, 90]) ...[
                      GestureDetector(
                        onTap: () {
                          if (_days != d) {
                            setState(() => _days = d);
                            _load();
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _days == d ? AppConstants.primary : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _days == d ? AppConstants.primary : AppConstants.borderGray,
                            ),
                          ),
                          child: Text(
                            'Last $d days',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _days == d ? Colors.white : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Charts
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: AppConstants.bodyStyle(color: AppConstants.error),
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: [
                              _ChartCard(
                                title: 'Orders Over Time',
                                child: _ordersOverTime.every((e) => e.orders == 0)
                                    ? _emptyChart('No orders in this period')
                                    : SizedBox(
                                        height: 200,
                                        child: _areaChart(
                                          spots: [
                                            for (var i = 0; i < _ordersOverTime.length; i++)
                                              FlSpot(i.toDouble(), _ordersOverTime[i].orders.toDouble()),
                                          ],
                                          color: AppConstants.primary,
                                          showY: true,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              _ChartCard(
                                title: 'Revenue Over Time',
                                child: _revenueOverTime.every((e) => e.revenue == 0)
                                    ? _emptyChart('No revenue in this period')
                                    : SizedBox(
                                        height: 200,
                                        child: _areaChart(
                                          spots: [
                                            for (var i = 0; i < _revenueOverTime.length; i++)
                                              FlSpot(i.toDouble(), _revenueOverTime[i].revenue),
                                          ],
                                          color: AppConstants.accent,
                                          showY: true,
                                          money: true,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              _ChartCard(
                                title: 'Orders by Status',
                                child: _ordersByStatus.isEmpty
                                    ? _emptyChart('No orders yet')
                                    : SizedBox(
                                        height: 200,
                                        child: PieChart(
                                          PieChartData(
                                            sectionsSpace: 2,
                                            centerSpaceRadius: 46,
                                            sections: [
                                              for (final s in _ordersByStatus)
                                                PieChartSectionData(
                                                  value: s.value.toDouble(),
                                                  color: _statusColors[s.name] ??
                                                      _chartColors[_ordersByStatus.indexOf(s) % _chartColors.length],
                                                  radius: 54,
                                                  showTitle: false,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              _ChartCard(
                                title: 'Top Products',
                                child: _topProducts.isEmpty
                                    ? _emptyChart('No product data yet')
                                    : _topProductsList(),
                              ),
                              const SizedBox(height: 12),
                              _ChartCard(
                                title: 'New Users Over Time',
                                child: _usersOverTime.every((e) => e.users == 0)
                                    ? _emptyChart('No new users in this period')
                                    : SizedBox(
                                        height: 200,
                                        child: _areaChart(
                                          spots: [
                                            for (var i = 0; i < _usersOverTime.length; i++)
                                              FlSpot(i.toDouble(), _usersOverTime[i].users.toDouble()),
                                          ],
                                          color: AppConstants.accent,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              _ChartCard(
                                title: 'Seller Application Trend',
                                child: _sellerTrend.isEmpty
                                    ? _emptyChart('No applications yet')
                                    : SizedBox(
                                        height: 200,
                                        child: BarChart(
                                          BarChartData(
                                            alignment: BarChartAlignment.spaceAround,
                                            maxY: _maxTrendY() == 0 ? 1 : _maxTrendY(),
                                            barTouchData: BarTouchData(enabled: false),
                                            gridData: FlGridData(
                                              show: true,
                                              drawVerticalLine: false,
                                              getDrawingHorizontalLine: (v) => FlLine(
                                                color: AppConstants.borderGray.withValues(alpha: 0.3),
                                                strokeWidth: 1,
                                              ),
                                            ),
                                            borderData: FlBorderData(show: false),
                                            titlesData: FlTitlesData(
                                              leftTitles: const AxisTitles(
                                                sideTitles: SideTitles(showTitles: false),
                                              ),
                                              topTitles: const AxisTitles(
                                                sideTitles: SideTitles(showTitles: false),
                                              ),
                                              rightTitles: const AxisTitles(
                                                sideTitles: SideTitles(showTitles: false),
                                              ),
                                              bottomTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  getTitlesWidget: (value, meta) {
                                                    final i = value.toInt();
                                                    if (i < 0 || i >= _sellerTrend.length) {
                                                      return const SizedBox.shrink();
                                                    }
                                                    final month = _sellerTrend[i].month;
                                                    final short = month.length >= 7
                                                        ? month.substring(5)
                                                        : month;
                                                    return Padding(
                                                      padding: const EdgeInsets.only(top: 6),
                                                      child: Text(
                                                        short,
                                                        style: AppConstants.bodyStyle(fontSize: 9, color: Colors.black45),
                                                      ),
                                                    );
                                                  },
                                                  reservedSize: 24,
                                                  interval: 1,
                                                ),
                                              ),
                                            ),
                                            barGroups: [
                                              for (var i = 0; i < _sellerTrend.length; i++)
                                                BarChartGroupData(
                                                  x: i,
                                                  barsSpace: 2,
                                                  barRods: [
                                                    BarChartRodData(
                                                      toY: _sellerTrend[i].pending.toDouble(),
                                                      color: const Color(0xFFE8A020),
                                                      width: 8,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                    BarChartRodData(
                                                      toY: _sellerTrend[i].approved.toDouble(),
                                                      color: const Color(0xFF4ECDC4),
                                                      width: 8,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                    BarChartRodData(
                                                      toY: _sellerTrend[i].rejected.toDouble(),
                                                      color: const Color(0xFFD64545),
                                                      width: 8,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              // Legend for the trend chart
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _legendDot('Pending', const Color(0xFFE8A020)),
                                  const SizedBox(width: 12),
                                  _legendDot('Approved', const Color(0xFF4ECDC4)),
                                  const SizedBox(width: 12),
                                  _legendDot('Rejected', const Color(0xFFD64545)),
                                ],
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _maxTrendY() {
    var maxY = 0.0;
    for (final t in _sellerTrend) {
      maxY = [maxY, t.pending.toDouble(), t.approved.toDouble(), t.rejected.toDouble()]
          .reduce((a, b) => a > b ? a : b);
    }
    return maxY;
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _topProductsList() {
    final maxCount = _topProducts.first.count;
    return Column(
      children: [
        for (final p in _topProducts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppConstants.borderGray.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: maxCount == 0 ? 0 : p.count / maxCount,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppConstants.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${p.count}',
                    textAlign: TextAlign.right,
                    style: AppConstants.monoStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppConstants.secondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _areaChart({
    required List<FlSpot> spots,
    required Color color,
    bool showY = false,
    bool money = false,
  }) {
    final hasData = spots.isNotEmpty;
    final maxY = hasData
        ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b)
        : 1.0;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => [
              for (final t in touchedSpots)
                LineTooltipItem(
                  money
                      ? adminCurrencyWhole(t.y)
                      : (t.y == t.y.roundToDouble() ? t.y.toInt().toString() : t.y.toStringAsFixed(1)),
                  TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        gridData: FlGridData(
          show: showY,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: AppConstants.borderGray.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: showY,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value == value.roundToDouble() ? value.toInt().toString() : '',
                style: AppConstants.bodyStyle(fontSize: 9, color: Colors.black38),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _ordersOverTime.length) {
                  return const SizedBox.shrink();
                }
                // Show ~4 evenly spaced labels
                if (_ordersOverTime.length > 4 && i % ((_ordersOverTime.length / 4).ceil()) != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _ordersOverTime[i].date,
                    style: AppConstants.bodyStyle(fontSize: 9, color: Colors.black45),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyChart(String message) {
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 28, color: Colors.black26),
            const SizedBox(height: 8),
            Text(message, style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
