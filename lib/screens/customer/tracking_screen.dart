import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/sole_status_chip.dart';
import '../../widgets/sole_timeline.dart';
import 'order_review_screen.dart';

/// Unified Order Detail / Tracking screen — content driven by order status.
///
/// Every order notification tap and every My Orders list tap routes here.
/// Shows a timeline, order details, and status-specific action buttons.
class OrderTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderTrackingScreen({super.key, required this.order});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  late Map<String, dynamic> _order;
  bool _isUpdating = false;

  // Status history timestamps (fetched from order_status_history)
  final Map<String, DateTime> _statusTimestamps = {};

  // Order status → timeline step index (5 steps with Part D's 'delivered')
  static const _statusToStep = <String, int>{
    'pending': 0,
    'placed': 0,
    'preparing': 1,
    'ready': 2,
    'delivered': 3,
    'received': 4,
    'cancelled': -1, // special: show cancelled banner
  };

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    _loadStatusHistory();
  }

  /// Fetch order_status_history rows to populate real timestamps.
  Future<void> _loadStatusHistory() async {
    try {
      final data = await Supabase.instance.client
          .from('order_status_history')
          .select('status, changed_at')
          .eq('order_id', _order['id'])
          .order('changed_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _statusTimestamps.clear();
        for (final row in (data as List)) {
          final status = row['status']?.toString() ?? '';
          final changedAt = DateTime.tryParse(row['changed_at']?.toString() ?? '');
          if (status.isNotEmpty && changedAt != null) {
            _statusTimestamps[status] = changedAt;
          }
        }
      });
    } catch (e) {
      // Status history may not exist yet — not fatal, timeline still renders
      debugPrint('[Tracking] Could not load status history: $e');
    }
  }

  String get _currentStatus =>
      (_order['status'] ?? 'pending').toString().toLowerCase();

  int get _activeIndex => _statusToStep[_currentStatus] ?? 0;

  String get _shortId {
    final id = _order['id']?.toString() ?? '';
    return id.length >= 8 ? id.substring(0, 8) : id;
  }

  // ─── Confirm Receipt (Part D) ──────────────────────────────────

  Future<void> _confirmReceipt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Receipt'),
        content: const Text(
          'I confirm that I have received this order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      final success = await context
          .read<OrderProvider>()
          .updateOrderStatus(_order['id'], 'received');

      if (mounted) {
        setState(() {
          _isUpdating = false;
          _order['status'] = 'received';
        });
        _loadStatusHistory(); // refresh timestamps

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order confirmed! Thank you.'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm receipt: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = _currentStatus;
    final items = _order['order_items'] is List
        ? _order['order_items'] as List
        : <dynamic>[];
    final totalAmount =
        (_order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = _order['created_at']?.toString() ?? '';
    final fulfillment =
        (_order['fulfillment'] ?? 'pickup').toString().toLowerCase();

    // Resolve store name from order_items → products → stores, or profiles
    String storeName = 'Artisan Shop';
    if (items.isNotEmpty) {
      final firstItem = Map<String, dynamic>.from(items.first as Map);
      final product = firstItem['products'];
      if (product is Map) {
        storeName = product['name']?.toString() ?? storeName;
      }
    }
    // Fallback: use profiles or a generic name
    if (storeName == 'Artisan Shop') {
      final profile = _order['profiles'];
      if (profile is Map) {
        storeName = profile['full_name']?.toString() ?? 'Artisan Shop';
      }
    }

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Order #$_shortId',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (status == 'received')
            SoleStatusChip(status: status),
        ],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cancelled banner ────────────────────────────
                if (status == 'cancelled') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppConstants.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppConstants.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel_outlined,
                            color: AppConstants.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This order was cancelled.',
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Order header details card ───────────────────
                SoleCard(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  storeName,
                                  style: AppConstants.bodyStyle(
                                    fontSize: 12,
                                    color: AppConstants.secondary
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (items.isNotEmpty) ...[
                                  Text(
                                    '${items.length} item${items.length == 1 ? '' : 's'}',
                                    style: AppConstants.bodyStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            '₱${totalAmount.toStringAsFixed(2)}',
                            style: AppConstants.monoStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Items list
                      ...items.map((item) {
                        final itemMap = Map<String, dynamic>.from(item as Map);
                        final product = itemMap['products'] is Map
                            ? Map<String, dynamic>.from(itemMap['products'] as Map)
                            : null;
                        final productName = product?['name']?.toString() ?? 'Item';
                        final size = itemMap['size']?.toString() ?? '';
                        final qty = (itemMap['quantity'] as num?)?.toInt() ?? 1;
                        final unitPrice =
                            (itemMap['unit_price'] as num?)?.toDouble() ?? 0;

                        // Get image URL from product_images
                        String? imageUrl;
                        if (product != null) {
                          final productImages = product['product_images'];
                          if (productImages is List && productImages.isNotEmpty) {
                            final sorted = List<Map<String, dynamic>>.from(
                              productImages.map(
                                (e) => Map<String, dynamic>.from(e as Map),
                              ),
                            )..sort((a, b) =>
                                (a['display_order'] as int? ?? 0)
                                    .compareTo(b['display_order'] as int? ?? 0));
                            imageUrl = sorted.first['image_url']?.toString();
                          }
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              // Product thumbnail
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppConstants.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          imageUrl,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.shopping_bag_outlined,
                                            size: 20,
                                            color: AppConstants.primary,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.shopping_bag_outlined,
                                        size: 20,
                                        color: AppConstants.primary,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      productName,
                                      style: AppConstants.bodyStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      [
                                        if (size.isNotEmpty) 'Size: $size',
                                        'Qty: $qty',
                                        '₱${unitPrice.toStringAsFixed(0)}',
                                      ].join(' · '),
                                      style: AppConstants.bodyStyle(
                                        fontSize: 11,
                                        color: AppConstants.secondary
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Order Progress Timeline ─────────────────────
                Text(
                  'Order Progress',
                  style: AppConstants.headlineStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),

                SoleCard(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: SoleTimeline(
                    items: _buildTimelineItems(),
                    activeIndex: _activeIndex,
                  ),
                ),

                // ── Status-specific section + action button ─────
                if (_currentStatus != 'cancelled') ...[
                  const SizedBox(height: 24),
                  _buildStatusSection(),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Timeline items with real timestamps from order_status_history ──

  List<SoleTimelineItem> _buildTimelineItems() {
    final status = _currentStatus;
    final placedAt = _formatTimestamp(_statusTimestamps['pending'] ??
        _statusTimestamps['placed'] ??
        DateTime.tryParse(_order['created_at']?.toString() ?? ''));
    final preparingAt = _formatTimestamp(_statusTimestamps['preparing']);
    final readyAt = _formatTimestamp(_statusTimestamps['ready']);
    final deliveredAt = _formatTimestamp(_statusTimestamps['delivered']);
    final receivedAt = _formatTimestamp(_statusTimestamps['received']);

    final fulfillment =
        (_order['fulfillment'] ?? 'pickup').toString().toLowerCase();
    final readyLabel = fulfillment == 'delivery'
        ? 'Out for Delivery'
        : 'Ready for Pickup';
    final readyDesc = fulfillment == 'delivery'
        ? 'Shoe finished, polished, and boxed for delivery.'
        : 'Shoe finished, polished, and boxed for pickup.';

    return [
      SoleTimelineItem(
        title: 'Order Placed',
        description: 'Artisan shop received your craft request.',
        time: placedAt,
      ),
      SoleTimelineItem(
        title: 'Being Prepared',
        description: 'Leather cutting & welt stitching in progress.',
        time: preparingAt,
      ),
      SoleTimelineItem(
        title: readyLabel,
        description: readyDesc,
        time: readyAt,
      ),
      SoleTimelineItem(
        title: 'Delivered',
        description: 'Order handed to courier / arrived at pickup.',
        time: deliveredAt,
      ),
      SoleTimelineItem(
        title: 'Received',
        description: 'Confirmed by you. Wear it in style!',
        time: receivedAt,
      ),
    ];
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $hour:$minute $amPm';
  }

  // ─── Status-specific section + CTA ─────────────────────────────

  Widget _buildStatusSection() {
    final status = _currentStatus;
    final fulfillment =
        (_order['fulfillment'] ?? 'pickup').toString().toLowerCase();

    switch (status) {
      case 'pending':
      case 'placed':
        return _buildInfoCard(
          icon: Icons.hourglass_empty_outlined,
          color: AppConstants.statusPendingColor,
          title: 'Waiting for seller to confirm',
          subtitle: 'Your order is pending seller confirmation.',
          child: null,
        );

      case 'preparing':
        return _buildInfoCard(
          icon: Icons.inventory_2_outlined,
          color: AppConstants.statusConfirmedColor,
          title: 'Your order is being prepared',
          subtitle: 'The artisan is crafting your shoes.',
          child: null,
        );

      case 'ready':
        return _buildInfoCard(
          icon: fulfillment == 'delivery'
              ? Icons.local_shipping_outlined
              : Icons.store_outlined,
          color: AppConstants.statusReadyColor,
          title: fulfillment == 'delivery'
              ? 'Out for Delivery'
              : 'Ready for Pickup',
          subtitle: fulfillment == 'delivery'
              ? 'Your order is on its way.'
              : 'Your order is ready for pickup at the store.',
          child: null,
        );

      case 'delivered':
        return _buildInfoCard(
          icon: Icons.check_circle_outline,
          color: AppConstants.statusDeliveredColor,
          title: 'Your order has arrived',
          subtitle: 'Please confirm that you received it.',
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: double.infinity,
              child: SolePrimaryButton(
                label: _isUpdating ? 'Confirming...' : 'Confirm Receipt',
                onPressed: _isUpdating ? null : _confirmReceipt,
                icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.white),
              ),
            ),
          ),
        );

      case 'received':
        return _buildInfoCard(
          icon: Icons.check_circle,
          color: AppConstants.success,
          title: 'Delivered',
          subtitle: 'Order confirmed. Enjoy your new shoes!',
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: double.infinity,
              child:               OutlinedButton.icon(
                onPressed: () {
                  // Navigate to order review screen which properly handles
                  // per-order-item reviews with all required IDs.
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderReviewScreen(order: _order),
                    ),
                  );
                },
                icon: const Icon(Icons.star_outline, size: 18),
                label: Text(
                  'Rate & Review',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primary,
                  side: const BorderSide(color: AppConstants.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? child,
  }) {
    return SoleCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
