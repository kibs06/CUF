import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../services/product_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_status_chip.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadOrders();
    });
  }

  void _updateStatus(dynamic orderId, String currentStatus) async {
    String nextStatus = AppConstants.statusPlaced;
    if (currentStatus == AppConstants.statusPlaced) {
      nextStatus = AppConstants.statusPreparing;
    } else if (currentStatus == AppConstants.statusPreparing) {
      nextStatus = AppConstants.statusReady;
    } else if (currentStatus == AppConstants.statusReady) {
      nextStatus = AppConstants.statusReceived;
    } else {
      return; // already received
    }

    final success = await Provider.of<OrderProvider>(
      context,
      listen: false,
    ).updateOrderStatus(orderId, nextStatus);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order #$orderId advanced to $nextStatus!'),
          backgroundColor: AppConstants.success,
        ),
      );
      // Auto-sync product active status when order is fulfilled
      if (nextStatus == AppConstants.statusReceived) {
        final orders = Provider.of<OrderProvider>(context, listen: false).orders;
        final matches = orders.where((o) => o['id'] == orderId).toList();
        if (matches.isNotEmpty) {
          final order = matches.first;
          final productId = order['product_id']?.toString();
          if (productId != null) {
            try {
              await ProductService.instance.syncProductActiveStatus(productId);
            } catch (_) {
              // Silently fail — status will self-correct on next update
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Workshop Orders Queue',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          orderProvider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppConstants.primary),
                )
              : orderProvider.orders.isEmpty
              ? Center(
                  child: Text(
                    'No orders in queue.',
                    style: AppConstants.bodyStyle(
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  itemCount: orderProvider.orders.length,
                  itemBuilder: (context, index) {
                    final order = orderProvider.orders[index];
                    final id = order['id'];
                    final String status = order['status'];
                    final double total = order['total_amount'] as double;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: SoleCard(
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Order #${id.toString().length >= 8 ? id.toString().substring(0, 8) : id}',
                                    style: AppConstants.monoStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppConstants.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SoleStatusChip(status: status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Size: EU ${order['size']} | Variant: ${order['color']}',
                              style: AppConstants.bodyStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Destination: ${order['delivery_address']}',
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            const Divider(
                              color: AppConstants.borderGray,
                              height: 1,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total: ₱${total.toStringAsFixed(0)}',
                                  style: AppConstants.monoStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                // Button to advance status
                                if (status != AppConstants.statusReceived)
                                  TextButton.icon(
                                    onPressed: () => _updateStatus(id, status),
                                    icon: const Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                    ),
                                    label: Text(
                                      status == AppConstants.statusPlaced
                                          ? 'Start Work'
                                          : 'Complete Craft',
                                      style: AppConstants.bodyStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppConstants.primary,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    'Delivered & Received',
                                    style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      color: AppConstants.success,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
