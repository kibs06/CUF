import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../utils/card_capture_coach.dart';
import '../../utils/foot_measurement_utils.dart';
import 'foot_processing_screen.dart';

/// TODO(paper-scan): The reference detector below is still simulated
/// (corner sets are synthesized, not CV output). The coaching authority is
/// real: every simulated frame goes through [coachForDetection] →
/// [diagnoseReferenceQuad], so tilted/lifted/too-small references re-coach
/// exactly as they will with live CV. Do not ship as a working feature
/// until the real detector lands behind the [ReferenceDetector] seam.
///
/// Guided reference capture screen for foot sizing.
///
/// Shows a live camera feed with guidance overlay for positioning the
/// reference (card, A4, Letter) and foot side-by-side, flat on the floor.
/// Flow per foot: frame → hold still ~1s → auto-capture burst
/// ([cardBurstFrameCount] frames) → next foot. Left first, then right;
/// the larger foot wins downstream in sizing.
class FootCaptureScreen extends StatefulWidget {
  final String paperSize; // 'a4', 'letter', or 'card'
  final String footCondition; // 'bare' or 'socks'

  /// Shopping preference for EU→US conversion ('men', 'women', 'kids').
  final String shoeCategory;

  const FootCaptureScreen({
    super.key,
    required this.paperSize,
    required this.footCondition,
    this.shoeCategory = 'men',
  });

  @override
  State<FootCaptureScreen> createState() => _FootCaptureScreenState();
}

class _FootCaptureScreenState extends State<FootCaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitializing = true;
  bool _isCapturing = false;

  // Capture state
  int _currentFoot = 0; // 0 = left, 1 = right — advances after each burst
  String _guidanceText = 'Point camera at your foot beside the reference';
  String _guidanceStatus =
      'searching'; // searching|detected|holding|ready|burst|tooSmall|tilted|wrongObject

  // Hold-still dwell: consecutive ready ticks (500ms each → 2 = ~1s).
  int _holdTicks = 0;

  // Burst progress 0..cardBurstFrameCount while capturing.
  int _burstTaken = 0;
  bool get _inBurst => _burstTaken > 0 && _isCapturing;

  // Per-frame mm/px scales of the current burst (summarized via IQR).
  final List<double> _burstScales = [];

  // Last validator-approved reference quad: forwarded to processing so the
  // real pipeline can run once an outline is also available. Null until
  // the first measurable frame (never a stale or refused quad).
  List<Offset>? _lastGoodCorners;

  // Simulated detector tick (see _simulatedCorners). Counts frames so the
  // sim can interleave tilted frames that must re-coach through the real
  // validator.
  int _simTick = 0;

  PaperDimensions get _reference => PaperDimensions.fromKey(widget.paperSize);
  String get _footLabel => _currentFoot == 0 ? 'left' : 'right';
  String get _refNoun => _reference.isCard ? 'card' : 'paper';

  // Scan animation
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  // Simulated paper detection (classical CV would replace this)
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _scanLineController.dispose();
    _detectionTimer?.cancel();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      // Request camera permission
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _guidanceText = 'Camera permission required';
            _isInitializing = false;
          });
        }
        return;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _guidanceText = 'No camera found';
            _isInitializing = false;
          });
        }
        return;
      }

      // Use the back camera
      final backCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isInitializing = false);
        _startPaperDetection();
      }
    } catch (e) {
      debugPrint('[FootCapture] Camera init error: $e');
      if (mounted) {
        setState(() {
          _guidanceText = 'Camera error: $e';
          _isInitializing = false;
        });
      }
    }
  }

  /// Reference detection loop.
  ///
  /// SIMULATED until the CV pipeline lands (see file docs): corner sets are
  /// synthesized, but every frame is judged by the real [coachForDetection]
  /// authority — including interleaved tilted frames that must re-coach.
  /// In production this timer becomes the CV callback:
  /// grayscale → Canny → contours → quad → [coachForDetection].
  void _startPaperDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isCapturing) return;
      _simTick++;

      final corners = _simulatedCorners();
      if (corners.isNotEmpty &&
          isPlausibleReferenceQuad(corners, _reference)) {
        _lastGoodCorners = List<Offset>.from(corners);
      }
      final holdProgress =
          (_holdTicks * 500 / cardHoldStillMs).clamp(0.0, 1.0);
      final coach = coachForDetection(
        corners: corners,
        paper: _reference,
        footLabel: _footLabel,
        holdProgress: holdProgress,
      );

      setState(() {
        _guidanceText = coach.message;
        switch (coach.status) {
          case CardCoachStatus.searching:
            _guidanceStatus = 'searching';
            _holdTicks = 0;
          case CardCoachStatus.tooSmall:
            _guidanceStatus = 'tooSmall';
            _holdTicks = 0;
          case CardCoachStatus.tilted:
            _guidanceStatus = 'tilted';
            _holdTicks = 0;
          case CardCoachStatus.wrongObject:
            _guidanceStatus = 'wrongObject';
            _holdTicks = 0;
          case CardCoachStatus.holding:
            _guidanceStatus = _holdTicks > 0 ? 'holding' : 'detected';
            _holdTicks++;
          case CardCoachStatus.ready:
            _guidanceStatus = 'ready';
        }
      });

      // Dwell complete → fire the auto-capture burst (no tap needed).
      if (coach.status == CardCoachStatus.ready) {
        timer.cancel();
        _captureBurst();
      }
    });
  }

  /// Synthesized detector output (SIM — replaced by CV).
  ///
  /// Ticks 0–5: nothing (framing). Then a stable, reference-proportioned
  /// quad with small jitter. Every 7th stable tick emits a keystoned quad
  /// so the tilted re-coach path exercises through the real validator.
  List<Offset> _simulatedCorners() {
    if (_simTick < 6) return const [];
    // Reference-proportioned quad: long edge 200px, short edge by aspect.
    const long = 200.0;
    final short = long / _reference.aspectRatio;
    final jx = ((_simTick % 3) - 1) * 2.0;
    final jy = ((_simTick % 5) - 2) * 2.0;
    if (_simTick % 7 == 0) {
      // Keystoned: top edge pinched (lifted-card look).
      return [
        Offset(140 + jx, 100 + jy),
        Offset(220 + jx, 100 + jy),
        const Offset(260, 200),
        const Offset(60, 200),
      ];
    }
    return [
      Offset(100 + jx, 100 + jy),
      Offset(100 + long + jx, 100 + jy),
      Offset(100 + long + jx, 100 + short + jy),
      Offset(100 + jx, 100 + short + jy),
    ];
  }

  /// Auto-capture burst: [cardBurstFrameCount] frames, ~250ms apart.
  ///
  /// Each frame records its mm/px scale (from the current detection) for
  /// the IQR summary. The burst is kept only if [summarizeScaleSamples]
  /// accepts it; otherwise the user re-captures — never a single frame.
  Future<void> _captureBurst() async {
    if (_cameraController == null || _isCapturing) return;
    setState(() {
      _isCapturing = true;
      _burstTaken = 0;
      _burstScales.clear();
      _guidanceStatus = 'burst';
    });

    String? firstPath;
    try {
      for (var i = 0; i < cardBurstFrameCount; i++) {
        final XFile image = await _cameraController!.takePicture();
        firstPath ??= image.path;
        final scale = computeScaleFactor(
          paperCorners: _simulatedCorners(),
          paper: _reference,
        );
        if (scale != null) _burstScales.add(scale);
        if (mounted) setState(() => _burstTaken = i + 1);
        await Future.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      debugPrint('[FootCapture] Burst error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }

    if (!mounted) return;
    final summary = summarizeScaleSamples(_burstScales);
    setState(() {
      _isCapturing = false;
      _burstTaken = 0;
    });

    if (summary == null || firstPath == null) {
      // Too few valid frames — re-coach, never measure.
      setState(() {
        _guidanceStatus = 'searching';
        _guidanceText =
            'That burst was shaky — hold still and we\'ll retry your $_footLabel foot';
        _holdTicks = 0;
      });
      _startPaperDetection();
      return;
    }

    if (_currentFoot == 0) {
      // Left done → guide the right foot through the same flow.
      setState(() {
        _currentFoot = 1;
        _holdTicks = 0;
        _simTick = 0;
        _guidanceStatus = 'searching';
        _guidanceText =
            'Left foot captured — now place your right foot beside the $_refNoun';
      });
      _startPaperDetection();
      return;
    }

    // Both feet captured — hand the right-foot burst to processing.
    // NOTE: the left-foot burst is currently discarded after confirming the
    // flow; per-foot persistence + larger-foot-wins comparison land with the
    // dual-foot results wiring (follow-up), not here.
    // (No outline yet — segmentation lands in phases, so processing keeps
    // its explicit simulation until then; corners already flow through.)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FootProcessingScreen(
          imagePath: firstPath!,
          paperSize: widget.paperSize,
          footCondition: widget.footCondition,
          footSide: 'right',
          burstScaleMedian: summary.medianScale,
          burstScaleIqr: summary.iqrScale,
          burstFrames: summary.keptCount,
          refCorners: _lastGoodCorners,
          shoeCategory: widget.shoeCategory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera Preview ──
          if (_isInitializing)
            _buildLoadingState()
          else if (_cameraController != null && _cameraController!.value.isInitialized)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            _buildErrorState(),

          // ── Scan Line Animation ──
          if (_guidanceStatus != 'searching')
            AnimatedBuilder(
              animation: _scanLineAnimation,
              builder: (context, child) {
                return Positioned(
                  top: MediaQuery.of(context).size.height * 0.15 +
                      (MediaQuery.of(context).size.height * 0.5 * _scanLineAnimation.value),
                  left: 40,
                  right: 40,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: _guidanceStatus == 'ready'
                          ? AppConstants.success
                          : AppConstants.accent,
                      boxShadow: [
                        BoxShadow(
                          color: (_guidanceStatus == 'ready'
                                  ? AppConstants.success
                                  : AppConstants.accent)
                              .withValues(alpha: 0.8),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // ── Paper Detection Frame ──
          _buildDetectionFrame(),

          // ── Top Bar (foot indicator + close) ──
          _buildTopBar(),

          // ── Bottom Guidance Bar ──
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppConstants.accent,
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            'Initializing camera...',
            style: AppConstants.bodyStyle(
              color: AppConstants.surfaceLight.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: AppConstants.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _guidanceText,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                color: AppConstants.surfaceLight.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppConstants.inkInverse),
              ),
              child: Text(
                'Go Back',
                style: AppConstants.bodyStyle(color: AppConstants.inkInverse),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionFrame() {
    final screenSize = MediaQuery.of(context).size;
    final frameWidth = screenSize.width * 0.75;
    final frameHeight = frameWidth * 1.4; // Paper-like aspect ratio

    return Center(
      child: SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: Stack(
          children: [
            // Corner brackets (matching ARViewPlaceholder style)
            _buildCorner(Alignment.topLeft),
            _buildCorner(Alignment.topRight),
            _buildCorner(Alignment.bottomLeft),
            _buildCorner(Alignment.bottomRight),

            // Border
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _guidanceStatus == 'ready'
                      ? AppConstants.success
                      : AppConstants.accent.withValues(alpha: 0.4),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),

            // Center guide text
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fit_screen_outlined,
                    color: AppConstants.accent.withValues(alpha: 0.4),
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Place foot here',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.surfaceLight.withValues(alpha: 0.5),
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

  Widget _buildCorner(Alignment alignment) {
    const double size = 24;
    const double thickness = 4;
    final double top = (alignment == Alignment.topLeft || alignment == Alignment.topRight) ? 0 : double.nan;
    final double bottom = (alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight) ? 0 : double.nan;
    final double left = (alignment == Alignment.topLeft || alignment == Alignment.bottomLeft) ? 0 : double.nan;
    final double right = (alignment == Alignment.topRight || alignment == Alignment.bottomRight) ? 0 : double.nan;

    return Positioned(
      top: top.isNaN ? null : top,
      bottom: bottom.isNaN ? null : bottom,
      left: left.isNaN ? null : left,
      right: right.isNaN ? null : right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border(
            top: (top == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
            bottom: (bottom == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
            left: (left == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
            right: (right == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 20,
      right: 20,
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
              child: Icon(
                Icons.close,
                color: AppConstants.inkInverse,
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
                  _currentFoot == 0 ? Icons.accessibility_new : Icons.accessibility_new,
                  color: AppConstants.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentFoot == 0 ? 'Left Foot' : 'Right Foot',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.inkInverse,
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
      bottom: MediaQuery.of(context).padding.bottom + 24,
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
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _inBurst || _guidanceStatus == 'ready'
                        ? AppConstants.success
                        : _guidanceStatus == 'detected' ||
                                _guidanceStatus == 'holding'
                            ? AppConstants.accent
                            : _guidanceStatus == 'tilted' ||
                                    _guidanceStatus == 'tooSmall' ||
                                    _guidanceStatus == 'wrongObject'
                                ? AppConstants.error
                                : AppConstants.surfaceLight
                                    .withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _guidanceText,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.surfaceLight.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Capture indicator — auto-capture needs no tap; the ring shows
          // hold-still dwell, then the burst frame count.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _inBurst || _guidanceStatus == 'ready'
                  ? AppConstants.success
                  : _guidanceStatus == 'holding' ||
                          _guidanceStatus == 'detected'
                      ? AppConstants.accent
                      : AppConstants.surfaceLight.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
            ),
            child: Center(
              child: _inBurst
                  ? Text(
                      '$_burstTaken/$cardBurstFrameCount',
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _guidanceStatus == 'tilted' ||
                                  _guidanceStatus == 'tooSmall' ||
                                  _guidanceStatus == 'wrongObject'
                              ? Icons.warning_amber_outlined
                              : Icons.camera_alt,
                          color: Colors.white,
                          size: 32,
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
