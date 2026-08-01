/// Unit tests for the segmentation-mask → foot-points extraction logic
/// (`evaluateFootMask` in foot_detector.dart).
///
/// This is the geometric core of the segmentation fallback detector and is
/// pure Dart (no ML runtime needed), so it's independently testable (§2.2 /
/// §8 of the implementation briefs).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/foot_detector.dart';

/// Build a synthetic mask: a foreground (confidence 1.0) region defined by a
/// list of (row, col) cells on an [w]×[h] grid, everything else 0.0.
List<double> _maskWithCells(int w, int h, List<(int, int)> cells) {
  final confidences = List<double>.filled(w * h, 0.0);
  for (final (row, col) in cells) {
    if (row >= 0 && row < h && col >= 0 && col < w) {
      confidences[row * w + col] = 1.0;
    }
  }
  return confidences;
}

/// Cells forming a 45°-oriented parallelogram (foot-like elongation), used to
/// verify the principal-axis logic is not assuming vertical orientation.
/// [halfLen] is the half-extent along the principal axis, [halfPerp] the
/// half-extent perpendicular to it (both in grid cells).
List<(int, int)> _diagonalParallelogramCells({
  required double halfLen,
  required double halfPerp,
}) {
  const center = 50.0;
  final cells = <(int, int)>[];
  const invSqrt2 = 0.7071067811865476;
  for (int r = 0; r < 100; r++) {
    for (int c = 0; c < 100; c++) {
      final dx = c - center;
      final dy = r - center;
      final proj = (dx + dy) * invSqrt2;
      final perp = (dy - dx) * invSqrt2;
      if (proj.abs() <= halfLen && perp.abs() <= halfPerp) {
        cells.add((r, c));
      }
    }
  }
  return cells;
}

/// Cells forming a vertical foot-shaped blob on a 100×100 grid:
/// a rounded column, wider at the bottom (heel side), narrower at the top (toe).
List<(int, int)> _verticalFootCells() {
  final cells = <(int, int)>[];
  // Toe: narrow column, rows 10..29, cols 48..51
  for (int r = 10; r <= 29; r++) {
    for (int c = 48; c <= 51; c++) {
      cells.add((r, c));
    }
  }
  // Mid: rows 30..69, cols 45..54
  for (int r = 30; r <= 69; r++) {
    for (int c = 45; c <= 54; c++) {
      cells.add((r, c));
    }
  }
  // Heel: wider, rows 70..89, cols 40..59
  for (int r = 70; r <= 89; r++) {
    for (int c = 40; c <= 59; c++) {
      cells.add((r, c));
    }
  }
  return cells;
}

void main() {
  const w = 100;
  const h = 100;

  group('evaluateFootMask — gating', () {
    test('returns negative for empty/short confidences', () {
      final result = evaluateFootMask(
        confidences: const [],
        width: w,
        height: h,
      );
      expect(result.footDetected, isFalse);
    });

    test('returns negative for zero-size mask', () {
      final result = evaluateFootMask(
        confidences: [0.0],
        width: 0,
        height: 0,
      );
      expect(result.footDetected, isFalse);
    });

    test('returns negative for a tiny foreground blob (noise)', () {
      // Only 10 pixels above threshold — below minFootMaskPixels.
      final cells = [for (int i = 0; i < 10; i++) (i, i)];
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.footDetected, isFalse);
    });

    test('returns negative for all-zero mask', () {
      final result = evaluateFootMask(
        confidences: List<double>.filled(w * h, 0.0),
        width: w,
        height: h,
      );
      expect(result.footDetected, isFalse);
    });
  });

  group('evaluateFootMask — detection & points', () {
    test('detects a vertical foot-shaped blob', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
      expect(result.confidence, greaterThan(0.5));
      expect(result.heelPoint, isNotNull);
      expect(result.toePoint, isNotNull);
      expect(result.widthPoints, isNotNull);
      expect(result.widthPoints!.length, 2);
    });

    test('heel is the wider end (bottom), toe the narrower end (top)', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
      );
      // Principal axis is vertical; wider end (heel) is at higher row
      // (larger y). Toe is the narrow end at smaller y.
      expect(result.heelPoint!.y, greaterThan(result.toePoint!.y));
    });

    test('heel-toe axis follows the blob orientation (not assumed vertical)', () {
      // Diagonal foot-shaped parallelogram: 80 units along a 45° axis and
      // 16 units of perpendicular width → aspect ratio ≈ 5.0 (foot-plausible,
      // within [minFootAspectRatio, maxFootAspectRatio]).
      final cells = _diagonalParallelogramCells(halfLen: 40, halfPerp: 8);
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
      final heel = result.heelPoint!;
      final toe = result.toePoint!;
      final length = math.sqrt(
        (heel.x - toe.x) * (heel.x - toe.x) + (heel.y - toe.y) * (heel.y - toe.y),
      );
      // The heel and toe should be substantially separated along the long axis.
      expect(length, greaterThan(0.3));
    });

    test('widthPoints span the widest part of the blob', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
      );
      final widthPoints = result.widthPoints!;
      // Widest part is the heel band (cols 40..59) → x separation ≈ 0.19
      final xSpan = (widthPoints[1].x - widthPoints[0].x).abs();
      expect(xSpan, greaterThan(0.15));
    });

    test('reports preferSide as the assumed side', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
        preferSide: 'left',
      );
      expect(result.footDetected, isTrue);
      expect(result.footSide, 'left');
    });
  });

  group('evaluateFootMask — shape validation (§1.1 false-positive rejection)', () {
    test('rejects a whole-frame foreground mask (wall/object filling camera)', () {
      // 100% foreground → above maxFootMaskForegroundFraction.
      final confidences = List<double>.filled(w * h, 0.95);
      final result = evaluateFootMask(
        confidences: confidences,
        width: w,
        height: h,
      );
      expect(result.footDetected, isFalse);
    });

    test('rejects a round/squarish blob (hand, balled-up cloth)', () {
      // Circle radius 18 → aspect ratio ≈ 1.0, below minFootAspectRatio.
      final cells = <(int, int)>[];
      final cx = 50.0;
      final cy = 50.0;
      for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
          final d = math.sqrt((r - cy) * (r - cy) + (c - cx) * (c - cx));
          if (d <= 18) cells.add((r, c));
        }
      }
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.footDetected, isFalse);
    });

    test('rejects a thread-thin strip (fold in clothing, cable)', () {
      // A 4-cell-wide × 60-cell-long diagonal strip (~240 cells, well above
      // the 200-pixel area floor) → elongation far above maxFootAspectRatio,
      // so it's rejected by the SHAPE check rather than the area check.
      final cells = <(int, int)>[];
      for (int t = 0; t < 60; t++) {
        for (int d = 0; d < 4; d++) {
          cells.add((20 + t, 20 + t + d));
        }
      }
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.footDetected, isFalse);
    });
  });

  group('evaluateFootMask — guide-box overlap (§2.3 position sanity)', () {
    test('accepts a mask substantially inside the guide box', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
        guideRect: const Rect.fromLTRB(0.30, 0.05, 0.70, 0.95),
      );
      expect(result.footDetected, isTrue);
    });

    test('rejects a mask sitting in a corner outside the guide box', () {
      // Corner guide that the vertical foot blob (center) does NOT overlap.
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
        guideRect: const Rect.fromLTRB(0.75, 0.75, 1.0, 1.0),
      );
      expect(result.footDetected, isFalse);
    });

    test('no guide box means no position check (backward compatible)', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
    });
  });

  group('evaluateFootMask — connected-component isolation (§1.1)', () {
    test('ignores a disconnected secondary foreground region', () {
      // The vertical foot blob PLUS a large disconnected blob in the top-right
      // corner (e.g. leg/ankle skin or a hand at the frame edge). Without
      // §1.1 isolation the corner blob would pull the PCA / extreme points
      // toward it; with it, every point must come from the foot.
      final cells = <(int, int)>[
        ..._verticalFootCells(),
        // Secondary blob: rows 2..22, cols 82..97 (21×16 = 336 cells, above
        // the 200-pixel area floor). Disconnected — the foot's columns end
        // at 59, the blob starts at 82.
        for (int r = 2; r <= 22; r++)
          for (int c = 82; c <= 97; c++) (r, c),
      ];
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
      // Foot columns are 40..59 → normalized x ∈ [0.40, 0.59]. The secondary
      // blob would produce x ≥ 0.82, so all points must stay ≤ 0.65.
      for (final p in [
        result.heelPoint!,
        result.toePoint!,
        ...result.widthPoints!,
      ]) {
        expect(p.x, inInclusiveRange(0.35, 0.65));
      }
    });

    test('largest component wins even when a patch is large', () {
      // A big disconnected blob (rows 55..94, cols 80..95 → 40×16 = 640 cells)
      // that alone would still pass the area/elongation checks — but it is
      // NOT the largest component, so the foot (880 cells) must drive the
      // geometry.
      final cells = <(int, int)>[
        ..._verticalFootCells(),
        for (int r = 55; r <= 94; r++)
          for (int c = 80; c <= 95; c++) (r, c),
      ];
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
      for (final p in [result.heelPoint!, result.toePoint!]) {
        expect(p.x, inInclusiveRange(0.35, 0.65));
      }
    });

    test('reported case: shoe in the guide box + out-of-box leg skin patch', () {
      // Mirrors the screenshot: the foot fills the guide box; a disconnected
      // patch (leg/ankle skin) sits at the frame edge, outside the box. The
      // points must land on the foot inside the box — never on the patch.
      final cells = <(int, int)>[
        ..._verticalFootCells(),
        // Patch: rows 60..99, cols 78..95 (40×18 = 720 cells).
        for (int r = 60; r <= 99; r++)
          for (int c = 78; c <= 95; c++) (r, c),
      ];
      final guideRect = const Rect.fromLTRB(0.30, 0.05, 0.70, 0.95);
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
        guideRect: guideRect,
      );
      expect(result.footDetected, isTrue);
      for (final p in [
        result.heelPoint!,
        result.toePoint!,
        ...result.widthPoints!,
      ]) {
        expect(guideRect.contains(Offset(p.x, p.y)), isTrue);
      }
    });
  });

  group('evaluateFootMask — guide-box clipping (§1.2)', () {
    test('clips out-of-box mask pixels before point extraction', () {
      // A foot blob WIDER than the guide box: cols 30..69 (x 0.30–0.69). The
      // box covers only cols 40..59 — exactly 50% of the width, meeting
      // minGuideOverlapFraction while leaving 10 columns outside on each side.
      final cells = <(int, int)>[
        for (int r = 10; r <= 89; r++)
          for (int c = 30; c <= 69; c++) (r, c),
      ];
      const guideRect = Rect.fromLTRB(0.40, 0.05, 0.60, 0.95);
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
        guideRect: guideRect,
      );
      expect(result.footDetected, isTrue);
      // Without §1.2 clipping, the widest points would sit at x ≈ 0.30/0.69
      // (outside the box). With clipping, every point is inside.
      for (final p in [
        result.heelPoint!,
        result.toePoint!,
        ...result.widthPoints!,
      ]) {
        expect(guideRect.contains(Offset(p.x, p.y)), isTrue);
      }
    });
  });

  group('evaluateFootMask — confidence', () {
    test('confidence reflects foreground mask confidence', () {
      // Half the cells at 0.6 confidence, half at 1.0 → mean ≈ 0.8
      final confidences = List<double>.filled(w * h, 0.0);
      final cells = _verticalFootCells();
      var sum = 0.0;
      for (final (r, c) in cells) {
        final conf = ((r + c) % 2 == 0) ? 0.6 : 1.0;
        confidences[r * w + c] = conf;
        sum += conf;
      }
      final expected = sum / cells.length;
      final result = evaluateFootMask(
        confidences: confidences,
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
      expect(result.confidence, closeTo(expected, 0.01));
    });
  });

  group('evaluateFootMask — weighted scoring (§1)', () {
    test('exposes sub-scores and a combined quality score', () {
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
      );
      expect(result.footDetected, isTrue);
      expect(result.qualityScore, greaterThanOrEqualTo(kSampleAcceptScore));
      expect(result.segmentationScore, greaterThan(0.5));
      expect(result.shapeScore, greaterThan(0.5));
      expect(result.containmentScore, 1.0); // No guide box → neutral
    });

    test('partial guide-box overlap yields a partial containment score', () {
      // Guide box covers only the left half (cols 40–49) of the foot
      // (cols 40–59) → ~50% containment, which partially credits the score.
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, _verticalFootCells()),
        width: w,
        height: h,
        guideRect: const Rect.fromLTRB(0.40, 0.05, 0.50, 0.95),
      );
      expect(result.containmentScore, greaterThan(0.0));
      expect(result.containmentScore, lessThan(1.0));
      // Points must still come from inside the (clipped) guide box.
      for (final p in [result.heelPoint!, result.toePoint!]) {
        expect(p.x, lessThanOrEqualTo(0.50));
      }
    });

    test('below-threshold combined score yields footDetected false', () {
      // Round blob: shape sub-score ≈ 0, so the combined score is
      // ≈ 0.25·seg + 0.35·0 + 0.40·cont = 0.65 < kSampleAcceptScore even
      // though segmentation confidence is 1.0 — the score model rejects it
      // instead of the old hard aspect gate.
      final cells = <(int, int)>[];
      final cx = 50.0;
      final cy = 50.0;
      for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
          final d = math.sqrt((r - cy) * (r - cy) + (c - cx) * (c - cx));
          if (d <= 18) cells.add((r, c));
        }
      }
      final result = evaluateFootMask(
        confidences: _maskWithCells(w, h, cells),
        width: w,
        height: h,
      );
      expect(result.qualityScore, lessThan(kSampleAcceptScore));
      expect(result.footDetected, isFalse);
    });
  });

  group('footShapeScore (§1.2)', () {
    test('scores 1.0 on the ideal plateau', () {
      expect(footShapeScore(3.0), closeTo(1.0, 0.001));
      expect(footShapeScore(4.0), closeTo(1.0, 0.001));
    });

    test('decays toward 0 at the acceptability edges', () {
      expect(footShapeScore(2.0), greaterThan(0.0));
      expect(footShapeScore(2.0), lessThan(1.0));
      expect(footShapeScore(5.5), greaterThan(0.0));
      expect(footShapeScore(5.5), lessThan(1.0));
    });

    test('scores 0 well outside the range', () {
      expect(footShapeScore(1.0), 0.0);
      expect(footShapeScore(6.5), 0.0);
      expect(footShapeScore(0.5), 0.0);
    });
  });

  group('combineQualityScore (§1.3)', () {
    test('perfect sub-scores give 1.0', () {
      expect(
        combineQualityScore(
          segmentationScore: 1.0,
          shapeScore: 1.0,
          containmentScore: 1.0,
        ),
        closeTo(1.0, 0.001),
      );
    });

    test('weighted combination respects the containment weight', () {
      // A frame with perfect segmentation/shape but zero containment: the
      // combined score is just (seg + shape) weights and must fall below the
      // accept threshold, confirming containment carries real weight.
      final score = combineQualityScore(
        segmentationScore: 1.0,
        shapeScore: 1.0,
        containmentScore: 0.0,
      );
      expect(
        score,
        closeTo(kQualityWeightSegmentation + kQualityWeightShape, 0.001),
      );
      expect(score, lessThan(kSampleAcceptScore));
    });
  });
}
