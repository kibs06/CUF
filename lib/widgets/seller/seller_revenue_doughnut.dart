import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show FrictionSimulation;

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/sales_trend_data.dart';

/// Revenue breakdown doughnut — "how is this period's revenue split between
/// online and in-store."
///
/// Complements — never replaces — the monthly trend card: the trend answers
/// "how did revenue move over the last 6 months," this answers "how is the
/// current month split." Reuses the same data already fetched for the trend
/// chart (`SalesTrendResult.points.last`) so both cards always agree — and both
/// split the channels with the very same `SellerTheme.channel*` tokens.
///
/// The ring is drawn by [Doughnut3DPainter] rather than an fl_chart
/// `PieChart`: see that class for why the extrusion is hand-painted.
class SellerRevenueDoughnutChart extends StatelessWidget {
  final String title;
  final String periodLabel;
  final SalesTrendResult? trendResult;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const SellerRevenueDoughnutChart({
    super.key,
    required this.title,
    required this.periodLabel,
    this.trendResult,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  // Same low-baseline floor as the trend chart's delta pill — a tiny/no
  // prior period shouldn't render as a stark red "% down" claim.
  static const double _lowBaselineFloor = 500;

  /// Box the ring is drawn in, and how far the ring is extruded downward.
  static const double _ringBoxHeight = 200;
  static const double _ringDepth = 26;

  /// One tap on the ring = one hop: it rises, tips its face back and turns a
  /// full revolution, so the seam between the channels sweeps past before it
  /// lands back on exactly the pose it started in. Public so that tap can be
  /// driven at an exact frame in tests.
  static const Duration hopDuration = Duration(milliseconds: 1100);

  /// Where the ring can be *turned* from: a slide moves it this many radians
  /// per logical pixel — one full revolution per 320px, about the width of the
  /// card's own content, so a comfortable swipe is one turn. Public so the
  /// slide's tracking can be asserted without guessing at the sensitivity.
  static const double turnPerPixel = 2 * math.pi / 320;

  /// The box the 3D ring is painted into — the repaint boundary that isolates
  /// the draw-in animation from the rest of the card. Public so the geometry
  /// tests can capture it.
  static const Key ringKey = Key('seller-revenue-doughnut-ring');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildChartContent(),
        if (trendResult != null && _hasData) ...[
          const SizedBox(height: 12),
          _buildLegendRows(),
          const SizedBox(height: 12),
          _buildTrendFooter(trendResult!),
        ],
      ],
    );
  }

  bool get _hasData {
    final points = trendResult?.points ?? [];
    return points.isNotEmpty && points.last.revenue > 0;
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          periodLabel,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: SellerTheme.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: AppConstants.bodyStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ─── Chart content: loading / error / empty / doughnut ──────────
  Widget _buildChartContent() {
    if (isLoading) return _buildLoadingState();
    if (error != null) return _buildErrorState();
    if (!_hasData) return _buildEmptyState();
    final last = trendResult!.points.last;
    return _buildDoughnut(last.onlineRevenue, last.inStoreRevenue);
  }

  Widget _buildDoughnut(double online, double inStore) {
    final total = online + inStore;
    return _buildRing(
      slices: [
        DoughnutSlice(online, SellerTheme.channelOnline),
        DoughnutSlice(inStore, SellerTheme.channelInStore),
      ],
      value: _formatCurrencyShort(total),
      label: 'this month',
    );
  }

  /// The extruded ring plus the figure sitting in its hole.
  ///
  /// [TweenAnimationBuilder] feeds `progress` to the painter, which ties the
  /// sweep and the extrusion together — the ring rises out of the card as it
  /// draws in, instead of a flat arc fading in.
  Widget _buildRing({
    required List<DoughnutSlice> slices,
    required String value,
    required String label,
  }) {
    return SizedBox(
      width: double.infinity,
      height: _ringBoxHeight,
      child: _ExtrudedRing(
        slices: slices,
        value: value,
        label: label,
        depth: _ringDepth,
      ),
    );
  }

  // ─── Legend rows: channel · amount + percent ────────────────────
  Widget _buildLegendRows() {
    final last = trendResult!.points.last;
    final total = last.revenue;
    return Column(
      children: [
        _legendRow(
          color: SellerTheme.channelOnline,
          label: 'online',
          amount: last.onlineRevenue,
          total: total,
        ),
        const SizedBox(height: 8),
        _legendRow(
          color: SellerTheme.channelInStore,
          label: 'in-store',
          amount: last.inStoreRevenue,
          total: total,
        ),
      ],
    );
  }

  Widget _legendRow({
    required Color color,
    required String label,
    required double amount,
    required double total,
  }) {
    final percent = total > 0 ? (amount / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SellerTheme.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          _formatCurrency(amount),
          style: AppConstants.monoStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· $percent%',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: SellerTheme.textMuted,
          ),
        ),
      ],
    );
  }

  // ─── Trend footer — mirrors SellerRevenueColumnsChart's delta logic ─
  Widget _buildTrendFooter(SalesTrendResult trend) {
    final prev = trend.previousPeriodRevenue;
    final total = trend.totalRevenue;

    if (prev <= 0) {
      return _buildFooterRow(
        icon: Icons.remove,
        iconColor: SellerTheme.textMuted,
        text: 'No previous-period data',
        textColor: SellerTheme.textMuted,
      );
    }

    // Low baseline (new store / first month): the swing is noise, not signal.
    if (prev < _lowBaselineFloor) {
      return _buildFooterRow(
        icon: Icons.auto_graph,
        iconColor: SellerTheme.textMuted,
        text: total <= 0
            ? 'No orders yet this period'
            : 'Early days — trend will firm up',
        textColor: SellerTheme.textMuted,
      );
    }

    final change = trend.percentChange;
    final isUp = change >= 0;
    final color = isUp ? AppConstants.success : AppConstants.error;
    return _buildFooterRow(
      icon: isUp ? Icons.arrow_upward : Icons.arrow_downward,
      iconColor: color,
      text: '${change.abs().toStringAsFixed(1)}% ${isUp ? "up" : "down"}',
      textColor: color,
      suffix: 'vs ${_formatCurrency(prev)} last month',
    );
  }

  Widget _buildFooterRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    String? suffix,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppConstants.bodyStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(
              suffix,
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: SellerTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── States ─────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading chart data...',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: SellerTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              'Failed to load chart data',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: SellerTheme.textMuted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  'Retry',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // The same ring in the card's hairline grey — reads as an empty doughnut
    // rather than a fully-colored circle implying "100% of nothing" — so the
    // card keeps its shape before the first sale lands. [cardBorder] is
    // brightness-aware, which is why this cannot be a `const` slice.
    return _buildRing(
      slices: [DoughnutSlice(1, SellerTheme.cardBorder)],
      value: '₱0',
      label: 'No sales yet',
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────
  String _formatCurrency(double amount) {
    final whole = amount.floor();
    final formatted = whole.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '₱$formatted';
  }

  String _formatCurrencyShort(double amount) {
    if (amount >= 1000000) return '₱${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '₱${(amount / 1000).toStringAsFixed(1)}k';
    return '₱${amount.floor()}';
  }
}

// ─── 3D doughnut ────────────────────────────────────────────────

// ─── The tap ────────────────────────────────────────────────────

/// The extruded ring, the figure in its hole, and the two gestures that move
/// it: a tap hops it, a slide turns it.
///
/// A tap plays one hop: the ring rises, its top face tips back a few degrees
/// and it turns a full revolution, so the seam between the channels sweeps all
/// the way round before it lands. A horizontal slide turns the ring 1:1 with
/// the finger ([SellerRevenueDoughnutChart.turnPerPixel]) and lets it coast to
/// a stop on release, so the seam can be brought round to any channel. With a
/// single live channel there is no seam to watch — a uniform ring is
/// rotationally symmetric — so both gestures read as the ring leaving the card
/// and turning rather than as a change of data. Either way they are decorative:
/// the legend rows carry the numbers, which is why neither is in the semantics
/// tree.
///
/// The ring also comes off the card for as long as a finger is *on* it — the
/// same pose as the top of a hop — so a slide reads as picking the ring up and
/// turning it rather than as a picture being wiped sideways. Letting go of a
/// lifted ring sets it back down without the hop: the full turn belongs to a
/// *tap*, and a ring that was picked up should not bounce on the way down.
///
/// Only the tap's travel honours reduced motion. A hold and a slide are direct
/// manipulation — the ring goes off the card because it is in a hand, and turns
/// exactly as far as the finger pushes it — which is the same rule scroll
/// physics follow.
class _ExtrudedRing extends StatefulWidget {
  const _ExtrudedRing({
    required this.slices,
    required this.value,
    required this.label,
    required this.depth,
  });

  final List<DoughnutSlice> slices;
  final String value;
  final String label;

  /// The resting extrusion height ([SellerRevenueDoughnutChart._ringDepth]).
  final double depth;

  @override
  State<_ExtrudedRing> createState() => _ExtrudedRingState();
}

class _ExtrudedRingState extends State<_ExtrudedRing>
    with TickerProviderStateMixin {
  /// Draws the ring in on the first frame — the sweep and the extrusion rise
  /// together, so the ring grows out of the card instead of fading in.
  late final AnimationController _drawIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// The tap. Idle at rest, replayed from 0 on every tap — so a second tap
  /// mid-hop restarts the spin rather than compounding it.
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: SellerRevenueDoughnutChart.hopDuration,
  );

  /// The seller's own turn of the ring, in radians, dragged by finger and then
  /// coasted to a stop by a friction simulation. Unbounded on purpose: the ring
  /// turns as far as it is pushed, and the geometry only ever reads the angle
  /// modulo a full turn.
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
  );

  /// A finger on the ring, 0 → 1. Holds the ring at the top of its hop for as
  /// long as it is touched.
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );

  /// Long enough to read as the ring being picked up, short enough that it is
  /// already up by the time a slide has crossed the drag slop.
  static const Duration _holdDuration = Duration(milliseconds: 220);

  bool _held = false;

  /// A flick slower than this just stops where the finger left it (rad/s).
  static const double _coastThreshold = 1.2;

  /// Ceiling on a flick's angular speed (rad/s) — a hard throw carries the ring
  /// about one more turn instead of spinning it like a top.
  static const double _maxCoast = 10;

  /// How fast a coast bleeds off. Lower stops sooner.
  static const double _coastDrag = 0.16;

  /// How high the hop carries the ring, in logical pixels. Big enough to read
  /// as travel, small enough that the ring never climbs out of its box.
  static const double _liftHeight = 13;

  /// The pose at the top of the hop: the face tipped a few degrees further back
  /// (seen less from above, i.e. leaning away) over a deeper wall — ring and
  /// shadow both, which is what sells "it left the card".
  static const double _tippedFlatness = 0.47;
  static const double _hoppedDepth = 33;

  @override
  void initState() {
    super.initState();
    _drawIn.forward();
  }

  @override
  void dispose() {
    _drawIn.dispose();
    _hop.dispose();
    _slide.dispose();
    _hold.dispose();
    super.dispose();
  }

  bool get _reducedMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Owns *when* the ring is off the card. It ends four ways — a finger comes
  /// back up, the platform cancels the pointer, another gesture wins the arena
  /// (a scroll that started on the chart) and the widget goes away — and every
  /// one of them has to set the ring back down, or it stays hovering for the
  /// rest of the session. One flag, driven from the pointer rather than from
  /// the tap callbacks, is the only version of this that cannot be left stuck
  /// on.
  void _setHeld(bool held) {
    if (held == _held) return;
    _held = held;
    // Reduced motion still gets the pose — the ring coming up is how the seller
    // knows it is in their hand — it just does not travel there. The rule
    // `PressSink` states for the product cards' shadow.
    if (_reducedMotion) {
      _hold.value = held ? 1 : 0;
      return;
    }
    _hold.animateTo(
      held ? 1 : 0,
      duration: _holdDuration,
      curve: held ? Curves.easeOut : Curves.easeOutCubic,
    );
  }

  void _onTap() {
    // Reduced motion gets nothing here rather than a snap: the ring's resting
    // pose *is* the end of the hop, so a snap would be no animation at all.
    if (_reducedMotion) return;
    // A tap on a ring that is *already off the card* is the end of a hold, not
    // a fresh tap: the seller picked it up and is putting it down, so it settles
    // back instead of hopping and turning. Without this the release plays the
    // hop on top of the hold coming down — the ring dips, jumps back to the top
    // of the hop and lands, and the hold reads as a bounce.
    //
    // It reads the *pose* rather than the pointer flag, because the pointer came
    // up in the same event that started the hold coming down — the flag is
    // already false by the time the tap is delivered.
    if (_offCard > 0.5) return;
    _hop.forward(from: 0);
  }

  void _onDragStart(DragStartDetails details) {
    // Assigning to `value` stops whatever the ring was doing, so a finger takes
    // it over from a coast. Wrapping first keeps the angle the seller sees —
    // how many turns it has been through is nobody's business.
    _slide.value = _slide.value % (2 * math.pi);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _slide.value +=
        details.delta.dx * SellerRevenueDoughnutChart.turnPerPixel;
  }

  void _onDragEnd(DragEndDetails details) {
    var speed =
        (details.primaryVelocity ?? 0) *
        SellerRevenueDoughnutChart.turnPerPixel;
    if (speed.abs() < _coastThreshold) return;
    speed = speed.clamp(-_maxCoast, _maxCoast);
    _slide.animateWith(
      FrictionSimulation(_coastDrag, _slide.value, speed),
    );
  }

  /// How far off the card the ring is right now, 0…1: the finger's hold, plus
  /// whatever a tap's arc has added on top, capped at the one pose both of them
  /// are built from. So a tap *on* a held ring rises once rather than twice, and
  /// neither gesture can drop the ring out from under the other.
  double get _offCard {
    final hop = _hop.value;
    // Pin both ends: `sin(π)` is 1.2e-16 rather than 0 in double arithmetic, and
    // a hop has to land on *exactly* the resting pose, not a hair off it.
    final arc = (hop <= 0 || hop >= 1) ? 0.0 : math.sin(math.pi * hop);
    return math.min(1, _hold.value + arc);
  }

  /// The ring's pose right now: how far off the card it is ([_offCard]) and the
  /// turn a tap is adding. The painter and the figure in the hole both read
  /// this, so they can never disagree about where the ring is.
  ///
  /// The slide is *not* in here: it is not part of the pose, and it has to add
  /// to the turn rather than replace it.
  ({double depth, double lift, double spin, double flatness}) _pose() {
    final off = _offCard;
    return (
      depth: widget.depth + (_hoppedDepth - widget.depth) * off,
      lift: _liftHeight * off,
      spin: 2 * math.pi * Curves.easeOutCubic.transform(_hop.value),
      flatness:
          Doughnut3DPainter.restingFlatness +
          (_tippedFlatness - Doughnut3DPainter.restingFlatness) * off,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Which pointer is *on* the ring, asked of the pointer rather than of the
      // gesture arena: a slide, a scroll that starts on the chart and a finger
      // that drifts off it all have to set the ring back down, and all three
      // end here. (The trade is that a scroll begun over the chart answers the
      // touch too, the same rule `PressSink` states for the product cards.)
      onPointerDown: (_) => _setHeld(true),
      onPointerUp: (_) => _setHeld(false),
      onPointerCancel: (_) => _setHeld(false),
      child: GestureDetector(
        // Paint only: the ring's numbers are in the widget tree beside it, so a
        // tap or a slide here would otherwise offer a screen reader an action
        // that reports nothing.
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _slide.stop,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              // Its own layer: animating one canvas shouldn't invalidate the
              // header, legend and footer around it on every frame.
              child: RepaintBoundary(
                key: SellerRevenueDoughnutChart.ringKey,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_drawIn, _hop, _slide, _hold]),
                  builder: (context, _) {
                    final pose = _pose();
                    return CustomPaint(
                      painter: Doughnut3DPainter(
                        slices: widget.slices,
                        progress: Curves.easeOutCubic.transform(_drawIn.value),
                        depth: pose.depth,
                        // Where the seller has slid it, plus whatever is left
                        // of a tap's turn: the two add, so grabbing a ring
                        // mid-hop can never jump the seam.
                        spin: _slide.value + pose.spin,
                        lift: pose.lift,
                        flatness: pose.flatness,
                      ),
                    );
                  },
                ),
              ),
            ),
            // The figure belongs to the *top* face: it sits half the extrusion
            // above the middle of the box, and rides the hop and the hold.
            AnimatedBuilder(
              animation: Listenable.merge([_hop, _hold]),
              builder: (context, child) {
                final pose = _pose();
                return Transform.translate(
                  offset: Offset(0, -(pose.depth / 2) - pose.lift),
                  child: child,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.value,
                    style: AppConstants.monoStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.label,
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: SellerTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One slice of the ring: a revenue share and the channel colour it paints in.
///
/// Public rather than file-private (same for [Doughnut3DPainter]) so the
/// geometry can be pinned by pixel probes in
/// `test/widgets/seller_revenue_doughnut_3d_test.dart`.
class DoughnutSlice {
  const DoughnutSlice(this.value, this.color);

  final double value;
  final Color color;
}

/// Paints the split as an extruded (3D) doughnut.
///
/// fl_chart's `PieChart` only knows how to fill flat wedges — a shadow offset
/// behind a wedge is the closest it gets, and it breaks the moment two wedges
/// touch — so the ring is one canvas pass with an oblique projection:
///
/// * **Top face** — the ring squashed vertically by [flatness], which is what
///   a circle looks like from ~30° above. It carries a sheen from the upper
///   left, so the surface reads as lit rather than as a flat fill.
/// * **Front wall** — every point of the outer ellipse has a twin [depth]
///   pixels straight down. Only the near (lower) half of that wall is visible;
///   the far half is behind the top face, so it is never painted.
/// * **Through the hole** — the mirror of that rule: the *far* inner wall shows
///   inside the opening (blurred into a shadow), while the near inner wall is
///   hidden by the ring in front of it.
///
/// The last three arguments ([spin], [lift], [flatness]) are the tap's pose —
/// at rest they are all zero / [restingFlatness], which is the layout the card
/// settles into.
///
/// Slice colours are the theme's channel tokens (rust / mid espresso), so the
/// same revenue means the same colour across both cards.
class Doughnut3DPainter extends CustomPainter {
  const Doughnut3DPainter({
    required this.slices,
    required this.progress,
    required this.depth,
    this.spin = 0,
    this.lift = 0,
    this.flatness = restingFlatness,
  });

  final List<DoughnutSlice> slices;

  /// 0 → an empty canvas, 1 → the finished ring. Drives the sweep *and* the
  /// extrusion height, so this is the only input the draw-in needs.
  final double progress;

  /// Extrusion height, in logical pixels. The tap deepens it a little, which is
  /// half of what makes the ring look like it rose off the card.
  final double depth;

  /// Rotation of the whole slice layout, in radians. The ring's own geometry is
  /// rotationally symmetric, so this turns the *slices* — and with them the
  /// seam, which is the only part of a spin two channels ever show.
  final double spin;

  /// Raises the ring off its rest line, in pixels, without changing its size.
  final double lift;

  /// Vertical squash of the top face. [restingFlatness] reads as "viewed from
  /// ~30° above": clearly dimensional, flat enough to still compare slices by
  /// eye. The tap tips it back from there.
  final double flatness;

  /// The squash the card rests at, and the one the hop is measured from.
  static const double restingFlatness = 0.55;

  /// Hole radius as a fraction of the outer radius.
  static const double _innerRatio = 0.58;

  /// Keeps the ring off the edges of a tablet-width card.
  static const double _maxRadius = 118;

  /// Angular slit between slices (~2px at the rim) so two channels never read
  /// as one wedge — the hand-drawn stand-in for `sectionsSpace`.
  static const double _sliceGap = 0.028;

  /// The sweep starts at 12 o'clock, matching the pie the dashboard had before.
  static const double _startAngle = -math.pi / 2;

  /// Slack for "this slice goes all the way round", in radians.
  static const double _fullTurn = 1e-6;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(
      0,
      (sum, s) => sum + (s.value.isFinite && s.value > 0 ? s.value : 0),
    );
    final t = progress.clamp(0.0, 1.0).toDouble();
    if (total <= 0 || t <= 0) return;
    if (size.width < 16 || size.height < 16) return;

    // ── Geometry ────────────────────────────────────────────────
    final cx = size.width / 2;
    // The extrusion hangs *below* the top face, so the top face — not the
    // bounding box — is the thing the figure in the hole centres on, and the
    // hop's lift takes the whole ring up from there.
    final cy = size.height / 2 - depth / 2 - lift;
    var rx = math.min(_maxRadius, size.width / 2 - 4);
    // Clamp against the *resting* tilt: a hop only ever tips the face back
    // (less squash), so a ring that fits at rest fits throughout, and this can
    // never make the ring swell sideways mid-hop.
    final maxRy = (size.height - depth - 8) / 2;
    if (rx * restingFlatness > maxRy) rx = maxRy / restingFlatness;
    final ry = rx * flatness;
    final outer = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );
    final inner = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * _innerRatio * 2,
      height: ry * _innerRatio * 2,
    );
    final extrusion = depth * t;

    // ── Slice spans, clockwise from 12 o'clock ──────────────────
    final spans = <({double a0, double a1, Color color})>[];
    var angle = _startAngle + spin;
    final sweepTotal = 2 * math.pi * t;
    for (final slice in slices) {
      final value =
          (slice.value.isFinite && slice.value > 0) ? slice.value : 0.0;
      if (value <= 0) continue;
      final sweep = sweepTotal * (value / total);
      if (sweep <= 0) continue;
      spans.add((a0: angle, a1: angle + sweep, color: slice.color));
      angle += sweep;
    }
    if (spans.isEmpty) return;
    // A lone slice is a closed ring — a slit in it would be a seam, not a
    // channel boundary.
    final inset = spans.length > 1 ? _sliceGap / 2 : 0.0;

    // ── Front wall ──────────────────────────────────────────────
    for (final span in spans) {
      final paint = _wallPaint(span.color, cy, ry + extrusion);
      for (final segment in _nearHalf(span.a0, span.a1)) {
        canvas.drawPath(
          _wallPath(outer, segment.$1, segment.$2, extrusion),
          paint,
        );
      }
    }

    // ── Inside the hole: the far inner wall ─────────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(inner));
    // Shallower than the outer wall: the hole is a recess, and a full-depth
    // inner wall would climb into the figure sitting in the middle of it.
    final holeDepth = extrusion * 0.6;
    for (final span in spans) {
      final paint = Paint()
        ..color = Color.lerp(span.color, Colors.black, 0.52)!
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      for (final segment in _farHalf(span.a0, span.a1)) {
        canvas.drawPath(
          _wallPath(inner, segment.$1, segment.$2, holeDepth),
          paint,
        );
      }
    }
    canvas.restore();

    // ── Top face ────────────────────────────────────────────────
    for (final span in spans) {
      final a0 = span.a0 + inset;
      final a1 = span.a1 - inset;
      final sweep = a1 - a0;
      if (sweep <= 0) continue;

      if (sweep >= 2 * math.pi - _fullTurn) {
        // A lone slice is a closed ring — and a full turn is exactly where
        // `arcTo` gives up: `Path.arcTo(rect, angle, 2π)` builds a path that
        // fills as *nothing at all* (an annulus drawn that way disappears, and
        // takes the width of the ring with it). Two ovals under even-odd are
        // the same geometry, closed, and immune to winding direction.
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addOval(outer)
            ..addOval(inner),
          _facePaint(span.color, outer),
        );
        canvas.drawOval(outer, _rimPaint());
        continue;
      }

      canvas.drawPath(
        Path()
          ..arcTo(outer, a0, sweep, true)
          ..arcTo(inner, a1, -sweep, false)
          ..close(),
        _facePaint(span.color, outer),
      );
      canvas.drawArc(outer, a0, sweep, false, _rimPaint());
    }
  }

  /// A hairline of light on the top face's rim, so the face never melts into
  /// the wall standing behind it.
  Paint _rimPaint() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = Colors.white.withValues(alpha: 0.14);

  /// Point on [ellipse] at [angle], dropped [drop] pixels to its extruded twin.
  Offset _point(Rect ellipse, double angle, double drop) => Offset(
    ellipse.center.dx + ellipse.width / 2 * math.cos(angle),
    ellipse.center.dy + ellipse.height / 2 * math.sin(angle) + drop,
  );

  /// The wall over `[a0, a1]`: the arc, dropped to its twin, and back — a
  /// closed band that fills like a ribbon of the ring's side.
  Path _wallPath(Rect ellipse, double a0, double a1, double drop) {
    final end = _point(ellipse, a1, drop);
    return Path()
      ..arcTo(ellipse, a0, a1 - a0, true)
      ..lineTo(end.dx, end.dy)
      ..arcTo(ellipse.shift(Offset(0, drop)), a1, a0 - a1, false)
      ..close();
  }

  /// The stretch of `[a0, a1]` on the near (lower) half of the ellipse — the
  /// only part of a wall a viewer can actually see.
  List<(double, double)> _nearHalf(double a0, double a1) =>
      _halves(a0, a1, near: true);

  /// …and on the far (upper) half — the inner wall visible through the hole.
  List<(double, double)> _farHalf(double a0, double a1) =>
      _halves(a0, a1, near: false);

  /// `sin(angle) > 0` marks the near half (canvas y grows downward), so the
  /// near windows are `[2πk, 2πk + π]` and the far ones are the gaps between
  /// them. A slice can straddle a window edge, hence a list.
  List<(double, double)> _halves(
    double a0,
    double a1, {
    required bool near,
  }) {
    final out = <(double, double)>[];
    if (a1 <= a0) return out;
    final kFirst = ((a0 - math.pi) / (2 * math.pi)).floor();
    final kLast = (a1 / (2 * math.pi)).ceil();
    for (var k = kFirst; k <= kLast; k++) {
      final windowStart = 2 * math.pi * k + (near ? 0 : math.pi);
      final start = math.max(a0, windowStart);
      final end = math.min(a1, windowStart + math.pi);
      if (end > start) out.add((start, end));
    }
    return out;
  }

  /// The wall is one dark band, deepest at the bottom lip: the light comes
  /// from above, so it falls off as the surface turns away from it.
  Paint _wallPaint(Color base, double top, double height) {
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(base, Colors.black, 0.30)!,
          Color.lerp(base, Colors.black, 0.46)!,
        ],
      ).createShader(Rect.fromLTRB(0, top, 1, top + height));
  }

  /// The top face catches the light at its upper-left and settles into its own
  /// colour — the sheen that makes the surface read as a lit plane.
  Paint _facePaint(Color base, Rect bounds) {
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(base, Colors.white, 0.18)!,
          base,
          Color.lerp(base, Colors.black, 0.10)!,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(bounds);
  }

  @override
  bool shouldRepaint(covariant Doughnut3DPainter old) =>
      old.progress != progress ||
      old.depth != depth ||
      !listEquals(
        old.slices.map((s) => (s.value, s.color)).toList(),
        slices.map((s) => (s.value, s.color)).toList(),
      );
}
