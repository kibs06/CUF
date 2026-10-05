/// Non-UI brain of the V3 try-on session
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.6, design
/// `VIRTUAL_FITTING_ARCHITECTURE.md` §2.3).
///
/// Cloned structurally from `ScanSessionController` — injected channel, typed
/// phases, one-shot events, `_disposed` guards on every async path — because
/// that skeleton is the one that survived a shipped AR flow. What it does
/// **not** clone is everything V4 added: **the detection loop is here as of
/// 2026-10-04** (frames → ML Kit → temporal gate → `setFootPose` at ≥5 Hz, plus
/// the native `footLock` state), while lock hysteresis stays in the native
/// tracker (V4.2) — and **the live fit verdict is built as of V4.6**: Dart grades
/// the tracker's own measured length (`footMeasure` → [TryOnLiveFoot] →
/// `lib/utils/try_on_fit.dart`) rather than the saved scan. The architecture's
/// retry/backoff stays deliberately absent: this loop *stops* after
/// [kFootTrackFailureLimit] consecutive failures instead of retrying forever,
/// and the session's lifecycle is still the controller's.
///
/// **The sequence, and why it is two calls instead of one.** V0's findings
/// F17–F19 are not advice, they are constraints:
///
///   1. The native view must exist **before** the session starts, because
///      `startSession` is what answers the session and awaiting it first
///      deadlocks the plugin into its 15 s timeout on every device. So the
///      staging (`prepareModel`) and the start ([startAr]) are separate steps,
///      and [startAr] refuses to run unless its caller says the view is up.
///   2. A handover that arrives before the view exists is **legal**: the native
///      plugin parks `setModel` and applies it on view creation. So the model is
///      handed over the moment it is verified, not deferred until "the view is
///      ready" — the V0 plugin discarded a parked model and that was the bug.
///   3. **The flag gates side effects, not just rendering.** With
///      [enabled] false this class reads nothing, downloads nothing and makes
///      **zero channel calls**, so a build that did not ask for try-on is
///      completely inert.
///
/// **Degrade, never dead-end (D8).** Every failure path ends in
/// [TryOnMode.simulated] with a [TryOnDegradeReason] — and, because
/// [TryOnDegradedEvent] is emitted on each, "silent to the customer" still means
/// "explained to the log".
///
/// **No `stopSession` from Dart.** Native teardown is single-owned by the
/// platform view's disposal (the D1 rule the scan controller follows after a
/// double-stop caused a session-restart storm). `dispose` cancels subscriptions
/// and stops listening; it does not reach into the native session.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/ar_try_on_channel.dart';
import '../../services/shoe_model_service.dart';
import '../../utils/foot_detector.dart';
import '../../utils/foot_pose.dart';
import '../../utils/mlkit_segmentation_foot_detector.dart';
import '../../utils/shoe_model_resolver.dart';
import '../../utils/try_on_coach.dart';
import '../../utils/try_on_fit.dart';
import 'try_on_mode.dart';
import 'try_on_phase.dart';

/// §2.11's detector cadence: one observation every 200 ms (5 Hz).
///
/// The same number the scan samples at, so the try-on cannot be the reason a
/// phone's battery or thermals behave differently from the flow already in
/// customers' hands.
const Duration kFootTrackInterval = Duration(milliseconds: 200);

/// How many consecutive loop failures stop the loop.
///
/// Today's answer on a build without the native half is a
/// `MissingPluginException` per tick, and five exceptions a second for the
/// length of a session is worse than five and then silence: one second of
/// failures is enough to say *what* is missing in a log, and stopping keeps the
/// loop from being the noisiest thing on the screen. V4.2 removes the failure
/// mode, not the guard.
const int kFootTrackFailureLimit = 5;

class TryOnSessionController extends ChangeNotifier {
  TryOnSessionController({
    required this.productId,
    this.variantId,
    required this.enabled,
    this.footTrackEnabled = false,
    this.diagnostics = false,
    ArTryOnChannel? channel,
    ShoeModelService? models,
    FootDetector? footDetector,
  })  : _channel = channel ?? ArTryOnChannel(),
        _models = models ?? ShoeModelService(),
        _injectedDetector = footDetector;

  /// The product whose model is being rendered.
  final String productId;

  /// The selected variant, when the page has one. The resolver decides whether
  /// it wins over the product-level default (§2.7.2).
  final String? variantId;

  /// The V3 switch. Taken as an argument rather than read from
  /// `AppConstants`, so a test drives both configurations in one run — the same
  /// shape as `TryOnPrefetch(enabled:)`.
  final bool enabled;

  /// The V4 loop switch ([AppConstants.tryOnFootTrackEnabled]), separate from
  /// [enabled] for the reason that constant records: rendering and
  /// frame-spending are different permissions. Defaults to `false`, so every
  /// existing caller — including tests written before this parameter existed —
  /// keeps exact V3 behaviour.
  final bool footTrackEnabled;

  /// **V4.9's readout switch** (`AppConstants.shoePreviewDiagnosticsEnabled`):
  /// when true, `startAr` asks the native view for its one-line heartbeat
  /// ([nativeStatusLine]) before it asks for the session itself.
  ///
  /// A parameter of the build for the same reason [footTrackEnabled] is: a
  /// `bool.fromEnvironment` cannot be flipped under `flutter test`, so the
  /// screen passes the constant and a test drives both configurations. Default
  /// `false`, so every caller written before it keeps exact V4.8 behaviour —
  /// and in particular **no channel traffic**: a build that did not ask for the
  /// readout never makes the call, the same rule the V3 switch follows.
  final bool diagnostics;

  final ArTryOnChannel _channel;
  final ShoeModelService _models;

  bool _disposed = false;
  bool _prepareStarted = false;
  bool _arStarted = false;

  TryOnPhase _phase = TryOnPhase.idle;
  TryOnMode _mode = TryOnMode.simulated;
  TryOnDegradeReason _degradeReason = TryOnDegradeReason.none;

  String? _failureReason;
  String? _failureMessage;

  ShoeModelSpec? _spec;
  String? _modelPath;

  int? _modelLoadMs;
  int? _triangles;
  TryOnPerf? _lastPerf;

  // ── V4 foot tracking (the loop runs only when footTrackEnabled) ──────

  /// The detector this controller did **not** build itself, when a test or a
  /// future caller supplies one. The loop constructs the ML Kit detector
  /// lazily otherwise, so a build with the flag off never brings the runtime up
  /// at all (F19's rule, extended to V4's half).
  final FootDetector? _injectedDetector;
  FootDetector? _detector;
  Timer? _footTimer;
  bool _footTickInProgress = false;
  int _footPoseCount = 0;
  int _footTickFailures = 0;

  /// **V4.8: true while the loop is stopped because the app left the
  /// foreground** — the one stopped-state [setAppForeground] undoes. Kept
  /// distinct from every other reason the loop stops, because a resume must
  /// restart a background pause and must **not** restart a failure stop, a
  /// degraded session, or a disposed controller.
  bool _footPausedForLifecycle = false;

  /// **V4.9: the native renderer's own heartbeat**, null until the first
  /// `status` event arrives. The angle bracket-free contract is the preview's:
  /// the value is assigned only when it changes, and it rides a
  /// [ValueNotifier] rather than the controller's own notifications because it
  /// changes once a second on a beat nothing else in the session cares about.
  final ValueNotifier<String?> nativeStatusLine =
      ValueNotifier<String?>(null);

  /// The same temporal gate the scan uses, at the same defaults: "a foot" must
  /// mean one thing in this app.
  final TemporalFootGate _footGate = TemporalFootGate();

  bool _footLocked = false;
  double _footQuality = 0;
  String? _footSide;

  /// **V4.5's coaching inputs**, captured on the same tick that published the
  /// pose: whether a foot was seen at all, and how it sits in the frame.
  bool _footSeen = false;
  TryOnFootFraming _footFraming = TryOnFootFraming.unknown;

  /// Ticks elapsed without a lock — **a counted duration, not a wall clock.**
  /// The loop's own cadence is the clock (exact under `fakeAsync`, where
  /// `DateTime.now()` is not), and it stops when the loop stops, which is what
  /// "15 s of trying" means. Reset by a lock.
  int _footSearchTicks = 0;

  /// True once the customer accepted the manual-placement offer. Cleared by
  /// the next lock, so a later loss can offer again.
  bool _manualOfferDismissed = false;

  StreamSubscription<ArTryOnEvent>? _eventSubscription;
  final StreamController<TryOnSessionEvent> _events =
      StreamController<TryOnSessionEvent>.broadcast();

  // ═════════════════════════════════════════════════════════════════
  // READ-ONLY RENDER STATE
  // ═════════════════════════════════════════════════════════════════

  /// What the AR session is doing. See the phase file's note: this is *not* the
  /// same question as [mode].
  TryOnPhase get phase => _phase;

  /// What the surface should render.
  TryOnMode get mode => _mode;

  /// Why [mode] is [TryOnMode.simulated], or [TryOnDegradeReason.none] when it
  /// is not.
  TryOnDegradeReason get degradeReason => _degradeReason;

  /// Native vocabulary for a failure — `unsupported_device`, `timeout`,
  /// `renderer_init_failed`, … Kept for the log and V5's `error_reason` column.
  String? get failureReason => _failureReason;

  /// Native detail to go with [failureReason]. Never shown as-is.
  String? get failureMessage => _failureMessage;

  /// The resolved row behind the model, when there is one.
  ShoeModelSpec? get spec => _spec;

  /// Absolute path of the verified local `.glb`, when it is on disk.
  String? get modelPath => _modelPath;

  /// The native side's own parse time, once it has loaded the mesh (V3.3) —
  /// V5's `model_loaded.load_ms`.
  int? get modelLoadMs => _modelLoadMs;

  /// Triangles the renderer actually loaded.
  int? get triangles => _triangles;

  /// Most recent frame-rate sample.
  TryOnPerf? get lastPerf => _lastPerf;

  /// True while the V4 detection loop is ticking. False with the flag off, and
  /// false again after [kFootTrackFailureLimit] stops it.
  bool get footTrackingActive => _footTimer != null;

  /// Pose frames successfully published — V5's counter, and the loop tests'
  /// observable.
  int get footPoseCount => _footPoseCount;

  /// The native tracker's current lock state (last `footLock` event).
  bool get footLocked => _footLocked;

  /// Post-smoothing quality from the same event.
  double get footQuality => _footQuality;

  /// Which foot the tracker locked, when it said.
  String? get footSide => _footSide;

  /// **V4.5's card state** — which sentence the coach card should render, or
  /// null when no card belongs on screen (the switch off, or a phase that is
  /// not a live AR session). `lib/utils/try_on_coach.dart` owns the rules;
  /// `lib/widgets/try_on/try_on_coach_card.dart` owns the English.
  ///
  /// A [ValueNotifier] rather than plain state a screen rebuilds from: the cue
  /// changes on *ticks*, while the controller notifies listeners on poses and
  /// events — a screen listening to those would rebuild five times a second to
  /// redraw a sentence that changes a handful of times per session. The value
  /// is assigned only when it actually changes, so subscribers wake on exactly
  /// those beats.
  final ValueNotifier<TryOnCoachCue?> coachCue =
      ValueNotifier<TryOnCoachCue?>(null);

  /// **V4.6: the live reading behind the fit verdict.**
  ///
  /// The tracker's eased heel→toe length and smoothed quality, updated from the
  /// native `footMeasure` stream (~2 Hz) and from each `footLock` edge, cleared
  /// when the loop stops. A notifier for the same reason [coachCue] is one: the
  /// screen listens to this directly, so a number that changes twice a second
  /// wakes exactly the card that draws it instead of the whole tree.
  final ValueNotifier<TryOnLiveFoot> liveFoot =
      ValueNotifier<TryOnLiveFoot>(const TryOnLiveFoot());

  /// **V4.5: the customer accepted the manual-placement offer.** The card stops
  /// offering and says where to tap instead; the tap itself is V3.4's native
  /// path, so nothing else moves here.
  void dismissManualOffer() {
    if (_disposed) return;
    _manualOfferDismissed = true;
    _refreshCoachCue();
  }

  /// **V4.8: the app's lifecycle, applied to the loop's frame spending.**
  ///
  /// Called by the screen's `WidgetsBindingObserver` on every lifecycle change.
  /// With [foreground] false — backgrounded, or merely inactive — the detection
  /// loop is paused, so a screen nobody is looking at asks for no camera frame,
  /// runs no ML Kit detection and publishes no pose. With it true the loop
  /// restarts **only if this method is what paused it**: a loop stopped by
  /// [kFootTrackFailureLimit] consecutive failures, a session that degraded
  /// while backgrounded, and a controller already disposed all stay stopped,
  /// because none of those is a backgrounded app.
  ///
  /// **A pause is not a stop.** It leaves [liveFoot] alone (the session is not
  /// over; the next `footMeasure` refreshes the reading) and it moves no phase.
  /// The native side owns its own half of the same event — the platform view
  /// pauses and resumes its ARCore session with its surface — so this method
  /// never reaches for the channel.
  void setAppForeground({required bool foreground}) {
    if (_disposed) return;
    if (!footTrackEnabled) return;

    if (!foreground) {
      if (_footTimer == null) return;
      _footTimer?.cancel();
      _footTimer = null;
      _footPausedForLifecycle = true;
      return;
    }

    if (!_footPausedForLifecycle) return;
    _footPausedForLifecycle = false;
    // A resume only ever restarts the loop this class paused; a session that
    // degraded while backgrounded stays on the fallback screen.
    if (_mode != TryOnMode.real) return;
    _startFootTracking();
  }

  /// True once the model is staged and AR has not been asked to start — the
  /// exact precondition [startAr] needs its caller to satisfy.
  bool get needsArStart => _phase == TryOnPhase.modelReady;

  Stream<TryOnSessionEvent> get events => _events.stream;

  // ═════════════════════════════════════════════════════════════════
  // 1. STAGE THE MODEL
  // ═════════════════════════════════════════════════════════════════

  /// Resolve the model, verify it locally, and hand it to the native side.
  ///
  /// Safe to call before the platform view exists (F18) and safe to call once:
  /// a second call is a no-op, because retrying is the customer re-entering the
  /// screen with a new controller, not a page rebuilding.
  Future<void> prepareModel() async {
    if (_disposed) return;
    if (!enabled) {
      _degrade(TryOnDegradeReason.featureOff);
      return;
    }
    if (_prepareStarted) return;
    _prepareStarted = true;

    _phase = TryOnPhase.loadingModel;
    notifyListeners();

    final startedAt = DateTime.now();

    final ShoeModelSpec? spec;
    try {
      spec = await _models.resolveForProduct(productId, variantId: variantId);
    } catch (e) {
      // A missing table, a dropped connection, an RLS refusal. The customer
      // gets the simulated screen; the log gets the exception.
      _fail(
        phase: TryOnPhase.error,
        reason: 'resolve_failed',
        message: e.toString(),
        degrade: TryOnDegradeReason.modelUnavailable,
      );
      return;
    }
    if (_disposed) return;

    if (spec == null) {
      // Nothing to render — and nothing went wrong. `idle` rather than `error`
      // is the distinction that keeps this out of the error dashboards.
      _phase = TryOnPhase.idle;
      _degrade(TryOnDegradeReason.modelMissing);
      return;
    }
    _spec = spec;

    final ShoeModelFile file;
    try {
      file = await _models.ensureLocal(spec);
    } catch (e) {
      // An integrity mismatch, a storage 404, an unwritable cache. Serving an
      // unverified model is worse than serving none — that is why the read
      // service throws, and why the throw is caught here.
      _fail(
        phase: TryOnPhase.error,
        reason: 'model_unavailable',
        message: e.toString(),
        degrade: TryOnDegradeReason.modelUnavailable,
      );
      return;
    }
    if (_disposed) return;

    _modelPath = file.path;

    // F18: hand it over now. If the view is not up yet the native side parks it;
    // a failure here is not fatal, because `startAr` is the authority on whether
    // anything can render at all (a build with no native plugin throws
    // MissingPluginException from both calls, and the video-less verdict belongs
    // to the session start).
    try {
      // The shared factory, so the payload the AR session sends and the one the
      // product page's inline 3D box sends cannot drift apart — they feed the
      // same renderer.
      await _channel.setModel(TryOnModelSpec.fromModel(spec, path: file.path));
    } catch (e) {
      debugPrint('[TryOn] setModel handover failed: $e');
    }
    if (_disposed) return;

    _phase = TryOnPhase.modelReady;
    notifyListeners();
    _events.add(TryOnModelReadyEvent(
      path: file.path,
      fromCache: file.fromCache,
      stageMs: DateTime.now().difference(startedAt).inMilliseconds,
    ));
  }

  // ═════════════════════════════════════════════════════════════════
  // 2. START AR — ONLY ONCE THE VIEW EXISTS
  // ═════════════════════════════════════════════════════════════════

  /// Start the AR session, **after** the platform view that hosts it is
  /// mounted.
  ///
  /// [arViewReady] is not a formality: F17 says awaiting `startSession` before
  /// the native view exists deadlocks into the 15 s timeout on every device, and
  /// Dart cannot verify the native view's existence by itself. So the caller
  /// states it, and a `false` here is refused outright — an inert simulated
  /// screen with [TryOnDegradeReason.arViewNotReady] instead of a 15-second
  /// stall the customer cannot explain.
  Future<void> startAr({required bool arViewReady}) async {
    if (_disposed) return;
    if (!enabled) {
      _degrade(TryOnDegradeReason.featureOff);
      return;
    }
    if (_arStarted) return;
    // Nothing staged → nothing to render. Also covers the no-model and
    // model-failed paths, which must not start a camera the customer cannot use.
    if (_phase != TryOnPhase.modelReady) {
      // **Not a failure, and not a silent drop either (V4.9).** This is the
      // *usual* shape of the first call on a device: the view is created a frame
      // or two after the screen builds, while the handover is still resolving,
      // downloading and verifying — so the screen's retry (the `needsArStart`
      // seam) is what calls back in once the phase lands. When this line was
      // added nothing retried, and a 48-minute black-camera mount left no trace
      // of the drop to read (QA, 2026-10-05).
      debugPrint(
        '[TryOn] startAr dropped: phase=$_phase — the model is not staged yet; '
        'the screen retries when it is',
      );
      return;
    }

    if (!arViewReady) {
      _arStarted = true;
      _degrade(TryOnDegradeReason.arViewNotReady);
      return;
    }

    _arStarted = true;
    _phase = TryOnPhase.arStarting;
    notifyListeners();

    _eventSubscription ??= _channel.events.listen(_onNativeEvent);

    if (diagnostics) {
      // V4.9: the Dart define cannot cross the channel by itself, and the
      // native side cannot read it — this call *is* the switch's other half.
      // Asked for before `startSession` so the readout is already on for a
      // session that then fails to start. Non-fatal on purpose: a build whose
      // native side predates this call loses the line, not the session.
      try {
        await _channel.setDiagnostics(true);
      } catch (e) {
        debugPrint('[TryOn] diagnostics request failed: $e');
      }
    }

    final TryOnStartResult result;
    try {
      result = await _channel.startSession();
    } catch (e) {
      // MissingPluginException today, on every build without the native plugin.
      _fail(
        phase: TryOnPhase.arFailed,
        reason: 'error',
        message: e.toString(),
        degrade: TryOnDegradeReason.arFailed,
      );
      return;
    }
    if (_disposed) return;

    _failureReason = result.started ? null : (result.reason ?? 'error');
    _failureMessage = result.started ? null : result.message;

    // The gate answers the mode; the reason mapping answers the *why* at the
    // granularity a customer-facing sentence needs.
    if (resolveTryOnDecision(
      arSupported: result.started,
      modelAvailable: _modelPath != null,
    ).isReal) {
      _mode = TryOnMode.real;
      _degradeReason = TryOnDegradeReason.none;
      _lastDegradeKey = null;
      _phase = TryOnPhase.searching;
      _startFootTracking();
      notifyListeners();
      return;
    }

    _phase = TryOnPhase.arFailed;
    _degrade(
      tryOnDegradeReasonForArFailure(result.reason),
      message: result.message,
    );
  }

  /// **V4.9: the night-aid torch** — the AR screen's flash toggle, forwarded
  /// to the native view. Only a real session has a camera to flash; a build
  /// running the simulated feed keeps zero channel traffic (the controller's
  /// contract), so the call is skipped there. Fire-and-forget: the button has
  /// already flipped, and a failed request costs the user one more tap.
  Future<void> setTorch(bool enabled) async {
    if (_mode != TryOnMode.real) return;
    if (_disposed) return;
    try {
      await _channel.setTorch(enabled);
    } catch (e) {
      debugPrint('[TryOn] torch request failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // 3. FOOT TRACKING LOOP (V4)
  // ═════════════════════════════════════════════════════════════════

  /// Starts the ≥5 Hz detection loop — **only in a real session**, and only
  /// when the build asked for it.
  ///
  /// A Dart `Timer.periodic` rather than a native callback because D3 keeps
  /// detection in Dart: the detector is 43 KB of tuned, tested logic, and a
  /// second implementation in Kotlin would be two places to tune. 200 ms is
  /// §2.11's cadence, the same one the scan runs.
  ///
  /// **No retry/backoff yet.** The architecture places retry/backoff with this
  /// loop and what is built here is the *stop* half of it: consecutive failures
  /// end the loop with a logged reason instead of one exception per tick. A
  /// recovery policy (session restart, permission re-request) belongs with
  /// V4.8/V4.9, where a device can say which failure deserves one.
  void _startFootTracking() {
    if (!footTrackEnabled) return;
    if (_mode != TryOnMode.real) return;
    if (_footTimer != null) return;
    _footTimer =
        Timer.periodic(kFootTrackInterval, (_) => unawaited(_footTick()));
    _refreshCoachCue();
  }

  /// Stops the loop. Idempotent, and safe to call after [dispose].
  void _stopFootTracking() {
    _footTimer?.cancel();
    _footTimer = null;
    // V4.5: a stopped loop is the offer, not a silence — see `_refreshCoachCue`.
    _refreshCoachCue();
    // V4.6: a stopped loop has no live reading. Whatever number is in the
    // notifier now belongs to a session that ended, and a fit verdict must not
    // keep grading it (the same rule that clears the mask and the anchor).
    liveFoot.value = const TryOnLiveFoot();
  }

  /// Recomputes [coachCue] from the state above, and is called from exactly the
  /// places one of its inputs moves: a tick, a `footLock`, a start/stop, and the
  /// offer's dismissal. Cheap and pure; the notifier drops no-op assignments.
  void _refreshCoachCue() {
    if (_disposed) return;
    coachCue.value = coachCueFor(
      trackingEnabled: footTrackEnabled,
      trackingActive: footTrackingActive,
      phase: _phase,
      locked: _footLocked,
      footSeen: _footSeen,
      searchingFor: kFootTrackInterval * _footSearchTicks,
      framing: _footFraming,
      manualOfferDismissed: _manualOfferDismissed,
    );
  }

  /// One cadence tick: frame → detection → gate → pose.
  ///
  /// **Overlap-guarded.** `acquireCameraFrame` and `detect` are both async, and
  /// a 200 ms cadence on a phone whose detector occasionally takes longer must
  /// drop a tick rather than queue a second detection behind the first: the
  /// frames are 200 ms apart, and a backlog would publish poses describing a
  /// foot position the customer has already left.
  ///
  /// **Every failure is swallowed.** The camera is best-effort infrastructure
  /// for a screen whose subject is the shoe; a detection problem must cost
  /// poses, not the session.
  Future<void> _footTick() async {
    if (_disposed || !footTrackEnabled) return;
    if (_mode != TryOnMode.real) return;
    if (_footTickInProgress) return;
    _footTickInProgress = true;
    // V4.5: a tick is 200 ms of *trying*, whatever it returns — a session whose
    // frame source never answers must still reach the manual offer. Counted
    // only while no lock is held, so the offer measures time without a lock.
    if (!_footLocked) _footSearchTicks++;
    _refreshCoachCue();
    try {
      final frame = await _channel.acquireCameraFrame();
      if (_disposed) return;
      if (frame == null || frame.nv21Bytes.isEmpty) return;

      final detector =
          _detector ??= _injectedDetector ?? MlKitSegmentationFootDetector();
      final detection = await detector.detect(
        nv21Bytes: frame.nv21Bytes,
        width: frame.width,
        height: frame.height,
        rotationDegrees: frame.rotationDegrees,
      );
      if (_disposed) return;

      // The same consecutive-positive rule the scan applies before recording a
      // sample: one lucky frame is not a foot.
      final confirmed = _footGate.update(detection.footDetected);

      // V4.5: the frame that feeds the pose feeds the coach card — a confirmed
      // foot turns the card from "point at your foot" into framing advice, and
      // a run of unconfirmed frames turns it back.
      final pose = confirmed ? footPoseFromDetection(detection) : null;
      _footSeen = pose != null;
      _footFraming = pose == null
          ? TryOnFootFraming.unknown
          : footFramingFromDetection(detection);
      _refreshCoachCue();
      if (pose == null) return;

      await _channel.setFootPose(pose);
      if (_disposed) return;
      _footPoseCount++;
      _footTickFailures = 0;

      // V4.4: the same accepted frame carries its segmentation mask, and the
      // mask is what makes the foot read as *inside* the shoe (the native side
      // paints the camera's own pixels over it through a mask-shaped mesh).
      //
      // **Auxiliary on purpose — its own try/catch, and no failure counter.**
      // The pose just crossed; a mask that does not must cost the occlusion for
      // one frame, never the tracking loop (the counter below is the loop's,
      // and `kFootTrackFailureLimit` frames of a mask fault would stop a loop
      // that is otherwise working). Null is the pose detector's answer, and it
      // is not an error: no mask simply means no occlusion this frame.
      final mask = detection.mask;
      if (mask != null) {
        try {
          await _channel.setFootMask(
            bytes32x32: mask,
            confidence: detection.qualityScore,
          );
        } catch (e) {
          debugPrint(
            '[TryOn] foot mask send failed — no occlusion this frame: $e',
          );
        }
      }
    } catch (e) {
      _footTickFailures++;
      if (_footTickFailures == 1) {
        debugPrint('[TryOn] foot tracking tick failed: $e');
      }
      if (_footTickFailures >= kFootTrackFailureLimit) {
        debugPrint(
          '[TryOn] foot tracking stopped after $kFootTrackFailureLimit '
          'consecutive failures — the native frame source is V4.2: $e',
        );
        _stopFootTracking();
      }
    } finally {
      _footTickInProgress = false;
    }
  }

  /// Applies one native `footMeasure` to the live reading (V4.6).
  ///
  /// **A bad number is refused, not clamped into a verdict.** The native side
  /// only publishes finite, positive millimetres (the tracker rejects anything
  /// else as not-a-sample), so a zero or a NaN here means a malformed payload —
  /// and grading the fit engine on it would be exactly the "confident about a
  /// broken input" failure every surface in this feature refuses. Quality is
  /// clamped rather than refused: it is a confidence, not a measurement, and
  /// clamping one cannot change what is true.
  void _applyFootMeasure({required double lengthMm, required double quality}) {
    if (_disposed) return;
    if (_mode != TryOnMode.real) return;
    if (!lengthMm.isFinite || lengthMm <= 0) return;
    liveFoot.value = TryOnLiveFoot(
      lengthMm: lengthMm,
      quality: quality.isFinite ? quality.clamp(0.0, 1.0) : 0.0,
      locked: _footLocked,
    );
  }

  /// Applies a native `footLock` event to the phase machine.
  ///
  /// **The native tracker is the authority, and Dart does not second-guess it:**
  /// the event carries the post-smoothing quality, and comparing it against
  /// §2.9's enter/leave thresholds here would be a second hysteresis that can
  /// disagree with the first. What Dart adds is the *phase* — `locked` is what a
  /// screen celebrates, `lost` is where a lock goes when it drops.
  void _applyFootLock({
    required bool locked,
    required double quality,
    String? side,
  }) {
    if (_disposed) return;
    if (_mode != TryOnMode.real) {
      // A late event from a session that has already degraded: worth a log line,
      // but it must not move a phase the fallback screen is driving.
      debugPrint('[TryOn] footLock after the session left real mode: '
          'locked=$locked q=$quality');
      return;
    }

    _footLocked = locked;
    _footQuality = quality;
    _footSide = side;

    // V4.6: the live reading's lock half. Each edge updates the notifier, so the
    // verdict card appears and disappears with the tracker's own authority — it
    // never re-derives the hysteresis (the V4.1 rule, unchanged).
    liveFoot.value = TryOnLiveFoot(
      lengthMm: liveFoot.value.lengthMm,
      quality:
          quality.isFinite ? quality.clamp(0.0, 1.0) : liveFoot.value.quality,
      locked: locked,
    );

    if (locked) {
      _phase = TryOnPhase.locked;
      // V4.5: a lock resets the offer clock and clears an earlier acceptance,
      // so a later loss can offer manual placement again.
      _footSearchTicks = 0;
      _manualOfferDismissed = false;
    } else if (_phase == TryOnPhase.locked) {
      _phase = TryOnPhase.lost;
    }

    _refreshCoachCue();
    notifyListeners();
    _events.add(TryOnFootLockChangedEvent(
      locked: locked,
      quality: quality,
      side: side,
    ));
  }

  // ═════════════════════════════════════════════════════════════════
  // NATIVE EVENTS
  // ═════════════════════════════════════════════════════════════════

  void _onNativeEvent(ArTryOnEvent event) {
    if (_disposed) return;

    switch (event) {
      case TryOnModelLoadedEvent(:final loadMs, :final triangles):
        _modelLoadMs = loadMs;
        _triangles = triangles;
        notifyListeners();

      case TryOnPerfEvent(:final perf):
        _lastPerf = perf;
        notifyListeners();

      case TryOnFootLockEvent(:final locked, :final quality, :final side):
        _applyFootLock(locked: locked, quality: quality, side: side);

      case TryOnFootMeasureEvent(:final lengthMm, :final quality):
        _applyFootMeasure(lengthMm: lengthMm, quality: quality);

      case TryOnStatusEvent(:final line):
        // An empty line is a malformed payload's residue rather than a
        // heartbeat: drawing a blank strip over the camera is worse than
        // drawing nothing, and the previous line (if any) still describes the
        // session better than the empty one does.
        if (line.isNotEmpty) nativeStatusLine.value = line;

      case TryOnErrorEvent(:final reason, :final message):
        _failureReason = reason;
        _failureMessage = message;
        // A renderer that died mid-session is the same outcome as one that never
        // started: the placeholder. Outside a live session the event is recorded
        // and nothing moves.
        if (_phase == TryOnPhase.searching ||
            _phase == TryOnPhase.arStarting ||
            _phase == TryOnPhase.locked ||
            _phase == TryOnPhase.lost) {
          // A renderer that died mid-session takes the loop with it: frames
          // bought for a screen that is no longer rendering are exactly the
          // cost the flag exists to avoid.
          _stopFootTracking();
          _phase = TryOnPhase.arFailed;
          _degrade(TryOnDegradeReason.arFailed, message: message);
          // V4.5: after the phase moves, so the cue lands on null (arFailed)
          // rather than on the offer the stopped loop momentarily implied.
          _refreshCoachCue();
        } else {
          notifyListeners();
        }

      case TryOnScreenshotEvent():
      case ArTryOnUnknownEvent():
        // Screenshots normally return on the `captureScreenshot` call (V3.7);
        // an unknown event is a newer native build talking (V4's `footLock`),
        // which is logged rather than treated as an error.
        debugPrint('[TryOn] native event: ${event.runtimeType}');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // DEGRADATION
  // ═════════════════════════════════════════════════════════════════

  /// Records a failure a *step* hit, then degrades.
  void _fail({
    required TryOnPhase phase,
    required String reason,
    required String message,
    required TryOnDegradeReason degrade,
  }) {
    if (_disposed) return;
    _failureReason = reason;
    _failureMessage = message;
    _phase = phase;
    _degrade(degrade, message: message);
  }

  /// The last degradation announced — see [_degrade].
  String? _lastDegradeKey;

  /// Lands on the simulated screen with a stated reason, **once**.
  ///
  /// The de-duplication is not cosmetic: a session asked to both prepare and
  /// start with the switch off degrades twice, and without this a log would
  /// carry two identical "why this is the fallback" lines for one page view. A
  /// session that reached [TryOnMode.real] clears the key, so a genuine second
  /// failure after a successful start is still announced.
  void _degrade(TryOnDegradeReason reason, {String? message}) {
    if (_disposed) return;
    _mode = TryOnMode.simulated;
    _degradeReason = reason;

    final key = '${reason.name}|${message ?? ''}';
    if (_lastDegradeKey == key) return;
    _lastDegradeKey = key;

    notifyListeners();
    _events.add(TryOnDegradedEvent(reason: reason, message: message));
  }

  // ═════════════════════════════════════════════════════════════════
  // TEARDOWN
  // ═════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _disposed = true;
    _stopFootTracking();
    // The detector is a platform resource (ML Kit holds native handles), so it
    // is disposed even when it was injected: the controller owns the loop, and
    // an injected detector has no other owner to hand it back to.
    _detector?.dispose();
    _detector = null;
    // V4.5/V4.6: the two notifiers are the screen's subscriptions, disposed
    // under the same contract as the event stream below.
    coachCue.dispose();
    liveFoot.dispose();
    nativeStatusLine.dispose();
    _eventSubscription?.cancel();
    // D1: no Dart-initiated stopSession — the platform view owns native teardown.
    _channel.detach().ignore();
    _events.close();
    super.dispose();
  }
}
