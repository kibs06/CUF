import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/card_capture_coach.dart';
import 'package:app/utils/foot_measurement_utils.dart';

/// Good card-proportioned quad: 160x100px (aspect 1.6 ≈ card 1.586).
List<Offset> goodCardQuad() => const [
      Offset(100, 100),
      Offset(260, 100),
      Offset(260, 200),
      Offset(100, 200),
    ];

void main() {
  group('diagnoseReferenceQuad', () {
    test('empty for a good card quad', () {
      expect(
        diagnoseReferenceQuad(goodCardQuad(), PaperDimensions.card),
        isEmpty,
      );
    });

    test('badCornerCount when empty', () {
      expect(
        diagnoseReferenceQuad(const [], PaperDimensions.card),
        contains(ReferenceQuadIssue.badCornerCount),
      );
    });

    test('tooSmall for a far-away card', () {
      final far = [
        const Offset(100, 100),
        const Offset(140, 100),
        const Offset(140, 125),
        const Offset(100, 125),
      ];
      expect(
        diagnoseReferenceQuad(far, PaperDimensions.card),
        contains(ReferenceQuadIssue.tooSmall),
      );
    });

    test('keystoned for a lifted card', () {
      final tilted = [
        const Offset(140, 100),
        const Offset(220, 100),
        const Offset(260, 200),
        const Offset(60, 200),
      ];
      final issues = diagnoseReferenceQuad(tilted, PaperDimensions.card);
      expect(issues, isNotEmpty);
      expect(
        issues.intersection({
          ReferenceQuadIssue.keystoned,
          ReferenceQuadIssue.sideMismatch,
          ReferenceQuadIssue.aspectMismatch,
        }),
        isNotEmpty,
      );
    });

    test('aspectMismatch for a square passed as card', () {
      final square = [
        const Offset(100, 100),
        const Offset(250, 100),
        const Offset(250, 250),
        const Offset(100, 250),
      ];
      expect(
        diagnoseReferenceQuad(square, PaperDimensions.card),
        contains(ReferenceQuadIssue.aspectMismatch),
      );
    });

    test('isPlausible stays consistent with diagnose', () {
      expect(isPlausibleReferenceQuad(goodCardQuad(), PaperDimensions.card), isTrue);
      expect(
        isPlausibleReferenceQuad(const [], PaperDimensions.card),
        isFalse,
      );
    });
  });

  group('coachForDetection', () {
    test('searching with no corners, names foot + card', () {
      final s = coachForDetection(
        corners: const [],
        paper: PaperDimensions.card,
        footLabel: 'left',
      );
      expect(s.status, CardCoachStatus.searching);
      expect(s.isMeasurable, isFalse);
      expect(s.message, contains('left'));
      expect(s.message, contains('card'));
    });

    test('tooSmall asks to move closer', () {
      final s = coachForDetection(
        corners: const [
          Offset(100, 100),
          Offset(140, 100),
          Offset(140, 125),
          Offset(100, 125),
        ],
        paper: PaperDimensions.card,
        footLabel: 'right',
      );
      expect(s.status, CardCoachStatus.tooSmall);
      expect(s.isMeasurable, isFalse);
      expect(s.message, contains('Move closer'));
    });

    test('tilted card re-coaches to lay flat', () {
      final s = coachForDetection(
        corners: const [
          Offset(140, 100),
          Offset(220, 100),
          Offset(260, 200),
          Offset(60, 200),
        ],
        paper: PaperDimensions.card,
        footLabel: 'left',
      );
      expect(s.status, CardCoachStatus.tilted);
      expect(s.isMeasurable, isFalse);
      expect(s.message, contains('flat'));
    });

    test('good quad starts holding, ready at full dwell', () {
      final holding = coachForDetection(
        corners: goodCardQuad(),
        paper: PaperDimensions.card,
        footLabel: 'left',
      );
      expect(holding.status, CardCoachStatus.holding);
      expect(holding.isMeasurable, isTrue);

      final ready = coachForDetection(
        corners: goodCardQuad(),
        paper: PaperDimensions.card,
        footLabel: 'left',
        holdProgress: 1.0,
      );
      expect(ready.status, CardCoachStatus.ready);
      expect(ready.isMeasurable, isTrue);
    });

    test('paper copy names paper, not card', () {
      final s = coachForDetection(
        corners: const [],
        paper: PaperDimensions.a4,
        footLabel: 'right',
      );
      expect(s.message, contains('A4'));
      expect(s.message, isNot(contains('card')));
    });
  });

  group('summarizeScaleSamples', () {
    test('null for too few samples', () {
      expect(summarizeScaleSamples([]), isNull);
      expect(summarizeScaleSamples([0.5, 0.51, 0.49]), isNull);
    });

    test('median of a steady burst with ~zero IQR', () {
      final s = summarizeScaleSamples(
        [0.535, 0.537, 0.536, 0.538, 0.535, 0.537],
      )!;
      expect(s.medianScale, closeTo(0.536, 0.002));
      expect(s.iqrScale, lessThan(0.005));
      expect(s.rawCount, 6);
      expect(s.keptCount, 6);
    });

    test('rejects non-finite and non-positive samples', () {
      expect(
        summarizeScaleSamples(
          [0.53, double.nan, 0.54, -1.0, double.infinity],
        ),
        isNull, // only 2 valid < min 4
      );
    });

    test('IQR filters a shaky frame', () {
      final s = summarizeScaleSamples(
        [0.535, 0.536, 0.537, 0.536, 0.535, 0.62],
      );
      // 6 samples: IQR filter keeps 5–6; median must stay near 0.536,
      // never pulled to the 0.62 shake.
      expect(s, isNotNull);
      expect(s!.medianScale, closeTo(0.536, 0.005));
    });
  });

  group('burst constants', () {
    test('burst is 5–8 frames with ~1s dwell', () {
      expect(cardBurstFrameCount, greaterThanOrEqualTo(5));
      expect(cardBurstFrameCount, lessThanOrEqualTo(8));
      expect(cardHoldStillMs, 1000);
      expect(cardBurstMinSamples, lessThanOrEqualTo(cardBurstFrameCount));
    });
  });
}
