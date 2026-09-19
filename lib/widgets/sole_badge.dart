import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;

  /// Ink on the badge's fill. Nullable so the constructor stays `const`;
  /// resolves to [AppConstants.inkInverse] — a badge sits on a coloured fill,
  /// so its ink must not follow the page.
  final Color? textColor;
  final IconData? icon;
  final EdgeInsetsGeometry? padding;

  const SoleBadge({
    super.key,
    required this.label,
    this.backgroundColor = AppConstants.primary,
    this.textColor,
    this.icon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: textColor ?? AppConstants.inkInverse,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
