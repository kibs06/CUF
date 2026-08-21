import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/foot_measurement.dart';
import 'package:app/utils/foot_measurement_utils.dart';

void main() {
  group('generateSizeRecommendationReason', () {
    test('clear fit — no boundary proximity', () {
      // 265mm with EU 43: well within the EU 43 range, not near boundary
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 265.0,
        euSize: '43',
        measurementSource: 'ar_guided_tap',
      );
      expect(reason, contains('EU 43'));
      expect(reason, isNot(contains('snugger fit')));
    });

    test('near previous size boundary — mentions snugger option', () {
      // Use a value that's within kBoundaryProximityMm (2mm) of prev boundary
      // The prev upper boundary for EU 43 = (43-1) * 20/3 - 8 = 271.33
      // So 273mm is near that boundary
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 273.0,
        euSize: '43',
        measurementSource: 'ar_guided_tap',
      );
      expect(reason, contains('EU 42'));
      expect(reason, contains('snugger fit'));
    });

    test('auto scan high confidence — uses confidence phrasing', () {
      // 273mm is near the EU 43/44 boundary, so the boundary branch fires
      // first. Use a value that's clearly NOT near any boundary.
      // EU 45 lower bound = 45 * 20/3 - 8 = 292. 290mm is well within EU 45.
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 290.0,
        euSize: '45',
        measurementSource: 'ar_auto_scan',
        confidenceLevel: 'high',
      );
      expect(reason, contains('high measurement confidence'));
      expect(reason, contains('EU 45'));
    });

    test('auto scan low confidence — no confidence phrasing', () {
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 280.0,
        euSize: '44',
        measurementSource: 'ar_auto_scan',
        confidenceLevel: 'low',
      );
      expect(reason, isNot(contains('high measurement confidence')));
    });

    test('paper scan — standard phrasing', () {
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 260.0,
        euSize: '41',
        measurementSource: 'paper',
      );
      expect(reason, contains('EU 41'));
      expect(reason, contains('26.0 cm'));
    });

    test('invalid EU size — fallback message', () {
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 260.0,
        euSize: '',
        measurementSource: 'ar_guided_tap',
      );
      expect(reason, contains('recommend'));
    });

    test('EU 35 boundary check — no negative size reference', () {
      // EU 35 is the smallest adult size, no EU 34 to reference
      final reason = generateSizeRecommendationReason(
        compensatedLengthMm: 226.0,
        euSize: '35',
        measurementSource: 'ar_guided_tap',
      );
      expect(reason, contains('EU 35'));
      // Should NOT mention EU 34 since it's below the chart
      expect(reason, isNot(contains('EU 34')));
    });
  });

  group('widthMmToFitCategory', () {
    test('narrow foot — ratio < 0.36', () {
      // 90mm width / 270mm length = 0.333
      expect(widthMmToFitCategory(90, 270), 'narrow');
    });

    test('standard foot — ratio between 0.36 and 0.42', () {
      // 105mm / 270mm = 0.389
      expect(widthMmToFitCategory(105, 270), 'standard');
    });

    test('wide foot — ratio > 0.42', () {
      // 120mm / 270mm = 0.444
      expect(widthMmToFitCategory(120, 270), 'wide');
    });

    test('edge case — zero length returns standard', () {
      expect(widthMmToFitCategory(100, 0), 'standard');
    });
  });

  group('applySockCompensation', () {
    test('bare feet — no change', () {
      expect(applySockCompensation(270, isLength: true, isSocks: false), 270);
      expect(applySockCompensation(100, isLength: false, isSocks: false), 100);
    });

    test('socks — length reduced by 3mm', () {
      expect(applySockCompensation(270, isLength: true, isSocks: true), 267);
    });

    test('socks — width reduced by 2mm', () {
      expect(applySockCompensation(100, isLength: false, isSocks: true), 98);
    });
  });

  group('checkPlausibility', () {
    test('normal length — ok', () {
      expect(checkPlausibility(27, isLength: true), PlausibilityResult.ok);
    });

    test('edge-case length — soft warn', () {
      expect(checkPlausibility(14, isLength: true), PlausibilityResult.softWarn);
      expect(checkPlausibility(31, isLength: true), PlausibilityResult.softWarn);
    });

    test('implausible length — hard reject', () {
      expect(checkPlausibility(10, isLength: true), PlausibilityResult.hardReject);
      expect(checkPlausibility(36, isLength: true), PlausibilityResult.hardReject);
    });

    test('normal width — ok', () {
      expect(checkPlausibility(10, isLength: false), PlausibilityResult.ok);
    });

    test('edge-case width — soft warn', () {
      expect(checkPlausibility(5.5, isLength: false), PlausibilityResult.softWarn);
      expect(checkPlausibility(14, isLength: false), PlausibilityResult.softWarn);
    });

    test('implausible width — hard reject', () {
      expect(checkPlausibility(3, isLength: false), PlausibilityResult.hardReject);
      expect(checkPlausibility(16, isLength: false), PlausibilityResult.hardReject);
    });
  });

  group('FootMeasurement sizing logic', () {
    test('determineSizingFootSide — left longer', () {
      final m = FootMeasurement(
        userId: 'test',
        footLengthLeftMm: 280,
        footLengthRightMm: 270,
        footWidthLeftMm: 100,
        footWidthRightMm: 105,
        paperSizeUsed: 'ar',
        scanDate: DateTime.now(),
      );
      expect(m.determineSizingFootSide, 'left');
    });

    test('determineSizingFootSide — right longer', () {
      final m = FootMeasurement(
        userId: 'test',
        footLengthLeftMm: 270,
        footLengthRightMm: 280,
        paperSizeUsed: 'ar',
        scanDate: DateTime.now(),
      );
      expect(m.determineSizingFootSide, 'right');
    });

    test('sizingFootWidth — uses sizing foot side', () {
      final m = FootMeasurement(
        userId: 'test',
        footLengthLeftMm: 280,
        footLengthRightMm: 270,
        footWidthLeftMm: 100,
        footWidthRightMm: 105,
        sizingFootSide: 'left',
        paperSizeUsed: 'ar',
        scanDate: DateTime.now(),
      );
      // Left is the sizing foot → should use left width (100), not right (105)
      expect(m.sizingFootWidth, 100);
    });

    test('euToUs — men offset', () {
      expect(FootMeasurement.euToUs('42', category: 'men'), '9');
    });

    test('euToUs — women offset', () {
      // EU 42 women → 42 - 31.5 = 10.5 → rounds to 10 or 11
      final result = FootMeasurement.euToUs('42', category: 'women');
      expect(int.parse(result), greaterThanOrEqualTo(10));
      expect(int.parse(result), lessThanOrEqualTo(11));
    });

    test('euToUs — kids offset same as men', () {
      expect(FootMeasurement.euToUs('36', category: 'kids'), '3');
      expect(FootMeasurement.euToUs('36', category: 'men'), '3');
    });
  });
}
