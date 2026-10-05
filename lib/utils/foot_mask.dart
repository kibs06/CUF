/// The foot mask's vocabulary for V4.4 — the foreground field that makes the
/// foot read as **inside** the shoe.
///
/// The native side receives a [kFootMaskSize]² byte mask over
/// `com.solevision/ar_try_on`'s `setFootMask`, turns it into a mesh and draws
/// the camera's own pixels over the shoe through it (`FootMaskMesh` /
/// `FootMaskOverlay` in the Android plugin). Everything here is pure and
/// deterministic: the wire format is decided in one place and — for the same
/// reasons the pose points are — the mask's orientation is a test, not a
/// device question.
///
/// **Orientation, and why it needs stating.** The mask is row-major, top-down,
/// x→u and y→v, in the user's `FootDetectionResult` normalized space — i.e.
/// exactly the space `heelPoint`/`toePoint` are expressed in. The Android side
/// maps a mask quad through the same upright-image→viewport mapping it raycasts
/// the heel and toe through, so the occlusion lands where the pose landed, with
/// no second convention to disagree with the first.
library;

import 'dart:typed_data';

/// The foot mask's on-the-wire side — §2.10's "~32×32".
///
/// The detector's raw segmentation mask is typically 256×256 (65 K confidence
/// values, each of which the platform channel serializes individually). 32×32
/// is 1 KB per accepted frame at ≥5 Hz, and it is more than a silhouette needs:
/// the Android side dilates and upsamples before it becomes geometry.
const int kFootMaskSize = 32;

/// Box-averages a segmentation mask into a [size]×[size] byte mask
/// (0–255, `round(mean × 255)`).
///
/// [confidences] is the per-pixel foreground probability in row-major order,
/// top-down, in the **mask's own** normalized space — the same input
/// `evaluateFootMask` takes, and the same space the resulting points are
/// normalized in. [width]/[height] are the mask's dimensions; they may be
/// smaller or larger than [size].
///
/// **Total by construction, never throwing.** Degenerate input (empty,
/// non-positive dimensions, a truncated buffer) returns a zero-filled mask, and
/// non-finite samples are skipped rather than propagated. That is the right
/// failure for an auxiliary draw: a zero mask on the wire is a shoe with no
/// occlusion over it for one frame, not a stopped detection loop.
Uint8List downsampleFootMask(
  List<double> confidences,
  int width,
  int height, {
  int size = kFootMaskSize,
}) {
  final out = Uint8List(size * size);
  if (size <= 0 || width <= 0 || height <= 0) return out;
  if (confidences.length < width * height) return out;

  for (var oy = 0; oy < size; oy++) {
    final y0 = (oy * height) ~/ size;
    // At least one row, at most the mask: the clamp is what keeps the last
    // output cell reaching the image edge when `size` does not divide `height`.
    final y1 = (((oy + 1) * height) ~/ size).clamp(y0 + 1, height);
    for (var ox = 0; ox < size; ox++) {
      final x0 = (ox * width) ~/ size;
      final x1 = (((ox + 1) * width) ~/ size).clamp(x0 + 1, width);

      var sum = 0.0;
      var count = 0;
      for (var y = y0; y < y1; y++) {
        final row = y * width;
        for (var x = x0; x < x1; x++) {
          final v = confidences[row + x];
          if (!v.isFinite) continue;
          sum += v.clamp(0.0, 1.0);
          count++;
        }
      }
      final mean = count == 0 ? 0.0 : sum / count;
      out[oy * size + ox] = (mean * 255.0).round().clamp(0, 255);
    }
  }
  return out;
}
