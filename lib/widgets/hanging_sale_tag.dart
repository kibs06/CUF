import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/sale_tag_provider.dart';

/// A small physical "hang tag" clipped to the top-right corner of a product
/// card — like the cardboard price tags on real clothing.
///
/// Two states (per user + product, driven by [SaleTagProvider]):
///  * **Unrevealed** — a cream tag with a "?" and a gentle amber pulse that
///    invites a tap ("there's a deal here").
///  * **Revealed** — a one-way flip that unfurls the live discount
///    (`-23%`, pulled from `salePercent` each render). Once revealed for a
///    user+product it stays revealed everywhere that product is shown.
///
/// Motion: a slow pendulum swing around the string's anchor point (a barely-
/// noticeable breeze, frozen under reduced-motion settings), a 3D card-flip
/// reveal with a settle bounce and a tiny sparkle burst, and a light haptic.
class HangingSaleTag extends StatefulWidget {
  final String productId;

  /// The live discount percentage (from `salePrice`-aware helpers). Shown on
  /// the revealed face; re-read by the parent each build so a seller changing
  /// the discount updates the number even after the user revealed it.
  final int? salePercent;

  const HangingSaleTag({
    super.key,
    required this.productId,
    this.salePercent,
  });

  @override
  State<HangingSaleTag> createState() => _HangingSaleTagState();
}

class _HangingSaleTagState extends State<HangingSaleTag>
    with TickerProviderStateMixin {
  // ── Motion controllers ───────────────────────────────────────────
  late final AnimationController _swingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final AnimationController _sparkleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  // Resting tilt ~7° off vertical (bottom leaning OUT toward the card edge,
  // like a real tag dangling from the corner), plus a faint ±3° breeze.
  static const double _restingAngle = -0.12;
  static const double _swingAmplitude = 0.055;

  // Pivot = where the string meets the card edge, in widget coordinates.
  static const Offset _anchor = Offset(36, 7);

  bool _reducedMotion = false;
  bool _localRevealed = false; // guest fallback: session-only flip

  // Reveal-transition tracking: the flip plays once, when the reveal flag
  // flips false→true *while mounted* (this tap or the price tape's tap).
  // Mounts that are already revealed, or reveals that arrive via the async
  // provider load, jump straight to the revealed face instead of animating.
  bool _firstBuild = true;
  bool _prevRevealed = false;
  bool _revealScheduled = false;

  /// Read-based revealed check (safe outside build, e.g. tap handlers and
  /// debugFillProperties). Use [context.watch] in build for reactivity.
  bool get _isRevealed =>
      _localRevealed ||
      (context.read<SaleTagProvider?>()?.isRevealed(widget.productId) ?? false);

  @override
  void initState() {
    super.initState();

    _revealController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Settle bounce after the flip lands.
        if (!_reducedMotion) _bounceController.forward(from: 0);
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
        _swingController.stop();
      } else if (!_swingController.isAnimating) {
        _swingController.repeat();
      }
    } else if (!_swingController.isAnimating && !_reducedMotion) {
      _swingController.repeat();
    }

    // Load the user's revealed set once (idempotent per user).
    context.read<SaleTagProvider?>()?.ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant HangingSaleTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      // Grid builders recycle elements: the same State can be re-used for a
      // different product after the user scrolls. Reset every per-product
      // transition flag so the new product starts fresh (unrevealed, no
      // leftover flip/sparkle/bounce).
      _localRevealed = false;
      _firstBuild = true;
      _prevRevealed = false;
      _revealScheduled = false;
      _revealController.reset();
      _bounceController.reset();
      _sparkleController.reset();
    }
  }

  @override
  void dispose() {
    _swingController.dispose();
    _revealController.dispose();
    _bounceController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_isRevealed) return; // one-way transition — never replays

    HapticFeedback.lightImpact();
    // The reveal flag is the single source of truth; the flip plays via the
    // transition handler in build() (which also fires when the price tape
    // triggers the same reveal).
    final provider = context.read<SaleTagProvider?>();
    if (provider != null) {
      provider.reveal(widget.productId); // optimistic + persist
    } else {
      setState(() => _localRevealed = true); // guest: session-only
    }
  }

  /// Called from build when the reveal flag flips false→true while mounted.
  void _scheduleRevealAnimation({required bool wasLoading}) {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reducedMotion || wasLoading) {
        // Reduced motion, or the reveal came from the async provider load:
        // jump straight to the revealed face — never replay the flip.
        _revealController.value = 1.0;
      } else {
        // User-triggered reveal: play the flip (tag leads, tape follows).
        _revealController.forward(from: 0);
        _sparkleController.forward(from: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider here (build) so the face updates reactively when a
    // reveal lands (this tap, another tag, or a provider load).
    final SaleTagProvider? provider = context.watch<SaleTagProvider?>();
    final bool revealed =
        _localRevealed || (provider?.isRevealed(widget.productId) ?? false);
    final int? pct = widget.salePercent;

    // ── Reveal transition (plays the flip exactly once per mount) ──────
    if (_firstBuild) {
      _firstBuild = false;
      if (revealed) {
        _revealController.value = 1.0; // already revealed at mount — jump
      }
    } else if (revealed && !_prevRevealed) {
      _scheduleRevealAnimation(wasLoading: provider?.isLoading ?? false);
    }
    _prevRevealed = revealed;

    final double swingAngle =
        _restingAngle + _swingAmplitude * math.sin(_swingController.value * 2 * math.pi);
    final bool flipInProgress = _revealController.isAnimating;
    // During the flip, the controller drives which face shows; otherwise the
    // stable revealed state (incl. mounts that jump straight to revealed).
    final double flipAngle = flipInProgress
        ? _revealController.value * math.pi
        : (revealed ? math.pi : 0.0);
    final bool showFront = flipAngle < math.pi / 2;

    final String semanticLabel = revealed
        ? (pct != null ? 'On sale, $pct percent off' : 'On sale')
        : 'Sale tag, tap to reveal discount';

    return Semantics(
      button: !revealed,
      label: semanticLabel,
      onTap: revealed ? null : _handleTap,
      excludeSemantics: true,
      child: GestureDetector(
        // Unrevealed: absorb the tap to trigger the reveal. Revealed: become
        // translucent so the tap falls through to the card underneath
        // (navigates to the product) instead of leaving a dead zone.
        behavior: revealed
            ? HitTestBehavior.translucent
            : HitTestBehavior.opaque,
        onTap: revealed ? null : _handleTap,
        child: SizedBox(
          width: 72,
          height: 100,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Pendulum: the whole tag+string swings around the anchor ──
              Transform.rotate(
                angle: swingAngle,
                alignment: Alignment(
                  0,
                  (_anchor.dy - 50) / 50, // pivot near the top of the widget
                ),
                child: SizedBox(
                  width: 72,
                  height: 100,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // String from anchor → grommet (slight catenary sag).
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _StringPainter()),
                        ),
                      ),
                      // Tag body (52×64) + grommet, offset below the anchor.
                      Positioned(
                        left: 8,
                        top: 24,
                        child: SizedBox(
                          width: 52,
                          height: 64,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Positioned.fill(
                                child: CustomPaint(painter: _TagBodyPainter()),
                              ),
                              // ── Flip reveal (front ↔ back face) ────────
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Transform(
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.0012)
                                      ..rotateY(flipAngle),
                                    alignment: Alignment.center,
                                    child: showFront
                                        ? _buildFrontFace()
                                        : Transform(
                                            transform: Matrix4.identity()
                                              ..rotateY(math.pi),
                                            alignment: Alignment.center,
                                            child: _buildBackFace(),
                                          ),
                                  ),
                                ),
                              ),
                              // ── Sparkle burst on reveal ────────────────
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: AnimatedBuilder(
                                    animation: _sparkleController,
                                    builder: (context, child) {
                                      final t = _sparkleController.value;
                                      if (t <= 0 || t >= 1) {
                                        return const SizedBox.shrink();
                                      }
                                      return CustomPaint(
                                        painter: _SparklePainter(progress: t),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              // ── Settle bounce (scale overshoot) ────────
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: AnimatedBuilder(
                                    animation: _bounceController,
                                    builder: (context, child) {
                                      final v = _bounceController.value;
                                      if (v == 0) return const SizedBox.shrink();
                                      // 1 → 1.1 → 1
                                      final scale = v < 0.5
                                          ? 1 + 0.12 * (v / 0.5)
                                          : 1.12 - 0.12 * ((v - 0.5) / 0.5);
                                      return Transform.scale(
                                        scale: scale,
                                        child: child,
                                      );
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Static anchor: the tiny stitch where the string meets the
              //    card edge (drawn above the swinging child, never moves) ──
              Positioned(
                left: _anchor.dx - 3.5,
                top: _anchor.dy - 3.5,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD9A441),
                    border: Border.all(
                      color: AppConstants.secondary.withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Faces ────────────────────────────────────────────────────────

  /// Unrevealed: "SALE" micro-label, a big "?", and a slow amber pulse dot.
  Widget _buildFrontFace() {
    final double pulse = _reducedMotion
        ? 0.5
        : 0.35 + 0.3 * math.sin(_swingController.value * 2 * math.pi + 1.2);
    return _FaceLayout(
      label: 'SALE',
      labelColor: AppConstants.secondary,
      main: '?',
      mainSize: 22,
      mainColor: AppConstants.secondary,
      dotColor: const Color(0xFFFFC107).withValues(alpha: pulse),
      dotGlow: pulse,
    );
  }

  /// Revealed: "OFF" micro-label and the live discount, bold.
  Widget _buildBackFace() {
    final int? pct = widget.salePercent;
    return _FaceLayout(
      label: 'OFF',
      labelColor: const Color(0xFFD9A441),
      main: pct != null ? '-$pct%' : 'SALE',
      mainSize: 15,
      mainColor: AppConstants.error,
      dotColor: const Color(0xFFFFC107),
      dotGlow: 0.0,
    );
  }

}

/// Shared layout for a tag face: micro-label on top, main text center,
/// small dot at the bottom.
class _FaceLayout extends StatelessWidget {
  final String label;
  final Color labelColor;
  final String main;
  final double mainSize;
  final Color mainColor;
  final Color dotColor;
  final double dotGlow;

  const _FaceLayout({
    required this.label,
    required this.labelColor,
    required this.main,
    required this.mainSize,
    required this.mainColor,
    required this.dotColor,
    required this.dotGlow,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Micro label
        Positioned(
          top: 18,
          left: 0,
          right: 0,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: labelColor,
              letterSpacing: 1.4,
            ),
          ),
        ),
        // Main content
        Positioned(
          top: 27,
          left: 0,
          right: 0,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                main,
                style: AppConstants.monoStyle(
                  fontSize: mainSize,
                  fontWeight: FontWeight.bold,
                  color: mainColor,
                ),
              ),
            ),
          ),
        ),
        // Bottom dot (pulses when unrevealed)
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                boxShadow: dotGlow > 0
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFC107)
                              .withValues(alpha: dotGlow * 0.8),
                          blurRadius: 5 * dotGlow + 1,
                          spreadRadius: 1.5 * dotGlow,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────

/// Thin string from the anchor point down to the grommet, with a slight sag.
class _StringPainter extends CustomPainter {
  const _StringPainter();

  static const Offset _grommet = Offset(42, 36);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(_HangingSaleTagState._anchor.dx, _HangingSaleTagState._anchor.dy)
      ..quadraticBezierTo(40.5, 18, _grommet.dx, _grommet.dy);

    // Subtle darker under-stroke for depth.
    canvas.drawPath(
      path.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFD9A441)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StringPainter oldDelegate) => false;
}

/// The tag card: cream gradient body, cut top-right corner, thin border,
/// soft drop shadow, and a punched grommet near the cut corner.
class _TagBodyPainter extends CustomPainter {
  const _TagBodyPainter();

  static final Rect _grommet =
      Rect.fromCircle(center: const Offset(34, 12), radius: 4.6);

  @override
  void paint(Canvas canvas, Size size) {
    const h = 64.0;

    final path = Path()
      ..moveTo(0, 6)
      ..quadraticBezierTo(0, 0, 6, 0)
      ..lineTo(36, 0) // run up to the cut corner
      ..lineTo(52, 16) // angled cut (string side)
      ..lineTo(52, h - 6)
      ..quadraticBezierTo(52, h, 46, h)
      ..lineTo(6, h)
      ..quadraticBezierTo(0, h, 0, h - 6)
      ..close();

    // Soft drop shadow — lifts the tag off the photo beneath it.
    canvas.drawShadow(path, Colors.black87, 4, false);

    // Cream paper gradient.
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF2), Color(0xFFF5E7D0)],
        ).createShader(Offset.zero & size),
    );

    // Thin border (slightly stronger on the cut edge).
    canvas.drawPath(
      path,
      Paint()
        ..color = AppConstants.primary.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // Punched grommet: amber ring + dark "through-hole".
    canvas.drawCircle(
      _grommet.center,
      _grommet.width / 2,
      Paint()
        ..color = const Color(0xFFD9A441)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      _grommet.center,
      _grommet.width / 2 - 1.4,
      Paint()..color = const Color(0xFF4A2A14),
    );
  }

  @override
  bool shouldRepaint(covariant _TagBodyPainter oldDelegate) => false;
}

/// A handful of amber dots radiating outward and fading — the reveal flourish.
class _SparklePainter extends CustomPainter {
  final double progress;

  const _SparklePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = const Color(0xFFFFC107);

    for (var i = 0; i < 4; i++) {
      final angle = -math.pi / 2 + i * (math.pi / 2) + 0.45;
      final dist = 12 + 24 * progress;
      final pos = center + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      paint.color = const Color(0xFFFFC107)
          .withValues(alpha: (1 - progress).clamp(0.0, 1.0));
      canvas.drawCircle(
        pos,
        2.4 - 1.1 * progress,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
