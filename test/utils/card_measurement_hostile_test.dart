import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/foot_measurement_utils.dart';

/// Axis-aligned card quad: x∈[100,260] → 85.6mm, y∈[100,200] → 53.98mm.
List<Offset> cardQuad() => const [
      Offset(100, 100),
      Offset(260, 100),
      Offset(260, 200),
      Offset(100, 200),
    ];

/// Analytic inverse of a 3×3 row-major homography (test forward model).
List<double> _invert3x3(List<double> h) {
  final a = h[0], b = h[1], c = h[2];
  final d = h[3], e = h[4], f = h[5];
  final g = h[6], hh = h[7], i = h[8];
  final det =
      a * (e * i - f * hh) - b * (d * i - f * g) + c * (d * hh - e * g);
  assert(det.abs() > 1e-12);
  final s = 1 / det;
  return [
    (e * i - f * hh) * s,
    (c * hh - b * i) * s,
    (b * f - c * e) * s,
    (f * g - d * i) * s,
    (a * i - c * g) * s,
    (c * d - a * f) * s,
    (d * hh - e * g) * s,
    (b * g - a * hh) * s,
    (a * e - b * d) * s,
  ];
}

/// Apply a 3×3 row-major homography (test forward model).
Offset _applyH(List<double> h, Offset p) {
  final w = h[6] * p.dx + h[7] * p.dy + h[8];
  return Offset(
    (h[0] * p.dx + h[1] * p.dy + h[2]) / w,
    (h[3] * p.dx + h[4] * p.dy + h[5]) / w,
  );
}

/// Ellipse outline (foot-like) in pixels.
List<Offset> ellipse({
  double cx = 180,
  double cy = 150,
  double rx = 90,
  double ry = 25,
  int steps = 24,
}) {
  final pts = <Offset>[];
  for (var i = 0; i < steps; i++) {
    final a = 2 * pi * i / steps;
    pts.add(Offset(cx + rx * cos(a), cy + ry * sin(a)));
  }
  return pts;
}

void main() {
  group('measureFootRectified — hostile', () {
    test('axis-aligned card recovers exact mm extents', () {
      // 180px horizontal → 180 * 85.6/160 = 96.3mm;
      // 50px vertical → 50 * 53.98/100 = 26.99mm.
      final m = measureFootRectified(
        footOutline: ellipse(),
        refCorners: cardQuad(),
        paper: PaperDimensions.card,
      )!;
      expect(m.lengthMm, closeTo(96.3, 0.5));
      expect(m.widthMm, closeTo(26.99, 0.5));
    });

    test('in-plane rotation is tilt-invariant (mild tilt cancels)', () {
      // Rotate the whole scene 30° about the quad center: shape preserved,
      // so the validator passes and mm must match the unrotated case.
      final cx = 180.0, cy = 150.0;
      final a = 30 * pi / 180;
      Offset rot(Offset p) {
        final dx = p.dx - cx, dy = p.dy - cy;
        return Offset(
          cx + dx * cos(a) - dy * sin(a),
          cy + dx * sin(a) + dy * cos(a),
        );
      }
      final m = measureFootRectified(
        footOutline: ellipse().map(rot).toList(),
        refCorners: cardQuad().map(rot).toList(),
        paper: PaperDimensions.card,
      )!;
      expect(m.lengthMm, closeTo(96.3, 0.6));
      expect(m.widthMm, closeTo(26.99, 0.6));
    });

    test('keystoned (tilted) card → null, never a skewed size', () {
      final tilted = [
        const Offset(140, 100),
        const Offset(220, 100),
        const Offset(260, 200),
        const Offset(60, 200),
      ];
      expect(
        measureFootRectified(
          footOutline: ellipse(),
          refCorners: tilted,
          paper: PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('planar tilt cancels: tilted-view foot recovers true mm', () {
      // Top 120px vs bottom 160px, symmetric: inside the gate. Forward
      // model: a 96.3×27.0mm foot photographed under this perspective.
      // Build its pixels by pushing a mm-space ellipse through the
      // INVERSE homography (3×3 analytic inverse, local to this test),
      // then the production path must recover the true mm within 0.5.
      final mildTilt = [
        const Offset(120, 60),
        const Offset(240, 60),
        const Offset(260, 200),
        const Offset(100, 200),
      ];
      expect(
        diagnoseReferenceQuad(mildTilt, PaperDimensions.card),
        isEmpty,
      );
      final h = homographyPixelsToMm(mildTilt, PaperDimensions.card)!;
      final inv = _invert3x3(h);
      // mm ellipse: 96.3 long × 27.0 wide, centered on the card.
      final pixels = <Offset>[];
      for (var i = 0; i < 24; i++) {
        final a = 2 * pi * i / 24;
        pixels.add(
          _applyH(inv, Offset(42.8 + 48.15 * cos(a), 26.99 + 13.5 * sin(a))),
        );
      }
      final m = measureFootRectified(
        footOutline: pixels,
        refCorners: mildTilt,
        paper: PaperDimensions.card,
      )!;
      expect(m.lengthMm, closeTo(96.3, 0.5));
      expect(m.widthMm, closeTo(27.0, 0.5));
    });

    test('lifted card (severe, one edge pinched) → null', () {
      // Top edge 60px vs bottom 160px: side ratio 0.375 — a lifted edge
      // the plane math cannot trust. NOTE: 4 corners alone cannot prove
      // lift vs tilt; severe geometry refuses, mild cases rely on the
      // lay-flat coaching + burst IQR, not the gate.
      final lifted = [
        const Offset(170, 60),
        const Offset(230, 60),
        const Offset(260, 200),
        const Offset(100, 200),
      ];
      expect(
        diagnoseReferenceQuad(lifted, PaperDimensions.card).isNotEmpty,
        isTrue,
      );
      expect(
        measureFootRectified(
          footOutline: ellipse(),
          refCorners: lifted,
          paper: PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('too-small quad → null', () {
      final far = [
        const Offset(100, 100),
        const Offset(140, 100),
        const Offset(140, 125),
        const Offset(100, 125),
      ];
      expect(
        measureFootRectified(
          footOutline: ellipse(),
          refCorners: far,
          paper: PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('empty / tiny / collinear outlines → null', () {
      expect(
        measureFootRectified(
          footOutline: const [],
          refCorners: cardQuad(),
          paper: PaperDimensions.card,
        ),
        isNull,
      );
      expect(
        measureFootRectified(
          footOutline: List.generate(5, (i) => Offset(100.0 + i, 100)),
          refCorners: cardQuad(),
          paper: PaperDimensions.card,
        ),
        isNull,
      );
      // 12 identical points: zero extent.
      expect(
        measureFootRectified(
          footOutline: List.filled(12, const Offset(150, 150)),
          refCorners: cardQuad(),
          paper: PaperDimensions.card,
        ),
        isNull,
      );
      // Perfect line: zero width.
      expect(
        measureFootRectified(
          footOutline: List.generate(12, (i) => Offset(100.0 + i * 10, 150)),
          refCorners: cardQuad(),
          paper: PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('non-finite points → null, never NaN out', () {
      final badOutline = ellipse()..[3] = const Offset(double.nan, 150);
      expect(
        measureFootRectified(
          footOutline: badOutline,
          refCorners: cardQuad(),
          paper: PaperDimensions.card,
        ),
        isNull,
      );
      final badCorners = List<Offset>.from(cardQuad())
        ..[1] = const Offset(double.infinity, 100);
      expect(
        measureFootRectified(
          footOutline: ellipse(),
          refCorners: badCorners,
          paper: PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('corner order does not matter (cyclic sort)', () {
      final shuffled = [cardQuad()[2], cardQuad()[0], cardQuad()[3], cardQuad()[1]];
      final m = measureFootRectified(
        footOutline: ellipse(),
        refCorners: shuffled,
        paper: PaperDimensions.card,
      )!;
      expect(m.lengthMm, closeTo(96.3, 0.5));
    });

    test('foot beside (outside) the card still measures — no clip', () {
      // Real captures put the foot NEXT to the card; homography
      // extrapolates linearly and must not refuse.
      final beside = ellipse(cx: 350, cy: 150);
      final m = measureFootRectified(
        footOutline: beside,
        refCorners: cardQuad(),
        paper: PaperDimensions.card,
      )!;
      expect(m.lengthMm, closeTo(96.3, 0.5));
      expect(m.widthMm, closeTo(26.99, 0.5));
    });

    test('portrait card maps axes with the card (orientation-safe)', () {
      // Card standing portrait: x∈[100,200]→85.6, y∈[100,260]→53.98.
      final portrait = [
        const Offset(100, 100),
        const Offset(200, 100),
        const Offset(200, 260),
        const Offset(100, 260),
      ];
      expect(isPlausibleReferenceQuad(portrait, PaperDimensions.card), isTrue);
      // Vertical ellipse: 180px tall → 180*53.98/160 = 60.73mm long,
      // 50px wide → 50*85.6/100 = 42.8mm wide.
      final m = measureFootRectified(
        footOutline: ellipse(cx: 150, cy: 180, rx: 25, ry: 90),
        refCorners: portrait,
        paper: PaperDimensions.card,
      )!;
      expect(m.lengthMm, closeTo(60.73, 0.6));
      expect(m.widthMm, closeTo(42.8, 0.6));
    });
  });

  group('homographyPixelsToMm — hostile', () {
    test('degenerate quad (all same point) → null', () {
      expect(
        homographyPixelsToMm(
          List.filled(4, const Offset(100, 100)),
          PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('wrong corner count → null', () {
      expect(
        homographyPixelsToMm(
          const [Offset(0, 0), Offset(1, 1)],
          PaperDimensions.card,
        ),
        isNull,
      );
    });

    test('identity check: quad corners map to rect corners in mm', () {
      final h = homographyPixelsToMm(cardQuad(), PaperDimensions.card)!;
      final mapped = cardQuad().map((c) => applyHomography(h, c)!).toList();
      // Cyclic order preserved; numerically equal to the mm rectangle.
      final expected = [
        const Offset(0, 0),
        const Offset(85.6, 0),
        const Offset(85.6, 53.98),
        const Offset(0, 53.98),
      ];
      for (var i = 0; i < 4; i++) {
        expect(mapped[i].dx, closeTo(expected[i].dx, 1e-6));
        expect(mapped[i].dy, closeTo(expected[i].dy, 1e-6));
      }
    });

    test('applyHomography guards bad input', () {
      final h = homographyPixelsToMm(cardQuad(), PaperDimensions.card)!;
      expect(applyHomography(h, const Offset(double.nan, 0)), isNull);
      expect(applyHomography([1.0, 2.0], const Offset(0, 0)), isNull);
    });
  });

  group('adjustReferenceCorner — fallback', () {
    test('valid drag replaces one corner', () {
      final out = adjustReferenceCorner(
        cardQuad(),
        1,
        const Offset(262, 102),
      )!;
      expect(out[1], const Offset(262, 102));
      expect(out[0], cardQuad()[0]);
    });

    test('bad input keeps old quad (null)', () {
      expect(adjustReferenceCorner(cardQuad(), -1, const Offset(0, 0)), isNull);
      expect(adjustReferenceCorner(cardQuad(), 4, const Offset(0, 0)), isNull);
      expect(
        adjustReferenceCorner(cardQuad(), 1, const Offset(double.nan, 0)),
        isNull,
      );
      expect(
        adjustReferenceCorner(
          const [Offset(0, 0), Offset(1, 1)],
          0,
          const Offset(0, 0),
        ),
        isNull,
      );
    });

    test('adjusted quad is still gated before measuring', () {
      // Drag a corner into a keystone: adjustment succeeds, but the
      // validator must refuse it for measurement.
      final dragged = adjustReferenceCorner(
        cardQuad(),
        1,
        const Offset(140, 100),
      )!;
      expect(
        diagnoseReferenceQuad(dragged, PaperDimensions.card).isNotEmpty,
        isTrue,
      );
      expect(
        measureFootRectified(
          footOutline: ellipse(),
          refCorners: dragged,
          paper: PaperDimensions.card,
        ),
        isNull,
      );
    });
  });

  group('recommendCardSizes — no fake precision', () {
    test('clear high-confidence fit → single size', () {
      // 268mm + 8 allowance = 276 → EU 43 (273–280), 3mm past the
      // threshold: outside the 2mm boundary band, so one honest size.
      // (Exactly ON a threshold, e.g. 265.0, correctly shows a range.)
      final r = recommendCardSizes(
        compensatedLengthMm: 268,
        measurementSource: 'paper',
        confidenceLevel: 'high',
      )!;
      expect(r.eu, '43');
      expect(r.isSingleSize, isTrue);
      expect(r.confidenceLabel, contains('High'));
      expect(r.us, isNot('—'));
      expect(r.uk, isNot('—'));
    });

    test('near boundary → range of two, honest label', () {
      // 265.5 + 8 = 273.5, just 0.5 past the EU43 threshold → range 42–43.
      final r = recommendCardSizes(
        compensatedLengthMm: 265.5,
        measurementSource: 'paper',
        confidenceLevel: 'high',
      )!;
      expect(r.eu, '43');
      expect(r.rangeLowEu, '42');
      expect(r.rangeHighEu, '43');
      expect(r.isSingleSize, isFalse);
      expect(r.confidenceLabel, contains('Between sizes'));
    });

    test('low confidence → range + confirm-fit label', () {
      // 268 is NOT near a boundary, so the low-confidence branch owns the
      // label. (Near-boundary + low confidence reports 'Between sizes',
      // which is the more actionable of the two true statements.)
      final r = recommendCardSizes(
        compensatedLengthMm: 268,
        measurementSource: 'paper',
        confidenceLevel: 'low',
      )!;
      expect(r.isSingleSize, isFalse);
      expect(r.confidenceLabel, contains('confirm fit'));
    });

    test('garbage in → null, never a size', () {
      expect(
        recommendCardSizes(
          compensatedLengthMm: double.nan,
          measurementSource: 'paper',
        ),
        isNull,
      );
      expect(
        recommendCardSizes(
          compensatedLengthMm: 50, // 5cm foot: hard reject
          measurementSource: 'paper',
        ),
        isNull,
      );
      expect(
        recommendCardSizes(
          compensatedLengthMm: 400, // 40cm foot: hard reject
          measurementSource: 'paper',
        ),
        isNull,
      );
    });

    test('sock compensation composes with sizing', () {
      // 271mm in socks → 268 bare → EU 43 single (see clear-fit test).
      final comp = applySockCompensation(271, isLength: true, isSocks: true);
      expect(comp, 268.0);
      final r = recommendCardSizes(
        compensatedLengthMm: comp,
        measurementSource: 'paper',
        confidenceLevel: 'high',
      )!;
      expect(r.eu, '43');
      expect(r.isSingleSize, isTrue);
    });
  });
}
