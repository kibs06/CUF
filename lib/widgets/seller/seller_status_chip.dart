import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerStatusChip extends StatelessWidget {
  final String status;

  const SellerStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    // Map DB status values to seller-friendly display labels and colors.
    // DB stores 'preparing' (shown as 'Confirmed') and 'received' (shown as 'Delivered').
    const dbToUiLabel = <String, String>{
      'pending': 'Pending',
      'preparing': 'Confirmed',
      'ready': 'Ready',
      'received': 'Delivered',
      'cancelled': 'Cancelled',
    };

    Color bg;
    Color text;

    switch (status.toLowerCase()) {
      case 'pending':
        bg = AppConstants.statusPendingColor.withValues(alpha: 0.12);
        text = AppConstants.statusPendingColor;
        break;
      case 'preparing':
        bg = AppConstants.statusConfirmedColor.withValues(alpha: 0.12);
        text = AppConstants.statusConfirmedColor;
        break;
      case 'ready':
        bg = AppConstants.statusReadyColor.withValues(alpha: 0.12);
        text = AppConstants.statusReadyColor;
        break;
      case 'received':
        bg = AppConstants.statusDeliveredColor.withValues(alpha: 0.12);
        text = AppConstants.statusDeliveredColor;
        break;
      case 'cancelled':
        bg = AppConstants.statusCancelledColor.withValues(alpha: 0.12);
        text = AppConstants.statusCancelledColor;
        break;
      default:
        bg = AppConstants.secondary.withValues(alpha: 0.1);
        text = AppConstants.secondary;
    }

    final displayLabel = dbToUiLabel[status.toLowerCase()] ?? status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayLabel.toUpperCase(),
        style: AppConstants.monoStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }
}
