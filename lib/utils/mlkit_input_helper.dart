/// Shared helpers for building ML Kit [InputImage]s from the ARCore NV21
/// camera frames.
///
/// Both the pose detector and the segmentation detector convert the same
/// ARCore NV21 frame into an [InputImage] with identical metadata (upright
/// rotation, NV21 format). Centralizing that keeps the two detectors
/// consistent and avoids duplicating ~20 lines per implementation.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Build an [InputImage] from an NV21-encoded camera frame.
///
/// [width]/[height] are the sensor-orientation dimensions.
/// [rotationDegrees] is the rotation that makes the image upright.
InputImage buildNv21InputImage({
  required Uint8List nv21Bytes,
  required int width,
  required int height,
  required int rotationDegrees,
}) {
  return InputImage.fromBytes(
    bytes: nv21Bytes,
    metadata: InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotationFromDegrees(rotationDegrees),
      format: InputImageFormat.nv21,
      bytesPerRow: width,
    ),
  );
}

/// Map a rotation in degrees (0/90/180/270) to an [InputImageRotation].
InputImageRotation rotationFromDegrees(int degrees) {
  switch (degrees) {
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      return InputImageRotation.rotation0deg;
  }
}
