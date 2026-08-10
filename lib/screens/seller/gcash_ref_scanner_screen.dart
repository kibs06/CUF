import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../utils/gcash_ref_extractor.dart';

/// Scan-to-fill GCash reference number using OCR (text recognition — not
/// barcode scanning; GCash receipts print the Ref No. as plain text).
///
/// Flow: camera capture (or gallery photo) → on-device OCR → mandatory
/// confirmation. The detected value is ALWAYS shown to the seller with
/// Use / Retake / Enter-manually options — it is never auto-filled silently.
///
/// Pops with the chosen reference number (digits only), or `null` if the
/// seller bailed out to manual entry / closed the screen.
class GcashRefScannerScreen extends StatefulWidget {
  const GcashRefScannerScreen({super.key});

  @override
  State<GcashRefScannerScreen> createState() => _GcashRefScannerScreenState();
}

enum _ScanPhase { preview, analyzing, confirm }

class _GcashRefScannerScreenState extends State<GcashRefScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _cameraError;

  TextRecognizer? _recognizer;

  _ScanPhase _phase = _ScanPhase.preview;
  String? _capturedPath;
  GcashRefExtraction? _extraction;
  bool _ocrFailed = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    try {
      _recognizer?.close();
    } catch (_) {
      // Best-effort cleanup.
    }
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _cameraError = 'Camera permission is required to scan the '
                'reference number.';
            _isInitializing = false;
          });
        }
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera found on this device.';
            _isInitializing = false;
          });
        }
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint('[GcashRefScan] Camera init error: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Could not start the camera: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_cameraController == null || _isCapturing) return;
    if (!_cameraController!.value.isInitialized) return;

    setState(() => _isCapturing = true);
    try {
      final XFile shot = await _cameraController!.takePicture();
      if (!mounted) return;
      await _analyze(shot.path);
    } catch (e) {
      debugPrint('[GcashRefScan] Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture failed — please try again.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Screenshots are the common case for GCash receipts, so allow picking one
  /// from the gallery as an alternative to pointing the camera at the screen.
  Future<void> _pickFromGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    await _analyze(picked.path);
  }

  Future<void> _analyze(String path) async {
    // Stop the camera sensor while we review/OCR — the seller may spend a
    // while on the confirm screen. `_retake` re-initializes it.
    final camera = _cameraController;
    _cameraController = null;
    camera?.dispose();

    setState(() {
      _phase = _ScanPhase.analyzing;
      _capturedPath = path;
      _extraction = null;
      _ocrFailed = false;
    });

    try {
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(path);
      final recognized = await _recognizer!.processImage(inputImage);

      final lines = <String>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isNotEmpty) lines.add(text);
        }
      }

      final extraction = GcashRefExtractor.extract(lines);
      if (!mounted) return;
      setState(() {
        _extraction = extraction;
        _ocrFailed = false;
        _phase = _ScanPhase.confirm;
      });
    } catch (e) {
      debugPrint('[GcashRefScan] OCR error: $e');
      if (mounted) {
        setState(() {
          _ocrFailed = true;
          _phase = _ScanPhase.confirm;
        });
      }
    }
  }

  void _useReference(String value) => Navigator.of(context).pop(value);

  void _enterManually() => Navigator.of(context).pop(null);

  Future<void> _retake() async {
    setState(() {
      _phase = _ScanPhase.preview;
      _capturedPath = null;
      _extraction = null;
      _ocrFailed = false;
      _isInitializing = true;
    });
    // The camera was disposed after the last capture — start it fresh.
    await _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_phase) {
        _ScanPhase.analyzing => _buildAnalyzingView(),
        _ScanPhase.confirm => _buildConfirmView(),
        _ScanPhase.preview => _buildPreviewView(),
      },
    );
  }

  // ── Preview: live camera + shutter ─────────────────────────────

  Widget _buildPreviewView() {
    return Stack(
      children: [
        if (_isInitializing)
          const Center(
            child: CircularProgressIndicator(color: AppConstants.accent),
          )
        else if (_cameraController != null &&
            _cameraController!.value.isInitialized)
          SizedBox.expand(child: CameraPreview(_cameraController!))
        else
          _buildCameraError(),

        // Top bar
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Row(
            children: [
              _circleButton(
                icon: Icons.close,
                onTap: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              Text(
                'Scan Ref No.',
                style: AppConstants.bodyStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 40),
            ],
          ),
        ),

        // Guidance hint
        Positioned(
          top: MediaQuery.of(context).padding.top + 76,
          left: 20,
          right: 20,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Point at the "Ref No." on the customer\'s screen',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppConstants.accent, width: 4),
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: AppConstants.accent,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: AppConstants.secondary,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                label: Text(
                  'Use a screenshot from gallery',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              _cameraError ?? 'Camera unavailable.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _pickFromGallery,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: Text(
                    'Use gallery photo',
                    style: AppConstants.bodyStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Enter manually',
                    style: AppConstants.bodyStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Analyzing: OCR in progress ─────────────────────────────────

  Widget _buildAnalyzingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(color: AppConstants.accent),
          SizedBox(height: 16),
          Text(
            'Reading reference number…',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Confirm: show the captured photo + the detected value ──────

  Widget _buildConfirmView() {
    final path = _capturedPath;
    return Stack(
      children: [
        // Captured photo as background (dimmed)
        if (path != null && File(path).existsSync())
          Positioned.fill(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              color: Colors.black.withValues(alpha: 0.55),
              colorBlendMode: BlendMode.darken,
            ),
          ),
        // Result card
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SellerTheme.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: SellerTheme.cardBorder),
                boxShadow: AppConstants.sellerShadow,
              ),
              child: _buildResultBody(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultBody() {
    if (_ocrFailed) {
      return _resultMessage(
        icon: Icons.error_outline,
        color: AppConstants.error,
        title: "Couldn't read a reference number",
        message: 'Try holding steadier, use a screenshot, or enter the '
            'number manually.',
        showRetake: true,
        showManual: true,
      );
    }

    final extraction = _extraction;
    if (extraction == null || !extraction.detected) {
      return _resultMessage(
        icon: Icons.find_in_page_outlined,
        color: AppConstants.statusPendingColor,
        title: 'No reference number found',
        message: 'We couldn\'t spot a GCash "Ref No." in that image. '
            'Try again or enter it manually.',
        showRetake: true,
        showManual: true,
      );
    }

    // Detected — show the value and let the seller confirm (never auto-fill).
    final candidates = extraction.candidates;
    if (candidates.length > 1 && !extraction.matchedLabel) {
      // Ambiguous: let the seller pick, don't guess silently.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.help_outline, color: AppConstants.primary, size: 28),
          const SizedBox(height: 8),
          Text(
            'Multiple numbers found — which is the Ref No.?',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ...candidates.map((candidate) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _useReference(candidate),
                child: Text(
                  GcashRefExtractor.formatGrouped(candidate),
                  style: AppConstants.monoStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          _retakeAndManualRow(),
        ],
      );
    }

    final ref = extraction.reference!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppConstants.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.check_circle, color: AppConstants.success, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          'Detected reference number',
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          extraction.displayGrouped,
          textAlign: TextAlign.center,
          style: AppConstants.monoStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'You can still edit it after it is filled in.',
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.primary,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => _useReference(ref),
          child: Text(
            'Use this reference',
            style: AppConstants.bodyStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _retakeAndManualRow(),
      ],
    );
  }

  Widget _retakeAndManualRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _retake,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppConstants.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              'Retake',
              style: AppConstants.bodyStyle(
                color: AppConstants.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextButton(
            onPressed: _enterManually,
            child: Text(
              'Enter manually',
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultMessage({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required bool showRetake,
    required bool showManual,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.7),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        if (showRetake) ...[
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.primary,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _retake,
            child: Text(
              'Try again',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (showManual)
          TextButton(
            onPressed: _enterManually,
            child: Text(
              'Enter manually',
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
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
}
