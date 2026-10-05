/// **V4.7's saved-size check, as a pure decision.** Given one live reading of
/// the foot and the customer's saved scan measurement, may the try-on screen
/// say "your saved size may be stale — rescan?"?
///
/// Pure Dart — no Flutter, no provider, no channel — for the same reason
/// `fit_engine.dart` and `try_on_fit.dart` are: the one sentence this phase
/// adds is pinned in a table test, where there is no camera and no profile to
/// blame.
///
/// **Five decisions are this file.**
///
///  1. **It compares, it never merges.** The live reading grades the foot in
///     the frame (V4.6's rule); the saved scan is a measurement from some
///     earlier day. This function is the one place the two meet, and all it
///     may produce is a suggestion — it never feeds the verdict, and it never
///     touches the selected size (the roadmap's "never silently switch
///     sizes": the notice carries no size at all, so no caller *can* switch
///     one from here).
///  2. **Both numbers are already the app's own.** The live side is
///     [TryOnLiveFoot]'s eased length — the very number V4.3 sizes the drawn
///     shoe with. The saved side is the caller's `FootMeasurement.maxFootLength`
///     — the very number `footFitInputFrom` grades with (the v2 E8 rule: every
///     millimetre the customer sees comes from one conversion path). Neither
///     side is re-derived here.
///  3. **The lock gates speech.** No lock, no notice: an unlocked tracker can
///     still draw the shoe from its last anchor, but a claim about the saved
///     profile does not outlive the foot being in view (the V4.6 rule,
///     unchanged).
///  4. **The threshold is strictly greater than 8 mm** ([kStaleSavedFootMm],
///     the roadmap's number): exactly 8 mm is a foot measured twice on
///     different days, not a stale profile. It is a workshop number — V4.9's
///     device session is where it gets tuned.
///  5. **Implausible numbers are refused, not compared.** A 40 mm "foot" and a
///     400 mm one are bad readings; the engine's own plausible band
///     ([kPlausibleFootLengthMm]–[kPlausibleFootLengthMaxMm]) is reused so
///     "plausible" means one thing in this codebase.
///
/// **Known and accepted at this phase:** the tracker cannot tell which foot it
/// is looking at, so a live left foot is compared against the saved sizing
/// foot's length (the larger one). Typical left/right asymmetry and the v2
/// sock compensation are both well inside the 8 mm band; a real-world pair
/// that straddles it would produce a suggestion to rescan, which is the safe
/// direction. V4.9 measures whether it happens in practice.
library;

import 'fit_engine.dart';
import 'try_on_fit.dart';

/// How far the live foot may differ from the saved scan before the screen
/// suggests a rescan. The roadmap's number (V4.7), applied strictly: exactly
/// 8 mm is not stale.
const double kStaleSavedFootMm = 8.0;

/// One "your saved size may be stale" suggestion, ready to render.
///
/// Deliberately a value object with no size in it: the notice is advice about
/// the saved profile, and the one thing it must never be able to do is change
/// the size the customer selected.
class TryOnSavedSizeNotice {
  /// The live (eased) heel→toe length the tracker published, in mm.
  final double liveLengthMm;

  /// The saved scan's own length, in mm — `FootMeasurement.maxFootLength`.
  final double savedLengthMm;

  const TryOnSavedSizeNotice({
    required this.liveLengthMm,
    required this.savedLengthMm,
  });

  /// Signed difference (live − saved), in mm: positive means the foot in view
  /// is the longer one.
  double get differenceMm => liveLengthMm - savedLengthMm;

  /// Whether the live foot is longer than the saved one.
  bool get isLiveLonger => differenceMm > 0;

  @override
  String toString() => 'TryOnSavedSizeNotice(live: $liveLengthMm mm, '
      'saved: $savedLengthMm mm)';
}

/// Decide whether the screen may suggest a rescan, or stay silent.
///
/// Returns null for every cannot-say case — unlocked tracker, no reading yet,
/// a broken or implausible number on either side, or a difference inside the
/// 8 mm band — and a [TryOnSavedSizeNotice] only when the two measurements
/// genuinely disagree.
TryOnSavedSizeNotice? tryOnSavedSizeNoticeFor({
  required TryOnLiveFoot live,
  required double? savedLengthMm,
}) {
  // The lock first, like every other surface that speaks over the camera.
  if (!live.locked) return null;

  final liveMm = live.lengthMm;
  final savedMm = savedLengthMm;
  if (liveMm == null || savedMm == null) return null;
  if (!_plausibleFootLength(liveMm) || !_plausibleFootLength(savedMm)) {
    return null;
  }

  final notice = TryOnSavedSizeNotice(
    liveLengthMm: liveMm,
    savedLengthMm: savedMm,
  );
  return notice.differenceMm.abs() > kStaleSavedFootMm ? notice : null;
}

/// The engine's own band: a length outside it is a bad reading, not a foot —
/// and comparing two bad readings is how a screen invents a suggestion.
bool _plausibleFootLength(double mm) {
  if (mm.isNaN || mm.isInfinite) return false;
  return mm >= kPlausibleFootLengthMm && mm <= kPlausibleFootLengthMaxMm;
}
