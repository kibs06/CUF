/// Unit tests for the foot detection layer.
///
/// Tests the pure, deterministic evaluation logic in `foot_detector.dart`
/// (landmark → gating + point extraction). The ML Kit plugin itself is not
/// required here — this keeps the layer independently testable (§8 of the
/// implementation brief).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/foot_detector.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // GATING (§3.3 / §4)
  // ═══════════════════════════════════════════════════════════════

  group('evaluateFootLandmarks — gating', () {
    test('returns negative when no landmarks at all', () {
      final result = evaluateFootLandmarks(
        leftHeel: null,
        leftToe: null,
        rightHeel: null,
        rightToe: null,
      );
      expect(result.footDetected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('returns negative when only one landmark present', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.5, y: 0.8, likelihood: 0.9),
        leftToe: null,
        rightHeel: null,
        rightToe: null,
      );
      expect(result.footDetected, isFalse);
    });

    test('returns negative when landmarks below confidence threshold', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.5, y: 0.8, likelihood: 0.2),
        leftToe: const LandmarkInput(x: 0.5, y: 0.3, likelihood: 0.4),
        rightHeel: null,
        rightToe: null,
      );
      expect(result.footDetected, isFalse);
    });

    test('returns negative when only one landmark is above threshold', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.5, y: 0.8, likelihood: 0.9),
        leftToe: const LandmarkInput(x: 0.5, y: 0.3, likelihood: 0.1),
        rightHeel: null,
        rightToe: null,
      );
      expect(result.footDetected, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // POINT EXTRACTION (§5)
  // ═══════════════════════════════════════════════════════════════

  group('evaluateFootLandmarks — point extraction', () {
    test('detects left foot and extracts heel/toe points', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.30, y: 0.85, likelihood: 0.92),
        leftToe: const LandmarkInput(x: 0.31, y: 0.20, likelihood: 0.88),
        rightHeel: null,
        rightToe: null,
      );

      expect(result.footDetected, isTrue);
      expect(result.footSide, 'left');
      expect(result.heelPoint, isNotNull);
      expect(result.toePoint, isNotNull);

      final heel = result.heelPoint!;
      final toe = result.toePoint!;
      expect(heel.x, closeTo(0.30, 0.001));
      expect(heel.y, closeTo(0.85, 0.001));
      expect(toe.x, closeTo(0.31, 0.001));
      expect(toe.y, closeTo(0.20, 0.001));

      // Confidence = min of the landmark pair
      expect(result.confidence, closeTo(0.88, 0.001));
    });

    test('detects right foot and extracts heel/toe points', () {
      final result = evaluateFootLandmarks(
        leftHeel: null,
        leftToe: null,
        rightHeel: const LandmarkInput(x: 0.70, y: 0.85, likelihood: 0.95),
        rightToe: const LandmarkInput(x: 0.68, y: 0.18, likelihood: 0.93),
      );

      expect(result.footDetected, isTrue);
      expect(result.footSide, 'right');
      expect(result.confidence, closeTo(0.93, 0.001));
    });

    test('widthPoints are null for pose-based detection (no width landmarks)', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.3, y: 0.8, likelihood: 0.9),
        leftToe: const LandmarkInput(x: 0.3, y: 0.2, likelihood: 0.9),
        rightHeel: null,
        rightToe: null,
      );
      expect(result.widthPoints, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SIDE PREFERENCE
  // ═══════════════════════════════════════════════════════════════

  group('evaluateFootLandmarks — side preference', () {
    test('prefers requested left side when both feet detected', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.3, y: 0.8, likelihood: 0.7),
        leftToe: const LandmarkInput(x: 0.3, y: 0.2, likelihood: 0.7),
        rightHeel: const LandmarkInput(x: 0.7, y: 0.8, likelihood: 0.95),
        rightToe: const LandmarkInput(x: 0.7, y: 0.2, likelihood: 0.95),
        preferSide: 'left',
      );
      expect(result.footSide, 'left');
    });

    test('prefers requested right side when both feet detected', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.3, y: 0.8, likelihood: 0.95),
        leftToe: const LandmarkInput(x: 0.3, y: 0.2, likelihood: 0.95),
        rightHeel: const LandmarkInput(x: 0.7, y: 0.8, likelihood: 0.8),
        rightToe: const LandmarkInput(x: 0.7, y: 0.2, likelihood: 0.8),
        preferSide: 'right',
      );
      expect(result.footSide, 'right');
    });

    test('falls back to higher-confidence side when no preference', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.3, y: 0.8, likelihood: 0.65),
        leftToe: const LandmarkInput(x: 0.3, y: 0.2, likelihood: 0.6),
        rightHeel: const LandmarkInput(x: 0.7, y: 0.8, likelihood: 0.9),
        rightToe: const LandmarkInput(x: 0.7, y: 0.2, likelihood: 0.9),
      );
      expect(result.footSide, 'right');
    });

    test('strict gating: rejects opposite foot when preferred side absent (§4)', () {
      // Scanning left foot, but this frame only shows the right foot →
      // the frame must contribute NOTHING, not a right-foot sample.
      final result = evaluateFootLandmarks(
        leftHeel: null,
        leftToe: null,
        rightHeel: const LandmarkInput(x: 0.7, y: 0.8, likelihood: 0.9),
        rightToe: const LandmarkInput(x: 0.7, y: 0.2, likelihood: 0.9),
        preferSide: 'left',
      );
      expect(result.footDetected, isFalse);
      // The rejected side is preserved for device-testing diagnostics.
      expect(result.rejectedFootSide, 'right');
    });

    test('strict gating: accepts preferred side even when lower confidence', () {
      final result = evaluateFootLandmarks(
        leftHeel: const LandmarkInput(x: 0.3, y: 0.8, likelihood: 0.7),
        leftToe: const LandmarkInput(x: 0.3, y: 0.2, likelihood: 0.7),
        rightHeel: const LandmarkInput(x: 0.7, y: 0.8, likelihood: 0.99),
        rightToe: const LandmarkInput(x: 0.7, y: 0.2, likelihood: 0.99),
        preferSide: 'left',
      );
      expect(result.footDetected, isTrue);
      expect(result.footSide, 'left');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // TEMPORAL CONSISTENCY (§1.2 of the fix brief)
  // ═══════════════════════════════════════════════════════════════

  group('TemporalFootGate — consecutive confirmation', () {
    test('starts unconfirmed', () {
      final gate = TemporalFootGate();
      expect(gate.confirmed, isFalse);
    });

    test('requires confirmAfter consecutive positives to confirm', () {
      final gate = TemporalFootGate(confirmAfter: 3, clearAfter: 3);
      expect(gate.update(false), isFalse);
      expect(gate.update(true), isFalse);
      expect(gate.update(true), isFalse);
      // Third consecutive positive flips to confirmed.
      expect(gate.update(true), isTrue);
      expect(gate.confirmed, isTrue);
    });

    test('a single negative resets the positive streak', () {
      final gate = TemporalFootGate(confirmAfter: 3, clearAfter: 3);
      gate.update(true);
      gate.update(true);
      gate.update(false); // Breaks the streak
      expect(gate.update(true), isFalse); // Streak restarted
      expect(gate.update(true), isFalse);
      expect(gate.update(true), isTrue); // Only now confirmed
    });

    test('requires clearAfter consecutive negatives to unconfirm', () {
      final gate = TemporalFootGate(confirmAfter: 2, clearAfter: 3);
      gate.update(true);
      expect(gate.update(true), isTrue); // Confirmed
      expect(gate.update(false), isTrue); // neg streak 1, still confirmed
      expect(gate.update(false), isTrue); // neg streak 2, still confirmed
      expect(gate.update(false), isFalse); // neg streak 3 → cleared
      expect(gate.confirmed, isFalse);
    });

    test('reset clears state', () {
      final gate = TemporalFootGate(confirmAfter: 2, clearAfter: 2);
      gate.update(true);
      gate.update(true);
      expect(gate.confirmed, isTrue);
      gate.reset();
      expect(gate.confirmed, isFalse);
      expect(gate.positiveStreak, 0);
      expect(gate.update(true), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // DATA CLASSES
  // ═══════════════════════════════════════════════════════════════

  group('data classes', () {
    test('FootPoint asOffset converts normalized coords', () {
      const point = FootPoint(x: 0.5, y: 0.25, likelihood: 0.9);
      final offset = point.asOffset;
      expect(offset.dx, 0.5);
      expect(offset.dy, 0.25);
    });

    test('FootDetectionResult.negative has sane defaults', () {
      const result = FootDetectionResult.negative();
      expect(result.footDetected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.heelPoint, isNull);
      expect(result.toePoint, isNull);
      expect(result.widthPoints, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SMART-ASSIST PROPOSAL (§6 of MANUAL_MEASUREMENT_PIVOT_PROMPT)
  // ═══════════════════════════════════════════════════════════════

  group('proposePointPair — smart-assist proposal', () {
    const heel = FootPoint(x: 0.2, y: 0.8, likelihood: 0.9);
    const toe = FootPoint(x: 0.6, y: 0.8, likelihood: 0.9);
    const widthA = FootPoint(x: 0.3, y: 0.4, likelihood: 0.9);
    const widthB = FootPoint(x: 0.7, y: 0.4, likelihood: 0.9);

    FootDetectionResult detected({List<FootPoint>? width, FootPoint? heelPt, FootPoint? toePt}) {
      return FootDetectionResult(
        footDetected: true,
        confidence: 0.9,
        footSide: 'left',
        heelPoint: heelPt,
        toePoint: toePt,
        widthPoints: width,
      );
    }

    test('returns null when detection is negative', () {
      const negative = FootDetectionResult.negative();
      expect(proposePointPair(negative, isFront: true), isNull);
      expect(proposePointPair(negative, isFront: false), isNull);
    });

    test('front step proposes the widest-point pair', () {
      final pair = proposePointPair(
        detected(width: [widthA, widthB]),
        isFront: true,
      );
      expect(pair, isNotNull);
      expect(pair!.a.x, widthA.x);
      expect(pair.a.y, widthA.y);
      expect(pair.b.x, widthB.x);
      expect(pair.b.y, widthB.y);
    });

    test('front step returns null when width points are missing', () {
      final pair = proposePointPair(
        detected(width: null, heelPt: heel, toePt: toe),
        isFront: true,
      );
      expect(pair, isNull);
    });

    test('front step returns null when fewer than two width points', () {
      final pair = proposePointPair(
        detected(width: [widthA]),
        isFront: true,
      );
      expect(pair, isNull);
    });

    test('side step proposes heel + toe tip', () {
      final pair = proposePointPair(
        detected(width: [widthA, widthB], heelPt: heel, toePt: toe),
        isFront: false,
      );
      expect(pair, isNotNull);
      expect(pair!.a.x, heel.x);
      expect(pair.a.y, heel.y);
      expect(pair.b.x, toe.x);
      expect(pair.b.y, toe.y);
    });

    test('side step returns null when heel or toe is missing', () {
      final missingHeel = proposePointPair(
        detected(width: [widthA, widthB], heelPt: null, toePt: toe),
        isFront: false,
      );
      expect(missingHeel, isNull);

      final missingToe = proposePointPair(
        detected(width: [widthA, widthB], heelPt: heel, toePt: null),
        isFront: false,
      );
      expect(missingToe, isNull);
    });
  });
}
