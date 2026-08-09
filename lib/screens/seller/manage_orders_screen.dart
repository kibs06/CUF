import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../widgets/countdown_delete_button.dart';
import '../../providers/order_provider.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/seller/seller_order_card.dart';
import '../../widgets/seller/seller_status_chip.dart';
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
  final Set<dynamic> _updatingOrderIds = {};
  // Track orders pending deletion (orderId -> Timer for 5s undo)
  final Map<dynamic, Timer> _pendingDeletes = {};
  final Set<dynamic> _deletedOrderIds = {};

  // No 'received' tab — received orders show in 'Delivered' tab
  // but the DB value is 'received' (customer confirmed).
  // The 'Delivered' tab shows DB status='delivered' (seller handed off,
  // awaiting customer confirmation).

  final List<String> _tabs = [
    'All',
    'Pending',
    'Confirmed',
    'Ready',
    'Delivered',
    'Cancelled',
  ];
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        Provider.of<OrderProvider>(context, listen: false).loadOrders();
      }
      _wasOffline = !isOnline;
    });
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
    _connectivitySub?.cancel();
    _tabController.dispose();
    // Cancel all pending delete timers
    for (final timer in _pendingDeletes.values) {
      timer.cancel();
    }
    _pendingDeletes.clear();
    super.dispose();
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

  // ── Swipe-to-delete for cancelled orders ─────────────────────

  void _confirmDeleteOrder(dynamic orderId, Map<String, dynamic> orderData) {
    if (_pendingDeletes.containsKey(orderId) || _deletedOrderIds.contains(orderId)) return;
    HapticFeedback.mediumImpact();

    final shortId = orderId.toString().length >= 8
        ? orderId.toString().substring(0, 8)
        : orderId.toString();

    String customerName = 'Customer';
    if (orderData['profiles'] != null) {
      final profile = orderData['profiles'];
      customerName = profile['full_name'] ?? profile['email'] ?? 'Customer';
    } else if (orderData['customer_name'] != null) {
      customerName = orderData['customer_name'];
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppConstants.sellerCardBg,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 32, color: AppConstants.error),
            const SizedBox(height: 12),
            Text(
              'Delete Order #$shortId?',
              style: AppConstants.bodyStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$customerName\nWait for the button to activate, then you have 5 seconds to undo.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          CountdownDeleteButton(
            onConfirm: () {
              Navigator.of(context).pop();
              _swipeDeleteOrder(orderId, orderData);
            },
          ),
        ],
      ),
    );
  }

  void _swipeDeleteOrder(dynamic orderId, Map<String, dynamic> orderData) {
    if (_pendingDeletes.containsKey(orderId) || _deletedOrderIds.contains(orderId)) return;

    HapticFeedback.mediumImpact();

    final provider = Provider.of<OrderProvider>(context, listen: false);
    final deletedData = provider.deleteOrder(orderId);
    if (deletedData == null) return;

    _deletedOrderIds.add(orderId);
    setState(() {});

    // 5-second undo window
    final timer = Timer(const Duration(seconds: 5), () {
      // Undo window expired — permanently delete from database
      _pendingDeletes.remove(orderId);
      _deletedOrderIds.remove(orderId);
      provider.permanentlyDeleteOrder(orderId);
    });
    _pendingDeletes[orderId] = timer;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Order deleted — undo available for 5s'),
        duration: const Duration(seconds: 5),
        backgroundColor: AppConstants.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppConstants.primary,
          onPressed: () {
            timer.cancel();
            _pendingDeletes.remove(orderId);
            _deletedOrderIds.remove(orderId);
            provider.restoreOrder(deletedData);
            setState(() {});
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Order restored'),
                backgroundColor: AppConstants.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          },
        ),
      ),
    );
  }

  Map<String, Color> get _statusColors => {
    'pending': AppConstants.statusPendingColor,
    'confirmed': AppConstants.statusConfirmedColor,
    'ready': AppConstants.statusReadyColor,
    'delivered': AppConstants.statusDeliveredColor,
    'cancelled': AppConstants.statusCancelledColor,
  };

  Future<void> _updateStatus(dynamic orderId, String currentStatus, {Map<String, dynamic>? orderData}) async {
    // Guard: null orderId or already in flight
    if (orderId == null) return;
    if (_updatingOrderIds.contains(orderId)) return;
    if (!mounted) return;

    // Determine next status
    String nextStatus;
    switch (currentStatus.toLowerCase()) {
      case 'pending':
        nextStatus = 'confirmed';
        break;
      case 'preparing':
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

    // Build short order ID for display (first 8 chars)
    final shortId = orderId.toString().length >= 8
        ? orderId.toString().substring(0, 8)
        : orderId.toString();

    // Extract order context for dialog (prefer enriched data passed in)
    final o = orderData ??
        Provider.of<OrderProvider>(context, listen: false).orders.firstWhere(
          (o) => o['id'] == orderId,
          orElse: () => {},
        );
    String customerName = 'Customer';
    if (o['profiles'] != null) {
      final profile = o['profiles'];
      customerName = profile['full_name'] ?? profile['email'] ?? 'Customer';
    } else if (o['customer_name'] != null) {
      customerName = o['customer_name'];
    }
    final itemCount = (o['quantity'] as num?)?.toInt() ?? 0;
    final totalAmount = (o['total_amount'] is double)
        ? o['total_amount'] as double
        : (o['total_amount'] ?? 0).toDouble();

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppConstants.sellerCardBg,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status transition chips
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SellerStatusChip(status: currentStatus),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ),
                SellerStatusChip(status: nextStatus),
              ],
            ),
            const SizedBox(height: 16),
            // Title with icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 22,
                  color: AppConstants.statusConfirmedColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Confirm Order #$shortId?',
                    style: AppConstants.bodyStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Compact order context
            Text(
              '$customerName · $itemCount item${itemCount == 1 ? '' : 's'} · ₱${totalAmount.toStringAsFixed(0)}',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Notification note
            Text(
              'The customer will be notified.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.statusConfirmedColor,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Confirm',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Set loading state
    setState(() => _updatingOrderIds.add(orderId));

    try {
      final success = await Provider.of<OrderProvider>(
        context,
        listen: false,
      ).updateOrderStatus(orderId, nextStatus);

      if (mounted) {
        setState(() => _updatingOrderIds.remove(orderId));

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #$orderId updated to $nextStatus'),
              backgroundColor: AppConstants.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update Order #$orderId. Please try again.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingOrderIds.remove(orderId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating Order #$orderId: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _showRejectDialog(dynamic orderId, Map<String, dynamic> orderData) async {
    if (orderId == null || !mounted) return;

    final shortId = orderId.toString().length >= 8
        ? orderId.toString().substring(0, 8)
        : orderId.toString();

    String customerName = 'Customer';
    if (orderData['profiles'] != null) {
      final profile = orderData['profiles'];
      customerName = profile['full_name'] ?? profile['email'] ?? 'Customer';
    } else if (orderData['customer_name'] != null) {
      customerName = orderData['customer_name'];
    }

    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppConstants.sellerCardBg,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SellerStatusChip(status: 'pending'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ),
                SellerStatusChip(status: 'cancelled'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 22,
                  color: AppConstants.error,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Reject Order #$shortId?',
                    style: AppConstants.bodyStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              customerName,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: 'Reason for rejection (optional)',
                hintStyle: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppConstants.borderGray),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: AppConstants.bodyStyle(fontSize: 13),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Text(
              'The customer will be notified.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Reject',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _updatingOrderIds.add(orderId));

    try {
      final success = await Provider.of<OrderProvider>(
        context,
        listen: false,
      ).cancelOrder(
        orderId: orderId,
        newStatus: 'cancelled',
        reason: reasonController.text.trim().isEmpty 
            ? 'Rejected by seller' 
            : reasonController.text.trim(),
      );

      if (mounted) {
        setState(() => _updatingOrderIds.remove(orderId));

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #$orderId has been rejected'),
              backgroundColor: AppConstants.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to reject Order #$orderId. Please try again.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingOrderIds.remove(orderId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting Order #$orderId: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  // ── Build order card, wrapped in Slidable for cancelled orders ──

  Widget _buildSlidableOrderCard(
      Map<String, dynamic> order, dynamic id, String status) {
    final isCancelled = status.toLowerCase() == 'cancelled';
    final isPendingDelete = _deletedOrderIds.contains(id);

    final card = SellerOrderCard(
      order: order,
      isUpdating: _updatingOrderIds.contains(id),
      onPrimaryAction: () => _updateStatus(id, status, orderData: order),
      onReject: status.toLowerCase() == 'pending'
          ? () => _showRejectDialog(id, order)
          : null,
      onViewDetails: () {
        Navigator.of(context)
            .push<bool>(
              MaterialPageRoute(
                builder: (_) => OrderDetailScreen(order: order),
              ),
            )
            .then((result) {
          if (result == true && mounted) {
            Provider.of<OrderProvider>(context, listen: false).loadOrders();
          }
        });
      },
    );

    // Wrap all cards with fade animation for smooth deletion
    Widget animatedCard = AnimatedOpacity(
      opacity: isPendingDelete ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: isPendingDelete ? const Offset(0.15, 0) : Offset.zero,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        child: card,
      ),
    );

    // Only cancelled orders are swipeable
    if (!isCancelled) return animatedCard;

    return Slidable(
      key: ValueKey(id),
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.28,
        children: [
          CustomSlidableAction(
            onPressed: (_) => _confirmDeleteOrder(id, order),
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            borderRadius: BorderRadius.circular(16),
            padding: EdgeInsets.zero,
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
      child: animatedCard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final allOrders = orderProvider.orders;

    List<Map<String, dynamic>> filteredOrders;
    if (_tabIndex == 0) {
      filteredOrders = allOrders;
    } else {
      // Map UI tab labels to actual DB status values
      const uiToDbFilter = <String, String>{
        'confirmed': 'preparing',
        'delivered': 'delivered',
      };
      final statusFilter = _tabs[_tabIndex].toLowerCase();
      final dbFilter = uiToDbFilter[statusFilter] ?? statusFilter;
      filteredOrders = allOrders
          .where((o) => (o['status'] ?? '').toLowerCase() == dbFilter)
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
                // Map UI tab labels to DB status values for counting
                const uiToDbCount = <String, String>{
                  'confirmed': 'preparing',
                  'delivered': 'delivered',
                };
                final dbTab = uiToDbCount[tab.toLowerCase()] ?? tab.toLowerCase();
                final count = tab == 'All'
                    ? allOrders.length
                    : allOrders
                          .where(
                            (o) =>
                                (o['status'] ?? '').toLowerCase() == dbTab,
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
                      order['time_ago'] = _timeAgo(order['created_at'] as String?);
                      order['fulfillment_type'] = 'Walk-in';

                      return _buildSlidableOrderCard(order, id, status);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
