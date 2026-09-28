/// What the fit verdict card should render — and, more importantly, when it
/// should render **nothing**.
///
/// Pure Dart — no Flutter — so every fallback rule is unit-testable without a
/// widget harness, following `fit_engine.dart` and `size_match.dart`. The
/// widget (`lib/widgets/fit_verdict_card.dart`) owns the providers, the flag
/// and the one scan fetch; this file owns *the decision*.
///
/// The rule the whole surface follows (roadmap V1.6, plan §8 R1): **never
/// wrong, never confident about it.** A product with no last spec, a page with
/// no size selected, a size the engine refuses to grade, a customer with no
/// scan — each is a different reason to say nothing, and all of them say
/// nothing rather than a guess. The only two things this card ever adds to a
/// page are a verdict (with its reasons) and an invitation to scan, which is a
/// fact about the customer rather than a claim about the shoe.
library;

import '../models/foot_measurement.dart';
import 'fit_engine.dart';
import 'size_key.dart';

/// Why the card is showing — or hiding.
enum FitVerdictCardStatus {
  /// The kill switch (`AppConstants.virtualFitEnabled`) is off.
  disabled,

  /// The product carries no usable last spec (`FitSpecs.fromProduct` is null):
  /// the columns are unset, half-filled, or implausible.
  noSpecs,

  /// No size is selected on the page yet, or the selected string carries no
  /// number at all (`'Other'`, `''`). A verdict is *about a size*, so there is
  /// nothing to grade.
  ///
  /// A size in a system this app cannot convert is not this case: it is graded
  /// only if it happens to land within [kMaxExtrapolationSteps] of the measured
  /// sample, so it lands in [ungradeable] instead — and a catalog that stores
  /// nothing else yields no selected size at all, because `stockByEuSize`
  /// skips those rows rather than guessing at them.
  noSize,

  /// The engine refused this size — most often further than 8 EU steps from
  /// the size the seller measured, where the 6.67 mm/step line means nothing.
  ungradeable,

  /// The customer has a foot profile, but its scan's millimetres are still
  /// being fetched. A loading beat, not a verdict.
  awaitingScan,

  /// No scan on hand — either never scanned, or the fetch came back empty.
  /// The card invites one; it does not guess a size.
  needsScan,

  /// The fetch for a saved scan failed. We cannot tell an un-scanned customer
  /// from a scanned one, so we say nothing: inviting a scan the customer has
  /// already done costs them a scan and reads as a bug.
  unavailable,

  /// The answer.
  verdict,
}

/// How far the card got in obtaining the saved scan's millimetres.
///
/// The card's own state, not the provider's: `FootMeasurementProvider` holds a
/// measurement in memory only after a scan *in this session*, so a customer who
/// scanned last week arrives here with nothing and the card must go and read
/// it (see `FitVerdictCard`). These four values are the whole story of that
/// read, and they are what separates "you have not scanned yet" from "we could
/// not check".
enum FitScanProbe {
  /// No saved foot profile — nothing to fetch, and an invitation is truthful.
  unnecessary,

  /// A saved profile exists and its measurement is being fetched.
  pending,

  /// The fetch finished. No measurement in hand means there is none to have.
  done,

  /// The fetch failed. We cannot know, so we do not speak.
  failed,
}

/// What to render, decided from the product, the selected size and the scan
/// state. Built by [fitVerdictCardStateFor].
class FitVerdictCardState {
  final FitVerdictCardStatus status;

  /// The engine's answer — non-null exactly when [status] is
  /// [FitVerdictCardStatus.verdict].
  final FitVerdict? verdict;

  /// The EU size [verdict] is about — non-null exactly with [verdict].
  final double? sizeEu;

  const FitVerdictCardState._(this.status, {this.verdict, this.sizeEu});

  /// Whether the card renders anything at all.
  ///
  /// `false` is the roadmap's "no specs ⇒ hide the card" plus every other
  /// cannot-say case. A hidden card leaves no gap behind it — the widget
  /// returns a `SizedBox.shrink()`, and the product page owns its own spacing.
  bool get isVisible =>
      status == FitVerdictCardStatus.verdict ||
      status == FitVerdictCardStatus.awaitingScan ||
      status == FitVerdictCardStatus.needsScan;

  /// The state for a status that answers with no verdict — including the two
  /// that are visible: the scan invitation and the awaiting-scan beat.
  static FitVerdictCardState of(FitVerdictCardStatus status) =>
      FitVerdictCardState._(status);

  static FitVerdictCardState answer(FitVerdict verdict, double sizeEu) =>
      FitVerdictCardState._(
        FitVerdictCardStatus.verdict,
        verdict: verdict,
        sizeEu: sizeEu,
      );
}

/// Decide what the fit card shows for one product page, one selected size and
/// one scan state.
///
/// Order matters, and it follows what the customer can act on: the switch, then
/// whether the shoe *can* be graded at all, then the customer's own scan, then
/// the size. The scan comes before the size deliberately — an invitation to
/// scan is true whatever size is selected (and the page selects one a moment
/// later anyway), while a verdict needs the size.
///
/// [probe] is supplied by the widget rather than read here, so this file stays
/// free of `AppConstants` and of the provider — and so the whole "is there a
/// scan to grade with" question has exactly one implementation, in
/// `FitVerdictCard`, that both the decision and the fetch obey.
FitVerdictCardState fitVerdictCardStateFor({
  required bool enabled,
  required Map<String, dynamic> product,
  required String? selectedSize,
  required FootMeasurement? measurement,
  required FitScanProbe probe,
  FitBands bands = const FitBands(),
}) {
  if (!enabled) {
    return FitVerdictCardState.of(FitVerdictCardStatus.disabled);
  }

  // No last spec, no verdict — and no card: an empty card would be an
  // advertisement for a feature this product cannot have.
  final specs = FitSpecs.fromProduct(product);
  if (specs == null) {
    return FitVerdictCardState.of(FitVerdictCardStatus.noSpecs);
  }

  final foot = footFitInputFrom(measurement);
  if (foot == null) {
    return switch (probe) {
      // A profile exists and we are reading it — say nothing rather than
      // inviting a scan the customer may have already done.
      FitScanProbe.pending => FitVerdictCardState.of(
          FitVerdictCardStatus.awaitingScan,
        ),
      // A failed read is not evidence of anything.
      FitScanProbe.failed => FitVerdictCardState.of(
          FitVerdictCardStatus.unavailable,
        ),
      // Never scanned, or scanned but no measurement came back. Both are
      // "we have no millimetres" — the invitation is the honest next step.
      FitScanProbe.unnecessary ||
      FitScanProbe.done => FitVerdictCardState.of(
          FitVerdictCardStatus.needsScan,
        ),
    };
  }
  // A measurement with no length cannot answer a sizing question, and the
  // engine would only say so in its own words. `footFitInputFrom` already
  // returns null for it, which the branch above handles.

  final euSize = selectedSize == null ? null : sizeNumberInEu(selectedSize);
  if (euSize == null) {
    return FitVerdictCardState.of(FitVerdictCardStatus.noSize);
  }

  final verdict = fitVerdictAt(
    foot: foot,
    shoe: specs,
    sizeEu: euSize,
    bands: bands,
  );
  if (verdict == null) {
    return FitVerdictCardState.of(FitVerdictCardStatus.ungradeable);
  }

  return FitVerdictCardState.answer(verdict, euSize);
}
