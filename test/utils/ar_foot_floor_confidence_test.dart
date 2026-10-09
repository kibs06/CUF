import 'package:app/utils/ar_foot_measurement_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

MeasurementSample sample({
  required double length,
  required double width,
  double hitShare = 1.0,
}) =>
    MeasurementSample(
      lengthMm: length,
      widthMm: width,
      trackingQuality: 1.0,
      segmentationConfidence: 0.9,
      timestamp: DateTime(2026, 10, 9),
      captureAngle: 'both',
      pointHitShare: hitShare,
    );

/// Fifteen readings that agree closely, so spread does not decide the score.
List<MeasurementSample> steady({double hitShare = 1.0}) => [
      for (var i = 0; i < 15; i++)
        sample(
          length: 265 + (i % 3) * 0.5,
          width: 100 + (i % 3) * 0.5,
          hitShare: hitShare,
        ),
    ];

/// Fifteen readings that disagree widely.
List<MeasurementSample> scattered({double hitShare = 1.0}) => [
      for (var i = 0; i < 15; i++)
        sample(
          length: i.isEven ? 220 : 300,
          width: i.isEven ? 80 : 130,
          hitShare: hitShare,
        ),
    ];

void main() {
  group('pointHitShareFactor', () {
    test('full hits leave the score alone', () {
      expect(pointHitShareFactor(1.0), 1.0);
      expect(pointHitShareFactor(kFullPointHitShare), 1.0);
    });

    test('falls linearly between the full and the no-hit shares', () {
      expect(pointHitShareFactor(0.6), closeTo(0.5, 1e-9));
    });

    test('never drops below the minimum factor', () {
      expect(pointHitShareFactor(kNoPointHitShare), kMinPointHitFactor);
      expect(pointHitShareFactor(0.0), kMinPointHitFactor);
    });
  });

  group('combineGuidedSamples with a surface hit share', () {
    test('a partial hit share scales the score by exactly its factor', () {
      final full = combineGuidedSamples(steady())!;
      final partial = combineGuidedSamples(steady(hitShare: 0.6))!;

      expect(
        partial.confidenceScore,
        closeTo(full.confidenceScore * pointHitShareFactor(0.6), 1e-9),
      );
      expect(partial.pointHitShare, closeTo(0.6, 1e-9));
    });

    test('samples that predate the field keep their full score', () {
      final result = combineGuidedSamples(steady())!;
      expect(result.pointHitShare, 1.0);
    });
  });

  group('rescanGate', () {
    test('a steady, fully hit scan is used', () {
      final result = combineGuidedSamples(steady());
      expect(result, isNotNull);
      expect(result!.confidenceScore, greaterThanOrEqualTo(kRescanConfidence));
      expect(rescanGate(result), same(result));
    });

    test('a scattered scan the surface barely answered asks for a rescan', () {
      final result = combineGuidedSamples(scattered(hitShare: 0.3));
      expect(result, isNotNull,
          reason: 'combining still produces a result to judge');
      expect(result!.confidenceScore, lessThan(kRescanConfidence));
      expect(rescanGate(result), isNull);
    });

    test('no result stays no result', () {
      expect(rescanGate(null), isNull);
    });
  });
}
