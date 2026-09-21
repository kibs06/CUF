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
  ///
  /// Padding is not the only way to reach 40px: see [targetBelow], which adds
  /// a line to the target instead. Prefer it wherever the dead air would show,
  /// since air is visible and a second line is not.
  ///
  /// **Pad vertically, not horizontally, wherever the price has to line up.**
  /// The padding moves the *price text*, so a horizontal inset shifts the number
  /// away from whatever shares its line — the original price under it, the name
  /// above it, the same price on a card with no sale. The tape's own overhang
  /// does not follow the padding (it is measured from the text), so a caller can
  /// drop the horizontal half and keep the look: the strip is still wider than
  /// the digits, the digits just start where every other line starts.
  final EdgeInsets hitPadding;

  /// A line that belongs with the price and shares the tape's tap target,
  /// without the tape covering it — the strikethrough original price under the
  /// sale price on a catalog card.
  ///
  /// **Why a target needs it at all.** The ≥40px has to come from inside this
  /// widget's own box: Flutter delivers a tap only within every ancestor's
  /// bounds, so slack cannot be borrowed from the parent and no overlay can
  /// reach outside it. On a card, the only 40px available are the price lines
  /// themselves — which is exactly what this is for. With it, the caller can
  /// pass a vertical-only [hitPadding] (`EdgeInsets.symmetric(vertical: 4)` on
  /// the product card) and the price block keeps a card's normal spacing: the
  /// number hugs the content above it and starts on the same left edge as
  /// everything else, and the original hugs the number — where the padding-only
  /// version needed ~26px of dead air around the number that read as a gap in
  /// the card:
  ///
  /// ```
  /// SalePriceTape(
  ///   hitPadding: EdgeInsets.symmetric(vertical: 4),
  ///   targetBelow: Text('₱150.00', style: strikeThrough),
  ///   child: Text('₱100.00', style: salePrice),
  /// )
  /// ```
  ///
  /// The tape's visual still hugs the price alone (its insets are measured
  /// against the price's own box, not the target's), and this line keeps its
  /// own text and its own announcement in the semantics tree. A tap anywhere in
  /// the box — this line included — peels the tape, which is the point of putting
  /// them in one target.
  final Widget? targetBelow;

  /// A widget that belongs on the price's LINE — a product card's category
  /// label — centered against the number itself.
  ///
  /// **Why it has to live here.** Once [targetBelow] is in the box, the box is
  /// two lines tall, so anything a caller centers against it lands on the seam
  /// between the two prices: half the original's line below the number, which is
  /// exactly the "the category didn't align" report. A caller cannot fix that
  /// from outside — the number's line is not its box — and the two ways out are
  /// worse: padding the label's box to the tape's shape makes the block a whole
  /// line taller the moment the label has to take a line of its own (it then
  /// clips the card), and nudging it up with a transform moves it into the
  /// price above when it wraps. So the tape owns it: the label shares the
  /// number's row and is centered on the number's line, or — when the two cannot
  /// share a row — it drops to a line of its own between the number and the
  /// original, exactly as a caller's own row would have made it, and costs the
  /// block no more height than that line.
  ///
  /// It is deliberately **not** part of the tap target: the reveal covers the
  /// number and [targetBelow], which is what a tap on the price means. A tap on
  /// this belongs to the caller (on a card, opening the product).
  final Widget? sameLine;

  const SalePriceTape({
    super.key,
    required this.productId,
    required this.child,
    this.hitPadding = const EdgeInsets.fromLTRB(10, 18, 10, 8),
    this.targetBelow,
    this.sameLine,
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

  // How far the visual tape reaches past the price TEXT on each side. It is a
  // strip pressed over the number, so it is a little wider than the digits and
  // a little taller than their line. Deliberately constants measured from the
  // text rather than derived from [hitPadding]: the padding is the tap target's
  // business, and a caller that pads only vertically — which a card must, so its
  // price lines up with everything above it — must not drag the tape in with it.
  static const double _overhangTop = 8;
  static const double _overhangBottom = 4;
  static const double _overhangSide = 10;

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
          scale = v < 0.5
              ? 1 + 0.05 * (v / 0.5)
              : 1.05 - 0.05 * ((v - 0.5) / 0.5);
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
      // While the tape covers the number, the number itself is not announced —
      // the reveal label is the node a screen reader gets. A line the caller
      // stacked under it ([targetBelow]) is its own text and keeps its own
      // announcement.
      child: showTape ? ExcludeSemantics(child: price) : price,
    );

    // The visual tape hugs the TEXT with a fixed overhang on all four sides, so
    // it never reaches the strikethrough original price that sits below the box
    // on catalog cards, and never grows or shrinks with the padding. Clamped so
    // a caller padding with zero bottom slack still gets a sane (non-inverted)
    // box.
    final double visualTop = (widget.hitPadding.top - _overhangTop).clamp(
      0.0,
      double.infinity,
    );
    final double visualBottom = (widget.hitPadding.bottom - _overhangBottom)
        .clamp(0.0, double.infinity);
    // Horizontally the tape is allowed past the box (the stack does not clip):
    // the strip is wider than the digits, and with no side padding — which is
    // what a card wants — that overhang lands outside the box while the price
    // itself stays flush with the card's other lines.
    final double visualLeft = widget.hitPadding.left - _overhangSide;
    final double visualRight = widget.hitPadding.right - _overhangSide;

    // The price's own box: the covered number and the tape over it. The
    // visual's insets are measured against THIS box (the padded price), so a
    // line the caller puts under the price — see [targetBelow] — shares the tap
    // target without the tape ever growing over it.
    final Widget pricedBox = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        // The covered price (blurred/frosted by the tape above it).
        paddedPrice,
        // Invisible hit area — the whole padded box, so the tap target is
        // comfortably ≥40px without visually oversizing the tape. It exists
        // only while there is tape to peel (a revealed price is just a price).
        if (showTape)
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
        if (showTape)
          Positioned(
            left: visualLeft,
            right: visualRight,
            top: visualTop,
            bottom: visualBottom,
            child: IgnorePointer(
              // Named so a test can measure the strip itself — its overhang is a
              // constant of the text and must not follow the tap padding.
              key: const Key('sale-price-tape-visual'),
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
                      animation: Listenable.merge([
                        _peelController,
                        _shimmerController,
                      ]),
                      builder: (context, child) {
                        final t = _peelController.value;
                        // Phase A: corner lift (tape resists). Phase B: the
                        // tape comes free and flicks off up-right.
                        final phaseA = Curves.easeOut.transform(
                          (t / 0.42).clamp(0.0, 1.0),
                        );
                        final phaseB = Curves.easeIn.transform(
                          ((t - 0.42) / 0.58).clamp(0.0, 1.0),
                        );
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
                              ..translateByDouble(dx, dy, 0.0, 1.0)
                              ..scaleByDouble(scale, scale, scale, 1.0),
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
    );

    // What the tape's box holds: the price, and — when the caller owns a line
    // that belongs with it — that line under it, inside the same tap target.
    //
    // The ≥40px target has to come from inside this widget's own box (a tap
    // outside a box's bounds is never delivered, so slack cannot be borrowed
    // from a parent). On a catalog card the price and its original are the
    // cheapest 40px there is, and putting both in the target is what lets the
    // card keep the block as tight as a card with no sale at all — the padding
    // alone would have to open ~26px of dead air around the number, which reads
    // as a gap in the card.
    // The number's line: the number, and — when the caller has something that
    // belongs beside it ([sameLine]) — that too, in a Wrap so the two share a
    // row while they fit and the label takes its own line when they do not. A
    // Wrap rather than a Row for the reason the card's own row is one: at the
    // largest text scale a number and a label cannot both fit across a two-column
    // card, and the price must never be the thing that shrinks.
    final Widget? alongside = widget.sameLine;
    final Widget priceLine = alongside == null
        ? pricedBox
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: 6,
            children: [pricedBox, alongside],
          );

    final Widget? below = widget.targetBelow;
    final Widget box = below == null
        ? priceLine
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              priceLine,
              // The line below shares the target, and only the line below: as
              // its own hit area instead of one spanning the whole box, so a
              // [sameLine] label beside the number stays the caller's to tap.
              Stack(
                children: [
                  below,
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleTap,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

    if (!showTape) return box;

    return Semantics(
      // Its own node, so the reveal is announced as one phrase rather than
      // merging into whatever the caller put around the price (a line under it
      // would otherwise join the label).
      container: true,
      // A line the caller put under the price is its own node, not a second
      // line of this label.
      explicitChildNodes: below != null,
      button: true,
      label: 'Sale price hidden, tap to reveal',
      onTap: _handleTap,
      // The subtree is dropped wholesale only when the box holds nothing but the
      // covered number (the number is excluded on its own above, so a caller's
      // line under it keeps its own announcement).
      excludeSemantics: below == null,
      child: box,
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
          colors: [Color(0x00FFFFFF), Color(0x45FFFFFF), Color(0x00FFFFFF)],
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
