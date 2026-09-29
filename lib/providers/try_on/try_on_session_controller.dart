/// Non-UI brain of the V3 try-on session
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.6, design
/// `VIRTUAL_FITTING_ARCHITECTURE.md` §2.3).
///
/// Cloned structurally from `ScanSessionController` — injected channel, typed
/// phases, one-shot events, `_disposed` guards on every async path — because
/// that skeleton is the one that survived a shipped AR flow. What it does
/// **not** clone is the detection loop: driving pose frames at ≥5 Hz, lock
/// hysteresis and the live fit verdict are V4, and the architecture's retry/
/// backoff belongs with that loop rather than with a floor-placed shoe.
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
import '../../utils/shoe_model_resolver.dart';
import 'try_on_mode.dart';
import 'try_on_phase.dart';

class TryOnSessionController extends ChangeNotifier {
  TryOnSessionController({
    required this.productId,
    this.variantId,
    required this.enabled,
    ArTryOnChannel? channel,
    ShoeModelService? models,
  })  : _channel = channel ?? ArTryOnChannel(),
        _models = models ?? ShoeModelService();

  /// The product whose model is being rendered.
  final String productId;

  /// The selected variant, when the page has one. The resolver decides whether
  /// it wins over the product-level default (§2.7.2).
  final String? variantId;

  /// The V3 switch. Taken as an argument rather than read from
  /// `AppConstants`, so a test drives both configurations in one run — the same
  /// shape as `TryOnPrefetch(enabled:)`.
  final bool enabled;

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
    if (_phase != TryOnPhase.modelReady) return;

    if (!arViewReady) {
      _arStarted = true;
      _degrade(TryOnDegradeReason.arViewNotReady);
      return;
    }

    _arStarted = true;
    _phase = TryOnPhase.arStarting;
    notifyListeners();

    _eventSubscription ??= _channel.events.listen(_onNativeEvent);

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
      notifyListeners();
      return;
    }

    _phase = TryOnPhase.arFailed;
    _degrade(
      tryOnDegradeReasonForArFailure(result.reason),
      message: result.message,
    );
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

      case TryOnErrorEvent(:final reason, :final message):
        _failureReason = reason;
        _failureMessage = message;
        // A renderer that died mid-session is the same outcome as one that never
        // started: the placeholder. Outside a live session the event is recorded
        // and nothing moves.
        if (_phase == TryOnPhase.searching ||
            _phase == TryOnPhase.arStarting) {
          _phase = TryOnPhase.arFailed;
          _degrade(TryOnDegradeReason.arFailed, message: message);
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
    _eventSubscription?.cancel();
    // D1: no Dart-initiated stopSession — the platform view owns native teardown.
    _channel.detach().ignore();
    _events.close();
    super.dispose();
  }
}
