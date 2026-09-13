import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/compact_number.dart';

void main() {
  group('compactNumber', () {
    test('values under 1000 render as-is', () {
      expect(compactNumber(0), '0');
      expect(compactNumber(1), '1');
      expect(compactNumber(42), '42');
      expect(compactNumber(999), '999');
    });

    test('thousands use k suffix', () {
      expect(compactNumber(1000), '1k');
      expect(compactNumber(1200), '1.2k');
      expect(compactNumber(15000), '15k');
      expect(compactNumber(999999), '1000k');
    });

    test('millions use m suffix', () {
      expect(compactNumber(1000000), '1m');
      expect(compactNumber(2500000), '2.5m');
    });

    test('strips trailing .0', () {
      expect(compactNumber(2000), '2k');
      expect(compactNumber(3000000), '3m');
    });
  });
}
