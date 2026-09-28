/// Typed state machine for the V3 try-on session
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.6, design
/// `VIRTUAL_FITTING_ARCHITECTURE.md` §2.3).
///
/// The shape is deliberately the one `lib/providers/v2/scan_phase.dart` already
/// proved: a closed set of phases, one-shot events for the things a screen must
/// react to *once*, and no English anywhere — the screen maps a reason to
/// copy/icon/tone, so copy stays editable in one file and tests assert
/// structure instead of sentences.
///
/// **What a phase means, and what it is not.** The phase describes the **AR
/// session**; [TryOnMode] describes **what the surface renders**. They are
/// different questions, and conflating them is how a "no model" case ends up
/// looking like an error: a product with no model is [TryOnPhase.idle] (nothing
/// was asked of AR) with `TryOnDegradeReason.modelMissing`, not a failure.
///
/// Phase coverage in this phase of the project, stated plainly so nobody reads
/// the enum as more than it is:
///
///   * **Reachable in V3:** [idle], [loadingModel], [modelReady], [arStarting],
///     [arFailed], [searching], [error].
///   * **[locked], [lost], [capturing] belong to V4's foot tracking.** They are
///     declared here because the architecture fixes this set — V4 fills them in
///     rather than renaming the machine underneath the screen that already
///     renders it. V3's floor-place MVP has no foot lock, so it never reaches
///     them.
library;

import 'try_on_mode.dart';

/// High-level phase of the V3 try-on session. Exactly one is active at a time.
enum TryOnPhase {
  /// Nothing has been attempted, **or** there is nothing to attempt — no model
  /// for this product. Both are "nothing is happening", and neither is an error.
  idle,

  /// Resolving the product's model and making it local. Rendered as an
  /// indeterminate "getting the shoe ready" beat.
  loadingModel,

  /// The model is verified on disk and has been handed to the native side, and
  /// AR has not been started yet. The screen starts AR from here — see the
  /// F17–F19 guard on `TryOnSessionController.startAr`.
  modelReady,

  /// `startSession` is in flight. The native view must already exist
  /// (F17: the reverse order deadlocks into the 15 s timeout).
  arStarting,

  /// The AR session refused to start, or failed after starting. The reason is on
  /// the controller; the surface is the simulated screen.
  arFailed,

  /// The camera is live and the floor plane is being looked for — the state a
  /// floor-place MVP actually lives in.
  searching,

  /// **V4.** The foot is tracked and the shoe is anchored to it.
  locked,

  /// **V4.** A lock was lost; coaching is driving the customer back.
  lost,

  /// **V4.** A frame is being sampled for the live fit verdict.
  capturing,

  /// A step threw that was expected to work (a model that could not be resolved
  /// or verified). Kept distinct from [arFailed] because the two have different
  /// causes — one is storage, one is the renderer — and V5's telemetry splits
  /// them.
  error,
}

/// One-shot outcomes the try-on screen reacts to exactly once.
///
/// Persistent state lives in the controller's fields, and the screen rebuilds
/// from those. Only things a screen must *act* on — and therefore cannot
/// re-derive from a phase it may observe several times — are events.
sealed class TryOnSessionEvent {
  const TryOnSessionEvent();
}

/// A verified model is local and has been handed to the native side.
///
/// This is the one event the screen must act on once: the handover is the seam
/// `ShoeModelService` exists to fill (V2.5), and the native side parks it if its
/// view is not up yet (F18), so the screen is free to act the moment it arrives.
class TryOnModelReadyEvent extends TryOnSessionEvent {
  /// Absolute path of the verified `.glb`.
  final String path;

  /// True when the file was already cached — the proof the V2.6 prefetch did its
  /// job, and the number V5's `model_loaded` telemetry will want beside it.
  final bool fromCache;

  /// How long resolution + verification took, in milliseconds.
  final int stageMs;

  const TryOnModelReadyEvent({
    required this.path,
    required this.fromCache,
    required this.stageMs,
  });

  @override
  String toString() => 'TryOnModelReadyEvent($path, '
      '${fromCache ? 'cache' : 'download'}, ${stageMs}ms)';
}

/// The session fell back to the simulated screen, with the reason why.
class TryOnDegradedEvent extends TryOnSessionEvent {
  final TryOnDegradeReason reason;

  /// Native-supplied detail, kept for the log. Never shown as-is.
  final String? message;

  const TryOnDegradedEvent({required this.reason, this.message});

  @override
  String toString() => 'TryOnDegradedEvent(${reason.name}'
      '${message == null ? '' : ': $message'})';
}
