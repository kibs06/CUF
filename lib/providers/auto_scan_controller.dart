import 'dart:async';

import 'package:flutter/material.dart';

// TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
import '../services/diag_logger.dart' show navDiag;
import '../services/ar_core_channel.dart';
import '../utils/ar_foot_measurement_pipeline.dart';
import '../utils/foot_detector.dart';
import '../utils/foot_measurement_utils.dart';
import '../utils/mlkit_segmentation_foot_detector.dart';

// ═══════════════════════════════════════════════════════════════
// ONE-SHOT OUTCOME EVENTS
// ═══════════════════════════════════════════════════════════════

/// One-shot outcomes the scan SCREEN reacts to (snackbars, navigation).
///
/// Controllers must not navigate or show snackbars themselves — the screen
/// listens to this stream and performs the UI action. Everything expressible
/// as persistent state (stall coaching, no-foot failure, session errors) is
/// NOT an event; it is [AutoScanController] state the widget renders.
sealed class AutoScanEvent {
  const AutoScanEvent();
}

/// The left foot's side capture combined successfully and the flow advanced
/// to the right foot. Screen shows the "Left foot: Xmm" snackbar.
class LeftFootDoneEvent extends AutoScanEvent {
  final double lengthMm;
  const LeftFootDoneEvent({required this.lengthMm});
}

/// A side capture's samples failed to combine into a measurement. Screen
/// shows the "Not enough valid samples" snackbar.
class SideCombineFailedEvent extends AutoScanEvent {
  const SideCombineFailedEvent();
}

/// Both feet are done — screen navigates to `FootResultsScreen` with the
/// payload. Carries every argument `FootResultsScreen` receives, computed by
/// the same math that previously ran inline in `_navigateToResults`.
class ScanCompletedEvent extends AutoScanEvent {
  final AutoScanResultsPayload payload;
  const ScanCompletedEvent({required this.payload});
}

/// All values passed to `FootResultsScreen` after both feet complete.
class AutoScanResultsPayload {
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
  final String confidenceLevel;
  final double confidenceScore;
  final int leftSampleCount;
  final int rightSampleCount;

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

  const AutoScanResultsPayload({
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
    required this.confidenceLevel,
    required this.confidenceScore,
    required this.leftSampleCount,
    required this.rightSampleCount,
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

// ═══════════════════════════════════════════════════════════════
// CONTROLLER
// ═══════════════════════════════════════════════════════════════

/// Non-UI logic of the auto AR foot scan (`FootArScanScreen`).
///
/// Owns: ARCore session/tracking state, the guided two-angle sampling loop
/// (front→side per foot), quality/temporal gating, stall detection, sample
/// collection, and the statistical combination + results computation.
///
/// Extracted verbatim from `foot_ar_scan_screen.dart` (Phase 1 refactor) —
/// behavior-preserving move; every constant, guard order and state transition
/// is unchanged from the pre-extraction widget code. Navigation, snackbars,
/// animations and all rendering stay in the screen, which listens to this
/// ChangeNotifier for rebuilds and to [events] for one-shot outcomes.
class AutoScanController extends ChangeNotifier {
  /// §8: Stall/fallback detection — driven off DETECTION ATTEMPTS rather than
  /// a wall-clock timer, so it naturally adapts if [sampleIntervalMs] or
  /// [scanDuration] ever change. (A previous fixed 12s timer outlived the 4s
  /// scan window entirely: end-of-pass always flipped [_scanActive] false
  /// first, so the stall prompt could never fire.) If this many frames have
  /// been attempted in the current pass without a SINGLE confirmed detection,
  /// coach the user toward Guided Tap. The condition is cumulative over the
  /// whole pass — not an instantaneous check — so a scan that is
  /// mid-confirmation (temporal gate needs ~3 positive frames) or warming up
  /// the ML model does not false-positive as long as any confirmation lands
  /// within the window.
  static const int _stallAfterAttempts = 10; // ≈2s at sampleIntervalMs=200ms

  /// TEMP-DEBUG: stage-by-stage sample pipeline logging for the "Foot
  /// detected but 0 samples" diagnosis (§1 of ZERO_SAMPLES_DIAGNOSTIC_PROMPT).
  /// Set false to silence. Remove after diagnosis.
  static const bool _kSampleDebugLogging = true;

  final ArCoreChannel _arCore;
  final FootDetector Function() _detectorFactory;

  /// Config consumed by the results computation (sock compensation +
  /// EU→US conversion category), mirroring the screen's constructor args.
  final String footCondition;
  final String shoeCategory;

  bool _disposed = false;

  // ── ARCore State ──
  ArTrackingState _trackingState = ArTrackingState.paused;
  bool _planeDetected = false;

  /// §2 localized plane tracking: whether a tracked horizontal plane currently
  /// covers the guide-box REGION specifically (verified by hit-testing the
  /// box center + corners), not merely whether any plane exists anywhere.
  /// Capture is only "ready" when this is true — so users start as soon as
  /// the small floor area under the guide box is mapped, without waving the
  /// phone around to map the whole room.
  bool _areaTracked = false;

  /// Periodic re-check of [_areaTracked] (planes grow over time, so a single
  /// 'plane' event isn't enough — the box area may become covered later).
  Timer? _areaCheckTimer;

  // ── Detection State ──
  FootDetector? _detector;

  /// Whether a foot was confidently detected in the most recent sampled frame
  /// (score-based: true once the combined quality score clears
  /// [kSampleAcceptScore] through the temporal gate).
  bool _footDetected = false;

  /// How many frames in the current scan pass produced a valid foot detection.
  /// Used to fail the scan explicitly if NO frame detected a foot (§4).
  int _validDetectionsThisPass = 0;

  /// True when a scan pass failed because no foot was ever detected.
  bool _noFootScanFailure = false;

  // ── Debug Detection Overlay data ──
  // Most recent detection result + its frame geometry, rendered as an overlay
  // on the camera preview by the screen (data produced HERE during sampling).

  /// Most recent detection result (or null if none yet).
  FootDetectionResult? _lastDetection;

  /// Dimensions of the frame [_lastDetection] was computed from, needed
  /// to map normalized mask coordinates onto the (center-cropped) preview.
  int _lastFrameWidth = 0;
  int _lastFrameHeight = 0;
  int _lastFrameRotation = 0;

  // ── Scan State ──
  int _currentFoot = 0; // 0 = left, 1 = right

  /// Current guided capture step for the active foot: 'front' (top-down,
  /// primary for width) or 'side' (profile, primary for length).
  String _captureStep = 'front';

  /// Rolling temporal-consistency gate (§1.2): requires several CONSECUTIVE
  /// shape-validated positive frames before the detection is "confirmed" and
  /// samples begin recording (also prevents UI flicker).
  final TemporalFootGate _temporalGate = TemporalFootGate();

  bool _scanActive = false;
  DateTime? _scanStartTime;
  final List<MeasurementSample> _leftSamples = [];
  final List<MeasurementSample> _rightSamples = [];
  Timer? _sampleTimer;
  int _currentSampleCount = 0;

  // ── Live Measurement Preview data ──
  // Per-frame real-world measurements computed during capture; the screen
  // formats them into the live cm readout near the guide box. Doubles as a
  // diagnostic signal: a wildly unstable/implausible number while a real foot
  // is clearly in frame points at extraction trouble (§2.2).
  double? _liveLengthMm;
  double? _liveWidthMm;

  /// Guards against overlapping [_collectSample] runs.
  ///
  /// The sample timer fires every 200ms but detection + hitTest is async
  /// (method channel round-trips, ML Kit inference). If inference ever takes
  /// longer than the interval, concurrent invocations could double-append
  /// samples from the same frame and skew the statistical pipeline.
  bool _sampleInProgress = false;

  // ── Processing State ──
  bool _isProcessing = false;
  String _processingStep = '';

  // ── Guidance State ──
  String _guidanceText = 'Initializing AR...';
  String _guidanceState =
      'initializing'; // 'initializing', 'searching', 'ready', 'scanning', 'done'

  /// True when a capture step just completed and the app is waiting for the
  /// user to start the next step (front → side, or left → right foot).
  /// Guards [_updateGuidance] from overwriting the step-complete coaching
  /// text when ARCore tracking/plane events fire between steps (the two-step
  /// flow makes the inter-step instruction critical, §2.5).
  bool _stepPending = false;

  // §8 stall detection counters
  int _attemptsThisPass = 0;
  bool _stallPromptShown = false;

  StreamSubscription<ArSessionEvent>? _eventSubscription;

  /// One-shot outcome events (navigation/snackbar triggers). Broadcast so
  /// late listeners never receive stale events.
  final StreamController<AutoScanEvent> _eventController =
      StreamController<AutoScanEvent>.broadcast();

  Stream<AutoScanEvent> get events => _eventController.stream;

  AutoScanController({
    ArCoreChannel? arCore,
    FootDetector Function()? detectorFactory,
    this.footCondition = 'bare',
    this.shoeCategory = 'men',
  })  : _arCore = arCore ?? ArCoreChannel.instance,
        _detectorFactory =
            detectorFactory ?? MlKitSegmentationFootDetector.new;

  // ── Read-only state for rendering ──
  ArTrackingState get trackingState => _trackingState;
  bool get planeDetected => _planeDetected;
  bool get areaTracked => _areaTracked;
  bool get footDetected => _footDetected;
  FootDetectionResult? get lastDetection => _lastDetection;
  int get lastFrameWidth => _lastFrameWidth;
  int get lastFrameHeight => _lastFrameHeight;
  int get lastFrameRotation => _lastFrameRotation;
  int get currentFoot => _currentFoot;
  String get captureStep => _captureStep;
  Rect get currentGuideRect =>
      _captureStep == 'front' ? kFrontCaptureGuideRect : kSideCaptureGuideRect;
  double? get liveLengthMm => _liveLengthMm;
  double? get liveWidthMm => _liveWidthMm;
  String get guidanceText => _guidanceText;
  String get guidanceState => _guidanceState;
  bool get scanActive => _scanActive;
  bool get stepPending => _stepPending;

  /// Whether the §8 stall-coaching prompt has fired in the current pass.
  bool get stallPromptShown => _stallPromptShown;
  bool get noFootFailure => _noFootScanFailure;
  bool get processing => _isProcessing;
  String get processingStep => _processingStep;
  int get currentSampleCount => _currentSampleCount;

  /// Whether the LEFT foot already has samples (top-bar check icon).
  bool get leftFootHasSamples => _leftSamples.isNotEmpty;

  /// Samples accumulated for each foot so far (test/observability surface —
  /// also what the results payload's per-foot combine draws from).
  int get leftSampleCount => _leftSamples.length;
  int get rightSampleCount => _rightSamples.length;

  /// Confirmed detections in the current/most-recent pass — gates the
  /// "Switch to Guided Tap" fallback button's visibility.
  int get validDetectionsThisPass => _validDetectionsThisPass;

  // ═════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═════════════════════════════════════════════════════════════

  /// Camera permission was denied — surface today's exact error text/state.
  /// (The permission request itself stays in the screen.)
  void reportCameraPermissionDenied() {
    _guidanceText = 'Camera permission is required for AR scanning';
    _guidanceState = 'error';
    notifyListeners();
  }

  /// Start the detector + ARCore session and begin listening for events.
  /// Resolves only after the terminal session-start outcome is known.
  Future<void> initialize() async {
    // Initialize the on-device foot detector.
    // Segmentation fallback (FULL REPLACEMENT per §2.3 of the fix brief):
    // ML Kit Pose proved inconsistent on tight foot-only crops (its person
    // detector needs body context), so the segmentation-based detector is now
    // the sole detection path. Gating/measurement logic is unchanged — it
    // consumes the same FootDetectionResult contract via the FootDetector
    // interface. The pose detector remains in the repo only for §1
    // diagnostic comparison; it is not instantiated here.
    _detector = _detectorFactory();

    // Start ARCore session. Resolves only with a terminal outcome — E3 fix
    // makes `started == false` REACHABLE now (unsupported device, needs
    // install, timeout), so surface the specific reason instead of a generic
    // error.
    final start = await _arCore.startSession();
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
              "AR isn't supported on this device — use Guided Tap to measure your feet instead.";
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

    // Listen for ARCore events
    _eventSubscription = _arCore.events.listen(_onSessionEvent);

    // §2 localized plane tracking: poll whether the guide-box region is
    // covered by a tracked plane. ARCore planes grow incrementally, so keep
    // re-checking while the user positions the phone — readiness flips on as
    // soon as the box area is mapped, no full-room mapping required.
    _areaCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => refreshAreaTracking(),
    );
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
        notifyListeners();
        refreshAreaTracking(); // Re-verify the box region after tracking changes
        _updateGuidance();
        break;

      case 'plane':
        _planeDetected = true;
        notifyListeners();
        refreshAreaTracking(); // Is the box area actually on this plane?
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

  /// §2 localized plane tracking: verify a tracked plane actually covers the
  /// guide-box region by hit-testing its center + corners. The box area is
  /// "tracked" when the center (and most corners) land on the floor plane —
  /// this is what gates capture readiness, replacing the old "any plane
  /// exists" check. Runs on the 500 ms poll tick AND after tracking/plane
  /// events.
  Future<void> refreshAreaTracking() async {
    if (_disposed || _scanActive) return;
    if (!_arCore.isSessionActive) return;

    final rect = currentGuideRect;
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
    final tracked = onPlane >= 3; // Center + ≥2 corners on a plane.
    if (tracked != _areaTracked) {
      _areaTracked = tracked;
      notifyListeners();
      _updateGuidance();
    }
  }

  // ═════════════════════════════════════════════════════════════
  // GUIDANCE
  // ═════════════════════════════════════════════════════════════

  void _updateGuidance() {
    if (_disposed) return;
    if (_scanActive) return; // Don't clobber guidance while a scan is running
    if (_stepPending) return; // Keep the "capture the SIDE view" coaching text

    final assessment = assessTracking(
      trackingState: _trackingState == ArTrackingState.tracking
          ? 1.0
          : _trackingState == ArTrackingState.limited
              ? 0.5
              : 0.0,
      planeDetected: _planeDetected,
      // §2: readiness now hinges on the guide-box AREA being tracked, not
      // merely any plane existing somewhere in the scene.
      areaTracked: _areaTracked,
      sessionDuration: _arCore.isSessionActive
          ? const Duration(seconds: 3) // Approximate
          : Duration.zero,
    );

    _guidanceText = assessment.message;
    _guidanceState = assessment.ready ? 'ready' : assessment.state;
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════
  // SCANNING
  // ═════════════════════════════════════════════════════════════

  void startScan() {
    if (_trackingState != ArTrackingState.tracking) return;
    // §2: only start when the guide-box region itself is on a tracked plane.
    if (!_areaTracked) {
      // Coach instead of silently no-oping — this happens right after a step
      // transition when the new guide-box position isn't mapped yet (the
      // 'ready' state was set by _endScan while _stepPending blocked
      // _updateGuidance from flipping it back to 'searching').
      // Clear _stepPending so _updateGuidance() (triggered by the 500ms
      // area tracker) can restore 'ready' once the box area gets tracked —
      // otherwise the UI would be stuck on 'searching' forever.
      _stepPending = false;
      _guidanceState = 'searching';
      _guidanceText =
          'Point the guide box at the floor — move your phone slowly so the area is tracked';
      notifyListeners();
      return;
    }

    _scanActive = true;
    _scanStartTime = DateTime.now();
    _currentSampleCount = 0;
    _validDetectionsThisPass = 0;
    _footDetected = false;
    _lastDetection = null; // Clear stale overlay points from prior scan/foot
    _liveLengthMm = null; // Clear stale live readout from prior scan/foot
    _liveWidthMm = null;
    _noFootScanFailure = false;
    _attemptsThisPass = 0; // §8 stall detection resets per pass
    _stallPromptShown = false;
    _temporalGate.reset();
    _guidanceState = 'scanning';
    _guidanceText = _stepGuidanceText();
    _stepPending = false; // A step is now running
    notifyListeners();

    // Collect samples at regular intervals
    _sampleTimer = Timer.periodic(
      Duration(milliseconds: sampleIntervalMs),
      (_) => _collectSample(),
    );

    // End scan after the configured duration
    Timer(scanDuration, () {
      if (!_disposed && _scanActive) {
        _endScan();
      }
    });

    // §8 stall detection now runs inside [_collectSample] — see
    // [_maybeShowStallPrompt]. An attempts-based check can never outlive the
    // scan window the way the previous wall-clock timer did.
  }

  /// Coaching text for the current capture step (§2.2/§2.5).
  String _stepGuidanceText() {
    final foot = _currentFoot == 0 ? 'left' : 'right';
    if (_captureStep == 'front') {
      return 'Top view: hold phone ~30cm above your $foot foot and fit it in the box';
    }
    return 'Side view: hold phone beside your $foot foot — heel to toe in the box';
  }

  Future<void> _collectSample() async {
    if (!_scanActive || _scanStartTime == null) return;
    if (_sampleInProgress) return; // No overlapping sample collection
    _sampleInProgress = true;

    try {
      // Get current ARCore tracking quality
      final trackingQuality = _trackingState == ArTrackingState.tracking
          ? 1.0
          : _trackingState == ArTrackingState.limited
              ? 0.5
              : 0.0;

      // ── 1. Acquire the current camera frame (NV21) from ARCore ──
      // The native side caches a throttled CPU frame from ARCore's separate
      // image stream (alongside the GPU texture used for the live preview).
      final frame = await _arCore.acquireCameraFrame();
      if (frame == null || frame.nv21Bytes.isEmpty) {
        _lastDetection = null; // No frame — don't show stale overlay points
        _setLiveMeasurement(); // No frame — clear the live readout too
        _setFootDetectionState(false);
        return;
      }

      // Remember frame geometry for the debug overlay coordinate mapping.
      _lastFrameWidth = frame.width;
      _lastFrameHeight = frame.height;
      _lastFrameRotation = frame.rotationDegrees;

      // ── 2. Run on-device foot detection on this sampled frame ──
      final detector = _detector;
      if (detector == null) return;

      final detection = await detector.detect(
        nv21Bytes: frame.nv21Bytes,
        width: frame.width,
        height: frame.height,
        rotationDegrees: frame.rotationDegrees,
        // Strict gating: only accept the foot being scanned (§4).
        preferSide: _currentFoot == 0 ? 'left' : 'right',
        // §2.3: mask must substantially overlap the current guide box.
        guideRect: currentGuideRect,
      );

      _sampleDebug(
        'frame=${frame.width}x${frame.height} rot=${frame.rotationDegrees} '
        '→ detect=${detection.footDetected ? 'OK' : 'FAIL'} '
        'conf=${detection.confidence.toStringAsFixed(2)} '
        'side=${detection.footSide ?? '-'} '
        'H=${detection.heelPoint?.asOffset} T=${detection.toePoint?.asOffset} '
        'widthPts=${detection.widthPoints?.length ?? 0}',
      );

      // ── 3. Score-based acceptance gate (§1 of the overhaul brief) ──
      // `footDetected` now reflects the COMBINED sample-quality score
      // (segmentation + shape + containment sub-scores weighted together,
      // compared to kSampleAcceptScore) instead of a strict AND-chain of
      // binary gates. A frame below threshold contributes NOTHING. Raycast
      // failure below still hard-rejects (a sample with no 3D position is
      // fundamentally unusable regardless of score).
      final rawValid = detection.footDetected &&
          detection.heelPoint != null &&
          detection.toePoint != null;

      _sampleDebug(
        'score=${detection.qualityScore.toStringAsFixed(2)} '
        '(seg=${detection.segmentationScore.toStringAsFixed(2)}, '
        'shape=${detection.shapeScore.toStringAsFixed(2)}, '
        'cont=${detection.containmentScore.toStringAsFixed(2)})',
      );

      // §1.5 temporal consistency applied to the SCORE: a single lucky frame
      // must not flip the detection state — require a few CONSECUTIVE frames
      // whose combined quality score clears the threshold before recording
      // samples. This also smooths the UI chip (no flicker).
      final confirmed = _temporalGate.update(rawValid);

      if (!rawValid) {
        // Dev diagnostic: log the detected/rejected side + confidence so
        // device testing can reveal how reliably the model labels the foot
        // (per §2.1 caveat). Repeated `rejected='right'` while scanning left
        // points at a side-labeling problem, not a "no foot" problem.
        debugPrint(
          '[ArScan] No foot (side=${detection.footSide}, '
          'rejected=${detection.rejectedFootSide}, '
          'conf=${detection.confidence.toStringAsFixed(2)}) — frame skipped',
        );
        _sampleDebug('raw=REJECT (see mask trace above) temporal=$confirmed');
        _lastDetection = null; // Clear overlay — no valid foot this frame
        _setLiveMeasurement(); // No valid foot — clear the live readout too
        // §1.2 hysteresis: a single bad frame must NOT flip the chip off.
        // `confirmed` was already updated with rawValid=false, so it holds
        // true until clearAfter consecutive negatives — that's what drives
        // the UI state (anti-flicker).
        _setFootDetectionState(confirmed);
        return;
      }

      _lastDetection = detection;
      _setFootDetectionState(confirmed);

      // ── 4. Convert 2D detection points to 3D world via ARCore hitTest ──
      final screenPoints = <Offset>[
        detection.heelPoint!.asOffset,
        detection.toePoint!.asOffset,
        ...?detection.widthPoints?.map((p) => p.asOffset),
      ];
      final worldPoints = await _arCore.hitTestBatch(screenPoints: screenPoints);
      final raycastHit = worldPoints.length >= 2 &&
          worldPoints[0] != null &&
          worldPoints[1] != null;

      // ── 5. Compute real-world measurements (meters → mm) ──
      // Computed for EVERY raw-valid frame — even before temporal
      // confirmation — so the live cm readout (§2) updates continuously during
      // capture using the same raycast math the samples use. Only CONFIRMED
      // frames record a sample below.
      double? lengthMm;
      double? widthMm;
      if (raycastHit) {
        final len = worldPoints[0]!.distanceTo(worldPoints[1]!) * 1000;
        final wid = (worldPoints.length >= 4 &&
                worldPoints[2] != null &&
                worldPoints[3] != null)
            // Widest-point pair provided by the detector (segmentation)
            ? worldPoints[2]!.distanceTo(worldPoints[3]!) * 1000
            // No width landmarks — proportional estimate
            : len * 0.38;
        lengthMm = len;
        widthMm = wid;
        _setLiveMeasurement(lengthMm: len, widthMm: wid);
        _sampleDebug('raycast=OK len=${len.toStringAsFixed(1)}mm '
            'wid=${wid.toStringAsFixed(1)}mm');
      } else {
        _setLiveMeasurement(); // Raycast missed the floor plane
        // hitTestBatch fills misses with null (list length is preserved), so
        // count NON-NULL entries — this distinguishes "no plane hits at all"
        // from "some hits but <2 landed on heel/toe" (small tracked-plane /
        // isPoseInPolygon issue, §2.3 of the diagnostic prompt).
        final nonNullHits = worldPoints.whereType<ArWorldPoint>().length;
        _sampleDebug('raycast=REJECT ($nonNullHits/${screenPoints.length} '
            'points hit the floor plane, expected ≥2 non-null)');
      }

      // Not yet temporally confirmed — wait for consecutive positive frames.
      // (The live readout above already updated, so it's not blank during the
      // confirmation window — §2.1.)
      if (!confirmed) {
        debugPrint(
          '[ArScan] Foot present, confirming (streak=${_temporalGate.positiveStreak})',
        );
        return;
      }

      _validDetectionsThisPass++;

      _sampleDebug(
        'temporal=OK streak=${_temporalGate.positiveStreak} '
        'confirmed=$_validDetectionsThisPass',
      );
      debugPrint(
        '[ArScan] Confirmed (side=${detection.footSide}, '
        'conf=${detection.confidence.toStringAsFixed(2)})',
      );

      if (!raycastHit) return; // Raycast missed the floor plane — no sample

      // Sanity bounds: reject degenerate measurements
      if (lengthMm == null ||
          widthMm == null ||
          lengthMm <= 0 ||
          lengthMm > 500 ||
          widthMm <= 0 ||
          widthMm > 200) {
        _sampleDebug('sanity=REJECT (len=${lengthMm?.toStringAsFixed(1) ?? '-'}mm '
            'wid=${widthMm?.toStringAsFixed(1) ?? '-'}mm, bounds 0-500/0-200)');
        return;
      }

      final sample = MeasurementSample(
        lengthMm: lengthMm,
        widthMm: widthMm,
        trackingQuality: trackingQuality,
        segmentationConfidence: detection.confidence,
        timestamp: DateTime.now(),
        captureAngle: _captureStep,
      );

      if (_currentFoot == 0) {
        _leftSamples.add(sample);
      } else {
        _rightSamples.add(sample);
      }

      _sampleDebug('sample=RECORDED total=${_leftSamples.length + _rightSamples.length}');
      if (!_disposed) {
        _currentSampleCount++;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ArScan] Sample collection error: $e');
    } finally {
      _sampleInProgress = false;
      // §8 stall detection: this tick attempted one frame (or hit a persistent
      // no-frame/no-detection state). Counting here means every code path
      // through [_collectSample] feeds the stall check exactly once.
      _attemptsThisPass++;
      _maybeShowStallPrompt();
    }
  }

  /// §8 stall fallback: once enough frames have been ATTEMPTED this pass with
  /// zero confirmed detections, coach the user toward Guided Tap.
  ///
  /// Deliberately non-destructive: the pass keeps running (a late recovery can
  /// still record samples) and the guidance state stays 'scanning' so the
  /// progress ring, guide box and live readout are not torn down mid-pass.
  /// Shown at most once per pass; the post-failure error UI offers the actual
  /// switch button when the pass ends empty.
  void _maybeShowStallPrompt() {
    if (!_scanActive ||
        _disposed ||
        _stallPromptShown ||
        _validDetectionsThisPass > 0 ||
        _attemptsThisPass < _stallAfterAttempts) {
      return;
    }
    _stallPromptShown = true;
    _guidanceText =
        'Having trouble detecting your foot? Try Guided Tap instead.';
    notifyListeners();
  }

  /// Update the live foot-detection indicator state.
  void _setFootDetectionState(bool detected) {
    if (_disposed) return;
    _footDetected = detected;
    notifyListeners();
  }

  /// Update the live measurement preview values (§2 of the extraction-fix
  /// brief).
  ///
  /// [lengthMm]/[widthMm] are the most recent frame's raw world measurements
  /// (mm). Omit both to clear the readout (no foot / no raycast this frame).
  void _setLiveMeasurement({double? lengthMm, double? widthMm}) {
    if (_disposed) return;
    _liveLengthMm = lengthMm;
    _liveWidthMm = widthMm;
    notifyListeners();
  }

  /// TEMP-DEBUG: emit a stage log line for the 0-samples diagnosis
  /// (ZERO_SAMPLES_DIAGNOSTIC_PROMPT §1). Remove after diagnosis.
  void _sampleDebug(String msg) {
    if (_kSampleDebugLogging) {
      debugPrint('[SAMPLE-DEBUG] $msg');
    }
  }

  /// Re-run the current capture step after a failed pass.
  void retryScan() {
    if (_disposed) return;
    _noFootScanFailure = false;
    notifyListeners();
    _updateGuidance(); // Restore ready/searching state
    if (_areaTracked && _trackingState == ArTrackingState.tracking) {
      startScan();
    }
  }

  /// §8: Stall fallback — the screen navigates to Guided Tap mode carrying
  /// over the already-selected foot/side/options so the user doesn't restart.

  void _endScan() {
    _sampleTimer?.cancel();

    // ── §4/§1.3: If NO frame in this capture pass produced a shape-validated
    // AND temporally confirmed foot detection, fail explicitly instead of
    // silently proceeding with an empty sample set. This is also the
    // acceptance check for the false-positive fix (empty surface → consistently
    // "no foot detected").
    if (_validDetectionsThisPass == 0) {
      _scanActive = false;
      _noFootScanFailure = true;
      _guidanceState = 'error';
      _guidanceText = "We couldn't detect a foot — make sure your foot is fully inside the guide box and try again";
      notifyListeners();
      return;
    }

    // ── §2.5: Front capture done → advance to the side capture for the same foot ──
    if (_captureStep == 'front') {
      _captureStep = 'side';
      _scanActive = false;
      _stepPending = true;
      _guidanceState = 'ready';
      // §2: the new guide-box position must be re-verified against a
      // tracked plane before the next capture can start (no stale-true
      // from the previous angle). The 500ms area tracker re-checks.
      _areaTracked = false;
      _guidanceText = _currentFoot == 0
          ? 'Top view done! Now capture the SIDE of your left foot'
          : 'Top view done! Now capture the SIDE of your right foot';
      notifyListeners();
      return;
    }

    // ── Side capture done → finalize this foot via per-angle combination (§2.4) ──
    _scanActive = false;
    _guidanceState = 'processing';
    _guidanceText = 'Processing measurement...';
    notifyListeners();

    final samples = _currentFoot == 0 ? _leftSamples : _rightSamples;
    final result = combineGuidedSamples(samples);

    if (result == null) {
      _guidanceState = 'ready';
      _guidanceText = 'Measurement failed — please try again';
      notifyListeners();
      _eventController.add(const SideCombineFailedEvent());
      return;
    }

    // If this was the left foot, move to right foot
    if (_currentFoot == 0) {
      _currentFoot = 1;
      _captureStep = 'front';
      _currentSampleCount = 0;
      _stepPending = true;
      _guidanceState = 'ready';
      // §2: re-verify the right-foot guide-box area against a tracked plane.
      _areaTracked = false;
      _guidanceText = 'Left foot done! Now scan your right foot';
      notifyListeners();

      _eventController.add(LeftFootDoneEvent(lengthMm: result.lengthMm));
    } else {
      // Both feet done — compute results and let the screen navigate
      _finishBothFeet();
    }
  }

  /// Both feet done: combine both sample sets, apply compensation/sizing
  /// math, and emit [ScanCompletedEvent] carrying every `FootResultsScreen`
  /// argument. Previously ran inline in `_navigateToResults`.
  void _finishBothFeet() {
    _isProcessing = true;
    _processingStep = 'Combining measurements...';
    notifyListeners();

    final leftResult = combineGuidedSamples(_leftSamples);
    final rightResult = combineGuidedSamples(_rightSamples);

    if (leftResult == null && rightResult == null) {
      _isProcessing = false;
      _guidanceState = 'ready';
      _guidanceText = 'Both scans failed — please try again';
      notifyListeners();
      return;
    }

    // §4: Apply sock-thickness compensation.
    final isSocks = footCondition == 'socks';
    final leftLengthComp = applySockCompensation(
        leftResult?.lengthMm ?? 0, isLength: true, isSocks: isSocks);
    final leftWidthComp = applySockCompensation(
        leftResult?.widthMm ?? 0, isLength: false, isSocks: isSocks);
    final rightLengthComp = applySockCompensation(
        rightResult?.lengthMm ?? 0, isLength: true, isSocks: isSocks);
    final rightWidthComp = applySockCompensation(
        rightResult?.widthMm ?? 0, isLength: false, isSocks: isSocks);

    // §3: Determine sizing foot (longer foot wins). Use compensated lengths.
    final sizingSide = (leftLengthComp >= rightLengthComp) ? 'left' : 'right';
    final sizingLengthMm = sizingSide == 'left' ? leftLengthComp : rightLengthComp;
    final euSize = footLengthMmToEuSize(sizingLengthMm);
    final usSize =
        euSize != null ? euToUs(euSize, category: shoeCategory) : null;
    final ukSize = euSize != null ? euToUk(euSize) : null;

    // §6: Width-to-fit category.
    final sizingWidthMm = sizingSide == 'left' ? leftWidthComp : rightWidthComp;
    final widthCategory = widthMmToFitCategory(sizingWidthMm, sizingLengthMm);

    // Compute overall confidence
    final leftConf = leftResult?.confidenceScore ?? 0.0;
    final rightConf = rightResult?.confidenceScore ?? 0.0;
    final overallConf = (leftConf + rightConf) / 2;
    final confLevel = overallConf >= 0.75 ? 'high'
        : overallConf >= 0.45 ? 'medium'
        : 'low';

    // §A.4: Generate size recommendation reasoning.
    final reason = euSize != null
        ? generateSizeRecommendationReason(
            compensatedLengthMm: sizingLengthMm,
            euSize: euSize,
            measurementSource: 'ar_auto_scan',
            confidenceLevel: confLevel,
          )
        : null;

    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] AutoScanController emitting ScanCompletedEvent '
        '(disposed=$_disposed, samples L=${_leftSamples.length} '
        'R=${_rightSamples.length})');
    _eventController.add(ScanCompletedEvent(
      payload: AutoScanResultsPayload(
        footSide: 'both',
        footLengthMm: leftResult?.lengthMm ?? 0,
        footWidthMm: leftResult?.widthMm ?? 0,
        footLengthRightMm: rightResult?.lengthMm,
        footWidthRightMm: rightResult?.widthMm,
        euSize: euSize,
        usSize: usSize,
        ukSize: ukSize,
        paperSize: 'ar',
        footCondition: footCondition,
        paperConfidence: overallConf,
        lightingQuality: 0.9,
        confidenceLevel: confLevel,
        confidenceScore: overallConf,
        leftSampleCount: leftResult?.finalSampleCount ?? 0,
        rightSampleCount: rightResult?.finalSampleCount ?? 0,
        measurementSource: 'ar_auto_scan',
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
    _sampleTimer?.cancel();
    _areaCheckTimer?.cancel();
    _detector?.dispose();
    // D1 fix: no explicit session teardown here — native teardown is
    // single-owned by Flutter's PlatformView disposal when the AR widget
    // unmounts. A Dart-initiated stopSession() could land after the next
    // screen's view registered natively, destroying it mid-creation.
    _eventController.close();
    super.dispose();
  }
}
