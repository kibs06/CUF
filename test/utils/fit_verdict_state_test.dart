import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/foot_measurement.dart';
import 'package:app/utils/fit_engine.dart';
import 'package:app/utils/fit_verdict_state.dart';

/// The card's fallback rules (roadmap V1.6).
///
/// The value of this file is the list of cases where the card says **nothing**.
/// Every one of them is a place where a card that guessed would be
/// confidently wrong about a shoe the customer is about to buy: a product with
/// no last spec, a page with no size, a size the engine refuses, a customer
/// whose scan we could not read. The two visible states that are *not* a
/// verdict — the scan invitation and the reading beat — are pinned here too,
/// because telling a scanned customer to scan is the same class of mistake
/// from the other end.

/// A men's EU 42 product: 275 mm internal last, 98 mm wide, measured at 42.
Map<String, dynamic> productWith({
  Object? length = 275,
  Object? width = 98,
  Object? ref = 42,
}) => {
  'id': 'product-1',
  'last_length_mm': length,
  'last_width_mm': width,
  'fit_ref_size_eu': ref,
};

/// A 265 mm foot, 95 mm wide — 10 mm of toe room in the EU 42 above.
FootMeasurement scannedFoot({
  double? lengthMm = 265,
  double? widthMm = 95,
  double? leftLengthMm,
  double? leftWidthMm,
}) => FootMeasurement(
  userId: 'user-1',
  sizingFootSide: 'right',
  footLengthLeftMm: leftLengthMm,
  footWidthLeftMm: leftWidthMm,
  footLengthRightMm: lengthMm,
  footWidthRightMm: widthMm,
  paperSizeUsed: 'ar',
  scanDate: DateTime(2026, 9, 27),
);

FitVerdictCardState decide({
  Map<String, dynamic>? product,
  String? selectedSize = '42',
  FootMeasurement? measurement,
  FitScanProbe probe = FitScanProbe.done,
  bool enabled = true,
}) => fitVerdictCardStateFor(
  enabled: enabled,
  product: product ?? productWith(),
  selectedSize: selectedSize,
  measurement: measurement,
  probe: probe,
);

void main() {
  group('the kill switch', () {
    test('an off build renders nothing at all', () {
      final state = decide(measurement: scannedFoot(), enabled: false);

      expect(state.status, FitVerdictCardStatus.disabled);
      expect(state.isVisible, isFalse);
    });
  });

  group('no specs, no card (V1.6)', () {
    test('every half-filled or unmeasured spec hides the card', () {
      // The whole product row the seller form can produce without a spec.
      final cases = <String, Map<String, dynamic>>{
        'nothing set': productWith(
          length: null,
          width: null,
          ref: null,
        ),
        'length without a reference size': productWith(ref: null),
        'reference size without a length': productWith(length: null),
        'a length outside the plausible band': productWith(length: 4200),
        'a reference size outside the EU band': productWith(ref: 90),
        'an unparseable length': productWith(length: 'about 27'),
      };

      for (final entry in cases.entries) {
        final state = decide(product: entry.value, measurement: scannedFoot());

        expect(
          state.status,
          FitVerdictCardStatus.noSpecs,
          reason: '${entry.key} should hide the card',
        );
        expect(state.isVisible, isFalse, reason: entry.key);
        expect(state.verdict, isNull, reason: entry.key);
      }
    });

    test('no specs hides the card even for a scanned customer', () {
      // The alternative — an empty "add a spec" card for sellers to see — is
      // a customer-facing advertisement for a product that cannot have one.
      final state = decide(
        product: productWith(length: null, width: null, ref: null),
        measurement: scannedFoot(),
        probe: FitScanProbe.unnecessary,
      );

      expect(state.status, FitVerdictCardStatus.noSpecs);
    });
  });

  group('no size selected', () {
    test('the card waits rather than grading an unstated size', () {
      final state = decide(selectedSize: null, measurement: scannedFoot());

      expect(state.status, FitVerdictCardStatus.noSize);
      expect(state.isVisible, isFalse);
    });

    test('a size string with no number in it says nothing either', () {
      final state = decide(selectedSize: 'Other', measurement: scannedFoot());

      expect(state.status, FitVerdictCardStatus.noSize);
      expect(state.isVisible, isFalse);
    });
  });

  group('a size the engine refuses', () {
    test('nine steps from the measured sample is no verdict, not a bad one', () {
      // 275 mm at EU 42 graded down to EU 33 is a 6.67 mm/step guess nine steps
      // out — past kMaxExtrapolationSteps, where the engine stops answering.
      final state = decide(selectedSize: '33', measurement: scannedFoot());

      expect(state.status, FitVerdictCardStatus.ungradeable);
      expect(state.isVisible, isFalse);
    });

    test('a size in another system is never smuggled in as EU', () {
      // `sizeNumberInEu('JP 25')` keeps its raw 25 — the extrapolation cap is
      // what stops it being graded against an EU 42 last.
      final state = decide(selectedSize: 'JP 25', measurement: scannedFoot());

      expect(state.status, FitVerdictCardStatus.ungradeable);
      expect(state.isVisible, isFalse);
    });
  });

  group('the customer side (V1.6)', () {
    test('no scan on file invites one instead of guessing a size', () {
      final state = decide(measurement: null, probe: FitScanProbe.unnecessary);

      expect(state.status, FitVerdictCardStatus.needsScan);
      expect(state.isVisible, isTrue);
      expect(state.verdict, isNull);
    });

    test('a read that came back empty still invites one', () {
      // A manual-picker customer: a size on file, never a millimetre.
      final state = decide(measurement: null, probe: FitScanProbe.done);

      expect(state.status, FitVerdictCardStatus.needsScan);
    });

    test('a read in flight neither invites nor answers', () {
      final state = decide(measurement: null, probe: FitScanProbe.pending);

      expect(state.status, FitVerdictCardStatus.awaitingScan);
      expect(state.isVisible, isTrue);
      expect(state.verdict, isNull);
    });

    test('a failed read says nothing, because it cannot tell scanned from not', () {
      final state = decide(measurement: null, probe: FitScanProbe.failed);

      expect(state.status, FitVerdictCardStatus.unavailable);
      expect(state.isVisible, isFalse);
    });

    test('a measurement with a width but no length is no measurement', () {
      // `footFitInputFrom` needs a length; a width alone cannot size a shoe.
      final state = decide(
        measurement: scannedFoot(lengthMm: null, widthMm: 95),
        probe: FitScanProbe.done,
      );

      expect(state.status, FitVerdictCardStatus.needsScan);
    });

    test('a measurement in hand ends the question whatever the read did', () {
      // The provider can hold a scan from earlier in this session while the
      // read of the stored one fails: the memory wins, no card is hidden.
      final state = decide(
        measurement: scannedFoot(),
        probe: FitScanProbe.failed,
      );

      expect(state.status, FitVerdictCardStatus.verdict);
    });

    test('the scan invitation is checked before the size', () {
      // Both are missing. The invitation is true whatever size is selected and
      // the page selects one a moment later, so it is the one worth showing.
      final state = decide(
        selectedSize: null,
        measurement: null,
        probe: FitScanProbe.unnecessary,
      );

      expect(state.status, FitVerdictCardStatus.needsScan);
    });
  });

  group('the answer', () {
    test('grades the selected size against the customer own scan', () {
      final state = decide(measurement: scannedFoot());

      expect(state.status, FitVerdictCardStatus.verdict);
      expect(state.isVisible, isTrue);
      expect(state.sizeEu, 42);
      expect(state.verdict!.kind, FitVerdictKind.trueToSize);
      expect(state.verdict!.toeAllowanceMm, closeTo(10, 0.01));
      expect(state.verdict!.widthCompared, isTrue);
    });

    test('the verdict follows the size, not the page', () {
      final snug = decide(selectedSize: '41', measurement: scannedFoot());
      final roomy = decide(selectedSize: '43', measurement: scannedFoot());

      expect(snug.verdict!.kind, FitVerdictKind.snug);
      expect(snug.sizeEu, 41);
      expect(roomy.verdict!.kind, FitVerdictKind.roomy);
      expect(roomy.sizeEu, 43);
    });

    test('a half size is graded like any other', () {
      final state = decide(selectedSize: '42.5', measurement: scannedFoot());

      expect(state.status, FitVerdictCardStatus.verdict);
      expect(state.sizeEu, 42.5);
    });

    test('sizes written with a system prefix are read as EU', () {
      final state = decide(selectedSize: 'EU 42', measurement: scannedFoot());

      expect(state.sizeEu, 42);
      expect(state.verdict!.kind, FitVerdictKind.trueToSize);
    });

    test('a spec with no measured width still answers, and says what it lost', () {
      final state = decide(
        product: productWith(width: null),
        measurement: scannedFoot(),
      );

      expect(state.status, FitVerdictCardStatus.verdict);
      expect(state.verdict!.widthCompared, isFalse);
      expect(
        state.verdict!.reasons.join(' '),
        contains('no last width recorded'),
      );
      // Completeness drops the confidence, it does not silence the verdict.
      expect(state.verdict!.confidence, lessThan(0.85));
    });

    test('an out-of-band scan width costs the width, not the verdict', () {
      final state = decide(measurement: scannedFoot(widthMm: 400));

      expect(state.status, FitVerdictCardStatus.verdict);
      expect(state.verdict!.widthCompared, isFalse);
      expect(state.verdict!.reasons.join(' '), contains('out of range'));
    });

    test('the caller can pass a tuned band set through', () {
      // The V0.8 workshop hook: one parameter, and the shipped defaults are
      // untouched for every other caller.
      final state = fitVerdictCardStateFor(
        enabled: true,
        product: productWith(),
        selectedSize: '42',
        measurement: scannedFoot(),
        probe: FitScanProbe.done,
        bands: const FitBands(trueToeMaxMm: 9),
      );

      // 10 mm of toe room fits the default band and not the tightened one.
      expect(state.verdict!.kind, FitVerdictKind.roomy);
    });
  });
}
