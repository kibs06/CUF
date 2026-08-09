import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleStatusChip extends StatelessWidget {
  final String status;

  const SoleStatusChip({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;

    switch (status.toLowerCase()) {
      case 'approved':
      case 'received':
      case 'completed':
      case 'ready':
      case 'fit looks good!':
        bg = AppConstants.success.withOpacity(0.15);
        text = AppConstants.success;
        break;
      case 'pending':
      case 'placed':
      case 'preparing':
      case 'being prepared':
      case 'in_progress':
      case 'tracking your feet...':
        bg = Colors.amber.withOpacity(0.15);
        text = const Color(0xFFC47D00);
        break;
      case 'rejected':
      case 'deactivated':
      case 'failed':
        bg = AppConstants.error.withOpacity(0.15);
        text = AppConstants.error;
        break;
      case 'awaiting_payment_confirmation':
        bg = AppConstants.primary.withOpacity(0.12);
        text = AppConstants.primary;
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
