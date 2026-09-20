import 'package:flutter_test/flutter_test.dart';

import 'package:app/providers/product_provider.dart';
import 'package:app/utils/product_audience.dart';

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
///
/// [stock] is the size/stock pairs that make up the product's authoritative
/// `inventory` relation (the shape `SupabaseService.fetchProducts()` returns).
Map<String, dynamic> product({
  required String id,
  String name = 'Artisan Shoe',
  String category = 'Sneakers',
  double price = 1000,
  double? salePrice,
  num? avgRating,
  int reviewCount = 0,
  List<(String, int)> stock = const [],
  String? audience,
  List<String> tags = const [],
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
    'tags': tags,
    'price': price,
    'sale_price': ?salePrice,
    'avg_rating': ?avgRating,
    'review_count': reviewCount,
    // Omitted entirely when unset, which is exactly how a row with a NULL
    // `audience` arrives from PostgREST.
    'audience': ?audience,
    'inventory': [
      for (final (size, units) in stock) {'size': size, 'stock': units},
    ],
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

    test('every mode has a short label too, and none of them is longer', () {
      // The sheet shows the long ones and the Workshop Collection poster shows
      // the short ones. Both lists are exhaustive over the enum, so a mode
      // added with only a long label does not compile; this pins the pairs so a
      // later edit cannot quietly give one surface the other one's words.
      expect(sortModeShortLabel(SortMode.featured), 'Featured');
      expect(sortModeShortLabel(SortMode.priceLowToHigh), 'Low to High');
      expect(sortModeShortLabel(SortMode.priceHighToLow), 'High to Low');
      expect(sortModeShortLabel(SortMode.nameAZ), 'A to Z');
      expect(sortModeShortLabel(SortMode.nameZA), 'Z to A');
      expect(sortModeShortLabel(SortMode.topRated), 'Top Rated');
      expect(sortModeShortLabel(SortMode.bestSelling), 'Best Selling');

      for (final mode in SortMode.values) {
        expect(
          sortModeShortLabel(mode).length,
          lessThanOrEqualTo(sortModeLabel(mode).length),
          reason: '$mode is only shortened, never rewritten',
        );
      }
    });
  });

  group('productsInSize — the "Based on your size" grid', () {
    test('keeps exactly the products that stock the size right now', () {
      final provider = providerWith(
        [
          product(id: 'fit', stock: [('EU 42', 3)]),
          product(id: 'other-size', stock: [('EU 40', 3)]),
          product(id: 'no-data'),
        ],
        {},
      );

      expect(provider.productsInSize(42).map((p) => p['id']).toList(), ['fit']);
    });

    test('a sold-out size is not suggested, and neither is the next size down',
        () {
      final provider = providerWith(
        [
          product(id: 'sold-out', stock: [('EU 42', 0)]),
          // Close, but not the customer's size: a suggestion rail offers
          // what they actually wear, not what fits "roughly".
          product(id: 'near', stock: [('EU 41.5', 4)]),
        ],
        {},
      );

      expect(provider.productsInSize(42), isEmpty);
    });

    test('no size on file yields no rail — never a fallback size', () {
      final provider = providerWith(
        [product(id: 'a', stock: [('EU 42', 3)])],
        {},
      );

      expect(provider.productsInSize(null), isEmpty);
    });

    test('a size stored in another system converts before it is matched', () {
      // US 9 on the men's chart is EU 42 — the same physical size.
      final provider = providerWith(
        [product(id: 'us-sized', stock: [('US 9', 2)])],
        {},
      );

      expect(provider.productsInSize(42).map((p) => p['id']).toList(),
          ['us-sized']);
    });

    test('ranks by units sold, not catalog order', () {
      final provider = providerWith(
        [
          product(id: 'low', name: 'Low', stock: [('EU 42', 1)]),
          product(id: 'high', name: 'High', stock: [('EU 42', 1)]),
          product(id: 'mid', name: 'Mid', stock: [('EU 42', 1)]),
        ],
        {'low': 1, 'high': 50, 'mid': 10},
      );

      expect(provider.productsInSize(42).map((p) => p['id']).toList(),
          ['high', 'mid', 'low']);
    });

    test('a never-sold product still qualifies (only the best-seller rule '
        'needs sales)', () {
      final provider = providerWith(
        [product(id: 'new', name: 'New', stock: [('EU 42', 2)])],
        {},
      );

      expect(provider.productsInSize(42).map((p) => p['id']).toList(), ['new']);
    });

    test('ties break deterministically (rating, then name) despite shuffle',
        () {
      final lowerRated = product(
        id: 'low',
        name: 'Aaa',
        avgRating: 3.0,
        stock: [('EU 42', 1)],
      );
      final higherRated = product(
        id: 'high',
        name: 'Zzz',
        avgRating: 4.9,
        stock: [('EU 42', 1)],
      );

      final first = providerWith([lowerRated, higherRated], {})
          .productsInSize(42)
          .map((p) => p['id'])
          .toList();
      final second = providerWith([higherRated, lowerRated], {})
          .productsInSize(42)
          .map((p) => p['id'])
          .toList();

      expect(first, ['high', 'low']);
      expect(second, first);
    });

    test('returns the whole shelf by default, most-sold first', () {
      final provider = providerWith(
        [
          for (var i = 0; i < 20; i++)
            product(id: 'p$i', name: 'P$i', stock: [('EU 42', 1)]),
        ],
        {for (var i = 0; i < 20; i++) 'p$i': i + 1},
      );

      final shelf = provider.productsInSize(42);

      // Uncapped, like `productsInAudience`: the home section decides its own
      // preview length (ten cells + a "See more" card), and needs the whole
      // shelf to know whether that card belongs there at all.
      expect(shelf.length, 20);
      expect(shelf.first['id'], 'p19');
      expect(shelf.last['id'], 'p0');
    });

    test('a catalog with nothing in that size yields an empty rail', () {
      final provider = providerWith(
        [product(id: 'a', stock: [('EU 40', 2)])],
        {'a': 9},
      );

      // The section hides itself on an empty list — no header with no cards.
      expect(provider.productsInSize(42), isEmpty);
    });

    test('an explicit limit is honoured, and 0 means no cap', () {
      final provider = providerWith(
        [
          for (var i = 0; i < 5; i++)
            product(id: 'p$i', stock: [('EU 42', 1)]),
        ],
        {for (var i = 0; i < 5; i++) 'p$i': i + 1},
      );

      expect(provider.productsInSize(42, limit: 3).length, 3);
      expect(provider.productsInSize(42, limit: 0).length, 5);
    });
  });

  /// The search page's own lookups. Both are derived from the catalog already
  /// in memory, so there is no query and no network to stub.
  group('searchResults / suggestionsFor / relatedProducts', () {
    test('finds the catalog by its OWN vocabulary — the reported dead end', () {
      // "Formal Shoes" matched nothing before: `Formal` is a CATEGORY value,
      // and no product is named it or tagged with it.
      final provider = providerWith(
        [
          product(id: 'oxford', name: 'Classic Oxford', category: 'Formal'),
          product(id: 'slide', name: 'Beach Slide', category: 'Sandals'),
        ],
        {},
      );

      expect(
        provider.searchResults('Formal Shoes').map((p) => p['id']).toList(),
        ['oxford'],
      );
    });

    test('matches a name, a tag word, or a category word', () {
      final provider = providerWith(
        [
          product(id: 'named', name: 'Derby Brogue'),
          product(id: 'tagged', name: 'Plain Pair', tags: ['handmade']),
          product(id: 'categorised', name: 'Plain Pair', category: 'Boots'),
          product(id: 'other', name: 'Plain Pair', category: 'Sports'),
        ],
        {},
      );

      expect(provider.searchResults('brogue').map((p) => p['id']), ['named']);
      expect(
          provider.searchResults('handmade').map((p) => p['id']), ['tagged']);
      expect(
          provider.searchResults('boots').map((p) => p['id']), ['categorised']);
      expect(provider.searchResults('nothing-here'), isEmpty);
    });

    test('a blank query returns nothing rather than the whole catalog', () {
      final provider = providerWith([product(id: 'a')], {});

      expect(provider.searchResults(''), isEmpty);
      expect(provider.searchResults('   '), isEmpty);
    });

    test('the category filter narrows, and null means every category', () {
      final provider = providerWith(
        [
          product(id: 'formal', name: 'Oxford', category: 'Formal'),
          product(id: 'sandals', name: 'Oxford Slide', category: 'Sandals'),
        ],
        {},
      );

      expect(
        provider.searchResults('oxford').map((p) => p['id']).toList(),
        ['formal', 'sandals'],
      );
      expect(
        provider
            .searchResults('oxford', category: 'Sandals')
            .map((p) => p['id'])
            .toList(),
        ['sandals'],
      );
    });

    test('sorts what it returns WITHOUT changing the catalog sort', () {
      final provider = providerWith(
        [
          product(id: 'pricey', name: 'Oxford', price: 3000),
          product(id: 'cheap', name: 'Oxford Slide', price: 1000),
        ],
        {},
      );

      expect(
        provider
            .searchResults('oxford', sort: SortMode.priceLowToHigh)
            .map((p) => p['id'])
            .toList(),
        ['cheap', 'pricey'],
      );
      // The Home feed's order is none of the results page's business.
      expect(provider.sortMode, SortMode.featured);
    });

    test('an explicit limit is honoured, and 0 means no cap', () {
      final provider = providerWith(
        [for (var i = 0; i < 5; i++) product(id: 'p$i', name: 'Oxford $i')],
        {},
      );

      expect(provider.searchResults('oxford', limit: 3).length, 3);
      expect(provider.searchResults('oxford', limit: 0).length, 5);
    });

    test('searchCategories lists only the categories the query found', () {
      final provider = providerWith(
        [
          product(id: 'formal', name: 'Oxford', category: 'Formal'),
          product(id: 'sandals', name: 'Oxford Slide', category: 'Sandals'),
          product(id: 'untouched', name: 'Trail Boot', category: 'Boots'),
        ],
        {},
      );

      expect(provider.searchCategories('oxford'), ['Formal', 'Sandals']);
      // A category nothing matched is not offered as a filter — a chip that
      // can only lead to "0 results" is worse than no chip.
      expect(provider.searchCategories('oxford'), isNot(contains('Boots')));
      // And 'All' is the page's own chip, not one of these.
      expect(provider.searchCategories('oxford'), isNot(contains('All')));
      // Nothing found → nothing to filter by.
      expect(provider.searchCategories(''), isEmpty);
      expect(provider.searchCategories('nothing-here'), isEmpty);
    });

    test('suggestionsFor reads the catalog vocabulary', () {
      final provider = providerWith(
        [product(id: 'a', name: 'Classic Oxford', category: 'Formal')],
        {},
      );

      final terms = provider.suggestionsFor('for').map((s) => s.term).toList();
      expect(terms, contains('Formal'));
      expect(provider.suggestionsFor('').isEmpty, isTrue);
    });

    test('relatedProducts is what a no-match search falls back to', () {
      // It takes no query on purpose: a query that matched nothing has no
      // vocabulary in the catalog to be similar to, so the shop's own best is
      // the honest answer.
      final provider = providerWith(
        [
          product(id: 'low', name: 'Low'),
          product(id: 'high', name: 'High'),
          product(id: 'mid', name: 'Mid'),
        ],
        {'low': 1, 'high': 50, 'mid': 10},
      );

      expect(provider.relatedProducts().map((p) => p['id']).toList(),
          ['high', 'mid', 'low']);
      expect(provider.relatedProducts(limit: 2).length, 2);
    });
  });

  group('productsForAudience — the Men\'s / Women\'s / Kids\' rails', () {
    test('keeps exactly the products stated as that audience', () {
      final provider = providerWith(
        [
          product(id: 'm', audience: 'men'),
          product(id: 'w', audience: 'women'),
          product(id: 'k', audience: 'kids'),
        ],
        {},
      );

      expect(provider.productsForAudience('men').map((p) => p['id']).toList(),
          ['m']);
      expect(
          provider.productsForAudience('women').map((p) => p['id']).toList(),
          ['w']);
      expect(provider.productsForAudience('kids').map((p) => p['id']).toList(),
          ['k']);
    });

    test('unisex appears in NO rail — one card must not fill three strips',
        () {
      final provider = providerWith(
        [product(id: 'any', name: 'House Slipper', audience: 'unisex')],
        {},
      );

      for (final audience in productRailAudiences) {
        expect(provider.productsForAudience(audience), isEmpty,
            reason: 'unisex must stay out of the $audience rail');
      }
      // Asking for it directly is not a rail, and yields nothing either.
      expect(provider.productsForAudience('unisex'), isEmpty);
    });

    test('an unset product is in no rail — but is still in the catalog', () {
      final provider = providerWith(
        [product(id: 'legacy', name: 'Legacy Pair')],
        {},
      );

      for (final audience in productRailAudiences) {
        expect(provider.productsForAudience(audience), isEmpty);
      }

      // The regression this phase must not cause: an unstated audience hides a
      // product from the curated rails ONLY. Search, the catalog grid and
      // category browsing all still see it.
      expect(
        provider.getFilteredProducts('').map((p) => p['id']).toList(),
        ['legacy'],
      );
      expect(
        provider.getFilteredProducts('legacy').map((p) => p['id']).toList(),
        ['legacy'],
      );
    });

    test('an unrecognised or non-rail audience yields an empty rail, never a '
        'default one', () {
      final provider = providerWith(
        [product(id: 'm', audience: 'men')],
        {},
      );

      for (final bad in [null, '', 'Men', 'audience', 'men,women']) {
        expect(provider.productsForAudience(bad), isEmpty,
            reason: '$bad is not a canonical rail audience');
      }
    });

    test('ranks by units sold, then rating, then name', () {
      final provider = providerWith(
        [
          product(id: 'low', name: 'Low', audience: 'men'),
          product(id: 'high', name: 'High', audience: 'men'),
          product(id: 'mid', name: 'Mid', audience: 'men'),
        ],
        {'low': 1, 'high': 50, 'mid': 10},
      );

      expect(provider.productsForAudience('men').map((p) => p['id']).toList(),
          ['high', 'mid', 'low']);
    });

    test('ties break deterministically despite the catalog order', () {
      final lowerRated = product(
          id: 'low', name: 'Aaa', audience: 'men', avgRating: 3.0);
      final higherRated = product(
          id: 'high', name: 'Zzz', audience: 'men', avgRating: 4.9);

      final first = providerWith([lowerRated, higherRated], {})
          .productsForAudience('men')
          .map((p) => p['id'])
          .toList();
      final second = providerWith([higherRated, lowerRated], {})
          .productsForAudience('men')
          .map((p) => p['id'])
          .toList();

      expect(first, ['high', 'low']);
      expect(second, first);
    });

    test('a never-sold product still qualifies — only the best-seller rule '
        'needs sales', () {
      final provider = providerWith(
        [product(id: 'new', name: 'New', audience: 'women')],
        {},
      );

      expect(
          provider.productsForAudience('women').map((p) => p['id']).toList(),
          ['new']);
    });

    test('caps at the rail limit, dropping the least-sold matches', () {
      final provider = providerWith(
        [
          for (var i = 0; i < 20; i++)
            product(id: 'p$i', name: 'P$i', audience: 'kids'),
        ],
        {for (var i = 0; i < 20; i++) 'p$i': i + 1},
      );

      final rail = provider.productsForAudience('kids');

      expect(rail.length, kAudienceRailLimit);
      expect(rail.first['id'], 'p19');
      expect(rail.map((p) => p['id']), isNot(contains('p0')));
    });

    test('an explicit limit is honoured, and 0 means no cap', () {
      final provider = providerWith(
        [
          for (var i = 0; i < 5; i++)
            product(id: 'p$i', audience: 'men'),
        ],
        {for (var i = 0; i < 5; i++) 'p$i': i + 1},
      );

      expect(provider.productsForAudience('men', limit: 3).length, 3);
      expect(provider.productsForAudience('men', limit: 0).length, 5);
    });
  });

  /// The Home category row's audience chips. A chip is only offered when it can
  /// actually show something (same rule as 'On Sale' / 'Best Sellers'), which is
  /// also what made it safe to turn the feature on with an untagged catalog.
  group('audiencesInCatalog — the Home category row\'s chips', () {
    test('offers only the audiences the catalog holds, in vocabulary order', () {
      final provider = providerWith(
        [
          product(id: 'k', audience: 'kids'),
          product(id: 'm', audience: 'men'),
          product(id: 'u', audience: 'unisex'),
        ],
        {},
      );

      // Vocabulary order (men, women, kids, unisex) — not the catalog's order,
      // and `women` is absent because nothing is tagged for it.
      expect(provider.audiencesInCatalog, ['men', 'kids', 'unisex']);
    });

    test('is empty while nothing is tagged — the state of the live catalog', () {
      final provider = providerWith(
        [
          product(id: 'a'),
          product(id: 'b', audience: 'Men'), // not canonical: not an audience
        ],
        {},
      );

      expect(provider.audiencesInCatalog, isEmpty);
    });

    test('offers unisex even though no rail does', () {
      final provider = providerWith(
        [product(id: 'u', name: 'House Slipper', audience: 'unisex')],
        {},
      );

      expect(provider.audiencesInCatalog, [kUnisexAudience]);
      for (final audience in productRailAudiences) {
        expect(provider.productsForAudience(audience), isEmpty,
            reason: 'a unisex product must still stay out of the $audience rail');
      }
    });
  });

  /// The audience listing page's source. Deliberately more permissive than
  /// [productsForAudience]: a customer who tapped the Unisex chip asked for that
  /// shelf, so unisex is included rather than skipped, and an uncapped list is
  /// what a whole-shelf page shows.
  group('productsInAudience — the audience listing page', () {
    test('keeps exactly that audience, including unisex, never the untagged', () {
      final provider = providerWith(
        [
          product(id: 'm', audience: 'men'),
          product(id: 'w', audience: 'women'),
          product(id: 'u', audience: 'unisex'),
          product(id: 'none'),
        ],
        {},
      );

      List<String> ids(String? audience) => provider
          .productsInAudience(audience)
          .map((p) => p['id'].toString())
          .toList();

      expect(ids('men'), ['m']);
      expect(ids('women'), ['w']);
      // The one difference from the rail: the page shows the unisex shelf.
      expect(ids('unisex'), ['u']);
      expect(ids('men'), isNot(contains('none')));
      expect(ids('unisex'), isNot(contains('none')));
    });

    test('an unrecognised audience is empty, never a default shelf', () {
      final provider = providerWith(
        [product(id: 'm', audience: 'men')],
        {},
      );

      for (final bad in [null, '', 'Men', 'men,women', 'shoes']) {
        expect(provider.productsInAudience(bad), isEmpty,
            reason: '$bad is not a canonical audience');
      }
    });

    test('sorts by the page\'s own mode without touching the catalog sort', () {
      final provider = providerWith(
        [
          product(id: 'pricey', name: 'B', price: 3000, audience: 'men'),
          product(id: 'cheap', name: 'A', price: 900, audience: 'men'),
        ],
        {},
      );
      expect(provider.sortMode, SortMode.featured);

      final lowFirst = provider.productsInAudience('men',
          sort: SortMode.priceLowToHigh);
      final highFirst = provider.productsInAudience('men',
          sort: SortMode.priceHighToLow);

      expect(lowFirst.map((p) => p['id'].toString()), ['cheap', 'pricey']);
      expect(highFirst.map((p) => p['id'].toString()), ['pricey', 'cheap']);
      // The pages' sort is local: Home is still on Featured.
      expect(provider.sortMode, SortMode.featured);
    });

    test('is not capped at the rail limit, and an explicit limit still works',
        () {
      final provider = providerWith(
        [
          for (var i = 0; i < 20; i++)
            product(id: 'p$i', name: 'P$i', audience: 'women'),
        ],
        {},
      );

      expect(provider.productsInAudience('women').length, 20);
      expect(provider.productsInAudience('women', limit: 4).length, 4);
      expect(kAudienceRailLimit, lessThan(20));
    });
  });

  /// The seller tabs (Dashboard / POS / Products) share ONE seller-scoped
  /// catalog: the same list is read by the POS grid, the Products grid and the
  /// Dashboard's low-stock count. So the grid's two in-place edits — pruning a
  /// deleted product, and rewriting a product's stock after an Adjust Stock
  /// save — have to land on the shared list instead of a screen-local copy.
  /// These cover the parts that need no network, which is where the logic is:
  /// the write-through, the id coercion, and the no-op case that must not
  /// repaint every listening tab.
  group('shared seller catalog — in-place edits (no refetch)', () {
    test('removeProductLocally drops exactly the deleted product', () {
      final provider = providerWith(
        [product(id: 'a'), product(id: 'b'), product(id: 'c')],
        {},
      );

      provider.removeProductLocally('b');

      expect(provider.products.map((p) => p['id']).toList(), ['a', 'c']);
    });

    test('removeProductLocally matches an id held as a non-string', () {
      // Ids reach the grid as strings (SupabaseService._mapProduct stringifies
      // them), but a caller can still be holding the raw value.
      final provider = providerWith([product(id: '42'), product(id: '43')], {});

      provider.removeProductLocally(42);

      expect(provider.products.map((p) => p['id']).toList(), ['43']);
    });

    test('removing an id that is not in the catalog changes nothing', () {
      final provider = providerWith([product(id: 'a')], {});
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.removeProductLocally('nope');

      expect(provider.products.length, 1);
      expect(notifications, 0,
          reason: 'a no-op must not repaint every tab that reads this list');
    });

    test('applyStockLocally rewrites the raw relation AND the mapped sizes',
        () {
      final provider = providerWith(
        [product(id: 'a', stock: [('EU 42', 3)])],
        {'a': 7},
      );

      provider.applyStockLocally('a', {'EU 41': 0, 'EU 42': 9});

      final updated = provider.products.single;
      // The seller grid's badges/filters read the relation…
      expect(updated['inventory'], [
        {'size': 'EU 41', 'stock': 0},
        {'size': 'EU 42', 'stock': 9},
      ]);
      // …and POS tiles / customer size selectors read the mapped map, so
      // leaving it stale would show sold-out stock as available.
      expect(updated['sizes'], {'EU 41': 0, 'EU 42': 9});
      // Rebuilding the map must not drop the stamped sold count.
      expect(updated['units_sold'], 7);
    });

    test('applyStockLocally is a no-op for an id outside the catalog', () {
      final provider = providerWith([product(id: 'a')], {});
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.applyStockLocally('nope', {'EU 42': 5});

      expect(provider.products.single.containsKey('sizes'), isFalse);
      expect(notifications, 0);
    });

    test('a fresh seller catalog reports no error', () {
      expect(providerWith([product(id: 'a')], {}).sellerCatalogError, isNull);
    });
  });
}
