/// Foot outline for a single captured still (card Capture-to-Fit path).
///
/// The live try-on loop segments NV21 preview frames; an instant card
/// capture instead segments the full-resolution burst stills it just wrote
/// to disk. ML Kit's selfie segmenter accepts a file path directly
/// ([segmentFootOutlineInStill]), and the mask-to-polygon step
/// ([extractFootOutlineFromMask]) is pure Dart so the geometry is
/// table-testable without an ML runtime.
///
/// The outline comes back in the still's full-resolution pixels — the same
/// space `decodeAndDetectStill` reports reference corners in — so
/// `measureCardCapture` can rectify it with no further mapping.
///
/// Every failure (no mask, tiny blob, whole-frame blob, degenerate polygon)
/// is an empty list: the capture screen re-coaches (`outlineInvalid`), never
/// measures off a guess.
library;

import 'dart:io' show File;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// Foreground probability at or above this is foot.
const double kStillMaskThreshold = 0.5;

/// Minimum kept blob, as a fraction of the mask field. Below this the blob
/// is noise (matches the live detector's ~1% noise floor).
const double kStillMinForegroundFraction = 0.01;

/// Maximum kept blob, as a fraction of the mask field. Above this the mask
/// is a wall/floor/carpet, not a foot (matches the live detector's 60%
/// whole-frame rejection).
const double kStillMaxForegroundFraction = 0.60;

/// Outline points are stride-downsampled to at most this many — plenty for
/// the PCA extent math, and bounded for the homography loop.
const int kStillOutlineMaxPoints = 96;

/// Row-boundary polygon of the largest foreground blob.
///
/// Thresholds [confidences] (row-major, [maskW]×[maskH]), keeps the largest
/// 4-connected component, and returns its left-edge-top-to-bottom +
/// right-edge-bottom-to-top polygon in mask pixels. Empty when there is no
/// usable blob: bad dims, no seed pixel, or a blob outside the
/// min/max foreground fractions, or fewer than 10 polygon points (the
/// `measureFootRectified` floor).
List<Offset> extractFootOutlineFromMask({
  required List<double> confidences,
  required int maskW,
  required int maskH,
  double threshold = kStillMaskThreshold,
}) {
  if (maskW <= 0 || maskH <= 0) return const [];
  if (confidences.length < maskW * maskH) return const [];

  // Seed at the most confident foreground pixel — the foot is the dominant
  // subject in the guided framing, so the strongest response belongs to it.
  var seed = -1;
  var seedConf = threshold;
  for (var i = 0; i < maskW * maskH; i++) {
    final v = confidences[i];
    if (v >= seedConf) {
      seedConf = v;
      seed = i;
    }
  }
  if (seed < 0) return const [];

  // Largest 4-connected foreground component from the seed. The seed holds
  // the peak, and the foot is one connected mass around it; a flood from
  // the peak cannot leak into a disconnected noise blob.
  final seen = Uint8List(maskW * maskH);
  final stack = <int>[seed];
  seen[seed] = 1;
  final minX = List<int>.filled(maskH, maskW);
  final maxX = List<int>.filled(maskH, -1);
  var count = 0;
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    count++;
    final x = cur % maskW;
    final y = cur ~/ maskW;
    if (x < minX[y]) minX[y] = x;
    if (x > maxX[y]) maxX[y] = x;
    if (x > 0) {
      final n = cur - 1;
      if (seen[n] == 0 && confidences[n] >= threshold) {
        seen[n] = 1;
        stack.add(n);
      }
    }
    if (x < maskW - 1) {
      final n = cur + 1;
      if (seen[n] == 0 && confidences[n] >= threshold) {
        seen[n] = 1;
        stack.add(n);
      }
    }
    if (y > 0) {
      final n = cur - maskW;
      if (seen[n] == 0 && confidences[n] >= threshold) {
        seen[n] = 1;
        stack.add(n);
      }
    }
    if (y < maskH - 1) {
      final n = cur + maskW;
      if (seen[n] == 0 && confidences[n] >= threshold) {
        seen[n] = 1;
        stack.add(n);
      }
    }
  }

  final field = maskW * maskH;
  if (count < field * kStillMinForegroundFraction) return const [];
  if (count > field * kStillMaxForegroundFraction) return const [];

  final poly = <Offset>[];
  for (var y = 0; y < maskH; y++) {
    if (maxX[y] < 0) continue;
    poly.add(Offset(minX[y].toDouble(), y.toDouble()));
  }
  for (var y = maskH - 1; y >= 0; y--) {
    if (maxX[y] < 0) continue;
    if (maxX[y] == minX[y]) continue;
    poly.add(Offset(maxX[y].toDouble(), y.toDouble()));
  }
  if (poly.length < 10) return const [];
  if (poly.length <= kStillOutlineMaxPoints) return poly;
  final stride = poly.length / kStillOutlineMaxPoints;
  final out = <Offset>[];
  for (var i = 0; i < kStillOutlineMaxPoints; i++) {
    out.add(poly[(i * stride).floor()]);
  }
  return out;
}

/// Segments the foot in the still at [imagePath], in full-image pixels.
///
/// Runs the same selfie-segmentation model the live loop uses, over the
/// decoded file rather than an NV21 preview frame. Never throws — any
/// failure (missing file, no mask, unusable blob) is an empty outline, and
/// the caller re-coaches.
Future<List<Offset>> segmentFootOutlineInStill(String imagePath) async {
  try {
    final segmenter = SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: true,
    );
    try {
      final mask = await segmenter.processImage(
        InputImage.fromFilePath(imagePath),
      );
      if (mask == null || mask.confidences.isEmpty) return const [];
      final outline = extractFootOutlineFromMask(
        confidences: mask.confidences,
        maskW: mask.width,
        maskH: mask.height,
      );
      if (outline.isEmpty) return const [];
      final bytes = await compute(_readStillBytes, imagePath);
      if (bytes == null) return const [];
      final decoded = img.decodeJpg(bytes) ?? img.decodePng(bytes);
      if (decoded == null) return const [];
      final sx = decoded.width / mask.width;
      final sy = decoded.height / mask.height;
      if (!sx.isFinite || !sy.isFinite || sx <= 0 || sy <= 0) {
        return const [];
      }
      return [
        for (final p in outline) Offset(p.dx * sx, p.dy * sy),
      ];
    } finally {
      segmenter.close();
    }
  } catch (_) {
    return const [];
  }
}

/// File read off the caller's thread; `compute` needs a top-level function.
Future<Uint8List?> _readStillBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
