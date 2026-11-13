import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/in_store_barcode.dart';

void main() {
  group('check digit', () {
    test('matches the known EAN-13 example 4006381333931', () {
      expect(inStoreBarcodeCheckDigit('400638133393'), 1);
      expect(inStoreBarcodeFromBase('400638133393'), '4006381333931');
    });

    test('rejects non-12-digit bases', () {
      expect(() => inStoreBarcodeCheckDigit('123'), throwsArgumentError);
      expect(
        () => inStoreBarcodeCheckDigit('1234567890123'),
        throwsArgumentError,
      );
      expect(
        () => inStoreBarcodeCheckDigit('12345678901x'),
        throwsArgumentError,
      );
    });
  });

  group('validation', () {
    test('accepts a checksum-valid 13-digit code', () {
      expect(isValidEan13('4006381333931'), isTrue);
    });

    test('rejects wrong check digits, short codes and non-digits', () {
      expect(isValidEan13('4006381333932'), isFalse);
      expect(isValidEan13('400638133393'), isFalse);
      expect(isValidEan13('40063813339311'), isFalse);
      expect(isValidEan13('400638133393x'), isFalse);
      expect(isValidEan13(null), isFalse);
      expect(isValidEan13(''), isFalse);
    });

    test('in-store range is the 2xx restricted-circulation prefix', () {
      expect(isInStoreBarcode('4006381333931'), isFalse);
      expect(isInStoreBarcode(generateInStoreBarcode(storeSeed: 'store-1')),
          isTrue);
    });
  });

  group('generation', () {
    test('produces a valid 200-prefixed EAN-13', () {
      final code =
          generateInStoreBarcode(storeSeed: 'store-1', random: Random(7));
      expect(code.length, ean13Length);
      expect(code.startsWith(inStoreBarcodePrefix), isTrue);
      expect(isValidEan13(code), isTrue);
      expect(isInStoreBarcode(code), isTrue);
    });

    test('is deterministic for the same seed and random sequence', () {
      final a =
          generateInStoreBarcode(storeSeed: 'store-1', random: Random(7));
      final b =
          generateInStoreBarcode(storeSeed: 'store-1', random: Random(7));
      expect(a, b);
    });

    test('separates stores into different segments', () {
      final a =
          generateInStoreBarcode(storeSeed: 'store-1', random: Random(7));
      final b =
          generateInStoreBarcode(storeSeed: 'store-2', random: Random(7));
      expect(a.substring(3, 7), isNot(b.substring(3, 7)));
    });

    test('successive draws vary', () {
      final rng = Random(99);
      final codes = {
        for (var i = 0; i < 10; i++)
          generateInStoreBarcode(storeSeed: 'store-1', random: rng),
      };
      expect(codes.length, greaterThan(1));
      for (final code in codes) {
        expect(isInStoreBarcode(code), isTrue);
      }
    });
  });
}
