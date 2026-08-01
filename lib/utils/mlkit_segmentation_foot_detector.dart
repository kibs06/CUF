/// ML Kit Selfie Segmentation-based foot detector (the §2 fallback).
///
/// This is the segmentation fallback that replaces ML Kit Pose as the primary
/// detector for the close-up scan framing. ML Kit Pose landmark models are
/// tuned for full/partial-body context (hip/knee/ankle relationships) and
/// fail inconsistently on tight foot-only crops; per-pixel person-segmentation
/// does not require body context and works on crops.
///
/// Architecture (§2.2 of POSE_DETECTION_INCONSISTENT_FIX_PROMPT):
/// - Runs `google_mlkit_selfie_segmentation` (same plugin family as the pose
///   detector, same NV21 `InputImage` pipeline — zero new plumbing).
/// - The model returns a per-pixel `SegmentationMask` (foreground confidences).
/// - A general person-segmentation model suffices here because in this scan
///   framing the foot is the largest/closest object in view.
/// - Point extraction from the mask is computed geometrically in
///   [evaluateFootMask] (foot_detector.dart): PCA principal axis → heel/toe,
///   max perpendicular extent → widest pair. No skeleton landmarks involved.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import 'foot_detector.dart';
import 'mlkit_input_helper.dart';

/// [FootDetector] implementation backed by ML Kit Selfie Segmentation.
class MlKitSegmentationFootDetector implements FootDetector {
  final SelfieSegmenter _segmenter;

  MlKitSegmentationFootDetector()
      : _segmenter = SelfieSegmenter(
          // `single` mode: each sampled frame is an independent detection
          // (we sample every 200ms rather than processing a continuous
          // camera stream). Docs recommend `single` for independent images.
          mode: SegmenterMode.single,
          // Raw-size mask (model output, typically ~256×256). Using the raw
          // mask instead of the input-rescaled one cuts the platform-channel
          // payload ~4-5× (65K vs 307K confidence values per 200ms sample,
          // each serialized individually). `evaluateFootMask` normalizes by
          // the mask's own width/height, so normalized hitTest coordinates
          // remain correct in the upright image space.
          enableRawSizeMask: true,
        );

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  }) async {
    try {
      final inputImage = buildNv21InputImage(
        nv21Bytes: nv21Bytes,
        width: width,
        height: height,
        rotationDegrees: rotationDegrees,
      );

      final mask = await _segmenter.processImage(inputImage);
      if (mask == null || mask.confidences.isEmpty) {
        debugPrint('[SegDiag] No segmentation mask returned');
        return const FootDetectionResult.negative();
      }

      // Upright frame dims (swap for 90/270° rotation). Passed so the
      // elongation check runs in true pixel space — the raw mask is square
      // but the upright frame is portrait, and normalized-space elongation
      // would be distorted by the frame aspect ratio.
      final sideways = (rotationDegrees % 180) == 90;
      final uprightW = sideways ? height : width;
      final uprightH = sideways ? width : height;

      final result = evaluateFootMask(
        confidences: mask.confidences,
        width: mask.width,
        height: mask.height,
        preferSide: preferSide,
        guideRect: guideRect,
        frameWidth: uprightW,
        frameHeight: uprightH,
        // TEMP-DEBUG: stage-by-stage pipeline trace for the 0-samples
        // diagnosis (ZERO_SAMPLES_DIAGNOSTIC_PROMPT). Remove after.
        onStageLog: (trace) => debugPrint('[SAMPLE-DEBUG] $trace'),
      );

      if (result.footDetected) {
        debugPrint(
          '[SegDiag] Foot detected (side=${result.footSide}, '
          'conf=${result.confidence.toStringAsFixed(2)}, '
          'mask=${mask.width}x${mask.height}, '
          'heel=${result.heelPoint?.asOffset}, toe=${result.toePoint?.asOffset}, '
          'widthPts=${result.widthPoints?.length})',
        );
      } else {
        debugPrint(
          '[SegDiag] No foot (conf=${result.confidence.toStringAsFixed(2)}, '
          'mask=${mask.width}x${mask.height})',
        );
      }

      return result;
    } catch (e) {
      // Never let a detection error crash the scan loop.
      debugPrint('[SegDiag] Segmentation error: $e');
      return const FootDetectionResult.negative();
    }
  }

  @override
  void dispose() {
    try {
      _segmenter.close();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
