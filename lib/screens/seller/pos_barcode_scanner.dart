import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../constants/app_constants.dart';

/// Full-screen barcode/QR scanner for the POS flow.
///
/// Returns the scanned barcode string via [Navigator.pop] on success,
/// or `null` if the user dismisses without scanning.
class PosBarcodeScanner extends StatefulWidget {
  const PosBarcodeScanner({super.key});

  @override
  State<PosBarcodeScanner> createState() => _PosBarcodeScannerState();
}

class _PosBarcodeScannerState extends State<PosBarcodeScanner> {
  MobileScannerController? _cameraController;
  bool _permissionDenied = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    // Start after first frame to avoid dispose-during-init issues
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _cameraController?.start();
      } catch (_) {
        if (mounted) setState(() => _permissionDenied = true);
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    if (code.isEmpty) return;

    // Tangible scan feedback before the screen pops with the result.
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() => _isProcessing = true);
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return _buildPermissionDeniedView();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          if (_cameraController != null)
            MobileScanner(
              controller: _cameraController!,
              onDetect: _onDetect,
            ),

          // Scan overlay
          _buildScanOverlay(),

          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _buildCircleButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Text(
                  'Scan Barcode',
                  style: AppConstants.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 40), // Balance for back button
              ],
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Point camera at product barcode or QR code',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.7;
        final topOffset = (constraints.maxHeight - scanAreaSize) / 2;

        return Stack(
          children: [
            // Dark overlay with cutout
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black45,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                  ),
                  Positioned(
                    top: topOffset,
                    left: (constraints.maxWidth - scanAreaSize) / 2,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scan area border
            Positioned(
              top: topOffset,
              left: (constraints.maxWidth - scanAreaSize) / 2,
              child: Container(
                width: scanAreaSize,
                height: scanAreaSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppConstants.accent,
                    width: 3,
                  ),
                ),
              ),
            ),

            // Corner accents
            ..._buildCornerAccents(
              top: topOffset,
              left: (constraints.maxWidth - scanAreaSize) / 2,
              size: scanAreaSize,
            ),

            // Animated scanning line — sweeps the scan area continuously.
            Positioned(
              top: topOffset,
              left: (constraints.maxWidth - scanAreaSize) / 2,
              width: scanAreaSize,
              height: scanAreaSize,
              child: const _ScanningLineAnimation(),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildCornerAccents({
    required double top,
    required double left,
    required double size,
  }) {
    const cornerSize = 24.0;
    const cornerWidth = 3.0;
    final corners = [
      // Top-left
      Positioned(
        top: top - cornerWidth / 2,
        left: left - cornerWidth / 2,
        child: _buildCorner(cornerSize, CornerAlign.topLeft),
      ),
      // Top-right
      Positioned(
        top: top - cornerWidth / 2,
        left: left + size - cornerSize + cornerWidth / 2,
        child: _buildCorner(cornerSize, CornerAlign.topRight),
      ),
      // Bottom-left
      Positioned(
        top: top + size - cornerSize + cornerWidth / 2,
        left: left - cornerWidth / 2,
        child: _buildCorner(cornerSize, CornerAlign.bottomLeft),
      ),
      // Bottom-right
      Positioned(
        top: top + size - cornerSize + cornerWidth / 2,
        left: left + size - cornerSize + cornerWidth / 2,
        child: _buildCorner(cornerSize, CornerAlign.bottomRight),
      ),
    ];
    return corners;
  }

  Widget _buildCorner(double size, CornerAlign align) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border(
          top: align == CornerAlign.topLeft || align == CornerAlign.topRight
              ? const BorderSide(color: AppConstants.accent, width: 3)
              : BorderSide.none,
          bottom:
              align == CornerAlign.bottomLeft || align == CornerAlign.bottomRight
                  ? const BorderSide(color: AppConstants.accent, width: 3)
                  : BorderSide.none,
          left: align == CornerAlign.topLeft || align == CornerAlign.bottomLeft
              ? const BorderSide(color: AppConstants.accent, width: 3)
              : BorderSide.none,
          right:
              align == CornerAlign.topRight || align == CornerAlign.bottomRight
                  ? const BorderSide(color: AppConstants.accent, width: 3)
                  : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Camera Permission',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              Text(
                'Camera Access Required',
                style: AppConstants.bodyStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'CUFMAI needs camera access to scan product barcodes. '
                'Please enable camera permission in your device settings.',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Go Back',
                  style: AppConstants.bodyStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Continuously sweeping teal line inside the scan area — the classic
/// "this is scanning" affordance. Loops via a repeating controller; the
/// ease-in-out curve makes the sweep feel like a smooth breath.
class _ScanningLineAnimation extends StatefulWidget {
  const _ScanningLineAnimation();

  @override
  State<_ScanningLineAnimation> createState() => _ScanningLineAnimationState();
}

class _ScanningLineAnimationState extends State<_ScanningLineAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const lineHeight = 22.0;
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final top = 2 +
                _progress.value * (constraints.maxHeight - lineHeight - 4);
            // Positioned must be a direct child of a Stack (ParentData rule) —
            // neither LayoutBuilder nor AnimatedBuilder can host it directly.
            return Stack(
              children: [
                Positioned(
                  top: top,
                  left: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: Container(
                      height: lineHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppConstants.accent.withValues(alpha: 0),
                            AppConstants.accent.withValues(alpha: 0.55),
                            AppConstants.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppConstants.accent,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AppConstants.accent
                                    .withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum CornerAlign { topLeft, topRight, bottomLeft, bottomRight }
