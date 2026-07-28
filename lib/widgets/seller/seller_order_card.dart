import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import 'seller_status_chip.dart';

class SellerOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onPrimaryAction;
  final VoidCallback onViewDetails;
  final VoidCallback? onReject;
  final bool isUpdating;
  /// When false, the primary action button is hidden and View Details
  /// expands to full width. Used on the Dashboard where status changes
  /// should only happen from the Orders tab / Order Detail screen.
  final bool showPrimaryAction;

  const SellerOrderCard({
    super.key,
    required this.order,
    required this.onPrimaryAction,
    required this.onViewDetails,
    this.onReject,
    this.isUpdating = false,
    this.showPrimaryAction = true,
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
    Color primaryColor;
    switch (status.toLowerCase()) {
      case 'pending':
        primaryLabel = '';
        primaryColor = AppConstants.statusConfirmedColor;
        break;
      case 'preparing':
        primaryLabel = 'Mark Ready';
        primaryColor = AppConstants.statusReadyColor;
        break;
      case 'ready':
        primaryLabel = 'Mark Delivered';
        primaryColor = AppConstants.statusDeliveredColor;
        break;
      case 'received':
        primaryLabel = '';
        primaryColor = AppConstants.accent;
        break;
      case 'cancelled':
        primaryLabel = 'Restore';
        primaryColor = AppConstants.statusPendingColor;
        break;
      default:
        primaryLabel = '';
        primaryColor = AppConstants.statusConfirmedColor;
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
            children: [
              Flexible(
                child: Text(
                  'Order #${id.toString().length >= 8 ? id.toString().substring(0, 8) : id}',
                  style: AppConstants.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
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
          if (primaryLabel.isNotEmpty && showPrimaryAction)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton(
                      onPressed: isUpdating ? null : onPrimaryAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        disabledBackgroundColor: primaryColor.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isUpdating
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
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
                const SizedBox(width: 8),
                // Show Reject button for pending orders
                if (onReject != null && status.toLowerCase() == 'pending')
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: isUpdating ? null : onReject,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppConstants.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Reject',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (onReject == null || status.toLowerCase() != 'pending')
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
          if (primaryLabel.isEmpty || !showPrimaryAction)
              SizedBox(
                height: 36,
                width: double.infinity,
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
        ],
      ),
    );
  }
}
