import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/seller_notification_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/order_service.dart';
import '../../services/sales_service.dart';
import '../../services/seller_notification_service.dart';
import '../../services/store_service.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/seller/seller_metric_card.dart';
import '../../widgets/seller/seller_alert_chip.dart';
import '../../widgets/seller/seller_order_card.dart';
import '../../widgets/seller/seller_sparkline.dart';
import '../../models/sales_trend_data.dart';
import '../../widgets/seller/seller_stacked_area_chart.dart';
import '../../widgets/seller/seller_revenue_doughnut.dart';
import 'manage_orders_screen.dart';
import 'manage_products_screen.dart';
import 'custom_orders_screen.dart';
import 'order_detail_screen.dart';
import 'seller_notification_center_screen.dart';
import 'seller_inbox_screen.dart';
import 'reports_screen.dart';

/// Dashboard data model — holds all real data fetched from Supabase.
class _DashboardData {
  final double todayRevenue;
  final List<double> weeklySalesChart;
  final List<double> monthlySalesChart;
  // Online-only breakdowns
  final List<double> onlineWeeklyChart;
  final List<double> onlineMonthlyChart;
  // POS-only breakdowns
  final List<double> posWeeklyChart;
  final List<double> posMonthlyChart;
  // Trend data for comparison
  final SalesTrendResult? weeklyTrend;
  final SalesTrendResult? monthlyTrend;
  final List<Map<String, dynamic>> recentOrders;
  final Map<String, int> ordersByStatus;
  final Map<String, dynamic>? store;
  final int lowStockCount;
  final int pendingCustoms;
  final List<Map<String, dynamic>> lowStockItems;
  final List<Map<String, dynamic>> staleOrders;

  const _DashboardData({
    required this.todayRevenue,
    required this.weeklySalesChart,
    required this.monthlySalesChart,
    required this.onlineWeeklyChart,
    required this.onlineMonthlyChart,
    required this.posWeeklyChart,
    required this.posMonthlyChart,
    this.weeklyTrend,
    this.monthlyTrend,
    required this.recentOrders,
    required this.ordersByStatus,
    this.store,
    required this.lowStockCount,
    required this.pendingCustoms,
    required this.lowStockItems,
    required this.staleOrders,
  });
}

/// Seller Dashboard — "Morning Briefing" concept.
/// Answers 4 questions instantly: sales, attention, orders, stock.
class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  late Future<_DashboardData> _dashboardFuture;
  _DashboardData? _cachedData;
  String? _storeId;
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        _loadDashboard();
      }
      _wasOffline = !isOnline;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboard();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final auth = context.read<AuthProvider>();
    final storeId = await StoreService.instance.getMyStore();
    if (storeId == null || !mounted) return;
    final id = storeId['id'] as String;
    setState(() {
      _storeId = id;
      _dashboardFuture = _fetchDashboardData(auth, id);
    });
    _dashboardFuture.then((data) {
      if (mounted) setState(() => _cachedData = data);
    });
    // Initialize seller notifications for this store
    // Set up subscription first (init is idempotent for same storeId)
    final notifProv = context.read<SellerNotificationProvider>();
    notifProv.init(id);
    // Initialize message provider for inbox badge
    // Set up subscription before load so it catches events if load fails
    final msgProv = context.read<MessageProvider>();
    msgProv.subscribeToInbox(storeId: id);
    msgProv.loadConversationsForStore(id);
  }

  Future<_DashboardData> _fetchDashboardData(
    AuthProvider auth,
    String storeId,
  ) async {
    final salesService = SalesService();
    final orderService = OrderService();

    final results = await Future.wait([
      salesService.getTodayRevenue(storeId),
      orderService.getRecentOrders(storeId, limit: 3),
      orderService.getOrderCountByStatus(storeId),
      StoreService.instance.getMyStore(),
      salesService.getOnlineWeeklyRevenue(storeId),
      salesService.getPosWeeklyRevenue(storeId),
      salesService.getOnlineMonthlyRevenueTrend(storeId),
      salesService.getPosMonthlyRevenueTrend(storeId),
      salesService.getWeeklyTrend(storeId: storeId, channel: SalesChannelFilter.all),
      salesService.getMonthlyTrend(storeId: storeId, channel: SalesChannelFilter.all),
      // Load products & orders for low stock / pending customs / alerts
      context.read<ProductProvider>().loadSellerProducts(),
      context.read<OrderProvider>().loadOrders(),
    ]);

    if (!mounted) return _emptyDashboard();

    final products = context.read<ProductProvider>().products;
    final orders = context.read<OrderProvider>().orders;

    final lowStockItems = _getLowStockItems(products);
    final lowStockCount = lowStockItems.length;

    final pendingCustoms = context
        .read<OrderProvider>()
        .customizations
        .where((c) => c['status'] == 'pending')
        .length;

    // Ensure lowStockItems and staleOrders are computed after products/orders are loaded

    final staleOrders = orders
        .where((o) => (o['status'] ?? '').toLowerCase() == 'placed')
        .take(2)
        .toList();

    // ── Notification: stale_order ─────────────────────────────────
    // Fire-and-forget: notify seller about stale pending orders.
    for (final order in staleOrders) {
      final orderId = order['id']?.toString();
      final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '');
      if (orderId != null && createdAt != null) {
        final hoursPending = DateTime.now().difference(createdAt).inHours;
        SellerNotificationService.instance.createStaleOrder(
          storeId: storeId,
          orderId: orderId,
          hoursPending: hoursPending,
        ); // intentionally not awaited
      }
    }

    // Compute combined charts from online + POS parts
    // Future.wait indices: 0=todayRevenue, 1=recentOrders, 2=ordersByStatus,
    // 3=store, 4=onlineWeekly, 5=posWeekly, 6=onlineMonthly, 7=posMonthly,
    // 8=weeklyTrend, 9=monthlyTrend, 10=loadProducts, 11=loadOrders
    final onlineWeekly = results[4] as List<double>;
    final posWeekly = results[5] as List<double>;
    final weeklySalesChart = List.generate(7, (i) => onlineWeekly[i] + posWeekly[i]);
    final onlineMonthly = results[6] as List<double>;
    final posMonthly = results[7] as List<double>;
    final monthlySalesChart = List.generate(6, (i) => onlineMonthly[i] + posMonthly[i]);

    return _DashboardData(
      todayRevenue: results[0] as double,
      recentOrders: results[1] as List<Map<String, dynamic>>,
      ordersByStatus: results[2] as Map<String, int>,
      store: results[3] as Map<String, dynamic>?,
      weeklySalesChart: weeklySalesChart,
      monthlySalesChart: monthlySalesChart,
      onlineWeeklyChart: onlineWeekly,
      posWeeklyChart: posWeekly,
      onlineMonthlyChart: onlineMonthly,
      posMonthlyChart: posMonthly,
      weeklyTrend: results[8] as SalesTrendResult?,
      monthlyTrend: results[9] as SalesTrendResult?,
      lowStockCount: lowStockCount,
      pendingCustoms: pendingCustoms,
      lowStockItems: lowStockItems,
      staleOrders: staleOrders,
    );
  }

  static _DashboardData _emptyDashboard() => const _DashboardData(
    todayRevenue: 0,
    weeklySalesChart: [0, 0, 0, 0, 0, 0, 0],
    monthlySalesChart: [0, 0, 0, 0, 0, 0],
    onlineWeeklyChart: [0, 0, 0, 0, 0, 0, 0],
    posWeeklyChart: [0, 0, 0, 0, 0, 0, 0],
    onlineMonthlyChart: [0, 0, 0, 0, 0, 0],
    posMonthlyChart: [0, 0, 0, 0, 0, 0],
    weeklyTrend: null,
    monthlyTrend: null,
    recentOrders: [],
    ordersByStatus: {},
    lowStockCount: 0,
    pendingCustoms: 0,
    lowStockItems: [],
    staleOrders: [],
  );

  List<Map<String, dynamic>> _getLowStockItems(
    List<Map<String, dynamic>> products,
  ) {
    final items = <Map<String, dynamic>>[];
    for (var prod in products) {
      final sizesMap = Map<String, dynamic>.from(prod['sizes'] ?? {});
      for (var entry in sizesMap.entries) {
        if (entry.value is int && entry.value > 0 && entry.value <= 5) {
          items.add({
            'name': prod['name'],
            'size': entry.key,
            'qty': entry.value,
          });
        }
      }
    }
    return items;
  }

  String _formatCurrency(double amount) {
    final whole = amount.floor();
    final formatted = whole.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '₱$formatted';
  }



  String _timeAgo(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Time-based greeting
    final hour = DateTime.now().hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    final firstName = auth.displayName.split(' ').first;

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CUFMAI',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$greeting, $firstName',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.white.withAlpha(180),
              ),
            ),
          ],
        ),
        actions: [
          _buildMessageIcon(),
          // Right padding lives on the last action now that the
          // initials avatar is gone.
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildNotificationBell(),
          ),
        ],
      ),
      body: _storeId == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppConstants.primary),
              ),
            )
          : FutureBuilder<_DashboardData>(
              future: _dashboardFuture,
              builder: (context, snapshot) {
                // Show skeleton only on initial load (no cached data yet)
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _cachedData == null) {
                  return _buildLoadingSkeleton();
                }
                if (snapshot.hasError && _cachedData == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ErrorRetryWidget(
                        message:
                            'Failed to load dashboard data.\n${snapshot.error}',
                        onRetry: () {
                          setState(() {
                            _dashboardFuture = _fetchDashboardData(
                              context.read<AuthProvider>(),
                              _storeId!,
                            );
                          });
                        },
                      ),
                    ),
                  );
                }
                // Use snapshot data if available, otherwise use cache
                final data = snapshot.hasData ? snapshot.data! : _cachedData!;
                return _buildDashboardBody(data);
              },
            ),
    );
  }

  // ─── LOADING SKELETON ───────────────────────────────────────────
  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metrics grid placeholder
          Row(
            children: [
              Expanded(flex: 58, child: ShimmerBox(width: double.infinity, height: 138)),
              const SizedBox(width: 8),
              Expanded(flex: 42, child: ShimmerBox(width: double.infinity, height: 112)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(flex: 42, child: ShimmerBox(width: double.infinity, height: 112)),
              const SizedBox(width: 8),
              Expanded(flex: 58, child: ShimmerBox(width: double.infinity, height: 138)),
            ],
          ),
          const SizedBox(height: 16),
          // Chart placeholder
          ShimmerBox(width: double.infinity, height: 180, borderRadius: 16),
          const SizedBox(height: 16),
          // Orders placeholder
          ShimmerBox(width: double.infinity, height: 120, borderRadius: 16),
          const SizedBox(height: 8),
          ShimmerBox(width: double.infinity, height: 120, borderRadius: 16),
        ],
      ),
    );
  }

  // ─── DASHBOARD BODY ─────────────────────────────────────────────
  Widget _buildDashboardBody(_DashboardData data) {
    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: () async {
        final auth = context.read<AuthProvider>();
        final future = _fetchDashboardData(auth, _storeId!);
        setState(() => _dashboardFuture = future);
        try {
          final data = await future;
          if (mounted) setState(() => _cachedData = data);
        } catch (_) {
          // Keep showing stale data; FutureBuilder will handle error state
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Block 1 — Today's Snapshot (real data)
            _buildMetricsGrid(data),
            const SizedBox(height: 16),

            // Block 2 — Needs Attention Alert Strip
            if (data.lowStockItems.isNotEmpty ||
                data.staleOrders.isNotEmpty ||
                data.pendingCustoms > 0)
              _buildAlertStrip(data),

            // Block 3 — Order Status Summary
            if (data.ordersByStatus.isNotEmpty) ...[
              _buildStatusSummary(data.ordersByStatus),
              const SizedBox(height: 16),
            ],

            // Block 4 — Recent Orders (real data)
            _buildSectionLabel('RECENT ORDERS'),
            const SizedBox(height: 10),
            _buildRecentOrders(data),
            const SizedBox(height: 20),

            // Block 5 — Weekly Stacked Area Chart (Online + In-Store)
            Container(
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              child: SellerStackedAreaChart(
                title: 'Revenue — This Week',
                subtitle: _getWeekDateRange(),
                points: data.weeklyTrend?.points ?? [],
                trendResult: data.weeklyTrend,
                isWeekly: true,
                labels: const [
                  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Block 6 — Monthly Stacked Area Chart
            Container(
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              child: SellerStackedAreaChart(
                title: 'Revenue — Monthly Trend',
                subtitle: SalesService.monthlyFullLabels().last,
                points: data.monthlyTrend?.points ?? [],
                trendResult: data.monthlyTrend,
                isWeekly: false,
              ),
            ),
            const SizedBox(height: 20),

            // Block 7 — Revenue Breakdown Doughnut (online vs in-store)
            Container(
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              child: SellerRevenueDoughnutChart(
                title: 'Revenue breakdown',
                periodLabel: SalesService.monthlyFullLabels().last,
                trendResult: data.monthlyTrend,
              ),
            ),
            const SizedBox(height: 16),
            _buildFullReportCta(),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ─── Block 1: Metrics Grid (real data) ──────────────────────────
  Widget _buildMetricsGrid(_DashboardData data) {
    final storeRating = data.store?['rating'];
    final ratingStr = storeRating != null
        ? '${(storeRating as num).toDouble().toStringAsFixed(1)} ★'
        : null;

    // Compute weekly total for the metrics card
    final weeklyTotal = data.weeklySalesChart.fold<double>(0, (a, b) => a + b);

    return Column(
      children: [
        Row(
          children: [
            // Today's Revenue (large, left)
            Expanded(
              flex: 58,
              child: SellerMetricCard(
                label: "TODAY'S SALES",
                value: _formatCurrency(data.todayRevenue),
                isLarge: true,
                subtitle: ratingStr,
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SellerSparkline(values: data.weeklySalesChart),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Weekly Sales (small, right)
            Expanded(
              flex: 42,
              child: SellerMetricCard(
                label: 'THIS WEEK',
                value: _formatCurrency(weeklyTotal),
                valueColor: AppConstants.primary,
                subtitle: _getWeekDateRange(),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SellerSparkline(
                    values: data.weeklySalesChart,
                    color: AppConstants.primary,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Low Stock (small, left)
            Expanded(
              flex: 42,
              child: SellerMetricCard(
                label: 'LOW STOCK',
                value: '${data.lowStockCount}',
                valueColor: data.lowStockCount > 0
                    ? AppConstants.lowStockColor
                    : AppConstants.okStockColor,
                subtitle: data.lowStockCount > 0
                    ? 'items need restocking'
                    : 'stock levels OK',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ManageProductsScreen(initialFilter: 'Low Stock'),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // Custom Orders (small, right)
            Expanded(
              flex: 58,
              child: SellerMetricCard(
                label: 'CUSTOM ORDERS',
                value: '${data.pendingCustoms}',
                subtitle: 'unreviewed requests',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomOrdersScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Block 2: Alert Strip ───────────────────────────────────────
  Widget _buildAlertStrip(_DashboardData data) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var item in data.lowStockItems.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SellerAlertChip(
                  icon: Icons.warning_amber_rounded,
                  text:
                      '${item['name']} Size ${item['size']} — ${item['qty']} left',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const ManageProductsScreen(initialFilter: 'Low Stock'),
                      ),
                    );
                  },
                ),
              ),
            for (var order in data.staleOrders)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SellerAlertChip(
                  icon: Icons.schedule,
                  text: 'Order #${order['id']} — pending',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const ManageOrdersScreen(initialFilter: 'pending'),
                      ),
                    );
                  },
                ),
              ),
            if (data.pendingCustoms > 0)
              SellerAlertChip(
                icon: Icons.design_services,
                text: '${data.pendingCustoms} custom requests',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomOrdersScreen(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ─── Block 3: Order Status Summary ──────────────────────────────
  Widget _buildStatusSummary(Map<String, int> ordersByStatus) {
    final statusOrder = ['placed', 'preparing', 'ready', 'received'];
    final total = ordersByStatus.values.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppConstants.sellerShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ORDER STATUS',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                ).copyWith(letterSpacing: 1.0),
              ),
              const SizedBox(width: 8),
              Text(
                '$total total',
                style: AppConstants.monoStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: statusOrder.map((status) {
              final count = ordersByStatus[status] ?? 0;
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: AppConstants.monoStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _statusColor(status),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.toUpperCase(),
                      style: AppConstants.monoStyle(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'placed':
        return AppConstants.statusPendingColor;
      case 'preparing':
        return AppConstants.statusConfirmedColor;
      case 'ready':
        return AppConstants.statusReadyColor;
      case 'received':
        return AppConstants.statusDeliveredColor;
      default:
        return AppConstants.secondary;
    }
  }

  // ─── Block 4: Recent Orders (real data) ─────────────────────────
  Widget _buildRecentOrders(_DashboardData data) {
    final orders = data.recentOrders;

    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppConstants.sellerShadow,
        ),
        child: Center(
          child: Text(
            'No pending orders.',
            style: AppConstants.bodyStyle(color: Colors.grey.shade400),
          ),
        ),
      );
    }

    return Column(
      children: [
        ...orders.map((order) {
          // Enrich the order map for SellerOrderCard
          final enriched = Map<String, dynamic>.from(order);
          enriched['time_ago'] = _timeAgo(order['created_at'] as String?);
          enriched['fulfillment_type'] = 'Walk-in';

          // Dashboard is a glanceable summary — status changes should
          // happen from the Orders tab / Order Detail screen where the
          // seller has full context, not as a reflexive tap here.
          return SellerOrderCard(
            order: enriched,
            onPrimaryAction: () {},
            onViewDetails: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderDetailScreen(order: enriched),
                ),
              );
            },
            showPrimaryAction: false,
          );
        }),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageOrdersScreen()),
              );
            },
            child: Text(
              'View All Orders →',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppConstants.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Block 8: Full Report CTA ───────────────────────────────────
  Widget _buildFullReportCta() {
    return Material(
      color: AppConstants.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReportsScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppConstants.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'View Full Sales Report',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Daily revenue, top products & CSV export',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppConstants.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section Label ──────────────────────────────────────────────
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



  // ─── Week helpers ───────────────────────────────────────────────
  String _getWeekDateRange() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[startOfWeek.month - 1]} ${startOfWeek.day}–${endOfWeek.day}';
  }



  // ─── Message Icon with Badge ──────────────────────────────────
  Widget _buildMessageIcon() {
    final msgProvider = context.watch<MessageProvider>();
    final badge = msgProvider.unreadBadge;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
          onPressed: () async {
            // Force-refresh before navigating so badge & list are current
            await msgProvider.refreshInbox();
            if (!mounted || !context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SellerInboxScreen(),
              ),
            );
          },
        ),
        if (badge.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppConstants.statusConfirmedColor,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // ─── Notification Bell with Badge ──────────────────────────────
  Widget _buildNotificationBell() {
    final notifProvider = context.watch<SellerNotificationProvider>();
    final badge = notifProvider.unreadBadge;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () async {
            // Force-refresh unread count before navigating, as a safety net
            await notifProvider.refreshNotifications();
            if (!mounted || !context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SellerNotificationCenterScreen(),
              ),
            );
          },
        ),
        if (badge.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppConstants.statusConfirmedColor,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
