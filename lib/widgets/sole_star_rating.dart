import 'package:flutter/material.dart';

/// Reusable star rating widget.
///
/// Supports both read-only display ([interactive] = false) and
/// tap-to-rate mode ([interactive] = true).
class SoleStarRating extends StatelessWidget {
  /// Current rating (1–5). In interactive mode, this is the selected value.
  final int rating;

  /// Size of each star icon.
  final double size;

  /// When true, tapping a star fires [onRatingChanged].
  final bool interactive;

  /// Callback when the user taps a star. Null in read-only mode.
  final ValueChanged<int>? onRatingChanged;

  /// Color for filled stars.
  final Color activeColor;

  /// Color for empty stars.
  final Color inactiveColor;

  /// Spacing between stars.
  final double spacing;

  const SoleStarRating({
    super.key,
    required this.rating,
    this.size = 18,
    this.interactive = false,
    this.onRatingChanged,
    this.activeColor = const Color(0xFFF59E0B),
    this.inactiveColor = const Color(0xFFD2C7BC),
    this.spacing = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNumber = index + 1;
        final isFilled = starNumber <= rating;

        Widget star = Icon(
          isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: isFilled ? activeColor : inactiveColor,
        );

        if (interactive) {
          star = GestureDetector(
            onTap: () => onRatingChanged?.call(starNumber),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing / 2),
              child: AnimatedScale(
                scale: isFilled ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: star,
              ),
            ),
          );
        } else {
          star = Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing / 2),
            child: star,
          );
        }

        return star;
      }),
    );
  }
}
