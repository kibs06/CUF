import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/sale_price.dart';
import 'package:app/utils/store_sale.dart';

/// The store-level aggregate the Stores tab's sale tag reads.
///
/// It is a *summary*, not a new rule: every case here is really asserting that
/// the summary agrees with `sale_price.dart` — the same `isOnSale`, the same
/// floored `maxDiscountPercent`, and the expiry from the same set.

Map<String, dynamic> product({
  String id = 'p',
  double price = 1000,
  double? salePrice,
  DateTime? startsAt,
  DateTime? endsAt,
}) => {
  'id': id,
  'name': 'Artisan Shoe',
  'price': price,
  'sale_price': ?salePrice,
  'sale_starts_at': ?startsAt,
  'sale_ends_at': ?endsAt,
};

void main() {
  final now = DateTime(2026, 9, 21, 12);

  group('storeSaleFrom', () {
    test('counts only the products on sale right now', () {
      final sale = storeSaleFrom([
        product(id: 'on', salePrice: 700),
        product(id: 'full-price'),
        // Expired: the shared rule excludes it, so the count and the figure are
        // both built from what a customer can actually buy at a discount.
        product(
          id: 'over',
          salePrice: 700,
          endsAt: now.subtract(const Duration(hours: 1)),
        ),
        // Not started yet.
        product(
          id: 'soon',
          salePrice: 700,
          startsAt: now.add(const Duration(hours: 1)),
        ),
      ], now: now);

      expect(sale.count, 1);
      expect(sale.hasSale, isTrue);
    });

    test('takes the best discount, floored like the ON SALE poster', () {
      final sale = storeSaleFrom([
        product(id: 'small', price: 1000, salePrice: 900), // 10%
        product(id: 'best', price: 1000, salePrice: 667), // 33.3%
        product(id: 'mid', price: 1000, salePrice: 800), // 20%
      ], now: now);

      expect(sale.bestDiscount, 33);
    });

    test('a shelf with no sale is empty, never a zero figure', () {
      final sale = storeSaleFrom([product(id: 'a'), product(id: 'b')], now: now);

      expect(sale.hasSale, isFalse);
      expect(sale.count, 0);
      expect(sale.bestDiscount, isNull);
      expect(sale.earliestEnd, isNull);
    });

    test('a sale too small to floor counts, but has no figure', () {
      // 1000 → 999 is a real active sale (`isOnSale` is true) that floors to
      // 0%, so `maxDiscountPercent` returns null. The tag still has to appear
      // — hiding would make a store that IS on sale look like one that is not.
      final sale = storeSaleFrom([
        product(id: 'tiny', price: 1000, salePrice: 999),
      ], now: now);

      expect(sale.hasSale, isTrue);
      expect(sale.bestDiscount, isNull);
    });

    test('an empty store has no sale', () {
      final sale = storeSaleFrom(const [], now: now);

      expect(sale.hasSale, isFalse);
      expect(sale.bestDiscount, isNull);
      expect(sale.earliestEnd, isNull);
    });

    test('the label names the count and the figure it actually shows', () {
      final sale = storeSaleFrom([
        product(id: 'a', price: 1000, salePrice: 700),
        product(id: 'b', price: 1000, salePrice: 600),
      ], now: now);

      expect(
        sale.semanticsLabel,
        "On sale: 2 items, up to 40 percent off. Double tap to see this "
        "store's sale items.",
      );

      // And a sale with no floorable figure never claims "0 percent".
      final tiny = storeSaleFrom([
        product(id: 'tiny', price: 1000, salePrice: 999),
      ], now: now);
      expect(tiny.semanticsLabel, startsWith('On sale: 1 item.'));
    });
  });

  group('earliestSaleEnd', () {
    test('is the soonest end among the active sales', () {
      final soon = now.add(const Duration(hours: 2));
      final later = now.add(const Duration(days: 3));

      expect(
        earliestSaleEnd([
          product(id: 'later', salePrice: 700, endsAt: later),
          product(id: 'soon', salePrice: 700, endsAt: soon),
        ], now: now),
        soon,
      );
    });

    test('open-ended sales are skipped, not treated as never-ending claims', () {
      final soon = now.add(const Duration(days: 1));

      expect(
        earliestSaleEnd([
          product(id: 'open', salePrice: 700), // no end date
          product(id: 'ends', salePrice: 700, endsAt: soon),
        ], now: now),
        soon,
      );

      // Only open-ended sales → nothing to schedule.
      expect(
        earliestSaleEnd([product(id: 'open', salePrice: 700)], now: now),
        isNull,
      );
    });

    test('ignores sales that are not active', () {
      expect(
        earliestSaleEnd([
          product(
            id: 'over',
            salePrice: 700,
            endsAt: now.subtract(const Duration(minutes: 1)),
          ),
        ], now: now),
        isNull,
      );
    });

    test('surfaces the next end once the soonest has passed', () {
      final first = now.add(const Duration(hours: 1));
      final second = now.add(const Duration(hours: 5));
      final products = [
        product(id: 'a', salePrice: 700, endsAt: first),
        product(id: 'b', salePrice: 700, endsAt: second),
      ];

      expect(earliestSaleEnd(products, now: now), first);
      // One second past the first end: the store is still on sale, and the
      // watcher needs the *next* moment to arm for.
      expect(
        earliestSaleEnd(products, now: first.add(const Duration(seconds: 1))),
        second,
      );
    });
  });
}
