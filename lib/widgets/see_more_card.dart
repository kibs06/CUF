import 'package:flutter/material.dart';

import '../constants/app_brightness.dart';
import '../constants/app_palette.dart';
import 'fit_card.dart';

/// The "See more" cell that closes a capped home grid: the same poster as the
/// size card next to it, saying `See` / `more` over a heavy arrow.
///
/// It is a [FitCard] and nothing else — same fill, edge, radius, DM Sans, same
/// per-line scaling — so it reads as a sibling of the tile that opens the grid
/// rather than as a new component. All this widget adds is the mark ([ArrowGlyph])
/// and the press nudge.
///
/// **The press nudge is the only motion**, and it is skipped when the platform
/// asks for reduced motion (`MediaQuery.disableAnimations`, the convention
/// `hanging_sale_tag.dart` and `sale_price_tape.dart` already follow) — the
/// [InkWell] ripple stays either way.
class SeeMoreCard extends StatefulWidget {
  const SeeMoreCard({super.key, required this.onTap});

  /// Pushes the full shelf. This card only ever appears when there is something
  /// on the other side of it, so the callback is required.
  final VoidCallback onTap;

  @override
  State<SeeMoreCard> createState() => _SeeMoreCardState();
}

class _SeeMoreCardState extends State<SeeMoreCard> {
  /// How far the arrow slides on press, as a fraction of its own width.
  static const double _nudge = 0.06;

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return FitCard(
      lines: const ['See', 'more'],
      // Clay as INK rather than as a fill, the same role the size card's value
      // uses: the pinned `AppConstants.primary` is a fill colour and would be
      // too low-contrast on the dark page.
      heroWidget: AnimatedSlide(
        offset: (_pressed && !reducedMotion)
            ? const Offset(_nudge, 0)
            : Offset.zero,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: ArrowGlyph(
          color: AppPalette.of(AppBrightness.current).primaryInk,
        ),
      ),
      // The arrow is paint, not text, so the label is spelled here — the whole
      // card announces itself as one target for "open everything".
      semanticsLabel: 'See more products',
      onHighlightChanged: (pressed) {
        if (pressed != _pressed) setState(() => _pressed = pressed);
      },
      onTap: widget.onTap,
    );
  }
}

/// A heavy right-pointing arrow, drawn rather than typed: no package, no font
/// glyph, and the stroke weight can stay proportional to the mark at any size.
///
/// Fixed intrinsic size — [FitCard] scales it as a block, so the coordinates
/// below are always the ones painted.
class ArrowGlyph extends StatelessWidget {
  const ArrowGlyph({super.key, required this.color});

  final Color color;

  static const double _width = 140;
  static const double _height = 100;

  @override
  Widget build(BuildContext context) {
    // The mark is decorative on its own: the words and the whole-card target
    // are announced by the card's own semantics.
    return ExcludeSemantics(
      child: SizedBox(
        width: _width,
        height: _height,
        child: CustomPaint(painter: _ArrowPainter(color)),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // One scale from the reference canvas, so the stroke keeps the same
    // proportion to the head at any box size (the box is fixed today, but a
    // painter that only works at one size is a trap for the next change).
    final k = size.width / ArrowGlyph._width;
    double x(double value) => value * k;
    double y(double value) => value * (size.height / (ArrowGlyph._height));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(x(10), y(50))
      ..lineTo(x(126), y(50)) // shaft
      ..moveTo(x(82), y(10))
      ..lineTo(x(126), y(50))
      ..lineTo(x(82), y(90)); // head

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}
