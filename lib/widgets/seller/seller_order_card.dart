import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import 'seller_status_chip.dart';

class SellerOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onPrimaryAction;
  final VoidCallback onViewDetails;

  const SellerOrderCard({
    super.key,
    required this.order,
    required this.onPrimaryAction,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final id = order['id'] ?? '';
    final customerName = order['customer_name'] ?? 'Customer';
    final phone = order['customer_phone'] ?? '';
    final status = order['status'] ?? 'pending';
    final itemCount = order['quantity'] ?? 0;
    final totalAmount = (order['total_amount'] is double)
        ? order['total_amount'] as double
        : (order['total_amount'] ?? 0).toDouble();
    final fulfillmentType = order['fulfillment_type'] ?? 'Walk-in';
    final timeAgo = order['time_ago'] ?? '';

    String primaryLabel;
    switch (status.toLowerCase()) {
      case 'pending':
        primaryLabel = 'Confirm Order';
        break;
      case 'confirmed':
        primaryLabel = 'Mark Ready';
        break;
      case 'ready':
        primaryLabel = 'Mark Delivered';
        break;
      case 'delivered':
        primaryLabel = '';
        break;
      case 'cancelled':
        primaryLabel = 'Restore';
        break;
      default:
        primaryLabel = 'Confirm Order';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppConstants.sellerShadow,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #$id',
                style: AppConstants.monoStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
              Row(
                children: [
                  SellerStatusChip(status: status),
                  const SizedBox(width: 8),
                  Text(
                    timeAgo,
                    style: AppConstants.bodyStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 16, color: AppConstants.borderGray),
          Row(
            children: [
              Expanded(
                child: Text(
                  customerName,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.secondary,
                  ),
                ),
              ),
              if (phone.isNotEmpty)
                GestureDetector(
                  onTap: () {},
                  child: Icon(Icons.phone, size: 16, color: AppConstants.accent),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$itemCount items · ₱${totalAmount.toStringAsFixed(0)}  $fulfillmentType',
            style: AppConstants.bodyStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          if (primaryLabel.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton(
                      onPressed: onPrimaryAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        primaryLabel,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: onViewDetails,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppConstants.borderGray),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'View Details',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
