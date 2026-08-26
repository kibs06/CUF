import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../providers/auto_scan_controller.dart';
// TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
import '../../services/diag_logger.dart' show navDiag;
import '../../services/ar_core_channel.dart';
import '../../utils/ar_foot_measurement_pipeline.dart' show scanDuration;
import '../../utils/foot_detector.dart';
import '../../utils/foot_measurement_utils.dart' show mapNormalizedToView;
import 'foot_floor_detection_screen.dart' show FloorReference;
import 'foot_manual_measure_screen.dart';
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
///
/// All sampling/state-machine logic lives in [AutoScanController] (Phase 1
/// extraction — behavior-preserving); this widget renders controller state,
/// requests camera permission, owns animations, and performs the navigation/
/// snackbar reactions to one-shot controller events.
class FootArScanScreen extends StatefulWidget {
  final String footCondition; // 'bare' or 'socks'

  /// Shopping preference for EU→US conversion ('men', 'women', 'kids').
  final String shoeCategory;

  /// Optional floor reference captured by the floor-detection screen
  /// (floor-plane normal + a confirmed point on the floor plane).
  final FloorReference? floorReference;

  const FootArScanScreen({
    super.key,
    required this.footCondition,
    this.shoeCategory = 'men',
    this.floorReference,
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

  // ── Controller (all scan/session/state-machine logic) ──
  late final AutoScanController _scan;

  // ── Widget-owned concerns ──
  StreamSubscription<AutoScanEvent>? _scanEventsSub;

  /// Previous [_scan.scanActive] value — drives the progress-ring
  /// forward/stop edges (previously inline in start/endScan).
  bool _prevScanActive = false;

  /// Whether the debug overlay is drawn on the camera preview.
  bool _showDebugOverlay = true;

  // ── Animations ──
  late AnimationController _pulseController;
  late AnimationController _progressController;

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

    _scan = AutoScanController(
      footCondition: widget.footCondition,
      shoeCategory: widget.shoeCategory,
    );
    _scan.addListener(_onScanChanged);
    _scanEventsSub = _scan.events.listen(_onScanEvent);

    _initializeSession();
  }

  @override
  void dispose() {
    _scanEventsSub?.cancel();
    _scan.removeListener(_onScanChanged);
    _pulseController.dispose();
    _progressController.dispose();
    // Cancels timers/event subscriptions, disposes the detector and stops
    // the ARCore session (the teardown the widget previously did itself).
    _scan.dispose();
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
        setState(() => _scan.reportCameraPermissionDenied());
      }
      return;
    }

    await _scan.initialize();
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTROLLER WIRING
  // ═══════════════════════════════════════════════════════════════

  void _onScanChanged() {
    if (!mounted) return;

    // Drive the pass progress ring from scanActive edges (previously the
    // inline `forward(from: 0)` / `stop()` calls in start/endScan).
    final active = _scan.scanActive;
    if (active && !_prevScanActive) {
      _progressController.forward(from: 0);
    } else if (!active && _prevScanActive) {
      _progressController.stop();
    }
    _prevScanActive = active;

    setState(() {});
  }

  /// Reacts to one-shot outcomes. Controllers don't navigate or show
  /// snackbars themselves — the screen does, in response to these events.
  void _onScanEvent(AutoScanEvent event) {
    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] AutoScan screen received ${event.runtimeType} '
        '(mounted=$mounted)');
    if (!mounted) return;

    switch (event) {
      case LeftFootDoneEvent(:final lengthMm):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Left foot: ${lengthMm.toStringAsFixed(0)}mm — now scan right foot'),
            backgroundColor: AppConstants.success,
          ),
        );
      case SideCombineFailedEvent():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Not enough valid samples. Hold steady and keep the foot inside the guide box.',
            ),
            backgroundColor: AppConstants.error,
          ),
        );
      case ScanCompletedEvent(:final payload):
        // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
        navDiag('[NAV-DEBUG] AutoScan pushReplacement → FootResultsScreen '
            '(canPop=${Navigator.of(context).canPop()})');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FootResultsScreen(
              footSide: payload.footSide,
              footLengthMm: payload.footLengthMm,
              footWidthMm: payload.footWidthMm,
              footLengthRightMm: payload.footLengthRightMm,
              footWidthRightMm: payload.footWidthRightMm,
              euSize: payload.euSize,
              usSize: payload.usSize,
              ukSize: payload.ukSize,
              paperSize: payload.paperSize,
              footCondition: payload.footCondition,
              paperConfidence: payload.paperConfidence,
              lightingQuality: payload.lightingQuality,
              confidenceLevel: payload.confidenceLevel,
              confidenceScore: payload.confidenceScore,
              leftSampleCount: payload.leftSampleCount,
              rightSampleCount: payload.rightSampleCount,
              // v2 fields
              measurementSource: payload.measurementSource,
              shoeCategory: payload.shoeCategory,
              sizingFootSide: payload.sizingFootSide,
              widthCategory: payload.widthCategory,
              leftLengthComp: payload.leftLengthComp,
              leftWidthComp: payload.leftWidthComp,
              rightLengthComp: payload.rightLengthComp,
              rightWidthComp: payload.rightWidthComp,
              sizeRecommendationReason: payload.sizeRecommendationReason,
            ),
          ),
        );
    }
  }

  /// §8: Stall fallback — navigate to Guided Tap mode carrying over the
  /// already-selected foot/side/options so the user doesn't restart.
  void _switchToGuidedTap() {
    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] AutoScan pushReplacement → FootManualMeasureScreen '
        '(canPop=${Navigator.of(context).canPop()})');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FootManualMeasureScreen(
          footCondition: widget.footCondition,
          shoeCategory: widget.shoeCategory,
          smartAssistEnabled: true,
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

          // ── Debug Detection Overlay (heel/toe/width points) ──
          if (_showDebugOverlay) _buildDebugOverlay(),

          // ── Guided Capture Guide Box (§2.3) ──
          if (_scan.guidanceState == 'scanning' || _scan.guidanceState == 'ready')
            _buildGuideBox(),

          // ── Guidance Overlay ──
          _buildGuidanceOverlay(),

          // ── Top Bar ──
          _buildTopBar(),

          // ── Bottom Bar ──
          _buildBottomBar(),

          // ── Processing Overlay ──
          if (_scan.processing) _buildProcessingOverlay(),
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
    final detection = _scan.lastDetection;
    if (detection == null ||
        !detection.footDetected ||
        detection.heelPoint == null ||
        detection.toePoint == null) {
      return const SizedBox.shrink();
    }

    final uprightW = (_scan.lastFrameRotation % 180) == 90
        ? _scan.lastFrameHeight
        : _scan.lastFrameWidth;
    final uprightH = (_scan.lastFrameRotation % 180) == 90
        ? _scan.lastFrameWidth
        : _scan.lastFrameHeight;

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
    final uprightW = (_scan.lastFrameRotation % 180) == 90
        ? _scan.lastFrameHeight
        : _scan.lastFrameWidth;
    final uprightH = (_scan.lastFrameRotation % 180) == 90
        ? _scan.lastFrameWidth
        : _scan.lastFrameHeight;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GuideBoxPainter(
            guideRect: _scan.currentGuideRect,
            frameWidth: uprightW,
            frameHeight: uprightH,
            active: _scan.guidanceState == 'scanning',
            label: _scan.captureStep == 'front' ? 'TOP VIEW' : 'SIDE VIEW',
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
          if (_scan.guidanceState == 'scanning') ...[
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
              '${_scan.currentSampleCount} samples',
              style: AppConstants.monoStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.accent,
              ),
            ),
          ] else if (_scan.guidanceState == 'ready') ...[
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
          ] else if (_scan.guidanceState == 'searching') ...[
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
                  color: _scan.currentFoot == 0 ? AppConstants.accent : AppConstants.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _scan.currentFoot == 0 ? 'Left Foot' : 'Right Foot',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (_scan.leftFootHasSamples && _scan.currentFoot == 1) ...[
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
              color: _scan.captureStep == 'front'
                  ? AppConstants.accent.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _scan.captureStep == 'front'
                      ? Icons.arrow_drop_down_circle_outlined
                      : Icons.arrow_forward_rounded,
                  size: 14,
                  color: _scan.captureStep == 'front'
                      ? AppConstants.accent
                      : AppConstants.success,
                ),
                const SizedBox(width: 4),
                Text(
                  _scan.captureStep == 'front' ? 'TOP' : 'SIDE',
                  style: AppConstants.monoStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _scan.captureStep == 'front'
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
                    color: _scan.trackingState == ArTrackingState.tracking
                        ? AppConstants.success
                        : _scan.trackingState == ArTrackingState.limited
                            ? Colors.amber
                            : AppConstants.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _scan.trackingState == ArTrackingState.tracking
                      ? 'TRACKING'
                      : _scan.trackingState == ArTrackingState.limited
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
                    color: _scan.guidanceState == 'ready'
                        ? AppConstants.success
                        : _scan.guidanceState == 'scanning'
                            ? AppConstants.accent
                            : Colors.white.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _scan.guidanceText,
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
          if (_scan.scanActive) _buildFootDetectionChip(),

          const SizedBox(height: 16),

          // Action button
          if (_scan.guidanceState == 'ready' && !_scan.scanActive)
            GestureDetector(
              onTap: _scan.startScan,
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
          else if (_scan.guidanceState == 'error')
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // §4/§6: explicit failure state with a real retry action
                if (_scan.noFootFailure) ...[
                  FilledButton.icon(
                    onPressed: _scan.retryScan,
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
                // §8: Stall fallback — switch to Guided Tap mode
                if (_scan.validDetectionsThisPass == 0) ...[
                  FilledButton.icon(
                    onPressed: _switchToGuidedTap,
                    icon: const Icon(Icons.touch_app_outlined, size: 18),
                    label: const Text('Switch to Guided Tap'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.success,
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
    // §1: `footDetected` is driven by the temporal gate on the COMBINED
    // quality score (≥ kSampleAcceptScore), so it's the authoritative signal
    // — a score-based acceptance model replaces the old binary confidence
    // check (which would disagree with the scoring under weighted gating).
    final detected = _scan.footDetected;

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
              _scan.processingStep,
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
    if (_scan.guidanceState != 'scanning') return null; // Only during live capture
    final isFront = _scan.captureStep == 'front';
    final valueMm = isFront ? _scan.liveWidthMm : _scan.liveLengthMm;
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
