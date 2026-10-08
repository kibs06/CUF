import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/ar_core_channel.dart';

void main() {
  group('ArWorldPoint.fromMap source', () {
    test('reads a depth-sourced point', () {
      final point = ArWorldPoint.fromMap({
        'x': 0.1,
        'y': 0.2,
        'z': -0.5,
        'distance': 0.55,
        'source': 'depth',
      });

      expect(point.source, 'depth');
      expect(point.x, 0.1);
      expect(point.distanceFromCamera, 0.55);
    });

    test('defaults to plane when the platform sends no source', () {
      final point = ArWorldPoint.fromMap({
        'x': 0.0,
        'y': 0.0,
        'z': 0.0,
        'distance': 1.0,
      });

      expect(point.source, 'plane');
    });
  });
}
