import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/foot_measurement.dart';
import 'package:app/utils/fit_engine.dart';

/// The verdict rule: two sets of millimetres in, one honest answer out.
///
/// These tests pin the *shipped defaults* of architecture §2.6 — the band
/// edges, the order the bands are checked in, the confidence model — so that
/// the V0.8 artisan workshop changes them on purpose. The failure modes that
/// matter here are the ones where being confidently wrong costs a customer a
/// return: a missing spec, an unmeasured width, a size far from the sample, a
/// foot that cannot physically enter the shoe.

/// A men's EU 42 last: 275 mm internal length, 98 mm internal width.
FitSpecs shoeAt42({double length = 275, double? width = 98, double ref = 42}) =>
    FitSpecs(lastLengthMm: length, lastWidthMm: width, refSizeEu: ref);

/// A 265 mm foot, 95 mm wide — 10 mm of toe room in the EU 42 above.
FootFitInput footOf({double length = 265, double? width = 95, double? confidence})
    => FootFitInput(lengthMm: length, widthMm: width, scanConfidence: confidence);

FitVerdict verdictAt(double size, {FitSpecs? shoe, FootFitInput? foot}) =>
    fitVerdictAt(
      foot: foot ?? footOf(),
      shoe: shoe ?? shoeAt42(),
      sizeEu: size,
    )!;

FootMeasurement measurementOf({
  String? sizingFootSide,
  double? footLengthLeftMm,
  double? footWidthLeftMm,
  double? footLengthRightMm,
  double? footWidthRightMm,
  double? footLengthLeftCompensatedMm,
  double? footWidthLeftCompensatedMm,
  double? footLengthRightCompensatedMm,
  double? footWidthRightCompensatedMm,
  double? overallConfidenceScore,
  String? confidenceLevel,
}) =>
    FootMeasurement(
      userId: 'user-1',
      footLengthLeftMm: footLengthLeftMm,
      footWidthLeftMm: footWidthLeftMm,
      footLengthRightMm: footLengthRightMm,
      footWidthRightMm: footWidthRightMm,
      footLengthLeftCompensatedMm: footLengthLeftCompensatedMm,
      footWidthLeftCompensatedMm: footWidthLeftCompensatedMm,
      footLengthRightCompensatedMm: footLengthRightCompensatedMm,
      footWidthRightCompensatedMm: footWidthRightCompensatedMm,
      sizingFootSide: sizingFootSide,
      overallConfidenceScore: overallConfidenceScore,
      confidenceLevel: confidenceLevel,
      paperSizeUsed: 'ar',
      scanDate: DateTime(2026, 9, 27),
    );

void main() {
  group('the grading step', () {
    test('adds one 6.67 mm EU step of length per size', () {
      final shoe = shoeAt42();
      expect(lastLengthAt(shoe, 42), closeTo(275, 0.001));
      expect(lastLengthAt(shoe, 43), closeTo(281.67, 0.001));
      expect(lastLengthAt(shoe, 40), closeTo(261.66, 0.001));
    });

    test('grades width by the documented 2 mm step', () {
      expect(lastWidthAt(shoeAt42(), 43), closeTo(100, 0.001));
      expect(lastWidthAt(shoeAt42(), 38), closeTo(90, 0.001));
    });

    test('a spec with no measured width grades to null, not to a guess', () {
      expect(lastWidthAt(shoeAt42(width: null), 43), isNull);
    });

    test('allowances grow monotonically, one step apart', () {
      final first = verdictAt(41).toeAllowanceMm;
      final second = verdictAt(42).toeAllowanceMm;
      final third = verdictAt(43).toeAllowanceMm;

      expect(second - first, closeTo(kEuLengthStepMm, 0.001));
      expect(third - second, closeTo(kEuLengthStepMm, 0.001));
    });
  });

  group('the band table (architecture §2.6)', () {
    // A 265 mm foot against a 275 mm EU 42 last, one size per band.
    final cases = <(double size, FitVerdictKind kind, double toeAllowance)>[
      (40, FitVerdictKind.tooSmall, -3.34),
      (41, FitVerdictKind.snug, 3.33),
      (42, FitVerdictKind.trueToSize, 10),
      (43, FitVerdictKind.roomy, 16.67),
      (44, FitVerdictKind.tooBig, 23.34),
    ];

    for (final (size, kind, toeAllowance) in cases) {
      test('EU $size reports ${kind.name}', () {
        final verdict = verdictAt(size);

        expect(verdict.kind, kind);
        expect(verdict.toeAllowanceMm, closeTo(toeAllowance, 0.01));
        expect(verdict.widthCompared, isTrue);
      });
    }

    test('a size where both ends are out of band reads as tooBig', () {
      // EU 44 is 23 mm long AND 7 mm wide — the length is the bigger problem,
      // and `tooBig` is checked before the width can call it merely roomy.
      final verdict = verdictAt(44);

      expect(verdict.kind, FitVerdictKind.tooBig);
      expect(verdict.widthAllowanceMm, closeTo(7, 0.01));
    });

    test('the toe edge sits exactly at 8 mm and no allowance is hidden', () {
      final shoe = shoeAt42(length: 270, width: null);
      final snug = fitVerdictAt(
        foot: footOf(length: 262.5, width: null),
        shoe: shoe,
        sizeEu: 42,
      )!;
      final trueFit = fitVerdictAt(
        foot: footOf(length: 262, width: null),
        shoe: shoe,
        sizeEu: 42,
      )!;

      expect(snug.kind, FitVerdictKind.snug);
      expect(trueFit.kind, FitVerdictKind.trueToSize);
    });

    test('the width band is inclusive at 6 mm', () {
      // Socks are already in the payload (`ScanResultsPayloadV2`), so the engine
      // applies no sock allowance of its own: the boundary is the printed one.
      final atSix = fitVerdictAt(
        foot: footOf(length: 265, width: 92),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;
      final pastSix = fitVerdictAt(
        foot: footOf(length: 265, width: 91.5),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(atSix.widthAllowanceMm, closeTo(6, 0.001));
      expect(atSix.kind, FitVerdictKind.trueToSize);
      expect(pastSix.kind, FitVerdictKind.roomy);
    });

    test('a narrow last called tooSmall on width alone, with toe room to spare',
        () {
      final verdict = fitVerdictAt(
        foot: footOf(length: 265, width: 100),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.toeAllowanceMm, closeTo(10, 0.01));
      expect(verdict.widthAllowanceMm, closeTo(-2, 0.01));
      expect(verdict.kind, FitVerdictKind.tooSmall);
      expect(verdict.reasons.join(' '), contains('narrower than your foot'));
    });

    test('the width band is inclusive at −1 mm', () {
      final verdict = fitVerdictAt(
        foot: footOf(length: 265, width: 99),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.widthAllowanceMm, closeTo(-1, 0.001));
      expect(verdict.kind, FitVerdictKind.trueToSize);
    });

    test('a loose last outranks a snug length, and the reasons say why', () {
      // 4 mm of toe room (snug) with a last 7 mm wider than the foot (loose):
      // going up a size would fix the length and worsen the width.
      final verdict = fitVerdictAt(
        foot: footOf(length: 271, width: 91),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.kind, FitVerdictKind.roomy);
      expect(
        verdict.reasons.join(' '),
        contains('a different last shape is likely to fit you better'),
      );
    });

    test('a last shorter than the foot says so in millimetres', () {
      final verdict = fitVerdictAt(
        foot: footOf(length: 280, width: 95),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.toeAllowanceMm, closeTo(-5, 0.01));
      expect(verdict.reasons.first, contains('shorter than your foot'));
    });

    test('a length veto names the minimum it broke', () {
      // 1.5 mm of toe room: inside neither the snug band nor the 3 mm floor,
      // so the sentence says which line was crossed — and not just "too small".
      final verdict = fitVerdictAt(
        foot: footOf(length: 273.5, width: 95),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.kind, FitVerdictKind.tooSmall);
      expect(
        verdict.reasons.first,
        contains('under the 3 mm minimum'),
      );
    });

    test('a width veto does not blame the length for it', () {
      // A real customer's foot: 3.3 mm of toe room — *inside* the band — on a
      // last 2 mm narrower than the foot. The verdict is `tooSmall` on the
      // width alone, so the first reason must not claim a minimum the toe room
      // never crossed; the width sentence under it is the explanation.
      final verdict = fitVerdictAt(
        foot: footOf(length: 271.67, width: 100),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.toeAllowanceMm, closeTo(3.33, 0.02));
      expect(verdict.widthAllowanceMm, closeTo(-2, 0.01));
      expect(verdict.kind, FitVerdictKind.tooSmall);
      expect(verdict.reasons.first, isNot(contains('minimum')));
      expect(verdict.reasons.first, contains('only 3 mm of toe room'));
      expect(verdict.reasons[1], contains('narrower than your foot'));
    });

    test('the last-shape advice waits until the length is actually snug', () {
      // Too short *and* too wide: "snug in length" would be false, and its
      // conclusion — try another last, not another size — is the wrong advice
      // for a shoe that a bigger size would fit.
      final verdict = fitVerdictAt(
        foot: footOf(length: 275, width: 91),
        shoe: shoeAt42(),
        sizeEu: 42,
      )!;

      expect(verdict.kind, FitVerdictKind.tooSmall);
      expect(verdict.widthAllowanceMm, closeTo(7, 0.01));
      expect(
        verdict.reasons.join(' '),
        isNot(contains('a different last shape')),
      );
      expect(verdict.reasons.join(' '), contains('wider than your foot'));
    });
  });

  group('missing inputs never become a guess', () {
    test('no spec, no verdict', () {
      expect(FitSpecs.fromProduct(const {}), isNull);
      expect(FitSpecs.fromProduct(const {'last_length_mm': 275}), isNull);
      expect(FitSpecs.fromProduct(const {'fit_ref_size_eu': 42}), isNull);
    });

    test('an implausible spec is refused rather than graded', () {
      expect(
        FitSpecs.fromProduct(
          const {'last_length_mm': 4200, 'fit_ref_size_eu': 42},
        ),
        isNull,
      );
      expect(
        FitSpecs.fromProduct(
          const {'last_length_mm': 275, 'fit_ref_size_eu': 60},
        ),
        isNull,
      );
    });

    test('an implausible width is dropped, keeping a length-only verdict', () {
      final specs = FitSpecs.fromProduct(
        const {'last_length_mm': 275, 'last_width_mm': 5, 'fit_ref_size_eu': 42},
      )!;

      expect(specs.lastLengthMm, 275);
      expect(specs.lastWidthMm, isNull);
    });

    test('a row read from Postgres parses numeric strings', () {
      final specs = FitSpecs.fromProduct(
        const <String, dynamic>{
          'last_length_mm': '275.5',
          'last_width_mm': '98',
          'heel_height_mm': '25',
          'fit_ref_size_eu': '42',
        },
      )!;

      expect(specs.lastLengthMm, closeTo(275.5, 0.001));
      expect(specs.lastWidthMm, closeTo(98, 0.001));
      expect(specs.heelHeightMm, closeTo(25, 0.001));
      expect(specs.refSizeEu, closeTo(42, 0.001));
    });

    test('a foot that cannot answer still gets no verdict', () {
      final foot = footOf(length: 40, width: 95);

      expect(fitVerdictAt(foot: foot, shoe: shoeAt42(), sizeEu: 42), isNull);
    });

    test('a broken last length is refused even when handed over directly', () {
      final shoe = FitSpecs(lastLengthMm: 4200, refSizeEu: 42);

      expect(fitVerdictAt(foot: footOf(), shoe: shoe, sizeEu: 42), isNull);
    });

    test('a size too far from the measured sample is refused', () {
      // 8 steps away is the last gradeable size (EU 42 ± 8 = 34…50).
      expect(verdictAt(50), isNotNull);
      expect(fitVerdictAt(foot: footOf(), shoe: shoeAt42(), sizeEu: 51), isNull);
      expect(fitVerdictAt(foot: footOf(), shoe: shoeAt42(), sizeEu: 33), isNull);
    });

    test('no width on the product: length-only verdict, and it says so', () {
      final verdict = verdictAt(42, shoe: shoeAt42(width: null));

      expect(verdict.kind, FitVerdictKind.trueToSize);
      expect(verdict.widthAllowanceMm, isNull);
      expect(verdict.widthCompared, isFalse);
      expect(
        verdict.reasons.join(' '),
        contains('no last width recorded'),
      );
    });

    test('no width on the scan: length-only verdict, and it says so', () {
      final verdict = verdictAt(42, foot: footOf(width: null));

      expect(verdict.widthAllowanceMm, isNull);
      expect(verdict.reasons.join(' '), contains('no width in your scan'));
    });

    test('a non-numeric scan width is named, not printed', () {
      // `double.nan.round()` throws, so the reason has to be built from a safe
      // value — and the verdict still has to exist.
      final verdict = verdictAt(42, foot: footOf(width: double.nan));

      expect(verdict.widthAllowanceMm, isNull);
      expect(verdict.kind, FitVerdictKind.trueToSize);
      expect(verdict.reasons.join(' '), contains('not a number'));
    });

    test('a broken scan width costs the comparison, not the verdict', () {
      // The length is the primary signal: one out-of-range width must not cost
      // the customer the whole verdict — but it must not be compared either.
      final verdict = verdictAt(42, foot: footOf(width: 10));

      expect(verdict.widthAllowanceMm, isNull);
      expect(verdict.kind, FitVerdictKind.trueToSize);
      expect(verdict.reasons.join(' '), contains('out of range'));
      expect(verdict.reasons.join(' '), isNot(contains('no width in your scan')));
    });
  });

  group('confidence', () {
    test('scan quality and a width comparison multiply', () {
      final verdict = verdictAt(42, foot: footOf(confidence: 0.8));

      expect(verdict.confidence, closeTo(0.8 * 0.85, 0.001));
      expect(verdict.isConfident, isTrue);
    });

    test('a length-only verdict is worth less than a two-sided one', () {
      final twoSided = verdictAt(42, foot: footOf(confidence: 0.8));
      final lengthOnly = verdictAt(
        42,
        foot: footOf(confidence: 0.8, width: null),
      );

      expect(lengthOnly.confidence, lessThan(twoSided.confidence));
    });

    test('an unmeasured scan confidence is not a good one', () {
      final verdict = verdictAt(42, foot: footOf(width: null));

      expect(verdict.confidence, closeTo(kUnknownScanConfidence * 0.60, 0.001));
    });

    test('a weak scan is named in the reasons', () {
      final verdict = verdictAt(42, foot: footOf(confidence: 0.4));

      expect(verdict.isConfident, isFalse);
      expect(verdict.reasons.join(' '), contains('weakest link'));
      expect(verdict.reasons.join(' '), contains('treat as a hint'));
    });

    test('grading away from the measured sample costs confidence', () {
      final atSample = verdictAt(42, foot: footOf(confidence: 1));
      final twoAway = verdictAt(44, foot: footOf(confidence: 1));
      final fiveAway = verdictAt(47, foot: footOf(confidence: 1));

      expect(twoAway.confidence, closeTo(atSample.confidence, 0.001));
      expect(fiveAway.confidence, closeTo(0.85 * 0.85, 0.001));
      expect(fiveAway.reasons.join(' '), contains('sizes away'));
    });
  });

  group('recommendFit — the tightest size that still fits', () {
    test('picks the true fit, not the roomiest one', () {
      final verdict = recommendFit(
        foot: footOf(),
        shoe: shoeAt42(),
        sizesEu: const [40, 41, 42, 43, 44],
      )!;

      expect(verdict.sizeEu, 42);
      expect(verdict.kind, FitVerdictKind.trueToSize);
      // A true fit needs no commentary.
      expect(verdict.reasons.join(' '), isNot(contains('closest fit')));
    });

    test('when nothing reaches the band it says so', () {
      final verdict = recommendFit(
        foot: footOf(),
        shoe: shoeAt42(),
        sizesEu: const [40, 41],
      )!;

      expect(verdict.sizeEu, 41);
      expect(verdict.kind, FitVerdictKind.snug);
      expect(verdict.reasons.join(' '), contains('closest fit'));
    });

    test('prefers snug over roomy when the range stops before the band', () {
      final verdict = recommendFit(
        foot: footOf(),
        shoe: shoeAt42(),
        sizesEu: const [41, 43, 44],
      )!;

      expect(verdict.kind, FitVerdictKind.snug);
    });

    test('all too small: the largest size is the closest to fitting', () {
      final verdict = recommendFit(
        foot: footOf(),
        shoe: shoeAt42(),
        sizesEu: const [38, 39, 40],
      )!;

      expect(verdict.sizeEu, 40);
      expect(verdict.kind, FitVerdictKind.tooSmall);
    });

    test('all too big: the smallest size is the closest to fitting', () {
      final verdict = recommendFit(
        foot: footOf(),
        shoe: shoeAt42(),
        sizesEu: const [46, 47],
      )!;

      expect(verdict.sizeEu, 46);
      expect(verdict.kind, FitVerdictKind.tooBig);
    });

    test('duplicate sizes are judged once', () {
      final verdict = recommendFit(
        foot: footOf(),
        shoe: shoeAt42(),
        sizesEu: const [42, 42, 42],
      )!;

      expect(verdict.sizeEu, 42);
    });

    test('nothing judgeable returns null rather than a size', () {
      expect(
        recommendFit(foot: footOf(), shoe: shoeAt42(), sizesEu: const []),
        isNull,
      );
      expect(
        recommendFit(
          foot: footOf(),
          shoe: shoeAt42(),
          sizesEu: const [60, 61],
        ),
        isNull,
      );
    });
  });

  group('footFitInputFrom — the scan side', () {
    test('reads the sizing foot, compensated values first', () {
      final input = footFitInputFrom(measurementOf(
        sizingFootSide: 'right',
        footLengthRightMm: 268,
        footLengthRightCompensatedMm: 271,
        footWidthRightMm: 96,
        footWidthRightCompensatedMm: 99,
        footLengthLeftMm: 284,
        footWidthLeftMm: 101,
      ))!;

      expect(input.lengthMm, 271);
      expect(input.widthMm, 99);
    });

    test('without a sizing foot it takes the longer one, and pairs its width',
        () {
      final input = footFitInputFrom(measurementOf(
        footLengthLeftMm: 260,
        footWidthLeftMm: 90,
        footLengthRightMm: 264,
        footWidthRightMm: 94,
      ))!;

      expect(input.lengthMm, 264);
      expect(input.widthMm, 94);
    });

    test('carries the numeric confidence when the scan recorded one', () {
      final input = footFitInputFrom(
        measurementOf(footLengthRightMm: 264, overallConfidenceScore: 0.82),
      )!;

      expect(input.scanConfidence, closeTo(0.82, 0.001));
    });

    test('falls back to the confidence band, and to null when there is none',
        () {
      expect(
        footFitInputFrom(
          measurementOf(footLengthRightMm: 264, confidenceLevel: 'high'),
        )!.scanConfidence,
        closeTo(0.9, 0.001),
      );
      expect(
        footFitInputFrom(measurementOf(footLengthRightMm: 264))!.scanConfidence,
        isNull,
      );
    });

    test('a scan with no length cannot answer a sizing question', () {
      expect(footFitInputFrom(null), isNull);
      expect(footFitInputFrom(measurementOf(footWidthRightMm: 94)), isNull);
    });
  });

  group('custom bands', () {
    test('the workshop can move a band without touching the defaults', () {
      const looser = FitBands(trueToeMaxMm: 18, tooBigToeMm: 26);
      final stock = verdictAt(43);
      final tuned = fitVerdictAt(
        foot: footOf(),
        shoe: shoeAt42(),
        sizeEu: 43,
        bands: looser,
      )!;

      expect(stock.kind, FitVerdictKind.roomy);
      expect(tuned.kind, FitVerdictKind.trueToSize);
    });
  });
}
