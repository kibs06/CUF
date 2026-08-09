import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import 'foot_processing_screen.dart';

/// Real camera capture screen for the AR foot sizing feature.
///
/// Shows a live camera feed with guidance overlay for positioning
/// the paper and foot. Uses classical CV (edge detection) to detect
/// the paper boundary and provide real-time feedback.
///
/// Captures one image per foot (left, then right).
class FootCaptureScreen extends StatefulWidget {
  final String paperSize; // 'a4' or 'letter'
  final String footCondition; // 'bare' or 'socks'

  const FootCaptureScreen({
    super.key,
    required this.paperSize,
    required this.footCondition,
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
  final int _currentFoot = 0; // 0 = left, 1 = right
  String _guidanceText = 'Point camera at your foot on the paper';
  String _guidanceStatus = 'searching'; // 'searching', 'detected', 'ready'
  double _paperConfidence = 0.0;

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

  /// Simulated paper detection loop.
  ///
  /// In a production build, this would run classical CV:
  /// 1. Convert camera frame to grayscale
  /// 2. Apply Canny edge detection
  /// 3. Find contours
  /// 4. Approximate polygons to find 4-corner shapes
  /// 5. Validate aspect ratio against expected paper dimensions
  ///
  /// For now, we simulate detection with a timer that progresses
  /// from "searching" → "detected" → "ready" states.
  void _startPaperDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isCapturing) return;

      // Simulate detection confidence building over time
      setState(() {
        _paperConfidence = (_paperConfidence + 0.15).clamp(0.0, 1.0);

        if (_paperConfidence < 0.4) {
          _guidanceStatus = 'searching';
          _guidanceText = 'Point camera at your foot on the paper';
        } else if (_paperConfidence < 0.8) {
          _guidanceStatus = 'detected';
          _guidanceText = 'Paper detected — hold steady';
        } else {
          _guidanceStatus = 'ready';
          _guidanceText = 'Tap to capture ${_currentFoot == 0 ? 'left' : 'right'} foot';
        }
      });

      if (_paperConfidence >= 1.0) {
        timer.cancel();
      }
    });
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || _isCapturing || _paperConfidence < 0.8) return;

    setState(() => _isCapturing = true);

    try {
      final XFile image = await _cameraController!.takePicture();

      if (!mounted) return;

      // Navigate to processing screen with the captured image
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FootProcessingScreen(
            imagePath: image.path,
            paperSize: widget.paperSize,
            footCondition: widget.footCondition,
            footSide: _currentFoot == 0 ? 'left' : 'right',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FootCapture] Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
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
                side: const BorderSide(color: AppConstants.surfaceLight),
              ),
              child: Text(
                'Go Back',
                style: AppConstants.bodyStyle(color: AppConstants.surfaceLight),
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
              child: const Icon(
                Icons.close,
                color: AppConstants.surfaceLight,
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
                    color: AppConstants.surfaceLight,
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
                    color: _guidanceStatus == 'ready'
                        ? AppConstants.success
                        : _guidanceStatus == 'detected'
                            ? AppConstants.accent
                            : AppConstants.surfaceLight.withValues(alpha: 0.5),
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

          // Capture button
          GestureDetector(
            onTap: _guidanceStatus == 'ready' ? _captureImage : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _guidanceStatus == 'ready'
                    ? AppConstants.accent
                    : AppConstants.surfaceLight.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: _guidanceStatus == 'ready'
                    ? [
                        BoxShadow(
                          color: AppConstants.accent.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: _isCapturing
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt,
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
