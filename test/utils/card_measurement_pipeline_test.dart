import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/card_capture_coach.dart';
import 'package:app/utils/card_measurement_pipeline.dart';
import 'package:app/utils/foot_measurement_utils.dart';

List<Offset> cardQuad() => const [
      Offset(100, 100),
      Offset(260, 100),
      Offset(260, 200),
      Offset(100, 200),
    ];

/// Realistic 265×103mm foot in A4 pixels (500px→210mm, 700px→297mm).
/// The pipeline enforces hard-reject plausibility (12–34cm), so ok-path
/// tests must use real-foot-scale geometry — toy quads under 12cm
/// correctly refuse with implausibleMeasurement (covered below).
List<Offset> a4Quad() => const [
      Offset(50, 50),
      Offset(550, 50),
      Offset(550, 750),
      Offset(50, 750),
    ];

List<Offset> realisticFoot() {
  final pts = <Offset>[];
  for (var i = 0; i < 24; i++) {
    final a = 2 * pi * i / 24;
    pts.add(Offset(300 + 315 * cos(a), 400 + 121.5 * sin(a)));
  }
  return pts;
}

CardMeasurementOutcome run({
  List<Offset>? corners,
  List<Offset>? outline,
  bool isSocks = false,
  String confidence = 'high',
}) =>
    measureCardCapture(
      refCorners: corners ?? a4Quad(),
      footOutline: outline ?? realisticFoot(),
      paper: PaperDimensions.a4,
      isSocks: isSocks,
      measurementSource: 'paper',
      confidenceLevel: confidence,
      shoeCategory: 'men',
      scaleMedian: 0.42,
      scaleIqrMmPerPx: 0.001,
      burstFrames: 6,
    );

void main() {
  group('measureCardCapture — outcome contract', () {
    test('ok path yields mm + compensated + recommendation + provenance', () {
      final o = run();
      expect(o.isOk, isTrue);
      final s = o.success!;
      // 630px → 630 * 210/500 = 264.6mm; +8 allowance = 272.6 → EU 42.
      expect(s.lengthMm, closeTo(264.6, 1.0));
      expect(s.compensatedLengthMm, closeTo(264.6, 1.0));
      expect(s.recommendation.eu, '42');
      expect(s.recommendation.isSingleSize, isTrue);
      expect(s.burstFrames, 6);
      expect(s.scaleMedian, closeTo(0.42, 1e-9));
    });

    test('socks discount flows into the recommendation', () {
      final bare = run(isSocks: false).success!;
      final socks = run(isSocks: true).success!;
      expect(
        socks.compensatedLengthMm,
        closeTo(bare.compensatedLengthMm - 3.0, 1e-9),
      );
    });

    test('toy-scale foot correctly refuses as implausible (not a bug)', () {
      // 96mm outline through a valid card quad: geometry fine, but 9.6cm
      // is no foot — the pipeline must refuse, never size it.
      final toy = <Offset>[];
      for (var i = 0; i < 24; i++) {
        final a = 2 * pi * i / 24;
        toy.add(Offset(180 + 90 * cos(a), 150 + 25 * sin(a)));
      }
      final o = measureCardCapture(
        refCorners: cardQuad(),
        footOutline: toy,
        paper: PaperDimensions.card,
        isSocks: false,
        measurementSource: 'paper',
        confidenceLevel: 'high',
        shoeCategory: 'men',
        scaleMedian: 0.536,
        scaleIqrMmPerPx: 0.002,
        burstFrames: 6,
      );
      expect(o.isOk, isFalse);
      expect(o.failure, CardMeasurementFailure.implausibleMeasurement);
    });

    test('tilted card → referenceInvalid with explainable issues', () {
      final o = run(corners: const [
        Offset(140, 100),
        Offset(220, 100),
        Offset(260, 200),
        Offset(60, 200),
      ]);
      expect(o.isOk, isFalse);
      expect(o.failure, CardMeasurementFailure.referenceInvalid);
      expect(o.issues, isNotEmpty);
    });

    test('missing corners → referenceInvalid', () {
      final o = run(corners: const []);
      expect(o.failure, CardMeasurementFailure.referenceInvalid);
      expect(o.issues, contains(ReferenceQuadIssue.badCornerCount));
    });

    test('tiny outline → outlineInvalid', () {
      final o = run(
        outline: List.generate(5, (i) => Offset(100.0 + i, 100)),
      );
      expect(o.isOk, isFalse);
      expect(o.failure, CardMeasurementFailure.outlineInvalid);
    });

    test('absurd outline → implausibleMeasurement, never a size', () {
      // ~960mm foot: passes geometry, fails plausibility.
      final huge = <Offset>[];
      for (var i = 0; i < 24; i++) {
        final a = 2 * pi * i / 24;
        huge.add(Offset(500 + 900 * cos(a), 500 + 250 * sin(a)));
      }
      final o = run(outline: huge);
      expect(o.isOk, isFalse);
      expect(o.failure, CardMeasurementFailure.implausibleMeasurement);
    });
  });

  group('burstConfidenceLevel', () {
    test('steady burst → high', () {
      expect(
        burstConfidenceLevel(scaleMedian: 0.536, scaleIqr: 0.002),
        'high',
      );
    });

    test('normal shake → medium', () {
      expect(
        burstConfidenceLevel(scaleMedian: 0.536, scaleIqr: 0.010),
        'medium',
      );
    });

    test('wild burst → low', () {
      expect(
        burstConfidenceLevel(scaleMedian: 0.536, scaleIqr: 0.030),
        'low',
      );
    });

    test('garbage median → low, never throws', () {
      expect(
        burstConfidenceLevel(scaleMedian: 0, scaleIqr: 0.001),
        'low',
      );
      expect(
        burstConfidenceLevel(
          scaleMedian: double.nan,
          scaleIqr: double.nan,
        ),
        'low',
      );
    });
  });
}
