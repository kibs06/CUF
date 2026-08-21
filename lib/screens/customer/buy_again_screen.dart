import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/sole_card.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'tracking_screen.dart';

/// Shopee-style "My Purchases" screen showing order history with tabs.
/// Navigation target of the profile section's "View Details >" link on the
/// Buy Again strip.
///
/// Receives the raw [orders] list (same as BuyAgainSection) and groups them
/// by status into tabs: To Ship | To Receive | Completed | Return/Refund | Cancelled.
class BuyAgainScreen extends StatefulWidget {
  const BuyAgainScreen({
    super.key,
    required this.orders,
    this.onProductOpened,
  });

  final List<Map<String, dynamic>> orders;
  final Future<void> Function()? onProductOpened;

  @override
  State<BuyAgainScreen> createState() => _BuyAgainScreenState();
}

class _BuyAgainScreenState extends State<BuyAgainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<dynamic, Timer> _pendingDeletes = {};

  static const _tabs = <_OrderTab>[
    _OrderTab('To Ship', 'to_ship'),
    _OrderTab('To Receive', 'to_receive'),
    _OrderTab('Completed', 'completed'),
    _OrderTab('Return/Refund', 'return_refund'),
    _OrderTab('Cancelled', 'cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    for (final timer in _pendingDeletes.values) {
      timer.cancel();
    }
    _pendingDeletes.clear();
    _tabController.dispose();
    super.dispose();
  }

  /// Filter orders for a given tab.
  List<Map<String, dynamic>> _filterOrders(String filter) {
    return widget.orders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      switch (filter) {
        case 'to_ship':
          return status == 'pending' ||
              status == 'placed' ||
              status == 'preparing';
        case 'to_receive':
          return status == 'ready';
        case 'completed':
          return status == 'delivered' || status == 'received';
        case 'return_refund':
          return status == 'cancellation_requested';
        case 'cancelled':
          return status == 'cancelled';
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'My Purchases',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppConstants.secondary),
            onPressed: () {
              // TODO: Add search within orders
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((tab) {
                final filtered = _filterOrders(tab.filter);
                return filtered.isEmpty
                    ? _buildEmptyState(tab.label)
                    : _buildOrderList(filtered);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

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

  /// Show a confirmation dialog listing items, then add to cart.
  void _buyAgain(Map<String, dynamic> order) {
    final items = order['order_items'] is List
        ? order['order_items'] as List
        : <dynamic>[];

    // Build preview list for the dialog
    final previewItems = <_CartItemPreview>[];
    for (final item in items) {
      final map = item as Map;
      final product = map['products'];
      final productName =
          product is Map ? (product['name']?.toString() ?? 'Product') : 'Product';
      final size = map['size']?.toString() ?? '';
      final quantity = (map['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = (map['unit_price'] as num?)?.toDouble() ?? 0.0;
      previewItems.add(_CartItemPreview(
        name: productName,
        size: size,
        quantity: quantity,
        price: unitPrice,
      ));
    }

    if (previewItems.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add to Cart',
          style: AppConstants.bodyStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Store name
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _extractStoreName(order),
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Item list
              ...previewItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: AppConstants.bodyStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.size.isNotEmpty)
                            Text(
                              item.size,
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.secondary.withValues(alpha: 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'x${item.quantity}',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '₱${(item.price * item.quantity).toStringAsFixed(2)}',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmBuyAgain(order);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Add to Cart',
              style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _extractStoreName(Map<String, dynamic> order) {
    final storeData = order['stores'];
    if (storeData is Map) {
      return storeData['name']?.toString() ?? 'Store';
    }
    return 'Store';
  }

  /// Actually add items to cart and navigate.
  void _confirmBuyAgain(Map<String, dynamic> order) {
    final cart = context.read<CartProvider>();
    final items = order['order_items'] is List
        ? order['order_items'] as List
        : <dynamic>[];

    String storeId = order['store_id']?.toString() ?? 'unknown';
    String storeName = _extractStoreName(order);

    int addedCount = 0;
    for (final item in items) {
      final map = item as Map;
      final product = map['products'];
      final productId = map['product_id']?.toString();
      if (productId == null || productId.isEmpty) continue;

      final productName =
          product is Map ? (product['name']?.toString() ?? '') : '';
      final size = map['size']?.toString() ?? '';
      final quantity = (map['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = (map['unit_price'] as num?)?.toDouble() ?? 0.0;

      String? imageUrl;
      if (product is Map) {
        final productImages = product['product_images'];
        if (productImages is List && productImages.isNotEmpty) {
          final sorted = List<Map<String, dynamic>>.from(
            productImages.map((e) => Map<String, dynamic>.from(e as Map)),
          )..sort((a, b) =>
              (a['display_order'] as int? ?? 0)
                  .compareTo(b['display_order'] as int? ?? 0));
          imageUrl = sorted.first['image_url']?.toString();
          if (imageUrl != null && imageUrl.isEmpty) imageUrl = null;
        }
      }

      cart.addToCart(
        productId: productId,
        productName: productName,
        imageUrl: imageUrl ?? '',
        price: unitPrice,
        size: size,
        storeId: storeId,
        storeName: storeName,
        quantity: quantity,
      );
      addedCount += quantity;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $addedCount item${addedCount != 1 ? 's' : ''} to cart'),
        backgroundColor: AppConstants.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CartScreen()),
    );
  }

  Widget _buildOrderList(List<Map<String, dynamic>> orders) {
    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: () async {
        if (context.mounted) {
          context.read<OrderProvider>().loadMyOrders();
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final card = _PurchaseOrderCard(
            order: order,
            onTap: () => _navigateToTracking(order),
            onBuyAgain: () => _buyAgain(order),
            onProductTap: (productId) => _openProduct(productId),
          );

          final status = (order['status'] ?? '').toString().toLowerCase();
          if (status != 'cancelled') return card;

          return Slidable(
            key: ValueKey(order['id']),
            startActionPane: ActionPane(
              motion: const BehindMotion(),
              dismissible: DismissiblePane(
                onDismissed: () {
                  HapticFeedback.lightImpact();
                  _swipeDeleteOrder(order);
                },
              ),
              children: [
                SlidableAction(
                  onPressed: (_) {
                    HapticFeedback.lightImpact();
                    _swipeDeleteOrder(order);
                  },
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
            child: card,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String tabName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: EmptyStateWidget(
          icon: Icons.shopping_bag_outlined,
          title: 'No orders here yet',
          subtitle: 'Your $tabName orders will appear here.',
        ),
      ),
    );
  }

  void _navigateToTracking(Map<String, dynamic> order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(order: order),
      ),
    );
  }

  /// Look up the full product from the catalog and open ProductDetailScreen.
  void _openProduct(String productId) {
    final productProvider = context.read<ProductProvider>();
    final product = productProvider.products
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (p) => p?['id']?.toString() == productId,
          orElse: () => null,
        );
    if (product == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  void _swipeDeleteOrder(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    if (status != 'cancelled') return;

    final orderId = order['id'];
    if (_pendingDeletes.containsKey(orderId)) return;

    final provider = Provider.of<OrderProvider>(context, listen: false);
    final deleted = provider.deleteMyOrder(orderId);
    if (deleted == null) return;

    final timer = Timer(const Duration(seconds: 4), () {
      _pendingDeletes.remove(orderId);
      provider.permanentlyDeleteMyOrder(deleted);
    });
    _pendingDeletes[orderId] = timer;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Order deleted — undo available for 4s'),
        duration: const Duration(seconds: 4),
        backgroundColor: AppConstants.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppConstants.primary,
          onPressed: () {
            timer.cancel();
            _pendingDeletes.remove(orderId);
            provider.restoreMyOrder(deleted);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
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
// Purchase Order Card — Shopee-style with store header, product list
// ══════════════════════════════════════════════════════════════════

class _PurchaseOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  final VoidCallback onBuyAgain;
  final void Function(String productId) onProductTap;

  const _PurchaseOrderCard({
    required this.order,
    required this.onTap,
    required this.onBuyAgain,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final items = order['order_items'] is List
        ? order['order_items'] as List
        : <dynamic>[];

    // Extract store name — orders may or may not have stores join
    String storeName = 'Store';
    final storeData = order['stores'];
    if (storeData is Map) {
      storeName = storeData['name']?.toString() ?? 'Store';
    } else {
      // Fallback: try store_id or generic label
      storeName = 'Store';
    }

    // Count total items
    int totalItems = 0;
    for (final item in items) {
      final map = item as Map;
      totalItems += (map['quantity'] as num?)?.toInt() ?? 0;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SoleCard(
        color: Colors.white,
        padding: EdgeInsets.zero,
        shadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        child: Column(
          children: [
            // ── Store header: store name + status ─
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Store icon
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppConstants.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.storefront_outlined,
                      size: 16,
                      color: AppConstants.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Store name
                  Expanded(
                    child: Text(
                      storeName,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Status badge
                  _OrderStatusBadge(status: status),
                ],
              ),
            ),

            // ── Product items ─
            ...items.map((item) {
              final map = item as Map;
              final product = map['products'];
              final productName =
                  product is Map ? (product['name']?.toString() ?? '') : '';
              final size = map['size']?.toString() ?? '';
              final quantity = (map['quantity'] as num?)?.toInt() ?? 0;


              // Extract image URL
              String? imageUrl;
              if (product is Map) {
                final productImages = product['product_images'];
                if (productImages is List && productImages.isNotEmpty) {
                  final sorted = List<Map<String, dynamic>>.from(
                    productImages.map(
                        (e) => Map<String, dynamic>.from(e as Map)),
                  )..sort((a, b) =>
                      (a['display_order'] as int? ?? 0)
                          .compareTo(b['display_order'] as int? ?? 0));
                  imageUrl = sorted.first['image_url']?.toString();
                  if (imageUrl != null && imageUrl.isEmpty) imageUrl = null;
                }
              }

              // Get product ID for navigation
              final productId = map['product_id']?.toString() ?? '';

              return GestureDetector(
                onTap: productId.isNotEmpty
                    ? () => onProductTap(productId)
                    : onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // Product image
                      _ProductThumbnail(imageUrl: imageUrl),
                      const SizedBox(width: 12),
                      // Product details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName.isNotEmpty
                                  ? productName
                                  : 'Product',
                              style: AppConstants.bodyStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (size.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                size,
                                style: AppConstants.bodyStyle(
                                  fontSize: 12,
                                  color: AppConstants.secondary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Quantity
                      if (quantity > 0)
                        Text(
                          'x$quantity',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),

            // ── Price + Total ─
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'Total $totalItems item${totalItems != 1 ? 's' : ''}: ',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '₱${totalAmount.toStringAsFixed(2)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Divider ─
            const Divider(height: 1, color: Color(0xFFF0F0F0)),

            // ── Buy Again button ─
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onBuyAgain,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primary,
                      side: const BorderSide(color: AppConstants.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      'Buy Again',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Order Status Badge
// ══════════════════════════════════════════════════════════════════

class _OrderStatusBadge extends StatelessWidget {
  final String status;

  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _getStatusInfo(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  (String, Color) _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
      case 'placed':
        return ('To Ship', AppConstants.statusPendingColor);
      case 'preparing':
        return ('Preparing', AppConstants.statusConfirmedColor);
      case 'ready':
        return ('Shipped', AppConstants.success);
      case 'delivered':
      case 'received':
        return ('Completed', AppConstants.statusDeliveredColor);
      case 'cancellation_requested':
        return ('Return/Refund', Colors.orange);
      case 'cancelled':
        return ('Cancelled', AppConstants.error);
      default:
        return (status.toUpperCase(), AppConstants.secondary);
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// Product Thumbnail
// ══════════════════════════════════════════════════════════════════

class _ProductThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _ProductThumbnail({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: imageUrl != null
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 72,
                  height: 72,
                  color: AppConstants.primary.withValues(alpha: 0.06),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(AppConstants.primary),
                      ),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 72,
                  height: 72,
                  color: AppConstants.primary.withValues(alpha: 0.06),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    size: 28,
                    color: AppConstants.primary,
                  ),
                ),
              )
            : Container(
                width: 72,
                height: 72,
                color: AppConstants.primary.withValues(alpha: 0.06),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  size: 28,
                  color: AppConstants.primary,
                ),
              ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Cart preview item for confirmation dialog
// ══════════════════════════════════════════════════════════════════

class _CartItemPreview {
  final String name;
  final String size;
  final int quantity;
  final double price;

  const _CartItemPreview({
    required this.name,
    required this.size,
    required this.quantity,
    required this.price,
  });
}
