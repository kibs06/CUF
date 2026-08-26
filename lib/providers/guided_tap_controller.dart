import 'dart:async';

import 'package:flutter/material.dart';

// TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
import '../services/diag_logger.dart' show navDiag;

import '../screens/customer/foot_floor_detection_screen.dart' show FloorReference;
import '../services/ar_core_channel.dart';
import '../utils/foot_detector.dart';
import '../utils/foot_measurement_utils.dart';
import '../utils/mlkit_segmentation_foot_detector.dart';

// ═══════════════════════════════════════════════════════════════
// ONE-SHOT OUTCOME EVENTS
// ═══════════════════════════════════════════════════════════════

/// One-shot outcomes the manual-measure SCREEN reacts to (navigation).
///
/// Controllers must not navigate themselves — the screen listens to this
/// stream and performs the UI action. Everything expressible as persistent
/// state (feedback toast, guidance text, invalid-tap coaching) is NOT an
/// event; it is [GuidedTapController] state the widget renders.
sealed class GuidedTapEvent {
  const GuidedTapEvent();
}

/// Both feet are done — screen navigates to `FootResultsScreen` with the
/// payload. Carries every argument `FootResultsScreen` receives, computed by
/// the same math that previously ran inline in `_navigateToResults`.
class MeasurementCompletedEvent extends GuidedTapEvent {
  final GuidedTapResultsPayload payload;
  const MeasurementCompletedEvent({required this.payload});
}

/// All values passed to `FootResultsScreen` after both feet complete.
class GuidedTapResultsPayload {
  final String footSide;
  final double footLengthMm;
  final double footWidthMm;
  final double? footLengthRightMm;
  final double? footWidthRightMm;
  final String? euSize;
  final String? usSize;
  final String? ukSize;
  final String paperSize;
  final String footCondition;
  final double paperConfidence;
  final double lightingQuality;
  final bool manualMode;

  // v2 fields
  final String measurementSource;
  final String shoeCategory;
  final String sizingFootSide;
  final String widthCategory;
  final double leftLengthComp;
  final double leftWidthComp;
  final double rightLengthComp;
  final double rightWidthComp;
  final String? sizeRecommendationReason;

  const GuidedTapResultsPayload({
    required this.footSide,
    required this.footLengthMm,
    required this.footWidthMm,
    required this.footLengthRightMm,
    required this.footWidthRightMm,
    required this.euSize,
    required this.usSize,
    required this.ukSize,
    required this.paperSize,
    required this.footCondition,
    required this.paperConfidence,
    required this.lightingQuality,
    required this.manualMode,
    required this.measurementSource,
    required this.shoeCategory,
    required this.sizingFootSide,
    required this.widthCategory,
    required this.leftLengthComp,
    required this.leftWidthComp,
    required this.rightLengthComp,
    required this.rightWidthComp,
    required this.sizeRecommendationReason,
  });
}

/// A manually placed measurement point: on-screen view pixel + real-world hit.
/// (Was the private `_ManualPoint` inside the screen.)
class PlacedPoint {
  final Offset screen;
  final ArWorldPoint world;

  const PlacedPoint({required this.screen, required this.world});
}

// ═══════════════════════════════════════════════════════════════
// CONTROLLER
// ═══════════════════════════════════════════════════════════════

/// Non-UI logic of the manual tap-to-measure AR flow
/// (`FootManualMeasureScreen`).
///
/// Owns: ARCore session/tracking state, tap→raycast point placement with
/// burst-sampling jitter smoothing, the A/B pair state machine
/// (place → adjust → confirm), drag-adjustment raycasts, the optional
/// smart-assist proposal sampler, per-foot measurement storage, and the
/// results computation.
///
/// Extracted verbatim from `foot_manual_measure_screen.dart` (Phase 1
/// refactor) — behavior-preserving move; every constant, guard order and
/// state transition is unchanged from the pre-extraction widget code.
/// Navigation, animations and all rendering stay in the screen, which listens
/// to this ChangeNotifier for rebuilds and to [events] for one-shot outcomes.
class GuidedTapController extends ChangeNotifier {
  // ── Plausibility bounds (cm) for the confirm guard ──
  // Tiered bounds exist in foot_measurement_utils.dart (hard-reject +
  // soft-warn) but the manual flow has only ever enforced the HARD tier
  // (feedback toast, no dialog) — preserved as-is. The same shared constants
  // also gate the screen-side live-readout formatting.
  static const double _minPlausibleLengthCm = kHardRejectMinLengthCm;
  static const double _maxPlausibleLengthCm = kHardRejectMaxLengthCm;
  static const double _minPlausibleWidthCm = kHardRejectMinWidthCm;
  static const double _maxPlausibleWidthCm = kHardRejectMaxWidthCm;

  /// Burst sampling: number of hitTest samples to fire per tap for jitter
  /// smoothing. ~200ms window at typical frame rate.
  static const int _burstSampleCount = 5;

  /// Maximum spread (mm) across a burst sample before showing a soft hint.
  static const double _burstSpreadHintMm = 4.0;

  final ArCoreChannel _arCore;
  final FootDetector Function() _detectorFactory;

  /// Config mirroring the screen's constructor args.
  final String footCondition;
  final String shoeCategory;

  /// Whether the optional smart-assist layer (§6) is enabled. When false, no
  /// background segmentation sampler runs and no suggestions are shown.
  final bool smartAssistEnabled;

  /// Optional floor reference captured upstream. Plumbing note: the manual
  /// flow accepts a [FloorReference] but does not currently read it — all
  /// tap math anchors on live per-tap hitTests. Scaffolding for a future
  /// drift-correction layer (unchanged from the pre-extraction screen).
  final FloorReference? floorReference;

  bool _disposed = false;

  // ── ARCore State ──
  ArTrackingState _trackingState = ArTrackingState.paused;

  /// Cached camera-frame geometry, needed to invert the preview's center-crop
  /// so a tap (view pixels) becomes normalized upright-frame coordinates for
  /// the native hitTest.
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _frameRotation = 0;

  // ── Manual Point Placement State ──
  PlacedPoint? _pointA;
  PlacedPoint? _pointB;

  /// Placement phase for the current pair: 0 = waiting for point A,
  /// 1 = waiting for point B, 2 = pair complete (drag to adjust).
  int _pairPhase = 0;

  /// Live A→crosshair / A→B distance (mm) shown on the line (§2.3 live
  /// measurement while placing point B; final distance once locked).
  double? _liveDistanceMm;
  Timer? _liveCenterTimer;

  /// Which placed point is being dragged: 0 = A, 1 = B.
  int? _dragIndex;

  /// Guards against overlapping drag raycasts (pan updates fire faster than
  /// the hitTest channel round-trip, so out-of-order results could jitter the
  /// dragged point).
  bool _dragHitInProgress = false;

  /// Guards against a rapid double-tap both completing their async hitTest and
  /// placing point B at almost the same spot as point A (the second tap sees
  /// phase already advanced to 1 and places B). The plausibility guard catches
  /// the ~0cm result at confirm, but this prevents the confusion outright.
  bool _placementInProgress = false;

  // ── Smart-Assist (§6 of MANUAL_MEASUREMENT_PIVOT_PROMPT) ──
  // The paused automatic detection is reused as an optional suggestion layer:
  // while the user waits to place the first point of a pair, a background
  // segmentation detector proposes the two initial positions (normalized →
  // view pixels via the shared center-crop transform). The user can accept
  // them — and drag-adjust with the exact same manual UI — or ignore them and
  // tap manually. Never blocks the manual flow.
  FootDetector? _assistDetector;
  Timer? _assistTimer;
  bool _assistBusy = false;

  /// Proposed point positions in view pixels (suggestion markers + accept),
  /// plus the detection's quality score (0.0–1.0) so the user can gauge how
  /// trustworthy the proposal is before accepting.
  ({Offset a, Offset b, double confidence})? _suggestion;

  /// Last known preview size (pushed by the screen's build) for the
  /// background sampler.
  Size? _viewSize;

  // ── Feedback toast (invalid-tap message, §3.3) ──
  String? _tapFeedback;
  Timer? _feedbackTimer;

  // ── Scan State ──
  int _currentFoot = 0; // 0 = left, 1 = right
  String _captureStep = 'front'; // 'front' (width) or 'side' (length)

  // Stored measurements per foot (mm).
  double? _leftWidthMm;
  double? _leftLengthMm;
  double? _rightWidthMm;
  double? _rightLengthMm;

  // ── Processing / Completion ──
  bool _isProcessing = false;
  String _processingStep = '';

  // ── UI State ──
  String _guidanceText = 'Initializing AR...';
  String _guidanceState =
      'initializing'; // 'initializing', 'searching', 'ready', 'error'

  StreamSubscription<ArSessionEvent>? _eventSubscription;

  /// Periodic (cheap) guidance refresh — re-derives coaching copy from the
  /// cached _trackingState without hit-testing or any area gate, so guidance
  /// converges even if the first ARCore state-change event races past our
  /// subscription at session start (broadcast streams drop un-listened
  /// events).
  Timer? _guidanceRefreshTimer;

  // ── Timing instrumentation (grep logcat for 'AR_TIMING') ──
  // Measures screen-open → first-successful-point so the real speed of the
  // removed floor-scan wait can be quantified on-device.
  final Stopwatch _timingWatch = Stopwatch()..start();
  bool _loggedFirstTracking = false;
  bool _loggedFirstPoint = false;
  int? _firstTrackingMs; // Cached for the first_point summary line below.

  void _logTiming(String milestone) {
    debugPrint('[AR_TIMING] $milestone +${_timingWatch.elapsedMilliseconds}ms');
  }

  /// One consolidated summary at the first accepted point: ARCore's own init
  /// speed (time to first TRACKING) vs. the user-visible wait to first point.
  void _logFirstPointSummary(String source) {
    final now = _timingWatch.elapsedMilliseconds;
    final trackingMs = _firstTrackingMs;
    if (trackingMs == null) {
      debugPrint('[AR_TIMING] first_point +${now}ms [$source] | tracking: n/a');
      return;
    }
    debugPrint('[AR_TIMING] first_point +${now}ms [$source] | tracking at +${trackingMs}ms | gap-after-tracking ${now - trackingMs}ms');
  }

  /// One-shot outcome events (navigation triggers). Broadcast so late
  /// listeners never receive stale events.
  final StreamController<GuidedTapEvent> _eventController =
      StreamController<GuidedTapEvent>.broadcast();

  Stream<GuidedTapEvent> get events => _eventController.stream;

  GuidedTapController({
    ArCoreChannel? arCore,
    FootDetector Function()? detectorFactory,
    this.footCondition = 'bare',
    this.shoeCategory = 'men',
    this.smartAssistEnabled = true,
    this.floorReference,
  })  : _arCore = arCore ?? ArCoreChannel.instance,
        _detectorFactory =
            detectorFactory ?? MlKitSegmentationFootDetector.new {
    // The screen's State used to log this first thing in initState; the
    // controller is constructed there, so the moment (and elapsed value) match.
    _logTiming('screen_opened');

    // Lightweight guidance refresh (1s, no hit-testing). _updateGuidance
    // guards its own notifications with change detection, so this is a no-op
    // once guidance has converged — it only exists to recover from a missed
    // initial tracking event. Taps are never gated on it.
    //
    // Armed in the constructor (not initialize()) because the original screen
    // started it in initState — BEFORE the camera-permission request — and
    // its ticks drive the pre-session guidance copy.
    _guidanceRefreshTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateGuidance());
  }

  // ── Read-only state for rendering ──
  ArTrackingState get trackingState => _trackingState;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  int get frameRotation => _frameRotation;

  /// Upright (rotation-corrected) frame dimensions for coordinate mapping —
  /// consumed by the screen's painters alongside [currentGuideRect].
  int get uprightWidth =>
      (_frameRotation % 180) == 90 ? _frameHeight : _frameWidth;
  int get uprightHeight =>
      (_frameRotation % 180) == 90 ? _frameWidth : _frameHeight;

  PlacedPoint? get pointA => _pointA;
  PlacedPoint? get pointB => _pointB;
  int get pairPhase => _pairPhase;
  double? get liveDistanceMm => _liveDistanceMm;
  int? get dragIndex => _dragIndex;
  ({Offset a, Offset b, double confidence})? get suggestion => _suggestion;
  String? get tapFeedback => _tapFeedback;
  int get currentFoot => _currentFoot;
  String get captureStep => _captureStep;
  Rect get currentGuideRect =>
      _captureStep == 'front' ? kFrontCaptureGuideRect : kSideCaptureGuideRect;
  String get guidanceText => _guidanceText;
  String get guidanceState => _guidanceState;
  bool get processing => _isProcessing;
  String get processingStep => _processingStep;

  // ═════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═════════════════════════════════════════════════════════════

  /// Camera permission was denied — surface today's exact error text/state.
  /// (The permission request itself stays in the screen.)
  void reportCameraPermissionDenied() {
    _guidanceText = 'Camera permission is required for AR measuring';
    _guidanceState = 'error';
    notifyListeners();
  }

  /// Start the ARCore session and begin listening for events. Resolves only
  /// after the terminal session-start outcome is known.
  Future<void> initialize() async {
    // Start ARCore session (world tracking + plane detection only — no
    // detection models needed in the manual flow). E3 fix: started == false
    // is now reachable — surface the specific reason.
    final start = await _arCore.startSession();
    _logTiming('session_started');
    if (_disposed) return;
    if (!start.started) {
      switch (start.reason) {
        case 'needs_install':
          _guidanceText =
              'Google Play is installing ARCore — please try again in a moment.';
          break;
        case 'unsupported_device':
        case 'user_opted_out':
        case 'unsupported':
          _guidanceText =
              "AR isn't supported on this device — use manual measurement instead.";
          break;
        case 'timeout':
          _guidanceText =
              'AR took too long to start — check your connection and try again.';
          break;
        default:
          _guidanceText = start.message ?? 'Failed to start AR session.';
      }
      _guidanceState = 'error';
      notifyListeners();
      return;
    }

    if (_disposed) return; // Torn down during init — don't register timers/events

    // Cache camera-frame geometry for tap→normalized coordinate mapping.
    _fetchFrameGeometry();

    // Listen for ARCore events
    _eventSubscription = _arCore.events.listen(_onSessionEvent);

    // Smart-assist background sampler (§6): throttled + self-gating. While
    // the user is waiting to place the first point, propose an initial pair
    // from the paused segmentation detector. The user can accept it and
    // drag-adjust, or ignore it and tap manually. Skipped entirely when the
    // user disabled smart-assist on the instructions screen.
    if (smartAssistEnabled) {
      _assistTimer = Timer.periodic(
        const Duration(milliseconds: 600),
        (_) => _sampleSmartAssist(),
      );
    }
  }

  void _onSessionEvent(ArSessionEvent event) {
    if (_disposed) return;

    switch (event.type) {
      case 'tracking':
        final state = event.data['state']?.toString() ?? 'paused';
        if (!_loggedFirstTracking && state == 'tracking') {
          _loggedFirstTracking = true;
          _firstTrackingMs = _timingWatch.elapsedMilliseconds;
          _logTiming('first_tracking');
        }
        _trackingState = state == 'tracking'
            ? ArTrackingState.tracking
            : state == 'limited'
                ? ArTrackingState.limited
                : ArTrackingState.paused;
        notifyListeners();
        _updateGuidance();
        break;

      case 'plane':
        // Informational only in manual mode — taps resolve per-hitTest, so
        // there is no plane-coverage gate to refresh (REMOVE_FLOOR_SCAN_WAIT).
        _updateGuidance();
        break;

      case 'error':
        final msg = event.data['message']?.toString() ?? 'Unknown error';
        _guidanceText = msg;
        _guidanceState = 'error';
        notifyListeners();
        break;
    }
  }

  /// Fetch the cached camera frame once so we know its upright dimensions and
  /// rotation — required to invert the preview's center-crop for taps.
  Future<void> _fetchFrameGeometry() async {
    for (int i = 0; i < 6; i++) {
      if (_disposed) return;
      final frame = await _arCore.acquireCameraFrame();
      if (frame != null && frame.width > 0 && frame.height > 0) {
        _frameWidth = frame.width;
        _frameHeight = frame.height;
        _frameRotation = frame.rotationDegrees;
        notifyListeners();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  // ═════════════════════════════════════════════════════════════
  // GUIDANCE
  // ═════════════════════════════════════════════════════════════

  /// Manual mode: guidance is driven purely by ARCore's TRACKING state — there
  /// is NO floor-area / guide-box gate (REMOVE_FLOOR_SCAN_WAIT). The tap UI is
  /// available as soon as the session is tracking, even with no plane mapped
  /// yet; a tap that misses a tracked surface is rejected per-tap with the
  /// §3.3 message, which naturally coaches the user instead of a blocking
  /// "scanning floor" wait.
  void _updateGuidance() {
    if (_disposed) return;
    if (_pairPhase > 0) return; // Don't clobber the placement prompt

    final ready = _trackingState == ArTrackingState.tracking;
    final limited = _trackingState == ArTrackingState.limited;
    final newState = ready ? 'ready' : (limited ? 'limited' : 'searching');
    final newText = ready
        ? _firstPointPrompt()
        : limited
            // §3 coaching: keep the user moving — parallax helps ARCore
            // triangulate features faster than holding perfectly still.
            ? 'Tracking is limited — move your phone slowly side to side'
            // §3 coaching: motion + texture expectation-setting instead of a
            // blocking wait; taps still work and are validated per-tap.
            : 'Move your phone slightly so the floor is tracked — then tap to place points. Plain tile or carpet may take a little longer.';

    // No-op when nothing changed — the 1s refresh timer calls this every
    // second, so skip setState churn once guidance has converged.
    if (newState == _guidanceState && newText == _guidanceText) return;

    _guidanceState = newState;
    if (!ready && _pairPhase == 0) _suggestion = null;
    _guidanceText = newText;
    notifyListeners();
  }

  /// Called by the screen's build so the background sampler knows the preview
  /// size. Plain caching input — no rebuild notification (the original cached
  /// it as a plain assignment inside build too).
  void updateViewSize(Size size) {
    _viewSize = size;
  }

  String _footLabel() => _currentFoot == 0 ? 'left' : 'right';

  String _firstPointPrompt() {
    if (_captureStep == 'front') {
      return 'Tap the widest point on the inside of your ${_footLabel()} foot';
    }
    return 'Tap your heel';
  }

  String _secondPointPrompt() {
    if (_captureStep == 'front') {
      return 'Now tap the widest point on the outside of your ${_footLabel()} foot';
    }
    return 'Now tap the tip of your longest toe';
  }

  // ═════════════════════════════════════════════════════════════
  // POINT PLACEMENT
  // ═════════════════════════════════════════════════════════════

  double _worldDistanceMm(ArWorldPoint a, ArWorldPoint b) =>
      a.distanceTo(b) * 1000;

  /// Handle a tap on the preview. Places point A (phase 0) or point B
  /// (phase 1); ignores taps that don't hit a tracked surface (§3.3).
  ///
  /// §2 improvement: fires burst sampling (multiple hitTests at the same
  /// coordinate, ~200ms window) and takes the median for jitter smoothing.
  Future<void> handleTapAt(Offset local, Size viewSize) async {
    if (_guidanceState == 'error' || _guidanceState == 'initializing') return;
    if (_pairPhase == 2) return; // Locked — drag or confirm/trash
    if (_placementInProgress) return; // No overlapping placements
    _placementInProgress = true;

    // §2 Tracking-quality gate: reject taps when ARCore isn't tracking.
    final trackingState = await _arCore.getTrackingState();
    if (_disposed) { _placementInProgress = false; return; }
    if (trackingState != ArTrackingState.tracking) {
      _placementInProgress = false;
      _showFeedback('Move phone slowly — tracking is limited');
      return;
    }

    final normalized = mapViewToNormalized(
      local,
      viewSize,
      frameWidth: uprightWidth,
      frameHeight: uprightHeight,
    );

    // §2 Burst sampling: fire multiple hitTests at the same coordinate
    // across a ~200ms window, then take the median world point.
    final worldPoints = <ArWorldPoint>[];
    for (int i = 0; i < _burstSampleCount; i++) {
      final hit = await _arCore.hitTest(x: normalized.dx, y: normalized.dy);
      if (hit != null) worldPoints.add(hit);
      // Small delay between samples (except after the last one)
      if (i < _burstSampleCount - 1) {
        await Future.delayed(const Duration(milliseconds: 40));
      }
    }
    if (_disposed) { _placementInProgress = false; return; }

    if (worldPoints.isEmpty) {
      _placementInProgress = false;
      _showFeedback(
          "Can't measure there — tap on the tracked floor near your foot");
      return;
    }

    // Take the median of the burst samples for jitter smoothing.
    final world = _medianWorldPoint(worldPoints);

    // §2 Burst spread check: if the spread exceeds _burstSpreadHintMm,
    // show a soft "hold steady" hint — never blocks the flow.
    if (worldPoints.length >= 3) {
      final spread = _burstSpreadMm(worldPoints);
      if (spread > _burstSpreadHintMm) {
        _showFeedback('Hold steady — detected some movement');
      }
    }

    // User chose manual placement — clear any smart-assist suggestion.
    _suggestion = null;
    if (_pairPhase == 0) {
      _pointA = PlacedPoint(screen: local, world: world);
      if (!_loggedFirstPoint) {
        _loggedFirstPoint = true;
        _logFirstPointSummary('manual tap');
      }
      _pairPhase = 1;
      _guidanceText = _secondPointPrompt();
      _guidanceState = 'ready';
      _startLiveCenterUpdates();
    } else {
      _pointB = PlacedPoint(screen: local, world: world);
      _pairPhase = 2;
      _liveCenterTimer?.cancel();
      _liveDistanceMm = _worldDistanceMm(_pointA!.world, world);
      _guidanceText = 'Drag the points to adjust, then confirm';
    }
    notifyListeners();
    _placementInProgress = false;
  }

  /// Compute the median world point from a list of burst samples.
  /// Averages each coordinate independently for robustness.
  ArWorldPoint _medianWorldPoint(List<ArWorldPoint> points) {
    if (points.length == 1) return points[0];
    final xs = points.map((p) => p.x).toList()..sort();
    final ys = points.map((p) => p.y).toList()..sort();
    final zs = points.map((p) => p.z).toList()..sort();
    final ds = points.map((p) => p.distanceFromCamera).toList()..sort();
    final mid = points.length ~/ 2;
    final medianX = points.length.isOdd ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2;
    final medianY = points.length.isOdd ? ys[mid] : (ys[mid - 1] + ys[mid]) / 2;
    final medianZ = points.length.isOdd ? zs[mid] : (zs[mid - 1] + zs[mid]) / 2;
    final medianD = points.length.isOdd ? ds[mid] : (ds[mid - 1] + ds[mid]) / 2;
    return ArWorldPoint(x: medianX, y: medianY, z: medianZ, distanceFromCamera: medianD);
  }

  /// Compute the max spread (mm) across burst samples.
  double _burstSpreadMm(List<ArWorldPoint> points) {
    if (points.length < 2) return 0;
    double maxDist = 0;
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        final d = points[i].distanceTo(points[j]) * 1000; // meters → mm
        if (d > maxDist) maxDist = d;
      }
    }
    return maxDist;
  }

  /// §2.3 live measurement: while placing point B, poll the ARCore hitTest at
  /// the screen center and draw a line from A to the crosshair with a live cm
  /// readout (reference-app "Add a point" pattern — the user aims with the
  /// phone, taps to commit).
  void _startLiveCenterUpdates() {
    _liveCenterTimer?.cancel();
    _liveCenterTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (_disposed || _pairPhase != 1) {
        _liveCenterTimer?.cancel();
        return;
      }
      final world = await _arCore.hitTest(x: 0.5, y: 0.5);
      if (_disposed) return;
      if (world != null && _pointA != null) {
        _liveDistanceMm = _worldDistanceMm(_pointA!.world, world);
        notifyListeners();
      }
    });
  }

  // ═════════════════════════════════════════════════════════════
  // SMART-ASSIST (§6 — optional auto-proposed initial points)
  // ═════════════════════════════════════════════════════════════

  /// Background sampler: periodically run the (paused) segmentation detector
  /// while the user waits to place the first point, and propose an initial
  /// pair for the CURRENT step. Self-gating (only when the area is tracked,
  /// guidance is ready, and no pair is in progress); non-blocking.
  Future<void> _sampleSmartAssist() async {
    // Double-gate: the timer isn't even started when disabled, but this keeps
    // the sampler inert even if a stray tick ever slipped through.
    if (!smartAssistEnabled) return;
    if (_assistBusy || _disposed) return;
    if (!_arCore.isSessionActive) return;
    if (_pairPhase != 0 || _guidanceState != 'ready') return;
    if (_trackingState != ArTrackingState.tracking) return;
    final viewSize = _viewSize;
    if (viewSize == null || viewSize.width <= 0 || viewSize.height <= 0) return;

    _assistBusy = true;
    try {
      // Lazy detector creation inside the try: if the native segmenter fails
      // to init, catch it below so the Timer.periodic callback can never
      // escape an unhandled async exception (repeated every 600ms).
      _assistDetector ??= _detectorFactory();
      final frame = await _arCore.acquireCameraFrame();
      if (_disposed || frame == null || frame.width <= 0 || frame.height <= 0) {
        return;
      }
      final result = await _assistDetector!.detect(
        nv21Bytes: frame.nv21Bytes,
        width: frame.width,
        height: frame.height,
        rotationDegrees: frame.rotationDegrees,
        preferSide: _footLabel(),
        guideRect: currentGuideRect,
      );
      if (_disposed || _pairPhase != 0 || _guidanceState != 'ready') return;

      final pair = proposePointPair(result, isFront: _captureStep == 'front');
      if (pair == null) {
        if (_suggestion != null) {
          _suggestion = null;
          notifyListeners();
        }
        return;
      }

      // Map the normalized (upright-frame) points into view pixels with the
      // shared center-crop transform, exactly like the guide-box painter.
      final aView = mapNormalizedToView(
        Offset(pair.a.x, pair.a.y),
        viewSize,
        frameWidth: uprightWidth,
        frameHeight: uprightHeight,
      );
      final bView = mapNormalizedToView(
        Offset(pair.b.x, pair.b.y),
        viewSize,
        frameWidth: uprightWidth,
        frameHeight: uprightHeight,
      );
      final bounds = Offset.zero & viewSize;
      if (!bounds.contains(aView) || !bounds.contains(bView)) return;

      _suggestion = (
        a: aView,
        b: bView,
        confidence: result.qualityScore,
      );
      notifyListeners();
    } catch (e) {
      // Never let a smart-assist failure affect the manual flow or crash the
      // timer zone — the suggestion is a convenience, not a requirement.
      debugPrint('[SmartAssist] sampler error: $e');
      if (!_disposed && _suggestion != null) {
        _suggestion = null;
        notifyListeners();
      }
    } finally {
      _assistBusy = false;
    }
  }

  /// Accept the smart-assist suggestion: raycast both proposed points to real
  /// world space and lock them in as the pair (same plausibility guard as a
  /// manual confirm, so a bad proposal can't silently produce a bad size).
  Future<void> acceptSuggestion() async {
    final suggestion = _suggestion;
    if (suggestion == null || _pairPhase != 0) return;
    if (_placementInProgress) return;
    final viewSize = _viewSize;
    if (viewSize == null) return;

    // No area/tracking pre-gate (REMOVE_FLOOR_SCAN_WAIT): if the proposed
    // points don't hit a tracked surface, the batch hitTest returns nulls
    // below and we show the §3.3 message — same per-tap validation as manual.
    _placementInProgress = true;
    try {
      final aNorm = mapViewToNormalized(
        suggestion.a,
        viewSize,
        frameWidth: uprightWidth,
        frameHeight: uprightHeight,
      );
      final bNorm = mapViewToNormalized(
        suggestion.b,
        viewSize,
        frameWidth: uprightWidth,
        frameHeight: uprightHeight,
      );
      // One batch call: a single channel round trip + a consistent snapshot
      // of the same frame (two sequential hitTests could straddle a tracking
      // change). hitTestBatch expects normalized coords, which we have.
      final hits = await _arCore.hitTestBatch(screenPoints: [aNorm, bNorm]);
      if (_disposed) return;
      final aWorld = hits.isNotEmpty ? hits[0] : null;
      final bWorld = hits.length > 1 ? hits[1] : null;
      if (aWorld == null || bWorld == null) {
        _showFeedback(
            "Suggested points didn't hit the floor — place them manually");
        if (_suggestion != null) {
          _suggestion = null;
          notifyListeners();
        }
        return;
      }

      final mm = _worldDistanceMm(aWorld, bWorld);
      final cm = mm / 10;
      final isFront = _captureStep == 'front';
      final minCm = isFront ? _minPlausibleWidthCm : _minPlausibleLengthCm;
      final maxCm = isFront ? _maxPlausibleWidthCm : _maxPlausibleLengthCm;
      if (cm < minCm || cm > maxCm) {
        _showFeedback('Suggested size looks off — place the points manually');
        if (_suggestion != null) {
          _suggestion = null;
          notifyListeners();
        }
        return;
      }

      _pointA = PlacedPoint(screen: suggestion.a, world: aWorld);
      if (!_loggedFirstPoint) {
        _loggedFirstPoint = true;
        _logFirstPointSummary('smart-assist');
      }
      _pointB = PlacedPoint(screen: suggestion.b, world: bWorld);
      _pairPhase = 2;
      _liveDistanceMm = mm;
      _guidanceText = 'Drag the points to adjust, then confirm';
      _suggestion = null;
      notifyListeners();
    } finally {
      _placementInProgress = false;
    }
  }

  // ═════════════════════════════════════════════════════════════
  // POINT DRAGGING (adjust after placement, §2.4)
  // ═════════════════════════════════════════════════════════════

  void onPanStart(Offset localPosition) {
    if (_pairPhase != 2) return;
    const hitRadius = 44.0;
    if (_pointA != null &&
        (_pointA!.screen - localPosition).distance < hitRadius) {
      _dragIndex = 0;
    } else if (_pointB != null &&
        (_pointB!.screen - localPosition).distance < hitRadius) {
      _dragIndex = 1;
    }
  }

  Future<void> onPanUpdate(Offset localPosition, Size viewSize) async {
    if (_dragIndex == null || _pairPhase != 2) return;
    if (_dragHitInProgress) return; // Drop overlapping drag raycasts
    _dragHitInProgress = true;

    final normalized = mapViewToNormalized(
      localPosition,
      viewSize,
      frameWidth: uprightWidth,
      frameHeight: uprightHeight,
    );
    final world = await _arCore.hitTest(x: normalized.dx, y: normalized.dy);
    _dragHitInProgress = false;
    if (_disposed || world == null) return;

    if (_dragIndex == 0) {
      _pointA = PlacedPoint(screen: localPosition, world: world);
    } else {
      _pointB = PlacedPoint(screen: localPosition, world: world);
    }
    if (_pointA != null && _pointB != null) {
      _liveDistanceMm = _worldDistanceMm(_pointA!.world, _pointB!.world);
    }
    notifyListeners();
  }

  void onPanEnd() {
    _dragIndex = null;
  }

  // ═════════════════════════════════════════════════════════════
  // PAIR / STEP FLOW
  // ═════════════════════════════════════════════════════════════

  /// Clear the current pair so the user can redo this angle (§2.5).
  void trashPair() {
    _liveCenterTimer?.cancel();
    _pointA = null;
    _pointB = null;
    _pairPhase = 0;
    _liveDistanceMm = null;
    _dragIndex = null;
    _dragHitInProgress = false;
    _suggestion = null; // Fresh suggestion for the redone pair, if any
    notifyListeners();
    // Let the readiness assessment drive the text/state — if the area dropped
    // out of tracking, show 'searching' rather than forcing 'ready'.
    _updateGuidance();
  }

  /// Lock the current pair and advance the flow (front → side → next foot).
  void confirmPair() {
    if (_pairPhase != 2 || _liveDistanceMm == null) return;

    final mm = _liveDistanceMm!;
    final cm = mm / 10;
    final isFront = _captureStep == 'front';
    final minCm = isFront ? _minPlausibleWidthCm : _minPlausibleLengthCm;
    final maxCm = isFront ? _maxPlausibleWidthCm : _maxPlausibleLengthCm;
    if (cm < minCm || cm > maxCm) {
      _showFeedback('That looks off — place the two points again');
      return;
    }

    // Store the measurement for this foot/angle.
    if (isFront) {
      if (_currentFoot == 0) {
        _leftWidthMm = mm;
      } else {
        _rightWidthMm = mm;
      }
    } else {
      if (_currentFoot == 0) {
        _leftLengthMm = mm;
      } else {
        _rightLengthMm = mm;
      }
    }

    // ── Front done → side capture for the same foot ──
    if (isFront) {
      _captureStep = 'side';
      _resetForNextStep(
        message: _currentFoot == 0
            ? 'Width done! Now the SIDE of your left foot'
            : 'Width done! Now the SIDE of your right foot',
      );
      return;
    }

    // ── Side done → next foot, or both feet done → results ──
    if (_currentFoot == 0) {
      _currentFoot = 1;
      _captureStep = 'front';
      _resetForNextStep(message: 'Left foot done! Now your right foot');
      return;
    }

    _completeMeasurement();
  }

  /// Reset pair + area-tracking state for the next capture step. The new
  /// guide-box position must be re-verified against a tracked plane before
  /// taps resolve again (the 500ms area tracker re-checks).
  void _resetForNextStep({required String message}) {
    // No area re-verification needed (REMOVE_FLOOR_SCAN_WAIT): the next step's
    // taps are validated per-tap via hitTest, so the UI just resets the pair.
    _pointA = null;
    _pointB = null;
    _pairPhase = 0;
    _liveDistanceMm = null;
    _dragIndex = null;
    _dragHitInProgress = false;
    _placementInProgress = false;
    _suggestion = null; // New step → sampler re-proposes for the new angle
    _guidanceState = 'ready';
    _guidanceText = message;
    notifyListeners();
  }

  /// Show a brief transient feedback toast (invalid taps, implausible values).
  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    _tapFeedback = message;
    notifyListeners();
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (!_disposed) {
        _tapFeedback = null;
        notifyListeners();
      }
    });
  }

  // ═════════════════════════════════════════════════════════════
  // RESULTS
  // ═════════════════════════════════════════════════════════════

  /// Both feet done: apply compensation/sizing math and emit
  /// [MeasurementCompletedEvent] carrying every `FootResultsScreen` argument.
  /// Previously ran inline in `_navigateToResults`; the screen performs the
  /// actual navigation on the event.
  Future<void> _completeMeasurement() async {
    _isProcessing = true;
    _processingStep = 'Computing your size...';
    notifyListeners();

    final leftLength = _leftLengthMm;
    final rightLength = _rightLengthMm;
    if (leftLength == null && rightLength == null) {
      if (!_disposed) {
        _isProcessing = false;
        _guidanceState = 'ready';
        _guidanceText = 'Both measurements failed — please try again';
        notifyListeners();
      }
      return;
    }

    // §4: Apply sock-thickness compensation to raw measurements.
    final isSocks = footCondition == 'socks';
    final leftLengthComp = applySockCompensation(
        leftLength ?? 0, isLength: true, isSocks: isSocks);
    final leftWidthComp = applySockCompensation(
        _leftWidthMm ?? 0, isLength: false, isSocks: isSocks);
    final rightLengthComp = applySockCompensation(
        rightLength ?? 0, isLength: true, isSocks: isSocks);
    final rightWidthComp = applySockCompensation(
        _rightWidthMm ?? 0, isLength: false, isSocks: isSocks);

    // §3: Determine sizing foot (longer foot wins). Use compensated lengths.
    final sizingSide = (leftLengthComp >= rightLengthComp) ? 'left' : 'right';

    // Use the sizing foot's compensated length for EU size lookup.
    final sizingLengthMm = sizingSide == 'left' ? leftLengthComp : rightLengthComp;
    final euSize = footLengthMmToEuSize(sizingLengthMm);
    final usSize = euSize != null
        ? euToUs(euSize, category: shoeCategory)
        : null;
    final ukSize = euSize != null ? euToUk(euSize) : null;

    // §6: Width-to-fit category from sizing foot's compensated dimensions.
    final sizingWidthMm = sizingSide == 'left' ? leftWidthComp : rightWidthComp;
    final widthCategory = widthMmToFitCategory(sizingWidthMm, sizingLengthMm);

    // §A.4: Generate size recommendation reasoning.
    final reason = euSize != null
        ? generateSizeRecommendationReason(
            compensatedLengthMm: sizingLengthMm,
            euSize: euSize,
            measurementSource: 'ar_guided_tap',
          )
        : null;

    if (_disposed) return;

    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] GuidedTapController emitting MeasurementCompletedEvent '
        '(disposed=$_disposed)');
    _eventController.add(MeasurementCompletedEvent(
      payload: GuidedTapResultsPayload(
        footSide: 'both',
        footLengthMm: leftLength ?? 0,
        footWidthMm: _leftWidthMm ?? 0,
        footLengthRightMm: rightLength,
        footWidthRightMm: _rightWidthMm,
        euSize: euSize,
        usSize: usSize,
        ukSize: ukSize,
        paperSize: 'ar',
        footCondition: footCondition,
        paperConfidence: 1.0,
        lightingQuality: 0.9,
        manualMode: true,
        // v2 fields
        measurementSource: 'ar_guided_tap',
        shoeCategory: shoeCategory,
        sizingFootSide: sizingSide,
        widthCategory: widthCategory,
        leftLengthComp: leftLengthComp,
        leftWidthComp: leftWidthComp,
        rightLengthComp: rightLengthComp,
        rightWidthComp: rightWidthComp,
        sizeRecommendationReason: reason,
      ),
    ));
  }

  // ═════════════════════════════════════════════════════════════
  // TEARDOWN
  // ═════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    _guidanceRefreshTimer?.cancel();
    _liveCenterTimer?.cancel();
    _feedbackTimer?.cancel();
    _assistTimer?.cancel();
    _assistDetector?.dispose();
    // D1 fix: no explicit session teardown here — native teardown is
    // single-owned by Flutter's PlatformView disposal when the AR widget
    // unmounts. A Dart-initiated stopSession() could land after the next
    // screen's view registered natively, destroying it mid-creation.
    _eventController.close();
    super.dispose();
  }
}
