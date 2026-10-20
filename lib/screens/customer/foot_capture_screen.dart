import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../utils/card_capture_coach.dart';
import '../../utils/foot_measurement_utils.dart';
import '../../utils/reference_detector.dart';
import 'foot_processing_screen.dart';

/// TODO(paper-scan): Foot-outline segmentation is still simulated
/// downstream in processing. The reference detector here is REAL classical
/// CV ([CvReferenceDetector] over live Y-plane frames); the
/// [SimulatedReferenceDetector] only runs when the image stream is
/// unavailable on a device.
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

  // Per-foot intro gate: the overlay names the foot to scan, and
  // detection only starts once the customer dismisses it.
  bool _showFootIntro = true;

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

  // Corner source: live CV over the image stream, sim fallback when the
  // stream is unavailable. The UI never knows which is behind the seam.
  ReferenceDetector _detector = const CvReferenceDetector();

  // Latest preview frame for the detection tick (cached by reference —
  // bytes are copied at tick time, never held across frames).
  CameraImage? _latestFrame;
  bool _streamActive = false;

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
    _detectionTimer?.cancel();
    _stopFrameStream();
    _cameraController?.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  /// Live Y-plane stream for the CV detector. On failure the sim fallback
  /// takes over so the guided flow still works (coaching authority —
  /// validator + hold dwell + burst — is identical either way).
  Future<void> _startFrameStream() async {
    final controller = _cameraController;
    if (controller == null || _streamActive) return;
    try {
      await controller.startImageStream((image) {
        _latestFrame = image;
      });
      _streamActive = true;
    } catch (e) {
      debugPrint('[FootCapture] Image stream unavailable, sim fallback: $e');
      _streamActive = false;
      _detector = SimulatedReferenceDetector(reference: _reference);
    }
  }

  Future<void> _stopFrameStream() async {
    final controller = _cameraController;
    if (controller == null || !_streamActive) return;
    _streamActive = false;
    _latestFrame = null;
    try {
      await controller.stopImageStream();
    } catch (e) {
      debugPrint('[FootCapture] stopImageStream: $e');
    }
  }

  /// Current corners from whichever detector is active, in preview pixels.
  List<Offset> _currentCorners() {
    final detector = _detector;
    if (detector is SimulatedReferenceDetector) {
      // Proportional sim quad; frame size only sets the scale.
      const frameW = 640;
      const frameH = 480;
      return detector.detect(
        luminance: Uint8List(0),
        frameW: frameW,
        frameH: frameH,
      );
    }
    final frame = _latestFrame;
    if (frame == null || frame.planes.isEmpty) return const [];
    try {
      final yPlane = frame.planes[0];
      final yBytes = yPlane.bytes;
      final rowStride = yPlane.bytesPerRow;
      final pixelStride = yPlane.bytesPerPixel ?? 1;
      if (yBytes.length < rowStride * (frame.height - 1) + frame.width) {
        return const [];
      }
      // Compact copy honoring stride (Y plane is the luminance signal).
      final compact = Uint8List(frame.width * frame.height);
      if (pixelStride == 1 && rowStride == frame.width) {
        compact.setAll(
            0, yBytes.sublist(0, compact.length));
      } else {
        for (var y = 0; y < frame.height; y++) {
          for (var x = 0; x < frame.width; x++) {
            compact[y * frame.width + x] =
                yBytes[y * rowStride + x * pixelStride];
          }
        }
      }
      return detector.detect(
        luminance: compact,
        frameW: frame.width,
        frameH: frame.height,
      );
    } catch (e) {
      debugPrint('[FootCapture] Frame convert: $e');
      return const [];
    }
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
        await _startFrameStream();
        // The intro overlay gates detection: it starts on dismissal.
        if (!_showFootIntro) _startPaperDetection();
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

  /// The intro overlay names the foot to scan; detection starts only
  /// once the customer confirms — so nobody scans blind.
  void _dismissFootIntro() {
    _detectionTimer?.cancel();
    setState(() => _showFootIntro = false);
    _startPaperDetection();
  }

  /// Reference detection loop: live CV corners (or sim fallback) through
  /// the real [coachForDetection] authority every 500ms.
  void _startPaperDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isCapturing) return;

      final corners = _currentCorners();
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
    // takePicture and the image stream are mutually exclusive: stop the
    // stream for the burst, restart it on every exit path below.
    await _stopFrameStream();
    try {
      for (var i = 0; i < cardBurstFrameCount; i++) {
        final XFile image = await _cameraController!.takePicture();
        firstPath ??= image.path;
        // Real per-frame evidence: decode this still and detect (isolate),
        // so the burst IQR reflects actual frame-to-frame spread.
        final bytes = await image.readAsBytes();
        final still = await compute(
          decodeAndDetectStill,
          {'bytes': bytes, 'maxSide': 320},
        );
        if (still.corners.isNotEmpty) {
          final scale = computeScaleFactor(
            paperCorners: still.corners,
            paper: _reference,
          );
          if (scale != null) {
            _burstScales.add(scale);
            _lastGoodCorners = List<Offset>.from(still.corners);
          }
        }
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
      await _startFrameStream();
      _startPaperDetection();
      return;
    }

    if (_currentFoot == 0) {
      // Left done → guide the right foot through the same flow.
      final detector = _detector;
      if (detector is SimulatedReferenceDetector) detector.reset();
      setState(() {
        _currentFoot = 1;
        _holdTicks = 0;
        _showFootIntro = true;
        _guidanceStatus = 'searching';
        _guidanceText =
            'Left foot captured — now place your right foot beside the $_refNoun';
      });
      await _startFrameStream();
      // The right-foot intro gates detection: it restarts on dismissal.
      return;
    }

    // Both feet captured — hand the right-foot burst to processing.
    // NOTE: the left-foot burst is currently discarded after confirming the
    // flow; per-foot persistence + larger-foot-wins comparison land with the
    // dual-foot results wiring (follow-up), not here.
    // (No outline yet — segmentation lands in phases, so processing keeps
    // its explicit simulation until then; burst-still corners are real CV
    // output and already flow through.)
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

          // ── Top Bar (foot indicator + close) ──
          _buildTopBar(),

          // ── Bottom Guidance Bar ──
          _buildBottomBar(),

          // ── Per-foot intro gate ──
          if (_showFootIntro) _buildFootIntro(),
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
  /// Full-screen intro naming the foot to scan, with an explicit confirm.
  /// Shown on entry (left foot) and again before the right-foot pass.
  Widget _buildFootIntro() {
    final foot = _footLabel;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: AppConstants.surfaceLight,
                  borderRadius: AppConstants.premiumCardRadius,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppConstants.accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.accessibility_new_rounded,
                        size: 28,
                        color: AppConstants.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scan your $foot foot',
                      style: AppConstants.headlineStyle(
                        fontSize: 22,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Place your $foot foot beside the $_refNoun, '
                      'both flat on the floor.',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _dismissFootIntro,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.accent,
                          foregroundColor: AppConstants.secondary,
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppConstants.stadiumRadius,
                          ),
                        ),
                        child: Text(
                          'I understand',
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
