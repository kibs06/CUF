import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_constants.dart';

/// Plays the "pack the box" add-to-order animation from [source] (the POS
/// Add-to-Order button's global position) to [targetKey] (the Order segment
/// in the Products/Order toggle) using a root Overlay entry.
///
/// Narrative (per the GIF addendum to the pack-the-box brief):
///   1. The product thumbnail appears at the source — the spot where the box
///      will form.
///   2. `assets/animations/box_animation.gif` plays its build-in portion
///      (blank → fully-drawn hexagonal box) around the thumbnail.
///   3. As the box reaches its solid state the thumbnail fades out — the item
///      is now "packed" and occluded by the box.
///   4. The solid box (the fully-drawn GIF frame) flies along an arc to the
///      Order toggle, lands with a bounce, an expanding ring flashes, and
///      [onLanded] fires.
///
/// The GIF is a 150×150 raster with real alpha transparency. Flutter's
/// built-in GIF playback can't scrub/trim frames, so the animation decodes
/// every frame once via `ui.instantiateImageCodec` and drives them itself
/// with the same 1400 ms master controller that runs the item fade and the
/// flight — frame-level control with no new dependencies. The fully-drawn
/// "solid" frame (index 42 of 90, pinned by the test suite) is what flies to
/// the Order toggle; the fade-out tail of the loop is never shown. Its orange
/// color was deliberately accepted as an accent for this animation (user
/// decision — see GIF addendum §0).
///
/// State-update rules from the original add-to-order brief are unchanged:
/// this fires AFTER the real order state has been updated and is purely
/// cosmetic — it never gates or delays the order data. If the GIF fails to
/// decode, the animation degrades to the original thumbnail flight.
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
      builder: (_) => _PackingBoxAnimation(
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
// Private packing widget — decodes the GIF once, then drives its frames plus
// the item fade and the arc flight from one master AnimationController.
// ---------------------------------------------------------------------------

class _PackingBoxAnimation extends StatefulWidget {
  final Offset source;
  final Offset target;
  final String? imageUrl;
  final VoidCallback onComplete;

  const _PackingBoxAnimation({
    required this.source,
    required this.target,
    this.imageUrl,
    required this.onComplete,
  });

  @override
  State<_PackingBoxAnimation> createState() => _PackingBoxAnimationState();
}

class _PackingBoxAnimationState extends State<_PackingBoxAnimation>
    with SingleTickerProviderStateMixin {
  static const String _boxAsset = 'assets/animations/box_animation.gif';

  // Master timeline fractions (of the 1400 ms master).
  static const double _drawInEnd = 0.50; // box fully drawn in → "packed"
  static const double _flightStart = 0.66; // solid box takes off

  /// On-screen box sizes: the drawn-in box, its smaller landing size after
  /// the flight, and the product thumbnail it packs. The GIF is 150 px
  /// native, so 140 px is still a crisp downscale.
  static const double _boxSize = 140.0;
  static const double _flightEndSize = 66.0;
  static const double _itemSize = 76.0;

  /// Index of the fully-drawn "solid" box frame in box_animation.gif.
  /// Measured as the frame with the most opaque pixels (42 of 90) and pinned
  /// by the test suite. Hardcoding it lets the runtime decode skip both the
  /// fade-out tail and every per-frame pixel readback — readbacks are the
  /// slow part, and on-device they previously finished long after the 1 s
  /// animation had already played.
  static const int _solidFrameIndex = 42;

  late final AnimationController _master;
  late final Animation<double> _itemFade; // 0→1 as the box solidifies
  late final Animation<double> _flight; // solid-box arc progress

  final List<ui.Image> _frames = [];
  bool _decodeDone = false;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // The item fades out as the box reaches its solid state (packed).
    _itemFade = CurvedAnimation(
      parent: _master,
      curve: Interval(0.40, 0.56, curve: Curves.easeIn),
    );

    // Flight of the solid box — springy arc + landing bounce (overshoots at
    // both ends, like the original single-flight version).
    _flight = CurvedAnimation(
      parent: _master,
      curve: Interval(_flightStart, 1.0, curve: Curves.easeInOutBack),
    );

    _master.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    // The sequence starts once the GIF frames are decoded (see _decodeFrames)
    // so the box is visible for the whole draw-in. If decoding fails, the
    // master still starts and the medallion fallback carries the animation.
    _decodeFrames();
  }

  /// Decodes only the frames the animation actually shows (0 → solid) — pure
  /// CPU `getNextFrame`, no per-frame pixel readbacks — so it finishes well
  /// inside the draw-in window even on slow devices.
  Future<void> _decodeFrames() async {
    try {
      final bytes = (await rootBundle.load(_boxAsset)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final count = math.min(_solidFrameIndex + 1, codec.frameCount);
        for (var i = 0; i < count; i++) {
          _frames.add((await codec.getNextFrame()).image);
        }
      } finally {
        codec.dispose();
      }
    } catch (e) {
      debugPrint('FlyToOrderAnimation: GIF decode failed: $e');
      // Degraded mode — the medallion fallback covers the flight.
    }
    if (mounted) {
      setState(() => _decodeDone = true);
      _master.forward();
    }
  }

  @override
  void dispose() {
    _master.dispose();
    for (final frame in _frames) {
      frame.dispose();
    }
    super.dispose();
  }

  /// Frame index for the draw-in stage: master progress 0→[_drawInEnd] maps
  /// to frames 0→solid. Beyond that (hold + flight) the solid frame is held.
  /// Guards against the asset having fewer frames than expected.
  int _frameIndex(double progress) {
    if (_frames.isEmpty) return 0;
    final maxIndex = math.min(_solidFrameIndex, _frames.length - 1);
    // Ease the frame advance (slow → fast → slow) so the box draws in
    // smoothly rather than at a constant rate.
    final t = Curves.easeInOutCubic
        .transform((progress / _drawInEnd).clamp(0.0, 1.0));
    return (t * maxIndex).round().clamp(0, maxIndex);
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
      animation: _master,
      builder: (context, _) {
        // easeInOutBack overshoots past 1.0 near the end — allow the arc and
        // size math to follow it so the box bounces past the toggle briefly.
        final flightT = _flight.value.clamp(0.0, 1.1);

        // Before takeoff (_flight.value == 0) this resolves to exactly the
        // source position — the box packs there, then flies off.
        final pos = _arcPosition(flightT);
        // Big box that keeps a good chunk of size through the flight
        // (140 → ~66 px) so the flying box stays legible.
        final boxSize = _boxSize + (_flightEndSize - _boxSize) * flightT;

        final hasBox = _decodeDone && _frames.isNotEmpty;
        final frameImage =
            hasBox ? _frames[_frameIndex(_master.value)] : null;
        final itemOpacity = (1.0 - _itemFade.value).clamp(0.0, 1.0);

        // Expanding landing ring at the toggle, active in the final stretch.
        final ringT = ((flightT - 0.72) / 0.28).clamp(0.0, 1.0);
        final ringRadius = 14.0 + ringT * 34.0;
        final ringOpacity = (1.0 - ringT) * 0.9;

        return Stack(
          children: [
            // Landing ring — sits under the arriving sealed box.
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

            // The product thumbnail at the box center — fades out (packed)
            // as the box reaches its solid state.
            if (itemOpacity > 0)
              Positioned(
                left: widget.source.dx - _itemSize / 2,
                top: widget.source.dy - _itemSize / 2,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: itemOpacity,
                    child: _productMedallion(_itemSize),
                  ),
                ),
              ),

            // The box — GIF frames draw it in around the thumbnail (0→solid),
            // then the solid frame flies to the toggle. Falls back to the
            // product medallion if the GIF hasn't decoded (or failed).
            Positioned(
              left: pos.dx - boxSize / 2,
              top: pos.dy - boxSize / 2,
              child: IgnorePointer(
                child: SizedBox(
                  width: boxSize,
                  height: boxSize,
                  child: frameImage != null
                      ? RawImage(
                          image: frameImage,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        )
                      : _productMedallion(boxSize),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Circular product thumbnail — used both for the item standing at the box
  /// center during the draw-in and as the degraded fallback flying object.
  Widget _productMedallion(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppConstants.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(child: _buildImageContent()),
    );
  }

  Widget _buildImageContent() {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        // Brand-brown icon on the cream circle — white-on-cream is invisible.
        placeholder: (context, url) => const Icon(
          Icons.receipt_long,
          size: 18,
          color: AppConstants.accent,
        ),
        errorWidget: (context, url, error) => const Icon(
          Icons.receipt_long,
          size: 18,
          color: AppConstants.accent,
        ),
      );
    }
    return const Icon(
      Icons.receipt_long,
      size: 18,
      color: AppConstants.accent,
    );
  }
}
