import 'dart:math';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/foot_measurement_utils.dart';

void main() {
  group('PaperDimensions', () {
    test('A4 has correct dimensions', () {
      expect(PaperDimensions.a4.widthMm, 210.0);
      expect(PaperDimensions.a4.heightMm, 297.0);
    });

    test('US Letter has correct dimensions', () {
      expect(PaperDimensions.letter.widthMm, 215.9);
      expect(PaperDimensions.letter.heightMm, 279.4);
    });

    test('fromKey returns A4 for "a4"', () {
      final paper = PaperDimensions.fromKey('a4');
      expect(paper.widthMm, 210.0);
      expect(paper.name, 'A4');
    });

    test('fromKey returns Letter for "letter"', () {
      final paper = PaperDimensions.fromKey('letter');
      expect(paper.widthMm, 215.9);
      expect(paper.name, 'US Letter');
    });

    test('fromKey defaults to A4 for unknown key', () {
      final paper = PaperDimensions.fromKey('unknown');
      expect(paper.widthMm, 210.0);
    });
  });

  group('pixelsToMm', () {
    test('converts pixels to mm with known scale factor', () {
      expect(pixelsToMm(100, 2.0), 200.0);
      expect(pixelsToMm(0, 2.0), 0.0);
      expect(pixelsToMm(50, 0.5), 25.0);
    });

    test('handles zero scale factor', () {
      expect(pixelsToMm(100, 0.0), 0.0);
    });
  });

  group('computeScaleFactor', () {
    test('returns null for fewer than 4 corners', () {
      final paper = PaperDimensions.a4;
      expect(computeScaleFactor(paperCorners: [], paper: paper), isNull);
      expect(
        computeScaleFactor(
          paperCorners: [Offset.zero, Offset(100, 0)],
          paper: paper,
        ),
        isNull,
      );
    });

    test('returns null for very small detected paper (degenerate)', () {
      final paper = PaperDimensions.a4;
      // All corners at the same point = zero diagonal
      final corners = [
        const Offset(100, 100),
        const Offset(100, 100),
        const Offset(100, 100),
        const Offset(100, 100),
      ];
      expect(computeScaleFactor(paperCorners: corners, paper: paper), isNull);
    });

    test('returns a reasonable scale factor for valid corners', () {
      final paper = PaperDimensions.a4;
      // Simulate a paper that spans 500px diagonally
      // A4 diagonal = sqrt(210^2 + 297^2) ≈ 363.7mm
      // Scale = 363.7 / 500 ≈ 0.727 mm/px
      final corners = [
        const Offset(100, 50),
        const Offset(400, 50),
        const Offset(400, 550),
        const Offset(100, 550),
      ];
      final scale = computeScaleFactor(paperCorners: corners, paper: paper);
      expect(scale, isNotNull);
      expect(scale!, greaterThan(0.3));
      expect(scale, lessThan(2.0));
    });
  });

  group('footLengthMmToEuSize', () {
    test('maps 265mm to a valid EU size (with 8mm allowance = 273mm)', () {
      final size = footLengthMmToEuSize(265);
      expect(size, isNotNull);
      // The exact size depends on the chart; verify it's a valid EU size
      final eu = int.tryParse(size!);
      expect(eu, greaterThanOrEqualTo(35));
      expect(eu, lessThanOrEqualTo(48));
    });

    test('maps very small foot to smallest size', () {
      final size = footLengthMmToEuSize(130);
      expect(size, '22');
    });

    test('maps very large foot to largest size', () {
      final size = footLengthMmToEuSize(310);
      expect(size, '48');
    });

    test('returns valid EU sizes for common adult foot lengths', () {
      // Test a range of common adult foot lengths
      for (double mm = 220; mm <= 300; mm += 10) {
        final size = footLengthMmToEuSize(mm);
        expect(size, isNotNull, reason: 'Size for ${mm}mm should not be null');
        final eu = int.tryParse(size!);
        expect(
          eu,
          greaterThanOrEqualTo(35),
          reason: 'EU size for ${mm}mm should be >= 35',
        );
        expect(
          eu,
          lessThanOrEqualTo(48),
          reason: 'EU size for ${mm}mm should be <= 48',
        );
      }
    });
  });

  group('euToUs', () {
    test('converts EU 42 to US 9', () {
      expect(euToUs('42'), '9');
    });

    test('converts EU 38 to US 5', () {
      expect(euToUs('38'), '5');
    });

    test('returns null for invalid input', () {
      expect(euToUs(''), null);
      expect(euToUs('abc'), null);
    });
  });

  group('euToUk', () {
    test('converts EU 42 to UK 8 or 9', () {
      final uk = euToUk('42');
      expect(uk, isNotNull);
      final ukNum = int.tryParse(uk!);
      expect(ukNum, greaterThanOrEqualTo(7));
      expect(ukNum, lessThanOrEqualTo(10));
    });

    test('returns null for invalid input', () {
      expect(euToUk(''), null);
      expect(euToUk('xyz'), null);
    });
  });

  group('computePaperConfidence', () {
    test('returns 0 for fewer than 4 corners', () {
      expect(computePaperConfidence([]), 0.0);
      expect(computePaperConfidence([Offset.zero, Offset(100, 0)]), 0.0);
    });

    test('returns high confidence for a near-perfect rectangle', () {
      // A perfect rectangle
      final corners = [
        const Offset(100, 100),
        const Offset(400, 100),
        const Offset(400, 500),
        const Offset(100, 500),
      ];
      final confidence = computePaperConfidence(corners);
      expect(confidence, greaterThan(0.8));
    });

    test('returns lower confidence for a distorted shape', () {
      // A very distorted quadrilateral
      final corners = [
        const Offset(100, 100),
        const Offset(500, 100),
        const Offset(300, 500),
        const Offset(100, 400),
      ];
      final confidence = computePaperConfidence(corners);
      expect(confidence, lessThan(0.8));
    });
  });

  group('computeLightingQuality', () {
    test('returns 1.0 for optimal brightness (80-180)', () {
      expect(computeLightingQuality(80), 1.0);
      expect(computeLightingQuality(130), 1.0);
      expect(computeLightingQuality(180), 1.0);
    });

    test('returns lower score for very dark images', () {
      expect(computeLightingQuality(20), lessThan(0.5));
      expect(computeLightingQuality(50), lessThan(1.0));
    });

    test('returns lower score for very bright images', () {
      expect(computeLightingQuality(220), lessThan(0.5));
      expect(computeLightingQuality(250), lessThan(1.0));
    });

    test('never returns below 0.2', () {
      expect(computeLightingQuality(0), greaterThanOrEqualTo(0.2));
      expect(computeLightingQuality(255), greaterThanOrEqualTo(0.2));
    });
  });

  group('FootMeasurementResult computation', () {
    test('computeFootMeasurements returns null for too few points', () {
      final outline = List.generate(5, (i) => Offset(i * 10.0, 0));
      expect(
        computeFootMeasurements(footOutline: outline, scaleFactor: 1.0),
        isNull,
      );
    });

    test(
      'computeFootMeasurements returns valid measurements for a foot-shaped outline',
      () {
        // Simulate a rough foot outline (20+ points)
        final outline = <Offset>[];
        for (double angle = 0; angle < 360; angle += 15) {
          final rad = angle * pi / 180;
          // Elongated ellipse (foot-like)
          final rx =
              50 + 30 * (angle < 180 ? 1 : 0.8); // slightly longer on one side
          final ry = 25;
          outline.add(Offset(100 + rx * cos(rad), 100 + ry * sin(rad)));
        }

        final measurements = computeFootMeasurements(
          footOutline: outline,
          scaleFactor: 0.5,
        );
        expect(measurements, isNotNull);
        expect(measurements!.lengthMm, greaterThan(50));
        expect(measurements.widthMm, greaterThan(20));
        expect(measurements.lengthMm, greaterThan(measurements.widthMm));
      },
    );
  });

  group('comfortAllowanceMm', () {
    test('is 8mm', () {
      expect(comfortAllowanceMm, 8.0);
    });
  });

  group('mapNormalizedToView (§3 shared overlay transform)', () {
    test('maps normalized center to view center (no drift)', () {
      // Landscape frame 1920×1080 on a portrait view 1080×1920 → center of
      // the frame must land exactly at the center of the view.
      final p = mapNormalizedToView(
        const Offset(0.5, 0.5),
        const Size(1080, 1920),
        frameWidth: 1920,
        frameHeight: 1080,
      );
      expect(p.dx, closeTo(540.0, 0.5));
      expect(p.dy, closeTo(960.0, 0.5));
    });

    test('crops the overflowing axis (landscape frame → portrait view)', () {
      // Frame 1920×1080 (aspect 1.78) is wider than the view (aspect 0.56),
      // so the left/right edges are cropped: normalized x=0 maps off-screen
      // to the left, x=1 maps off-screen to the right.
      final left = mapNormalizedToView(
        const Offset(0.0, 0.5),
        const Size(1080, 1920),
        frameWidth: 1920,
        frameHeight: 1080,
      );
      final right = mapNormalizedToView(
        const Offset(1.0, 0.5),
        const Size(1080, 1920),
        frameWidth: 1920,
        frameHeight: 1080,
      );
      expect(left.dx, lessThan(0));
      expect(right.dx, greaterThan(1080));
      // The non-cropped axis fills the view exactly.
      expect(left.dy, closeTo(960.0, 0.5));
      expect(right.dy, closeTo(960.0, 0.5));
    });

    test('crops the overflowing axis (portrait frame → landscape view)', () {
      // Frame 1080×1920 (aspect 0.56) is taller than the view 1920×1080
      // (aspect 1.78), so the top/bottom edges are cropped.
      final top = mapNormalizedToView(
        const Offset(0.5, 0.0),
        const Size(1920, 1080),
        frameWidth: 1080,
        frameHeight: 1920,
      );
      final bottom = mapNormalizedToView(
        const Offset(0.5, 1.0),
        const Size(1920, 1080),
        frameWidth: 1080,
        frameHeight: 1920,
      );
      expect(top.dy, lessThan(0));
      expect(bottom.dy, greaterThan(1080));
      expect(top.dx, closeTo(960.0, 0.5));
      expect(bottom.dx, closeTo(960.0, 0.5));
    });

    test('identity when frame and view aspects match', () {
      final p = mapNormalizedToView(
        const Offset(0.25, 0.75),
        const Size(400, 400),
        frameWidth: 400,
        frameHeight: 400,
      );
      expect(p.dx, closeTo(100.0, 0.5));
      expect(p.dy, closeTo(300.0, 0.5));
    });

    test('falls back to direct scaling when frame dims unknown', () {
      final p = mapNormalizedToView(
        const Offset(0.25, 0.75),
        const Size(400, 400),
        frameWidth: 0,
        frameHeight: 0,
      );
      expect(p.dx, closeTo(100.0, 0.5));
      expect(p.dy, closeTo(300.0, 0.5));
    });
  });

  group('mapViewToNormalized (manual tap-to-measure inverse transform)', () {
    test('round-trips a landscape frame through a portrait view', () {
      // Landscape sensor frame (1920x1080) center-cropped into a portrait
      // view (1080x1920). Any normalized point should survive
      // view->normalized->view unchanged.
      const view = Size(1080, 1920);
      const frameW = 1920;
      const frameH = 1080;

      for (final norm in const [
        Offset(0.5, 0.5),
        Offset(0.25, 0.75),
        Offset(0.9, 0.1),
        Offset(0.1, 0.9),
      ]) {
        final viewPx = mapNormalizedToView(
          norm,
          view,
          frameWidth: frameW,
          frameHeight: frameH,
        );
        final back = mapViewToNormalized(
          viewPx,
          view,
          frameWidth: frameW,
          frameHeight: frameH,
        );
        expect(back.dx, closeTo(norm.dx, 1e-4), reason: 'norm=$norm');
        expect(back.dy, closeTo(norm.dy, 1e-4), reason: 'norm=$norm');
      }
    });

    test('round-trips a portrait frame through a landscape view', () {
      const view = Size(1920, 1080);
      const frameW = 1080;
      const frameH = 1920;

      for (final norm in const [
        Offset(0.5, 0.5),
        Offset(0.3, 0.7),
        Offset(0.8, 0.2),
      ]) {
        final viewPx = mapNormalizedToView(
          norm,
          view,
          frameWidth: frameW,
          frameHeight: frameH,
        );
        final back = mapViewToNormalized(
          viewPx,
          view,
          frameWidth: frameW,
          frameHeight: frameH,
        );
        expect(back.dx, closeTo(norm.dx, 1e-4), reason: 'norm=$norm');
        expect(back.dy, closeTo(norm.dy, 1e-4), reason: 'norm=$norm');
      }
    });

    test('center tap maps to the frame center regardless of crop axis', () {
      // The screen center is always the upright-frame center in both crops.
      const view = Size(1080, 1920);
      const frameW = 1920;
      const frameH = 1080;
      final center = mapViewToNormalized(
        Offset(view.width / 2, view.height / 2),
        view,
        frameWidth: frameW,
        frameHeight: frameH,
      );
      expect(center.dx, closeTo(0.5, 1e-4));
      expect(center.dy, closeTo(0.5, 1e-4));
    });

    test('identity when frame and view aspects match', () {
      final p = mapViewToNormalized(
        const Offset(100, 300),
        const Size(400, 400),
        frameWidth: 400,
        frameHeight: 400,
      );
      expect(p.dx, closeTo(0.25, 1e-4));
      expect(p.dy, closeTo(0.75, 1e-4));
    });

    test('falls back to direct scaling when frame dims unknown', () {
      final p = mapViewToNormalized(
        const Offset(100, 300),
        const Size(400, 400),
        frameWidth: 0,
        frameHeight: 0,
      );
      expect(p.dx, closeTo(0.25, 1e-4));
      expect(p.dy, closeTo(0.75, 1e-4));
    });

    test('clamps out-of-frame taps into the 0-1 range', () {
      // Taps outside the drawn (cropped) region must still produce a valid
      // normalized coordinate the native hitTest can accept.
      final p = mapViewToNormalized(
        const Offset(-50, -50),
        const Size(1080, 1920),
        frameWidth: 1920,
        frameHeight: 1080,
      );
      expect(p.dx, greaterThanOrEqualTo(0.0));
      expect(p.dy, greaterThanOrEqualTo(0.0));
      expect(p.dx, lessThanOrEqualTo(1.0));
      expect(p.dy, lessThanOrEqualTo(1.0));
    });
  });
}
