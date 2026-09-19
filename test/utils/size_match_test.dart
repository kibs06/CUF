import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/foot_measurement.dart';
import 'package:app/utils/size_match.dart';

/// The rule that decides whether a product stocks the customer's size.
///
/// Every size-aware surface reads this one rule, so the cases that matter are
/// the ones where being *confidently wrong* would be worse than saying nothing:
/// a size stored in another system, a bare value outside the app's bands, a
/// sold-out exact size, and the near-size band.
Map<String, dynamic> productWithStock(List<(String size, int stock)> rows) => {
  'id': 'p',
  'name': 'Artisan Shoe',
  'inventory': [
    for (final (size, stock) in rows) {'size': size, 'stock': stock},
  ],
};

void main() {
  group('stockByEuSize — the authoritative source', () {
    test('keys inventory rows by EU size', () {
      final stock = stockByEuSize(
        productWithStock([('EU 42', 3), ('EU 43', 0)]),
      );

      expect(stock[42], 3);
      expect(stock[43], 0);
    });

    test('a bare size counts as EU (the app\'s default system)', () {
      expect(stockByEuSize(productWithStock([('42', 5)]))[42], 5);
    });

    test('sums a size across colours', () {
      // Black EU 42: 2 + Brown EU 42: 3 → 5 available on EU 42.
      final stock = stockByEuSize(
        productWithStock([('EU 42', 2), ('EU 42', 3)]),
      );

      expect(stock[42], 5);
    });

    test('a prefixed size is converted, not read as its digits', () {
      // US 9 (men) = EU 42.
      final stock = stockByEuSize(productWithStock([('US 9', 4)]));

      expect(stock[42], 4);
      expect(stock.containsKey(9), isFalse);
    });

    test('a system the app owns no chart for is skipped', () {
      // 'JP 25' is not EU 25 — guessing here is the wrong-claim risk.
      expect(stockByEuSize(productWithStock([('JP 25', 9)])), isEmpty);
    });

    test('a bare value outside the plausible band is skipped', () {
      // A bare '9' is far more likely a US 9 than an EU 9.
      expect(stockByEuSize(productWithStock([('9', 4)])), isEmpty);
      expect(stockByEuSize(productWithStock([('60', 4)])), isEmpty);
    });

    test("a child's size is matched like anyone else's", () {
      // The kids' band is 22–35; it must not be filtered out.
      expect(stockByEuSize(productWithStock([('28', 2)]))[28], 2);
    });

    test('a product with no size data yields nothing', () {
      expect(stockByEuSize({'id': 'p'}), isEmpty);
      expect(stockByEuSize({'id': 'p', 'inventory': 'nonsense'}), isEmpty);
    });

    test('product_variants alone are NOT the stock source', () {
      // inventory is authoritative; variants are derived from it. Reading
      // both could claim stock the buy button does not have (plan R4).
      final product = {
        'id': 'p',
        'product_variants': [
          {'size': 'EU 42', 'stock': 9},
        ],
      };

      expect(stockByEuSize(product), isEmpty);
      expect(stocksMySize(product, 42), isFalse);
    });
  });

  group('matchStockedSize', () {
    test('an exact size in stock is an exact match', () {
      final match = matchStockedSize(productWithStock([('EU 42', 2)]), 42);

      expect(match?.kind, SizeMatchKind.exact);
      expect(match?.euSize, 42);
      expect(match?.stock, 2);
      expect(match?.isAvailable, isTrue);
    });

    test('a sold-out exact size still answers, and reads as unavailable', () {
      // The product DOES sell EU 42. Offering EU 41.5 instead would be a
      // different shoe on a different fit.
      final match = matchStockedSize(
        productWithStock([('EU 42', 0), ('EU 41.5', 4)]),
        42,
      );

      expect(match?.kind, SizeMatchKind.exact);
      expect(match?.stock, 0);
      expect(match?.isAvailable, isFalse);
      expect(stocksMySize(productWithStock([('EU 42', 0)]), 42), isFalse);
    });

    test('a half size away answers as near, and is never substituted', () {
      final match = matchStockedSize(productWithStock([('EU 41.5', 3)]), 42);

      expect(match?.kind, SizeMatchKind.near);
      expect(match?.euSize, 41.5);
      expect(match?.isAvailable, isTrue);
      // Near is not "my size": a suggestion rail must not include it.
      expect(stocksMySize(productWithStock([('EU 41.5', 3)]), 42), isFalse);
    });

    test('a whole size away is not close enough to mention', () {
      expect(matchStockedSize(productWithStock([('EU 43', 3)]), 42), isNull);
    });

    test(
      'equally-near sizes resolve down, never above the customer\'s size',
      () {
        // 41.5 and 42.5 are both 0.5 away.
        final match = matchStockedSize(
          productWithStock([('EU 42.5', 2), ('EU 41.5', 2)]),
          42,
        );

        expect(match?.euSize, 41.5);
      },
    );

    test('no size data at all is null, not a guess', () {
      expect(matchStockedSize({'id': 'p'}, 42), isNull);
    });
  });

  group('shoppingEuSizeFrom — where "my size" comes from', () {
    test('the profile snapshot is the answer', () {
      expect(shoppingEuSizeFrom({'foot_size_ph': 42}), 42.0);
      // Stored as a string, and pre-labelled — both are the same size.
      expect(shoppingEuSizeFrom({'foot_size_ph': '42'}), 42.0);
      expect(shoppingEuSizeFrom({'foot_size_ph': 'EU 42.5'}), 42.5);
    });

    test('the snapshot wins over a scan in memory', () {
      // saveFootProfile is written by BOTH paths, so it is the more recent
      // thing the customer told us; a measurement in memory can be older than
      // a manual entry typed after it.
      final measurement = FootMeasurement(
        userId: 'u1',
        recommendedEuSize: '44',
        paperSizeUsed: 'ar',
        scanDate: DateTime(2026, 1, 1),
      );

      expect(
        shoppingEuSizeFrom({'foot_size_ph': 42}, measurement: measurement),
        42.0,
      );
    });

    test('a scan is the fallback when the snapshot has no size', () {
      final measurement = FootMeasurement(
        userId: 'u1',
        recommendedEuSize: '44',
        paperSizeUsed: 'ar',
        scanDate: DateTime(2026, 1, 1),
      );

      expect(shoppingEuSizeFrom(null, measurement: measurement), 44.0);
      expect(
        shoppingEuSizeFrom({'foot_size_ph': '   '}, measurement: measurement),
        44.0,
      );
    });

    test('the user-adjusted size on a scan wins over its recommendation', () {
      final measurement = FootMeasurement(
        userId: 'u1',
        recommendedEuSize: '44',
        userAdjustedEuSize: '43',
        paperSizeUsed: 'ar',
        scanDate: DateTime(2026, 1, 1),
      );

      expect(shoppingEuSizeFrom(null, measurement: measurement), 43.0);
    });

    test('nothing anywhere is null — every surface then renders nothing', () {
      expect(shoppingEuSizeFrom(null), isNull);
      expect(shoppingEuSizeFrom({}), isNull);
      expect(shoppingEuSizeFrom({'foot_size_ph': null}), isNull);
      expect(shoppingEuSizeFrom({'foot_size_ph': 'not a size'}), isNull);
    });
  });

  group('euSizeLabel', () {
    test('names the system and drops the pointless decimal', () {
      expect(euSizeLabel(42), 'EU 42');
      expect(euSizeLabel(42.5), 'EU 42.5');
    });
  });

  group('euSizeValue', () {
    test('prints the number alone, for a card that labels the unit itself', () {
      expect(euSizeValue(42), '42');
      expect(euSizeValue(42.5), '42.5');
      expect(euSizeValue(22), '22');
    });
  });
}
