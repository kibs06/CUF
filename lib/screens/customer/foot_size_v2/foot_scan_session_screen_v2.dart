import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../../../constants/app_constants.dart';
import '../../../providers/v2/scan_phase.dart';
import '../../../providers/v2/scan_session_controller.dart';
import '../../../services/ar_core_channel.dart' show ArTrackingState;
import '../../../utils/ar_foot_measurement_pipeline.dart' show idealSampleCount;
import '../../../utils/foot_detector.dart' show FootPoint;
import '../../../utils/foot_measurement_utils.dart' show mapNormalizedToView;
import '../../../widgets/foot_size_v2/foot_trace_overlay.dart';
import '../../../widgets/foot_size_v2/scan_instruction_overlay.dart';
import 'foot_scan_results_screen_v2.dart';
import '../../../widgets/foot_size_v2/glass_card.dart';
import '../../../widgets/foot_size_v2/scan_stepper.dart';

/// Foot Size 2.0 scan session — full-bleed AR view with the "stepper scan
/// flow" overlay system:
/// - Top: 4-segment animated progress stepper
/// - Center: guide frame for the current capture step (normalized coords
///   mapped through the same center-crop transform as v1)
/// - Coaching: one floating glass card, swapped via [AnimatedSwitcher]
/// - Live cm readout chip while capturing
/// - Bottom: morphing action button with sweep-ring capture progress
///
/// ONE screen hosts all four captures — no route transitions mid-session.
class FootScanSessionScreenV2 extends StatefulWidget {
  final String footCondition; // 'bare' | 'socks'
  final String shoeCategory; // 'men' | 'women' | 'kids'

  const FootScanSessionScreenV2({
    super.key,
    required this.footCondition,
    this.shoeCategory = 'men',
  });

  @override
  State<FootScanSessionScreenV2> createState() =>
      _FootScanSessionScreenV2State();
}

class _FootScanSessionScreenV2State extends State<FootScanSessionScreenV2>
    with TickerProviderStateMixin {
  late final ScanSessionController _session;
  StreamSubscription<ScanSessionEvent>? _eventsSub;
  bool _navigatedToResults = false;

  /// GIF-style instruction demo state: auto-plays once per capture step,
  /// dismissible, replayable via the "How to scan" chip.
  bool _showInstructions = false;
  CaptureStep? _instructionsShownFor;

  /// Drives the guide bracket's idle "breathing" scale while waiting.
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _session = ScanSessionController(
      footCondition: widget.footCondition,
      shoeCategory: widget.shoeCategory,
    );
    _session.addListener(_onSessionChanged);
    _eventsSub = _session.events.listen(_onSessionEvent);
    _session.initialize();

    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _session.removeListener(_onSessionChanged);
    _breathe.dispose();
    // Cancels timers + detector. Native teardown stays owned by PlatformView
    // disposal (D1 rule).
    _session.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // Auto-play the instruction demo once per new capture step, and drop it
    // the moment a capture starts.
    if (_session.phase == ScanPhase.ready &&
        _instructionsShownFor != _session.currentStep) {
      _instructionsShownFor = _session.currentStep;
      _showInstructions = true;
    }
    if (_session.phase == ScanPhase.capturing && _showInstructions) {
      _showInstructions = false;
    }
    setState(() {});
  }

  Future<void> _onSessionEvent(ScanSessionEvent event) async {
    switch (event) {
      case StepCompletedEvent():
        HapticFeedback.mediumImpact();
      case FootCompletedEvent():
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppConstants.success,
            content: Text(
              '${event.footSide == 'left' ? 'Left' : 'Right'} foot done — '
              '${event.lengthMm.round()} mm',
              style: AppConstants.bodyStyle(color: Colors.white),
            ),
          ),
        );
      case ScanCompleteEvent():
        if (_navigatedToResults || !mounted) return;
        _navigatedToResults = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                FootScanResultsScreenV2(payload: event.payload),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Report the view geometry so area probes and the guide box stay inside
    // the center-cropped visible band. Store-only setter — build-safe.
    final size = MediaQuery.sizeOf(context);
    _session.viewAspectRatio = size.width / size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── AR camera feed ──
          if (_session.phase != ScanPhase.needsPermission &&
              _session.phase != ScanPhase.startFailed)
            _buildArView(),

          // ── Guide frame (ready/capturing only) ──
          if (_session.phase == ScanPhase.ready ||
              _session.phase == ScanPhase.capturing ||
              _session.phase == ScanPhase.stepComplete)
            _buildGuideFrame(),

          // ── Live foot-trace scan animation (during capture) ──
          if (_session.phase == ScanPhase.capturing)
            Positioned.fill(
              child: FootTraceOverlay(
                progress: _session.passSampleCount / idealSampleCount,
                active: true,
              ),
            ),

          // ── Detection points debug overlay ──
          if (_showDebugOverlay) _buildDetectionOverlay(),

          // ── Foreground chrome ──
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      _GlassIconButton(icon: Icons.close_rounded, onTap: () {
                        _session.cancelCapture();
                        Navigator.of(context).pop();
                      }),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: ScanStepper(
                            activeIndex: _activeStepIndex,
                            activeProgress: _session.captureProgress,
                            capturing: _session.phase == ScanPhase.capturing,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _buildCoachArea(),
                _buildBottomControls(),
              ],
            ),
          ),

          // ── Full-screen states over dimmed camera ──
          if (_session.phase == ScanPhase.startFailed)
            _buildStartFailedSheet(),

          // ── Looping instruction demo (auto-plays once per step) ──
          if (_showInstructions &&
              (_session.phase == ScanPhase.ready ||
                  _session.phase == ScanPhase.stepComplete))
            ScanInstructionOverlay(
              step: _session.currentStep,
              onDismiss: () => setState(() => _showInstructions = false),
            ),

          if (_session.phase == ScanPhase.processing)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  int? get _activeStepIndex =>
      _session.phase == ScanPhase.capturing ||
              _session.phase == ScanPhase.stepComplete
          ? _session.currentStep.index
          : null;

  /// Debug overlay (detection points) — flip to true for on-device debugging.
  /// Ships OFF: it draws raw detection geometry over the camera in release.
  static const bool _showDebugOverlay = false;

  // ═════════════════════════════════════════════════════════════════
  // AR PLATFORM VIEW (identical wiring to v1's foot_ar_scan_screen)
  // ═════════════════════════════════════════════════════════════════

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

  // ═════════════════════════════════════════════════════════════════
  // GUIDE FRAME
  // ═════════════════════════════════════════════════════════════════

  Widget _buildGuideFrame() {
    final uprightW = (_session.lastFrameRotation % 180) == 90
        ? _session.lastFrameHeight
        : _session.lastFrameWidth;
    final uprightH = (_session.lastFrameRotation % 180) == 90
        ? _session.lastFrameWidth
        : _session.lastFrameHeight;

    final locked =
        _session.phase == ScanPhase.capturing && _session.footDetected;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _breathe,
          builder: (context, _) => CustomPaint(
            painter: _GuideBracketPainter(
              // Clamped to the visible crop band — the raw side rect extends
              // past the screen edges on tall phones (box drawn off-screen).
              guideRect: _session.effectiveGuideRect,
              frameWidth: uprightW,
              frameHeight: uprightH,
              locked: locked,
              // 1.00–1.03 breathing while unlocked; solid when locked.
              breathe: locked ? 0 : 0.03 * _breathe.value,
              label: _session.currentStep.captureAngle == 'front'
                  ? 'TOP VIEW'
                  : 'SIDE VIEW',
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // DETECTION OVERLAY (debug — same projection math as v1)
  // ═════════════════════════════════════════════════════════════════

  Widget _buildDetectionOverlay() {
    final detection = _session.lastDetection;
    if (detection == null ||
        !detection.footDetected ||
        detection.heelPoint == null ||
        detection.toePoint == null) {
      return const SizedBox.shrink();
    }

    final uprightW = (_session.lastFrameRotation % 180) == 90
        ? _session.lastFrameHeight
        : _session.lastFrameWidth;
    final uprightH = (_session.lastFrameRotation % 180) == 90
        ? _session.lastFrameWidth
        : _session.lastFrameHeight;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DetectionPointsPainter(
            heel: detection.heelPoint!,
            toe: detection.toePoint!,
            widthPoints: detection.widthPoints,
            frameWidth: uprightW,
            frameHeight: uprightH,
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // COACHING CARD + LIVE READOUT
  // ═════════════════════════════════════════════════════════════════

  Widget _buildCoachArea() {
    final hint = _coachHintForPhase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Replay chip for the looping instruction demo.
          if (!_showInstructions &&
              (_session.phase == ScanPhase.ready ||
                  _session.phase == ScanPhase.stepComplete))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                key: const Key('how-to-scan-chip'),
                onTap: () => setState(() => _showInstructions = true),
                child: GlassCard(
                  tone: GlassTone.neutral,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_outline_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'How to scan',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Live cm readout during capture.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _session.phase == ScanPhase.capturing &&
                    _session.liveLengthMm != null &&
                    _isPlausibleLive()
                ? Padding(
                    key: ValueKey('live-${_session.liveLengthMm!.round()}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      tone: GlassTone.active,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        '${(_session.liveLengthMm! / 10).toStringAsFixed(1)} cm',
                        style: AppConstants.monoStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('live-empty')),
          ),

          // The single coaching message.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: GlassCard(
              key: ValueKey(hint.reason),
              tone: _glassTone(hint.tone),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(hintIcon(hint), color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      hintText(hint),
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  CoachHint _coachHintForPhase() {
    final hint = _session.coachHint;
    if (hint != null) return hint;
    // Fallbacks before initialize completes / between states.
    return const CoachHint(
      reason: CoachReason.findFloor,
      tone: CoachTone.neutral,
    );
  }

  GlassTone _glassTone(CoachTone tone) {
    switch (tone) {
      case CoachTone.neutral:
        return GlassTone.neutral;
      case CoachTone.active:
        return GlassTone.active;
      case CoachTone.success:
        return GlassTone.success;
      case CoachTone.warning:
        return GlassTone.warning;
    }
  }

  IconData hintIcon(CoachHint hint) {
    switch (hint.reason) {
      case CoachReason.findFloor:
        return Icons.explore_outlined;
      case CoachReason.moveSlowly:
        return Icons.speed_outlined;
      case CoachReason.positionFoot:
        return Icons.crop_free_rounded;
      case CoachReason.holdStill:
        return Icons.center_focus_strong_rounded;
      case CoachReason.havingTrouble:
        return Icons.waving_hand_outlined;
      case CoachReason.stepDone:
      case CoachReason.footDone:
        return Icons.check_circle_outline_rounded;
    }
  }

  String hintText(CoachHint hint) {
    final stepLabel = _session.currentStep.captureAngle == 'front'
        ? 'top view'
        : 'side view';
    switch (hint.reason) {
      case CoachReason.findFloor:
        return 'Move your phone slowly over the floor';
      case CoachReason.moveSlowly:
        return 'Keep moving gently — tracking is limited here';
      case CoachReason.positionFoot:
        return 'Position your $stepLabel inside the frame';
      case CoachReason.holdStill:
        return 'Hold still — measuring…';
      case CoachReason.havingTrouble:
        return 'Having trouble? Good lighting and a textured floor help.';
      case CoachReason.stepDone:
        return 'Got it!';
      case CoachReason.footDone:
        return hint.footLengthMm != null
            ? 'Foot measured — ${hint.footLengthMm!.round()} mm'
            : 'Foot measured!';
    }
  }

  bool _isPlausibleLive() {
    final lenCm = (_session.liveLengthMm ?? 0) / 10;
    final widCm = (_session.liveWidthMm ?? 0) / 10;
    return lenCm >= 10 && lenCm <= 40 && widCm >= 4 && widCm <= 18;
  }

  // ═════════════════════════════════════════════════════════════════
  // BOTTOM CONTROLS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildBottomControls() {
    final phase = _session.phase;

    Widget action;
    switch (phase) {
      case ScanPhase.capturing:
        action = _CaptureRingButton(progress: _session.captureProgress);
      case ScanPhase.starting || ScanPhase.positioning:
        action = _MorphButton(
          label: 'Looking for the floor…',
          enabled: false,
          icon: Icons.radar_rounded,
        );
      case ScanPhase.ready || ScanPhase.stepComplete:
        final ready = _session.areaTracked &&
            _session.trackingState == ArTrackingState.tracking;
        action = _MorphButton(
          label: ready ? 'Measure ${_stepLabel()}' : 'Aim at the floor first',
          enabled: ready,
          icon: Icons.photo_camera_outlined,
          onTap: ready ? _session.startCapture : null,
        );
      default:
        action = const SizedBox(height: 56);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey(phase),
          child: SizedBox(width: double.infinity, height: 56, child: action),
        ),
      ),
    );
  }

  String _stepLabel() {
    switch (_session.currentStep) {
      case CaptureStep.leftTop:
        return 'left foot · top';
      case CaptureStep.leftSide:
        return 'left foot · side';
      case CaptureStep.rightTop:
        return 'right foot · top';
      case CaptureStep.rightSide:
        return 'right foot · side';
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // START-FAILED SHEET
  // ═════════════════════════════════════════════════════════════════

  Widget _buildStartFailedSheet() {
    final reason = _session.startFailureReason;
    final (icon, title, message) = switch (reason) {
      'needs_install' => (
          Icons.downloading_rounded,
          'Finishing AR setup',
          'Google Play is installing ARCore. Try again in a moment.',
        ),
      'unsupported_device' ||
      'user_opted_out' ||
      'unsupported' =>
        (
          Icons.block_outlined,
          'AR not available',
          "This device can't run AR scanning. Use the original Get Your Foot "
              'Size flow instead.',
        ),
      'timeout' => (
          Icons.wifi_off_outlined,
          'AR took too long to start',
          'Check your connection and try again.',
        ),
      _ => (
          Icons.error_outline,
          'Could not start AR',
          _session.startFailureMessage ?? 'Please try again.',
        ),
    };

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: GlassCard(
              borderRadius: BorderRadius.circular(24),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 44),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: AppConstants.headlineStyle(
                        fontSize: 19, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side:
                              BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => _retryStart(),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.accent,
                          foregroundColor: AppConstants.secondary,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryStart() async {
    await _session.initialize();
  }
}

// ═══════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Stadium button used in idle phases; morphs between enabled/disabled copy.
class _MorphButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final IconData icon;
  final VoidCallback? onTap;

  const _MorphButton({
    required this.label,
    required this.enabled,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: enabled ? 1 : 0.5,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppConstants.accent,
          foregroundColor: AppConstants.secondary,
          shape: const RoundedRectangleBorder(
            borderRadius: AppConstants.stadiumRadius,
          ),
        ),
        icon: Icon(icon),
        label: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
      ),
    );
  }
}

/// Shutter-style button with a sweep ring showing capture progress.
class _CaptureRingButton extends StatefulWidget {
  final double progress;

  const _CaptureRingButton({required this.progress});

  @override
  State<_CaptureRingButton> createState() => _CaptureRingButtonState();
}

class _CaptureRingButtonState extends State<_CaptureRingButton> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _RingPainter(progress: widget.progress.clamp(0.0, 1.0)),
            ),
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.accent,
                ),
                child: const Icon(Icons.center_focus_strong_rounded,
                    color: AppConstants.secondary, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: 0.25);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppConstants.accent;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -90 * 3.141592653589793 / 180,
      2 * 3.141592653589793 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════

/// Corner-bracket viewfinder for the current capture step. Same normalized →
/// center-crop mapping as v1's guide box so it aligns with what the
/// segmentation mask sees.
class _GuideBracketPainter extends CustomPainter {
  final Rect guideRect; // normalized
  final int frameWidth;
  final int frameHeight;
  final bool locked;

  /// Extra scale factor (0–~0.03) applied around the bracket center to make
  /// it "breathe" while waiting for the user.
  final double breathe;
  final String label;

  static const double _bracketLen = 26;

  _GuideBracketPainter({
    required this.guideRect,
    required this.frameWidth,
    required this.frameHeight,
    required this.locked,
    this.breathe = 0,
    required this.label,
  });

  Color get _color => locked ? AppConstants.accent : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    var topLeft =
        mapNormalizedToView(guideRect.topLeft, size, frameWidth: frameWidth, frameHeight: frameHeight);
    var bottomRight = mapNormalizedToView(
        guideRect.bottomRight, size,
        frameWidth: frameWidth, frameHeight: frameHeight);
    var rect = Rect.fromPoints(topLeft, bottomRight);

    if (breathe > 0) {
      rect = rect.inflate(rect.longestSide * breathe);
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = locked ? 4 : 3
      ..strokeCap = StrokeCap.round
      ..color = _color.withValues(alpha: locked ? 1 : 0.85);

    // Four corner brackets.
    final corners = [
      (rect.topLeft, const Offset(1, 1)),
      (rect.topRight, const Offset(-1, 1)),
      (rect.bottomLeft, const Offset(1, -1)),
      (rect.bottomRight, const Offset(-1, -1)),
    ];
    for (final (corner, dir) in corners) {
      canvas.drawLine(corner, corner + Offset(dir.dx * _bracketLen, 0), paint);
      canvas.drawLine(corner, corner + Offset(0, dir.dy * _bracketLen), paint);
    }

    // Step label above the bracket.
    final textSpan = TextSpan(
      text: label,
      style: AppConstants.bodyStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: _color,
        letterSpacing: 1.2,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left, rect.top - tp.height - 6));
  }

  @override
  bool shouldRepaint(covariant _GuideBracketPainter oldDelegate) =>
      oldDelegate.locked != locked ||
      oldDelegate.breathe != breathe ||
      oldDelegate.guideRect != guideRect ||
      oldDelegate.frameWidth != frameWidth ||
      oldDelegate.frameHeight != frameHeight;
}

/// Glow dots for detected heel/toe/width points + dashed link (debug overlay).
class _DetectionPointsPainter extends CustomPainter {
  final FootPoint heel;
  final FootPoint toe;
  final List<FootPoint>? widthPoints;
  final int frameWidth;
  final int frameHeight;

  _DetectionPointsPainter({
    required this.heel,
    required this.toe,
    required this.widthPoints,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset toView(FootPoint p) => mapNormalizedToView(
        p.asOffset, size,
        frameWidth: frameWidth, frameHeight: frameHeight);

    final dot = Paint()..color = AppConstants.accent;
    final halo = Paint()
      ..color = AppConstants.accent.withValues(alpha: 0.25);

    for (final p in [heel, toe, ...?widthPoints]) {
      final c = toView(p);
      canvas.drawCircle(c, 9, halo);
      canvas.drawCircle(c, 4, dot);
    }

    // Dashed heel→toe link.
    final a = toView(heel);
    final b = toView(toe);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.7);
    const seg = 8.0;
    const gap = 6.0;
    final dist = (b - a).distance;
    if (dist == 0) return;
    var t = 0.0;
    while (t < dist) {
      final next = (t + seg).clamp(0.0, dist);
      canvas.drawLine(
        Offset.lerp(a, b, t / dist)!,
        Offset.lerp(a, b, next / dist)!,
        dash,
      );
      t = next + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPointsPainter oldDelegate) => true;
}
