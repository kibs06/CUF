import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/cart_helpers.dart';

void main() {
  group('resolveVariant', () {
    test('returns matching variant for exact size and color', () {
      final variants = [
        {'id': 'v1', 'size': '40', 'color': 'Black', 'additional_price': 0},
        {'id': 'v2', 'size': '40', 'color': 'Brown', 'additional_price': 10},
        {'id': 'v3', 'size': '42', 'color': 'Black', 'additional_price': 0},
      ];

      final result = resolveVariant(variants: variants, size: '40', color: 'Brown');

      expect(result.variantId, 'v2');
      expect(result.additionalPrice, 10.0);
    });

    test('returns first matching variant when color is null', () {
      final variants = [
        {'id': 'v1', 'size': '40', 'color': 'Black', 'additional_price': 0},
        {'id': 'v2', 'size': '40', 'color': 'Brown', 'additional_price': 10},
      ];

      final result = resolveVariant(variants: variants, size: '40');

      expect(result.variantId, isNotNull);
      expect(result.variantId, anyOf(equals('v1'), equals('v2')));
    });

    test('returns null variantId when no size matches', () {
      final variants = [
        {'id': 'v1', 'size': '40', 'color': 'Black', 'additional_price': 0},
        {'id': 'v2', 'size': '42', 'color': 'Brown', 'additional_price': 10},
      ];

      final result = resolveVariant(variants: variants, size: '38');

      expect(result.variantId, isNull);
      expect(result.additionalPrice, 0.0);
    });

    test('returns 0 additional_price for matching variant with null price', () {
      final variants = [
        {'id': 'v1', 'size': '40', 'color': 'Black', 'additional_price': null},
      ];

      final result = resolveVariant(variants: variants, size: '40', color: 'Black');

      expect(result.variantId, 'v1');
      expect(result.additionalPrice, 0.0);
    });

    test('handles empty variants list', () {
      final result = resolveVariant(variants: [], size: '40');

      expect(result.variantId, isNull);
      expect(result.additionalPrice, 0.0);
    });
  });

  group('normalizeSize', () {
    test('strips EU prefix', () {
      expect(normalizeSize('EU40'), '40');
    });

    test('strips US prefix', () {
      expect(normalizeSize('US9'), '9');
    });

    test('returns numeric size unchanged', () {
      expect(normalizeSize('40'), '40');
    });

    test('handles empty string', () {
      expect(normalizeSize(''), '');
    });

    test('strips mixed alpha prefix', () {
      expect(normalizeSize('PH42'), '42');
    });

    test('handles decimal size', () {
      expect(normalizeSize('EU40.5'), '40.5');
    });
  });

  group('resolveInventoryStock', () {
    test('returns stock for exact size match', () {
      final inventoryRows = [
        {'size': '40', 'stock': 10},
        {'size': '42', 'stock': 5},
      ];

      final stock = resolveInventoryStock(
        inventoryRows: inventoryRows,
        productId: 'p1',
        cartSize: '40',
        productName: 'Test Product',
      );

      expect(stock, 10);
    });

    test('returns stock for normalized size match (EU prefix)', () {
      final inventoryRows = [
        {'size': '40', 'stock': 10},
        {'size': '42', 'stock': 5},
      ];

      final stock = resolveInventoryStock(
        inventoryRows: inventoryRows,
        productId: 'p1',
        cartSize: 'EU40',
        productName: 'Test Product',
      );

      expect(stock, 10);
    });

    test('returns -1 when no inventory rows exist', () {
      final stock = resolveInventoryStock(
        inventoryRows: [],
        productId: 'p1',
        cartSize: '40',
        productName: 'Test Product',
      );

      expect(stock, -1);
    });

    test('returns -1 when cartSize is empty', () {
      final inventoryRows = [
        {'size': '40', 'stock': 10},
      ];

      final stock = resolveInventoryStock(
        inventoryRows: inventoryRows,
        productId: 'p1',
        cartSize: '',
        productName: 'Test Product',
      );

      expect(stock, -1);
    });

    test('returns -1 when no size matches', () {
      final inventoryRows = [
        {'size': '40', 'stock': 10},
        {'size': '42', 'stock': 5},
      ];

      final stock = resolveInventoryStock(
        inventoryRows: inventoryRows,
        productId: 'p1',
        cartSize: '38',
        productName: 'Test Product',
      );

      expect(stock, -1);
    });

    test('returns 0 stock when inventory row exists but stock is 0', () {
      final inventoryRows = [
        {'size': '40', 'stock': 0},
      ];

      final stock = resolveInventoryStock(
        inventoryRows: inventoryRows,
        productId: 'p1',
        cartSize: '40',
        productName: 'Test Product',
      );

      expect(stock, 0);
    });
  });

  group('size unit conversion (US / EU / UK)', () {
    test('US to EU adds 33 (men\'s scale)', () {
      expect(convertSizeNumber(7, 'US', 'EU'), 40);
      expect(convertSizeNumber(10, 'US', 'EU'), 43);
    });

    test('US to UK subtracts 0.5', () {
      expect(convertSizeNumber(7, 'US', 'UK'), 6.5);
      expect(convertSizeNumber(10, 'US', 'UK'), 9.5);
    });

    test('EU to US subtracts 33', () {
      expect(convertSizeNumber(40, 'EU', 'US'), 7);
    });

    test('UK to US adds 0.5', () {
      expect(convertSizeNumber(6.5, 'UK', 'US'), 7);
    });

    test('round trips are lossless for half sizes', () {
      expect(convertSizeNumber(convertSizeNumber(7.5, 'US', 'EU'), 'EU', 'US'), 7.5);
      expect(convertSizeNumber(convertSizeNumber(7.5, 'US', 'UK'), 'UK', 'US'), 7.5);
    });

    test('same unit is identity', () {
      expect(convertSizeNumber(9, 'US', 'US'), 9);
      expect(convertSizeNumber(42, 'EU', 'EU'), 42);
    });

    test('formatSizeNumber drops decimals for whole numbers', () {
      expect(formatSizeNumber(40.0), '40');
      expect(formatSizeNumber(6.5), '6.5');
    });

    test('sizeNumber extracts the numeric part', () {
      expect(sizeNumber('US 7.5'), 7.5);
      expect(sizeNumber('EU40'), 40);
      expect(sizeNumber('7'), 7);
      expect(sizeNumber('garbage'), isNull);
    });

    test('unitOf detects the prefix; bare numbers default to US', () {
      expect(unitOf('US 7'), 'US');
      expect(unitOf('EU40'), 'EU');
      expect(unitOf('UK 6.5'), 'UK');
      expect(unitOf('7'), 'US');
    });

    test('displaySizeInUnit converts without touching the canonical string', () {
      expect(displaySizeInUnit('US 7', 'EU'), 'EU 40');
      expect(displaySizeInUnit('US 7', 'UK'), 'UK 6.5');
      expect(displaySizeInUnit('US 7', 'US'), 'US 7');
      expect(displaySizeInUnit('EU 40', 'US'), 'US 7');
      // Unparseable → falls back to the raw string.
      expect(displaySizeInUnit('garbage', 'EU'), 'garbage');
    });
  });
}
