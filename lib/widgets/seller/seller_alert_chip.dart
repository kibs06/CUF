import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerAlertChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  const SellerAlertChip({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppConstants.statusPendingColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppConstants.statusPendingColor),
            const SizedBox(width: 6),
            Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppConstants.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
