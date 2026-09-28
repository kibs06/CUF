/// The **capability gate** for the real AR try-on surface
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.8; design
/// `VIRTUAL_FITTING_ARCHITECTURE.md` §2.3, "mode selection — the seam that keeps
/// the fallback alive").
///
/// Two facts decide what a customer sees when they tap "Try on":
///
///   1. **Can this device run it?** ARCore says so only by trying —
///      `TryOnStartResult` carries the answer, and its vocabulary is the one the
///      shipped scan already uses (`unsupported_device`, `needs_install`,
///      `user_opted_out`, `timeout`, `error`).
///   2. **Is there a model to render, already on disk?** The native side is
///      handed a local path and never does HTTP (architecture §2.8), so a row in
///      `product_models` is not the same question as "there is something to
///      render".
///
/// Either one failing means [TryOnMode.simulated] — today's placeholder feed —
/// and never a dead end. That is decision D8, and it is the whole reason this
/// gate is a value rather than a boolean: the simulated screen is a *success*
/// case, and the screen should be able to say *why* it is showing the fallback.
///
/// **Why this is a pure file with no Flutter and no Supabase import** (the
/// `fit_engine.dart` / `shoe_model_resolver.dart` / `shoe_model_upload.dart`
/// precedent): the decision is a table, a wrong branch here is invisible on a
/// device that happens to support AR, and every caller should be able to read
/// the rule without a harness.
///
/// **The switch is not read here.** `AppConstants.tryOnV3Enabled` is applied by
/// the caller ([tryOnModelAvailable] takes it as an argument), so this file
/// cannot be the reason a test sees one configuration and a build sees another.
library;

/// What the try-on surface renders.
enum TryOnMode {
  /// The real platform view: the camera feed with an actual `.glb` in it.
  real,

  /// Today's `ARViewPlaceholder` feed. Not a failure mode — it is what most of
  /// the catalogue and some of the devices get, and it must keep working
  /// (D8).
  simulated,
}

/// Why the gate answered [TryOnMode.simulated].
///
/// The screen owns every sentence built from these — the same rule as
/// `scan_phase.dart`: the controller and the gate say *what* happened, never how
/// to phrase it, so copy is editable in exactly one place and tests assert
/// reasons instead of English.
enum TryOnDegradeReason {
  /// No degradation: the gate answered [TryOnMode.real].
  none,

  /// The V3 switch is off. Nothing was read, downloaded or started.
  featureOff,

  /// The device cannot run ARCore (`unsupported_device` / `unsupported`).
  arUnsupported,

  /// Google Play Services for AR is missing (`needs_install`).
  arNeedsInstall,

  /// The user declined the ARCore install (`user_opted_out`).
  arOptedOut,

  /// The session failed for any other reason — `timeout`, a native `error`, or a
  /// start that threw across the channel (a build with no native plugin at all,
  /// which is every build until V3.1 lands).
  arFailed,

  /// **AR was never asked to start because the native view was not mounted
  /// yet.** This is V0 findings F17–F19, which bind this phase: awaiting
  /// `startSession` before the platform view exists deadlocks the plugin into
  /// its 15 s timeout *on every device*. The controller refuses to start
  /// instead, so the failure becomes an inert simulated screen rather than a
  /// 15-second stall the customer cannot explain.
  arViewNotReady,

  /// The product has no usable model (no rows, or rows the resolver dropped).
  modelMissing,

  /// A model exists but could not be made local — a download failure, an
  /// integrity mismatch, an unwritable cache.
  modelUnavailable,
}

/// The gate's answer: what to render, and (when it is the fallback) why.
class TryOnDecision {
  final TryOnMode mode;
  final TryOnDegradeReason reason;

  const TryOnDecision({required this.mode, required this.reason});

  /// The one answer that needs no explanation.
  static const TryOnDecision real = TryOnDecision(
    mode: TryOnMode.real,
    reason: TryOnDegradeReason.none,
  );

  bool get isReal => mode == TryOnMode.real;
  bool get isSimulated => mode == TryOnMode.simulated;

  @override
  bool operator ==(Object other) =>
      other is TryOnDecision && other.mode == mode && other.reason == reason;

  @override
  int get hashCode => Object.hash(mode, reason);

  @override
  String toString() => 'TryOnDecision(${mode.name}, ${reason.name})';
}

/// **The gate.** Real only when the device can render *and* there is something
/// to render.
///
/// When both inputs are false the answer is [TryOnDegradeReason.modelMissing]
/// rather than an AR reason, and that ordering is deliberate: a missing model is
/// a fact the catalogue can fix and a support answer ("this pair has no 3D model
/// yet"), while `arUnsupported` is a fact about the customer's phone that no
/// amount of work on our side changes. Reporting the fixable one first is the
/// more useful sentence of the two.
TryOnDecision resolveTryOnDecision({
  required bool arSupported,
  required bool modelAvailable,
}) {
  if (arSupported && modelAvailable) return TryOnDecision.real;
  return TryOnDecision(
    mode: TryOnMode.simulated,
    reason: modelAvailable
        ? TryOnDegradeReason.arFailed
        : TryOnDegradeReason.modelMissing,
  );
}

/// The same gate, as the bare mode.
///
/// This is architecture §2.3's published signature, kept as a one-line delegate
/// so the documented API exists without a second copy of the rule that could
/// drift from [resolveTryOnDecision]. Callers that need to explain the fallback
/// use the decision form.
TryOnMode resolveTryOnMode({
  required bool arSupported,
  required bool modelAvailable,
}) =>
    resolveTryOnDecision(arSupported: arSupported, modelAvailable: modelAvailable)
        .mode;

/// The **availability half**, as an entry point sees it before any AR session
/// exists.
///
/// The switch is ANDed in here rather than read from `AppConstants` so a test
/// can drive both configurations in one run — the same reason
/// `TryOnPrefetch(enabled:)` takes its flag as an argument.
bool tryOnModelAvailable({
  required bool enabled,
  required bool hasLocalModel,
}) =>
    enabled && hasLocalModel;

/// Maps the native `startSession` failure vocabulary onto this file's reasons.
///
/// Unknown and absent codes collapse to [TryOnDegradeReason.arFailed] rather
/// than throwing: a newer native build sending a code this Dart build has never
/// heard of must still land the customer on the simulated screen, which is the
/// forward-compatibility rule the V0 spike's channel parser set.
TryOnDegradeReason tryOnDegradeReasonForArFailure(String? code) {
  switch (code) {
    case 'unsupported_device':
    case 'unsupported':
      return TryOnDegradeReason.arUnsupported;
    case 'needs_install':
      return TryOnDegradeReason.arNeedsInstall;
    case 'user_opted_out':
      return TryOnDegradeReason.arOptedOut;
    default:
      return TryOnDegradeReason.arFailed;
  }
}
