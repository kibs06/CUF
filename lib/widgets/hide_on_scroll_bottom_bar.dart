import 'package:flutter/material.dart';

/// A bottom bar that gets out of the way.
///
/// While the customer scrolls **down** the bar leaves the screen, so a feed is
/// read full-bleed; the moment they scroll **up** it comes back — that drag is
/// the gesture that means "I want to go somewhere else". Returning to the very
/// top restores it too, because that is where someone who has lost the bar
/// starts looking for it.
///
/// **Why it owns the page as well as the bar.** The bar should only move while
/// the thing above it is actually moving, and the only reliable source for that
/// is the scroll notifications bubbling out of the page's own scrollable — so
/// this widget has to wrap both: [child] (the page) inside a
/// [NotificationListener], [bar] below it.
///
/// **A threshold, and drags only.** Reacting to every pixel would flicker the
/// bar on a slow drag or an overscroll bounce, so it moves only after [threshold]
/// pixels of travel in one direction, and the travel resets the instant the
/// direction reverses — the hysteresis that keeps a dithering drag from adding
/// up to a move. A ballistic fling is ignored outright (`dragDetails == null`),
/// so a list that coasts to its end can never take the bar by itself.
///
/// **The space is given back, not covered up.** The bar collapses
/// ([AnimatedSize], anchored at its top so it slides *down* out of view) and the
/// page grows into the space it leaves. The alternative — sliding the bar over
/// the page — would leave the last row of every list sitting behind it, and the
/// whole point is a full screen.
///
/// Only the page's own vertical scrolling counts: a horizontal strip (the
/// category chips, a product rail) reports a horizontal axis and is ignored.
class HideOnScrollBottomBar extends StatefulWidget {
  const HideOnScrollBottomBar({
    super.key,
    required this.child,
    required this.bar,
    this.resetOn,
    this.threshold = 24,
    this.duration = const Duration(milliseconds: 220),
  });

  /// The page. Scroll notifications from inside it drive the bar.
  final Widget child;

  /// The bottom bar.
  final Widget bar;

  /// When this value changes the bar is brought back, whatever it was doing.
  ///
  /// The shell passes the active tab index, so switching tabs never strands a
  /// customer on a page whose bar is still hidden from the last one's scroll.
  final Object? resetOn;

  /// How far the customer must travel in one direction before the bar moves.
  final double threshold;

  /// How long the bar takes to leave or return.
  final Duration duration;

  @override
  State<HideOnScrollBottomBar> createState() => _HideOnScrollBottomBarState();
}

class _HideOnScrollBottomBarState extends State<HideOnScrollBottomBar> {
  bool _visible = true;

  /// Travel in the current direction that has not yet moved the bar.
  double _travel = 0;

  @override
  void didUpdateWidget(HideOnScrollBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetOn != widget.resetOn) {
      // No setState: this runs inside the rebuild that is already happening.
      _travel = 0;
      _visible = true;
    }
  }

  void _setVisible(bool visible) {
    if (_visible == visible) return;
    setState(() => _visible = visible);
  }

  bool _onScroll(ScrollNotification notification) {
    // A horizontal strip is not the page scrolling.
    if (notification.metrics.axis != Axis.vertical) return false;

    // At the top the bar is restored whatever the direction was: it is how the
    // customer leaves the page, so it is never missing there.
    if (notification.metrics.pixels <= 0) {
      _travel = 0;
      _setVisible(true);
      return false;
    }

    if (notification is! ScrollUpdateNotification) return false;
    // The customer's own drag only — see the class doc on flings.
    if (notification.dragDetails == null) return false;

    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;

    if (delta > 0 && _travel < 0) _travel = 0;
    if (delta < 0 && _travel > 0) _travel = 0;
    _travel += delta;

    if (_travel >= widget.threshold) {
      _travel = 0;
      _setVisible(false);
    } else if (_travel <= -widget.threshold) {
      _travel = 0;
      _setVisible(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: widget.duration,
            curve: Curves.easeOutCubic,
            // Anchored at its own top: the box's bottom edge is pinned to the
            // screen, so as the box collapses its top edge — and the bar with
            // it — travels down and off the view.
            alignment: Alignment.topCenter,
            child: _visible
                ? widget.bar
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}
