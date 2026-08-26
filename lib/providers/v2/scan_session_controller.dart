import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../../services/ar_core_channel.dart';
import '../../utils/ar_foot_measurement_pipeline.dart';
import '../../utils/foot_detector.dart';
import '../../utils/foot_measurement_utils.dart';
import '../../utils/mlkit_segmentation_foot_detector.dart';
import 'scan_phase.dart';

// ═══════════════════════════════════════════════════════════════════
// ONE-SHOT EVENTS
// ═══════════════════════════════════════════════════════════════════

/// One-shot outcomes the v2 session screen reacts to (haptics, navigation).
/// Persistent state lives in [ScanSessionController] fields — only things
/// the screen must react to exactly once are events here.
sealed class ScanSessionEvent {
  const ScanSessionEvent();
}

/// A capture step finished successfully — screen fires a celebratory haptic
/// + check burst. [step] is the step that just completed.
class StepCompletedEvent extends ScanSessionEvent {
  final CaptureStep step;
  const StepCompletedEvent({required this.step});
}

/// One foot fully measured. Screen shows a brief "left foot done" beat.
class FootCompletedEvent extends ScanSessionEvent {
  final String footSide; // 'left' | 'right'
  final double lengthMm;
  const FootCompletedEvent({required this.footSide, required this.lengthMm});
}

/// All captures done and combined — screen navigates to results with the
/// payload. E8 fix: every mm value in [ScanResultsPayloadV2] is the SAME
/// sock-compensated number used by the sizing math, so what the user sees
/// always matches how their size was computed.
class ScanCompleteEvent extends ScanSessionEvent {
  final ScanResultsPayloadV2 payload;
  const ScanCompleteEvent({required this.payload});
}

// ═══════════════════════════════════════════════════════════════════
// RESULTS PAYLOAD
// ═══════════════════════════════════════════════════════════════════

/// One "why this score" line under the confidence gauge. [positive] factors
/// supported the measurement (green check); negative ones lowered it (amber
/// warning) and double as the "not accurate enough — here's why" copy.
class ConfidenceFactorV2 {
  final bool positive;
  final String title;
  final String? detail;

  const ConfidenceFactorV2({
    required this.positive,
    required this.title,
    this.detail,
  });
}

/// Final results of a successful v2 scan. Unlike v1's payload this exposes
/// ONLY compensated values (E8) and carries no fake lighting/paper fields —
/// confidence is what the pipeline actually measured.
class ScanResultsPayloadV2 {
  /// Sock-compensated measurements per foot (mm). Null when that foot's
  /// combine failed but the other foot succeeded.
  final double? leftLengthMm;
  final double? leftWidthMm;
  final double? rightLengthMm;
  final double? rightWidthMm;

  /// Raw (pre-compensation) lengths for transparency display.
  final double? leftRawLengthMm;
  final double? rightRawLengthMm;

  final String? euSize;
  final String? usSize;
  final String? ukSize;

  /// Which foot determined the recommended size ('left' | 'right').
  final String sizingFootSide;

  /// 'narrow' | 'standard' | 'wide'
  final String widthCategory;

  final String footCondition;
  final String shoeCategory;
  final String confidenceLevel;
  final double confidenceScore;
  final int leftSampleCount;
  final int rightSampleCount;
  final String? sizeRecommendationReason;

  /// Per-factor breakdown behind [confidenceScore] — sample volume,
  /// reading consistency, measured-vs-estimated width, both feet, sock
  /// compensation. Rendered under the confidence gauge.
  final List<ConfidenceFactorV2> confidenceFactors;

  const ScanResultsPayloadV2({
    required this.leftLengthMm,
    required this.leftWidthMm,
    required this.rightLengthMm,
    required this.rightWidthMm,
    required this.leftRawLengthMm,
    required this.rightRawLengthMm,
    required this.euSize,
    required this.usSize,
    required this.ukSize,
    required this.sizingFootSide,
    required this.widthCategory,
    required this.footCondition,
    required this.shoeCategory,
    required this.confidenceLevel,
    required this.confidenceScore,
    required this.leftSampleCount,
    required this.rightSampleCount,
    required this.sizeRecommendationReason,
    this.confidenceFactors = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════
// CONTROLLER
// ═══════════════════════════════════════════════════════════════════

/// Non-UI brain of the Foot Size 2.0 auto-scan session.
///
/// Clean rewrite of v1's [AutoScanController] (not a subclass — see plan):
/// same hard-won sampling-loop skeleton (_sampleInProgress overlap guard,
/// attempts-based stall detection, temporal gate, guide-box area tracking,
/// 500ms area poll), with these deliberate deltas:
///
/// - **Typed state machine** ([ScanPhase]/[CoachHint]) instead of stringly
///   `guidanceState` + pre-formatted English strings.
/// - **E7**: proportional width estimates (`len * 0.38`) still feed the live
///   readout but recorded samples carry `widthMeasured: false`, excluding
///   them from width statistics.
/// - **E8**: the completion payload exposes compensated values only; no
///   hardcoded `lightingQuality` or misnamed `paperConfidence`.
/// - **E13**: each capture pass appends to a FRESH per-pass buffer which is
///   merged into the foot's set only on success — a retried pass can never
///   blend stale samples, and a completed foot's statistics are frozen
///   immediately (a later short pass can't retroactively fail it).
/// - Guided-Tap fallback removed (out of scope); stall coaching becomes an
///   amber hint + tips sheet instead.
class ScanSessionController extends ChangeNotifier {
  /// §8 stall coaching: attempts-based so it adapts to interval changes.
  static const int _stallAfterAttempts = 10; // ≈2s at sampleIntervalMs=200ms

  // ── V2-only precision tuning ──
  // The frozen v1 flow keeps the shared pipeline defaults; these tighter
  // gates apply to this controller only.
  //
  /// Longer per-pass window than v1's 4 s ([scanDuration]) → ~25% more
  /// samples per pass, which tightens the median and IQR the sizing math
  /// consumes. Costs one extra second per capture step.
  static const Duration kV2ScanDuration = Duration(seconds: 5);

  /// Detections below this segmentation confidence are shown live but never
  /// recorded as samples — weak frames only blur the statistics.
  static const double kV2MinSampleConfidence = 0.50;

  /// A measured width outside 20–60% of the measured length indicates a bad
  /// hitTest pair (e.g. one point missed the floor), not real anatomy.
  static const double kV2MinWidthRatio = 0.20;
  static const double kV2MaxWidthRatio = 0.60;

  final ArCoreChannel _arCore;
  final FootDetector Function() _detectorFactory;

  final String footCondition;
  final String shoeCategory;

  bool _disposed = false;

  // ── ARCore state ──
  ArTrackingState _trackingState = ArTrackingState.paused;
  bool _planeDetected = false;
  bool _areaTracked = false;
  Timer? _areaCheckTimer;

  /// View aspect ratio (width / height), reported by the session screen's
  /// layout. Used to compute which slice of the camera frame is actually
  /// visible after the native center-crop fill (see [_visibleBand]).
  /// Defaults to a typical tall phone (~19.5:9) until the screen reports.
  double _viewAspectRatio = 9 / 19.5;

  /// Store-only (no notification) — safe to call during build; the 500 ms
  /// area poll picks the new geometry up on its next tick.
  set viewAspectRatio(double ratio) {
    if (ratio > 0) _viewAspectRatio = ratio;
  }

  // ── Session start ──
  String? _startFailureReason;
  String? _startFailureMessage;

  // ── Detection state ──
  FootDetector? _detector;
  bool _footDetected = false;
  int _validDetectionsThisPass = 0;
  final TemporalFootGate _temporalGate = TemporalFootGate();

  // Debug overlay data (most recent detection + frame geometry).
  FootDetectionResult? _lastDetection;
  int _lastFrameWidth = 0;
  int _lastFrameHeight = 0;
  int _lastFrameRotation = 0;

  // ── Session progress ──
  ScanPhase _phase = ScanPhase.needsPermission;
  CaptureStep _currentStep = CaptureStep.leftTop;
  CoachHint? _coachHint;

  // Per-pass sample buffer (E13): merged into the foot's set only when the
  // pass succeeds. Cleared at the start of every pass and on retry.
  final List<MeasurementSample> _passSamples = [];

  /// Successfully combined per-foot results. Frozen once set — later passes
  /// never retroactively alter them (fixes v1's short-second-pass failure).
  MeasurementResult? _leftResult;
  MeasurementResult? _rightResult;

  Timer? _sampleTimer;
  DateTime? _passStartTime;
  bool _sampleInProgress = false;
  double _captureProgress = 0;

  // Live readout (per-frame raw world measurements during capture).
  double? _liveLengthMm;
  double? _liveWidthMm;

  // §8 stall counters (per pass).
  int _attemptsThisPass = 0;
  bool _stallPromptShown = false;

  StreamSubscription<ArSessionEvent>? _eventSubscription;

  final StreamController<ScanSessionEvent> _eventController =
      StreamController<ScanSessionEvent>.broadcast();

  Stream<ScanSessionEvent> get events => _eventController.stream;

  ScanSessionController({
    ArCoreChannel? arCore,
    FootDetector Function()? detectorFactory,
    this.footCondition = 'bare',
    this.shoeCategory = 'men',
  })  : _arCore = arCore ?? ArCoreChannel.instance,
        _detectorFactory =
            detectorFactory ?? MlKitSegmentationFootDetector.new;

  // ── Read-only render state ──
  ScanPhase get phase => _phase;
  CaptureStep get currentStep => _currentStep;
  CoachHint? get coachHint => _coachHint;
  ArTrackingState get trackingState => _trackingState;
  bool get areaTracked => _areaTracked;
  bool get footDetected => _footDetected;
  FootDetectionResult? get lastDetection => _lastDetection;
  int get lastFrameWidth => _lastFrameWidth;
  int get lastFrameHeight => _lastFrameHeight;
  int get lastFrameRotation => _lastFrameRotation;

  /// Progress through the active capture (0.0–1.0).
  double get captureProgress => _captureProgress;

  /// Clean samples recorded in the current (or just-finished) pass — drives
  /// the foot-trace overlay's progressive outline drawing.
  int get passSampleCount => _passSamples.length;

  double? get liveLengthMm => _liveLengthMm;
  double? get liveWidthMm => _liveWidthMm;

  /// Structured session-start failure (phase == [ScanPhase.startFailed]).
  String? get startFailureReason => _startFailureReason;
  String? get startFailureMessage => _startFailureMessage;

  /// Guide rect (normalized) for the current step.
  Rect get currentGuideRect =>
      _currentStep.captureAngle == 'front'
          ? kFrontCaptureGuideRect
          : kSideCaptureGuideRect;

  /// Upright camera-frame aspect (width / height after display rotation).
  /// Falls back to the common 4:3 sensor (3:4 upright) until the first frame
  /// reports its real dimensions.
  double get _uprightFrameAspect {
    if (_lastFrameWidth <= 0 || _lastFrameHeight <= 0) return 3 / 4;
    final w = (_lastFrameRotation % 180) == 90
        ? _lastFrameHeight
        : _lastFrameWidth;
    final h = (_lastFrameRotation % 180) == 90
        ? _lastFrameWidth
        : _lastFrameHeight;
    return w / h;
  }

  /// The slice of the upright camera frame actually visible on screen after
  /// the native center-crop fill (ArFootSizingView applies
  /// `scale = max(viewW/frameW, viewH/frameH)` — the overflowing axis is
  /// cropped). On a ~19.5:9 phone with a 4:3 sensor that is only
  /// x ∈ [0.19, 0.81] of the frame.
  Rect get _visibleBand {
    final frameAspect = _uprightFrameAspect;
    final viewAspect = _viewAspectRatio;
    if (frameAspect > viewAspect) {
      // Frame wider than view → left/right cropped.
      final half = (viewAspect / frameAspect) / 2;
      return Rect.fromLTRB(0.5 - half, 0, 0.5 + half, 1);
    }
    // Frame taller than view → top/bottom cropped.
    final half = (frameAspect / viewAspect) / 2;
    return Rect.fromLTRB(0, 0.5 - half, 1, 0.5 + half);
  }

  /// The guide box clamped to what the user can actually see on screen.
  ///
  /// Fixes the on-device "guide box gone on the side step" bug:
  /// kSideCaptureGuideRect spans x 0.15–0.85, but tall phones crop the
  /// preview to roughly x 0.19–0.81 — the box (and its 4 corner area probes)
  /// landed off-screen, so the side step showed no frame and area lock
  /// stalled. Area probes and the drawn frame both use this rect; detection
  /// still uses the full [currentGuideRect] (the detector sees uncropped
  /// frame content).
  Rect get effectiveGuideRect {
    final clamped = _visibleBand.intersect(currentGuideRect);
    if (clamped.width <= 0 || clamped.height <= 0) return currentGuideRect;
    return clamped;
  }

  /// Samples kept across the whole session so far (observability/tests).
  int get leftSampleCount =>
      _leftResult?.finalSampleCount ?? 0;
  int get rightSampleCount =>
      _rightResult?.finalSampleCount ?? 0;

  /// Whether capture can begin right now (tracking + guide area on floor).
  bool get readyToCapture =>
      _phase == ScanPhase.ready ||
      ((_phase == ScanPhase.positioning || _phase == ScanPhase.stepComplete) &&
          _areaTracked &&
          _trackingState == ArTrackingState.tracking);

  // ═════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═════════════════════════════════════════════════════════════════

  /// Camera permission denied — the screen reports it before calling
  /// [initialize]; this phase renders the permission UI.
  void reportPermissionDenied() {
    if (_disposed) return;
    _setPhase(ScanPhase.needsPermission);
  }

  /// Start the detector + ARCore session. Resolves after the terminal
  /// start outcome is known (started → positioning, else → startFailed).
  Future<void> initialize() async {
    if (_disposed) return;
    _detector = _detectorFactory();

    final start = await _arCore.startSession();
    if (_disposed) return;
    if (!start.started) {
      _startFailureReason = start.reason;
      _startFailureMessage = start.message;
      _setPhase(ScanPhase.startFailed);
      return;
    }

    _eventSubscription = _arCore.events.listen(_onSessionEvent);

    // Localized plane tracking: poll whether the current guide-box region is
    // covered by a tracked plane (planes grow incrementally over time).
    _areaCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => refreshAreaTracking(),
    );
    _setPhase(ScanPhase.positioning);
  }

  void _onSessionEvent(ArSessionEvent event) {
    if (_disposed) return;

    switch (event.type) {
      case 'tracking':
        final state = event.data['state']?.toString() ?? 'paused';
        _trackingState = state == 'tracking'
            ? ArTrackingState.tracking
            : state == 'limited'
                ? ArTrackingState.limited
                : ArTrackingState.paused;
        refreshAreaTracking();
        break;

      case 'plane':
        _planeDetected = true;
        refreshAreaTracking();
        break;

      case 'error':
        final msg = event.data['message']?.toString() ?? 'Unknown error';
        if (_phase != ScanPhase.capturing) {
          _coachHint = const CoachHint(
            reason: CoachReason.havingTrouble,
            tone: CoachTone.warning,
          );
          _startFailureMessage = msg;
          notifyListeners();
        }
        break;
    }
  }

  /// Verify a tracked plane covers the CURRENT step's guide-box region by
  /// hit-testing its center + corners (center + ≥2 corners on plane).
  /// Probes use [effectiveGuideRect] — corners outside the visible band can
  /// never hit a plane polygon, which permanently stalled side-step locking.
  Future<void> refreshAreaTracking() async {
    if (_disposed || _phase == ScanPhase.capturing) return;
    if (!_arCore.isSessionActive) return;

    final rect = effectiveGuideRect;
    final probePoints = <Offset>[
      rect.center,
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    final hits = await _arCore.hitTestBatch(screenPoints: probePoints);
    if (_disposed) return;
    final onPlane = hits.whereType<ArWorldPoint>().length;
    final tracked = onPlane >= 3;
    if (tracked != _areaTracked) {
      _areaTracked = tracked;
      _reconcileIdlePhases();
    }
  }

  /// Transition between idle phases (positioning ⇄ ready) based on tracking
  /// conditions. Never touches capturing/processing phases.
  void _reconcileIdlePhases() {
    if (_disposed || _phase == ScanPhase.capturing) return;

    final trackingOk = _areaTracked && _trackingState == ArTrackingState.tracking;

    switch (_phase) {
      case ScanPhase.positioning:
        if (trackingOk) {
          _phase = ScanPhase.ready;
          _coachHint = const CoachHint(
            reason: CoachReason.positionFoot,
            tone: CoachTone.active,
          );
          notifyListeners();
        } else {
          _updatePositioningHint();
        }
        break;
      case ScanPhase.ready:
        if (!trackingOk) {
          _phase = ScanPhase.positioning;
          _updatePositioningHint();
          notifyListeners();
        }
        break;
      case ScanPhase.stepComplete:
        // Waiting out the celebration beat — readiness flips via readyToCapture.
        break;
      default:
        break;
    }
  }

  void _updatePositioningHint() {
    if (!_planeDetected || _trackingState == ArTrackingState.paused) {
      _coachHint = const CoachHint(
        reason: CoachReason.findFloor,
        tone: CoachTone.neutral,
      );
    } else {
      _coachHint = const CoachHint(
        reason: CoachReason.moveSlowly,
        tone: CoachTone.neutral,
      );
    }
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════════
  // CAPTURE
  // ═════════════════════════════════════════════════════════════════

  /// Begin the current step's capture pass (screen action button).
  void startCapture() {
    if (_disposed || _phase == ScanPhase.capturing) return;
    if (!_areaTracked || _trackingState != ArTrackingState.tracking) {
      // Coach instead of silently no-oping (post-step transition the new box
      // position may not be mapped yet).
      _phase = ScanPhase.positioning;
      _coachHint = const CoachHint(
        reason: CoachReason.findFloor,
        tone: CoachTone.warning,
      );
      notifyListeners();
      return;
    }

    // E13: fresh buffer per pass — nothing from a previous attempt survives.
    _passSamples.clear();
    _validDetectionsThisPass = 0;
    _footDetected = false;
    _lastDetection = null;
    _liveLengthMm = null;
    _liveWidthMm = null;
    _attemptsThisPass = 0;
    _stallPromptShown = false;
    _captureProgress = 0;
    _temporalGate.reset();
    _passStartTime = DateTime.now();

    _phase = ScanPhase.capturing;
    _coachHint = const CoachHint(
      reason: CoachReason.holdStill,
      tone: CoachTone.active,
    );
    notifyListeners();

    _sampleTimer = Timer.periodic(
      Duration(milliseconds: sampleIntervalMs),
      (_) => _collectSample(),
    );

    Timer(kV2ScanDuration, () {
      if (!_disposed && _phase == ScanPhase.capturing) {
        _endPass();
      }
    });
  }

  /// Abandon the running pass (user backs out / screen disposes mid-capture).
  void cancelCapture() {
    if (_phase != ScanPhase.capturing) return;
    _sampleTimer?.cancel();
    _passSamples.clear(); // E13: partial pass never blends into results
    _phase = ScanPhase.ready;
    _reconcileIdlePhases();
    notifyListeners();
  }

  Future<void> _collectSample() async {
    if (_phase != ScanPhase.capturing || _passStartTime == null) return;
    if (_sampleInProgress) return; // No overlapping collection
    _sampleInProgress = true;

    try {
      final trackingQuality = _trackingState == ArTrackingState.tracking
          ? 1.0
          : _trackingState == ArTrackingState.limited
              ? 0.5
              : 0.0;

      _captureProgress = DateTime.now()
          .difference(_passStartTime!)
          .inMilliseconds /
          kV2ScanDuration.inMilliseconds;

      // ── 1. Acquire the cached NV21 CPU frame from ARCore ──
      final frame = await _arCore.acquireCameraFrame();
      if (frame == null || frame.nv21Bytes.isEmpty) {
        _lastDetection = null;
        _clearLiveMeasurement();
        _setFootDetected(false);
        return;
      }

      _lastFrameWidth = frame.width;
      _lastFrameHeight = frame.height;
      _lastFrameRotation = frame.rotationDegrees;

      // ── 2. On-device foot detection ──
      final detection = await _detector?.detect(
        nv21Bytes: frame.nv21Bytes,
        width: frame.width,
        height: frame.height,
        rotationDegrees: frame.rotationDegrees,
        preferSide: _currentStep.footSide,
        guideRect: currentGuideRect,
      );
      if (detection == null) return;

      // ── 3. Score-based acceptance + temporal gate ──
      final rawValid = detection.footDetected &&
          detection.heelPoint != null &&
          detection.toePoint != null;
      final confirmed = _temporalGate.update(rawValid);

      if (!rawValid) {
        debugPrint('[ArScanV2] No foot (side=${detection.footSide}, '
            'conf=${detection.confidence.toStringAsFixed(2)})');
        _lastDetection = null;
        _clearLiveMeasurement();
        _setFootDetected(confirmed);
        return;
      }

      _lastDetection = detection;
      _setFootDetected(confirmed);

      // ── 4. 2D points → 3D world via ARCore hitTest ──
      final screenPoints = <Offset>[
        detection.heelPoint!.asOffset,
        detection.toePoint!.asOffset,
        ...?detection.widthPoints?.map((p) => p.asOffset),
      ];
      final worldPoints = await _arCore.hitTestBatch(screenPoints: screenPoints);
      final raycastHit = worldPoints.length >= 2 &&
          worldPoints[0] != null &&
          worldPoints[1] != null;

      // ── 5. Real-world measurements (computed pre-confirmation so the live
      // readout updates continuously during capture) ──
      double? lengthMm;
      double? widthMm;
      var widthMeasured = false;
      if (raycastHit) {
        final len = worldPoints[0]!.distanceTo(worldPoints[1]!) * 1000;
        if (worldPoints.length >= 4 &&
            worldPoints[2] != null &&
            worldPoints[3] != null) {
          widthMm = worldPoints[2]!.distanceTo(worldPoints[3]!) * 1000;
          widthMeasured = true;
        } else {
          // E7: proportional estimate — fine for the LIVE readout, but the
          // recorded sample is tagged widthMeasured:false so it never enters
          // the width median.
          widthMm = len * 0.38;
          widthMeasured = false;
        }
        lengthMm = len;
        _liveLengthMm = len;
        _liveWidthMm = widthMm;
        notifyListeners();
      } else {
        _clearLiveMeasurement();
        final nonNullHits = worldPoints.whereType<ArWorldPoint>().length;
        debugPrint('[ArScanV2] raycast=REJECT ($nonNullHits/'
            '${screenPoints.length} points hit the plane)');
      }

      if (!confirmed) return; // Wait for consecutive positive frames
      _validDetectionsThisPass++;
      if (!raycastHit) return;

      // Sanity bounds: reject degenerate measurements.
      if (lengthMm == null ||
          widthMm == null ||
          lengthMm <= 0 ||
          lengthMm > 500 ||
          widthMm <= 0 ||
          widthMm > 200) {
        return;
      }

      // V2 precision gates (see the class constants above): weak detections
      // and anatomically implausible measured widths never become samples.
      if (detection.confidence < kV2MinSampleConfidence) {
        debugPrint('[ArScanV2] sample=SKIP low-confidence '
            '(${detection.confidence.toStringAsFixed(2)})');
        return;
      }
      // widthMm/lengthMm are already non-null here (sanity bounds above).
      if (widthMeasured &&
          (widthMm < lengthMm * kV2MinWidthRatio ||
              widthMm > lengthMm * kV2MaxWidthRatio)) {
        debugPrint('[ArScanV2] sample=SKIP implausible width '
            '(${widthMm.toStringAsFixed(1)}mm vs ${lengthMm.toStringAsFixed(1)}mm len)');
        return;
      }

      _passSamples.add(MeasurementSample(
        lengthMm: lengthMm,
        widthMm: widthMm,
        trackingQuality: trackingQuality,
        segmentationConfidence: detection.confidence,
        timestamp: DateTime.now(),
        captureAngle: _currentStep.captureAngle,
        widthMeasured: widthMeasured,
      ));

      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[ArScanV2] Sample collection error: $e');
    } finally {
      _sampleInProgress = false;
      _attemptsThisPass++;
      _maybeCoachStall();
    }
  }

  /// §8 stall coaching: enough attempted frames with zero confirmed
  /// detections → amber hint. Non-destructive: pass keeps running.
  void _maybeCoachStall() {
    if (_phase != ScanPhase.capturing ||
        _disposed ||
        _stallPromptShown ||
        _validDetectionsThisPass > 0 ||
        _attemptsThisPass < _stallAfterAttempts) {
      return;
    }
    _stallPromptShown = true;
    _coachHint = const CoachHint(
      reason: CoachReason.havingTrouble,
      tone: CoachTone.warning,
    );
    notifyListeners();
  }

  void _setFootDetected(bool detected) {
    if (_disposed) return;
    if (_footDetected != detected) {
      _footDetected = detected;
      notifyListeners();
    }
  }

  void _clearLiveMeasurement() {
    if (_disposed) return;
    _liveLengthMm = null;
    _liveWidthMm = null;
    notifyListeners();
  }

  /// Pass timer elapsed — advance the state machine.
  void _endPass() {
    _sampleTimer?.cancel();
    _captureProgress = 1;

    // No confirmed detections this pass → fail explicitly (v1 §4), discard
    // the pass buffer (E13) and coach a retry.
    if (_validDetectionsThisPass == 0) {
      _passSamples.clear();
      _phase = ScanPhase.ready;
      _coachHint = const CoachHint(
        reason: CoachReason.havingTrouble,
        tone: CoachTone.warning,
      );
      notifyListeners();
      return;
    }

    _phase = ScanPhase.stepComplete;
    _coachHint = const CoachHint(
      reason: CoachReason.stepDone,
      tone: CoachTone.success,
    );
    notifyListeners();
    _eventController.add(StepCompletedEvent(step: _currentStep));

    // Give the success beat ~900 ms before moving on.
    Timer(const Duration(milliseconds: 900), () {
      if (_disposed) return;
      _advanceAfterStepComplete();
    });
  }

  void _advanceAfterStepComplete() {
    // E13: only NOW does the successful pass join the foot's cumulative set
    // — a failed/retried pass never contributed anything.
    _mergePassIntoCurrentFoot();

    final side = _currentStep.footSide;
    final next = _currentStep.next;

    if (_currentStep.captureAngle == 'front') {
      // Top view done → same foot's side view next.
      if (next != null) {
        _currentStep = next;
      }
      _areaTracked = false; // New box position must be re-verified
      _phase = ScanPhase.ready;
      _coachHint = const CoachHint(
        reason: CoachReason.positionFoot,
        tone: CoachTone.active,
      );
      notifyListeners();
      return;
    }

    // Side done → combine this foot NOW (E13: frozen immediately).
    final result = combineGuidedSamples(_samplesFor(side));
    if (result == null) {
      // Combine failed — clear the foot and restart its TOP step.
      _clearFoot(side);
      _currentStep = side == 'left' ? CaptureStep.leftTop : CaptureStep.rightTop;
      _areaTracked = false;
      _phase = ScanPhase.ready;
      _coachHint = const CoachHint(
        reason: CoachReason.havingTrouble,
        tone: CoachTone.warning,
      );
      notifyListeners();
      return;
    }

    if (side == 'left') {
      _leftResult = result;
    } else {
      _rightResult = result;
    }

    _eventController.add(FootCompletedEvent(
      footSide: side,
      lengthMm: result.lengthMm,
    ));

    if (next != null) {
      _currentStep = next;
      _areaTracked = false;
      _phase = ScanPhase.ready;
      _coachHint = CoachHint(
        reason: CoachReason.footDone,
        tone: CoachTone.success,
        footLengthMm: result.lengthMm,
      );
      notifyListeners();
    } else {
      _finishBothFeet();
    }
  }

  List<MeasurementSample> _samplesFor(String footSide) {
    // Cumulative per-foot sets live only conceptually — we keep one list per
    // foot fed by successful passes.
    return footSide == 'left' ? _leftSamples : _rightSamples;
  }

  void _clearFoot(String footSide) {
    if (footSide == 'left') {
      _leftSamples.clear();
      _leftResult = null;
    } else {
      _rightSamples.clear();
      _rightResult = null;
    }
  }

  // Cumulative per-foot sample sets (fed by merged passes).
  final List<MeasurementSample> _leftSamples = [];
  final List<MeasurementSample> _rightSamples = [];

  /// Merge the just-completed pass into its foot's cumulative set.
  void _mergePassIntoCurrentFoot() {
    (_currentStep.footSide == 'left' ? _leftSamples : _rightSamples)
        .addAll(_passSamples);
  }

  // ═════════════════════════════════════════════════════════════════
  // FINALIZATION (E8)
  // ═════════════════════════════════════════════════════════════════

  void _finishBothFeet() {
    _phase = ScanPhase.processing;
    notifyListeners();

    final leftResult = _leftResult ?? combineGuidedSamples(_leftSamples);
    final rightResult = _rightResult ?? combineGuidedSamples(_rightSamples);
    _leftResult = leftResult;
    _rightResult = rightResult;

    if (leftResult == null && rightResult == null) {
      _clearFoot('left');
      _clearFoot('right');
      _currentStep = CaptureStep.leftTop;
      _areaTracked = false;
      _phase = ScanPhase.ready;
      _coachHint = const CoachHint(
        reason: CoachReason.havingTrouble,
        tone: CoachTone.warning,
      );
      notifyListeners();
      return;
    }

    final isSocks = footCondition == 'socks';
    final leftLengthComp = applySockCompensation(
        leftResult?.lengthMm ?? 0, isLength: true, isSocks: isSocks);
    final leftWidthComp = applySockCompensation(
        leftResult?.widthMm ?? 0, isLength: false, isSocks: isSocks);
    final rightLengthComp = applySockCompensation(
        rightResult?.lengthMm ?? 0, isLength: true, isSocks: isSocks);
    final rightWidthComp = applySockCompensation(
        rightResult?.widthMm ?? 0, isLength: false, isSocks: isSocks);

    // Longer compensated foot determines size.
    final sizingSide = leftLengthComp >= rightLengthComp ? 'left' : 'right';
    final sizingLengthMm =
        sizingSide == 'left' ? leftLengthComp : rightLengthComp;
    final euSize = footLengthMmToEuSize(sizingLengthMm);
    final usSize =
        euSize != null ? euToUs(euSize, category: shoeCategory) : null;
    final ukSize = euSize != null ? euToUk(euSize) : null;

    final sizingWidthMm = sizingSide == 'left' ? leftWidthComp : rightWidthComp;
    final widthCategory = widthMmToFitCategory(sizingWidthMm, sizingLengthMm);

    final leftConf = leftResult?.confidenceScore ?? 0.0;
    final rightConf = rightResult?.confidenceScore ?? 0.0;
    final overallConf = (leftConf + rightConf) / 2;
    final confLevel = overallConf >= 0.75
        ? 'high'
        : overallConf >= 0.45
            ? 'medium'
            : 'low';

    final reason = euSize != null
        ? generateSizeRecommendationReason(
            compensatedLengthMm: sizingLengthMm,
            euSize: euSize,
            measurementSource: 'ar_auto_scan',
            confidenceLevel: confLevel,
          )
        : null;

    final factors = _buildConfidenceFactors(
      leftResult: leftResult,
      rightResult: rightResult,
      sizingSide: sizingSide,
      isSocks: isSocks,
    );

    _setPhase(ScanPhase.complete);
    _eventController.add(ScanCompleteEvent(
      payload: ScanResultsPayloadV2(
        // E8: display values ARE the compensated sizing inputs.
        leftLengthMm: leftResult != null ? leftLengthComp : null,
        leftWidthMm: leftResult != null ? leftWidthComp : null,
        rightLengthMm: rightResult != null ? rightLengthComp : null,
        rightWidthMm: rightResult != null ? rightWidthComp : null,
        leftRawLengthMm: leftResult?.lengthMm,
        rightRawLengthMm: rightResult?.lengthMm,
        euSize: euSize,
        usSize: usSize,
        ukSize: ukSize,
        sizingFootSide: sizingSide,
        widthCategory: widthCategory,
        footCondition: footCondition,
        shoeCategory: shoeCategory,
        confidenceLevel: confLevel,
        confidenceScore: overallConf,
        leftSampleCount: leftResult?.finalSampleCount ?? 0,
        rightSampleCount: rightResult?.finalSampleCount ?? 0,
        sizeRecommendationReason: reason,
        confidenceFactors: factors,
      ),
    ));
  }

  /// Honest per-factor breakdown of the confidence score — what went well
  /// and what dragged it down ( doubles as the "why isn't this accurate"
  /// explanation the results screen renders under the gauge).
  List<ConfidenceFactorV2> _buildConfidenceFactors({
    required MeasurementResult? leftResult,
    required MeasurementResult? rightResult,
    required String sizingSide,
    required bool isSocks,
  }) {
    final factors = <ConfidenceFactorV2>[];
    final sizingResult = sizingSide == 'left' ? leftResult : rightResult;

    // ── Sample volume on the sizing foot ──
    final samples = sizingResult?.finalSampleCount ?? 0;
    if (samples >= idealSampleCount) {
      factors.add(ConfidenceFactorV2(
        positive: true,
        title: 'Plenty of clean readings',
        detail:
            '$samples samples kept — stray frames were discarded automatically.',
      ));
    } else if (samples >= minValidSamples) {
      factors.add(ConfidenceFactorV2(
        positive: false,
        title: 'Fewer readings than ideal ($samples)',
        detail:
            'A slower, steadier scan collects more frames and tightens the estimate.',
      ));
    } else {
      factors.add(ConfidenceFactorV2(
        positive: false,
        title: 'Very few clean readings ($samples)',
        detail: 'We still got a result, but consider re-scanning for precision.',
      ));
    }

    // ── Consistency (IQR spread of the sizing foot's length) ──
    final iqr = sizingResult?.lengthIqrMm;
    if (iqr != null) {
      if (iqr <= 3.0) {
        factors.add(ConfidenceFactorV2(
          positive: true,
          title: 'Very consistent readings',
          detail: 'Frame-to-frame spread was only ±${iqr.toStringAsFixed(1)} mm.',
        ));
      } else {
        factors.add(ConfidenceFactorV2(
          positive: false,
          title: 'Readings varied a bit',
          detail:
              'Spread of ±${iqr.toStringAsFixed(1)} mm — moving the phone slowly helps.',
        ));
      }
    }

    // ── Width measured directly vs proportional estimate (E7) ──
    final sizingSamples =
        sizingSide == 'left' ? _leftSamples : _rightSamples;
    if (sizingSamples.isNotEmpty) {
      final measuredWidths =
          sizingSamples.where((s) => s.widthMeasured).length;
      if (measuredWidths == 0) {
        factors.add(const ConfidenceFactorV2(
          positive: false,
          title: 'Width was estimated, not measured',
          detail:
              'The camera never caught your foot’s widest points — the fit '
              'category may be off.',
        ));
      } else if (measuredWidths >= sizingSamples.length ~/ 2) {
        factors.add(ConfidenceFactorV2(
          positive: true,
          title: 'Width measured directly',
          detail: '$measuredWidths frames caught your foot’s widest points.',
        ));
      }
    }

    // ── Both feet vs one ──
    if (leftResult != null && rightResult != null) {
      factors.add(ConfidenceFactorV2(
        positive: true,
        title: 'Both feet measured',
        detail:
            'Sized on your larger ($sizingSide) foot — the safe choice for fit.',
      ));
    } else {
      final done = leftResult != null ? 'left' : 'right';
      factors.add(ConfidenceFactorV2(
        positive: false,
        title: 'Only your $done foot was measured',
        detail:
            'The other foot’s capture didn’t produce enough data. Sizes are '
            'based on this foot alone.',
      ));
    }

    // ── Sock compensation transparency ──
    if (isSocks) {
      factors.add(const ConfidenceFactorV2(
        positive: true,
        title: 'Sock thickness compensated',
        detail: 'Standard sock offset subtracted before sizing.',
      ));
    }

    return factors;
  }

  void _setPhase(ScanPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════════
  // TEARDOWN
  // ═════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    _sampleTimer?.cancel();
    _areaCheckTimer?.cancel();
    _detector?.dispose();
    // D1 rule carried over: NO Dart-initiated stopSession — native teardown
    // is single-owned by Flutter's PlatformView disposal.
    _eventController.close();
    super.dispose();
  }
}
