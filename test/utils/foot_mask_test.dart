import 'dart:typed_data';

import 'package:app/utils/foot_mask.dart';
import 'package:flutter_test/flutter_test.dart';

/// `downsampleFootMask` — V4.4's wire-format decision.
///
/// Three things are pinned here, in the order they can break on a device:
///
///   1. **Orientation.** The mask is row-major and top-down, in the same
///      normalized space as the detection's heel/toe points. The Android side
///      maps a mask quad through the same upright-image→viewport mapping it
///      raycasts those points through, so a flipped row or column here is a
///      shoe occluded at the wrong place on screen — a bug a desk can catch
///      today and a device would only show as "occlusion looks off".
///   2. **Totality.** Degenerate input (empty, bad dimensions, truncated) and
///      non-finite samples produce a zero-filled mask rather than an exception.
///      Occlusion is auxiliary: dropping one is legal, throwing is not.
///   3. **Resolution coverage.** A 256×256 detector mask maps onto the 32×32
///      wire mask exactly (8×8 boxes), including the last row/column when the
///      dimensions do not divide evenly.
void main() {
  group('orientation', () {
    test('row-major, top-down: the top of the input lights the top of the output',
        () {
      const size = 4;
      // Only the top row is foreground: a 4×4 mask with row 0 set.
      final confidences = <double>[
        1, 1, 1, 1, //
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
      ];

      final out = downsampleFootMask(confidences, size, size, size: size);

      expect(out.sublist(0, size), everyElement(255),
          reason: 'input row 0 is output row 0');
      expect(out.sublist(size), everyElement(0),
          reason: 'nothing from below may leak upward');
    });

    test('x→u: a single input column lights the same output column', () {
      const size = 4;
      // Only column 1 is foreground.
      final confidences = <double>[
        0, 1, 0, 0, //
        0, 1, 0, 0,
        0, 1, 0, 0,
        0, 1, 0, 0,
      ];

      final out = downsampleFootMask(confidences, size, size, size: size);

      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final expected = x == 1 ? 255 : 0;
          expect(out[y * size + x], expected,
              reason: 'cell ($x,$y) should follow its own input pixel');
        }
      }
    });
  });

  group('averaging', () {
    test('a 4×4 mask becomes 2×2 box means', () {
      // Top-half foreground, bottom-half background → the top row of the
      // result is saturated and the bottom row is empty.
      final confidences = <double>[
        1, 1, 1, 1, //
        1, 1, 1, 1,
        0, 0, 0, 0,
        0, 0, 0, 0,
      ];

      final out = downsampleFootMask(confidences, 4, 4, size: 2);

      expect(out, <int>[255, 255, 0, 0]);
    });

    test('fractional means round to the nearest byte', () {
      // A 2×2 block of 0.25, 0.25, 0.25, 0.25 → 0.25 × 255 = 63.75 → 64.
      final confidences = List<double>.filled(4, 0.25);
      final out = downsampleFootMask(confidences, 2, 2, size: 1);
      expect(out.single, 64);
    });

    test('a 1×1 mask fills every output cell with the same value', () {
      final out = downsampleFootMask(<double>[0.75], 1, 1);
      expect(out, hasLength(kFootMaskSize * kFootMaskSize));
      expect(out, everyElement(191), reason: '0.75 × 255 = 191.25 → 191');
    });

    test('a 256×256 detector mask maps an 8×8 block onto one wire cell', () {
      // The detector's real mask size, with the real wire size: 256 / 32 = 8.
      final confidences = List<double>.filled(256 * 256, 0);
      // Light exactly one 8×8 block: rows 80–87, columns 16–23.
      for (var y = 80; y < 88; y++) {
        for (var x = 16; x < 24; x++) {
          confidences[y * 256 + x] = 1.0;
        }
      }

      final out = downsampleFootMask(confidences, 256, 256);

      expect(out, hasLength(kFootMaskSize * kFootMaskSize));
      // 80/8 = row 10; 16/8 = column 2.
      expect(out[10 * kFootMaskSize + 2], 255);
      final lit = out.where((v) => v != 0).length;
      expect(lit, 1, reason: 'one 8×8 block is exactly one cell — no bleed');
    });

    test('the last output cell reaches the image edge when size does not divide',
        () {
      // 3 rows into 2 output rows: the second cell must take rows 1 AND 2 —
      // so its mean is 1.0 only if both are read. (2 wide, so columns map
      // one-to-one and the expectation stays about the rows.)
      final confidences = <double>[
        0, 0, // row 0
        1, 1, // row 1
        1, 1, // row 2
      ];
      final out = downsampleFootMask(confidences, 2, 3, size: 2);
      expect(out, <int>[0, 0, 255, 255],
          reason: 'the bottom row is in the second cell, not dropped');
    });
  });

  group('totality', () {
    test('empty, non-positive and truncated input yields a zero mask', () {
      final zeros = Uint8List(kFootMaskSize * kFootMaskSize);

      expect(downsampleFootMask(const <double>[], 0, 0), zeros);
      expect(downsampleFootMask(const <double>[], 32, 32), zeros);
      expect(downsampleFootMask(<double>[1, 1, 1], 8, 8), zeros,
          reason: 'a truncated buffer must not be read past its end');
    });

    test('non-finite samples are skipped, not propagated', () {
      final confidences = <double>[
        1.0, double.nan, //
        double.infinity, 1.0,
      ];

      final out = downsampleFootMask(confidences, 2, 2, size: 1);

      // Two finite samples at 1.0: mean 1.0. A single NaN that had been summed
      // would have made the mean NaN and the cell 0 — or thrown.
      expect(out.single, 255);
    });

    test('a cell of nothing but non-finite samples is zero, not a crash', () {
      final confidences = <double>[double.nan, double.nan, double.nan, double.nan];
      final out = downsampleFootMask(confidences, 2, 2, size: 1);
      expect(out.single, 0);
    });

    test('out-of-range values are clamped, not wrapped', () {
      // One sample per output cell, so the expectation is per-pixel.
      final confidences = <double>[-0.5, 1.5, 0.0, 1.0];
      final out = downsampleFootMask(confidences, 2, 2, size: 2);
      expect(out, <int>[0, 255, 0, 255]);
    });
  });
}
