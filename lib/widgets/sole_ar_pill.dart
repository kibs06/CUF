import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleARPill extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  /// Fill colour of the pill. Null means the brand accent.
  final Color? background;

  /// Colour of the label drawn on the fill. Null means the secondary ink.
  final Color? foreground;

  const SoleARPill({
    super.key,
    required this.onPressed,
    this.label = 'Try On in AR',
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final background = this.background ?? AppConstants.accent;
    final foreground = this.foreground ?? AppConstants.secondary;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: AppConstants.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        // FittedBox keeps the label on one line inside a narrow slot; the
        // pill itself takes whatever width its parent gives it.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
