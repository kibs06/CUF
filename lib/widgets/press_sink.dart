import 'package:flutter/material.dart';

/// Press feedback for a card that is a `Container`, not a `Material`.
///
/// The product cards paint their edge and their fill on a `Container` inside a
/// plain `Stack`, and neither is a `Material` — an `InkWell`'s ripple paints on
/// the nearest `Material` ancestor, which for these cards is the page *behind*
/// them, so the ripple would be invisible and the tap would look inert. What
/// does read is the card's own shadow: pressed, it tightens and drops toward
/// the page, and the tile reads as sitting down under the finger.
///
/// **The shadow is painted here, not by the card.** It sits on its own
/// [DecoratedBox] directly under the card's box, so the card keeps owning its
/// fill, its radius and its hairline while the press animates only the shadow —
/// and the card is handed to the animation as its `child`, so a press *repaints*
/// a shadow instead of rebuilding a card (and its image, its text and its sale
/// overlay) seven times on the way down.
///
/// **It owns *when* the state is on**, the part that is easy to get subtly
/// wrong: a press can end four ways (`onTapUp`, `onTapCancel`, a finger that
/// drifts off the card, or a lost gesture arena) and every one of them has to
/// clear it, or a card stays sunk after the scroll that started on it. One
/// implementation, every product card.
///
/// The shadow is *lerped*, not swapped: the two lists pair up layer for layer
/// (same length, asserted), which is what `BoxShadow.lerpList` requires and what
/// keeps the press reading as the same shadow moving rather than a second one
/// appearing under the card.
class PressSink extends StatefulWidget {
  const PressSink({
    super.key,
    required this.idle,
    required this.pressed,
    required this.borderRadius,
    required this.child,
    this.onTap,
  }) : assert(
         idle.length == pressed.length,
         'the idle and pressed shadows must pair up layer for layer',
       );

  /// How long the card takes to settle down and back up. Short enough that the
  /// tap still feels immediate, long enough that the shadow is seen moving.
  static const Duration duration = Duration(milliseconds: 110);

  /// Ease out — the card starts moving at once and arrives gently, the same
  /// shape the See-more arrow's nudge uses.
  static const Curve curve = Curves.easeOut;

  /// The lift at rest — `AppConstants.productCardShadow` on the product cards.
  final List<BoxShadow> idle;

  /// The same shadow, tightened: what the card sits on while the finger is on
  /// it. `AppConstants.productCardShadowPressed`.
  final List<BoxShadow> pressed;

  /// The shape the shadow is cast from. Must be the card's own radius, or the
  /// shadow's corners peek out from behind it.
  final BorderRadius borderRadius;

  /// The card itself.
  final Widget child;

  /// Forwarded to the card's own tap handler; null leaves the surface a plain
  /// pressable tile that does nothing on release.
  final VoidCallback? onTap;

  @override
  State<PressSink> createState() => _PressSinkState();
}

class _PressSinkState extends State<PressSink> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (pressed == _pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion gets the state, not the travel: the shadow still changes
    // under the finger, it just does not animate there.
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return GestureDetector(
      // `opaque`: the card must answer a press anywhere on its own surface. The
      // padding bands between its rows are painted by no child, and the default
      // (defer to the child) drops those taps through to the page behind.
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: TweenAnimationBuilder<double>(
        // `end` is the whole state: the builder animates from wherever the
        // shadow is now to the new value, so a re-press mid-release continues
        // from the current depth instead of restarting from rest.
        tween: Tween<double>(end: _pressed ? 1 : 0),
        duration: reduced ? Duration.zero : PressSink.duration,
        curve: PressSink.curve,
        child: widget.child,
        builder: (context, t, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: BoxShadow.lerpList(widget.idle, widget.pressed, t)!,
          ),
          child: child,
        ),
      ),
    );
  }
}
