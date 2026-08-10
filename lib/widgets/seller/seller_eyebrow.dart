import 'package:flutter/material.dart';

import '../../constants/seller_theme_constants.dart';

/// Small-caps eyebrow section label — a small rust dot followed by
/// uppercase, letter-spaced, muted text. Mirrors the `.eyebrow` treatment
/// in the seller dashboard redesign mockup and is used across the seller
/// module for section headers.
class SellerEyebrow extends StatelessWidget {
  final String label;
  final Color? dotColor;
  final Color? textColor;

  const SellerEyebrow(this.label, {super.key, this.dotColor, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: dotColor ?? SellerTheme.rust,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: textColor ?? SellerTheme.textMuted,
          ),
        ),
      ],
    );
  }
}
