import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/sale_price.dart';

void main() {
  Map<String, dynamic> product({
    dynamic price = 1000,
    dynamic salePrice,
    dynamic startsAt,
    dynamic endsAt,
  }) =>
      {
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
          product(
            salePrice: 700,
            startsAt: DateTime.utc(2026, 8, 5),
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('expired sale is not active', () {
      expect(
        isOnSale(
          product(
            salePrice: 700,
            endsAt: DateTime.utc(2026, 8, 3),
          ),
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
        isOnSale(
          product(salePrice: 700, startsAt: now),
          now: now,
        ),
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
      expect(effectivePrice(product(price: '1500', salePrice: '1200'), now: now),
          1200);
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
}
