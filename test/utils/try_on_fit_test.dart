import 'package:app/utils/fit_engine.dart';
import 'package:app/utils/try_on_fit.dart';
import 'package:flutter_test/flutter_test.dart';

/// **V4.6's rules, as a table.** What the live-verdict card may say is a pure
/// function of the product, the selected size and one reading from the tracker —
/// no camera, no channel, no controller — so every silence and every sentence
/// can be pinned here.
///
/// Three things are being protected:
///
///   1. **The silence.** No spec, no size, no lock, no measurement, a broken
///      number or a reading the engine refuses must all produce `hidden` —
///      never a guessed band.
///   2. **The verdict.** It grades the *selected* size from the live length,
///      and it is length-only on purpose: the reasons must say the width was
///      not compared rather than pretending it was.
///   3. **The nudge.** A real but unconvincing reading asks for a better one
///      instead of printing a hint as an answer — and the decision is the
///      engine's composite confidence, not a raw quality threshold.
void main() {
  Map<String, dynamic> productWithSpec({double last = 275, double ref = 42}) =>
      <String, dynamic>{
        'last_length_mm': last,
        'fit_ref_size_eu': ref,
        'last_width_mm': 100,
      };

  TryOnFitCardState state({
    double? lengthMm = 265,
    double quality = 0.9,
    bool locked = true,
    String? size = '42',
    Map<String, dynamic>? product,
  }) =>
      tryOnFitCardStateFor(
        product: product ?? productWithSpec(),
        selectedSize: size,
        live: TryOnLiveFoot(lengthMm: lengthMm, quality: quality, locked: locked),
      );

  group('silence', () {
    test('no last spec is hidden, however good the reading', () {
      final result = state(product: <String, dynamic>{'id': 1, 'name': 'x'});

      expect(result.status, TryOnFitCardStatus.hidden);
      expect(result.isVisible, isFalse);
    });

    test('no size, or a size with no number, is hidden', () {
      expect(state(size: null).status, TryOnFitCardStatus.hidden);
      expect(state(size: 'Other').status, TryOnFitCardStatus.hidden);
    });

    test('an unlocked tracker is hidden — a claim does not outlive the lock',
        () {
      expect(state(locked: false).status, TryOnFitCardStatus.hidden);
    });

    test('no measurement yet is hidden', () {
      expect(state(lengthMm: null).status, TryOnFitCardStatus.hidden);
    });

    test('a broken length is hidden rather than graded', () {
      expect(state(lengthMm: double.nan).status, TryOnFitCardStatus.hidden);
      expect(
        state(lengthMm: double.infinity).status,
        TryOnFitCardStatus.hidden,
      );
      expect(state(lengthMm: 0).status, TryOnFitCardStatus.hidden);
      expect(state(lengthMm: -200).status, TryOnFitCardStatus.hidden);
    });

    test('a measurement the engine refuses (40 mm "foot") is hidden', () {
      expect(state(lengthMm: 40).status, TryOnFitCardStatus.hidden);
    });

    test('a size past the engine\'s reach is hidden, not guessed', () {
      // fit_ref_size_eu is 42 and the engine refuses beyond ±8 steps.
      expect(state(size: '51').status, TryOnFitCardStatus.hidden);
    });
  });

  group('the verdict', () {
    test('a confident reading answers with the band, the size and the mm', () {
      final result = state();

      expect(result.status, TryOnFitCardStatus.verdict);
      expect(result.sizeEu, 42);
      final verdict = result.verdict!;
      expect(verdict.kind, FitVerdictKind.trueToSize);
      expect(verdict.toeAllowanceMm, closeTo(10, 0.001));
    });

    test('the width is absent by construction, and the reasons say so', () {
      final verdict = state().verdict!;

      expect(verdict.widthCompared, isFalse);
      expect(
        verdict.reasons.join(' '),
        contains('width not compared'),
        reason: 'a length-only live reading must not imply the width was '
            'checked',
      );
    });

    test('it grades the selected size, not the reference one', () {
      final result = state(size: '43');

      expect(result.status, TryOnFitCardStatus.verdict);
      expect(result.sizeEu, 43);
      expect(result.verdict!.kind, FitVerdictKind.roomy);
      expect(result.verdict!.toeAllowanceMm, closeTo(16.67, 0.01));
    });
  });

  group('the nudge', () {
    test('a real but unconvincing reading asks for a better one', () {
      final result = state(quality: 0.7);

      expect(result.status, TryOnFitCardStatus.nudge);
      expect(result.verdict, isNull, reason: 'no claim is exposed to print');
      expect(result.isVisible, isTrue, reason: 'the ask itself is the card');
    });

    test('the decision is the engine\'s confidence, not the raw quality', () {
      // Quality 0.95, but the size is 7 steps from the measured sample: the
      // extrapolation discount drops the composite confidence under the floor.
      // A card that checked the quality number alone would print this one.
      final result = state(quality: 0.95, size: '49');

      expect(result.status, TryOnFitCardStatus.nudge);
    });
  });
}
