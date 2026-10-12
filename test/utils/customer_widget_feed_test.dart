import 'dart:math';

import 'package:app/models/customer_widget_data.dart';
import 'package:app/utils/customer_widget_feed.dart';
import 'package:flutter_test/flutter_test.dart';

/// One product row in the shape `SupabaseService.fetchProducts` returns.
///
/// ⚠️ The shape matters, and getting it wrong is how a test like this passes
/// vacuously: `stocksMySize` reads `inventory: [{size, stock}]` and **skips any
/// size whose system it does not own**, so a fixture written as `'42'` instead of
/// `'EU 42'` would match nothing and the "keeps only my size" assertions below
/// would pass for the wrong reason.
Map<String, dynamic> product({
  required String id,
  String? createdAt,
  List<(String, int)> stock = const [],
  String? audience,
  double price = 1000,
  double? salePrice,
  String? saleStartsAt,
  String? saleEndsAt,
}) =>
    <String, dynamic>{
      'id': id,
      'name': 'Product $id',
      'price': price,
      'sale_price': salePrice,
      'sale_starts_at': saleStartsAt,
      'sale_ends_at': saleEndsAt,
      'created_at': createdAt,
      'audience': audience,
      'inventory': [
        for (final (size, quantity) in stock) {'size': size, 'stock': quantity},
      ],
    };

void main() {
  group('new arrivals is the newest, and that is the whole rule', () {
    test('orders by created_at descending', () {
      final feed = feedForGroup(
        CustomerWidgetGroup.newArrivals,
        [
          product(id: 'old', createdAt: '2026-01-01T00:00:00Z'),
          product(id: 'newest', createdAt: '2026-10-01T00:00:00Z'),
          product(id: 'middle', createdAt: '2026-06-01T00:00:00Z'),
        ],
        euSize: null,
        limit: 0,
      );

      expect(feed.map((p) => p['id']).toList(), ['newest', 'middle', 'old']);
    });

    test('an unreadable created_at sorts LAST, not first', () {
      // The alternative — treating a missing date as "very old" or as "now" —
      // either buries a new product or puts a possibly-ancient one in the top
      // slot of a shelf that calls itself new.
      final feed = feedForGroup(
        CustomerWidgetGroup.newArrivals,
        [
          product(id: 'undated'),
          product(id: 'dated', createdAt: '2020-01-01T00:00:00Z'),
          product(id: 'unparseable', createdAt: 'not a date'),
        ],
        euSize: null,
        limit: 0,
      );

      expect(feed.first['id'], 'dated');
      expect(feed.skip(1).map((p) => p['id']), containsAll(['undated', 'unparseable']));
    });

  });

  group('the tile is ONE card, drawn at random from the shelf', () {
    // Six products, newest last, so "the shelf's own order" is p5 → p0.
    final shelf = [
      for (var i = 0; i < 6; i++)
        product(id: 'p$i', createdAt: '2026-01-0${i + 1}T00:00:00Z'),
    ];
    final ids = shelf.map((p) => p['id']).toList();

    test('exactly one product, at the default limit', () {
      final feed = feedForGroup(CustomerWidgetGroup.newArrivals, shelf, euSize: null);
      expect(kCustomerWidgetProductSlots, 1);
      expect(feed.length, 1);
    });

    test('the pick varies with the draw, and is stable under a seed', () {
      final first =
          feedForGroup(CustomerWidgetGroup.newArrivals, shelf, euSize: null, random: Random(7));
      final again =
          feedForGroup(CustomerWidgetGroup.newArrivals, shelf, euSize: null, random: Random(7));
      expect(first.single['id'], again.single['id']);

      // Across seeds the shelf is SAMPLED rather than truncated. This is the one
      // assertion that separates "one card, in random" from "one card, always the
      // newest" — which is what taking the head of the shelf would have given, and
      // what a customer would read as a tile that never changes.
      final seen = {
        for (var seed = 0; seed < 40; seed++)
          feedForGroup(CustomerWidgetGroup.newArrivals, shelf, euSize: null, random: Random(seed))
              .single['id'],
      };
      expect(seen.length, greaterThan(1));
      expect(seen, everyElement(isIn(ids)));
    });

    test('it does not repeat the product already on the tile', () {
      // A random draw repeats about one time in n, and a refresh that lands on the
      // same card is indistinguishable from a refresh that did not run.
      for (var seed = 0; seed < 25; seed++) {
        final pick = feedForGroup(CustomerWidgetGroup.newArrivals, shelf,
            euSize: null, random: Random(seed), avoidId: 'p3');
        expect(pick.single['id'], isNot('p3'));
      }
    });

    test('a one-product shelf still draws it even when it is the avoided one', () {
      // The exclusion is dropped rather than the shelf emptied: one product on the
      // tile beats a blank one, and the blank would look like a failure.
      final pick = feedForGroup(
        CustomerWidgetGroup.newArrivals,
        [product(id: 'only', createdAt: '2026-01-01T00:00:00Z')],
        euSize: null,
        random: Random(3),
        avoidId: 'only',
      );
      expect(pick.single['id'], 'only');
    });

    test('with no Random injected it falls back to the shelf\'s own order', () {
      // Which is what keeps this function usable as a pure "what qualifies" query:
      // every other test in this file reads it that way, and the service is the one
      // caller that passes a generator in.
      final feed = feedForGroup(CustomerWidgetGroup.newArrivals, shelf, euSize: null);
      expect(feed.single['id'], 'p5');
    });

    test('and the random pick applies to every shelf, not just new arrivals', () {
      // The cap lives in ONE place (`_cap`) for exactly this reason: a shelf that
      // capped its own way would make the tile's behaviour depend on which shelf was
      // showing, and an in-my-size shelf would silently keep the head of the list.
      final inSize = [
        for (var i = 0; i < 6; i++)
          product(id: 's$i', stock: [('EU 42', 2)]),
      ];
      final seen = {
        for (var seed = 0; seed < 40; seed++)
          feedForGroup(CustomerWidgetGroup.inMySize, inSize,
                  euSize: 42, random: Random(seed))
              .single['id'],
      };
      expect(seen.length, greaterThan(1));
      expect(
        feedForGroup(CustomerWidgetGroup.inMySize, inSize, euSize: 42).length,
        1,
        reason: 'the size shelf must obey the same one-slot cap',
      );
    });
  });

  group('in my size is the same rule as the home grid', () {
    test('keeps only products that stock the size, right now', () {
      final feed = feedForGroup(
        CustomerWidgetGroup.inMySize,
        [
          product(id: 'fit', stock: [('EU 42', 3)]),
          product(id: 'wrong-size', stock: [('EU 40', 3)]),
          product(id: 'sold-out', stock: [('EU 42', 0)]),
          product(id: 'no-data'),
        ],
        euSize: 42,
        // `limit: 0` — the filter is what this asserts. The one-card cap is a
        // separate rule and is proven in its own group below.
        limit: 0,
      );

      expect(feed.map((p) => p['id']).toList(), ['fit']);
    });

    test('no size on file yields nothing, never a fallback size', () {
      final feed = feedForGroup(
        CustomerWidgetGroup.inMySize,
        [product(id: 'a', stock: [('EU 42', 1)])],
        euSize: null,
      );

      expect(feed, isEmpty);
    });

    test('the shopping scale narrows the shelf, and unisex comes through', () {
      // The gendered half: a men's shopper is not shown a women's-only product,
      // and a unisex one IS in their size — it is a personal shelf, not a rail
      // that would list it three times.
      final products = [
        product(id: 'mens', stock: [('EU 42', 2)], audience: 'men'),
        product(id: 'womens', stock: [('EU 42', 2)], audience: 'women'),
        product(id: 'unisex', stock: [('EU 42', 2)], audience: 'unisex'),
        product(id: 'unstated', stock: [('EU 42', 2)]),
      ];

      expect(
        feedForGroup(
          CustomerWidgetGroup.inMySize,
          products,
          euSize: 42,
          category: 'men',
          limit: 0,
        ).map((p) => p['id']),
        ['mens', 'unisex'],
      );

      // No scale picked: size only. Emptying the shelf for a customer who never
      // chose a chart would hide the one surface that reads their size at all.
      // `limit: 0` because the tile's default cap of three is a separate rule —
      // asserting through it would say the fourth product failed the filter.
      expect(
        feedForGroup(CustomerWidgetGroup.inMySize, products,
                euSize: 42, limit: 0)
            .map((p) => p['id']),
        ['mens', 'womens', 'unisex', 'unstated'],
      );
    });
  });

  group('on sale is the live sale, by the app\'s own rule', () {
    final now = DateTime.utc(2026, 10, 12, 12);

    test('an expired, not-yet-started or cleared sale does not qualify', () {
      final feed = feedForGroup(
        CustomerWidgetGroup.onSale,
        [
          product(id: 'live', price: 100, salePrice: 80),
          product(id: 'ended', price: 100, salePrice: 80, saleEndsAt: '2026-10-01T00:00:00Z'),
          product(id: 'scheduled', price: 100, salePrice: 80, saleStartsAt: '2026-11-01T00:00:00Z'),
          product(id: 'no-op', price: 100, salePrice: 100),
          product(id: 'cleared', price: 100),
        ],
        euSize: null,
        now: now,
      );

      expect(feed.map((p) => p['id']).toList(), ['live']);
    });

    test('the shelf keeps the order it was handed', () {
      // No re-ranking by discount: the catalog is shuffled once per load, and
      // that shuffle is where the tile's variety comes from. Ranking here would
      // put the same three products on every customer's tile forever.
      final feed = feedForGroup(
        CustomerWidgetGroup.onSale,
        [
          product(id: 'small-discount', price: 100, salePrice: 95),
          product(id: 'big-discount', price: 100, salePrice: 50),
        ],
        euSize: null,
        now: now,
        limit: 0,
      );

      expect(feed.map((p) => p['id']).toList(), ['small-discount', 'big-discount']);
    });
  });

  group('pickGroup — one group per refresh, and never an empty one', () {
    final all = CustomerWidgetGroup.values.toSet();

    test('advancing moves to the next group', () {
      expect(
        pickGroup(
          available: all,
          lastShownIndex: CustomerWidgetGroup.newArrivals.index,
          advance: true,
        ),
        CustomerWidgetGroup.inMySize,
      );
    });

    test('advancing wraps around the end', () {
      expect(
        pickGroup(
          available: all,
          lastShownIndex: CustomerWidgetGroup.onSale.index,
          advance: true,
        ),
        CustomerWidgetGroup.newArrivals,
      );
    });

    test('a group with nothing in it is skipped, not shown empty', () {
      expect(
        pickGroup(
          available: {CustomerWidgetGroup.newArrivals, CustomerWidgetGroup.onSale},
          lastShownIndex: CustomerWidgetGroup.newArrivals.index,
          advance: true,
        ),
        CustomerWidgetGroup.onSale,
      );

      // With only the current group left it stays put rather than rotating onto
      // an empty shelf or clearing the tile.
      expect(
        pickGroup(
          available: {CustomerWidgetGroup.onSale},
          lastShownIndex: CustomerWidgetGroup.onSale.index,
          advance: true,
        ),
        CustomerWidgetGroup.onSale,
      );
    });

    test('an app-driven sync re-renders the SAME group', () {
      // The difference between the two kinds of refresh. Advancing here as well
      // would change the tile every time the customer opened the app.
      expect(
        pickGroup(
          available: all,
          lastShownIndex: CustomerWidgetGroup.onSale.index,
          advance: false,
        ),
        CustomerWidgetGroup.onSale,
      );
    });

    test('an app-driven sync still moves on if that group is now empty', () {
      expect(
        pickGroup(
          available: {CustomerWidgetGroup.inMySize},
          lastShownIndex: CustomerWidgetGroup.onSale.index,
          advance: false,
        ),
        CustomerWidgetGroup.inMySize,
      );
    });

    test('nothing available is null, which the caller answers by clearing', () {
      expect(pickGroup(available: {}, lastShownIndex: 0, advance: true), isNull);
    });

    test('an unknown position lands on the first group with products', () {
      // A cleared store, or a payload written by a build that knew fewer groups.
      expect(
        pickGroup(available: all, lastShownIndex: -1, advance: false),
        CustomerWidgetGroup.newArrivals,
      );
      expect(
        pickGroup(available: all, lastShownIndex: 99, advance: true),
        CustomerWidgetGroup.newArrivals,
      );
    });
  });
}
