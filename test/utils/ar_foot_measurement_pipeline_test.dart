/// Unit tests for the AR foot measurement pipeline.
///
/// Tests the pure math functions:
/// - Outlier filtering (IQR method)
/// - Median calculation
/// - Statistical combination of measurement samples
/// - Confidence scoring
/// - Tracking assessment
/// - Scan progress computation
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/ar_foot_measurement_pipeline.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // OUTLIER FILTERING (IQR)
  // ═══════════════════════════════════════════════════════════════

  group('filterOutliersIqr', () {
    test('returns all values when fewer than 4', () {
      expect(filterOutliersIqr([1, 2, 3]), equals([1, 2, 3]));
      expect(filterOutliersIqr([5]), equals([5]));
      expect(filterOutliersIqr([]), isEmpty);
    });

    test('filters extreme outliers', () {
      // Normal range: 260-270mm. One outlier at 300mm.
      final values = [262.0, 264.0, 265.0, 266.0, 268.0, 300.0];
      final filtered = filterOutliersIqr(values);
      expect(filtered, isNot(contains(300.0)));
      expect(filtered.length, lessThan(values.length));
    });

    test('preserves all values when tightly clustered', () {
      final values = [265.0, 265.5, 266.0, 266.5, 267.0];
      final filtered = filterOutliersIqr(values);
      expect(filtered.length, equals(values.length));
    });

    test('handles identical values', () {
      final values = [265.0, 265.0, 265.0, 265.0];
      final filtered = filterOutliersIqr(values);
      expect(filtered.length, equals(4));
    });

    test('filters with lenient k value', () {
      final values = [260.0, 262.0, 265.0, 268.0, 270.0, 310.0];
      final strict = filterOutliersIqr(values, k: 1.5);
      final lenient = filterOutliersIqr(values, k: 3.0);
      // Lenient should keep more values
      expect(lenient.length, greaterThanOrEqualTo(strict.length));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SAMPLE QUALITY FILTERING
  // ═══════════════════════════════════════════════════════════════

  group('combineSamples', () {
    test('returns null for empty input', () {
      expect(combineSamples([]), isNull);
    });

    test('returns null when too few quality samples', () {
      final samples = List.generate(3, (i) => MeasurementSample(
        lengthMm: 265 + i * 0.5,
        widthMm: 100 + i * 0.3,
        trackingQuality: 0.9,
        segmentationConfidence: 0.8,
        timestamp: DateTime.now(),
      ));
      expect(combineSamples(samples), isNull);
    });

    test('filters out low-tracking-quality samples', () {
      final samples = List.generate(10, (i) => MeasurementSample(
        lengthMm: 265 + i * 0.3,
        widthMm: 100 + i * 0.1,
        trackingQuality: i < 3 ? 0.3 : 0.9, // First 3 are low quality
        segmentationConfidence: 0.8,
        timestamp: DateTime.now(),
      ));
      final result = combineSamples(samples);
      expect(result, isNotNull);
      expect(result!.filteredSampleCount, equals(7)); // Only 7 high-quality
    });

    test('filters out low-segmentation-confidence samples', () {
      final samples = List.generate(10, (i) => MeasurementSample(
        lengthMm: 265 + i * 0.3,
        widthMm: 100 + i * 0.1,
        trackingQuality: 0.9,
        segmentationConfidence: i < 4 ? 0.2 : 0.8, // First 4 are low confidence
        timestamp: DateTime.now(),
      ));
      final result = combineSamples(samples);
      expect(result, isNotNull);
      expect(result!.filteredSampleCount, equals(6));
    });

    test('produces reasonable median measurement', () {
      final samples = List.generate(20, (i) => MeasurementSample(
        lengthMm: 265.0 + (i % 5) * 0.5, // Tight cluster around 265-267mm
        widthMm: 100.0 + (i % 5) * 0.2,
        trackingQuality: 0.9,
        segmentationConfidence: 0.85,
        timestamp: DateTime.now(),
      ));
      final result = combineSamples(samples);
      expect(result, isNotNull);
      // Median should be near the center of our range
      expect(result!.lengthMm, greaterThanOrEqualTo(264));
      expect(result.lengthMm, lessThanOrEqualTo(268));
      expect(result.widthMm, greaterThanOrEqualTo(99));
      expect(result.widthMm, lessThanOrEqualTo(102));
    });

    test('result has correct confidence level', () {
      // Tight cluster = high confidence
      final tightSamples = List.generate(20, (i) => MeasurementSample(
        lengthMm: 265.0 + i * 0.1,
        widthMm: 100.0 + i * 0.05,
        trackingQuality: 0.95,
        segmentationConfidence: 0.9,
        timestamp: DateTime.now(),
      ));
      final tightResult = combineSamples(tightSamples);
      expect(tightResult, isNotNull);
      expect(tightResult!.confidence, anyOf(equals('high'), equals('medium')));

      // Spread cluster = lower confidence
      final spreadSamples = List.generate(20, (i) => MeasurementSample(
        lengthMm: 255.0 + i * 2.0, // Wide spread: 255-293mm
        widthMm: 90.0 + i * 1.0,
        trackingQuality: 0.8,
        segmentationConfidence: 0.7,
        timestamp: DateTime.now(),
      ));
      final spreadResult = combineSamples(spreadSamples);
      if (spreadResult != null) {
        // Wide spread should have lower confidence
        expect(
          spreadResult.confidenceScore,
          lessThan(tightResult.confidenceScore + 0.1),
        );
      }
    });

    test('sample counts are tracked correctly', () {
      final samples = List.generate(15, (i) => MeasurementSample(
        lengthMm: 265.0,
        widthMm: 100.0,
        trackingQuality: i < 5 ? 0.4 : 0.9, // 5 low quality
        segmentationConfidence: 0.8,
        timestamp: DateTime.now(),
      ));
      final result = combineSamples(samples);
      expect(result, isNotNull);
      expect(result!.rawSampleCount, equals(15));
      expect(result.filteredSampleCount, equals(10)); // 15 - 5 low quality
      expect(result.finalSampleCount, lessThanOrEqualTo(10));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GUIDED TWO-ANGLE COMBINATION (§2.4 of the guided-capture brief)
  // ═══════════════════════════════════════════════════════════════

  group('combineGuidedSamples', () {
    test('returns null for empty input', () {
      expect(combineGuidedSamples([]), isNull);
    });

    test('returns null when too few quality samples', () {
      final samples = List.generate(3, (i) => MeasurementSample(
        lengthMm: 265 + i * 0.5,
        widthMm: 100 + i * 0.3,
        trackingQuality: 0.9,
        segmentationConfidence: 0.8,
        timestamp: DateTime.now(),
        captureAngle: 'front',
      ));
      expect(combineGuidedSamples(samples), isNull);
    });

    test('uses side samples for length and front samples for width', () {
      final front = List.generate(10, (i) => MeasurementSample(
        lengthMm: 265.0 + i * 0.2,
        widthMm: 100.0 + i * 0.1,
        trackingQuality: 0.95,
        segmentationConfidence: 0.9,
        timestamp: DateTime.now(),
        captureAngle: 'front',
      ));
      final side = List.generate(10, (i) => MeasurementSample(
        lengthMm: 270.0 + i * 0.2, // Different cluster than front
        widthMm: 95.0 + i * 0.1,
        trackingQuality: 0.95,
        segmentationConfidence: 0.9,
        timestamp: DateTime.now(),
        captureAngle: 'side',
      ));
      final result = combineGuidedSamples([...front, ...side]);
      expect(result, isNotNull);
      // Length should follow the SIDE cluster (270-ish), width the FRONT
      // cluster (100-ish).
      expect(result!.lengthMm, greaterThanOrEqualTo(269));
      expect(result.lengthMm, lessThanOrEqualTo(272));
      expect(result.widthMm, greaterThanOrEqualTo(99));
      expect(result.widthMm, lessThanOrEqualTo(102));
    });

    test('falls back to all samples when an angle has too few', () {
      final front = List.generate(6, (i) => MeasurementSample(
        lengthMm: 265.0 + i * 0.2,
        widthMm: 100.0 + i * 0.1,
        trackingQuality: 0.95,
        segmentationConfidence: 0.9,
        timestamp: DateTime.now(),
        captureAngle: 'front',
      ));
      // Only 2 side samples (below minValidSamples) → length falls back.
      final side = List.generate(2, (i) => MeasurementSample(
        lengthMm: 270.0 + i,
        widthMm: 95.0 + i,
        trackingQuality: 0.95,
        segmentationConfidence: 0.9,
        timestamp: DateTime.now(),
        captureAngle: 'side',
      ));
      final result = combineGuidedSamples([...front, ...side]);
      expect(result, isNotNull);
      // Length falls back to the front cluster (~265).
      expect(result!.lengthMm, greaterThanOrEqualTo(264));
      expect(result.lengthMm, lessThanOrEqualTo(267));
    });

    test('legacy captureAngle=both counts for either dimension', () {
      final samples = List.generate(12, (i) => MeasurementSample(
        lengthMm: 265.0 + i * 0.1,
        widthMm: 100.0 + i * 0.05,
        trackingQuality: 0.95,
        segmentationConfidence: 0.9,
        timestamp: DateTime.now(),
      ));
      final result = combineGuidedSamples(samples);
      expect(result, isNotNull);
      expect(result!.lengthMm, greaterThanOrEqualTo(264));
      expect(result.lengthMm, lessThanOrEqualTo(267));
      expect(result.widthMm, greaterThanOrEqualTo(99));
      expect(result.widthMm, lessThanOrEqualTo(101));
    });

    group('widthMeasured exclusion (E7)', () {
      // Build a front-capture set where every sample has a real measured
      // width of ~96mm and a proportional ESTIMATE width of ~101mm
      // (265mm × 0.38). If estimates leak into the statistics the median
      // lands near 101; with the E7 fix it must stay at ~96.
      List<MeasurementSample> samplesWith({
        required bool measured,
      }) =>
          List.generate(10, (i) => MeasurementSample(
                lengthMm: 265.0 + i * 0.1,
                widthMm: measured ? 96.0 + i * 0.05 : 100.8 + i * 0.05,
                trackingQuality: 0.95,
                segmentationConfidence: 0.9,
                timestamp: DateTime.now(),
                captureAngle: 'front',
                widthMeasured: measured,
              ));

      test('proportional width estimates are excluded from width median', () {
        // Mix: 6 measured + 4 estimated (estimates are the majority of raw
        // rows but must not move the median).
        final result = combineGuidedSamples([
          ...samplesWith(measured: true),
          ...samplesWith(measured: false).take(4),
        ]);
        expect(result, isNotNull);
        expect(result!.widthMm, lessThan(98.0),
            reason: 'width median must come from measured widths (~96), '
                'not proportional estimates (~101)');
        expect(result.widthMm, greaterThanOrEqualTo(95.5));
      });

      test(
          'falls back to all widths when too few measured widths exist '
          '(scan never detected width points)', () {
        final result = combineGuidedSamples([
          ...samplesWith(measured: false),
        ]);
        expect(result, isNotNull,
            reason: 'all-estimate scans still produce a low-confidence '
                'result rather than failing');
        // Fallback includes the estimates (~101).
        expect(result!.widthMm, greaterThanOrEqualTo(99));
      });

      test('defaults to widthMeasured=true so legacy call sites are unchanged', () {
        final result = combineGuidedSamples(samplesWith(measured: true)
            .map((s) => MeasurementSample(
                  lengthMm: s.lengthMm,
                  widthMm: s.widthMm,
                  trackingQuality: s.trackingQuality,
                  segmentationConfidence: s.segmentationConfidence,
                  timestamp: s.timestamp,
                  captureAngle: s.captureAngle,
                ))
            .toList());
        expect(result, isNotNull);
        expect(result!.widthMm, greaterThanOrEqualTo(95.5));
        expect(result.widthMm, lessThan(97.0));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // TRACKING ASSESSMENT
  // ═══════════════════════════════════════════════════════════════

  group('assessTracking', () {
    test('reports ready when tracking + plane detected', () {
      final assessment = assessTracking(
        trackingState: 1.0,
        planeDetected: true,
        sessionDuration: const Duration(seconds: 5),
      );
      expect(assessment.ready, isTrue);
      expect(assessment.state, equals('tracking'));
    });

    test('reports not ready when tracking paused', () {
      final assessment = assessTracking(
        trackingState: 0.0,
        planeDetected: false,
        sessionDuration: const Duration(seconds: 5),
      );
      expect(assessment.ready, isFalse);
      expect(assessment.state, equals('lost'));
    });

    test('reports searching when tracking but no plane', () {
      final assessment = assessTracking(
        trackingState: 1.0,
        planeDetected: false,
        sessionDuration: const Duration(seconds: 3),
      );
      expect(assessment.ready, isFalse);
      expect(assessment.state, equals('searching'));
    });

    test('reports limited when tracking is partial', () {
      final assessment = assessTracking(
        trackingState: 0.5,
        planeDetected: false,
        sessionDuration: const Duration(seconds: 5),
      );
      expect(assessment.ready, isFalse);
      expect(assessment.state, equals('limited'));
    });

    test('reports ready when the guide-box area is tracked (§2)', () {
      // A plane exists elsewhere but the box area is verified tracked → ready.
      final assessment = assessTracking(
        trackingState: 1.0,
        planeDetected: true,
        areaTracked: true,
        sessionDuration: const Duration(seconds: 5),
      );
      expect(assessment.ready, isTrue);
      expect(assessment.state, equals('tracking'));
    });

    test('reports searching when a plane exists but the box area is not tracked (§2)', () {
      // Legacy signal says a plane was found, but the localized check failed
      // → not ready; the user must map the floor under the guide box.
      final assessment = assessTracking(
        trackingState: 1.0,
        planeDetected: true,
        areaTracked: false,
        sessionDuration: const Duration(seconds: 5),
      );
      expect(assessment.ready, isFalse);
      expect(assessment.state, equals('searching'));
    });

    test('falls back to planeDetected when areaTracked is null', () {
      // Backward compatibility: callers that don't use localized tracking
      // behave exactly as before.
      final assessment = assessTracking(
        trackingState: 1.0,
        planeDetected: true,
        sessionDuration: const Duration(seconds: 5),
      );
      expect(assessment.ready, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SCAN PROGRESS
  // ═══════════════════════════════════════════════════════════════

  group('scanProgress', () {
    test('returns 0 at start', () {
      final progress = scanProgress(DateTime.now());
      expect(progress, closeTo(0, 0.1));
    });

    test('returns 1.0 after scan duration', () {
      final startTime = DateTime.now().subtract(
        const Duration(seconds: 5), // Longer than scanDuration (4s)
      );
      final progress = scanProgress(startTime);
      expect(progress, equals(1.0));
    });

    test('returns intermediate value mid-scan', () {
      final startTime = DateTime.now().subtract(
        const Duration(seconds: 2), // Half of scanDuration
      );
      final progress = scanProgress(startTime);
      expect(progress, greaterThan(0.3));
      expect(progress, lessThan(0.7));
    });
  });

  group('scanComplete', () {
    test('returns false when scan just started', () {
      expect(scanComplete(DateTime.now()), isFalse);
    });

    test('returns true after scan duration', () {
      final startTime = DateTime.now().subtract(
        const Duration(seconds: 5),
      );
      expect(scanComplete(startTime), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // MEASUREMENT RESULT
  // ═══════════════════════════════════════════════════════════════

  group('MeasurementResult', () {
    test('toString formats correctly', () {
      const result = MeasurementResult(
        lengthMm: 265.3,
        widthMm: 100.7,
        lengthIqrMm: 2.1,
        widthIqrMm: 1.5,
        confidence: 'high',
        confidenceScore: 0.85,
        rawSampleCount: 20,
        filteredSampleCount: 18,
        finalSampleCount: 16,
      );
      final str = result.toString();
      expect(str, contains('265.3'));
      expect(str, contains('100.7'));
      expect(str, contains('high'));
      expect(str, contains('0.85'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // EDGE CASES
  // ═══════════════════════════════════════════════════════════════

  group('edge cases', () {
    test('combineSamples with all low-quality samples returns null', () {
      final samples = List.generate(20, (i) => MeasurementSample(
        lengthMm: 265.0,
        widthMm: 100.0,
        trackingQuality: 0.1, // All below threshold
        segmentationConfidence: 0.1,
        timestamp: DateTime.now(),
      ));
      expect(combineSamples(samples), isNull);
    });

    test('combineSamples with extreme outliers still produces result', () {
      final samples = List.generate(20, (i) {
        // Most samples are consistent, one has a crazy outlier
        final length = i == 15 ? 400.0 : 265.0 + i * 0.2;
        return MeasurementSample(
          lengthMm: length,
          widthMm: 100.0,
          trackingQuality: 0.9,
          segmentationConfidence: 0.85,
          timestamp: DateTime.now(),
        );
      });
      final result = combineSamples(samples);
      expect(result, isNotNull);
      // The outlier should be filtered, median should be near 265
      expect(result!.lengthMm, lessThan(280));
    });

    test('MeasurementSample toString works', () {
      final sample = MeasurementSample(
        lengthMm: 265.5,
        widthMm: 100.3,
        trackingQuality: 0.9,
        segmentationConfidence: 0.85,
        timestamp: DateTime(2024),
      );
      expect(sample.toString(), contains('265.5'));
      expect(sample.toString(), contains('100.3'));
    });
  });
}
