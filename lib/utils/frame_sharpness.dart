/// Blur detection for the foot scan's camera frames (pure Dart, no Flutter).
///
/// A blurry frame smears the foot's outline, so the heel, toe and width points
/// land a few pixels off the true edge, and at foot scale a few pixels is
/// millimetres. The scan drops frames whose sharpness falls below
/// [kMinFrameSharpness] instead of letting them into the median.
library;

import 'dart:typed_data';

/// Minimum sharpness (Laplacian variance of the luma plane) for a frame to
/// count as a sample.
///
/// Untuned starting point: calibrate it on the device by comparing the scores
/// of a sharp frame and a deliberately blurred one before trusting it.
const double kMinFrameSharpness = 15.0;

/// Variance of the 4-neighbour Laplacian over the luma (Y) plane of an NV21
/// frame. Higher means sharper edges.
///
/// Samples every [step]-th pixel to keep it cheap on a full camera frame. Returns
/// 0 when the frame is too small or its luma plane is truncated, so a malformed
/// frame is rejected rather than trusted.
double frameSharpness(
  Uint8List nv21,
  int width,
  int height, {
  int step = 2,
}) {
  if (width < 3 || height < 3 || step < 1) return 0;
  if (nv21.length < width * height) return 0;

  var count = 0;
  var sum = 0.0;
  var sumSquares = 0.0;
  for (var y = 1; y < height - 1; y += step) {
    for (var x = 1; x < width - 1; x += step) {
      final i = y * width + x;
      final laplacian = 4 * nv21[i] -
          nv21[i - 1] -
          nv21[i + 1] -
          nv21[i - width] -
          nv21[i + width];
      sum += laplacian;
      sumSquares += laplacian * laplacian;
      count++;
    }
  }
  if (count == 0) return 0;

  final mean = sum / count;
  return sumSquares / count - mean * mean;
}
