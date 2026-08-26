import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
// TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
import '../../services/diag_logger.dart' show navDiag;
import '../../services/ar_core_channel.dart';
import 'foot_ar_scan_screen.dart';
import 'foot_instructions_screen.dart' show ArMode;
import 'foot_manual_measure_screen.dart';

/// Floor reference captured before scanning.
///
/// Stores the floor plane's normal and a confirmed world-space point on the
/// floor plane, captured under known-good conditions (ARCore `TRACKING` + a
/// stable horizontal-upward-facing plane).
///
/// Plumbing note: both AR modes accept a [FloorReference] but neither
/// currently reads it — all measurement math anchors on live per-frame
/// hitTests. This is scaffolding for a future drift-correction layer.
///
/// Replaces the old `WallReference`: since the E4 fix, native `hitTest` only
/// ever returns points on horizontal-upward-facing planes, so a confirmed
/// floor-plane point IS the reference — there is no wall-floor line anymore.
class FloorReference {
  /// Floor plane normal vector (up = roughly (0, 1, 0)).
  final ArWorldPoint normal;

  /// A confirmed point on the floor plane (world-space).
  final ArWorldPoint origin;

  const FloorReference({required this.normal, required this.origin});
}

/// Floor-detection screen — the setup step preceding BOTH AR modes.
///
/// Flow:
/// 1. Camera permission + ARCore session start (reason-coded failure surfaced)
/// 2. User simply points the phone at the floor in front of them
/// 3. Once ARCore reports `TRACKING` **and** a horizontal plane has been
///    present continuously for a short debounce window, the floor reference
///    is captured automatically
/// 4. Auto-advance into the chosen AR mode — no confirm tap, no skip button
///
/// If no stable floor plane appears within [_floorDetectionTimeout], fail
/// gracefully with a clear message and a retry action (never a crash, never a
/// silent bad-anchor fallback).
class FootFloorDetectionScreen extends StatefulWidget {
  final String footCondition;
  final String shoeCategory;
  final bool smartAssistEnabled;
  final ArMode arMode;

  const FootFloorDetectionScreen({
    super.key,
    required this.footCondition,
    required this.shoeCategory,
    required this.smartAssistEnabled,
    required this.arMode,
  });

  @override
  State<FootFloorDetectionScreen> createState() =>
      _FootFloorDetectionScreenState();
}

class _FootFloorDetectionScreenState extends State<FootFloorDetectionScreen>
    with SingleTickerProviderStateMixin {
  final ArCoreChannel _arCore = ArCoreChannel.instance;

  // ── ARCore State ──
  ArTrackingState _trackingState = ArTrackingState.paused;
  bool _planeDetected = false;
  StreamSubscription<ArSessionEvent>? _eventSubscription;

  // ── Floor-stability gate ──
  // Consecutive-hold accumulator (the same debounce pattern the old tilt
  // leveling gate used): every tick the floor condition holds adds credit;
  // any break decays faster than it accumulates, so only a genuinely STABLE
  // floor passes. This mirrors TemporalFootGate's consecutive-positive
  // philosophy, expressed in wall-clock ticks because plane/tracking arrive
  // as sparse events rather than per-frame results.
  static const int _holdTickMs = 50;
  static const int _floorHoldRequiredMs = 800;
  int _floorHoldMs = 0;
  Timer? _stabilityTimer;

  /// Whether the floor condition currently holds (TRACKING + a plane seen).
  bool get _floorConditionHolds =>
      _trackingState == ArTrackingState.tracking && _planeDetected;

  double get _holdProgress =>
      (_floorHoldMs / _floorHoldRequiredMs).clamp(0.0, 1.0);

  // ── Detection State ──
  /// The captured floor reference.
  FloorReference? _floorReference;

  /// Whether a capture attempt is in progress.
  bool _capturing = false;

  /// Whether detection is complete (reference captured).
  bool _detectionComplete = false;

  // ── Failure handling ──
  /// No floor plane confirmed within this window → explicit, retryable error.
  static const int _floorDetectionTimeoutSeconds = 15;
  Timer? _timeoutTimer;

  /// Terminal error state (session failure, permission denied, or timeout).
  bool _failed = false;
  String _errorText = '';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _initSession();
    _startStabilityGate();
    _armTimeout();
  }

  @override
  void dispose() {
    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] FloorDetection dispose');
    _eventSubscription?.cancel();
    _stabilityTimer?.cancel();
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    // D1 fix: no explicit session teardown here. Native teardown is
    // single-owned by Flutter's PlatformView disposal (fires when this AR
    // widget unmounts). An explicit stopSession() landed AFTER the next
    // screen's view had already registered natively, destroying the incoming
    // view mid-creation — the Phase 1b transition crash.
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════

  Future<void> _initSession() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _failed = true;
          _errorText = 'Camera permission is required for AR scanning';
        });
      }
      return;
    }

    final start = await _arCore.startSession();
    if (!mounted) return;
    if (!start.started) {
      // E3 fix: this path is reachable (unsupported device / needs install /
      // timeout) — surface a real error state instead of leaving the user on
      // a permanently-unready detection screen.
      setState(() {
        _failed = true;
        _errorText = start.message ?? 'Failed to start AR session.';
      });
      return;
    }

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
          break;
        case 'plane':
          setState(() => _planeDetected = true);
          break;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // FLOOR-STABILITY GATE + CAPTURE
  // ═══════════════════════════════════════════════════════════════

  /// Periodic hold check: accumulate credit while the floor condition holds,
  /// decay when it breaks. On reaching the required hold, capture the floor
  /// reference automatically.
  void _startStabilityGate() {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer.periodic(
      const Duration(milliseconds: _holdTickMs),
      (_) {
        if (!mounted || _failed || _detectionComplete) return;
        if (_floorConditionHolds) {
          _floorHoldMs += _holdTickMs;
          if (_floorHoldMs >= _floorHoldRequiredMs &&
              !_capturing &&
              !_detectionComplete) {
            _captureFloorReference();
          }
        } else {
          _floorHoldMs = (_floorHoldMs - 2 * _holdTickMs).clamp(0, 1 << 31);
        }
      },
    );
  }

  /// Capture the floor reference: floor-plane normal + a confirmed point on
  /// the plane (average of three screen-center probes). Since the E4 fix the
  /// native hitTest only returns HORIZONTAL_UPWARD_FACING plane hits, so the
  /// probed point is guaranteed to be ON the floor — never on a wall.
  ///
  /// A transient probe failure does NOT consume the flow: the hold gate resets
  /// and re-debounces, retrying naturally on the next pass. The timeout is the
  /// backstop for persistent failure.
  Future<void> _captureFloorReference() async {
    if (_capturing || _detectionComplete) return;
    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] FloorDetection hold gate satisfied → capturing floor '
        'reference (tracking=$_trackingState, plane=$_planeDetected)');
    setState(() => _capturing = true);

    try {
      final floorPlane = await _arCore.getFloorPlane();
      if (floorPlane == null || !mounted) {
        _resetForRetry();
        return;
      }

      final hits = await _arCore.hitTestBatch(screenPoints: const [
        Offset(0.5, 0.5), // Center
        Offset(0.4, 0.5), // Slightly left of center
        Offset(0.6, 0.5), // Slightly right of center
      ]);

      final validHits = hits.whereType<ArWorldPoint>().toList();
      if (validHits.isEmpty || !mounted) {
        _resetForRetry();
        return;
      }

      // Average of valid floor hits = the confirmed floor point.
      double avgX = 0, avgY = 0, avgZ = 0;
      for (final hit in validHits) {
        avgX += hit.x;
        avgY += hit.y;
        avgZ += hit.z;
      }
      final n = validHits.length.toDouble();
      final origin = ArWorldPoint(
        x: avgX / n,
        y: avgY / n,
        z: avgZ / n,
        distanceFromCamera: validHits.first.distanceFromCamera,
      );

      final normal = ArWorldPoint(
        x: floorPlane.normalX,
        y: floorPlane.normalY,
        z: floorPlane.normalZ,
        distanceFromCamera: 0,
      );

      _timeoutTimer?.cancel();
      setState(() {
        _floorReference = FloorReference(normal: normal, origin: origin);
        _capturing = false;
        _detectionComplete = true;
      });

      // Auto-advance into the chosen AR mode after a brief success beat —
      // no user action required.
      // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
      navDiag('[NAV-DEBUG] FloorDetection reference captured → auto-advance '
          'timer armed (900ms, mounted=$mounted)');
      Timer(const Duration(milliseconds: 900), () {
        // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
        navDiag('[NAV-DEBUG] FloorDetection auto-advance timer fired '
            '(mounted=$mounted, detectionComplete=$_detectionComplete)');
        if (mounted && _detectionComplete) _navigateToScan();
      });
    } catch (e) {
      debugPrint('[FloorDetection] Capture error: $e');
      if (mounted) _resetForRetry();
    }
  }

  /// Reset the hold gate so the next stable window retries the capture.
  void _resetForRetry() {
    setState(() {
      _capturing = false;
      _floorHoldMs = 0;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // TIMEOUT / FAILURE
  // ═══════════════════════════════════════════════════════════════

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(
      const Duration(seconds: _floorDetectionTimeoutSeconds),
      () {
        if (!mounted || _detectionComplete || _failed) return;
        setState(() {
          _failed = true;
          _errorText =
              "We couldn't detect a stable floor. Try brighter lighting or a "
              'more textured surface, then try again.';
        });
      },
    );
  }

  void _retryDetection() {
    if (!mounted) return;
    setState(() {
      _failed = false;
      _errorText = '';
      _detectionComplete = false;
      _capturing = false;
      _floorReference = null;
      _planeDetected = false;
      _floorHoldMs = 0;
    });
    // The ARCore session keeps running across a retry (only the detection
    // gate re-arms); a session that never started will simply time out again
    // with its reason already shown.
    _armTimeout();
  }

  // ═══════════════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════════════

  void _navigateToScan() {
    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] FloorDetection pushReplacement → '
        '${widget.arMode == ArMode.guidedTap ? 'FootManualMeasureScreen' : 'FootArScanScreen'} '
        '(canPop=${Navigator.of(context).canPop()})');
    if (widget.arMode == ArMode.guidedTap) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FootManualMeasureScreen(
            footCondition: widget.footCondition,
            smartAssistEnabled: widget.smartAssistEnabled,
            shoeCategory: widget.shoeCategory,
            floorReference: _floorReference,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FootArScanScreen(
            footCondition: widget.footCondition,
            shoeCategory: widget.shoeCategory,
            floorReference: _floorReference,
          ),
        ),
      );
    }
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
          // ── AR Camera Feed ──
          _buildArView(),

          // ── Dim overlay ──
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),

          // ── Detection indicator / success indicator ──
          if (!_detectionComplete)
            _buildDetectingOverlay()
          else
            _buildSuccessOverlay(),

          // ── Top bar ──
          _buildTopBar(),

          // ── Bottom instructions / actions ──
          _buildBottomPanel(),
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

  /// Coaching copy for the current detection phase.
  String get _coachingText {
    if (_capturing) return 'Locking floor reference…';
    switch (_trackingState) {
      case ArTrackingState.paused:
        return 'Move your phone slowly to initialize AR tracking';
      case ArTrackingState.limited:
        return 'Tracking is limited — move your phone slowly side to side';
      case ArTrackingState.tracking:
        return _planeDetected
            ? 'Hold steady — detecting the floor…'
            : 'Point the camera at the floor in front of you';
    }
  }

  Widget _buildDetectingOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hold-progress ring: fills as the floor stays stable, matching the
          // scan screen's progress-ring idiom.
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: _capturing ? null : _holdProgress,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(
                      _holdProgress > 0 ? AppConstants.accent : Colors.white54,
                    ),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 40 + (_pulseController.value * 8),
                      height: 40 + (_pulseController.value * 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.accent.withValues(
                          alpha: 0.25 - (_pulseController.value * 0.15),
                        ),
                      ),
                      child: const Icon(
                        Icons.texture,
                        color: Colors.white70,
                        size: 24,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Coaching readout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _coachingText,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 80 + (_pulseController.value * 10),
                height: 80 + (_pulseController.value * 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.success.withValues(
                    alpha: 0.3 - (_pulseController.value * 0.15),
                  ),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppConstants.success,
                  size: 60,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Floor detected',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Starting your scan…',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
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
                  Icons.texture,
                  color: _detectionComplete
                      ? AppConstants.success
                      : AppConstants.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Floor Detection',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
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
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 20,
      left: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Instructions ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _detectionComplete
                          ? Icons.check_circle
                          : _failed
                              ? Icons.error_outline
                              : Icons.info_outline,
                      color: _detectionComplete
                          ? AppConstants.success
                          : _failed
                              ? AppConstants.error
                              : Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _detectionComplete
                            ? 'Floor locked — you can now scan'
                            : _failed
                                ? _errorText
                                : 'Point your camera at the floor ahead of you — '
                                    'no walls, no standing pose needed',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Action buttons ──
          if (_failed) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _retryDetection,
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.accent,
                  foregroundColor: AppConstants.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: Text(
                  'Try Again',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: Text(
                  'Go Back',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ] else ...[
            // Contrast-socks accuracy tip (carried over from the old wall
            // flow — kept as passive guidance, no tap required).
            Text(
              'Tip: wear socks that contrast with your floor color for best accuracy',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
