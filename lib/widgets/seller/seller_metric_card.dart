import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';

class SellerMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color? subtitleColor;
  final bool isLarge;
  final Color valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SellerMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.subtitleColor,
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
          // Hero card gets a subtle gradient (`.card.hero` in the mockup).
          gradient: isLarge
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [SellerTheme.card, SellerTheme.cardHeroEnd],
                )
              : null,
          color: isLarge ? null : SellerTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SellerTheme.cardBorder),
          boxShadow: SellerTheme.cardShadow,
        ),
        // Slightly tighter than the original 14 so a one-third-width card
        // (three across on the dashboard) still fits its eyebrow label.
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Eyebrow label: rust dot + uppercase, tracked-out caption.
            // The label is Flexible so a long one (e.g. "BULK RESERVATIONS"
            // in a one-third-width card) wraps to a second line instead of
            // overflowing the row.
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: SellerTheme.rust,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppConstants.bodyStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: SellerTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isLarge ? 18 : 12),
            Text(
              value,
              // Number typography is intentionally unchanged — only color.
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
                  color: subtitleColor ?? SellerTheme.textMuted,
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
