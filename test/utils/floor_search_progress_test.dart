import 'package:app/widgets/foot_size_v2/floor_search_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('floorSearchProgress', () {
    test('nothing found and not steady is zero', () {
      expect(floorSearchProgress(probeHits: 0, steady: false), 0.0);
    });

    test('hits alone fill 60% at the three-probe lock threshold', () {
      expect(floorSearchProgress(probeHits: 3, steady: false), closeTo(0.6, 1e-9));
    });

    test('steadiness alone adds 40%', () {
      expect(floorSearchProgress(probeHits: 0, steady: true), closeTo(0.4, 1e-9));
    });

    test('full lock reads 100%', () {
      expect(floorSearchProgress(probeHits: 3, steady: true), 1.0);
      expect(floorSearchProgress(probeHits: 5, steady: true), 1.0);
    });

    test('hits beyond the threshold do not overfill the bar', () {
      expect(floorSearchProgress(probeHits: 5, steady: false),
          floorSearchProgress(probeHits: 3, steady: false));
    });

    test('out-of-range hit counts are clamped', () {
      expect(floorSearchProgress(probeHits: -2, steady: false), 0.0);
    });
  });
}
