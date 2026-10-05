import 'package:app/utils/foot_detector.dart';
import 'package:app/utils/foot_pose.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pure detection → pose mapping (V4.1).
///
/// This file exists because the mapping is where a coordinate convention can be
/// flipped without anything throwing: the numbers are normalized UV on both
/// sides, and the only way to notice a swap is a test that knows what the
/// answer should be. No ML runtime, no channel, no controller — just the rule.
void main() {
  FootDetectionResult detection({
    bool detected = true,
    double quality = 0.8,
    FootPoint? heel,
    FootPoint? toe,
    List<FootPoint>? width,
    String? side = 'right',
  }) =>
      FootDetectionResult(
        footDetected: detected,
        confidence: quality,
        qualityScore: quality,
        footSide: side,
        heelPoint: heel ?? const FootPoint(x: 0.30, y: 0.80, likelihood: 0.9),
        toePoint: toe ?? const FootPoint(x: 0.35, y: 0.20, likelihood: 0.9),
        widthPoints: width,
      );

  group('footPoseFromDetection', () {
    test('a detected foot with both ends becomes a pose frame', () {
      final frame = footPoseFromDetection(detection());

      expect(frame, isNotNull);
      expect(frame!.heelUv, const Offset(0.30, 0.80));
      expect(frame.toeUv, const Offset(0.35, 0.20));
      expect(frame.footSide, 'right');
      expect(frame.confidence, 0.8);
    });

    test('the confidence sent is the combined quality score', () {
      // The detector's `confidence` (landmark likelihood) and its
      // `qualityScore` (segmentation + shape + containment) are different
      // numbers, and the native lock compares against the second one. Sending
      // the first would lock a foot the scan would have refused.
      final frame = footPoseFromDetection(
        FootDetectionResult(
          footDetected: true,
          confidence: 0.95,
          qualityScore: 0.72,
          footSide: 'left',
          heelPoint: const FootPoint(x: 0.1, y: 0.9, likelihood: 0.95),
          toePoint: const FootPoint(x: 0.2, y: 0.1, likelihood: 0.95),
        ),
      );

      expect(frame!.confidence, 0.72);
    });

    test('a negative detection is no frame, whatever else is present', () {
      expect(
        footPoseFromDetection(
          detection(
            detected: false,
            heel: const FootPoint(x: 0.1, y: 0.9, likelihood: 0.9),
            toe: const FootPoint(x: 0.2, y: 0.1, likelihood: 0.9),
          ),
        ),
        isNull,
      );
    });

    test('a frame missing either end cannot describe an axis', () {
      expect(
        footPoseFromDetection(
          FootDetectionResult(
            footDetected: true,
            confidence: 0.9,
            qualityScore: 0.9,
            toePoint: const FootPoint(x: 0.2, y: 0.1, likelihood: 0.9),
          ),
        ),
        isNull,
        reason: 'no heel means no forward vector — guessing one rotates a shoe',
      );

      expect(
        footPoseFromDetection(
          FootDetectionResult(
            footDetected: true,
            confidence: 0.9,
            qualityScore: 0.9,
            heelPoint: const FootPoint(x: 0.1, y: 0.9, likelihood: 0.9),
          ),
        ),
        isNull,
      );
    });

    test('detector width points are used as emitted, in order', () {
      final frame = footPoseFromDetection(
        detection(
          width: const <FootPoint>[
            FootPoint(x: 0.20, y: 0.55, likelihood: 0.8),
            FootPoint(x: 0.45, y: 0.50, likelihood: 0.8),
          ],
        ),
      );

      expect(frame!.widthUv, const <Offset>[
        Offset(0.20, 0.55),
        Offset(0.45, 0.50),
      ]);
    });

    test('a missing width pair falls back to the perpendicular estimate', () {
      final frame = footPoseFromDetection(detection())!;

      expect(frame.widthUv, hasLength(2));

      final axis = frame.toeUv - frame.heelUv;
      final width = frame.widthUv[1] - frame.widthUv[0];
      final mid = Offset(
        (frame.heelUv.dx + frame.toeUv.dx) / 2,
        (frame.heelUv.dy + frame.toeUv.dy) / 2,
      );
      final widthMid = Offset(
        (frame.widthUv[0].dx + frame.widthUv[1].dx) / 2,
        (frame.widthUv[0].dy + frame.widthUv[1].dy) / 2,
      );

      expect(widthMid.dx, closeTo(mid.dx, 1e-9));
      expect(widthMid.dy, closeTo(mid.dy, 1e-9));
      expect(width.distance, closeTo(axis.distance * 0.38, 1e-9));
      // Perpendicular: the dot product of the two vectors is zero.
      expect(axis.dx * width.dx + axis.dy * width.dy, closeTo(0, 1e-9));
    });
  });

  group('proportionalWidthPoints', () {
    test('a horizontal axis produces a vertical width pair', () {
      final points = proportionalWidthPoints(
        const Offset(0.2, 0.5),
        const Offset(0.6, 0.5),
      );

      expect(points, hasLength(2));
      expect(points[0].dx, closeTo(0.4, 1e-9));
      expect(points[1].dx, closeTo(0.4, 1e-9));
      // Order-agnostic: the pair is symmetric about the axis, so which point
      // comes first is convention, not shape.
      final ys = <double>[points[0].dy, points[1].dy]..sort();
      expect(ys.first, lessThan(0.5));
      expect(ys.last, greaterThan(0.5));
    });

    test('a vertical axis produces a horizontal width pair', () {
      final points = proportionalWidthPoints(
        const Offset(0.5, 0.2),
        const Offset(0.5, 0.6),
      );

      expect(points, hasLength(2));
      expect(points[0].dy, closeTo(0.4, 1e-9));
      expect(points[1].dy, closeTo(0.4, 1e-9));
      final xs = <double>[points[0].dx, points[1].dx]..sort();
      expect(xs.first, lessThan(0.5));
      expect(xs.last, greaterThan(0.5));
    });

    test('a degenerate axis produces no width points at all', () {
      expect(
        proportionalWidthPoints(const Offset(0.5, 0.5), const Offset(0.5, 0.5)),
        isEmpty,
      );
    });
  });
}
