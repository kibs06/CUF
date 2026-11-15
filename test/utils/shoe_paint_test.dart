import 'package:app/utils/shoe_paint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePaintHex', () {
    test('parses black and white to exact factors', () {
      expect(parsePaintHex('#000000'), [0.0, 0.0, 0.0]);
      expect(parsePaintHex('#FFFFFF'), [1.0, 1.0, 1.0]);
    });

    test('parses a mid hex within one step', () {
      final rgb = parsePaintHex('#5C3A21')!;
      expect(rgb[0], closeTo(0x5C / 255.0, 1e-9));
      expect(rgb[1], closeTo(0x3A / 255.0, 1e-9));
      expect(rgb[2], closeTo(0x21 / 255.0, 1e-9));
    });

    test('refuses everything that is not a web hex', () {
      expect(parsePaintHex(null), isNull);
      expect(parsePaintHex(''), isNull);
      expect(parsePaintHex('red'), isNull);
      expect(parsePaintHex('5C3A21'), isNull);
      expect(parsePaintHex('#FFF'), isNull);
      expect(parsePaintHex('#5C3A2122'), isNull);
      expect(parsePaintHex('#GGGGGG'), isNull);
    });
  });

  group('paintHexForColor', () {
    final rows = <Map<String, dynamic>>[
          {'color_name': 'Brown', 'paint_hex': '#5C3A21'},
          {'color_name': 'Black', 'paint_hex': '#1A1A1A'},
        ];

    test('returns the colour\u2019s paint', () {
      expect(paintHexForColor(rows, 'Brown'), '#5C3A21');
    });

    test('a colour with no row renders as-authored (null)', () {
      expect(paintHexForColor(rows, 'Tan'), isNull);
    });

    test('null and blank colours have no paint', () {
      expect(paintHexForColor(rows, null), isNull);
      expect(paintHexForColor(rows, '  '), isNull);
    });

    test('matching trims, but never rescues a different spelling', () {
      expect(paintHexForColor(rows, '  Brown '), '#5C3A21');
      expect(paintHexForColor(rows, 'brown'), isNull);
    });
  });
}
