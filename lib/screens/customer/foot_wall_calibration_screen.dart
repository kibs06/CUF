import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../constants/app_constants.dart';
import '../../services/ar_core_channel.dart';
import 'foot_ar_scan_screen.dart';
import 'foot_instructions_screen.dart' show ArMode;
import 'foot_manual_measure_screen.dart';

/// Wall-floor reference plane captured during calibration.
///
/// Stores the floor plane's normal and a world-space origin point on the
/// wall-floor intersection line. Both AR modes use this as a fixed,
/// drift-resistant anchor instead of relying purely on ARCore's
/// continuously-updating floor estimate.
class WallReference {
  /// Floor plane normal vector (up = roughly (0, 1, 0)).
  final ArWorldPoint normal;

  /// A point on the wall-floor intersection line (world-space).
  final ArWorldPoint origin;

  const WallReference({required this.normal, required this.origin});
}

/// Wall-calibration screen — Nike Fit-style setup step.
///
/// Flow:
/// 1. User stands feet-to-wall, phone held ~1m back at chest height
/// 2. Two-circle leveling gate: inner circle tracks live tilt, outer is target
/// 3. Once level + ARCore tracking == TRACKING, capture wall-floor reference
/// 4. Optional contrast-socks tip
/// 5. Navigate to chosen AR mode with the captured reference
class FootWallCalibrationScreen extends StatefulWidget {
  final String footCondition;
  final String shoeCategory;
  final bool smartAssistEnabled;
  final ArMode arMode;

  const FootWallCalibrationScreen({
    super.key,
    required this.footCondition,
    required this.shoeCategory,
    required this.smartAssistEnabled,
    required this.arMode,
  });

  @override
  State<FootWallCalibrationScreen> createState() =>
      _FootWallCalibrationScreenState();
}

class _FootWallCalibrationScreenState extends State<FootWallCalibrationScreen>
    with SingleTickerProviderStateMixin {
  final ArCoreChannel _arCore = ArCoreChannel.instance;

  // ── Leveling State ──
  /// Live tilt angle in degrees from vertical (0 = perfectly level).
  double _tiltDegrees = 0;

  /// How long the tilt has been within tolerance.
  int _levelHoldMs = 0;
  static const double _levelToleranceDegrees = 3.0;
  static const int _levelHoldRequiredMs = 500;
  Timer? _levelCheckTimer;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  /// Whether the leveling gate has passed.
  bool _isLevel = false;

  // ── ARCore State ──
  ArTrackingState _trackingState = ArTrackingState.paused;
  bool _planeDetected = false;
  StreamSubscription<ArSessionEvent>? _eventSubscription;

  // ── Calibration State ──
  /// The captured wall reference plane.
  WallReference? _wallReference;

  /// Whether calibration is in progress (capturing the wall-floor intersection).
  bool _capturing = false;

  /// Whether calibration is complete.
  bool _calibrationComplete = false;

  /// Number of failed leveling attempts (for skip-after-N pattern).
  int _failedAttempts = 0;

  /// Show the contrast-socks tip interstitial.
  bool _showSockTip = false;

  /// Whether the sock tip has been shown/dismissed this session.
  bool _sockTipDismissed = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _initSession();
    _initAccelerometer();
    _startLevelCheck();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _accelSubscription?.cancel();
    _levelCheckTimer?.cancel();
    _pulseController.dispose();
    _arCore.stopSession();
    super.dispose();
  }

  Future<void> _initSession() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _trackingState = ArTrackingState.paused;
        });
      }
      return;
    }

    final started = await _arCore.startSession();
    if (!started || !mounted) return;

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

  void _initAccelerometer() {
    _accelSubscription = accelerometerEventStream().listen((event) {
      if (!mounted) return;
      // Compute tilt from vertical using x and y acceleration components.
      // When phone is held vertically (standing), z ≈ 9.8, x/y ≈ 0.
      // Tilt angle = atan(sqrt(x² + y²) / z).
      final z = event.z.abs();
      final xy = math.sqrt(event.x * event.x + event.y * event.y);
      final tiltRad = math.atan2(xy, z);
      final tiltDeg = tiltRad * 180 / math.pi;

      setState(() => _tiltDegrees = tiltDeg);
    });
  }

  /// Start periodic check: if tilt is within tolerance, accumulate hold time.
  void _startLevelCheck() {
    _levelCheckTimer?.cancel();
    _levelCheckTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        if (!mounted) return;
        if (_tiltDegrees <= _levelToleranceDegrees) {
          _levelHoldMs += 50;
          if (_levelHoldMs >= _levelHoldRequiredMs && !_isLevel) {
            setState(() => _isLevel = true);
            // Auto-proceed to capture after a brief pause
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _isLevel && !_capturing && !_calibrationComplete) {
                _captureWallReference();
              }
            });
          }
        } else {
          _levelHoldMs = math.max(0, _levelHoldMs - 100);
          if (_isLevel) setState(() => _isLevel = false);
        }
      },
    );
  }

  /// Capture the wall-floor intersection as a reference plane.
  /// Uses the floor plane from ARCore + a vertical probe at the screen center.
  Future<void> _captureWallReference() async {
    if (_capturing || _calibrationComplete) return;
    setState(() => _capturing = true);

    try {
      // Get the floor plane
      final floorPlane = await _arCore.getFloorPlane();
      if (floorPlane == null || !mounted) {
        setState(() {
          _capturing = false;
          _failedAttempts++;
        });
        return;
      }

      // Probe the center of the screen to find a point on the floor near the wall.
      // The user is standing ~1m back from the wall, so the center of the frame
      // should be roughly where the wall meets the floor.
      final hits = await _arCore.hitTestBatch(screenPoints: const [
        Offset(0.5, 0.5), // Center
        Offset(0.4, 0.5), // Slightly left of center
        Offset(0.6, 0.5), // Slightly right of center
      ]);

      final validHits = hits.whereType<ArWorldPoint>().toList();
      if (validHits.isEmpty || !mounted) {
        setState(() {
          _capturing = false;
          _failedAttempts++;
        });
        return;
      }

      // Use the average of valid hits as the wall-floor origin point
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

      // Floor plane normal
      final normal = ArWorldPoint(
        x: floorPlane.normalX,
        y: floorPlane.normalY,
        z: floorPlane.normalZ,
        distanceFromCamera: 0,
      );

      setState(() {
        _wallReference = WallReference(normal: normal, origin: origin);
        _capturing = false;
        _calibrationComplete = true;
      });
    } catch (e) {
      debugPrint('[WallCalibration] Capture error: $e');
      if (mounted) {
        setState(() {
          _capturing = false;
          _failedAttempts++;
        });
      }
    }
  }

  void _skipCalibration() {
    _levelCheckTimer?.cancel();
    setState(() {
      _wallReference = null;
    });
    _navigateToScan();
  }

  void _showSockTipAndProceed() {
    setState(() => _showSockTip = true);
  }

  void _dismissSockTip() {
    setState(() {
      _showSockTip = false;
      _sockTipDismissed = true;
    });
    _navigateToScan();
  }

  void _proceedAfterCalibration() {
    if (!_sockTipDismissed) {
      _showSockTipAndProceed();
    } else {
      _navigateToScan();
    }
  }

  void _navigateToScan() {
    if (widget.arMode == ArMode.guidedTap) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FootManualMeasureScreen(
            footCondition: widget.footCondition,
            smartAssistEnabled: widget.smartAssistEnabled,
            shoeCategory: widget.shoeCategory,
            wallReference: _wallReference,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FootArScanScreen(
            footCondition: widget.footCondition,
            shoeCategory: widget.shoeCategory,
            wallReference: _wallReference,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSockTip) return _buildSockTipScreen();
    return _buildCalibrationScreen();
  }

  Widget _buildCalibrationScreen() {
    final canLevel = _trackingState == ArTrackingState.tracking && _planeDetected;
    final showSkip = _failedAttempts >= 2;

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

          // ── Leveling gate UI ──
          if (!_calibrationComplete) _buildLevelingOverlay(canLevel),

          // ── Success indicator ──
          if (_calibrationComplete) _buildSuccessOverlay(),

          // ── Top bar ──
          _buildTopBar(),

          // ── Bottom instructions + action ──
          _buildBottomPanel(showSkip, canLevel),
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

  Widget _buildLevelingOverlay(bool canLevel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Two-circle level indicator ──
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _LevelingPainter(
                tiltDegrees: _tiltDegrees,
                isLevel: _isLevel,
                tolerance: _levelToleranceDegrees,
                holdProgress: _levelHoldMs / _levelHoldRequiredMs,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Tilt readout ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isLevel
                  ? 'Level ✓'
                  : 'Tilt: ${_tiltDegrees.toStringAsFixed(1)}° — tilt phone to vertical',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _isLevel ? AppConstants.success : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (!canLevel)
            Text(
              _trackingState == ArTrackingState.paused
                  ? 'Move phone slowly to initialize AR tracking'
                  : 'Point camera at the wall-floor intersection',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
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
            'Wall reference captured',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ready to measure',
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
                  Icons.wallpaper,
                  color: _calibrationComplete
                      ? AppConstants.success
                      : AppConstants.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Wall Calibration',
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

  Widget _buildBottomPanel(bool showSkip, bool canLevel) {
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
                      _calibrationComplete
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: _calibrationComplete
                          ? AppConstants.success
                          : Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _calibrationComplete
                            ? 'Wall reference locked — you can now scan'
                            : 'Stand feet-to-wall, hold phone ~1m back at chest height, and level the phone',
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
          if (_calibrationComplete)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _proceedAfterCalibration,
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.accent,
                  foregroundColor: AppConstants.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: Text(
                  'Start Measuring',
                  style: AppConstants.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
              ),
            )
          else ...[
            if (showSkip)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _skipCalibration,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppConstants.buttonRadius,
                    ),
                  ),
                  child: Text(
                    'Skip Wall Calibration',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (showSkip) const SizedBox(height: 8),
            // Contrast socks tip
            if (canLevel && !_isLevel && !_capturing)
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

  Widget _buildSockTipScreen() {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppConstants.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.checkroom_outlined,
                      color: AppConstants.accent,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'One Tip Before Scanning',
                    style: AppConstants.headlineStyle(
                      fontSize: 22,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'For best accuracy, wear socks that contrast with your floor color. '
                    'Dark socks on a light floor (or vice versa) help the camera detect your foot edges more precisely.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      color: AppConstants.secondary.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is optional — bare feet work too.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _dismissSockTip,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.accent,
                        foregroundColor: AppConstants.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppConstants.buttonRadius,
                        ),
                      ),
                      child: Text(
                        'Got it, start scanning',
                        style: AppConstants.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter for the two-circle leveling indicator.
///
/// Outer circle is the fixed target. Inner circle tracks live tilt.
/// When aligned (within tolerance), the circles overlap and turn green.
class _LevelingPainter extends CustomPainter {
  final double tiltDegrees;
  final bool isLevel;
  final double tolerance;
  final double holdProgress; // 0.0–1.0

  _LevelingPainter({
    required this.tiltDegrees,
    required this.isLevel,
    required this.tolerance,
    required this.holdProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 8;
    final innerRadius = outerRadius * 0.6;

    // Map tilt to offset: 0° = centered, maxTilt (e.g. 30°) = edge of outer circle
    final maxTilt = 30.0;
    final clampedTilt = tiltDegrees.clamp(0.0, maxTilt);
    final normalizedTilt = clampedTilt / maxTilt;
    final maxOffset = outerRadius - innerRadius;
    final offset = normalizedTilt * maxOffset;

    // Inner circle offset direction (simplified: use a rotating offset based on tilt)
    // In reality we'd use x/y tilt components, but for simplicity we use the magnitude.
    final angle = DateTime.now().millisecond * 0.006; // Slow rotation for visual effect
    final innerCenter = Offset(
      center.dx + offset * math.cos(angle),
      center.dy + offset * math.sin(angle),
    );

    // ── Outer circle (target) ──
    final outerPaint = Paint()
      ..color = isLevel
          ? AppConstants.success.withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // ── Inner circle (live tilt) ──
    final innerPaint = Paint()
      ..color = isLevel
          ? AppConstants.success
          : AppConstants.accent.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(innerCenter, innerRadius, innerPaint);

    // ── Fill when level ──
    if (isLevel) {
      canvas.drawCircle(
        center,
        innerRadius,
        Paint()..color = AppConstants.success.withValues(alpha: 0.15),
      );
    }

    // ── Hold progress arc ──
    if (holdProgress > 0 && holdProgress < 1) {
      final progressPaint = Paint()
        ..color = AppConstants.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius + 4),
        -math.pi / 2,
        2 * math.pi * holdProgress,
        false,
        progressPaint,
      );
    }

    // ── Center dot ──
    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _LevelingPainter oldDelegate) {
    return oldDelegate.tiltDegrees != tiltDegrees ||
        oldDelegate.isLevel != isLevel ||
        oldDelegate.holdProgress != holdProgress;
  }
}
