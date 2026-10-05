/// **V4.6's live fit verdict, as a pure decision.** Given the product, the
/// selected size and one live reading of the foot, what — if anything — may the
/// card beside the shoe say?
///
/// Pure Dart — no Flutter, no provider, no channel — for the same reason
/// `fit_engine.dart` and `try_on_coach.dart` are: every sentence a customer can
/// be shown beside a camera is pinned in a table test, where there is no camera
/// to blame.
///
/// **Five decisions are this file.**
///
///  1. **The live measurement, not the saved scan.** The verdict on the try-on
///     screen grades the foot in the frame. The saved profile is a measurement
///     from some earlier day; V4.7 is where the two are *compared* ("your saved
///     size may be stale"), which is deliberately not the same thing as merging
///     them — a verdict that mixed a fresh length with an old one would be
///     wrong about both.
///  2. **Length only, and it says so.** The tracker measures heel→toe and
///     nothing else, so the width comparison is absent by construction rather
///     than by a broken number — `FootFitInput.widthMm` stays null, and the
///     engine's own reason list names the gap.
///  3. **The lock gates speech.** No lock, no card — the shoe keeps drawing
///     from the last anchor through an unlock (the V4.2 rule, a shoe that
///     detaches at 0.44 is worse than a slightly stale one), but a *claim*
///     about fit does not survive the tracker losing the foot.
///  4. **The engine's own confidence decides which card.** A measurement can be
///     good enough to draw and not good enough to answer with: when
///     [FitVerdict.isConfident] is false the verdict is replaced by the
///     nudge — the roadmap's "scan a bit closer for a better verdict" — rather
///     than printed with a hedge. That floor is the same one the V1 card honors,
///     so no surface invents its own idea of "confident".
///  5. **One reading, shared with the shoe.** The millimetres passed in are the
///     tracker's *eased* length — the very number V4.3's frame-scale correction
///     sizes the drawn shoe with (`FootPoseTracker.Measure`) — so the verdict
///     and the shoe can never describe two different feet.
library;

import 'fit_engine.dart';
import 'size_key.dart';

/// The live session facts the verdict card reads, as one immutable snapshot.
///
/// Owned and published by `TryOnSessionController` (`liveFoot`), updated from
/// the native `footMeasure` stream at ~2 Hz and from each `footLock` edge, and
/// cleared whenever the loop stops. [lengthMm] is null until the first
/// measurement arrives; [locked] is the native tracker's own lock, never
/// re-derived here.
class TryOnLiveFoot {
  /// Eased heel→toe length in millimetres, or null before the first reading.
  final double? lengthMm;

  /// Post-smoothing quality (0–1) the length was read at.
  final double quality;

  /// The native tracker's lock state at the same instant.
  final bool locked;

  const TryOnLiveFoot({
    this.lengthMm,
    this.quality = 0,
    this.locked = false,
  });

  @override
  String toString() => 'TryOnLiveFoot(length: ${lengthMm ?? '-'} mm, '
      'quality: ${quality.toStringAsFixed(2)}, locked: $locked)';
}

/// What the live-verdict card should show.
enum TryOnFitCardStatus {
  /// Nothing to say — and therefore nothing drawn. Covers every cannot-answer
  /// case: no last spec, no gradeable size, no lock, no measurement yet, or a
  /// measurement the engine refuses to grade.
  hidden,

  /// The engine's answer, confident enough to print.
  verdict,

  /// There is a measurement, but not a confident one: say what to do instead of
  /// what the answer might be.
  nudge,
}

/// What to render, decided from the product, the size and the live reading.
class TryOnFitCardState {
  final TryOnFitCardStatus status;

  /// The engine's answer — non-null exactly when [status] is
  /// [TryOnFitCardStatus.verdict].
  final FitVerdict? verdict;

  /// The EU size [verdict] is about — non-null exactly with [verdict].
  final double? sizeEu;

  const TryOnFitCardState._(this.status, {this.verdict, this.sizeEu});

  static const TryOnFitCardState hidden =
      TryOnFitCardState._(TryOnFitCardStatus.hidden);

  static const TryOnFitCardState nudge =
      TryOnFitCardState._(TryOnFitCardStatus.nudge);

  static TryOnFitCardState answer(FitVerdict verdict, double sizeEu) =>
      TryOnFitCardState._(
        TryOnFitCardStatus.verdict,
        verdict: verdict,
        sizeEu: sizeEu,
      );

  /// Whether the card draws anything at all.
  bool get isVisible => status != TryOnFitCardStatus.hidden;
}

/// Decide what the live-verdict card shows for one product, one selected size
/// and one reading of the foot.
///
/// The order is what a customer can act on, and each early return is a
/// deliberate silence rather than a fallback: a product with no last spec
/// (roadmap V1.6's "no specs ⇒ hide"), a size with no number to grade, an
/// unlocked tracker, or no measurement yet.
///
/// A [FitBands] override exists for tests and for the V0.8 threshold workshop,
/// exactly as [fitVerdictAt]'s does — the shipped default is the engine's.
TryOnFitCardState tryOnFitCardStateFor({
  required Map<String, dynamic> product,
  required String? selectedSize,
  required TryOnLiveFoot live,
  FitBands bands = const FitBands(),
}) {
  // No last spec, no verdict — and no card: an empty one would advertise a
  // feature this product cannot have (the V1 rule, unchanged).
  final specs = FitSpecs.fromProduct(product);
  if (specs == null) return TryOnFitCardState.hidden;

  final sizeEu = selectedSize == null ? null : sizeNumberInEu(selectedSize);
  if (sizeEu == null) return TryOnFitCardState.hidden;

  // The lock is the tracker saying "this is a foot I can follow". Before it, the
  // numbers exist but the claim cannot be made; after it drops, the coach card
  // is the surface that speaks.
  if (!live.locked) return TryOnFitCardState.hidden;

  final lengthMm = live.lengthMm;
  if (lengthMm == null || !lengthMm.isFinite || lengthMm <= 0) {
    return TryOnFitCardState.hidden;
  }

  final verdict = fitVerdictAt(
    foot: FootFitInput(
      lengthMm: lengthMm,
      // No width: the tracker measures heel→toe only, and the engine's reasons
      // will say the width was not compared rather than pretending it was.
      widthMm: null,
      scanConfidence: live.quality,
    ),
    shoe: specs,
    sizeEu: sizeEu,
    bands: bands,
  );
  // The engine refuses implausible millimetres and ungradeable sizes on its own
  // (a 40 mm "foot" is a bad reading, not a small one) — same silence.
  if (verdict == null) return TryOnFitCardState.hidden;

  return verdict.isConfident
      ? TryOnFitCardState.answer(verdict, sizeEu)
      : TryOnFitCardState.nudge;
}
