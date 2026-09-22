import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/seller_theme_constants.dart';
import 'package:app/models/sales_trend_data.dart';
import 'package:app/widgets/seller/seller_revenue_doughnut.dart';

/// The revenue doughnut is an *extruded* ring, not a flat pie: a squashed top
/// face, a dark front wall standing `depth` pixels below it, and the far inner
/// wall of the hole blurred into a shadow. None of that is expressible with
/// fl_chart's `PieChart`, so the ring is hand-painted — which means nothing in
/// the widget tree describes its geometry, and a mistake shows up as pixels
/// rather than as a layout error.
///
/// So these tests paint [Doughnut3DPainter] straight onto a canvas and read
/// the result back. The painter is driven directly rather than through the
/// widget on purpose: capturing a widget tree needs a real event loop
/// (`RenderRepaintBoundary.toImage`), and in one of those `google_fonts`
/// actually attempts its font fetch and fails the test. Painting the canvas
/// ourselves keeps the probes in the painter's own coordinates with no fonts
/// in the way; the last group covers the widget wiring that the canvas can't.

/// The ring box, and the extrusion height the card passes in.
const double _boxHeight = 200;
const double _depth = 26;

/// The pose at the top of a hop, copied from `_ExtrudedRingState` — the one pose
/// the hop's peak *and* a finger's hold are both built from (lifted 13, tipped
/// back to 0.47, wall 33 deep).
const double _hopLift = 13;
const double _hopFlatness = 0.47;
const double _hopDepth = 33;

/// A 320px card: the ring's own geometry then puts the top face's centre at
/// (160, 87) with a 118 x 65 outer ellipse and a 35 x 19 hole.
const double _centreX = 160;
const double _centreY = _boxHeight / 2 - _depth / 2;

/// A rendered canvas, addressed in the ring box's own coordinates.
class _Canvas {
  _Canvas(this._rgba, this.width);

  final Uint8List _rgba;
  final int width;

  /// Renders the painter over a white card, exactly as the dashboard does.
  static Future<_Canvas> paint({
    required double online,
    required double inStore,
    double width = 320,
    double progress = 1,
    double depth = _depth,
    double spin = 0,
    double lift = 0,
    double flatness = Doughnut3DPainter.restingFlatness,
  }) async {
    final size = Size(width, _boxHeight);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(Offset.zero & size, Paint()..color = Colors.white);
    Doughnut3DPainter(
      slices: [
        DoughnutSlice(online, SellerTheme.channelOnline),
        DoughnutSlice(inStore, SellerTheme.channelInStore),
      ],
      progress: progress,
      depth: depth,
      spin: spin,
      lift: lift,
      flatness: flatness,
    ).paint(canvas, size);

    final image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return _Canvas(data!.buffer.asUint8List(), size.width.round());
  }

  Color at(double x, double y) {
    final offset = (y.round() * width + x.round()) * 4;
    return Color.fromARGB(
      _rgba[offset + 3],
      _rgba[offset],
      _rgba[offset + 1],
      _rgba[offset + 2],
    );
  }
}

/// Perceived lightness, 0…255. The top face carries a sheen gradient and the
/// wall a vertical falloff, so the tests compare *relationships* — lit above
/// shaded, brown over blue — rather than RGB values a palette tweak would
/// break.
double _luma(Color c) =>
    0.299 * c.r * 255 + 0.587 * c.g * 255 + 0.114 * c.b * 255;

bool _isReddish(Color c) =>
    c.r * 255 > c.g * 255 && c.g * 255 > c.b * 255;

Widget _card({
  required double online,
  required double inStore,
  double width = 320,
  bool disableAnimations = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SellerRevenueDoughnutChart(
            title: 'Revenue breakdown',
            periodLabel: 'September 2026',
            trendResult: SalesTrendResult(
              points: [
                SalesDataPoint(
                  date: DateTime(2026, 9, 1),
                  onlineRevenue: online,
                  inStoreRevenue: inStore,
                  revenue: online + inStore,
                ),
              ],
              totalRevenue: online + inStore,
              previousPeriodRevenue: 0,
              percentChange: 0,
            ),
          ),
        ),
      ),
    ),
  ),
);

/// Taps the ring itself rather than the middle of its box: the ₱ figure is a
/// sibling painted on top of the canvas, so a tap at the box's centre lands on
/// the words.
Future<void> _tapRing(WidgetTester tester) async =>
    tester.tapAt(_ringPoint(tester));

/// A point inside the ring box but off the ₱ figure, which is painted on top
/// of the canvas in the middle of it.
Offset _ringPoint(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(SellerRevenueDoughnutChart.ringKey)) +
    const Offset(60, 100);

/// The pose the card is painting right now, read off the live painter.
Doughnut3DPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(SellerRevenueDoughnutChart.ringKey),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as Doughnut3DPainter;

void main() {
  group('the extrusion', () {
    test('stands a shaded wall below the top face', () async {
      final canvas = await _Canvas.paint(online: 701, inStore: 0);

      final face = canvas.at(_centreX - 100, _centreY); // 9 o'clock, on top
      final wall = canvas.at(_centreX, _centreY + 85); // below the front edge
      final past = canvas.at(_centreX, _centreY + 103); // past the silhouette

      expect(_isReddish(face), isTrue, reason: 'the face paints online rust');
      expect(
        _luma(wall),
        lessThan(_luma(face) * 0.8),
        reason:
            'a flat pie paints nothing at (160, 172) — the wall standing '
            'there is the whole 3D claim',
      );
      expect(
        past,
        Colors.white,
        reason:
            'the silhouette must stop one extrusion below the face (y≈178); '
            'deeper and the ring would clip the card',
      );
    });

    test('rises as it draws: progress 0 leaves the card untouched', () async {
      final canvas = await _Canvas.paint(online: 701, inStore: 0, progress: 0);

      expect(canvas.at(_centreX, _centreY + 85), Colors.white);
      expect(canvas.at(_centreX - 100, _centreY), Colors.white);
    });

    test('a narrow card shrinks the ring instead of clipping it', () async {
      const width = 160.0;
      final canvas = await _Canvas.paint(
        online: 701,
        inStore: 0,
        width: width,
      );

      // rx = width / 2 - 4: ring at 9 o'clock, card just outside it.
      expect(canvas.at(20, _centreY), isNot(Colors.white));
      expect(canvas.at(1, _centreY), Colors.white);
      expect(canvas.at(_centreX, _centreY + 103), Colors.white);
    });
  });

  group('the hole', () {
    test('is open, so the figure in the middle sits on the card', () async {
      final canvas = await _Canvas.paint(online: 701, inStore: 0);

      // Inside the inner ellipse, clear of the ₱ figure in the centre and of
      // the far inner wall, whose shadow only reaches a third of the way down.
      expect(canvas.at(120, 110), Colors.white);
      expect(canvas.at(160, 110), Colors.white);
    });

    test('shows the far inner wall darkening its top edge', () async {
      final canvas = await _Canvas.paint(online: 701, inStore: 0);

      // Right under the hole's back rim the wall turns away from the light.
      final shadow = canvas.at(_centreX, 58);
      expect(_luma(shadow), lessThan(200), reason: 'no shadow reads as flat');
      expect(_isReddish(shadow), isTrue);
    });
  });

  group('the tap’s pose, measured in pixels', () {
    test('a spin carries the seam round the ring', () async {
      final rest = await _Canvas.paint(online: 400, inStore: 301);
      final spun = await _Canvas.paint(
        online: 400,
        inStore: 301,
        spin: math.pi / 2,
      );

      // The seam starts at 12 o'clock; a quarter turn puts it at 3 o'clock,
      // and the face closes over where it was.
      expect(rest.at(_centreX, 35), Colors.white);
      expect(_isReddish(spun.at(_centreX, 35)), isTrue);
    });

    test('a lift raises the whole silhouette off its rest line', () async {
      final rest = await _Canvas.paint(online: 701, inStore: 0);
      final lifted = await _Canvas.paint(
        online: 701,
        inStore: 0,
        lift: _hopLift,
      );

      // The bottom of the wall is at y≈178 at rest — 26 of wall below the
      // face — and exactly `lift` higher with the hop on.
      expect(rest.at(_centreX, 172), isNot(Colors.white));
      expect(lifted.at(_centreX, 172), Colors.white);
    });

    test('a tilt flattens the top face without moving its centre', () async {
      final rest = await _Canvas.paint(online: 701, inStore: 0);
      final tilted = await _Canvas.paint(
        online: 701,
        inStore: 0,
        flatness: _hopFlatness,
      );

      // A flatter ellipse pulls its top vertex down towards the centre, so a
      // point the ring covers at rest is card again.
      expect(rest.at(_centreX, 26), isNot(Colors.white));
      expect(tilted.at(_centreX, 26), Colors.white);
      // …and the ring is still centred on the same line.
      expect(rest.at(_centreX - 100, _centreY), isNot(Colors.white));
      expect(tilted.at(_centreX - 100, _centreY), isNot(Colors.white));
    });

    test('the pose off the card — hop peak and held ring alike — fits the box', () async {
      final peak = await _Canvas.paint(
        online: 701,
        inStore: 0,
        depth: _hopDepth,
        lift: _hopLift,
        flatness: _hopFlatness,
      );

      // Top and bottom of the silhouette, ten pixels clear of the card's own
      // edges — the figure in the hole must never be crowded or clipped.
      expect(peak.at(_centreX - 100, _centreY), isNot(Colors.white));
      expect(peak.at(_centreX, _centreY + 103), Colors.white);
      expect(peak.at(_centreX, 4), Colors.white);
    });
  });

  group('the channels', () {
    test('a lone channel is closed, with no seam at 12 o’clock', () async {
      final canvas = await _Canvas.paint(online: 701, inStore: 0);

      expect(
        _isReddish(canvas.at(_centreX, 35)),
        isTrue,
        reason: 'the sweep starts at 12 o’clock: a slit there would be a seam',
      );
    });

    test('two live channels are separated by a slit', () async {
      final canvas = await _Canvas.paint(online: 400, inStore: 301);

      expect(
        canvas.at(_centreX, 35),
        Colors.white,
        reason: 'the gap between slices must draw through to the card',
      );
      // Away from both seams the ring paints on — the slit is a seam between
      // the slices, not a break in the ring.
      expect(_isReddish(canvas.at(_centreX - 100, _centreY)), isTrue);
    });

    test('in-store is the darker espresso, not the online rust', () async {
      final canvas = await _Canvas.paint(online: 0, inStore: 701);

      final face = canvas.at(_centreX - 100, _centreY);
      expect(_isReddish(face), isTrue);
      expect(
        _luma(face),
        lessThan(_luma(SellerTheme.channelOnline) * 0.95),
        reason: 'mid espresso is a darker brown than rust',
      );
    });

    test('an empty period still draws the ring, in the hairline grey', () async {
      final canvas = await _Canvas.paint(online: 0, inStore: 0);

      final face = canvas.at(_centreX - 100, _centreY);
      expect(_luma(face), greaterThan(200), reason: 'grey, not a channel');
      expect(_isReddish(face), isFalse);
    });
  });

  group('the tap', () {
    testWidgets('hops the ring and spins it a full turn, then lands', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();

      final rest = _painter(tester);
      expect(rest.spin, 0);
      expect(rest.lift, 0);

      await _tapRing(tester);
      await tester.pump();
      await tester.pump(SellerRevenueDoughnutChart.hopDuration ~/ 2);

      final peak = _painter(tester);
      expect(
        peak.spin,
        greaterThan(0),
        reason: 'the seam has to travel, or the tap shows nothing',
      );
      expect(peak.lift, greaterThan(0));
      expect(peak.depth, greaterThan(_depth), reason: 'the wall deepens too');
      expect(peak.flatness, lessThan(Doughnut3DPainter.restingFlatness));

      await tester.pumpAndSettle();
      final landed = _painter(tester);
      expect(
        landed.spin,
        moreOrLessEquals(2 * math.pi, epsilon: 0.001),
        reason: 'a full turn lands the seam back where it started',
      );
      expect(landed.lift, 0);
      expect(landed.depth, _depth);
      expect(landed.flatness, Doughnut3DPainter.restingFlatness);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a reduced-motion platform swallows the tap', (tester) async {
      await tester.pumpWidget(
        _card(online: 400, inStore: 301, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      await _tapRing(tester);
      await tester.pump(SellerRevenueDoughnutChart.hopDuration ~/ 2);

      expect(
        _painter(tester).spin,
        0,
        reason: 'there is no reduced-motion pose to snap to — so no hop',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the slide', () {
    testWidgets('turns the ring 1:1 with the finger, both ways', (tester) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(_ringPoint(tester));
      // Two pumps: a ticker's first frame is reported as zero elapsed, so the
      // hold only starts moving on the pump after the one that starts it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The move that gets a drag *recognized* is spent on the drag slop and
      // never reported — `DragStartBehavior.start`, the default — so this one
      // is thrown away and every reading below is a measured move. All of them
      // are taken with the finger still down: releasing hands the ring to the
      // friction simulation, and the angle keeps moving on its own.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final start = _painter(tester).spin;

      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(
        _painter(tester).spin - start,
        moreOrLessEquals(
          -80 * SellerRevenueDoughnutChart.turnPerPixel,
          epsilon: 0.001,
        ),
        reason: 'dragging back turns it back by exactly the distance moved',
      );

      await gesture.moveBy(const Offset(160, 0));
      await tester.pump();
      expect(
        _painter(tester).spin - start,
        moreOrLessEquals(
          80 * SellerRevenueDoughnutChart.turnPerPixel,
          epsilon: 0.001,
        ),
        reason: 'and dragging on turns it on by the same measure',
      );

      // …and it is a turn *of a held ring*: while the finger is down the ring
      // is off the card, at the same pose a hop's peak reaches.
      expect(_painter(tester).lift, _hopLift);
      expect(_painter(tester).flatness, _hopFlatness);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flick coasts past the finger, then settles', (tester) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();

      // Would time out here if the coast never ended.
      await tester.flingFrom(
        _ringPoint(tester),
        const Offset(120, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(
        _painter(tester).spin,
        greaterThan(120 * SellerRevenueDoughnutChart.turnPerPixel + 1),
        reason: 'momentum is the whole point of a flick',
      );
      expect(
        _painter(tester).lift,
        0,
        reason: 'the finger is up, so the ring is back on the card',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap after a slide turns a full turn from where it stopped', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();

      await tester.dragFrom(_ringPoint(tester), const Offset(80, 0));
      await tester.pumpAndSettle();
      final parked = _painter(tester).spin;
      expect(parked, isNot(0), reason: 'the slide left the ring turned');

      await _tapRing(tester);
      await tester.pump();
      await tester.pump(SellerRevenueDoughnutChart.hopDuration);
      await tester.pumpAndSettle();

      expect(
        _painter(tester).spin,
        moreOrLessEquals(parked + 2 * math.pi, epsilon: 0.001),
        reason:
            'the hop turns a full revolution from wherever the seller left '
            'it — the two gestures add, they do not restart each other',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the hold', () {
    testWidgets('a finger on the ring picks it up, and letting go sets it down', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();
      expect(_painter(tester).lift, 0, reason: 'nothing is touching it yet');

      final gesture = await tester.startGesture(_ringPoint(tester));
      await tester.pump();
      // Partway up: the hold eases, so the ring is seen leaving the card.
      await tester.pump(const Duration(milliseconds: 100));
      final rising = _painter(tester).lift;
      expect(rising, greaterThan(0));
      expect(rising, lessThan(_hopLift));

      await tester.pump(const Duration(milliseconds: 200));
      final held = _painter(tester);
      expect(held.lift, _hopLift, reason: 'the top of the hop, held');
      expect(held.depth, _hopDepth, reason: 'ring and its wall both come up');
      expect(held.flatness, _hopFlatness);
      expect(
        held.spin,
        0,
        reason: 'a hold is not a tap — nothing turns until it is slid',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_painter(tester).lift, 0);
      expect(_painter(tester).flatness, Doughnut3DPainter.restingFlatness);
      expect(
        _painter(tester).spin,
        0,
        reason: 'setting a picked-up ring down is not a hop: no turn',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a gesture that is taken away still sets the ring down', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(_ringPoint(tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).lift, _hopLift);

      // What a scroll that starts on the chart does: the arena goes elsewhere
      // and the ring is never told the finger came up.
      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _painter(tester).lift,
        0,
        reason: 'a held ring that is never released would hover all session',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a held ring settles down in one move, never over the top', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 400, inStore: 301));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(_ringPoint(tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).lift, _hopLift, reason: 'held, so off the card');

      await gesture.up();
      await tester.pump();

      // Letting go of a picked-up ring is one descent to rest. If the release
      // also played the hop the ring would dip, jump back to the top of the hop
      // and land — a bounce — so the lift is watched all the way down.
      var previous = _painter(tester).lift;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final lift = _painter(tester).lift;
        expect(lift, lessThanOrEqualTo(previous + 0.001));
        expect(lift, lessThanOrEqualTo(_hopLift + 0.001));
        previous = lift;
      }
      await tester.pumpAndSettle();
      expect(_painter(tester).lift, 0);
      expect(_painter(tester).spin, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('the card around it', () {
    testWidgets('hands the painter the channels, the depth and the total', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 701, inStore: 0));
      await tester.pumpAndSettle();

      final painter = _painter(tester);

      expect(painter.depth, _depth);
      expect(
        painter.progress,
        moreOrLessEquals(1, epsilon: 0.001),
        reason: 'the draw-in must finish, or the ring stays squashed',
      );
      expect(painter.slices.map((s) => s.value).toList(), [701, 0]);
      expect(
        painter.slices.map((s) => s.color).toList(),
        [
          SellerTheme.channelOnline,
          SellerTheme.channelInStore,
        ],
      );

      // ₱701 is the figure in the hole AND the online legend amount.
      expect(find.text('₱701'), findsNWidgets(2));
      expect(find.text('this month'), findsOneWidget);
      expect(find.text('online'), findsOneWidget);
      expect(find.text('in-store'), findsOneWidget);
      expect(find.text('· 0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty period draws the grey ring under the ₱0', (
      tester,
    ) async {
      await tester.pumpWidget(_card(online: 0, inStore: 0));
      await tester.pumpAndSettle();

      expect(_painter(tester).slices.single.color, SellerTheme.cardBorder);
      expect(find.text('₱0'), findsOneWidget);
      expect(find.text('No sales yet'), findsOneWidget);
      // No legend without data — there is nothing to split.
      expect(find.text('online'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
