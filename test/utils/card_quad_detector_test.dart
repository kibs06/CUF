import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/card_quad_detector.dart';

/// Synthetic luminance frame: background [bg], a filled rotated rectangle
/// (center, size, angleDeg, luminance [fg]), plus uniform noise ±[noise].
/// Returns row-major bytes.
Uint8List fixture({
  int w = 320,
  int h = 240,
  int bg = 200,
  double cx = 160,
  double cy = 120,
  double rw = 100,
  double rh = 60,
  double angleDeg = 0,
  int fg = 40,
  int noise = 0,
  int seed = 7,
}) {
  final rnd = Random(seed);
  final px = Uint8List(w * h);
  final a = angleDeg * pi / 180;
  final ca = cos(a), sa = sin(a);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x - cx, dy = y - cy;
      // Inverse-rotate into rect frame.
      final lx = dx * ca + dy * sa;
      final ly = -dx * sa + dy * ca;
      final inside = lx.abs() <= rw / 2 && ly.abs() <= rh / 2;
      var v = inside ? fg : bg;
      if (noise > 0) v += rnd.nextInt(2 * noise + 1) - noise;
      px[y * w + x] = v.clamp(0, 255);
    }
  }
  return px;
}

/// True rect corners (for accuracy assertions).
List<Point<double>> trueCorners({
  double cx = 160,
  double cy = 120,
  double rw = 100,
  double rh = 60,
  double angleDeg = 0,
}) {
  final a = angleDeg * pi / 180;
  final ca = cos(a), sa = sin(a);
  Point<double> rot(double lx, double ly) =>
      Point(cx + lx * ca - ly * sa, cy + lx * sa + ly * ca);
  return [rot(-rw / 2, -rh / 2), rot(rw / 2, -rh / 2), rot(rw / 2, rh / 2), rot(-rw / 2, rh / 2)];
}

/// Mean corner error after best cyclic assignment (detected ↔ true).
double cornerError(List<QuadPoint> det, List<Point<double>> truth) {
  var best = double.infinity;
  for (var shift = 0; shift < 4; shift++) {
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final d = det[i], t = truth[(i + shift) % 4];
      s += sqrt((d.x - t.x) * (d.x - t.x) + (d.y - t.y) * (d.y - t.y));
    }
    best = min(best, s / 4);
  }
  return best;
}

void main() {
  group('detectReferenceQuad — synthetic fixtures', () {
    test('axis-aligned dark card found within 3px', () {
      final q = detectReferenceQuad(fixture(), 320, 240)!;
      expect(
        cornerError(q.corners, trueCorners()),
        lessThan(3.0),
      );
    });

    test('rotated 25° card found within 4px', () {
      final q = detectReferenceQuad(fixture(angleDeg: 25), 320, 240)!;
      expect(
        cornerError(q.corners, trueCorners(angleDeg: 25)),
        lessThan(4.0),
      );
    });

    test('light card on dark floor (inverted polarity)', () {
      final q = detectReferenceQuad(
        fixture(bg: 40, fg: 210, angleDeg: -15),
        320,
        240,
      )!;
      expect(
        cornerError(q.corners, trueCorners(angleDeg: -15)),
        lessThan(4.0),
      );
    });

    test('survives sensor noise ±12', () {
      final q = detectReferenceQuad(
        fixture(noise: 12, angleDeg: 10),
        320,
        240,
      )!;
      expect(
        cornerError(q.corners, trueCorners(angleDeg: 10)),
        lessThan(5.0),
      );
    });

    test('small card (32px wide) still detected', () {
      final q = detectReferenceQuad(
        fixture(rw: 32, rh: 20, angleDeg: 10),
        320,
        240,
      );
      expect(q, isNotNull);
    });

    test('blank frame → null, never a hallucinated quad', () {
      expect(detectReferenceQuad(fixture(rw: 0, rh: 0), 320, 240), isNull);
    });

    test('textured stripes without a card → null', () {
      // High-contrast vertical stripes: strong edges, no quad.
      final px = Uint8List(320 * 240);
      for (var y = 0; y < 240; y++) {
        for (var x = 0; x < 320; x++) {
          px[y * 320 + x] = (x ~/ 8).isEven ? 60 : 200;
        }
      }
      expect(detectReferenceQuad(px, 320, 240), isNull);
    });

    test('circle (non-quad) → null', () {
      final px = Uint8List(320 * 240);
      for (var y = 0; y < 240; y++) {
        for (var x = 0; x < 320; x++) {
          final d = sqrt((x - 160) * (x - 160) + (y - 120) * (y - 120));
          px[y * 320 + x] = d <= 60 ? 40 : 200;
        }
      }
      expect(detectReferenceQuad(px, 320, 240), isNull);
    });

    test('decoy: small quad + large quad → largest wins', () {
      // Two dark rects; the bigger must win (it dominates scale anyway).
      final px = fixture(rw: 30, rh: 18, cx: 60, cy: 60);
      final big = trueCorners(cx: 220, cy: 150, rw: 110, rh: 66);
      // Paint the big rect into the same frame.
      for (var y = 0; y < 240; y++) {
        for (var x = 0; x < 320; x++) {
          if (_inPoly(x.toDouble(), y.toDouble(), big)) {
            px[y * 320 + x] = 40;
          }
        }
      }
      final q = detectReferenceQuad(px, 320, 240)!;
      expect(
        cornerError(
          q.corners,
          big.map((p) => Point(p.x, p.y)).toList(),
        ),
        lessThan(4.0),
      );
    });

    test('degenerate input → null without throwing', () {
      expect(detectReferenceQuad(Uint8List(0), 0, 0), isNull);
      expect(detectReferenceQuad(Uint8List(10), 320, 240), isNull);
      expect(detectReferenceQuad(fixture(), 16, 16), isNull);
    });

    test('fast enough for the 500ms detection tick', () {
      final px = fixture(noise: 8, angleDeg: 12);
      final sw = Stopwatch()..start();
      detectReferenceQuad(px, 320, 240);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

bool _inPoly(double x, double y, List<Point<double>> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i].x, yi = poly[i].y;
    final xj = poly[j].x, yj = poly[j].y;
    if ((yi > y) != (yj > y) &&
        x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}
