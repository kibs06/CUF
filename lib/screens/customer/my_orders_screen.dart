import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/message_service.dart';
import '../../widgets/chat/chat_view.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/no_internet_view.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/order_quick_message_sheet.dart';
import '../../widgets/sole_card.dart';
import 'tracking_screen.dart';

/// Customer-facing "My Orders" screen with tab-based status filtering.
///
/// Tabs: All orders | Unpaid | Processing | Shipped | Review | Returns
/// Accepts an optional [initialFilter] so the profile screen can deep-link
/// directly into the correct tab (e.g. tapping "Shipped" opens this screen
/// pre-filtered to the Shipped tab).
class MyOrdersScreen extends StatefulWidget {
  /// Optional initial filter tab. Valid values:
  /// 'all', 'unpaid', 'processing', 'shipped', 'review', 'returns'.
  final String initialFilter;

  const MyOrdersScreen({super.key, this.initialFilter = 'all'});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _bannerDismissed = false;
  StreamSubscription? _connectivitySub;
  bool _wasOffline = false;

  static const _tabs = <_OrderTab>[
    _OrderTab('All orders', 'all'),
    _OrderTab('Unpaid', 'unpaid'),
    _OrderTab('Processing', 'processing'),
    _OrderTab('Shipped', 'shipped'),
    _OrderTab('Review', 'review'),
    _OrderTab('Returns', 'returns'),
  ];

  @override
  void initState() {
    super.initState();
    final initialIndex = _tabs.indexWhere(
      (t) => t.filter == widget.initialFilter,
    );
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<OrderProvider>();
      provider.setMyOrdersFilter(
        _tabs[_tabController.index].filter,
      );
      provider.loadMyOrders();
    });

    // Auto-refresh orders when connection is restored after being offline
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        context.read<OrderProvider>().loadMyOrders();
      }
      _wasOffline = !isOnline;
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    context.read<OrderProvider>().setMyOrdersFilter(
      _tabs[_tabController.index].filter,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'My Orders',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: Stack(
              children: [
                AppConstants.noiseOverlay(opacity: 0.03),
                _buildBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // TAB BAR — scrollable with padding to prevent clipping
  // ════════════════════════════════════════════════════════════════

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: AppConstants.primary,
        indicatorWeight: 3,
        labelColor: AppConstants.secondary,
        unselectedLabelColor: AppConstants.secondary.withValues(alpha: 0.45),
        labelStyle: AppConstants.bodyStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: AppConstants.bodyStyle(
          fontSize: 13,
          fontWeight: FontWeight.normal,
        ),
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // BODY
  // ════════════════════════════════════════════════════════════════

  Widget _buildBody() {
    return Consumer<OrderProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingMyOrders) {
          return ConnectivityService.instance.isOnline
              ? _buildLoading()
              : NoInternetView(
                  onRetry: () => provider.loadMyOrders(),
                );
        }

        if (provider.myOrdersError != null) {
          return _buildError(provider);
        }

        return RefreshIndicator(
          color: AppConstants.primary,
          onRefresh: () => provider.loadMyOrders(),
          child: CustomScrollView(
            slivers: [
              // Promo banner
              if (!_bannerDismissed)
                SliverToBoxAdapter(child: _buildPromoBanner()),

              // Order list or empty state
              if (provider.myOrders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList.builder(
                    itemCount: provider.myOrders.length,
                    itemBuilder: (context, index) {
                      final order = provider.myOrders[index];
                      return _OrderCard(
                        order: order,
                        onTap: () => _navigateToTracking(order),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  // PROMO BANNER
  // ════════════════════════════════════════════════════════════════

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppConstants.primary.withValues(alpha: 0.12),
        ),
        boxShadow: AppConstants.warmShadow,
      ),
      child: Row(
        children: [
          // Truck icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Text(
              'Get Real-Time Order Updates via SMS.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Enable button
          FilledButton.icon(
            onPressed: _handleEnableSms,
            icon: const Icon(Icons.notifications_active, size: 14),
            label: Text(
              'Enable',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.success,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          const SizedBox(width: 4),

          // Dismiss
          GestureDetector(
            onTap: () => setState(() => _bannerDismissed = true),
            child: Icon(
              Icons.close,
              size: 16,
              color: AppConstants.secondary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  void _handleEnableSms() {
    // TODO: Wire up actual SMS opt-in when notification_service supports it.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SMS order updates — coming soon!'),
        backgroundColor: AppConstants.success,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // LOADING STATE — uses project's ShimmerBox pattern
  // ════════════════════════════════════════════════════════════════

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SoleCard(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            shadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShimmerBox(width: 60, height: 14),
                    const Spacer(),
                    const ShimmerBox(width: 50, height: 14),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ShimmerBox(width: 60, height: 60),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ShimmerBox(width: double.infinity, height: 14),
                          const SizedBox(height: 6),
                          const ShimmerBox(width: 100, height: 12),
                          const SizedBox(height: 8),
                          const ShimmerBox(width: 150, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ShimmerBox(width: 80, height: 12),
                    const Spacer(),
                    const ShimmerBox(width: 60, height: 8),
                    const SizedBox(width: 4),
                    const ShimmerBox(width: 60, height: 8),
                    const SizedBox(width: 4),
                    const ShimmerBox(width: 60, height: 8),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ShimmerBox(width: 80, height: 12),
                    const Spacer(),
                    const ShimmerBox(width: 100, height: 30),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ERROR STATE
  // ════════════════════════════════════════════════════════════════

  Widget _buildError(OrderProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppConstants.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load orders',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.myOrdersError ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => provider.loadMyOrders(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                'Retry',
                style: AppConstants.bodyStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // EMPTY STATE — uses project's EmptyStateWidget
  // ════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: EmptyStateWidget(
          icon: Icons.assignment_outlined,
          title: 'It is empty here :-(',
          subtitle: 'No orders found for this category.',
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // NAVIGATION
  // ════════════════════════════════════════════════════════════════

  void _navigateToTracking(Map<String, dynamic> order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(order: order),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Tab data helper
// ══════════════════════════════════════════════════════════════════

class _OrderTab {
  final String label;
  final String filter;
  const _OrderTab(this.label, this.filter);
}

// ══════════════════════════════════════════════════════════════════
// Order Card — Redesigned
// ══════════════════════════════════════════════════════════════════

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    final orderId = order['id'] ?? '';
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = order['created_at']?.toString() ?? '';
    final items = order['order_items'] is List
        ? order['order_items'] as List
        : <dynamic>[];

    // Extract product name, image, size, and quantity from first item
    String productName = '';
    String size = '';
    int quantity = 0;
    String? imageUrl;
    if (items.isNotEmpty) {
      final firstItem = Map<String, dynamic>.from(items.first as Map);
      final product = firstItem['products'];
      if (product is Map) {
        productName = product['name']?.toString() ?? '';
        // Extract image URL from nested product_images (sorted by display_order)
        final productImages = product['product_images'];
        if (productImages is List && productImages.isNotEmpty) {
          final sorted = List<Map<String, dynamic>>.from(
            productImages.map((e) => Map<String, dynamic>.from(e as Map)),
          )..sort((a, b) =>
              (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
          imageUrl = sorted.first['image_url']?.toString();
          if (imageUrl != null && imageUrl.isEmpty) imageUrl = null;
        }
      }
      size = firstItem['size']?.toString() ?? '';
      quantity = (firstItem['quantity'] as num?)?.toInt() ?? 0;
    }

    // Determine progress step index (0-3: pending, processing, shipped, delivered)
    final progressIndex = _getProgressIndex(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SoleCard(
          color: Colors.white,
          padding: const EdgeInsets.all(14),
          shadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          child: Stack(
            children: [
              Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: Order ID + Status chip ─
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Order #${orderId.length >= 8 ? orderId.substring(0, 8) : orderId}',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(status: status),
                ],
              ),

              const SizedBox(height: 12),

              // ── Row 2: Product thumbnail + details ─────────
              Row(
                children: [
                  // Product thumbnail (larger, rounded, subtle border)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppConstants.borderGray.withValues(alpha: 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 64,
                                height: 64,
                                color: AppConstants.primary.withValues(alpha: 0.08),
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        AppConstants.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 64,
                                height: 64,
                                color: AppConstants.primary.withValues(alpha: 0.08),
                                child: const Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 24,
                                  color: AppConstants.primary,
                                ),
                              ),
                            )
                          : Container(
                              width: 64,
                              height: 64,
                              color: AppConstants.primary.withValues(alpha: 0.08),
                              child: const Icon(
                                Icons.shopping_bag_outlined,
                                size: 24,
                                color: AppConstants.primary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName.isNotEmpty ? productName : 'Order',
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (size.isNotEmpty) 'Size: $size',
                            if (quantity > 0) 'Qty: $quantity',
                          ].join(' · '),
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Progress indicator ─────────────────────────
              if (status != 'cancelled') ...[
                const SizedBox(height: 12),
                _OrderProgressStepper(currentIndex: progressIndex),
              ],

              const SizedBox(height: 12),

              // ── Bottom row: Date + Price + Action buttons ─
              Row(
                children: [
                  // Date
                  Text(
                    _formatDate(createdAt),
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                  const Spacer(),
                  // Price
                  Text(
                    '₱${totalAmount.toStringAsFixed(2)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                  // Action button
                  if (_getActionLabel(status) != null) ...[
                    const SizedBox(width: 8),
                    _OrderActionButton(
                      label: _getActionLabel(status)!,
                      status: status,
                      onTap: onTap,
                    ),
                  ],
                ],
              ),
            ],
          ),
              // ── Chat icon (upper right corner) ─
              Positioned(
                top: 0,
                right: 0,
                child: _ChatIconButton(
                  orderId: orderId.toString(),
                  productName: productName,
                  imageUrl: imageUrl,
                  status: status,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Map order status to progress step index (0-3).
  int _getProgressIndex(String status) {
    switch (status) {
      case 'pending':
      case 'placed':
        return 0;
      case 'preparing':
        return 1;
      case 'ready':
        return 2;
      case 'delivered':
      case 'received':
        return 3;
      case 'cancelled':
        return -1;
      default:
        return 0;
    }
  }

  /// Get action button label based on status, or null for no button.
  String? _getActionLabel(String status) {
    switch (status) {
      case 'pending':
      case 'placed':
        return 'Cancel';
      case 'preparing':
        return 'Cancel';
      case 'ready':
        return 'Track';
      case 'delivered':
        return 'Review';
      case 'received':
        return 'Review';
      default:
        return null;
    }
  }

  String _formatDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// ══════════════════════════════════════════════════════════════════
// Status Pill with Icon
// ══════════════════════════════════════════════════════════════════

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final data = _getStatusData(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            data.icon,
            size: 12,
            color: data.color,
          ),
          const SizedBox(width: 4),
          Text(
            data.label.toUpperCase(),
            style: AppConstants.bodyStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: data.color,
            ),
          ),
        ],
      ),
    );
  }

  _StatusData _getStatusData(String status) {
    switch (status) {
      case 'pending':
      case 'placed':
        return _StatusData(
          label: 'Pending',
          color: AppConstants.statusPendingColor,
          icon: Icons.schedule,
        );
      case 'preparing':
        return _StatusData(
          label: 'Processing',
          color: AppConstants.statusConfirmedColor,
          icon: Icons.inventory_2_outlined,
        );
      case 'ready':
        return _StatusData(
          label: 'Ready',
          color: AppConstants.success,
          icon: Icons.check_circle_outline,
        );
      case 'delivered':
      case 'received':
        return _StatusData(
          label: 'Delivered',
          color: AppConstants.statusDeliveredColor,
          icon: Icons.home_outlined,
        );
      case 'cancelled':
        return _StatusData(
          label: 'Cancelled',
          color: AppConstants.error,
          icon: Icons.cancel_outlined,
        );
      default:
        return _StatusData(
          label: status,
          color: AppConstants.secondary,
          icon: Icons.help_outline,
        );
    }
  }
}

class _StatusData {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusData({
    required this.label,
    required this.color,
    required this.icon,
  });
}

// ══════════════════════════════════════════════════════════════════
// Order Progress Stepper — thin horizontal stepper
// ══════════════════════════════════════════════════════════════════

class _OrderProgressStepper extends StatelessWidget {
  final int currentIndex; // 0-3, or -1 for cancelled

  const _OrderProgressStepper({required this.currentIndex});

  static const _steps = ['Pending', 'Processing', 'Shipped', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (index) {
        // Odd indices are lines, even are dots
        if (index.isOdd) {
          // Line between dots
          final lineIndex = index ~/ 2;
          final isCompleted = lineIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppConstants.primary
                    : AppConstants.borderGray.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        } else {
          // Dot
          final dotIndex = index ~/ 2;
          final isActive = dotIndex == currentIndex;
          final isCompleted = dotIndex < currentIndex;
          return Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive || isCompleted
                  ? AppConstants.primary
                  : AppConstants.borderGray.withValues(alpha: 0.4),
              border: isActive
                  ? Border.all(color: AppConstants.primary.withValues(alpha: 0.3), width: 2)
                  : null,
            ),
            child: isCompleted
                ? Icon(Icons.check, size: 6, color: Colors.white)
                : null,
          );
        }
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Order Action Button — compact, status-aware
// ══════════════════════════════════════════════════════════════════

class _OrderActionButton extends StatelessWidget {
  final String label;
  final String status;
  final VoidCallback onTap;

  const _OrderActionButton({
    required this.label,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDestructive = status == 'pending' || status == 'placed' || status == 'preparing';
    final isPrimary = status == 'ready' || status == 'delivered' || status == 'received';

    return SizedBox(
      height: 28,
      child: isPrimary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                label,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: isDestructive ? AppConstants.error : AppConstants.secondary,
                side: BorderSide(
                  color: isDestructive
                      ? AppConstants.error.withValues(alpha: 0.4)
                      : AppConstants.borderGray,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                label,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Chat Icon Button — opens order-specific chat
// ══════════════════════════════════════════════════════════════════

class _ChatIconButton extends StatelessWidget {
  final String orderId;
  final String productName;
  final String? imageUrl;
  final String status;

  const _ChatIconButton({
    required this.orderId,
    required this.productName,
    this.imageUrl,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Message seller',
      child: SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              color: AppConstants.primary,
              size: 18,
            ),
          ),
          onPressed: () => _openOrderChat(context),
        ),
      ),
    );
  }

  Future<void> _openOrderChat(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final customerId = auth.currentUser?['id']?.toString();
    if (customerId == null) return;

    // Get order details to find the storeId and store name
    try {
      final orderData = await Supabase.instance.client
          .from('orders')
          .select('store_id, stores(name)')
          .eq('id', int.tryParse(orderId) ?? orderId)
          .maybeSingle();

      if (orderData == null || !context.mounted) return;
      final storeId = orderData['store_id']?.toString();
      if (storeId == null) return;

      // Extract store name from joined data
      final storeData = orderData['stores'];
      final storeName = (storeData is Map) 
          ? (storeData['name']?.toString() ?? 'Seller') 
          : 'Seller';

      // Get or create conversation
      final conversation = await MessageService.instance.getOrCreateConversation(
        storeId: storeId,
        customerId: customerId,
      );

      if (!context.mounted) return;

      // Check if conversation has messages
      final hasMessages = await MessageService.instance.hasMessages(conversation.id);

      if (!context.mounted) return;

      if (!hasMessages) {
        // No messages yet - show quick message options sheet
        final result = await showQuickMessageSheet(
          context: context,
          orderId: orderId,
          productName: productName,
          imageUrl: imageUrl,
          storeName: storeName,
          orderStatus: status,
        );

        if (result == null || !context.mounted) return;

        // Handle the result
        switch (result.action) {
          case QuickMessageAction.sendMessage:
            // Open chat and send the message
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatView(
                  conversationId: conversation.id,
                  viewerRole: 'customer',
                  otherPartyName: storeName,
                  orderReferenceId: orderId,
                  initialMessage: result.message,
                ),
              ),
            );
            break;
          case QuickMessageAction.requestChange:
            // Open chat with Request a Change flow
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatView(
                  conversationId: conversation.id,
                  viewerRole: 'customer',
                  otherPartyName: storeName,
                  orderReferenceId: orderId,
                  showChangeRequest: true,
                ),
              ),
            );
            break;
          case QuickMessageAction.typeCustom:
            // Open empty thread for custom message
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatView(
                  conversationId: conversation.id,
                  viewerRole: 'customer',
                  otherPartyName: storeName,
                  orderReferenceId: orderId,
                  focusInput: true,
                ),
              ),
            );
            break;
        }
      } else {
        // Messages exist - go straight to chat
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatView(
              conversationId: conversation.id,
              viewerRole: 'customer',
              otherPartyName: storeName,
              orderReferenceId: orderId,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ChatIconButton] Failed to open order chat: $e');
    }
  }
}
