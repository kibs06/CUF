/// **V4.5's coaching rules** — what the try-on screen says while a foot is being
/// found, chased or held.
///
/// Pure and deterministic on purpose: the card's copy, icons and tones live
/// with the widget (the same split [TryOnPhase] documents — the state machine
/// carries vocabulary, the screen carries English), and everything that decides
/// *which* sentence is right lives here, where a table test can pin it without a
/// camera, a detector or a device.
///
/// **Where the inputs come from.** All of them already exist by V4.4:
///
///  * `phase` / `locked` / `footQuality` — the phase machine, driven by the
///    native tracker's `footLock` events (V4.1). The architecture's own note on
///    that event says it "drives the coach card, not the render", and this is
///    the file that makes that true.
///  * `footSeen` / `framing` — the last accepted detection's own points
///    ([footFramingFromDetection]). No new channel traffic: the loop already
///    holds this frame's heel and toe when it publishes the pose.
///  * `searchingFor` — a **counted** duration (the loop's ticks × its cadence),
///    not a wall clock, so the 15 s offer is exact under `fakeAsync` and stops
///    when the loop stops. "15 s of trying" is the thing being measured.
///
/// **What it deliberately cannot say.** §2.12 groups "no floor plane" and "poor
/// light" into one coaching line, and this file keeps that grouping: the app has
/// no signal that separates them (both arrive as a foot that is never seen, and
/// the tracker's rejections are frames rather than errors), so one honest
/// sentence about the floor *and* the light beats two guesses. V4.9's device
/// session is where the thresholds below get retuned, and where a real signal
/// could ever justify splitting them.
library;

import 'dart:math' as math;

import '../providers/try_on/try_on_phase.dart';
import 'foot_detector.dart';

/// The sentence the card should be showing, or none.
enum TryOnCoachCue {
  /// Nothing seen yet, and it is too early to blame the scene.
  pointAtFoot,

  /// Nothing seen for a while: §2.12's combined floor + light line.
  improveScene,

  /// A foot is seen but reads small — the phone is too far away.
  moveCloser,

  /// A foot is seen and fills the frame — the phone is too close.
  moveBack,

  /// A foot is seen, framed sanely, and the tracker is about to lock.
  holdStill,

  /// The tracker holds a lock. The success beat.
  locked,

  /// A lock was lost and the customer is being walked back.
  regain,

  /// The offer: tracking has not locked (or has stopped) and the shoe can be
  /// placed by hand instead.
  manual,

  /// The offer was accepted — from here the card says where to tap.
  placeByTap,
}

/// How the detected foot sits in the frame, from its own heel→toe extent.
enum TryOnFootFraming {
  /// No usable heel/toe pair in this frame.
  unknown,

  /// The foot is small in frame: the phone is being held too far away.
  tooFar,

  /// The foot is framed sanely for measuring and locking.
  ok,

  /// The foot fills the frame: the phone is too close to see the floor around it.
  tooClose,
}

/// Heel→toe extent (normalized image space) below which the foot is "far".
///
/// Workshop numbers, like the fit engine's bands: the detector's normalized
/// space is the mask's own square, a foot held at the coached ~30 cm reads
/// roughly 0.45–0.75 across it, and V4.9 retunes these against real feet — the
/// card itself is what a device session watches while doing it.
const double kFootFramingTooFar = 0.30;

/// Heel→toe extent above which the foot is "too close".
const double kFootFramingTooClose = 0.92;

/// How long with no foot seen before the card stops saying "point at your foot"
/// and starts talking about the floor and the light.
const Duration kFootSceneHintAfter = Duration(seconds: 2);

/// How long without a lock before the card offers manual placement (§2.12's
/// "after 15 s offer manual placement").
const Duration kFootManualOfferAfter = Duration(seconds: 15);

/// The framing of a detection, from its heel→toe extent.
///
/// Total: no points, a degenerate pair or anything non-finite is
/// [TryOnFootFraming.unknown], which the cue rule treats as "no framing
/// opinion" rather than as a reason to speak.
TryOnFootFraming footFramingFromDetection(FootDetectionResult detection) {
  final heel = detection.heelPoint;
  final toe = detection.toePoint;
  if (heel == null || toe == null) return TryOnFootFraming.unknown;

  final dx = toe.x - heel.x;
  final dy = toe.y - heel.y;
  final span = math.sqrt(dx * dx + dy * dy);
  if (!span.isFinite || span <= 0) return TryOnFootFraming.unknown;
  if (span < kFootFramingTooFar) return TryOnFootFraming.tooFar;
  if (span > kFootFramingTooClose) return TryOnFootFraming.tooClose;
  return TryOnFootFraming.ok;
}

/// The cue the card should show, or null when no card belongs on screen.
///
/// **Null is the normal answer outside a live foot-tracking session** — the
/// switch off, or a phase that is not [TryOnPhase.searching], [TryOnPhase.locked]
/// or [TryOnPhase.lost]. The priority order below is the one a customer can act
/// on, top to bottom:
///
///  1. **A lock.** It outranks everything, including a manual offer that was
///     pending a moment earlier.
///  2. **The offer.** `!trackingActive` (the loop stopped after
///     [kFootTrackFailureLimit] failures) or [kFootManualOfferAfter] without a
///     lock. It outranks `regain` on purpose: "step back into view" has been
///     said for 15 s by then, and repeating it forever is how a customer ends up
///     stuck. Dismissed, it becomes [TryOnCoachCue.placeByTap] — the offer is
///     not re-made until the next lock, but the instruction stays.
///  3. **A loss** ([TryOnCoachCue.regain]).
///  4. **The framing**, when a foot is seen: far → [TryOnCoachCue.moveCloser],
///     close → [TryOnCoachCue.moveBack], otherwise [TryOnCoachCue.holdStill].
///     Framing outranks "hold still" because it is the more actionable of the
///     two: a customer holding perfectly still 1 m from the phone is still not
///     going to lock.
///  5. **Nothing seen**: [TryOnCoachCue.pointAtFoot] for
///     [kFootSceneHintAfter], then [TryOnCoachCue.improveScene].
TryOnCoachCue? coachCueFor({
  required bool trackingEnabled,
  required bool trackingActive,
  required TryOnPhase phase,
  required bool locked,
  required bool footSeen,
  required Duration searchingFor,
  required TryOnFootFraming framing,
  required bool manualOfferDismissed,
}) {
  if (!trackingEnabled) return null;
  if (phase != TryOnPhase.searching &&
      phase != TryOnPhase.locked &&
      phase != TryOnPhase.lost) {
    return null;
  }

  if (locked) return TryOnCoachCue.locked;

  if (!trackingActive || searchingFor >= kFootManualOfferAfter) {
    return manualOfferDismissed
        ? TryOnCoachCue.placeByTap
        : TryOnCoachCue.manual;
  }

  if (phase == TryOnPhase.lost) return TryOnCoachCue.regain;

  if (footSeen) {
    switch (framing) {
      case TryOnFootFraming.tooFar:
        return TryOnCoachCue.moveCloser;
      case TryOnFootFraming.tooClose:
        return TryOnCoachCue.moveBack;
      case TryOnFootFraming.ok:
      case TryOnFootFraming.unknown:
        return TryOnCoachCue.holdStill;
    }
  }

  return searchingFor >= kFootSceneHintAfter
      ? TryOnCoachCue.improveScene
      : TryOnCoachCue.pointAtFoot;
}
