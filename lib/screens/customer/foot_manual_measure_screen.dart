import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../services/ar_core_channel.dart';
import '../../utils/foot_detector.dart';
import '../../utils/foot_measurement_utils.dart';
import '../../utils/mlkit_segmentation_foot_detector.dart';
import 'foot_results_screen.dart';
import 'foot_wall_calibration_screen.dart' show WallReference;

/// Live AR manual tap-to-measure screen.
///
/// Fully manual measurement flow (MANUAL_MEASUREMENT_PIVOT_PROMPT): the user
/// taps to place the key points of their foot directly — no automatic
/// detection, segmentation, or confidence gating. The app's job is to track
/// the world accurately (ARCore), convert taps to real-world coordinates
/// (existing hitTest raycast), and get out of the way of the user's judgment.
///
/// Structure (reuses the dual-angle capture from the guided flow):
/// 1. Tracking initialization — localized floor-area tracking under the foot
/// 2. Left foot: FRONT (tap the two widest points) → width
/// 3. Left foot: SIDE (tap heel, then tip of longest toe) → length
/// 4. Right foot: same two pairs
/// 5. Navigate to results (length/width per foot, recommended size)
///
/// Interaction per pair:
/// - Tap to place point A. A line then draws from A to the center crosshair
///   with a live, continuously-updating cm value (matching the reference app's
///   "Add a point" crosshair pattern).
/// - Tap again to place point B and lock the measurement for that pair.
/// - Drag either point to adjust after placement — the distance label updates
///   live while dragging.
/// - Trash icon clears/redoes the current pair; Confirm advances the flow.
////// Taps that don't hit a tracked surface show a brief "can't measure there"
/// message and don't register a point (§3.3).
class FootManualMeasureScreen extends StatefulWidget {
  final String footCondition; // 'bare' or 'socks'

  /// Whether the optional smart-assist layer (§6) is enabled. When false, no
  /// background segmentation sampler runs and no suggestions are shown — the
  /// flow is fully manual. Defaults to true; the instructions screen exposes
  /// a toggle for this.
  final bool smartAssistEnabled;

  /// Shopping preference for EU→US conversion ('men', 'women', 'kids').
  final String shoeCategory;

  /// Optional wall-floor reference plane captured during calibration.
  /// When provided, measurements can be computed relative to this locked
  /// reference instead of ARCore's live floor estimate (reduces drift).
  final WallReference? wallReference;

  const FootManualMeasureScreen({
    super.key,
    required this.footCondition,
    this.smartAssistEnabled = true,
    this.shoeCategory = 'men',
    this.wallReference,
  });

  @override
  State<FootManualMeasureScreen> createState() => _FootManualMeasureScreenState();
}

/// A manually placed measurement point: on-screen view pixel + real-world hit.
class _ManualPoint {
  final Offset screen;
  final ArWorldPoint world;

  const _ManualPoint({required this.screen, required this.world});
}

class _FootManualMeasureScreenState extends State<FootManualMeasureScreen>
    with TickerProviderStateMixin {
  // ── Plausibility bounds (cm) for the live readout and confirm guard ──
  // Tiered: soft-warn (edge-case) and hard-reject (implausible) per §7.
  static const double _minPlausibleLengthCm = kHardRejectMinLengthCm;
  static const double _maxPlausibleLengthCm = kHardRejectMaxLengthCm;
  static const double _minPlausibleWidthCm = kHardRejectMinWidthCm;
  static const double _maxPlausibleWidthCm = kHardRejectMaxWidthCm;

  // ── ARCore State ──
  final ArCoreChannel _arCore = ArCoreChannel.instance;
  ArTrackingState _trackingState = ArTrackingState.paused;

  /// Cached camera-frame geometry, needed to invert the preview's center-crop
  /// so a tap (view pixels) becomes normalized upright-frame coordinates for
  /// the native hitTest.
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _frameRotation = 0;

  // ── Manual Point Placement State ──
  _ManualPoint? _pointA;
  _ManualPoint? _pointB;

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

  /// Burst sampling: number of hitTest samples to fire per tap for jitter
  /// smoothing. ~200ms window at typical frame rate.
  static const int _burstSampleCount = 5;
  /// Maximum spread (mm) across a burst sample before showing a soft hint.
  static const double _burstSpreadHintMm = 4.0;

  // ── Smart-Assist (§6 of MANUAL_MEASUREMENT_PIVOT_PROMPT) ──
  // The paused automatic detection is reused as an optional suggestion layer:
  // while the user waits to place the first point of a pair, a background
  // segmentation detector proposes the two initial positions (normalized →
  // view pixels via the shared center-crop transform). The user can accept
  // them — and drag-adjust with the exact same manual UI — or ignore them and
  // tap manually. Never blocks the manual flow.
  MlKitSegmentationFootDetector? _assistDetector;
  Timer? _assistTimer;
  bool _assistBusy = false;

  /// Proposed point positions in view pixels (suggestion markers + accept),
  /// plus the detection's quality score (0.0–1.0) so the user can gauge how
  /// trustworthy the proposal is before accepting.
  ({Offset a, Offset b, double confidence})? _suggestion;

  /// Last known preview size (captured in build) for the background sampler.
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

  // ── Processing / Navigation ──
  bool _isProcessing = false;
  String _processingStep = '';

  // ── Animations ──
  late AnimationController _pulseController;

  // ── UI State ──
  String _guidanceText = 'Initializing AR...';
  String _guidanceState =
      'initializing'; // 'initializing', 'searching', 'ready', 'error'

  StreamSubscription<ArSessionEvent>? _eventSubscription;

  // Periodic (cheap) guidance refresh — re-derives coaching copy from the
  // cached _trackingState without hit-testing or any area gate, so guidance
  // converges even if the first ARCore state-change event races past our
  // subscription at session start (broadcast streams drop un-listened events).
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

  // Geometry helpers for coordinate mapping.
  int get _uprightW =>
      (_frameRotation % 180) == 90 ? _frameHeight : _frameWidth;
  int get _uprightH =>
      (_frameRotation % 180) == 90 ? _frameWidth : _frameHeight;

  @override
  void initState() {
    super.initState();
    _logTiming('screen_opened');

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    // Lightweight guidance refresh (1s, no hit-testing). _updateGuidance
    // guards its own setState with change detection, so this is a no-op once
    // guidance has converged — it only exists to recover from a missed initial
    // tracking event. Taps are never gated on it.
    _guidanceRefreshTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateGuidance());

    _initializeSession();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _guidanceRefreshTimer?.cancel();
    _liveCenterTimer?.cancel();
    _feedbackTimer?.cancel();
    _assistTimer?.cancel();
    _assistDetector?.dispose();
    _pulseController.dispose();
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
          _guidanceText = 'Camera permission is required for AR measuring';
          _guidanceState = 'error';
        });
      }
      return;
    }

    // Start ARCore session (world tracking + plane detection only — no
    // detection models needed in the manual flow).
    final started = await _arCore.startSession();
    _logTiming('session_started');
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

    // Cache camera-frame geometry for tap→normalized coordinate mapping.
    _fetchFrameGeometry();

    // Listen for ARCore events
    _eventSubscription = _arCore.events.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case 'tracking':
          final state = event.data['state']?.toString() ?? 'paused';
          if (!_loggedFirstTracking && state == 'tracking') {
            _loggedFirstTracking = true;
            _firstTrackingMs = _timingWatch.elapsedMilliseconds;
            _logTiming('first_tracking');
          }
          setState(() {
            _trackingState = state == 'tracking'
                ? ArTrackingState.tracking
                : state == 'limited'
                    ? ArTrackingState.limited
                    : ArTrackingState.paused;
          });
          _updateGuidance();
          break;

        case 'plane':
          // Informational only in manual mode — taps resolve per-hitTest, so
          // there is no plane-coverage gate to refresh (REMOVE_FLOOR_SCAN_WAIT).
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

    // Smart-assist background sampler (§6): throttled + self-gating. While
    // the user is waiting to place the first point, propose an initial pair
    // from the paused segmentation detector. The user can accept it and
    // drag-adjust, or ignore it and tap manually. Skipped entirely when the
    // user disabled smart-assist on the instructions screen.
    if (widget.smartAssistEnabled) {
      _assistTimer = Timer.periodic(
        const Duration(milliseconds: 600),
        (_) => _sampleSmartAssist(),
      );
    }
  }

  /// Fetch the cached camera frame once so we know its upright dimensions and
  /// rotation — required to invert the preview's center-crop for taps.
  Future<void> _fetchFrameGeometry() async {
    for (int i = 0; i < 6; i++) {
      if (!mounted) return;
      final frame = await _arCore.acquireCameraFrame();
      if (frame != null && frame.width > 0 && frame.height > 0) {
        setState(() {
          _frameWidth = frame.width;
          _frameHeight = frame.height;
          _frameRotation = frame.rotationDegrees;
        });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Rect get _currentGuideRect =>
      _captureStep == 'front' ? kFrontCaptureGuideRect : kSideCaptureGuideRect;

  // ═══════════════════════════════════════════════════════════════
  // GUIDANCE
  // ═══════════════════════════════════════════════════════════════

  /// Manual mode: guidance is driven purely by ARCore's TRACKING state — there
  /// is NO floor-area / guide-box gate (REMOVE_FLOOR_SCAN_WAIT). The tap UI is
  /// available as soon as the session is tracking, even with no plane mapped
  /// yet; a tap that misses a tracked surface is rejected per-tap with the
  /// §3.3 message, which naturally coaches the user instead of a blocking
  /// "scanning floor" wait.
  void _updateGuidance() {
    if (!mounted) return;
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

    setState(() {
      _guidanceState = newState;
      if (!ready && _pairPhase == 0) _suggestion = null;
      _guidanceText = newText;
    });
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

  // ═══════════════════════════════════════════════════════════════
  // POINT PLACEMENT
  // ═══════════════════════════════════════════════════════════════

  double _worldDistanceMm(ArWorldPoint a, ArWorldPoint b) =>
      a.distanceTo(b) * 1000;

  /// Handle a tap on the preview. Places point A (phase 0) or point B
  /// (phase 1); ignores taps that don't hit a tracked surface (§3.3).
  ///
  /// §2 improvement: fires burst sampling (multiple hitTests at the same
  /// coordinate, ~200ms window) and takes the median for jitter smoothing.
  Future<void> _handleTapAt(Offset local, Size viewSize) async {
    if (_guidanceState == 'error' || _guidanceState == 'initializing') return;
    if (_pairPhase == 2) return; // Locked — drag or confirm/trash
    if (_placementInProgress) return; // No overlapping placements
    _placementInProgress = true;

    // §2 Tracking-quality gate: reject taps when ARCore isn't tracking.
    final trackingState = await _arCore.getTrackingState();
    if (!mounted) { _placementInProgress = false; return; }
    if (trackingState != ArTrackingState.tracking) {
      _placementInProgress = false;
      _showFeedback('Move phone slowly — tracking is limited');
      return;
    }

    final normalized = mapViewToNormalized(
      local,
      viewSize,
      frameWidth: _uprightW,
      frameHeight: _uprightH,
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
    if (!mounted) { _placementInProgress = false; return; }

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

    setState(() {
      // User chose manual placement — clear any smart-assist suggestion.
      _suggestion = null;
      if (_pairPhase == 0) {
        _pointA = _ManualPoint(screen: local, world: world);
        if (!_loggedFirstPoint) {
          _loggedFirstPoint = true;
          _logFirstPointSummary('manual tap');
        }
        _pairPhase = 1;
        _guidanceText = _secondPointPrompt();
        _guidanceState = 'ready';
        _startLiveCenterUpdates();
      } else {
        _pointB = _ManualPoint(screen: local, world: world);
        _pairPhase = 2;
        _liveCenterTimer?.cancel();
        _liveDistanceMm = _worldDistanceMm(_pointA!.world, world);
        _guidanceText = 'Drag the points to adjust, then confirm';
      }
    });
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
      if (!mounted || _pairPhase != 1) {
        _liveCenterTimer?.cancel();
        return;
      }
      final world = await _arCore.hitTest(x: 0.5, y: 0.5);
      if (!mounted) return;
      if (world != null && _pointA != null) {
        setState(() {
          _liveDistanceMm = _worldDistanceMm(_pointA!.world, world);
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // SMART-ASSIST (§6 — optional auto-proposed initial points)
  // ═══════════════════════════════════════════════════════════════

  /// Background sampler: periodically run the (paused) segmentation detector
  /// while the user waits to place the first point, and propose an initial
  /// pair for the CURRENT step. Self-gating (only when the area is tracked,
  /// guidance is ready, and no pair is in progress); non-blocking.
  Future<void> _sampleSmartAssist() async {
    // Double-gate: the timer isn't even started when disabled, but this keeps
    // the sampler inert even if a stray tick ever slipped through.
    if (!widget.smartAssistEnabled) return;
    if (_assistBusy || !mounted) return;
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
      _assistDetector ??= MlKitSegmentationFootDetector();
      final frame = await _arCore.acquireCameraFrame();
      if (!mounted || frame == null || frame.width <= 0 || frame.height <= 0) {
        return;
      }
      final result = await _assistDetector!.detect(
        nv21Bytes: frame.nv21Bytes,
        width: frame.width,
        height: frame.height,
        rotationDegrees: frame.rotationDegrees,
        preferSide: _footLabel(),
        guideRect: _currentGuideRect,
      );
      if (!mounted || _pairPhase != 0 || _guidanceState != 'ready') return;

      final pair = proposePointPair(result, isFront: _captureStep == 'front');
      if (pair == null) {
        if (_suggestion != null) setState(() => _suggestion = null);
        return;
      }

      // Map the normalized (upright-frame) points into view pixels with the
      // shared center-crop transform, exactly like the guide-box painter.
      final aView = mapNormalizedToView(
        Offset(pair.a.x, pair.a.y),
        viewSize,
        frameWidth: _uprightW,
        frameHeight: _uprightH,
      );
      final bView = mapNormalizedToView(
        Offset(pair.b.x, pair.b.y),
        viewSize,
        frameWidth: _uprightW,
        frameHeight: _uprightH,
      );
      final bounds = Offset.zero & viewSize;
      if (!bounds.contains(aView) || !bounds.contains(bView)) return;

      setState(() {
        _suggestion = (
          a: aView,
          b: bView,
          confidence: result.qualityScore,
        );
      });
    } catch (e) {
      // Never let a smart-assist failure affect the manual flow or crash the
      // timer zone — the suggestion is a convenience, not a requirement.
      debugPrint('[SmartAssist] sampler error: $e');
      if (mounted && _suggestion != null) {
        setState(() => _suggestion = null);
      }
    } finally {
      _assistBusy = false;
    }
  }

  /// Accept the smart-assist suggestion: raycast both proposed points to real
  /// world space and lock them in as the pair (same plausibility guard as a
  /// manual confirm, so a bad proposal can't silently produce a bad size).
  Future<void> _acceptSuggestion() async {
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
        frameWidth: _uprightW,
        frameHeight: _uprightH,
      );
      final bNorm = mapViewToNormalized(
        suggestion.b,
        viewSize,
        frameWidth: _uprightW,
        frameHeight: _uprightH,
      );
      // One batch call: a single channel round trip + a consistent snapshot
      // of the same frame (two sequential hitTests could straddle a tracking
      // change). hitTestBatch expects normalized coords, which we have.
      final hits = await _arCore.hitTestBatch(screenPoints: [aNorm, bNorm]);
      if (!mounted) return;
      final aWorld = hits.isNotEmpty ? hits[0] : null;
      final bWorld = hits.length > 1 ? hits[1] : null;
      if (aWorld == null || bWorld == null) {
        _showFeedback(
            "Suggested points didn't hit the floor — place them manually");
        if (_suggestion != null) setState(() => _suggestion = null);
        return;
      }

      final mm = _worldDistanceMm(aWorld, bWorld);
      final cm = mm / 10;
      final isFront = _captureStep == 'front';
      final minCm = isFront ? _minPlausibleWidthCm : _minPlausibleLengthCm;
      final maxCm = isFront ? _maxPlausibleWidthCm : _maxPlausibleLengthCm;
      if (cm < minCm || cm > maxCm) {
        _showFeedback('Suggested size looks off — place the points manually');
        if (_suggestion != null) setState(() => _suggestion = null);
        return;
      }

      setState(() {
        _pointA = _ManualPoint(screen: suggestion.a, world: aWorld);
        if (!_loggedFirstPoint) {
          _loggedFirstPoint = true;
          _logFirstPointSummary('smart-assist');
        }
        _pointB = _ManualPoint(screen: suggestion.b, world: bWorld);
        _pairPhase = 2;
        _liveDistanceMm = mm;
        _guidanceText = 'Drag the points to adjust, then confirm';
        _suggestion = null;
      });
    } finally {
      _placementInProgress = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // POINT DRAGGING (adjust after placement, §2.4)
  // ═══════════════════════════════════════════════════════════════

  void _onPanStart(DragStartDetails details) {
    if (_pairPhase != 2) return;
    final hitRadius = 44.0;
    if (_pointA != null &&
        (_pointA!.screen - details.localPosition).distance < hitRadius) {
      _dragIndex = 0;
    } else if (_pointB != null &&
        (_pointB!.screen - details.localPosition).distance < hitRadius) {
      _dragIndex = 1;
    }
  }

  Future<void> _onPanUpdate(DragUpdateDetails details, Size viewSize) async {
    if (_dragIndex == null || _pairPhase != 2) return;
    if (_dragHitInProgress) return; // Drop overlapping drag raycasts
    _dragHitInProgress = true;

    final normalized = mapViewToNormalized(
      details.localPosition,
      viewSize,
      frameWidth: _uprightW,
      frameHeight: _uprightH,
    );
    final world = await _arCore.hitTest(x: normalized.dx, y: normalized.dy);
    _dragHitInProgress = false;
    if (!mounted || world == null) return;

    setState(() {
      if (_dragIndex == 0) {
        _pointA = _ManualPoint(screen: details.localPosition, world: world);
      } else {
        _pointB = _ManualPoint(screen: details.localPosition, world: world);
      }
      if (_pointA != null && _pointB != null) {
        _liveDistanceMm = _worldDistanceMm(_pointA!.world, _pointB!.world);
      }
    });
  }

  void _onPanEnd() {
    _dragIndex = null;
  }

  // ═══════════════════════════════════════════════════════════════
  // PAIR / STEP FLOW
  // ═══════════════════════════════════════════════════════════════

  /// Clear the current pair so the user can redo this angle (§2.5).
  void _trashPair() {
    _liveCenterTimer?.cancel();
    setState(() {
      _pointA = null;
      _pointB = null;
      _pairPhase = 0;
      _liveDistanceMm = null;
      _dragIndex = null;
      _dragHitInProgress = false;
      _suggestion = null; // Fresh suggestion for the redone pair, if any
    });
    // Let the readiness assessment drive the text/state — if the area dropped
    // out of tracking, show 'searching' rather than forcing 'ready'.
    _updateGuidance();
  }

  /// Lock the current pair and advance the flow (front → side → next foot).
  void _confirmPair() {
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
      setState(() {
        _captureStep = 'side';
        _resetForNextStep(
          message: _currentFoot == 0
              ? 'Width done! Now the SIDE of your left foot'
              : 'Width done! Now the SIDE of your right foot',
        );
      });
      return;
    }

    // ── Side done → next foot, or both feet done → results ──
    if (_currentFoot == 0) {
      setState(() {
        _currentFoot = 1;
        _captureStep = 'front';
        _resetForNextStep(message: 'Left foot done! Now your right foot');
      });
      return;
    }

    _navigateToResults();
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
  }

  /// Show a brief transient feedback toast (invalid taps, implausible values).
  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _tapFeedback = message);
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _tapFeedback = null);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // RESULTS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _navigateToResults() async {
    setState(() {
      _isProcessing = true;
      _processingStep = 'Computing your size...';
    });

    final leftLength = _leftLengthMm;
    final rightLength = _rightLengthMm;
    if (leftLength == null && rightLength == null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _guidanceState = 'ready';
          _guidanceText = 'Both measurements failed — please try again';
        });
      }
      return;
    }

    // §4: Apply sock-thickness compensation to raw measurements.
    final isSocks = widget.footCondition == 'socks';
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
        ? euToUs(euSize, category: widget.shoeCategory)
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

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FootResultsScreen(
          footSide: 'both',
          footLengthMm: leftLength ?? 0,
          footWidthMm: _leftWidthMm ?? 0,
          footLengthRightMm: rightLength,
          footWidthRightMm: _rightWidthMm,
          euSize: euSize,
          usSize: usSize,
          ukSize: ukSize,
          paperSize: 'ar',
          footCondition: widget.footCondition,
          paperConfidence: 1.0,
          lightingQuality: 0.9,
          manualMode: true,
          // v2 fields
          measurementSource: 'ar_guided_tap',
          shoeCategory: widget.shoeCategory,
          sizingFootSide: sizingSide,
          widthCategory: widthCategory,
          leftLengthComp: leftLengthComp,
          leftWidthComp: leftWidthComp,
          rightLengthComp: rightLengthComp,
          rightWidthComp: rightWidthComp,
          sizeRecommendationReason: reason,
        ),
      ),
    );
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

          // ── Manual point interaction layer (taps + drags + markers) ──
          // Positioned.fill must be a DIRECT child of the Stack — the
          // LayoutBuilder needs the Stack's BoxConstraints, so it wraps the
          // gesture layer INSIDE the Positioned (the reverse nesting threw
          // "Incorrect use of ParentDataWidget" every frame).
          Positioned.fill(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              _viewSize = size; // Cached for the smart-assist sampler
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _handleTapAt(d.localPosition, size),
                onPanStart: (d) => _onPanStart(d),
                onPanUpdate: (d) => _onPanUpdate(d, size),
                onPanEnd: (_) => _onPanEnd(),
                child: CustomPaint(
                  painter: _ManualPointsPainter(
                    pointA: _pointA?.screen,
                    pointB: _pointB?.screen,
                    liveCursor:
                        _pairPhase == 1 ? size.center(Offset.zero) : null,
                    liveDistanceMm: _liveDistanceMm,
                    showCrosshair: _pairPhase < 2,
                    isFront: _captureStep == 'front',
                    draggingIndex: _dragIndex,
                    suggestionA: _suggestion?.a,
                    suggestionB: _suggestion?.b,
                    suggestionConfidence: _suggestion?.confidence,
                  ),
                ),
              );
            }),
          ),

          // ── Guide box (placement aid; §3.2 region reference) ──
          if (_guidanceState == 'ready' || _guidanceState == 'searching')
            _buildGuideBox(),

          // ── Guidance Overlay ──
          _buildGuidanceOverlay(),

          // ── Feedback toast ──
          if (_tapFeedback != null) _buildFeedbackToast(),

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

  /// Renders the guide box for the current step as a subtle placement aid
  /// (the region whose plane tracking gates tap resolution).
  Widget _buildGuideBox() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GuideBoxPainter(
            guideRect: _currentGuideRect,
            frameWidth: _uprightW,
            frameHeight: _uprightH,
            active: _guidanceState == 'ready',
            label: _captureStep == 'front' ? 'FRONT VIEW' : 'SIDE VIEW',
          ),
        ),
      ),
    );
  }

  Widget _buildGuidanceOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_guidanceState == 'ready') ...[
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

  Widget _buildFeedbackToast() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 24,
      right: 24,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppConstants.error.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _tapFeedback!,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Absorbs taps over non-interactive overlay chrome (top/bottom bars) so
  /// they don't fall through the Stack to the placement GestureDetector and
  /// silently place a point behind the UI. Buttons inside remain interactive
  /// — they sit deeper in the hit path and still win the gesture arena.
  Widget _buildTapBarrier(Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: child,
      );

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: _buildTapBarrier(
        Row(
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
              child: const Icon(Icons.close, color: Colors.white, size: 20),
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
                  color: _currentFoot == 0
                      ? AppConstants.accent
                      : AppConstants.success,
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
                if (_currentFoot == 1) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle,
                      color: AppConstants.success, size: 16),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Capture step indicator
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
                  _captureStep == 'front' ? 'WIDTH' : 'LENGTH',
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
      ),
    );
  }

  Widget _buildBottomBar() {
    final showConfirm = _pairPhase == 2;
    final showHint =
        _guidanceState == 'ready' && !showConfirm && _pairPhase < 2;

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 20,
      left: 20,
      right: 20,
      child: _buildTapBarrier(
        Column(
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
                        : _guidanceState == 'error'
                            ? AppConstants.error
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

          // Live measurement pill while placing point B (§2.3)
          if (_pairPhase == 1 && _liveDistanceMm != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppConstants.accent.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _liveMeasureText(),
                style: AppConstants.monoStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 16),

          // Action area
          if (showConfirm)
            Row(
              children: [
                // Trash / redo pair (§2.4, §2.5)
                GestureDetector(
                  onTap: _trashPair,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Confirm / next
                Expanded(
                  child: GestureDetector(
                    onTap: _confirmPair,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppConstants.accent,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.accent.withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Confirm ${_captureStep == 'front' ? 'Width' : 'Length'}',
                          style: AppConstants.bodyStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else if (showHint)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Smart-assist: accept the proposed pair (§6) ──
                if (_pairPhase == 0 && _suggestion != null) ...[
                  GestureDetector(
                    onTap: _acceptSuggestion,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppConstants.accent.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppConstants.accent.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: AppConstants.secondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _suggestionConfidenceLabel(),
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // Trash/redo is also available once the FIRST point of the
                // pair is placed (§2.5: redo an angle before moving on).
                if (_pairPhase == 1) ...[
                  GestureDetector(
                    onTap: _trashPair,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _pairPhase == 0
                            ? Icons.touch_app_outlined
                            : Icons.my_location,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _pairPhase == 0
                            ? 'Tap the foot to place the first point'
                            : 'Aim at the second point — tap to lock it in',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else if (_guidanceState == 'error')
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
      ),
    );
  }

  /// Button label for the smart-assist suggestion, including the detection's
  /// confidence as a percentage so the user can gauge how trustworthy the
  /// proposal is (falls back to the plain label defensively).
  String _suggestionConfidenceLabel() {
    final conf = _suggestion?.confidence;
    if (conf == null) return 'Use suggested points';
    final pct = (conf.clamp(0.0, 1.0) * 100).round();
    return 'Use suggested points · $pct%';
  }

  /// Live measurement text for the in-progress pair (§2.3).
  String _liveMeasureText() {
    final mm = _liveDistanceMm;
    if (mm == null) return 'measuring…';
    final cm = mm / 10;
    final isFront = _captureStep == 'front';
    final minCm = isFront ? _minPlausibleWidthCm : _minPlausibleLengthCm;
    final maxCm = isFront ? _maxPlausibleWidthCm : _maxPlausibleLengthCm;
    if (cm < minCm || cm > maxCm) return 'measuring…';
    final label = isFront ? 'Width' : 'Length';
    return '$label: ~${cm.toStringAsFixed(1)}cm';
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

/// Paints the manual measurement markers, lines, and crosshair on the preview.
///
/// All points are stored in VIEW PIXEL space (where the user tapped/dragged),
/// so they draw directly — no frame mapping needed here. The live crosshair
/// line (A → center) shows the continuously-updating distance while the user
/// aims at the second point.
class _ManualPointsPainter extends CustomPainter {
  final Offset? pointA;
  final Offset? pointB;

  /// Current screen-center position (while placing point B).
  final Offset? liveCursor;

  /// Live distance A→cursor / A→B in mm.
  final double? liveDistanceMm;

  /// Whether to draw the center crosshair reticle.
  final bool showCrosshair;

  /// Whether the current pair is the FRONT (width) capture — affects labels.
  final bool isFront;

  /// Index of the point currently being dragged (0 = A, 1 = B), if any.
  final int? draggingIndex;

  /// Smart-assist proposed point positions (view pixels, §6) — drawn
  /// dashed/translucent until accepted or ignored.
  final Offset? suggestionA;
  final Offset? suggestionB;

  /// Detection quality score (0.0–1.0) for the current suggestion, shown as a
  /// color-coded confidence pill so the user can gauge trustworthiness.
  final double? suggestionConfidence;

  const _ManualPointsPainter({
    required this.pointA,
    required this.pointB,
    required this.liveCursor,
    required this.liveDistanceMm,
    required this.showCrosshair,
    required this.isFront,
    required this.draggingIndex,
    this.suggestionA,
    this.suggestionB,
    this.suggestionConfidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Center crosshair reticle (placement aid) ──
    if (showCrosshair) {
      final c = size.center(Offset.zero);
      final reticlePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(c, 18, reticlePaint);
      canvas.drawCircle(c, 2, Paint()..color = Colors.white);
      const tick = 6.0;
      canvas.drawLine(Offset(c.dx, c.dy - 18 - tick), Offset(c.dx, c.dy - 18),
          reticlePaint);
      canvas.drawLine(Offset(c.dx, c.dy + 18), Offset(c.dx, c.dy + 18 + tick),
          reticlePaint);
      canvas.drawLine(Offset(c.dx - 18 - tick, c.dy), Offset(c.dx - 18, c.dy),
          reticlePaint);
      canvas.drawLine(Offset(c.dx + 18, c.dy), Offset(c.dx + 18 + tick, c.dy),
          reticlePaint);
    }

    // ── Live line A → crosshair while placing point B (§2.3) ──
    if (pointA != null && liveCursor != null && pointB == null) {
      final linePaint = Paint()
        ..color = AppConstants.accent
        ..strokeWidth = 2.5;
      canvas.drawLine(pointA!, liveCursor!, linePaint);
      if (liveDistanceMm != null) {
        _drawDistancePill(
          canvas,
          Offset(
            (pointA!.dx + liveCursor!.dx) / 2,
            (pointA!.dy + liveCursor!.dy) / 2,
          ),
          liveDistanceMm!,
        );
      }
    }

    // ── Locked line A → B with distance label (§2.4) ──
    if (pointA != null && pointB != null) {
      final linePaint = Paint()
        ..color = const Color(0xFF42A5F5)
        ..strokeWidth = 3;
      canvas.drawLine(pointA!, pointB!, linePaint);
      if (liveDistanceMm != null) {
        _drawDistancePill(
          canvas,
          Offset(
            (pointA!.dx + pointB!.dx) / 2,
            (pointA!.dy + pointB!.dy) / 2,
          ),
          liveDistanceMm!,
        );
      }
    }

    // ── Smart-assist suggestion (dashed line + hollow markers, §6) ──
    // Drawn translucent so it reads as a proposal, distinct from the locked
    // solid markers; disappears once the user places a point or accepts.
    if (suggestionA != null && suggestionB != null) {
      final dashPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      _drawDashedLine(canvas, suggestionA!, suggestionB!, dashPaint);
      _drawSuggestionMarker(canvas, suggestionA!);
      _drawSuggestionMarker(canvas, suggestionB!);
      if (suggestionConfidence != null) {
        _drawConfidencePill(
          canvas,
          Offset(
            (suggestionA!.dx + suggestionB!.dx) / 2,
            (suggestionA!.dy + suggestionB!.dy) / 2,
          ),
          suggestionConfidence!,
        );
      }
    }

    // ── Point markers (reuse H/T/W marker style) ──
    if (pointA != null) {
      final label = isFront ? 'W' : 'H';
      final color = isFront ? const Color(0xFF42A5F5) : const Color(0xFF4CAF50);
      _drawMarker(canvas, pointA!, label, color,
          dragging: draggingIndex == 0);
    }
    if (pointB != null) {
      final label = isFront ? 'W' : 'T';
      final color = isFront ? const Color(0xFF42A5F5) : const Color(0xFFF44336);
      _drawMarker(canvas, pointB!, label, color,
          dragging: draggingIndex == 1);
    }
  }

  void _drawMarker(Canvas canvas, Offset center, String label, Color color,
      {bool dragging = false}) {
    final radius = dragging ? 14.0 : 11.0;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    if (dragging) {
      // Outer highlight ring while dragging
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx + radius + 6, center.dy - tp.height / 2),
    );
  }

  /// Dashed line between two points (used for smart-assist suggestions).
  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 10.0;
    const gap = 8.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  /// Color-coded confidence pill on the suggestion line (§6): shows the
  /// detection's quality score as a percentage — green (≥0.85) high, amber
  /// (≥0.7) at/above the accept floor, red below (defensive — suggestions
  /// only appear once `footDetected`, i.e. qualityScore ≥ kSampleAcceptScore
  /// 0.7) — so the user knows how much to trust the auto-proposed points
  /// before accepting or dragging them.
  void _drawConfidencePill(Canvas canvas, Offset center, double confidence) {
    final pct = (confidence.clamp(0.0, 1.0) * 100).round();
    final color = confidence >= 0.85
        ? AppConstants.success
        : confidence >= kSampleAcceptScore
            ? const Color(0xFFFFB300)
            : AppConstants.error;

    final tp = TextPainter(
      text: TextSpan(
        text: '$pct%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, -tp.height / 2 - 14),
        width: tp.width + 14,
        height: tp.height + 6,
      ),
      const Radius.circular(9),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    tp.paint(
      canvas,
      Offset(rect.left + 7, rect.top + 3),
    );
  }

  /// Hollow translucent marker for a suggested (not yet accepted) point.
  void _drawSuggestionMarker(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  /// Pill-style distance label on the line (reference-app pattern).
  void _drawDistancePill(Canvas canvas, Offset center, double mm) {
    final cm = mm / 10;
    final tp = TextPainter(
      text: TextSpan(
        text: '${cm.toStringAsFixed(1)} cm',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: tp.width + 16,
        height: tp.height + 8,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.7));
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ManualPointsPainter oldDelegate) {
    return oldDelegate.pointA != pointA ||
        oldDelegate.pointB != pointB ||
        oldDelegate.liveCursor != liveCursor ||
        oldDelegate.liveDistanceMm != liveDistanceMm ||
        oldDelegate.showCrosshair != showCrosshair ||
        oldDelegate.isFront != isFront ||
        oldDelegate.draggingIndex != draggingIndex ||
        oldDelegate.suggestionA != suggestionA ||
        oldDelegate.suggestionB != suggestionB ||
        oldDelegate.suggestionConfidence != suggestionConfidence;
  }
}

/// Paints the guided-capture bounding box (§3.2 region reference) on the
/// camera preview. Reuses the shared center-crop coordinate transform.
class _GuideBoxPainter extends CustomPainter {
  final Rect guideRect;
  final int frameWidth;
  final int frameHeight;
  final bool active;
  final String label;

  const _GuideBoxPainter({
    required this.guideRect,
    required this.frameWidth,
    required this.frameHeight,
    required this.active,
    required this.label,
  });

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

    // ── Dim overlay outside the box ──
    final dimPaint =
        Paint()..color = Colors.black.withValues(alpha: active ? 0.15 : 0.08);
    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(rrect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, hole),
      dimPaint,
    );

    // ── Box border ──
    final borderColor = active ? AppConstants.accent : Colors.white54;
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.5 : 1.5,
    );

    // ── Corner brackets ──
    final bracketPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const b = 18.0;
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
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        tl.dx,
        (tl.dy - tp.height - 8).clamp(4, size.height - tp.height - 4),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _GuideBoxPainter oldDelegate) {
    return oldDelegate.guideRect != guideRect ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.active != active ||
        oldDelegate.label != label;
  }
}
