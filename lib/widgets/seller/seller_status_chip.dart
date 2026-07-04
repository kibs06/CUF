import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerStatusChip extends StatelessWidget {
  final String status;

  const SellerStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;

    switch (status.toLowerCase()) {
      case 'pending':
        bg = AppConstants.statusPendingColor.withOpacity(0.12);
        text = AppConstants.statusPendingColor;
        break;
      case 'confirmed':
        bg = AppConstants.statusConfirmedColor.withOpacity(0.12);
        text = AppConstants.statusConfirmedColor;
        break;
      case 'ready':
        bg = AppConstants.statusReadyColor.withOpacity(0.12);
        text = AppConstants.statusReadyColor;
        break;
      case 'delivered':
        bg = AppConstants.statusDeliveredColor.withOpacity(0.12);
        text = AppConstants.statusDeliveredColor;
        break;
      case 'cancelled':
        bg = AppConstants.statusCancelledColor.withOpacity(0.12);
        text = AppConstants.statusCancelledColor;
        break;
      default:
        bg = AppConstants.secondary.withOpacity(0.1);
        text = AppConstants.secondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: AppConstants.monoStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }
}
