import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'sole_card.dart';

class SoleMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String trend;
  final bool isPositiveTrend;
  final IconData icon;
  final Color iconColor;

  const SoleMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.trend,
    this.isPositiveTrend = true,
    required this.icon,
    this.iconColor = AppConstants.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SoleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary.withOpacity(0.6),
                ),
              ),
              Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: AppConstants.monoStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isPositiveTrend ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPositiveTrend ? AppConstants.success : AppConstants.error,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                trend,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isPositiveTrend ? AppConstants.success : AppConstants.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
