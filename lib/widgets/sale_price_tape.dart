import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/sale_tag_provider.dart';

/// A strip of "tape" stuck over a product's sale price, hiding the discounted
/// number until the customer peels it off.
///
/// **Independent reveal from the hanging sale tag (confirmed decision —
/// Option B):** the tape reads its OWN per-user + per-product flag from
/// [SaleTagProvider] (`isTapeRevealed`/`revealTape`); the tag's flag is never
/// consulted here, so peeling the tape has zero effect on the tag and vice
/// versa. The original (strikethrough) price line is untouched — only the
/// sale-price line is covered, and it stays covered until the user reveals
/// it.
///
/// Visuals: a slightly-rotated, semi-transparent frosted strip with torn short
/// edges, a soft drop shadow, a glossy sheen, faint fiber lines and a slow
/// idle shimmer. The peel is a corner lift (right end detaches first) followed
/// by an accelerating flick off to the side, with a light haptic at detach and
/// a tiny settle bounce on the price as the tape clears it.
///
/// The tape is a pure overlay (`Positioned` in a `Stack`) so the price block's
/// footprint/height never changes between the covered and revealed states —
/// the space for the price is reserved from the start.
class SalePriceTape extends StatefulWidget {
  final String productId;

  /// The sale-price widget (a `Text`). It is always in the tree — the tape
  /// just covers it; peeling moves the tape away, never fades the number in.
  final Widget child;

  /// Padding of the price box that doubles as the tap target. The box is
  /// padded so the hit area meets the ~40px minimum even though the tape
  /// visual stays small (tap target via hit-test padding, never by visually
  /// oversizing the tape). Mostly dead air above the price by default; pass
  /// a smaller top padding where the price must sit tight against content
  /// below (e.g. the detail screen's bottom-aligned row, where the original
  /// price sits beside the sale price). The same padded box is used in both
  /// the covered and revealed states, so the layout never reflows.
  final EdgeInsets hitPadding;

  const SalePriceTape({
    super.key,
    required this.productId,
    required this.child,
    this.hitPadding = const EdgeInsets.fromLTRB(10, 18, 10, 8),
  });

  @override
  State<SalePriceTape> createState() => _SalePriceTapeState();
}

class _SalePriceTapeState extends State<SalePriceTape>
    with TickerProviderStateMixin {
  late final AnimationController _peelController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _settleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final AnimationController _shimmerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  // Resting tilt of the stuck-on tape (~3.5°).
  static const double _baseAngle = -0.06;

  int get _seed => widget.productId.hashCode;

  bool _reducedMotion = false;
  bool _localRevealed = false; // guest fallback: session-only flip

  // Reveal-transition tracking (mirrors HangingSaleTag). The peel plays once,
  // when the reveal flag flips false→true *while mounted*. Mounts already
  // revealed, or reveals arriving via the async provider load, jump straight
  // to revealed (never a wall of peels on catalog load).
  bool _firstBuild = true;
  bool _prevRevealed = false;
  bool _peelRequested = false;
  bool _peelComplete = false;
  bool _hapticFired = false;

  /// Read-based revealed check (safe in tap handlers).
  bool get _isRevealed {
    final provider = context.read<SaleTagProvider?>();
    return _localRevealed ||
        (provider?.isTapeRevealed(widget.productId) ?? false);
  }

  @override
  void initState() {
    super.initState();

    // Haptic the instant the tape fully detaches (~halfway through the peel).
    _peelController.addListener(() {
      if (!_hapticFired && _peelController.value > 0.5) {
        _hapticFired = true;
        HapticFeedback.lightImpact();
      }
    });
    _peelController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Tape fully gone → settle bounce on the revealed price.
        setState(() => _peelComplete = true);
        if (!_reducedMotion) _settleController.forward(from: 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (motion != _reducedMotion) {
      _reducedMotion = motion;
      if (_reducedMotion) {
        _shimmerController.stop();
      } else if (!_shimmerController.isAnimating) {
        _shimmerController.repeat();
      }
    } else if (!_shimmerController.isAnimating && !_reducedMotion) {
      _shimmerController.repeat();
    }

    // Load the user's revealed set once (idempotent per user).
    context.read<SaleTagProvider?>()?.ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant SalePriceTape oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      // Grid builders recycle elements: the same State can be re-used for a
      // different product after the user scrolls. Reset every per-product
      // transition flag so the new product starts fresh (covered, unrevealed,
      // no stale local reveal, no leftover peel/settle).
      _localRevealed = false;
      _firstBuild = true;
      _prevRevealed = false;
      _peelRequested = false;
      _peelComplete = false;
      _hapticFired = false;
      _peelController.reset();
      _settleController.reset();
    }
  }

  @override
  void dispose() {
    _peelController.dispose();
    _settleController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_isRevealed) return; // one-way — never replays

    // The tape's OWN reveal flag is the source of truth; the peel fires via
    // the transition handler in build(). This deliberately does NOT touch
    // the hanging tag's flag (independent interactions — Option B).
    final provider = context.read<SaleTagProvider?>();
    if (provider != null) {
      provider.revealTape(widget.productId); // optimistic + persist
    } else {
      setState(() => _localRevealed = true); // guest: session-only
    }
  }

  /// Called from build when the tape's reveal flag flips false→true while
  /// mounted. The peel starts on the next frame — no stagger: the tape is
  /// its own interaction, independent of the hanging tag (Option B).
  void _schedulePeel({required bool wasLoading}) {
    if (_peelRequested) return;
    if (_reducedMotion || wasLoading) return; // instant swap, no peel

    _peelRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _peelController.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SaleTagProvider? provider = context.watch<SaleTagProvider?>();
    final bool revealed =
        _localRevealed || (provider?.isTapeRevealed(widget.productId) ?? false);

    // ── Reveal transition (plays the peel exactly once per mount) ──────
    if (_firstBuild) {
      _firstBuild = false;
    } else if (revealed && !_prevRevealed) {
      _shimmerController.stop();
      _schedulePeel(wasLoading: provider?.isLoading ?? false);
    }
    _prevRevealed = revealed;

    final bool showTape = !revealed || (_peelRequested && !_peelComplete);

    // The price itself — always in the tree, with a tiny settle bounce as the
    // tape clears it.
    final Widget price = AnimatedBuilder(
      animation: _settleController,
      builder: (context, child) {
        final v = _settleController.value;
        final double scale;
        if (v <= 0 || v >= 1) {
          scale = 1.0;
        } else {
          scale = v < 0.5 ? 1 + 0.05 * (v / 0.5) : 1.05 - 0.05 * ((v - 0.5) / 0.5);
        }
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );

    // The price sits in a box padded to a comfortable ≥40px tap target (the
    // tape visual stays small and hugs the text — the padding is mostly dead
    // air above the price). The SAME padded box is returned in the revealed
    // state, so the layout never reflows when the tape comes off.
    final Widget paddedPrice = Padding(
      padding: widget.hitPadding,
      child: price,
    );

    if (!showTape) return paddedPrice;

    // The visual tape hugs the text with ~8px overhang above and ~4px below,
    // inside the padded box — so it never reaches the strikethrough original
    // price that sits below the box on catalog cards. Clamped so a caller
    // padding with zero bottom slack still gets a sane (non-inverted) box.
    final double visualTop =
        (widget.hitPadding.top - 8).clamp(0.0, double.infinity);
    final double visualBottom =
        (widget.hitPadding.bottom - 4).clamp(0.0, double.infinity);

    return Semantics(
      button: true,
      label: 'Sale price hidden, tap to reveal',
      onTap: _handleTap,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          // The covered price (blurred/frosted by the tape above it).
          paddedPrice,
          // Invisible hit area — the whole padded box, so the tap target is
          // comfortably ≥40px without visually oversizing the tape.
          Positioned.fill(
            child: GestureDetector(
              key: const Key('sale-price-tape-overlay'),
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              child: const SizedBox.expand(),
            ),
          ),
          // The visual tape (shadow + peeled/shimmering strip) — purely
          // decorative (IgnorePointer), hugging the price text with a small
          // overhang so it reads as real tape without swallowing the original
          // price line.
          Positioned(
            left: 0,
            right: 0,
            top: visualTop,
            bottom: visualBottom,
            child: IgnorePointer(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Static shadow at the tape's rest position — when the tape
                  // lifts, the shadow stays put, selling the "lifted off the
                  // surface" read.
                  const Positioned.fill(
                    child: CustomPaint(painter: _TapeShadowPainter()),
                  ),
                  // The peeled/shimmering tape.
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge(
                        [_peelController, _shimmerController],
                      ),
                      builder: (context, child) {
                        final t = _peelController.value;
                        // Phase A: corner lift (tape resists). Phase B: the
                        // tape comes free and flicks off up-right.
                        final phaseA = Curves.easeOut
                            .transform((t / 0.42).clamp(0.0, 1.0));
                        final phaseB = Curves.easeIn
                            .transform(((t - 0.42) / 0.58).clamp(0.0, 1.0));
                        final dx = phaseA * 5 + phaseB * 54;
                        final dy = phaseA * -3 + phaseB * -44;
                        final tilt = phaseA * 0.5; // 3D lift toward viewer
                        final spin = _baseAngle + phaseB * 1.15;
                        final scale = 1.0 - phaseB * 0.14;
                        final opacity = t < 0.85
                            ? 1.0
                            : (1.0 - (t - 0.85) / 0.15).clamp(0.0, 1.0);

                        return Opacity(
                          opacity: opacity,
                          child: Transform(
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0012)
                              ..rotateX(tilt)
                              ..rotateZ(spin)
                              ..translate(dx, dy)
                              ..scale(scale),
                            alignment: Alignment.center,
                            // Corner lift: the RIGHT end detaches first.
                            child: Transform.rotate(
                              angle: -phaseA * 0.5,
                              alignment: Alignment.centerLeft,
                              child: _buildTapeVisual(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The tape material: torn strip (clipped) + frosted blur over whatever is
  /// behind it + the paper/gloss/fiber details.
  Widget _buildTapeVisual() {
    return ClipPath(
      clipper: _TapeClipper(seed: _seed),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1.8, sigmaY: 1.8),
        child: AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            return CustomPaint(
              painter: _TapePainter(
                seed: _seed,
                shimmerX: _reducedMotion ? 0 : _shimmerController.value,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

// ── Shape helpers ───────────────────────────────────────────────────

/// The torn strip shape: straight-ish top/bottom, jagged left/right ends.
/// Seeded per product so each tape's tears are a little different but stable
/// across rebuilds.
Path _tapeShape(Size size, int seed) {
  final r = math.Random(seed);
  final w = size.width;
  final h = size.height;
  const inset = 3.0;
  final x0 = inset;
  final x1 = w - inset;
  final y0 = inset;
  final y1 = h - inset;
  const steps = 6;

  Offset point(double fx, double fy, double amp) => Offset(
        fx + (r.nextDouble() - 0.5) * amp,
        fy + (r.nextDouble() - 0.5) * amp,
      );

  final pts = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    pts.add(point(x0 + (x1 - x0) * i / steps, y0, 1.2)); // top
  }
  for (var i = 1; i <= steps; i++) {
    pts.add(point(x1, y0 + (y1 - y0) * i / steps, 4.6)); // right (torn)
  }
  for (var i = 1; i <= steps; i++) {
    pts.add(point(x1 - (x1 - x0) * i / steps, y1, 1.2)); // bottom
  }
  for (var i = 1; i <= steps; i++) {
    pts.add(point(x0, y1 - (y1 - y0) * i / steps, 4.6)); // left (torn)
  }

  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

class _TapeClipper extends CustomClipper<Path> {
  final int seed;
  const _TapeClipper({required this.seed});

  @override
  Path getClip(Size size) => _tapeShape(size, seed);

  @override
  bool shouldReclip(covariant _TapeClipper oldDelegate) =>
      oldDelegate.seed != seed;
}

// ── Painters ───────────────────────────────────────────────────────

/// Soft shadow sitting at the tape's rest position (stays put while the tape
/// lifts, so the peel reads as physically leaving the surface).
class _TapeShadowPainter extends CustomPainter {
  const _TapeShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 3, size.width - 4, size.height - 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _TapeShadowPainter oldDelegate) => false;
}

/// The tape material: frosted paper fill, diagonal gloss sheen, faint fiber
/// lines, an idle shimmer band, and a thin torn-edge outline.
class _TapePainter extends CustomPainter {
  final int seed;
  final double shimmerX; // 0..1 idle sweep position (0 = no shimmer)

  const _TapePainter({required this.seed, required this.shimmerX});

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _tapeShape(size, seed);
    canvas.save();
    canvas.clipPath(shape);

    // Frosted warm-cream fill (translucent — the blurred price shows through
    // as a smudge, signalling a number without revealing it).
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF2DC), Color(0xFFEFE0C3)],
        ).createShader(Offset.zero & size),
    );

    // Glossy diagonal sheen (tape is a little shiny).
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x00FFFFFF),
            Color(0x45FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Faint horizontal fiber lines.
    final fiber = Paint()
      ..color = AppConstants.primary.withValues(alpha: 0.07)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (final y in [
      size.height * 0.32,
      size.height * 0.58,
      size.height * 0.82,
    ]) {
      final p = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * 0.5, y + 0.9, size.width, y);
      canvas.drawPath(p, fiber);
    }

    // Idle shimmer: a diagonal highlight band sweeping slowly across — the
    // "this is interactive" affordance (subtle, no busy labels on small cards).
    if (shimmerX > 0) {
      final x = (shimmerX - 0.25) * (size.width + 60);
      canvas.save();
      canvas.rotate(-0.45);
      canvas.drawRect(
        Rect.fromLTWH(x, -size.height, 16, size.height * 3),
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
      canvas.restore();
    }

    canvas.restore();

    // Thin torn-edge outline so the strip reads as paper, not a UI bar.
    canvas.drawPath(
      shape,
      Paint()
        ..color = AppConstants.secondary.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _TapePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.shimmerX != shimmerX;
}
