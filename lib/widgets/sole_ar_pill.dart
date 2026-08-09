import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleARPill extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const SoleARPill({
    super.key,
    required this.onPressed,
    this.label = 'Try On in AR',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppConstants.accent.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppConstants.accent,
          foregroundColor: AppConstants.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.remove_red_eye_outlined, // Simple AR / Glasses representation
              color: AppConstants.secondary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
