import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/card_capture_coach.dart' show burstConfidenceLevel;
import '../../utils/card_measurement_pipeline.dart';
import '../../utils/foot_measurement_utils.dart';
import 'foot_results_screen.dart';

/// TODO(paper-scan): This screen currently uses SIMULATED measurements
/// and a SIMULATED timer-based detection progression. The real CV pipeline
/// (paper corner detection, foot segmentation, scale-factor computation)
/// is not yet implemented. Do not ship this as a working feature.
///
/// Processing screen that runs the ML pipeline on a captured foot image.
///
/// This screen:
/// 1. Loads the captured image
/// 2. Runs paper corner detection (classical CV)
/// 3. Runs TFLite body segmentation to isolate the foot
/// 4. Computes foot length and width using the scale factor
/// 5. Maps measurements to EU/US/UK shoe sizes
///
/// Shows progress feedback to the user during processing.
class FootProcessingScreen extends StatefulWidget {
  final String imagePath;
  final String paperSize; // 'a4', 'letter', or 'card'
  final String footCondition; // 'bare' or 'socks'
  final String footSide; // 'left' or 'right'

  /// Burst scale summary from the capture screen (mm/px median + IQR
  /// spread + kept frames). Null for legacy single captures; when present
  /// the reported reference confidence comes from the burst IQR spread
  /// instead of the hardcoded simulation value.
  final double? burstScaleMedian;
  final double? burstScaleIqr;
  final int? burstFrames;

  /// Last good reference quad from the capture burst (image pixels).
  /// Foot outline from segmentation (image pixels). Both present → the
  /// real [measureCardCapture] pipeline runs; otherwise the explicit
  /// simulation below runs (detector/segmentation still land in phases).
  final List<Offset>? refCorners;
  final List<Offset>? footOutline;

  /// Shopping preference for EU→US conversion ('men', 'women', 'kids').
  final String shoeCategory;

  const FootProcessingScreen({
    super.key,
    required this.imagePath,
    required this.paperSize,
    required this.footCondition,
    required this.footSide,
    this.burstScaleMedian,
    this.burstScaleIqr,
    this.burstFrames,
    this.refCorners,
    this.footOutline,
    this.shoeCategory = 'men',
  });

  @override
  State<FootProcessingScreen> createState() => _FootProcessingScreenState();
}

class _FootProcessingScreenState extends State<FootProcessingScreen>
    with SingleTickerProviderStateMixin {
  String _currentStep = 'Loading image...';
  double _progress = 0.0;
  String? _error;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    // Start processing after a brief delay for the UI to render
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _startProcessing();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startProcessing() async {
    try {
      // Step 1: Load image
      setState(() {
        _currentStep = 'Loading captured image...';
        _progress = 0.1;
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Paper detection
      setState(() {
        _currentStep = 'Detecting paper boundaries...';
        _progress = 0.25;
      });
      // In production: run classical CV edge detection + contour finding
      // For now, simulate with known paper dimensions
      await Future.delayed(const Duration(milliseconds: 800));

      // Step 3: Compute scale factor
      setState(() {
        _currentStep = 'Computing scale factor...';
        _progress = 0.4;
      });
      // In production: use detected paper corners to compute actual scale
      // For simulation, use a reasonable scale based on typical phone camera
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 4: Foot segmentation
      setState(() {
        _currentStep = 'Segmenting foot outline...';
        _progress = 0.55;
      });
      // In production: run TFLite body segmentation model
      // Then extract the foot region using the paper boundary as mask
      await Future.delayed(const Duration(milliseconds: 1000));

      // Step 5: Compute measurements
      setState(() {
        _currentStep = 'Calculating measurements...';
        _progress = 0.75;
      });
      // Real pipeline when the capture forwarded corners + outline;
      // otherwise the explicit simulation (see file docs).
      final real = _runRealPipeline();
      if (real != null && !real.isOk) {
        if (mounted) {
          setState(() {
            _error = _failureCopy(real.failure!);
          });
        }
        return;
      }
      final footLengthMm =
          real?.success?.lengthMm ?? _simulateFootLength();
      final footWidthMm = real?.success?.widthMm ??
          _simulateFootWidth(footLengthMm);
      final recommendation = real?.success?.recommendation;
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 6: Map to shoe sizes
      setState(() {
        _currentStep = 'Mapping to shoe sizes...';
        _progress = 0.9;
      });
      final euSize = recommendation?.eu ?? footLengthMmToEuSize(footLengthMm);
      final usSize = recommendation?.us ??
          (euSize != null ? euToUs(euSize, category: widget.shoeCategory) : null);
      final ukSize =
          recommendation?.uk ?? (euSize != null ? euToUk(euSize) : null);
      await Future.delayed(const Duration(milliseconds: 400));

      setState(() {
        _progress = 1.0;
        _currentStep = 'Complete!';
      });
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      // Navigate to results screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FootResultsScreen(
            footSide: widget.footSide,
            footLengthMm: footLengthMm,
            footWidthMm: footWidthMm,
            euSize: euSize,
            usSize: usSize,
            ukSize: ukSize,
            paperSize: widget.paperSize,
            footCondition: widget.footCondition,
            paperConfidence: _burstConfidence(),
            lightingQuality: 0.88,
            shoeCategory: widget.shoeCategory,
            sizeRangeLow: recommendation?.rangeLowEu,
            sizeRangeHigh: recommendation?.rangeHighEu,
            sizeConfidenceLabel: recommendation?.confidenceLabel,
            sizeRecommendationReason: recommendation?.reason,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FootProcessing] Error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  /// Simulate a realistic foot length based on the foot side.
  ///
  /// In production, this would come from the actual ML pipeline output.
  /// Right feet are typically ~2-3mm shorter than left feet on average.
  double _simulateFootLength() {
    final baseLength = widget.footSide == 'left' ? 265.0 : 262.0;
    // Add small random variation (±5mm)
    final random = DateTime.now().microsecondsSinceEpoch % 10 - 5;
    return baseLength + random;
  }

  /// Simulate foot width based on length (typical ratio is ~38-40% of length).
  double _simulateFootWidth(double lengthMm) {
    return lengthMm * 0.39;
  }

  /// Reference confidence from the burst IQR spread when available:
  /// a tight burst (IQR ≈ 0) scores ~0.99, a spread burst degrades toward
  /// 0.2 (re-coach territory). Falls back to the simulation value for
  /// legacy single captures.
  double _burstConfidence() {
    final median = widget.burstScaleMedian;
    final iqr = widget.burstScaleIqr;
    if (median == null || iqr == null || !(median > 0)) return 0.92;
    return (1.0 - (iqr / median) * 8).clamp(0.2, 0.99);
  }

  /// Real validator-gated pipeline. Null when the capture did not forward
  /// corners + outline + burst stats (simulation path keeps running).
  CardMeasurementOutcome? _runRealPipeline() {
    final corners = widget.refCorners;
    final outline = widget.footOutline;
    final median = widget.burstScaleMedian;
    final iqr = widget.burstScaleIqr;
    final frames = widget.burstFrames;
    if (corners == null ||
        outline == null ||
        median == null ||
        iqr == null ||
        frames == null) {
      return null;
    }
    return measureCardCapture(
      refCorners: corners,
      footOutline: outline,
      paper: PaperDimensions.fromKey(widget.paperSize),
      isSocks: widget.footCondition == 'socks',
      measurementSource: 'paper',
      confidenceLevel: burstConfidenceLevel(
        scaleMedian: median,
        scaleIqr: iqr,
      ),
      shoeCategory: widget.shoeCategory,
      scaleMedian: median,
      scaleIqrMmPerPx: iqr,
      burstFrames: frames,
    );
  }

  /// Retake coaching for a pipeline refusal (shown in the error state).
  String _failureCopy(CardMeasurementFailure failure) {
    switch (failure) {
      case CardMeasurementFailure.referenceInvalid:
        return 'The reference shifted mid-capture — retake with the '
            '${widget.paperSize == 'card' ? 'card' : 'paper'} flat on the floor.';
      case CardMeasurementFailure.outlineInvalid:
        return 'We couldn\'t isolate the foot outline — retake with the '
            'whole foot in frame and good light.';
      case CardMeasurementFailure.implausibleMeasurement:
        return 'That measurement doesn\'t look like a foot — check the '
            'reference is fully visible and retake.';
      case CardMeasurementFailure.sizingOutOfRange:
        return 'That foot falls outside our size chart — try our in-store fitting.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceDark,
      body: Stack(
        children: [
          // Background image (darkened)
          if (File(widget.imagePath).existsSync())
            Positioned.fill(
              child: Opacity(
                opacity: 0.3,
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Processing UI
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Processing indicator
                  _buildProcessingIndicator(),
                  const SizedBox(height: 32),

                  // Step text
                  Text(
                    _currentStep,
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.inkInverse,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress bar
                  _buildProgressBar(),
                  const SizedBox(height: 16),

                  // Foot side indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppConstants.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.footSide == 'left' ? 'Left Foot' : 'Right Foot',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.accent,
                      ),
                    ),
                  ),

                  // Error state
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppConstants.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, color: AppConstants.error, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            'Processing failed',
                            style: AppConstants.bodyStyle(
                              color: AppConstants.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.surfaceLight.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppConstants.inkInverse),
                            ),
                            child: Text(
                              'Try Again',
                              style: AppConstants.bodyStyle(color: AppConstants.inkInverse),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppConstants.accent.withValues(alpha: 0.1 + (_pulseController.value * 0.15)),
            border: Border.all(
              color: AppConstants.accent.withValues(alpha: 0.3 + (_pulseController.value * 0.3)),
              width: 2,
            ),
          ),
          child: Center(
            child: _progress >= 1.0
                ? const Icon(
                    Icons.check_circle_outline,
                    color: AppConstants.success,
                    size: 40,
                  )
                : SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppConstants.accent,
                      value: _progress,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: AppConstants.surfaceLight.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(AppConstants.accent),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(_progress * 100).round()}%',
          style: AppConstants.monoStyle(
            fontSize: 12,
            color: AppConstants.surfaceLight.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
