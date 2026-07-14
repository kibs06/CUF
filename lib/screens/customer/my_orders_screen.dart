import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/no_internet_view.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_status_chip.dart';
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
  // TAB BAR
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
                const ShimmerBox(width: double.infinity, height: 14),
                const SizedBox(height: 8),
                const ShimmerBox(width: 120, height: 12),
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
// Order Card
// ══════════════════════════════════════════════════════════════════

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? '').toString();
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SoleCard(
          color: Colors.white,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: Order ID + Status chip ──────────────
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Order #${orderId.length >= 8 ? orderId.substring(0, 8) : orderId}',
                      style: AppConstants.monoStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SoleStatusChip(status: status),
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 2: Product name + size ─────────────────
              Row(
                children: [
                  // Product thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 48,
                              height: 48,
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
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppConstants.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.shopping_bag_outlined,
                                size: 22,
                                color: AppConstants.primary,
                              ),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppConstants.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 22,
                              color: AppConstants.primary,
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

              const SizedBox(height: 10),

              // ── Row 3: Date + Total ────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(createdAt),
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                  Text(
                    '₱${totalAmount.toStringAsFixed(2)}',
                    style: AppConstants.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
