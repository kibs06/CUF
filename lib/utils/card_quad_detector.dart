/// Classical-CV quadrilateral detector for the card reference.
///
/// Pure Dart, no plugins: Otsu threshold (both polarities) → largest
/// connected component → convex hull → Ramer–Douglas–Peucker polygon
/// approximation → 4-vertex angle/area scoring. The winner must still pass
/// [diagnoseReferenceQuad] downstream — this file finds quad-shaped
/// luminance regions; the validator decides whether one is trustworthy.
///
/// Input is a raw luminance plane (camera Y plane: one byte per pixel),
/// so the screen never decodes JPEGs for detection. Runs on a downscaled
/// frame (≈320px long side); coordinates are returned in the *input*
/// plane's pixels and the caller scales to full resolution.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 2D point in image pixels (x right, y down).
class QuadPoint {
  final double x;
  final double y;
  const QuadPoint(this.x, this.y);
}

/// A detected quadrilateral: exactly 4 corners in arbitrary order, plus
/// the component area in input-plane pixels (for size sanity downstream).
class DetectedQuad {
  final List<QuadPoint> corners;
  final double areaPx;
  const DetectedQuad(this.corners, this.areaPx);
}

/// Minimum component area as a share of the frame (below this is noise).
const double kMinComponentShare = 0.005;

/// RDP epsilon as a share of hull perimeter, tried in order.
const List<double> kRdpEpsilons = [0.02, 0.035, 0.012, 0.05];

/// Interior-angle tolerance around 90° for a plausible quad vertex.
const double kAngleToleranceDeg = 35;

/// Quad area must fill this share of its convex hull (rejects L-shapes
/// that RDP happened to squeeze to 4 points).
const double kMinHullFill = 0.82;

/// Detect the most quad-like luminance region in [luminance] (row-major,
/// [width]×[height]).
///
/// Returns null when nothing quad-like is found — the caller keeps
/// coaching (`searching`), never measures.
DetectedQuad? detectReferenceQuad(
  Uint8List luminance,
  int width,
  int height,
) {
  if (luminance.length < width * height || width < 32 || height < 32) {
    return null;
  }
  final pixels = luminance.sublist(0, width * height);
  final threshold = _otsuThreshold(pixels);
  DetectedQuad? best;
  // Both polarities: dark card on light floor, or light card on dark floor.
  for (final invert in [false, true]) {
    final mask = _thresholdMask(pixels, threshold, invert);
    // Enclosed components only: anything touching the frame edge is
    // background (or a card so close it fills the frame — either way the
    // validator/coaching must refuse it, never measure it).
    final comp = _largestEnclosedComponent(mask, width, height);
    if (comp == null) continue;
    if (comp.length < width * height * kMinComponentShare) continue;
    final hull = _convexHull(comp, width);
    if (hull.length < 4) continue;
    final quad = _approxQuad(hull);
    if (quad == null) continue;
    final area = _polygonArea(quad);
    final hullArea = _polygonArea(hull);
    if (!(area > 0) || hullArea <= 0 || area / hullArea < kMinHullFill) {
      continue;
    }
    if (best == null || area > best.areaPx) {
      best = DetectedQuad(quad, area);
    }
  }
  return best;
}

/// Otsu's threshold: the luminance split maximizing between-class variance.
int _otsuThreshold(Uint8List pixels) {
  final hist = Int32List(256);
  for (final p in pixels) {
    hist[p]++;
  }
  final total = pixels.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var bestVar = -1.0;
  var bestT = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > bestVar) {
      bestVar = between;
      bestT = t;
    }
  }
  return bestT;
}

/// Binary mask: foreground = dark side of the threshold (or light when
/// [invert]). Returned as a bitset (1 = foreground).
Uint8List _thresholdMask(Uint8List pixels, int threshold, bool invert) {
  final mask = Uint8List((pixels.length + 7) ~/ 8);
  for (var i = 0; i < pixels.length; i++) {
    final fg = invert ? pixels[i] > threshold : pixels[i] <= threshold;
    if (fg) mask[i >> 3] |= 1 << (i & 7);
  }
  return mask;
}

bool _maskGet(Uint8List mask, int i) => (mask[i >> 3] >> (i & 7)) & 1 == 1;

/// Largest 4-connected foreground component that does NOT touch the frame
/// edge, as pixel indices. Border-touching regions are background by
/// construction (capture coaching frames the whole card with margin).
/// Iterative flood fill with an explicit stack (no recursion depth risk).
List<int>? _largestEnclosedComponent(
    Uint8List mask, int width, int height) {
  final n = width * height;
  final visited = Uint8List((n + 7) ~/ 8);
  List<int>? best;
  final stack = Int32List(n);
  for (var seed = 0; seed < n; seed++) {
    if (!_maskGet(mask, seed) || _maskGet(visited, seed)) continue;
    // Flood from seed.
    var top = 0;
    stack[top++] = seed;
    visited[seed >> 3] |= 1 << (seed & 7);
    final comp = <int>[];
    var touchesBorder = false;
    while (top > 0) {
      final i = stack[--top];
      comp.add(i);
      final x = i % width;
      final y = i ~/ width;
      if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
        touchesBorder = true;
      }
      if (x > 0) {
        final j = i - 1;
        if (_maskGet(mask, j) && !_maskGet(visited, j)) {
          visited[j >> 3] |= 1 << (j & 7);
          stack[top++] = j;
        }
      }
      if (x < width - 1) {
        final j = i + 1;
        if (_maskGet(mask, j) && !_maskGet(visited, j)) {
          visited[j >> 3] |= 1 << (j & 7);
          stack[top++] = j;
        }
      }
      if (y > 0) {
        final j = i - width;
        if (_maskGet(mask, j) && !_maskGet(visited, j)) {
          visited[j >> 3] |= 1 << (j & 7);
          stack[top++] = j;
        }
      }
      if (y < height - 1) {
        final j = i + width;
        if (_maskGet(mask, j) && !_maskGet(visited, j)) {
          visited[j >> 3] |= 1 << (j & 7);
          stack[top++] = j;
        }
      }
    }
    if (!touchesBorder && (best == null || comp.length > best.length)) {
      best = comp;
    }
  }
  return best;
}

/// Andrew's monotone chain convex hull over component pixel centers.
/// Returns hull vertices counter-clockwise (pixel-center coordinates).
List<QuadPoint> _convexHull(List<int> comp, int width) {
  final pts = comp
      .map((i) => QuadPoint((i % width).toDouble(), (i ~/ width).toDouble()))
      .toList()
    ..sort((a, b) =>
        a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  // De-duplicate (can't happen for distinct pixels, but cheap insurance).
  final uniq = <QuadPoint>[];
  for (final p in pts) {
    if (uniq.isEmpty ||
        uniq.last.x != p.x ||
        uniq.last.y != p.y) {
      uniq.add(p);
    }
  }
  if (uniq.length < 3) return uniq;
  double cross(QuadPoint o, QuadPoint a, QuadPoint b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <QuadPoint>[];
  for (final p in uniq) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <QuadPoint>[];
  for (var i = uniq.length - 1; i >= 0; i--) {
    final p = uniq[i];
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return lower + upper;
}

double _perimeter(List<QuadPoint> poly) {
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    sum += math.sqrt(
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  }
  return sum;
}

double _polygonArea(List<QuadPoint> poly) {
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}

double _pointSegDist(QuadPoint p, QuadPoint a, QuadPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lenSq = dx * dx + dy * dy;
  if (lenSq <= 0) {
    return math.sqrt(
        (p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y));
  }
  var u = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
  u = u.clamp(0.0, 1.0);
  final cx = a.x + u * dx - p.x;
  final cy = a.y + u * dy - p.y;
  return math.sqrt(cx * cx + cy * cy);
}

/// Ramer–Douglas–Peucker simplification of a closed polygon.
List<QuadPoint> _rdp(List<QuadPoint> pts, double eps) {
  if (pts.length <= 2) return List.of(pts);
  var maxDist = 0.0;
  var maxIdx = 0;
  for (var i = 1; i < pts.length; i++) {
    final d = _pointSegDist(pts[i], pts.first, pts.last);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }
  if (maxDist <= eps) return [pts.first, pts.last];
  final left = _rdp(pts.sublist(0, maxIdx + 1), eps);
  final right = _rdp(pts.sublist(maxIdx), eps);
  return left.sublist(0, left.length - 1) + right;
}

/// Interior angle at [b] in degrees (0–180).
double _angleDeg(QuadPoint a, QuadPoint b, QuadPoint c) {
  final v1x = a.x - b.x, v1y = a.y - b.y;
  final v2x = c.x - b.x, v2y = c.y - b.y;
  final dot = v1x * v2x + v1y * v2y;
  final n1 = math.sqrt(v1x * v1x + v1y * v1y);
  final n2 = math.sqrt(v2x * v2x + v2y * v2y);
  if (n1 <= 0 || n2 <= 0) return 0;
  final cosA = (dot / (n1 * n2)).clamp(-1.0, 1.0);
  return math.acos(cosA) * 180 / math.pi;
}

/// Approximate [hull] to 4 vertices. Tries RDP epsilons in order and
/// returns the first 4-point result whose interior angles are all within
/// [kAngleToleranceDeg] of 90° (convexity is inherited from the hull).
List<QuadPoint>? _approxQuad(List<QuadPoint> hull) {
  final perim = _perimeter(hull);
  if (!(perim > 0)) return null;
  for (final epsShare in kRdpEpsilons) {
    final approx = _rdp([...hull, hull.first], perim * epsShare);
    // Closed polygon: first == last; drop the duplicate.
    final ring = approx.length > 1 ? approx.sublist(0, approx.length - 1) : approx;
    if (ring.length != 4) continue;
    var ok = true;
    for (var i = 0; i < 4; i++) {
      final ang = _angleDeg(ring[(i + 3) % 4], ring[i], ring[(i + 1) % 4]);
      if ((ang - 90).abs() > kAngleToleranceDeg) {
        ok = false;
        break;
      }
    }
    if (ok) return ring;
  }
  return null;
}
