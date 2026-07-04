import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SolePrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color textColor;
  final bool isLoading;
  final Widget? icon;

  /// When [expandToFill] is true (default), the button fills its parent's width.
  /// Set to false when placing inside a Row to avoid unbounded width errors.
  final bool expandToFill;

  const SolePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = AppConstants.primary,
    this.textColor = AppConstants.surfaceLight,
    this.isLoading = false,
    this.icon,
    this.expandToFill = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expandToFill ? double.infinity : null,
      height: 52,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: AppConstants.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    icon!,
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: AppConstants.headlineStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
