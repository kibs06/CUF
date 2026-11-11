import 'package:flutter/material.dart';

/// Reusable star rating widget.
///
/// Supports both read-only display ([interactive] = false) and
/// tap-to-rate mode ([interactive] = true).
class SoleStarRating extends StatelessWidget {
  /// Current rating (0–5, fractional allowed, e.g. 4.3). Read-only mode
  /// clips the active color to the exact fraction, so halves and
  /// three-quarters render as partially filled stars. In interactive mode
  /// this is the selected whole-star value and taps still snap to ints.
  /// `num` so existing `int` call sites keep compiling.
  final num rating;

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
    // Interactive mode snaps to whole stars; display mode keeps fractions.
    final displayRating =
        interactive ? rating.round().toDouble() : rating.toDouble();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNumber = index + 1;
        // 0..1 of this star that should glow (supports halves, 3/4, …).
        final fill = (displayRating - index).clamp(0.0, 1.0);
        final isFilled = fill >= 1.0;

        Widget star = fill <= 0.0 || isFilled
            ? Icon(
                isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: isFilled ? activeColor : inactiveColor,
              )
            : SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    Icon(
                      Icons.star_outline_rounded,
                      size: size,
                      color: inactiveColor,
                    ),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: Icon(
                          Icons.star_rounded,
                          size: size,
                          color: activeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );

        if (interactive) {
          star = GestureDetector(
            onTap: () => onRatingChanged?.call(starNumber.toInt()),
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
