import 'package:flutter_test/flutter_test.dart';

import 'package:app/providers/product_provider.dart';

/// Tests for the 'Best Sellers' pseudo-category (item 7) and the pieces of
/// [ProductProvider] it touches.
///
/// The real provider fetches from Supabase, so these use the
/// [ProductProvider.seeded] test seam, which installs exactly the state
/// `loadProducts()` leaves behind (products + the `units_sold` aggregation,
/// with `units_sold` stamped onto each product map). That lets the filter rule,
/// the chip list and the sort be asserted directly instead of re-implemented
/// in the test.

/// A catalog product with sensible defaults.
Map<String, dynamic> product({
  required String id,
  String name = 'Artisan Shoe',
  String category = 'Sneakers',
  double price = 1000,
  double? salePrice,
  num? avgRating,
  int reviewCount = 0,
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
    'price': price,
    'sale_price': ?salePrice,
    'avg_rating': ?avgRating,
    'review_count': reviewCount,
  };
}

ProductProvider providerWith(
  List<Map<String, dynamic>> products,
  Map<String, int> unitsSold,
) =>
    ProductProvider.seeded(products: products, unitsSold: unitsSold);

void main() {
  group('bestSellerProducts — the inclusion rule', () {
    test('keeps only products that have actually sold, most-sold first', () {
      final a = product(id: 'a', name: 'A');
      final b = product(id: 'b', name: 'B');
      final c = product(id: 'c', name: 'C');

      final best = bestSellerProducts(
        [a, b, c],
        {'a': 5, 'b': 40, 'c': 12},
      );

      expect(best.map((p) => p['id']).toList(), ['b', 'c', 'a']);
    });

    test('never-sold products are excluded, not ranked last', () {
      final sold = product(id: 'sold');
      final never = product(id: 'never');

      final best = bestSellerProducts([sold, never], {'sold': 1, 'never': 0});

      expect(best.map((p) => p['id']).toList(), ['sold']);
    });

    test('a brand-new catalog (nothing sold) yields an empty set', () {
      final best = bestSellerProducts(
        [product(id: 'a'), product(id: 'b')],
        {},
      );

      expect(best, isEmpty);
    });

    test('caps at the limit, dropping the least-sold of the sold ones', () {
      final products = [
        for (var i = 0; i < 30; i++) product(id: 'p$i'),
      ];
      final units = {for (var i = 0; i < 30; i++) 'p$i': i + 1};

      final best = bestSellerProducts(products, units);

      expect(best.length, kBestSellerLimit);
      expect(best.first['id'], 'p29');
      // p0 (1 unit) is the cheapest to lose; p10 (11 units) stays.
      expect(best.map((p) => p['id']), isNot(contains('p0')));
      expect(best.map((p) => p['id']), contains('p10'));
    });

    test('a catalog smaller than the limit returns every sold product', () {
      final products = [product(id: 'p1'), product(id: 'p2')];
      final best = bestSellerProducts(products, {'p1': 2, 'p2': 1});

      expect(best.length, 2);
    });

    test('explicit limit is honoured', () {
      final products = [
        for (var i = 0; i < 5; i++) product(id: 'p$i'),
      ];
      final units = {for (var i = 0; i < 5; i++) 'p$i': i + 1};

      expect(bestSellerProducts(products, units, limit: 3).length, 3);
      // limit <= 0 means "no cap".
      expect(bestSellerProducts(products, units, limit: 0).length, 5);
    });

    test('ties break deterministically (rating, then name) despite shuffle',
        () {
      final lowerRated = product(
        id: 'low',
        name: 'Aaa',
        avgRating: 3.0,
      );
      final higherRated = product(id: 'high', name: 'Zzz', avgRating: 4.9);
      final units = {'low': 7, 'high': 7};

      // Same set in both catalog orders — the ranking must not depend on the
      // per-load shuffle.
      final first = bestSellerProducts(
        [lowerRated, higherRated],
        units,
      ).map((p) => p['id']).toList();
      final second = bestSellerProducts(
        [higherRated, lowerRated],
        units,
      ).map((p) => p['id']).toList();

      expect(first, ['high', 'low']);
      expect(second, first);
    });
  });

  group('categories — the Best Sellers chip', () {
    test('chip is appended when something has sold', () {
      final provider = providerWith(
        [product(id: 'a'), product(id: 'b')],
        {'a': 3},
      );

      expect(provider.categories, contains(kBestSellersCategory));
    });

    test('no chip at all when nothing has sold (brand-new store)', () {
      final provider = providerWith(
        [product(id: 'a'), product(id: 'b')],
        {},
      );

      expect(provider.hasBestSellers, isFalse);
      expect(provider.categories, isNot(contains(kBestSellersCategory)));
    });

    test('appears alongside the On Sale chip when both apply', () {
      final provider = providerWith(
        [
          product(id: 'a', salePrice: 800),
          product(id: 'b'),
        ],
        {'b': 9},
      );

      expect(provider.categories, contains('On Sale'));
      expect(provider.categories, contains(kBestSellersCategory));
      expect(provider.categories.first, 'All');
    });
  });

  group('getFilteredProducts — Best Sellers filter', () {
    test('returns exactly the best-seller set, most-sold first', () {
      final provider = providerWith(
        [
          product(id: 'top', name: 'Top'),
          product(id: 'mid', name: 'Mid'),
          product(id: 'never', name: 'Never'),
        ],
        // 'never' is deliberately absent from the aggregation entirely.
        {'top': 30, 'mid': 4},
      );

      provider.selectCategory(kBestSellersCategory);
      final filtered = provider.getFilteredProducts('');

      expect(filtered.map((p) => p['id']).toList(), ['top', 'mid']);
      expect(filtered.map((p) => p['id']), isNot(contains('never')));
    });

    test('combines with a search keyword', () {
      final provider = providerWith(
        [
          product(id: 'sandals', name: 'Woven Sandals'),
          product(id: 'boots', name: 'Trail Boots'),
          product(id: 'never', name: 'Unsold Sandals'),
        ],
        {'sandals': 8, 'boots': 3},
      );

      provider.selectCategory(kBestSellersCategory);
      final filtered = provider.getFilteredProducts('sandals');

      expect(filtered.map((p) => p['id']).toList(), ['sandals']);
    });

    test('combines with a search keyword that matches tags', () {
      final provider = providerWith(
        [
          {...product(id: 'tagged', name: 'Shoe'), 'tags': ['handmade']},
          product(id: 'plain', name: 'Shoe'),
        ],
        {'tagged': 5, 'plain': 9},
      );

      provider.selectCategory(kBestSellersCategory);
      final filtered = provider.getFilteredProducts('handmade');

      expect(filtered.map((p) => p['id']).toList(), ['tagged']);
    });

    test('keeps the rest of the catalog out even with no search', () {
      final provider = providerWith(
        [
          for (var i = 0; i < 25; i++)
            product(id: 'p$i', category: i.isEven ? 'Sneakers' : 'Boots'),
        ],
        {for (var i = 0; i < 25; i++) 'p$i': i + 1},
      );

      provider.selectCategory(kBestSellersCategory);

      expect(provider.getFilteredProducts('').length, kBestSellerLimit);
    });

    test('combines with an explicit sort (best-selling stays most-sold first)',
        () {
      final provider = providerWith(
        [
          product(id: 'a', price: 100),
          product(id: 'b', price: 900),
          product(id: 'c', price: 500),
        ],
        {'a': 1, 'b': 50, 'c': 10},
      );

      provider.selectCategory(kBestSellersCategory);
      provider.setSortMode(SortMode.bestSelling);

      expect(
        provider.getFilteredProducts('').map((p) => p['id']).toList(),
        ['b', 'c', 'a'],
      );
      // …and a price sort still wins when the customer asks for it.
      provider.setSortMode(SortMode.priceLowToHigh);
      expect(
        provider.getFilteredProducts('').map((p) => p['id']).toList(),
        ['a', 'c', 'b'],
      );
    });

    test('switching back to All restores the whole catalog', () {
      final provider = providerWith(
        [
          product(id: 'sold', name: 'Sold'),
          product(id: 'never', name: 'Never'),
        ],
        {'sold': 2},
      );

      provider.selectCategory(kBestSellersCategory);
      expect(provider.getFilteredProducts('').length, 1);

      provider.selectCategory('All');
      expect(provider.getFilteredProducts('').length, 2);
    });

    test(
        'a chip left selected with nothing sold degrades like an empty '
        'category (matches On Sale when a sale expires mid-session)', () {
      final provider = providerWith(
        [product(id: 'a'), product(id: 'b')],
        {},
      );

      provider.selectCategory(kBestSellersCategory);

      // The chip is not rendered at all in this state (see the categories
      // group above), so this is only reachable if the data changed under a
      // selected chip: the rule is inactive, the name matches no product's
      // category field, and the screen shows its empty state — whose
      // "browse all" action clears the selection. Deliberately the same
      // treatment On Sale gets, not a silently different behaviour.
      expect(provider.hasBestSellers, isFalse);
      expect(provider.getFilteredProducts(''), isEmpty);
    });
  });

  group('bestSellers getter — the home rail', () {
    test('reads the live aggregation (no stale snapshot)', () {
      final provider = providerWith(
        [product(id: 'a'), product(id: 'b')],
        {'a': 1},
      );

      expect(provider.bestSellers.map((p) => p['id']).toList(), ['a']);

      // A later load replaced both the catalog and the aggregation: the rail
      // follows the new data, not the previous ranking.
      final reloaded = providerWith(
        [product(id: 'a'), product(id: 'b')],
        {'b': 4},
      );

      expect(reloaded.bestSellers.map((p) => p['id']).toList(), ['b']);
    });

    test('products carry the stamped units_sold a card renders', () {
      final provider = providerWith([product(id: 'a')], {'a': 7});

      expect(provider.products.single['units_sold'], 7);
      expect(provider.unitsSoldFor('a'), 7);
      expect(provider.unitsSoldFor('unknown'), 0);
    });

    test('empty catalog yields an empty rail (section hides itself)', () {
      final provider = providerWith([], {});

      expect(provider.bestSellers, isEmpty);
    });
  });

  group('existing behaviour is unchanged', () {
    test('On Sale chip still filters by the active-sale rule', () {
      final provider = providerWith(
        [
          product(id: 'sale', salePrice: 500),
          product(id: 'full', price: 500),
        ],
        {'full': 3},
      );

      provider.selectCategory('On Sale');

      expect(provider.getFilteredProducts('').map((p) => p['id']).toList(),
          ['sale']);
    });

    test('a real category still filters by the category field', () {
      final provider = providerWith(
        [
          product(id: 'sneaker', category: 'Sneakers'),
          product(id: 'boot', category: 'Boots'),
        ],
        {'sneaker': 5, 'boot': 6},
      );

      provider.selectCategory('Boots');

      expect(provider.getFilteredProducts('').map((p) => p['id']).toList(),
          ['boot']);
    });

    test('SortMode.bestSelling still sorts the unfiltered catalog', () {
      final provider = providerWith(
        [
          product(id: 'a'),
          product(id: 'b'),
          product(id: 'never'),
        ],
        {'a': 2, 'b': 9},
      );

      provider.setSortMode(SortMode.bestSelling);

      // Never-sold items sort to the bottom rather than disappearing — the
      // sort has always kept them.
      expect(provider.getFilteredProducts('').map((p) => p['id']).toList(),
          ['b', 'a', 'never']);
    });

    test('sortModeLabel is untouched', () {
      expect(sortModeLabel(SortMode.bestSelling), 'Best Selling');
    });
  });
}
