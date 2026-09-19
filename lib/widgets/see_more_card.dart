import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_brightness.dart';
import '../constants/app_palette.dart';
import 'fit_card.dart';

/// The "See more" cell that closes a capped home grid: the same poster as the
/// size card next to it, saying `See` / `more` over a heavy arrow.
///
/// It is a [FitCard] and nothing else — same fill, edge, radius, DM Sans, same
/// per-line scaling — so it reads as a sibling of the tile that opens the grid
/// rather than as a new component. All this widget adds is the mark
/// ([ArrowGlyph]) and its two motions:
///
///  * **The idle beat.** The arrow invites, so it moves whether or not the
///    customer is touching the card: *hold → glide right → ease back*, then
///    hold again ([SeeMoreCard.idleHold] of stillness between beats). The
///    holds are what make it a beat rather than a hum — a constantly-drifting
///    arrow next to products reads as noise. It is driven by a [Timer]-scheduled
///    controller, not a repeating one, so frames are only produced while the
///    arrow is actually moving (~1s of every ~1.9s), the ticker lives under a
///    [TickerMode] so a covered route mutes it, and it stops entirely when the
///    card is not on screen.
///  * **The press nudge.** The beat's full travel at once, on the fast curve.
///    Pressing also pauses the idle beat ([_IdleNudge] is disabled while
///    pressed, easing back to rest), so the two motions never fight over the
///    same pixels; releasing restarts the beat from its hold.
///
/// Both are skipped when the platform asks for reduced motion
/// (`MediaQuery.disableAnimations`, the convention `hanging_sale_tag.dart`
/// and `sale_price_tape.dart` already follow) — the [InkWell] ripple stays
/// either way.
class SeeMoreCard extends StatefulWidget {
  const SeeMoreCard({super.key, required this.onTap});

  /// Pushes the full shelf. This card only ever appears when there is something
  /// on the other side of it, so the callback is required.
  final VoidCallback onTap;

  /// How far the arrow travels — press and idle beat alike — as a fraction of
  /// the mark's own width. One number, so the two motions can never disagree
  /// about where "forward" is or how far it goes.
  static const double nudge = 0.06;

  /// The idle beat's rhythm: stillness, then the glide out, then the ease
  /// back. Exposed so the card's own test can drive the clock precisely.
  static const Duration idleHold = Duration(milliseconds: 900);
  static const Duration idleGlide = Duration(milliseconds: 550);
  static const Duration idleReturn = Duration(milliseconds: 450);

  @override
  State<SeeMoreCard> createState() => _SeeMoreCardState();
}

class _SeeMoreCardState extends State<SeeMoreCard> {
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
      //
      // The two slides compose: the OUTER one is the press nudge (parent-owned,
      // 150ms), the INNER one the idle beat ([_IdleNudge]'s own ticker). Both
      // are fractions of the mark's own width, so at the moment of a press the
      // arrow reads as continuing forward rather than jumping.
      heroWidget: TickerMode(
        enabled: !reducedMotion,
        child: AnimatedSlide(
          offset: _pressed ? const Offset(SeeMoreCard.nudge, 0) : Offset.zero,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: _IdleNudge(
            enabled: !reducedMotion && !_pressed,
            child: ArrowGlyph(
              color: AppPalette.of(AppBrightness.current).primaryInk,
            ),
          ),
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

/// The idle beat's motor: a timer-scheduled [AnimationController] driving one
/// glide-and-return cycle per beat, living BELOW the card's [TickerMode] so a
/// covered route (or a reduced-motion platform) mutes it for real — a ticker
/// created above the [TickerMode] would keep running regardless.
///
/// Frames are only scheduled while a beat is moving: between beats there is no
/// animation at all, just a [Timer], so an idle home feed is not repainting
/// twice a second for a card the customer is not looking at.
class _IdleNudge extends StatefulWidget {
  const _IdleNudge({required this.enabled, required this.child});

  /// Whether the beat may run. Going false mid-beat eases the arrow back to
  /// rest (150ms) rather than snapping it, which is what makes the press feel
  /// like the arrow continuing forward instead of teleporting.
  final bool enabled;

  final Widget child;

  @override
  State<_IdleNudge> createState() => _IdleNudgeState();
}

class _IdleNudgeState extends State<_IdleNudge>
    with SingleTickerProviderStateMixin {
  /// One cycle: out on [SeeMoreCard.idleGlide], back on [idleReturn]. The
  /// stillness between cycles is a [Timer] — not controller time — so nothing
  /// animates while the arrow waits.
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: SeeMoreCard.idleGlide + SeeMoreCard.idleReturn,
  );

  /// The cycle's shape: a fast ease out to full travel, then a slower ease
  /// back to rest.
  late final Animation<double> _fraction = TweenSequence<double>([
    TweenSequenceItem(
      tween: CurveTween(curve: Curves.easeOutCubic),
      weight: SeeMoreCard.idleGlide.inMilliseconds.toDouble(),
    ),
    TweenSequenceItem(
      tween: CurveTween(
        curve: Curves.easeInOutCubic,
      ).chain(Tween(begin: 1.0, end: 0.0)),
      weight: SeeMoreCard.idleReturn.inMilliseconds.toDouble(),
    ),
  ]).animate(_beat);

  Timer? _holdTimer;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _scheduleBeat();
  }

  @override
  void didUpdateWidget(_IdleNudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _scheduleBeat();
    } else {
      // Eased back to rest by the AnimatedSlide below; the motor just stops
      // contributing.
      _holdTimer?.cancel();
      _holdTimer = null;
      _beat.stop();
      setState(() => _moving = false);
    }
  }

  /// One beat = [SeeMoreCard.idleHold] of stillness, then the cycle. Chained
  /// through [_onBeatEnd], so it loops for as long as it is enabled.
  void _scheduleBeat() {
    _holdTimer?.cancel();
    _holdTimer = Timer(SeeMoreCard.idleHold, _startCycle);
  }

  void _startCycle() {
    if (!mounted || !widget.enabled) return;
    setState(() => _moving = true);
    _beat.forward(from: 0).whenComplete(_onCycleEnd);
  }

  void _onCycleEnd() {
    if (!mounted) return;
    // Runs too when the cycle is cancelled mid-flight (disabled / disposed
    // guard above), which is exactly when we must NOT schedule another.
    setState(() => _moving = false);
    if (widget.enabled) _scheduleBeat();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fraction,
      builder: (context, child) {
        return AnimatedSlide(
          // The same fraction of the mark's width the press nudge travels —
          // the beat's peak IS the pressed offset, by one shared constant.
          offset: Offset(_moving ? _fraction.value * SeeMoreCard.nudge : 0, 0),
          duration: _moving ? Duration.zero : const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: child,
        );
      },
      child: widget.child,
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
