import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../services/ar_core_channel.dart';
import '../../utils/ar_foot_measurement_pipeline.dart';
import '../../utils/foot_detector.dart';
import '../../utils/foot_measurement_utils.dart';
import '../../utils/mlkit_segmentation_foot_detector.dart';
import 'foot_results_screen.dart';

/// Live AR foot scanning screen.
///
/// Uses ARCore world tracking (visual-inertial odometry) to measure
/// the user's foot in real-world coordinates without any paper reference.
///
/// Guided two-angle capture (§2 of the guided-capture brief):
/// 1. Tracking initialization — wait for floor plane detection
/// 2. Left foot: FRONT (top-down) capture → width
/// 3. Left foot: SIDE (profile) capture → length
/// 4. Right foot: same two captures
/// 5. Statistical combination — compute final measurements
/// 6. Navigate to results screen
///
/// Each capture shows an on-screen guide box (drawn on the preview). Samples
/// are only recorded when the shape-validated foot mask substantially
/// overlaps the guide box (§2.3), so every accepted sample is captured under
/// near-identical geometric conditions. The mask coordinates are projected
/// onto the 3D floor plane via hitTest to get real-world measurements in mm.
class FootArScanScreen extends StatefulWidget {
  final String footCondition; // 'bare' or 'socks'

  const FootArScanScreen({
    super.key,
    required this.footCondition,
  });

  @override
  State<FootArScanScreen> createState() => _FootArScanScreenState();
}

class _FootArScanScreenState extends State<FootArScanScreen>
    with TickerProviderStateMixin {
  // Live-readout plausibility bounds (cm, §2.3 of the extraction-fix brief).
  // Broader than the sampling sanity bounds so a real foot is never hidden,
  // but absurd values (e.g. a toe point landing on someone's leg) show a
  // "measuring…" placeholder instead of a nonsense number.
  static const double _minPlausibleLiveLengthCm = 10;
  static const double _maxPlausibleLiveLengthCm = 40;
  static const double _minPlausibleLiveWidthCm = 4;
  static const double _maxPlausibleLiveWidthCm = 18;

  /// TEMP-DEBUG: stage-by-stage sample pipeline logging for the "Foot
  /// detected but 0 samples" diagnosis (§1 of ZERO_SAMPLES_DIAGNOSTIC_PROMPT).
  /// Set false to silence. Remove after diagnosis.
  static const bool _kSampleDebugLogging = true;

  // ── ARCore State ──
  final ArCoreChannel _arCore = ArCoreChannel.instance;
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


  // ── Detection State (§4 of FOOT_DETECTION_SEGMENTATION_PROMPT) ──
  // On-device foot detector (ML Kit Pose today; segmentation can be swapped
  // in via the FootDetector interface without touching this screen).
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

  // ── Debug Detection Overlay ──
  // The most recent detection result, rendered as an overlay on the camera
  // preview so device testing can visually verify that the extracted
  // heel/toe/width points actually align with the foot in the camera feed
  // (validates the mask↔preview coordinate mapping end-to-end).

  /// Most recent detection result (or null if none yet).
  FootDetectionResult? _lastDetection;

  /// Dimensions of the frame [FootDetectionResult] was computed from, needed
  /// to map normalized mask coordinates onto the (center-cropped) preview.
  int _lastFrameWidth = 0;
  int _lastFrameHeight = 0;
  int _lastFrameRotation = 0;

  /// Whether the debug overlay is drawn on the camera preview.
  bool _showDebugOverlay = true;

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

  // ── Live Measurement Preview (§2 of the extraction-fix brief) ──
  // Per-frame real-world measurements computed during capture, shown live
  // near the guide box as an at-a-glance readout. Doubles as a diagnostic
  // signal: a wildly unstable/implausible number while a real foot is clearly
  // in frame points at extraction trouble (§2.2).
  double? _liveLengthMm;
  double? _liveWidthMm;

  /// Guide box for the current capture step (normalized upright-frame coords).
  Rect get _currentGuideRect =>
      _captureStep == 'front' ? kFrontCaptureGuideRect : kSideCaptureGuideRect;

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

  // ── Animations ──
  late AnimationController _pulseController;
  late AnimationController _progressController;

  // ── UI State ──
  String _guidanceText = 'Initializing AR...';
  String _guidanceState = 'initializing'; // 'initializing', 'searching', 'ready', 'scanning', 'done'

  /// True when a capture step just completed and the app is waiting for the
  /// user to start the next step (front → side, or left → right foot).
  /// Guards [_updateGuidance] from overwriting the step-complete coaching
  /// text when ARCore tracking/plane events fire between steps (the two-step
  /// flow makes the inter-step instruction critical, §2.5).
  bool _stepPending = false;

  StreamSubscription<ArSessionEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _progressController = AnimationController(
      duration: scanDuration,
      vsync: this,
    );

    _initializeSession();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _sampleTimer?.cancel();
    _areaCheckTimer?.cancel();
    _detector?.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    _arCore.stopSession();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════

  Future<void> _initializeSession() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _guidanceText = 'Camera permission is required for AR scanning';
          _guidanceState = 'error';
        });
      }
      return;
    }

    // Initialize the on-device foot detector.
    // Segmentation fallback (FULL REPLACEMENT per §2.3 of the fix brief):
    // ML Kit Pose proved inconsistent on tight foot-only crops (its person
    // detector needs body context), so the segmentation-based detector is now
    // the sole detection path. Gating/measurement logic is unchanged — it
    // consumes the same FootDetectionResult contract via the FootDetector
    // interface. The pose detector remains in the repo only for §1
    // diagnostic comparison; it is not instantiated here.
    _detector = MlKitSegmentationFootDetector();

    // Start ARCore session
    final started = await _arCore.startSession();
    if (!started) {
      if (mounted) {
        setState(() {
          _guidanceText = 'Failed to start AR session. Is ARCore installed?';
          _guidanceState = 'error';
        });
      }
      return;
    }

    if (!mounted) return; // Popped during init — don't register timers/events

    // Listen for ARCore events
    _eventSubscription = _arCore.events.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case 'tracking':
          final state = event.data['state']?.toString() ?? 'paused';
          setState(() {
            _trackingState = state == 'tracking'
                ? ArTrackingState.tracking
                : state == 'limited'
                    ? ArTrackingState.limited
                    : ArTrackingState.paused;
          });
          _checkAreaTracked(); // Re-verify the box region after tracking changes
          _updateGuidance();
          break;

        case 'plane':
          setState(() => _planeDetected = true);
          _checkAreaTracked(); // Is the box area actually on this plane?
          _updateGuidance();
          break;

        case 'error':
          final msg = event.data['message']?.toString() ?? 'Unknown error';
          setState(() {
            _guidanceText = msg;
            _guidanceState = 'error';
          });
          break;
      }
    });

    // §2 localized plane tracking: poll whether the guide-box region is
    // covered by a tracked plane. ARCore planes grow incrementally, so keep
    // re-checking while the user positions the phone — readiness flips on as
    // soon as the box area is mapped, no full-room mapping required.
    _areaCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkAreaTracked(),
    );
  }

  /// §2 localized plane tracking: verify a tracked plane actually covers the
  /// guide-box region by hit-testing its center + corners. The box area is
  /// "tracked" when the center (and most corners) land on the floor plane —
  /// this is what gates capture readiness, replacing the old "any plane
  /// exists" check.
  Future<void> _checkAreaTracked() async {
    if (!mounted || _scanActive) return;
    if (!_arCore.isSessionActive) return;

    final rect = _currentGuideRect;
    final probePoints = <Offset>[
      rect.center,
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    final hits = await _arCore.hitTestBatch(screenPoints: probePoints);
    if (!mounted) return;
    final onPlane = hits.whereType<ArWorldPoint>().length;
    final tracked = onPlane >= 3; // Center + ≥2 corners on a plane.
    if (tracked != _areaTracked) {
      setState(() => _areaTracked = tracked);
      _updateGuidance();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GUIDANCE
  // ═══════════════════════════════════════════════════════════════

  void _updateGuidance() {
    if (!mounted) return;
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

    setState(() {
      _guidanceText = assessment.message;
      _guidanceState = assessment.ready ? 'ready' : assessment.state;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // SCANNING
  // ═══════════════════════════════════════════════════════════════

  void _startScan() {
    if (_trackingState != ArTrackingState.tracking) return;
    // §2: only start when the guide-box region itself is on a tracked plane.
    if (!_areaTracked) {
      // Coach instead of silently no-oping — this happens right after a step
      // transition when the new guide-box position isn't mapped yet (the
      // 'ready' state was set by _endScan while _stepPending blocked
      // _updateGuidance from flipping it back to 'searching').
      setState(() {
        // Clear _stepPending so _updateGuidance() (triggered by the 500ms
        // area tracker) can restore 'ready' once the box area gets tracked —
        // otherwise the UI would be stuck on 'searching' forever.
        _stepPending = false;
        _guidanceState = 'searching';
        _guidanceText =
            'Point the guide box at the floor — move your phone slowly so the area is tracked';
      });
      return;
    }

    setState(() {
      _scanActive = true;
      _scanStartTime = DateTime.now();
      _currentSampleCount = 0;
      _validDetectionsThisPass = 0;
      _footDetected = false;
      _lastDetection = null; // Clear stale overlay points from prior scan/foot
      _liveLengthMm = null; // Clear stale live readout from prior scan/foot
      _liveWidthMm = null;
      _noFootScanFailure = false;
      _temporalGate.reset();
      _guidanceState = 'scanning';
      _guidanceText = _stepGuidanceText();
      _stepPending = false; // A step is now running
    });

    _progressController.forward(from: 0);

    // Collect samples at regular intervals
    _sampleTimer = Timer.periodic(
      Duration(milliseconds: sampleIntervalMs),
      (_) => _collectSample(),
    );

    // End scan after the configured duration
    Timer(scanDuration, () {
      if (mounted && _scanActive) {
        _endScan();
      }
    });
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
        guideRect: _currentGuideRect,
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
      if (mounted) setState(() => _currentSampleCount++);
    } catch (e) {
      debugPrint('[ArScan] Sample collection error: $e');
    } finally {
      _sampleInProgress = false;
    }
  }

  /// Update the live foot-detection indicator state.
  void _setFootDetectionState(bool detected) {
    if (!mounted) return;
    setState(() {
      _footDetected = detected;
    });
  }

  /// Update the live measurement preview values (§2 of the extraction-fix
  /// brief).
  ///
  /// [lengthMm]/[widthMm] are the most recent frame's raw world measurements
  /// (mm). Omit both to clear the readout (no foot / no raycast this frame).
  void _setLiveMeasurement({double? lengthMm, double? widthMm}) {
    if (!mounted) return;
    setState(() {
      _liveLengthMm = lengthMm;
      _liveWidthMm = widthMm;
    });
  }

  /// TEMP-DEBUG: emit a stage log line for the 0-samples diagnosis
  /// (ZERO_SAMPLES_DIAGNOSTIC_PROMPT §1). Remove after diagnosis.
  void _sampleDebug(String msg) {
    if (_kSampleDebugLogging) {
      debugPrint('[SAMPLE-DEBUG] $msg');
    }
  }

  /// Live cm measurement readout text for the current capture step (§2).
  ///
  /// Shows the dimension each angle is primarily measuring — WIDTH for the
  /// FRONT/top-down capture, LENGTH for the SIDE/profile capture — computed
  /// from the most recent sampled frame via the same AR raycast used for
  /// samples. Values outside a broad plausible human-foot range (or an
  /// unavailable/absent foot) show a "measuring…" placeholder rather than a
  /// nonsense number (§2.3) — e.g. a toe point landing on someone's leg would
  /// show "measuring…" instead of an implausible length.
  String? _liveMeasureText() {
    if (_guidanceState != 'scanning') return null; // Only during live capture
    final isFront = _captureStep == 'front';
    final valueMm = isFront ? _liveWidthMm : _liveLengthMm;
    if (valueMm == null) return 'measuring…';
    final cm = valueMm / 10;
    final minCm =
        isFront ? _minPlausibleLiveWidthCm : _minPlausibleLiveLengthCm;
    final maxCm =
        isFront ? _maxPlausibleLiveWidthCm : _maxPlausibleLiveLengthCm;
    if (cm < minCm || cm > maxCm) return 'measuring…';
    final label = isFront ? 'Width' : 'Length';
    return '$label: ~${cm.toStringAsFixed(1)}cm';
  }

  /// Re-run the current capture step after a failed pass.
  void _retryScan() {
    if (!mounted) return;
    setState(() => _noFootScanFailure = false);
    _updateGuidance(); // Restore ready/searching state
    if (_areaTracked && _trackingState == ArTrackingState.tracking) {
      _startScan();
    }
  }

  void _endScan() {
    _sampleTimer?.cancel();
    _progressController.stop();

    // ── §4/§1.3: If NO frame in this capture pass produced a shape-validated
    // AND temporally confirmed foot detection, fail explicitly instead of
    // silently proceeding with an empty sample set. This is also the
    // acceptance check for the false-positive fix (empty surface → consistently
    // "no foot detected").
    if (_validDetectionsThisPass == 0) {
      if (mounted) {
        setState(() {
          _scanActive = false;
          _noFootScanFailure = true;
          _guidanceState = 'error';
          _guidanceText = "We couldn't detect a foot — make sure your foot is fully inside the guide box and try again";
        });
      }
      return;
    }

    // ── §2.5: Front capture done → advance to the side capture for the same foot ──
    if (_captureStep == 'front') {
      if (mounted) {
        setState(() {
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
        });
      }
      return;
    }

    // ── Side capture done → finalize this foot via per-angle combination (§2.4) ──
    setState(() {
      _scanActive = false;
      _guidanceState = 'processing';
      _guidanceText = 'Processing measurement...';
    });

    final samples = _currentFoot == 0 ? _leftSamples : _rightSamples;
    final result = combineGuidedSamples(samples);

    if (result == null) {
      if (mounted) {
        setState(() {
          _guidanceState = 'ready';
          _guidanceText = 'Measurement failed — please try again';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Not enough valid samples. Hold steady and keep the foot inside the guide box.',
            ),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      return;
    }

    // If this was the left foot, move to right foot
    if (_currentFoot == 0) {
      setState(() {
        _currentFoot = 1;
        _captureStep = 'front';
        _currentSampleCount = 0;
        _stepPending = true;
        _guidanceState = 'ready';
        // §2: re-verify the right-foot guide-box area against a tracked plane.
        _areaTracked = false;
        _guidanceText = 'Left foot done! Now scan your right foot';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Left foot: ${result.lengthMm.toStringAsFixed(0)}mm — now scan right foot'),
          backgroundColor: AppConstants.success,
        ),
      );
    } else {
      // Both feet done — navigate to results
      _navigateToResults();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RESULTS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _navigateToResults() async {
    setState(() {
      _isProcessing = true;
      _processingStep = 'Combining measurements...';
    });

    final leftResult = combineGuidedSamples(_leftSamples);
    final rightResult = combineGuidedSamples(_rightSamples);

    if (leftResult == null && rightResult == null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _guidanceState = 'ready';
          _guidanceText = 'Both scans failed — please try again';
        });
      }
      return;
    }

    // Use the larger foot for size recommendation (standard convention)
    final lengthMm = _chooseLarger(leftResult?.lengthMm, rightResult?.lengthMm);
    final euSize = footLengthMmToEuSize(lengthMm);
    final usSize = euSize != null ? euToUs(euSize) : null;
    final ukSize = euSize != null ? euToUk(euSize) : null;

    // Compute overall confidence
    final leftConf = leftResult?.confidenceScore ?? 0.0;
    final rightConf = rightResult?.confidenceScore ?? 0.0;
    final overallConf = (leftConf + rightConf) / 2;
    final confLevel = overallConf >= 0.75 ? 'high'
        : overallConf >= 0.45 ? 'medium'
        : 'low';

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FootResultsScreen(
          footSide: 'both',
          footLengthMm: leftResult?.lengthMm ?? 0,
          footWidthMm: leftResult?.widthMm ?? 0,
          footLengthRightMm: rightResult?.lengthMm,
          footWidthRightMm: rightResult?.widthMm,
          euSize: euSize,
          usSize: usSize,
          ukSize: ukSize,
          paperSize: 'ar', // Live AR scan
          footCondition: widget.footCondition,
          paperConfidence: overallConf,
          lightingQuality: 0.9,
          confidenceLevel: confLevel,
          confidenceScore: overallConf,
          leftSampleCount: leftResult?.finalSampleCount ?? 0,
          rightSampleCount: rightResult?.finalSampleCount ?? 0,
        ),
      ),
    );
  }

  double _chooseLarger(double? a, double? b) {
    if (a == null) return b ?? 0;
    if (b == null) return a;
    return a > b ? a : b;
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── AR Camera Feed (PlatformView) ──
          _buildArView(),

          // ── Debug Detection Overlay (heel/toe/width points) ──
          if (_showDebugOverlay) _buildDebugOverlay(),

          // ── Guided Capture Guide Box (§2.3) ──
          if (_guidanceState == 'scanning' || _guidanceState == 'ready')
            _buildGuideBox(),

          // ── Guidance Overlay ──
          _buildGuidanceOverlay(),

          // ── Top Bar ──
          _buildTopBar(),

          // ── Bottom Bar ──
          _buildBottomBar(),

          // ── Processing Overlay ──
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildArView() {
    // PlatformView with hybrid composition for ARCore camera feed.
    // Uses PlatformViewLink + AndroidViewSurface (per debug prompt §5 — Check D)
    // to ensure the native GLSurfaceView renders the camera feed correctly
    // instead of showing a solid black screen.
    return SizedBox.expand(
      child: PlatformViewLink(
        viewType: 'ar_foot_scan',
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: 'ar_foot_scan',
            layoutDirection: TextDirection.ltr,
            creationParams: <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      ),
    );
  }

  /// Debug overlay that draws the extracted heel/toe/width points on the
  /// camera preview so on-device testing can verify the segmentation mask
  /// coordinates align with the real foot (the §6/§8 validation step).
  ///
  /// The native AR preview renders the camera with center-crop (fill): the
  /// full frame is scaled to cover the view, cropping the excess on one axis.
  /// Detection points are normalized to the FULL upright frame, so they must
  /// be re-projected through the same crop before drawing, or they'd drift
  /// from the real foot pixels near the cropped edges.
  Widget _buildDebugOverlay() {
    final detection = _lastDetection;
    if (detection == null ||
        !detection.footDetected ||
        detection.heelPoint == null ||
        detection.toePoint == null) {
      return const SizedBox.shrink();
    }

    final uprightW = (_lastFrameRotation % 180) == 90
        ? _lastFrameHeight
        : _lastFrameWidth;
    final uprightH = (_lastFrameRotation % 180) == 90
        ? _lastFrameWidth
        : _lastFrameHeight;

    // Draw the confidence readout below the top bar (which occupies
    // padding.top + 12, roughly 40px tall) so it isn't obscured.
    final textTop = MediaQuery.of(context).padding.top + 64;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DebugDetectionPainter(
            heel: detection.heelPoint!,
            toe: detection.toePoint!,
            widthPoints: detection.widthPoints,
            confidence: detection.confidence,
            frameWidth: uprightW,
            frameHeight: uprightH,
            textTop: textTop,
          ),
        ),
      ),
    );
  }

  /// Renders the on-screen guide box for the current capture step (§2.3).
  ///
  /// The box is defined in NORMALIZED upright-frame coordinates and must map
  /// through the same center-crop transform as the camera preview so it lines
  /// up with the same pixels the segmentation mask sees. During 'ready' it
  /// shows the target (before the user taps start); during 'scanning' it's the
  /// live alignment target.
  Widget _buildGuideBox() {
    final uprightW = (_lastFrameRotation % 180) == 90
        ? _lastFrameHeight
        : _lastFrameWidth;
    final uprightH = (_lastFrameRotation % 180) == 90
        ? _lastFrameWidth
        : _lastFrameHeight;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GuideBoxPainter(
            guideRect: _currentGuideRect,
            frameWidth: uprightW,
            frameHeight: uprightH,
            active: _guidanceState == 'scanning',
            label: _captureStep == 'front' ? 'TOP VIEW' : 'SIDE VIEW',
            liveText: _liveMeasureText(),
          ),
        ),
      ),
    );
  }

  Widget _buildGuidanceOverlay() {
    // Central guidance indicators
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tracking indicator
          if (_guidanceState == 'scanning') ...[
            SizedBox(
              width: 120,
              height: 120,
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  return CircularProgressIndicator(
                    value: _progressController.value,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation(AppConstants.accent),
                    strokeCap: StrokeCap.round,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '$_currentSampleCount samples',
              style: AppConstants.monoStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.accent,
              ),
            ),
          ] else if (_guidanceState == 'ready') ...[
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 16 + (_pulseController.value * 8),
                  height: 16 + (_pulseController.value * 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.success.withValues(
                      alpha: 0.6 - (_pulseController.value * 0.3),
                    ),
                  ),
                );
              },
            ),
          ] else if (_guidanceState == 'searching') ...[
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppConstants.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Foot indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.accessibility_new,
                  color: _currentFoot == 0 ? AppConstants.accent : AppConstants.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentFoot == 0 ? 'Left Foot' : 'Right Foot',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (_leftSamples.isNotEmpty && _currentFoot == 1) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, color: AppConstants.success, size: 16),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Capture step indicator (§2.5: two structured captures per foot)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _captureStep == 'front'
                  ? AppConstants.accent.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _captureStep == 'front'
                      ? Icons.arrow_drop_down_circle_outlined
                      : Icons.arrow_forward_rounded,
                  size: 14,
                  color: _captureStep == 'front'
                      ? AppConstants.accent
                      : AppConstants.success,
                ),
                const SizedBox(width: 4),
                Text(
                  _captureStep == 'front' ? 'TOP' : 'SIDE',
                  style: AppConstants.monoStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _captureStep == 'front'
                        ? AppConstants.accent
                        : AppConstants.success,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Debug overlay toggle
          GestureDetector(
            onTap: () => setState(() => _showDebugOverlay = !_showDebugOverlay),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _showDebugOverlay
                    ? AppConstants.accent.withValues(alpha: 0.85)
                    : Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _showDebugOverlay ? Icons.bug_report : Icons.bug_report_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Tracking status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _trackingState == ArTrackingState.tracking
                        ? AppConstants.success
                        : _trackingState == ArTrackingState.limited
                            ? Colors.amber
                            : AppConstants.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _trackingState == ArTrackingState.tracking
                      ? 'TRACKING'
                      : _trackingState == ArTrackingState.limited
                          ? 'LIMITED'
                          : 'OFF',
                  style: AppConstants.monoStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 20,
      left: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Guidance text
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _guidanceState == 'ready'
                        ? AppConstants.success
                        : _guidanceState == 'scanning'
                            ? AppConstants.accent
                            : Colors.white.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _guidanceText,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Live foot-detection status (§6 of FOOT_DETECTION_SEGMENTATION_PROMPT)
          if (_scanActive) _buildFootDetectionChip(),

          const SizedBox(height: 16),

          // Action button
          if (_guidanceState == 'ready' && !_scanActive)
            GestureDetector(
              onTap: _startScan,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppConstants.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.accent.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            )
          else if (_guidanceState == 'error')
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // §4/§6: explicit failure state with a real retry action
                if (_noFootScanFailure) ...[
                  FilledButton.icon(
                    onPressed: _retryScan,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try Again'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: Text(
                    'Go Back',
                    style: AppConstants.bodyStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Live foot-detection status chip shown while scanning.
  ///
  /// Reflects the most recent sampled frame's detection state in real time,
  /// doubling as user guidance ("reposition your foot") and as a debugging
  /// signal during development (§6 of the implementation brief).
  Widget _buildFootDetectionChip() {
    // §1: `_footDetected` is driven by the temporal gate on the COMBINED
    // quality score (≥ kSampleAcceptScore), so it's the authoritative signal
    // — a score-based acceptance model replaces the old binary confidence
    // check (which would disagree with the scoring under weighted gating).
    final detected = _footDetected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: detected
            ? AppConstants.success.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: detected
              ? AppConstants.success
              : Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            detected ? Icons.check_circle : Icons.visibility_off_outlined,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            detected
                ? 'Foot detected'
                : 'No foot detected — position your foot in frame',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 2,
              color: AppConstants.accent,
            ),
            const SizedBox(height: 16),
            Text(
              _processingStep,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the debug detection overlay on the camera preview.
///
/// Maps normalized (0–1) detection points from the FULL upright camera frame
/// onto the center-cropped preview using the same scale-and-crop math a
/// `BoxFit.cover` render applies:
///   scale = max(viewW/frameW, viewH/frameH)
///   then crop the overflowing axis and offset by the crop margin.
/// This mirrors how the native ARCore preview draws the camera texture, so
/// the drawn markers should sit on the actual foot pixels (the whole point
/// of this debug view).
class _DebugDetectionPainter extends CustomPainter {
  final FootPoint heel;
  final FootPoint toe;
  final List<FootPoint>? widthPoints;
  final double confidence;
  final int frameWidth;
  final int frameHeight;

  /// Y position of the confidence readout (below the top bar).
  final double textTop;

  const _DebugDetectionPainter({
    required this.heel,
    required this.toe,
    required this.widthPoints,
    required this.confidence,
    required this.frameWidth,
    required this.frameHeight,
    this.textTop = 12,
  });

  /// Map a normalized frame point (0–1) to a pixel on [size] using
  /// center-crop (fill) semantics — shared helper so the guide box and
  /// detection points always use identical geometry.
  Offset _toView(Offset normalized, Size size) => mapNormalizedToView(
        normalized,
        size,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final heelPos = _toView(heel.asOffset, size);
    final toePos = _toView(toe.asOffset, size);

    // ── Heel→toe axis line (length) ──
    final axisPaint = Paint()
      ..color = const Color(0xAA4CAF50)
      ..strokeWidth = 2.5;
    canvas.drawLine(heelPos, toePos, axisPaint);

    // ── Width pair line ──
    if (widthPoints != null && widthPoints!.length >= 2) {
      final w1 = _toView(widthPoints![0].asOffset, size);
      final w2 = _toView(widthPoints![1].asOffset, size);
      final widthPaint = Paint()
        ..color = const Color(0xAA42A5F5)
        ..strokeWidth = 2.5;
      canvas.drawLine(w1, w2, widthPaint);

      // Blue markers at each width point
      final wFill = Paint()..color = const Color(0xFF42A5F5);
      canvas.drawCircle(w1, 7, wFill);
      canvas.drawCircle(w2, 7, wFill);
      _drawLabel(canvas, w1, 'W');
      _drawLabel(canvas, w2, 'W');
    }

    // ── Heel marker (green) + label ──
    final heelFill = Paint()..color = const Color(0xFF4CAF50);
    canvas.drawCircle(heelPos, 8, heelFill);
    canvas.drawCircle(
      heelPos,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawLabel(canvas, heelPos, 'H');

    // ── Toe marker (orange/red) + label ──
    final toeFill = Paint()..color = const Color(0xFFF44336);
    canvas.drawCircle(toePos, 8, toeFill);
    canvas.drawCircle(
      toePos,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawLabel(canvas, toePos, 'T');

    // ── Confidence text (top-left) ──
    final confidenceText = TextPainter(
      text: TextSpan(
        text: 'conf ${(confidence * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 4),
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    confidenceText.paint(
      canvas,
      Offset(12, textTop),
    );
  }

  void _drawLabel(Canvas canvas, Offset center, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx + 10, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DebugDetectionPainter oldDelegate) {
    return oldDelegate.heel != heel ||
        oldDelegate.toe != toe ||
        oldDelegate.confidence != confidence ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.widthPoints != widthPoints ||
        oldDelegate.textTop != textTop;
  }
}

/// Paints the guided-capture bounding box (§2.3) on the camera preview.
///
/// The box is defined in normalized upright-frame coordinates and mapped onto
/// the center-cropped preview using the same transform as
/// [_DebugDetectionPainter], so it visually lines up with the same camera
/// pixels the segmentation mask is validated against.
class _GuideBoxPainter extends CustomPainter {
  final Rect guideRect;
  final int frameWidth;
  final int frameHeight;
  final bool active;
  final String label;

  /// Live cm measurement readout (e.g. "Width: ~10.2cm") drawn inside the
  /// top-left of the box during scanning; null hides it (§2.4).
  final String? liveText;

  const _GuideBoxPainter({
    required this.guideRect,
    required this.frameWidth,
    required this.frameHeight,
    required this.active,
    required this.label,
    this.liveText,
  });

  /// Map a normalized frame point (0–1) to a pixel on [size] using
  /// center-crop (fill) semantics — shared helper with the debug overlay.
  Offset _toView(Offset normalized, Size size) => mapNormalizedToView(
        normalized,
        size,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final tl = _toView(Offset(guideRect.left, guideRect.top), size);
    final br = _toView(Offset(guideRect.right, guideRect.bottom), size);
    final box = Rect.fromPoints(tl, br);
    final rrect = RRect.fromRectAndRadius(box, const Radius.circular(14));

    // ── Dim overlay outside the box (except inside) ──
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: active ? 0.25 : 0.15);
    final outer = Path()..addRect(Offset.zero & size)..addRRect(rrect);
    canvas.drawPath(Path.combine(PathOperation.difference, outer, Path()..addRRect(rrect)), dimPaint);

    // ── Box border ──
    final borderColor = active ? AppConstants.accent : Colors.white70;
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 3 : 2,
    );

    // ── Corner brackets ──
    final bracketPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const b = 20.0;
    canvas.drawLine(tl, Offset(tl.dx + b, tl.dy), bracketPaint);
    canvas.drawLine(tl, Offset(tl.dx, tl.dy + b), bracketPaint);
    canvas.drawLine(Offset(br.dx - b, br.dy), Offset(br.dx, br.dy), bracketPaint);
    canvas.drawLine(Offset(br.dx, br.dy - b), Offset(br.dx, br.dy), bracketPaint);

    // ── Label chip ──
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(tl.dx, (tl.dy - tp.height - 8).clamp(4, size.height - tp.height - 4)),
    );

    // ── Live measurement readout (§2 of the extraction-fix brief) ──
    // Drawn just inside the top-left of the box, behind a subtle dark pill so
    // it stays readable over any camera content. Secondary to the label chip
    // and coaching text by design.
    if (liveText != null && liveText!.isNotEmpty) {
      final liveTp = TextPainter(
        text: TextSpan(
          text: liveText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          tl.dx + 4,
          tl.dy + 10,
          liveTp.width + 14,
          liveTp.height + 8,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        bg,
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );
      liveTp.paint(canvas, Offset(tl.dx + 11, tl.dy + 14));
    }
  }

  @override
  bool shouldRepaint(covariant _GuideBoxPainter oldDelegate) {
    return oldDelegate.guideRect != guideRect ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.active != active ||
        oldDelegate.label != label ||
        oldDelegate.liveText != liveText;
  }
}
