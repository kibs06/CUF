import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/product_stock.dart';

void main() {
  Map<String, dynamic> product(List<Map<String, dynamic>>? inventory) =>
      {'inventory': inventory};

  group('totalStock', () {
    test('sums stock across all sizes', () {
      expect(
        totalStock(product([
          {'size': '38', 'stock': 3},
          {'size': '40', 'stock': 5},
          {'size': '42', 'stock': 2},
        ])),
        10,
      );
    });

    test('returns 0 when every size is out of stock', () {
      expect(
        totalStock(product([
          {'size': '38', 'stock': 0},
          {'size': '40', 'stock': 0},
        ])),
        0,
      );
    });

    test('returns 0 when there are no inventory rows', () {
      expect(totalStock(product([])), 0);
    });

    test('returns 0 when inventory key is missing', () {
      expect(totalStock({'name': 'No inventory at all'}), 0);
    });

    test('ignores rows with missing stock', () {
      expect(
        totalStock(product([
          {'size': '38', 'stock': 4},
          {'size': '40'},
        ])),
        4,
      );
    });
  });

  group('isOutOfStock', () {
    test('false when at least one size has stock', () {
      expect(
        isOutOfStock(product([
          {'size': '38', 'stock': 1},
          {'size': '40', 'stock': 0},
        ])),
        isFalse,
      );
    });

    test('true when all sizes are zero', () {
      expect(
        isOutOfStock(product([
          {'size': '38', 'stock': 0},
        ])),
        isTrue,
      );
    });

    test('true when there are no inventory rows', () {
      expect(isOutOfStock(product([])), isTrue);
      expect(isOutOfStock({'name': 'legacy product'}), isTrue);
    });
  });

  group('purchasableProducts (hide-until-restocked browse rule)', () {
    test('keeps products with stock on at least one size', () {
      final products = [
        {'name': 'A', 'inventory': [
          {'size': '40', 'stock': 2},
        ]},
        {'name': 'B', 'inventory': [
          {'size': '40', 'stock': 0},
        ]},
        {'name': 'C', 'inventory': [
          {'size': '40', 'stock': 5},
          {'size': '42', 'stock': 0},
        ]},
      ];
      final result = purchasableProducts(products);
      expect(result.map((p) => p['name']), ['A', 'C']);
    });

    test('excludes products with zero stock on every size', () {
      final products = [
        {'name': 'OOS', 'inventory': [
          {'size': '40', 'stock': 0},
        ]},
        {'name': 'Legacy', 'inventory': []},
        {'name': 'NoInventoryKey', 'sizes': {'40': 0}},
      ];
      expect(purchasableProducts(products), isEmpty);
    });

    test('restocked product reappears on the next fetch', () {
      // Seller's stock hits 0 → product drops out of customer browse.
      final beforeRestock = {
        'name': 'Oxford',
        'inventory': [
          {'size': '41', 'stock': 0},
        ],
      };
      expect(purchasableProducts([beforeRestock]), isEmpty);

      // Seller restocks via Adjust Stock → inventory row is now > 0.
      final afterRestock = {
        'name': 'Oxford',
        'inventory': [
          {'size': '41', 'stock': 4},
        ],
      };
      final result = purchasableProducts([afterRestock]);
      expect(result.map((p) => p['name']), ['Oxford']);
    });

    test('returns empty for an empty catalog', () {
      expect(purchasableProducts([]), isEmpty);
    });
  });

  group('distributeVariantStock (restock keeps variants in sync)', () {
    test('adds the delta to the first row when increasing total', () {
      expect(distributeVariantStock([5, 3], 10), [7, 3]);
      expect(distributeVariantStock([5, 3], 18), [15, 3]);
    });

    test('subtracts the delta across rows when decreasing total', () {
      expect(distributeVariantStock([5, 3], 4), [1, 3]);
      expect(distributeVariantStock([5, 3], 0), [0, 0]);
    });

    test('no change when the target equals the current total', () {
      expect(distributeVariantStock([5, 3], 8), [5, 3]);
      expect(distributeVariantStock([0, 0], 0), [0, 0]);
    });

    test('clamps rows at zero and absorbs as much delta as possible', () {
      expect(distributeVariantStock([2, 3], 0), [0, 0]);
    });

    test('single row edge cases', () {
      expect(distributeVariantStock([5], 0), [0]);
      expect(distributeVariantStock([5], 10), [10]);
      expect(distributeVariantStock([5], 5), [5]);
    });

    test('empty input stays empty', () {
      expect(distributeVariantStock([], 0), isEmpty);
      expect(distributeVariantStock([], 5), isEmpty);
    });
  });
}
