import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../providers/guided_tap_controller.dart';
// TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
import '../../services/diag_logger.dart' show navDiag;
import '../../services/ar_core_channel.dart';
import '../../utils/foot_detector.dart';
import '../../utils/foot_measurement_utils.dart';
import 'foot_floor_detection_screen.dart' show FloorReference;
import 'foot_results_screen.dart';

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
///
/// Phase 1 refactor: all non-rendering logic (session init, tap/drag raycasts,
/// pair state machine, smart-assist sampling, results computation) lives in
/// [GuidedTapController]; this widget renders its state, forwards gestures,
/// and performs navigation purely as a response to controller events/state.
class FootManualMeasureScreen extends StatefulWidget {
  final String footCondition; // 'bare' or 'socks'

  /// Whether the optional smart-assist layer (§6) is enabled. When false, no
  /// background segmentation sampler runs and no suggestions are shown — the
  /// flow is fully manual. Defaults to true; the instructions screen exposes
  /// a toggle for this.
  final bool smartAssistEnabled;

  /// Shopping preference for EU→US conversion ('men', 'women', 'kids').
  final String shoeCategory;

  /// Optional floor reference captured by the floor-detection screen
  /// (floor-plane normal + a confirmed point on the floor plane). When
  /// provided, measurements can be computed relative to this locked
  /// reference instead of ARCore's live floor estimate (reduces drift).
  final FloorReference? floorReference;

  const FootManualMeasureScreen({
    super.key,
    required this.footCondition,
    this.smartAssistEnabled = true,
    this.shoeCategory = 'men',
    this.floorReference,
  });

  @override
  State<FootManualMeasureScreen> createState() => _FootManualMeasureScreenState();
}

class _FootManualMeasureScreenState extends State<FootManualMeasureScreen>
    with TickerProviderStateMixin {
  // ── Controller (all non-rendering logic; Phase 1 extraction) ──
  late final GuidedTapController _scan;
  StreamSubscription<GuidedTapEvent>? _eventsSub;

  // ── Animations ──
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _scan = GuidedTapController(
      footCondition: widget.footCondition,
      shoeCategory: widget.shoeCategory,
      smartAssistEnabled: widget.smartAssistEnabled,
      floorReference: widget.floorReference,
    );
    _scan.addListener(_onScanChanged);
    _eventsSub = _scan.events.listen(_onScanEvent);

    _requestPermissionAndInit();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _scan.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onScanChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// One-shot outcomes → navigation. Controllers never navigate themselves;
  /// the screen reacts to controller events with the exact same route push
  /// the pre-extraction inline code performed.
  void _onScanEvent(GuidedTapEvent event) {
    // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
    navDiag('[NAV-DEBUG] GuidedTap screen received ${event.runtimeType} '
        '(mounted=$mounted)');
    if (!mounted) return;
    switch (event) {
      case MeasurementCompletedEvent(:final payload):
        // TEMP-DEBUG [NAV-DEBUG]: phase 1b diagnosis — remove after fix verified.
        navDiag('[NAV-DEBUG] GuidedTap pushReplacement → FootResultsScreen '
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
              manualMode: payload.manualMode,
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

  Future<void> _requestPermissionAndInit() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        _scan.reportCameraPermissionDenied();
      }
      return;
    }

    await _scan.initialize();
  }

  // ═════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════

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
              _scan.updateViewSize(size); // Cached for the smart-assist sampler
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _scan.handleTapAt(d.localPosition, size),
                onPanStart: (d) => _scan.onPanStart(d.localPosition),
                onPanUpdate: (d) => _scan.onPanUpdate(d.localPosition, size),
                onPanEnd: (_) => _scan.onPanEnd(),
                child: CustomPaint(
                  painter: _ManualPointsPainter(
                    pointA: _scan.pointA?.screen,
                    pointB: _scan.pointB?.screen,
                    liveCursor:
                        _scan.pairPhase == 1 ? size.center(Offset.zero) : null,
                    liveDistanceMm: _scan.liveDistanceMm,
                    showCrosshair: _scan.pairPhase < 2,
                    isFront: _scan.captureStep == 'front',
                    draggingIndex: _scan.dragIndex,
                    suggestionA: _scan.suggestion?.a,
                    suggestionB: _scan.suggestion?.b,
                    suggestionConfidence: _scan.suggestion?.confidence,
                  ),
                ),
              );
            }),
          ),

          // ── Guide box (placement aid; §3.2 region reference) ──
          if (_scan.guidanceState == 'ready' || _scan.guidanceState == 'searching')
            _buildGuideBox(),

          // ── Guidance Overlay ──
          _buildGuidanceOverlay(),

          // ── Feedback toast ──
          if (_scan.tapFeedback != null) _buildFeedbackToast(),

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
            guideRect: _scan.currentGuideRect,
            frameWidth: _scan.uprightWidth,
            frameHeight: _scan.uprightHeight,
            active: _scan.guidanceState == 'ready',
            label: _scan.captureStep == 'front' ? 'FRONT VIEW' : 'SIDE VIEW',
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
          if (_scan.guidanceState == 'ready') ...[
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
                  _scan.tapFeedback!,
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
                  color: _scan.currentFoot == 0
                      ? AppConstants.accent
                      : AppConstants.success,
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
                if (_scan.currentFoot == 1) ...[
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
                  _scan.captureStep == 'front' ? 'WIDTH' : 'LENGTH',
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
      ),
    );
  }

  Widget _buildBottomBar() {
    final showConfirm = _scan.pairPhase == 2;
    final showHint =
        _scan.guidanceState == 'ready' && !showConfirm && _scan.pairPhase < 2;

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
                    color: _scan.guidanceState == 'ready'
                        ? AppConstants.success
                        : _scan.guidanceState == 'error'
                            ? AppConstants.error
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

          // Live measurement pill while placing point B (§2.3)
          if (_scan.pairPhase == 1 && _scan.liveDistanceMm != null) ...[
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
                  onTap: _scan.trashPair,
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
                    onTap: _scan.confirmPair,
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
                          'Confirm ${_scan.captureStep == 'front' ? 'Width' : 'Length'}',
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
                if (_scan.pairPhase == 0 && _scan.suggestion != null) ...[
                  GestureDetector(
                    onTap: _scan.acceptSuggestion,
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
                if (_scan.pairPhase == 1) ...[
                  GestureDetector(
                    onTap: _scan.trashPair,
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
                        _scan.pairPhase == 0
                            ? Icons.touch_app_outlined
                            : Icons.my_location,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _scan.pairPhase == 0
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
          else if (_scan.guidanceState == 'error')
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
    final conf = _scan.suggestion?.confidence;
    if (conf == null) return 'Use suggested points';
    final pct = (conf.clamp(0.0, 1.0) * 100).round();
    return 'Use suggested points · $pct%';
  }

  /// Live measurement text for the in-progress pair (§2.3).
  String _liveMeasureText() {
    final mm = _scan.liveDistanceMm;
    if (mm == null) return 'measuring…';
    final cm = mm / 10;
    final isFront = _scan.captureStep == 'front';
    final minCm = isFront ? kHardRejectMinWidthCm : kHardRejectMinLengthCm;
    final maxCm = isFront ? kHardRejectMaxWidthCm : kHardRejectMaxLengthCm;
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
