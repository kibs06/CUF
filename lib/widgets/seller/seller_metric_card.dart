import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final bool isLarge;
  final Color valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SellerMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.isLarge = false,
    this.valueColor = AppConstants.secondary,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: isLarge ? 138 : 112),
        decoration: BoxDecoration(
          color: AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppConstants.sellerShadow,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
            SizedBox(height: isLarge ? 18 : 12),
            Text(
              value,
              style: AppConstants.monoStyle(
                fontSize: isLarge ? 28 : 22,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
            ?trailing,
          ],
        ),
      ),
    );
  }
}
