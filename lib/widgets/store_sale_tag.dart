import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/store_sale.dart';

/// The Stores tab's sale indicator: a hang tag, at pill scale.
///
/// It borrows the **motif** of the product card's `HangingSaleTag` — cream
/// paper, a cut top-right corner, a punched amber grommet — not that widget.
/// The product tag is 72×100 and its tap *reveals* a discount (one-way, backed
/// by `SaleTagProvider`); this one is an 80×30 pill whose whole body is a single
/// tap that opens the store's sale items, so the two only share their looks.
///
/// **Two faces.** With a best discount it reads `UP TO` / `-30%` — the same
/// qualifier and the same floored rule the ON SALE home poster uses, so a store
/// tag and the feed poster can never overstate a deal. Without one (a sale too
/// small to floor, which `maxDiscountPercent` returns null for) it falls back to
/// a bare `ON` / `SALE`: hiding would make a store that *is* on sale look like
/// one that is not.
///
/// **Motion, when asked for.** [animate] is true only for the focused card in
/// the carousel; the peeking neighbours stay still. The beat is the app's
/// existing idle shape (`SeeMoreCard`'s glide, the Workshop poster's tease): a
/// [Timer] for the stillness, a controller for the lean, each beat **ending at
/// zero**, [TickerMode]-gated and skipped under reduced motion. It is
/// deliberately not the product tag's continuous pendulum — that swing is a
/// product's own identity, and a row of them in a swiping carousel is noise.
class StoreSaleTag extends StatefulWidget {
  const StoreSaleTag({
    super.key,
    required this.sale,
    required this.onTap,
    this.animate = false,
  });

  /// The store's live sale state. The caller derives it through
  /// [storeSaleFrom], so this widget owns only the looks.
  final StoreSale sale;

  /// Opens the store pre-filtered to its on-sale products. The whole tag is the
  /// target; there is nothing else to hit.
  final VoidCallback onTap;

  /// Whether the idle dangle runs — passed true only by the focused card.
  final bool animate;

  /// The pill's box in the hero card's stat row. Fixed so the row can be laid
  /// out without measuring the tag, and deliberately compact: at 320px with the
  /// other pills at 1.3× text scale this box is what keeps the row from
  /// overflowing, so it is sized against that case rather than around the copy.
  static const double width = 68;
  static const double height = 28;

  /// The idle dangle's rhythm: stillness, then the lean out, then the ease
  /// back. Exposed so the card's own test can drive the clock precisely.
  static const Duration dangleHold = Duration(milliseconds: 2600);
  static const Duration dangleLean = Duration(milliseconds: 700);
  static const Duration dangleBack = Duration(milliseconds: 700);

  /// The lean at its peak, in radians — a dangle, not a swing.
  static const double dangleAngle = 0.06;

  @override
  State<StoreSaleTag> createState() => _StoreSaleTagState();
}

class _StoreSaleTagState extends State<StoreSaleTag> {
  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final dancing = widget.animate && !reducedMotion;

    // One label, one target: the copy is paint and type, and the whole tag opens
    // the shelf, so the semantics carry the count and the figure rather than
    // reading the tag's fragments. `onTap` is on the Semantics node as well as
    // the gesture detector because `excludeSemantics` drops the child's own
    // action.
    return Semantics(
      button: true,
      label: widget.sale.semanticsLabel,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: StoreSaleTag.width,
          height: StoreSaleTag.height,
          child: TickerMode(
            enabled: dancing,
            child: _IdleDangle(
              enabled: dancing,
              child: _TagBody(sale: widget.sale),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tag's face and silhouette: the cream body, the cut corner, the grommet
/// and the two lines of copy.
class _TagBody extends StatelessWidget {
  const _TagBody({required this.sale});

  final StoreSale sale;

  @override
  Widget build(BuildContext context) {
    final discount = sale.bestDiscount;
    return CustomPaint(
      painter: const _StoreTagPainter(),
      // Clear of the grommet punched into the top-right cut.
      child: Padding(
        padding: const EdgeInsets.only(right: 13),
        // The box is fixed and the copy is not: at a large text scale the block
        // scales DOWN to the tag rather than growing out of it (the same
        // `scaleDown` the poster family uses). The tag's shape is its identity,
        // so it must not stretch to follow the type.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                discount != null ? 'UP TO' : 'ON',
                maxLines: 1,
                style: AppConstants.bodyStyle(
                  fontSize: 6.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  // The product tag's own amber micro-label, on its own paper.
                  color: const Color(0xFFD9A441),
                ),
              ),
              Text(
                discount != null ? '-$discount%' : 'SALE',
                maxLines: 1,
                style: AppConstants.monoStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  // The product tag's revealed number uses the error red; a
                  // store tag is the same kind of claim, so it is the same ink.
                  color: AppConstants.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The idle dangle's motor — a timer-scheduled controller driving one lean-and-
/// return cycle per beat, the same shape as `SeeMoreCard`'s `_IdleNudge` and for
/// the same reasons: frames only while the tag is actually moving, and the
/// ticker lives below the card's [TickerMode] so a covered route mutes it.
class _IdleDangle extends StatefulWidget {
  const _IdleDangle({required this.enabled, required this.child});

  /// Whether the beat may run. Going false mid-beat eases the tag back to square
  /// (200ms) rather than snapping it — a tap landing mid-lean must not leave the
  /// tag resting a few degrees off.
  final bool enabled;

  final Widget child;

  @override
  State<_IdleDangle> createState() => _IdleDangleState();
}

class _IdleDangleState extends State<_IdleDangle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: StoreSaleTag.dangleLean + StoreSaleTag.dangleBack,
  );

  /// One cycle: out on [StoreSaleTag.dangleLean], back on
  /// [StoreSaleTag.dangleBack]. The stillness between cycles is a [Timer] — not
  /// controller time — so nothing animates while the tag waits.
  late final Animation<double> _fraction = TweenSequence<double>([
    TweenSequenceItem(
      tween: CurveTween(curve: Curves.easeInOutCubic),
      weight: StoreSaleTag.dangleLean.inMilliseconds.toDouble(),
    ),
    TweenSequenceItem(
      tween: CurveTween(
        curve: Curves.easeInOutCubic,
      ).chain(Tween(begin: 1.0, end: 0.0)),
      weight: StoreSaleTag.dangleBack.inMilliseconds.toDouble(),
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
  void didUpdateWidget(_IdleDangle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _scheduleBeat();
    } else {
      _holdTimer?.cancel();
      _holdTimer = null;
      _beat.stop();
      setState(() => _moving = false);
    }
  }

  /// One beat = [StoreSaleTag.dangleHold] of stillness, then the cycle. Chained
  /// through [_onCycleEnd], so it loops for as long as it is enabled.
  void _scheduleBeat() {
    _holdTimer?.cancel();
    _holdTimer = Timer(StoreSaleTag.dangleHold, _startCycle);
  }

  void _startCycle() {
    if (!mounted || !widget.enabled) return;
    setState(() => _moving = true);
    _beat.forward(from: 0).whenComplete(_onCycleEnd);
  }

  void _onCycleEnd() {
    if (!mounted) return;
    // Also runs when the cycle is cancelled mid-flight (the guards above),
    // which is exactly when another beat must NOT be scheduled.
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
        return AnimatedRotation(
          // The tag hangs from the card edge above it, so the pivot is its own
          // top centre rather than the middle of the pill.
          alignment: Alignment.topCenter,
          turns:
              (_moving ? _fraction.value : 0.0) *
              StoreSaleTag.dangleAngle /
              (2 * math.pi),
          duration: _moving ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// The tag's paper: a rounded body with an angled cut on the grommet corner, a
/// soft shadow that lifts it off the store's photo, and the punched amber ring.
///
/// The coordinates are the widget's own fixed 80×30 box — the tag is not scaled
/// anywhere, so there is nothing to derive from a reference canvas.
class _StoreTagPainter extends CustomPainter {
  const _StoreTagPainter();

  /// The angled cut on the grommet corner, in pixels.
  static const double cut = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, 4)
      ..quadraticBezierTo(0, 0, 4, 0)
      ..lineTo(w - cut, 0)
      ..lineTo(w, cut) // the angled cut the string would pass through
      ..lineTo(w, h - 4)
      ..quadraticBezierTo(w, h, w - 4, h)
      ..lineTo(4, h)
      ..quadraticBezierTo(0, h, 0, h - 4)
      ..close();

    // It sits ON the store's banner, so it has to lift off it — the product
    // tag's own treatment.
    canvas.drawShadow(path, Colors.black87, 3, false);

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF2), Color(0xFFF5E7D0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = AppConstants.primary.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Punched grommet in the cut corner: amber ring + dark through-hole.
    final grommet = Offset(w - 9, 9);
    canvas.drawCircle(
      grommet,
      3.0,
      Paint()
        ..color = const Color(0xFFD9A441)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(grommet, 1.6, Paint()..color = const Color(0xFF4A2A14));
  }

  @override
  bool shouldRepaint(covariant _StoreTagPainter oldDelegate) => false;
}
