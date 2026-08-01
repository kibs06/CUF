/// ML Kit Pose-based foot detector.
///
/// Uses the `google_mlkit_pose_detection` plugin (already a dependency) to
/// detect the heel (`leftHeel`/`rightHeel`) and foot-index (toe area,
/// `leftFootIndex`/`rightFootIndex`) landmarks from the 33-point pose skeleton.
///
/// This is the "Option A" implementation from the implementation brief:
/// - Gates the scan: if neither foot's heel+toe pair is above
///   [minFootDetectionConfidence], the frame is treated as "no foot".
/// - Extracts heel + toe points in normalized image coordinates that feed
///   directly into the ARCore hitTest raycast step.
///
/// Known limitation (flagged for real-device testing): pose landmark models
/// are tuned for a foot at the end of a visible leg at "normal" distance.
/// Close-up top-down foot-only framing may produce lower likelihoods; the
/// confidence threshold ([minFootDetectionConfidence]) is the tuning knob.
/// If accuracy is insufficient, swap in a segmentation-based detector via the
/// [FootDetector] interface without touching the scan screen.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint;

// google_mlkit_pose_detection re-exports google_mlkit_commons
// (PoseLandmark, PoseDetector, etc.).
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'foot_detector.dart';
import 'mlkit_input_helper.dart';

/// [FootDetector] implementation backed by ML Kit Pose landmark detection.
class MlKitPoseFootDetector implements FootDetector {
  final PoseDetector _detector;

  MlKitPoseFootDetector({
    PoseDetectionModel model = PoseDetectionModel.base,
  }) : _detector = PoseDetector(
          options: PoseDetectorOptions(
            // `single` mode: each sampled frame is an independent detection
            // (we sample every 200ms rather than processing a continuous
            // camera stream). Docs recommend `single` for independent images.
            model: model,
            mode: PoseDetectionMode.single,
          ),
        );

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect, // Unused: pose landmarks have no mask/guide concept
  }) async {
    try {
      final inputImage = buildNv21InputImage(
        nv21Bytes: nv21Bytes,
        width: width,
        height: height,
        rotationDegrees: rotationDegrees,
      );

      final poses = await _detector.processImage(inputImage);
      if (poses.isEmpty) {
        _logRawConfidences(
          poseCount: 0,
          leftHeel: null,
          leftToe: null,
          rightHeel: null,
          rightToe: null,
          frameWidth: width,
          frameHeight: height,
          rotationDegrees: rotationDegrees,
        );
        return const FootDetectionResult.negative();
      }

      // ML Kit returns landmark coordinates in the upright (post-rotation)
      // image space. Normalize by the rotated image dimensions so points are
      // in 0.0–1.0 space matching ARCore hitTest.
      final isSideways = (rotationDegrees % 180) == 90;
      final rotatedWidth = isSideways ? height : width;
      final rotatedHeight = isSideways ? width : height;

      FootDetectionResult? bestResult;
      for (final pose in poses) {
        final lm = pose.landmarks;
        _logRawConfidences(
          poseCount: poses.length,
          leftHeel: lm[PoseLandmarkType.leftHeel],
          leftToe: lm[PoseLandmarkType.leftFootIndex],
          rightHeel: lm[PoseLandmarkType.rightHeel],
          rightToe: lm[PoseLandmarkType.rightFootIndex],
          frameWidth: width,
          frameHeight: height,
          rotationDegrees: rotationDegrees,
        );
        final result = evaluateFootLandmarks(
          leftHeel: _toLandmarkInput(lm[PoseLandmarkType.leftHeel], rotatedWidth, rotatedHeight),
          leftToe: _toLandmarkInput(lm[PoseLandmarkType.leftFootIndex], rotatedWidth, rotatedHeight),
          rightHeel: _toLandmarkInput(lm[PoseLandmarkType.rightHeel], rotatedWidth, rotatedHeight),
          rightToe: _toLandmarkInput(lm[PoseLandmarkType.rightFootIndex], rotatedWidth, rotatedHeight),
          preferSide: preferSide,
        );

        if (result.footDetected &&
            (bestResult == null || result.confidence > bestResult.confidence)) {
          bestResult = result;
        }
      }

      return bestResult ?? const FootDetectionResult.negative();
    } catch (e) {
      // Never let a detection error crash the scan loop.
      return const FootDetectionResult.negative();
    }
  }

  /// Temporary §1 diagnostic: log RAW per-landmark likelihood values (before
  /// any thresholding) so real-device logs can confirm whether failures are
  /// framing/context (consistently low likelihoods / zero poses on tight
  /// crops) vs. motion blur (low only while moving) vs. a threshold issue
  /// (moderate values just under [minFootDetectionConfidence]).
  void _logRawConfidences({
    required int poseCount,
    required PoseLandmark? leftHeel,
    required PoseLandmark? leftToe,
    required PoseLandmark? rightHeel,
    required PoseLandmark? rightToe,
    required int frameWidth,
    required int frameHeight,
    required int rotationDegrees,
  }) {
    String fmt(PoseLandmark? lm) =>
        lm == null ? 'absent' : lm.likelihood.toStringAsFixed(2);
    debugPrint(
      '[PoseDiag] poses=$poseCount '
      'Lheel=${fmt(leftHeel)} Ltoe=${fmt(leftToe)} '
      'Rheel=${fmt(rightHeel)} Rtoe=${fmt(rightToe)} '
      'frame=${frameWidth}x$frameHeight rot=$rotationDegrees',
    );
  }

  /// Convert an ML Kit [PoseLandmark] to a normalized [LandmarkInput].
  LandmarkInput? _toLandmarkInput(
    PoseLandmark? landmark,
    int imageWidth,
    int imageHeight,
  ) {
    if (landmark == null) return null;
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    return LandmarkInput(
      x: (landmark.x / imageWidth).clamp(0.0, 1.0),
      y: (landmark.y / imageHeight).clamp(0.0, 1.0),
      likelihood: landmark.likelihood.clamp(0.0, 1.0),
    );
  }

  @override
  void dispose() {
    try {
      _detector.close();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
