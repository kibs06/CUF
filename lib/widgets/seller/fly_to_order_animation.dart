import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_constants.dart';

/// Plays a bouncy "fly to Order" arc from [source] (the POS Add-to-Order
/// button's global position) to [targetKey] (the Order segment in the
/// Products/Order toggle) using a root Overlay entry.
///
/// Design decisions (per the POS add-to-order animation brief):
/// - **Trigger**: fired from `_addLineItem` AFTER the real order state has
///   been updated — the flight is purely cosmetic and never gates or delays
///   the order data.
/// - **Source**: the Add-to-Order button's global center, captured
///   synchronously before the sheet pops. Nothing else is stable at that
///   moment — the sheet is closing and the product grid is replaced by the
///   Order panel as soon as the item is added.
/// - **Path**: quadratic Bézier with the control point well above the
///   midpoint for a natural toss arc; `Curves.easeInOutBack` adds a springy
///   overshoot at both ends (anticipation at takeoff + bounce on landing).
/// - **Landing**: the thumbnail shrinks and fades near the end, an expanding
///   ring flashes at the toggle, then [onLanded] (the toggle pulse) fires.
/// - **Sheet overlap**: the flight starts immediately, overlapping the sheet's
///   own closing animation — the item visually leaves the sheet as it drops,
///   keeping the flight snappy (560 ms, within the brief's 400–700 ms window).
class FlyToOrderAnimation {
  FlyToOrderAnimation._();

  static void show({
    required BuildContext context,
    required Offset source,
    required GlobalKey targetKey,
    String? imageUrl,
    VoidCallback? onLanded,
  }) {
    final targetBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return;

    final targetPos = targetBox.localToGlobal(Offset.zero);
    final targetCenter = targetPos +
        Offset(targetBox.size.width / 2, targetBox.size.height / 2);

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _FlyingOrderItem(
        source: source,
        target: targetCenter,
        imageUrl: imageUrl,
        onComplete: () {
          entry.remove();
          onLanded?.call();
        },
      ),
    );

    overlay.insert(entry);
  }
}

// ---------------------------------------------------------------------------
// Private flying widget — manages its own AnimationController + overlay entry
// ---------------------------------------------------------------------------

class _FlyingOrderItem extends StatefulWidget {
  final Offset source;
  final Offset target;
  final String? imageUrl;
  final VoidCallback onComplete;

  const _FlyingOrderItem({
    required this.source,
    required this.target,
    this.imageUrl,
    required this.onComplete,
  });

  @override
  State<_FlyingOrderItem> createState() => _FlyingOrderItemState();
}

class _FlyingOrderItemState extends State<_FlyingOrderItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );

    // Springy: overshoots slightly at both ends — anticipation at takeoff,
    // a small bounce as the item "lands" in the Order toggle.
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutBack,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Quadratic Bézier arc from source → target.
  /// Control point sits well above the midpoint for a natural "toss" arc.
  Offset _arcPosition(double t) {
    final p0 = widget.source;
    final p2 = widget.target;
    final midX = (p0.dx + p2.dx) / 2;
    final minY = math.min(p0.dy, p2.dy);
    final p1 = Offset(midX, minY - 130); // 130 px above the highest point

    final u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        // EaseInOutBack overshoots past 1.0 near the end — allow the arc and
        // size math to follow it so the item bounces past the toggle briefly.
        final t = _progress.value.clamp(0.0, 1.1);
        final pos = _arcPosition(t);
        final size = 44.0 * (1.0 - t * 0.55); // 44 → ~20 px

        // Expanding landing ring at the toggle, active in the final stretch.
        final ringT = ((t - 0.72) / 0.28).clamp(0.0, 1.0);
        final ringRadius = 14.0 + ringT * 34.0;
        final ringOpacity = (1.0 - ringT) * 0.9;

        return Stack(
          children: [
            // Landing ring — sits under the arriving thumbnail.
            if (ringT > 0 && ringT < 1)
              Positioned(
                left: widget.target.dx - ringRadius,
                top: widget.target.dy - ringRadius,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: ringOpacity,
                    child: Container(
                      width: ringRadius * 2,
                      height: ringRadius * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppConstants.primary,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // The flying thumbnail — shrinks and fades into the toggle.
            Positioned(
              left: pos.dx - size / 2,
              top: pos.dy - size / 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity:
                      (1.0 - ((t - 0.78) / 0.22 * 0.9)).clamp(0.0, 1.0),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppConstants.accent, Color(0xFF3DBDB4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppConstants.accent.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(child: _buildImageContent()),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImageContent() {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Icon(
          Icons.receipt_long,
          size: 18,
          color: Colors.white,
        ),
        errorWidget: (context, url, error) => const Icon(
          Icons.receipt_long,
          size: 18,
          color: Colors.white,
        ),
      );
    }
    return const Icon(
      Icons.receipt_long,
      size: 18,
      color: Colors.white,
    );
  }
}
