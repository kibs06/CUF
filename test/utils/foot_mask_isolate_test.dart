import 'package:app/utils/foot_detector.dart';
import 'package:app/utils/foot_mask_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Small synthetic foot-like blob: elongated vertical bar in a 16x16 mask.
List<double> _footBlob({int size = 16}) {
  final out = List<double>.filled(size * size, 0.05);
  for (var y = 2; y < 14; y++) {
    for (var x = 6; x < 10; x++) {
      out[y * size + x] = 0.95;
    }
  }
  return out;
}

void main() {
  group('evaluateFootMaskOffMain', () {
    test('matches sync result on foot-like blob', () async {
      final confidences = _footBlob();
      final sync = evaluateFootMask(
        confidences: confidences,
        width: 16,
        height: 16,
        frameWidth: 160,
        frameHeight: 160,
      );
      final async = await evaluateFootMaskOffMain(
        confidences: confidences,
        width: 16,
        height: 16,
        frameWidth: 160,
        frameHeight: 160,
      );
      expect(async.footDetected, sync.footDetected);
      expect(async.qualityScore, closeTo(sync.qualityScore, 1e-9));
      if (sync.heelPoint != null) {
        expect(async.heelPoint!.x, closeTo(sync.heelPoint!.x, 1e-9));
        expect(async.heelPoint!.y, closeTo(sync.heelPoint!.y, 1e-9));
      }
    });

    test('negative stays negative off-main', () async {
      final empty = List<double>.filled(16 * 16, 0.01);
      final result = await evaluateFootMaskOffMain(
        confidences: empty,
        width: 16,
        height: 16,
        frameWidth: 160,
        frameHeight: 160,
      );
      expect(result.footDetected, isFalse);
    });
  });
}
