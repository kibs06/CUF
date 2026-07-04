import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_constants.dart';

/// Shows a flying product thumbnail from [sourceKey] to [targetKey] using an Overlay.
///
/// The animation creates a circular thumbnail that detaches from the source widget,
/// travels along a quadratic Bézier arc, shrinks, and fades — then the overlay is
/// automatically removed. No extra packages required; pure Flutter animation APIs.
///
/// Timing rationale:
/// - 600 ms flight duration with `Curves.easeInOutCubic` gives a snappy but
///   Weighted feel (fast in the middle, gentle at start/end).
/// - Scale shrinks from 48 px → ~19 px (0.4×) during flight for depth.
/// - Opacity fades in the last 20 % of the path so the arrival is soft.
class FlyToCartAnimation {
  FlyToCartAnimation._();

  /// Insert an overlay that flies a circular thumbnail from the center of
  /// [sourceKey] to the center of [targetKey].
  ///
  /// [imageUrl] is displayed inside the flying circle (optional — falls back
  /// to a teal bag icon). [onLanded] fires when the animation completes and
  /// the overlay has been removed (ideal place to trigger the cart icon bounce).
  static void show({
    required BuildContext context,
    required GlobalKey sourceKey,
    required GlobalKey targetKey,
    String? imageUrl,
    VoidCallback? onLanded,
  }) {
    final sourceBox =
        sourceKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (sourceBox == null || targetBox == null) return;

    final sourcePos = sourceBox.localToGlobal(Offset.zero);
    final targetPos = targetBox.localToGlobal(Offset.zero);
    final sourceCenter = sourcePos +
        Offset(sourceBox.size.width / 2, sourceBox.size.height / 2);
    final targetCenter = targetPos +
        Offset(targetBox.size.width / 2, targetBox.size.height / 2);

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _FlyingThumbnail(
        source: sourceCenter,
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
// Private flying widget — manages its own AnimationController and overlay
// ---------------------------------------------------------------------------

class _FlyingThumbnail extends StatefulWidget {
  final Offset source;
  final Offset target;
  final String? imageUrl;
  final VoidCallback onComplete;

  const _FlyingThumbnail({
    required this.source,
    required this.target,
    this.imageUrl,
    required this.onComplete,
  });

  @override
  State<_FlyingThumbnail> createState() => _FlyingThumbnailState();
}

class _FlyingThumbnailState extends State<_FlyingThumbnail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
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
  /// Control point sits above the midpoint for a natural "toss" arc.
  Offset _arcPosition(double t) {
    final p0 = widget.source;
    final p2 = widget.target;
    final midX = (p0.dx + p2.dx) / 2;
    final minY = math.min(p0.dy, p2.dy);
    final p1 = Offset(midX, minY - 120); // 120 px above the highest point

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
        final t = _progress.value;
        final pos = _arcPosition(t);
        final size = 48.0 * (1.0 - t * 0.6); // 48 → ~19 px

        return Positioned(
          left: pos.dx - size / 2,
          top: pos.dy - size / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: (1.0 - ((t - 0.7) / 0.3 * 0.8)).clamp(0.0, 1.0),
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
          Icons.shopping_bag,
          size: 20,
          color: Colors.white,
        ),
        errorWidget: (context, url, error) => const Icon(
          Icons.shopping_bag,
          size: 20,
          color: Colors.white,
        ),
      );
    }
    return const Icon(
      Icons.shopping_bag,
      size: 20,
      color: Colors.white,
    );
  }
}
