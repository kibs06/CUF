/// The foot-scan guide box that follows the detected foot (pure Dart, no Flutter
/// widgets; `dart:ui` is only used for the value types).
///
/// The fixed guide made the customer slide the foot into a box. Following the
/// foot keeps the box around it wherever it sits in the frame. Coordinates are
/// normalised (0–1) in the upright camera frame, the same space as the guide.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Padding added on each side of the foot's extent, as a fraction of the frame.
const double kFollowPadding = 0.08;

/// Smallest box side, so a short or partly seen foot still gets a usable box.
const double kFollowMinSide = 0.25;

/// How far the drawn box moves toward each new detection (0 = frozen, 1 = jump).
/// Half a step per detection keeps the box tracking without jitter.
const double kFollowSmoothing = 0.5;

/// A box around [points] (normalised, upright frame), padded and clamped to the
/// frame. Empty input is a caller error.
Rect footFollowRect(List<Offset> points) {
  assert(points.isNotEmpty, 'footFollowRect needs at least one point');

  var minX = points.first.dx;
  var maxX = points.first.dx;
  var minY = points.first.dy;
  var maxY = points.first.dy;
  for (final p in points) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }

  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2;
  final w = math.max(maxX - minX + 2 * kFollowPadding, kFollowMinSide);
  final h = math.max(maxY - minY + 2 * kFollowPadding, kFollowMinSide);

  return Rect.fromLTRB(
    math.max(0, cx - w / 2),
    math.max(0, cy - h / 2),
    math.min(1, cx + w / 2),
    math.min(1, cy + h / 2),
  );
}
