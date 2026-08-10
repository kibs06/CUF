import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';

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

    // Espresso/cream palette pairs (see SellerTheme): pending = amber,
    // confirmed = neutral blue, ready/received = sage, cancelled = red.
    Color bg;
    Color text;

    switch (status.toLowerCase()) {
      case 'pending':
        bg = SellerTheme.amberBg;
        text = SellerTheme.amberDark;
        break;
      case 'preparing':
        bg = SellerTheme.blueBg;
        text = SellerTheme.blue;
        break;
      case 'ready':
      case 'received':
        bg = SellerTheme.sageBg;
        text = SellerTheme.sageDark;
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
