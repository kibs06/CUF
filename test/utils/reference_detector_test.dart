import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:app/utils/foot_measurement_utils.dart';
import 'package:app/utils/reference_detector.dart';

/// 640×480 luminance frame with a dark axis-aligned card (200×120px).
Uint8List cardFrame() {
  const w = 640, h = 480;
  final px = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inside =
          (x - 320).abs() <= 100 && (y - 240).abs() <= 60;
      px[y * w + x] = inside ? 40 : 200;
    }
  }
  return px;
}

void main() {
  group('CvReferenceDetector', () {
    test('finds the card and reports full-frame coordinates', () {
      const detector = CvReferenceDetector();
      final corners = detector.detect(
        luminance: cardFrame(),
        frameW: 640,
        frameH: 480,
      );
      expect(corners, hasLength(4));
      // True card spans x 220–420, y 180–300.
      for (final c in corners) {
        expect(c.dx, inInclusiveRange(215.0, 425.0));
        expect(c.dy, inInclusiveRange(175.0, 305.0));
      }
    });

    test('blank frame → empty, never throws', () {
      const detector = CvReferenceDetector();
      expect(
        detector.detect(
          luminance: Uint8List(640 * 480)..fillRange(0, 640 * 480, 200),
          frameW: 640,
          frameH: 480,
        ),
        isEmpty,
      );
    });

    test('short/degenerate input → empty', () {
      const detector = CvReferenceDetector();
      expect(
        detector.detect(luminance: Uint8List(10), frameW: 640, frameH: 480),
        isEmpty,
      );
      expect(
        detector.detect(
          luminance: Uint8List(16 * 16),
          frameW: 16,
          frameH: 16,
        ),
        isEmpty,
      );
    });
  });

  group('decodeAndDetectStill', () {
    test('JPEG round-trip: encode → decode → detect', () {
      // Build an RGB still with a dark card, JPEG-encode it (as the
      // camera plugin would produce), then run the isolate entry point.
      const w = 640, h = 480;
      final still = img.Image(width: w, height: h);
      img.fill(still, color: img.ColorRgb8(200, 200, 200));
      img.fillRect(still,
          x1: 220, y1: 180, x2: 420, y2: 300,
          color: img.ColorRgb8(40, 40, 40));
      final jpeg = Uint8List.fromList(img.encodeJpg(still, quality: 90));
      final out = decodeAndDetectStill({'bytes': jpeg, 'maxSide': 320});
      expect(out.frameW, w);
      expect(out.frameH, h);
      expect(out.corners, hasLength(4));
    });

    test('garbage bytes → empty, never throws', () {
      final out = decodeAndDetectStill(
          {'bytes': Uint8List.fromList([0, 1, 2, 3]), 'maxSide': 320});
      expect(out.corners, isEmpty);
    });
  });

  group('SimulatedReferenceDetector', () {
    test('frames then produces a reference-proportioned quad', () {
      final sim = SimulatedReferenceDetector(
          reference: PaperDimensions.card);
      for (var i = 0; i < 5; i++) {
        expect(
          sim.detect(
              luminance: Uint8List(0), frameW: 640, frameH: 480),
          isEmpty,
        );
      }
      final corners = sim.detect(
          luminance: Uint8List(0), frameW: 640, frameH: 480);
      expect(corners, hasLength(4));
      sim.reset();
      expect(
        sim.detect(luminance: Uint8List(0), frameW: 640, frameH: 480),
        isEmpty,
      );
    });
  });

  group('inInclusiveRange helper', () {
    test('sanity', () {
      expect(5.0, inInclusiveRange(1.0, 5.0));
    });
  });

  test('detector is fast on full-res-ish stills', () {
    const detector = CvReferenceDetector();
    final sw = Stopwatch()..start();
    detector.detect(luminance: cardFrame(), frameW: 640, frameH: 480);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(500));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// Inclusive-range matcher (test-local; avoids pulling matchers-extras).
Matcher inInclusiveRange(double low, double high) =>
    _InInclusiveRange(low, high);

class _InInclusiveRange extends Matcher {
  final double low, high;
  _InInclusiveRange(this.low, this.high);
  @override
  bool matches(Object? item, Map matchState) =>
      item is num && item >= low && item <= high;
  @override
  Description describe(Description d) =>
      d.add('in inclusive range $low–$high');
  @override
  Description describeMismatch(
          Object? item, Description d, Map matchState, bool verbose) =>
      d.add('$item outside $low–$high');
}
