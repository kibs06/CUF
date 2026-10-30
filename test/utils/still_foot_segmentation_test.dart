import 'package:app/utils/still_foot_segmentation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mask→polygon step of instant Capture-to-Fit, without an ML runtime:
/// synthetic confidence fields pin the geometry contract — a real blob
/// becomes a bounded polygon in mask pixels, and anything unusable is empty
/// so the capture screen re-coaches instead of measuring.
void main() {
  /// A filled rectangle of [value] on a zero field.
  List<double> rectMask({
    required int w,
    required int h,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    double value = 0.95,
  }) {
    final out = List<double>.filled(w * h, 0.0);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        out[y * w + x] = value;
      }
    }
    return out;
  }

  group('extractFootOutlineFromMask', () {
    test('a solid blob becomes a bounded left+right polygon', () {
      const w = 40, h = 40;
      final outline = extractFootOutlineFromMask(
        confidences: rectMask(w: w, h: h, x0: 10, y0: 5, x1: 25, y1: 30),
        maskW: w,
        maskH: h,
      );

      expect(outline.length, greaterThanOrEqualTo(10));
      expect(outline.length, lessThanOrEqualTo(96));
      for (final p in outline) {
        expect(p.dx, inInclusiveRange(10.0, 25.0));
        expect(p.dy, inInclusiveRange(5.0, 30.0));
      }
      // Left edge runs top-to-bottom first: the opening point is the
      // top-left corner of the blob.
      expect(outline.first.dx, 10.0);
      expect(outline.first.dy, 5.0);
    });

    test('empty and sub-threshold fields are empty', () {
      expect(
        extractFootOutlineFromMask(
          confidences: List<double>.filled(20 * 20, 0.0),
          maskW: 20,
          maskH: 20,
        ),
        isEmpty,
      );
      expect(
        extractFootOutlineFromMask(
          confidences: rectMask(
            w: 20,
            h: 20,
            x0: 4,
            y0: 4,
            x1: 14,
            y1: 14,
            value: 0.2,
          ),
          maskW: 20,
          maskH: 20,
        ),
        isEmpty,
        reason: 'below the 0.5 foreground floor there is no seed at all',
      );
    });

    test('a tiny blob is noise, a whole-frame blob is a wall', () {
      expect(
        extractFootOutlineFromMask(
          confidences: rectMask(w: 40, h: 40, x0: 5, y0: 5, x1: 6, y1: 6),
          maskW: 40,
          maskH: 40,
        ),
        isEmpty,
        reason: '4 of 1600 pixels is below the 1% noise floor',
      );
      expect(
        extractFootOutlineFromMask(
          confidences: List<double>.filled(40 * 40, 0.99),
          maskW: 40,
          maskH: 40,
        ),
        isEmpty,
        reason: 'a full-frame mask is background, never a foot',
      );
    });

    test('bad dims are empty, never a crash', () {
      expect(
        extractFootOutlineFromMask(confidences: const [0.9], maskW: 0, maskH: 1),
        isEmpty,
      );
      expect(
        extractFootOutlineFromMask(confidences: const [], maskW: 4, maskH: 4),
        isEmpty,
      );
    });

    test('a tall blob downsamples to at most 96 points', () {
      const w = 60, h = 200;
      final outline = extractFootOutlineFromMask(
        confidences: rectMask(w: w, h: h, x0: 10, y0: 0, x1: 40, y1: 199),
        maskW: w,
        maskH: h,
      );

      expect(outline.length, lessThanOrEqualTo(96));
      expect(outline.length, greaterThanOrEqualTo(10));
    });
  });
}
