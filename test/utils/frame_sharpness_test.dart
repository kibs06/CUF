import 'dart:typed_data';

import 'package:app/utils/frame_sharpness.dart';
import 'package:flutter_test/flutter_test.dart';

/// A luma plane of [width]×[height] built from [pixel]; the chroma tail is
/// zero-filled so the buffer is a full NV21 frame.
Uint8List lumaFrame(int width, int height, int Function(int x, int y) pixel) {
  final bytes = Uint8List(width * height * 3 ~/ 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[y * width + x] = pixel(x, y);
    }
  }
  return bytes;
}

void main() {
  const width = 64;
  const height = 48;

  test('a flat frame has zero sharpness', () {
    final flat = lumaFrame(width, height, (x, y) => 128);
    expect(frameSharpness(flat, width, height), 0);
  });

  test('a high-contrast edge pattern scores far above the minimum', () {
    // Period-4 stripes: sharp edges that the every-2nd-pixel sampler can see
    // (a period-2 pattern aliases to a flat plane).
    final sharp = lumaFrame(width, height, (x, y) => x % 4 < 2 ? 0 : 255);
    final score = frameSharpness(sharp, width, height);
    expect(score, greaterThan(kMinFrameSharpness * 10));
  });

  test('a smooth gradient (blur-like) scores below the sharp pattern', () {
    final sharp = lumaFrame(width, height, (x, y) => x % 4 < 2 ? 0 : 255);
    // A slow ramp has almost no second-derivative energy: what blur leaves.
    final smooth = lumaFrame(width, height, (x, y) => (x * 2) % 256);
    expect(
      frameSharpness(smooth, width, height),
      lessThan(frameSharpness(sharp, width, height)),
    );
  });

  test('a truncated luma plane fails closed with zero', () {
    final short = Uint8List(10);
    expect(frameSharpness(short, width, height), 0);
  });

  test('a frame too small to have interior pixels scores zero', () {
    final tiny = Uint8List(4);
    expect(frameSharpness(tiny, 2, 2), 0);
  });
}
