import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/sale_price.dart';

void main() {
  Map<String, dynamic> product({
    dynamic price = 1000,
    dynamic salePrice,
    dynamic startsAt,
    dynamic endsAt,
  }) => {
    'price': price,
    'sale_price': ?salePrice,
    'sale_starts_at': ?startsAt,
    'sale_ends_at': ?endsAt,
  };

  final now = DateTime.utc(2026, 8, 4, 12); // Tuesday noon UTC

  group('isOnSale', () {
    test('active sale with no dates', () {
      expect(isOnSale(product(salePrice: 700), now: now), isTrue);
    });

    test('not-yet-started sale is not active', () {
      expect(
        isOnSale(
          product(salePrice: 700, startsAt: DateTime.utc(2026, 8, 5)),
          now: now,
        ),
        isFalse,
      );
    });

    test('expired sale is not active', () {
      expect(
        isOnSale(
          product(salePrice: 700, endsAt: DateTime.utc(2026, 8, 3)),
          now: now,
        ),
        isFalse,
      );
    });

    test('sale_price equal to price does NOT count as on sale', () {
      expect(isOnSale(product(salePrice: 1000), now: now), isFalse);
    });

    test('sale_price higher than price does NOT count as on sale', () {
      expect(isOnSale(product(salePrice: 1200), now: now), isFalse);
    });

    test('no sale fields at all (null-safe) is not on sale', () {
      expect(isOnSale(product(), now: now), isFalse);
    });

    test('sale price zero is not on sale', () {
      expect(isOnSale(product(salePrice: 0), now: now), isFalse);
    });

    test('active with future end date is on sale', () {
      expect(
        isOnSale(
          product(salePrice: 700, endsAt: DateTime.utc(2026, 8, 10)),
          now: now,
        ),
        isTrue,
      );
    });

    test('active with past start date is on sale', () {
      expect(
        isOnSale(
          product(salePrice: 700, startsAt: DateTime.utc(2026, 8, 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('sale starts exactly at now boundary counts as started', () {
      expect(
        isOnSale(product(salePrice: 700, startsAt: now), now: now),
        isTrue,
      );
    });
  });

  group('effectivePrice', () {
    test('returns sale price when on sale', () {
      expect(effectivePrice(product(salePrice: 700), now: now), 700);
    });

    test('returns original price when not on sale', () {
      expect(effectivePrice(product(), now: now), 1000);
      expect(effectivePrice(product(salePrice: 1000), now: now), 1000);
    });

    test('returns original price for expired sale', () {
      expect(
        effectivePrice(
          product(salePrice: 700, endsAt: DateTime.utc(2026, 8, 3)),
          now: now,
        ),
        1000,
      );
    });

    test('handles string prices from the DB', () {
      expect(
        effectivePrice(
          product(price: '1500', salePrice: '1200'),
          now: now,
        ),
        1200,
      );
    });
  });

  group('salePercent', () {
    test('computes discount percentage', () {
      expect(salePercent(product(salePrice: 700), now: now), 30); // 30% off
    });

    test('rounds to whole percent', () {
      expect(salePercent(product(salePrice: 667), now: now), 33);
    });

    test('returns null when not on sale', () {
      expect(salePercent(product(), now: now), isNull);
      expect(salePercent(product(salePrice: 1000), now: now), isNull);
    });
  });

  /// The "ON SALE · UP TO n%" poster's figure.
  ///
  /// It is the SAME rule as the rest of the page ([isOnSale]) read across a
  /// whole set, so what is pinned here is the set behaviour: the best deal wins
  /// rather than the last one, junk is skipped instead of dividing by it, and
  /// the rounding is DOWN — a shelf-wide "up to" claim must never advertise a
  /// discount no product in the catalog offers.
  group('maxDiscountPercent', () {
    test('is the biggest discount among the sale products', () {
      expect(
        maxDiscountPercent([
          product(price: 1000, salePrice: 900), // 10%
          product(price: 1000, salePrice: 700), // 30%
          product(price: 1000, salePrice: 800), // 20%
        ], now: now),
        30,
      );
    });

    test('rounds DOWN, unlike a badge', () {
      // 33.3% off — 33, never 34: the card speaks for the whole shelf.
      expect(
        maxDiscountPercent([product(price: 1000, salePrice: 667)], now: now),
        33,
      );
      // And it is genuinely floor, not round: 39.6% off stays 39.
      expect(
        maxDiscountPercent([product(price: 1000, salePrice: 604)], now: now),
        39,
      );
      expect(salePercent(product(price: 1000, salePrice: 667), now: now), 33);
    });

    test('null when nothing is on sale', () {
      expect(maxDiscountPercent(const [], now: now), isNull);
      expect(maxDiscountPercent([product()], now: now), isNull);
    });

    test('a sale that is not running does not count', () {
      expect(
        maxDiscountPercent([product()], now: now),
        isNull,
        reason: 'no sale_price at all',
      );
      expect(
        maxDiscountPercent([
          product(price: 1000),
          product(price: 1000, salePrice: 700),
          product(
            price: 1000,
            salePrice: 100,
            endsAt: DateTime.utc(2026, 8, 3),
          ), // expired: 90% off, and must NOT be the headline
          product(
            price: 1000,
            salePrice: 50,
            startsAt: DateTime.utc(2026, 8, 5),
          ), // not started yet
        ], now: now),
        30,
      );
    });

    test('invalid prices are skipped, never divided by', () {
      expect(
        maxDiscountPercent([
          product(price: 0, salePrice: 0), // no original price
          product(price: 1000, salePrice: 1000), // equal: not a discount
          product(price: 1000, salePrice: 1200), // higher: not a discount
          product(price: 1000, salePrice: 750), // 25%
        ], now: now),
        25,
      );
      expect(
        maxDiscountPercent([
          {'price': null, 'sale_price': 10},
          {'sale_price': 10},
        ], now: now),
        isNull,
      );
    });

    test('handles the string prices Supabase hands back', () {
      expect(
        maxDiscountPercent([
          product(price: '2000', salePrice: '1000'), // 50%
        ], now: now),
        50,
      );
    });

    test('a 100% off shelf is claimed honestly', () {
      expect(
        maxDiscountPercent([product(price: 1000, salePrice: 1)], now: now),
        99,
      );
    });
  });
}
