import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../widgets/seller/seller_order_card.dart';
import 'order_detail_screen.dart';

class ManageOrdersScreen extends StatefulWidget {
  final String? initialFilter;

  const ManageOrdersScreen({super.key, this.initialFilter});

  @override
  State<ManageOrdersScreen> createState() => _ManageOrdersScreenState();
}

class _ManageOrdersScreenState extends State<ManageOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  final List<String> _tabs = [
    'All',
    'Pending',
    'Confirmed',
    'Ready',
    'Delivered',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    final startIndex = widget.initialFilter != null
        ? _tabs
              .indexWhere(
                (t) => t.toLowerCase() == widget.initialFilter!.toLowerCase(),
              )
              .clamp(0, _tabs.length - 1)
        : 0;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: startIndex,
    );
    _tabIndex = startIndex;
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadOrders();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, Color> get _statusColors => {
    'pending': AppConstants.statusPendingColor,
    'confirmed': AppConstants.statusConfirmedColor,
    'ready': AppConstants.statusReadyColor,
    'delivered': AppConstants.statusDeliveredColor,
    'cancelled': AppConstants.statusCancelledColor,
  };

  void _updateStatus(int orderId, String currentStatus) async {
    String nextStatus;
    switch (currentStatus.toLowerCase()) {
      case 'pending':
        nextStatus = 'confirmed';
        break;
      case 'confirmed':
        nextStatus = 'ready';
        break;
      case 'ready':
        nextStatus = 'delivered';
        break;
      case 'cancelled':
        nextStatus = 'pending';
        break;
      default:
        return;
    }
    final success = await Provider.of<OrderProvider>(
      context,
      listen: false,
    ).updateOrderStatus(orderId, nextStatus);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order #$orderId moved to $nextStatus'),
          backgroundColor: AppConstants.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final allOrders = orderProvider.orders;

    List<Map<String, dynamic>> filteredOrders;
    if (_tabIndex == 0) {
      filteredOrders = allOrders;
    } else {
      final statusFilter = _tabs[_tabIndex].toLowerCase();
      filteredOrders = allOrders
          .where((o) => (o['status'] ?? '').toLowerCase() == statusFilter)
          .toList();
    }

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Orders',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppConstants.secondary,
              unselectedLabelColor: Colors.grey.shade500,
              indicatorColor: AppConstants.accent,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: AppConstants.bodyStyle(fontSize: 12),
              tabs: _tabs.map((tab) {
                final count = tab == 'All'
                    ? allOrders.length
                    : allOrders
                          .where(
                            (o) =>
                                (o['status'] ?? '').toLowerCase() ==
                                tab.toLowerCase(),
                          )
                          .length;
                final color =
                    _statusColors[tab.toLowerCase()] ?? AppConstants.secondary;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tab),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: AppConstants.monoStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // Orders list
          Expanded(
            child: orderProvider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppConstants.primary,
                    ),
                  )
                : filteredOrders.isEmpty
                ? Center(
                    child: Text(
                      'No ${_tabIndex == 0 ? '' : _tabs[_tabIndex].toLowerCase()} orders',
                      style: AppConstants.bodyStyle(
                        color: Colors.grey.shade400,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filteredOrders.length,
                    itemBuilder: (context, index) {
                      final order = filteredOrders[index];
                      final id = order['id'];
                      final status = order['status'] ?? 'pending';

                      // Build customer name from available data
                      String customerName = 'Customer';
                      if (order['profiles'] != null) {
                        final profile = order['profiles'];
                        customerName =
                            profile['full_name'] ??
                            profile['email'] ??
                            'Customer';
                      }

                      order['customer_name'] = customerName;
                      order['time_ago'] = '${(index + 1) * 5} min ago';
                      order['fulfillment_type'] = 'Walk-in';

                      return SellerOrderCard(
                        order: order,
                        onPrimaryAction: () => _updateStatus(id, status),
                        onViewDetails: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(order: order),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
