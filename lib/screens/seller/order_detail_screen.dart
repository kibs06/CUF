import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../widgets/seller/seller_status_chip.dart';

class OrderDetailScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final id = order['id'] ?? '';
    final status = order['status'] ?? 'pending';
    final customerName = order['customer_name'] ?? 'Customer';
    final phone = order['customer_phone'] ?? '';
    final itemCount = order['quantity'] ?? 0;
    final totalAmount = (order['total_amount'] is double)
        ? order['total_amount'] as double
        : (order['total_amount'] ?? 0).toDouble();
    final deliveryAddress = order['delivery_address'] ?? 'In-Store POS Handover';
    final paymentMethod = order['payment_method'] ?? 'Cash';
    final size = order['size'] ?? '40';
    final color = order['color'] ?? 'Standard Brown';

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Order #$id',
          style: AppConstants.monoStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and summary
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Order #${id.toString().length >= 8 ? id.toString().substring(0, 8) : id}',
                          style: AppConstants.monoStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SellerStatusChip(status: status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Customer', customerName),
                  if (phone.isNotEmpty) _infoRow('Phone', phone),
                  _infoRow('Items', '$itemCount'),
                  _infoRow('Size', size),
                  _infoRow('Color', color),
                  _infoRow('Fulfillment', deliveryAddress),
                  _infoRow('Payment', paymentMethod),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppConstants.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.secondary,
                        ),
                      ),
                      Text(
                        '\u20B1${totalAmount.toStringAsFixed(0)}',
                        style: AppConstants.monoStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Timeline section
            Text(
              'TIMELINE',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppConstants.sellerCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppConstants.sellerShadow,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _timelineStep('Order Placed', true),
                  _timelineStep('Confirmed', status != 'pending'),
                  _timelineStep('Ready', status == 'ready' || status == 'delivered'),
                  _timelineStep('Delivered', status == 'delivered'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppConstants.bodyStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.bodyStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineStep(String label, bool isComplete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete ? AppConstants.okStockColor : Colors.grey.shade200,
            ),
            child: Icon(
              isComplete ? Icons.check : Icons.circle_outlined,
              size: 14,
              color: isComplete ? Colors.white : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
              color: isComplete ? AppConstants.secondary : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
