import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/product_search.dart';

/// The customer search rule — what a query matches, and what to suggest.
///
/// The rule that matters most here is the one that caused a real dead end:
/// searching **"Formal Shoes"** returned nothing, because `Formal` is a
/// *category* — the catalog's own word for those products — and no product is
/// named that or tagged with it. A search that cannot use the catalog's own
/// vocabulary is a search that tells a customer their own catalog does not
/// exist.
Map<String, dynamic> p({
  required String name,
  String? category,
  List<String> tags = const [],
}) =>
    {
      'id': name,
      'name': name,
      'category': ?category,
      'tags': tags,
    };

void main() {
  group('searchWords', () {
    test('splits on whitespace, lowercases, drops empties', () {
      expect(searchWords('  Formal   SHOES '), ['formal', 'shoes']);
      expect(searchWords('loafers'), ['loafers']);
      expect(searchWords('   '), isEmpty);
      expect(searchWords(''), isEmpty);
    });
  });

  group('matchesSearchQuery — what a query finds', () {
    test('a whole-phrase name match', () {
      expect(
        matchesSearchQuery(p(name: 'Formal Derby'), 'formal derby'),
        isTrue,
      );
    });

    test('any word of the query in the name', () {
      // The customer typing more words is narrowing in their head, not asking
      // for a conjunction — so this is an OR, not an AND.
      expect(
        matchesSearchQuery(p(name: 'Formal Leather Derby'), 'leather derby'),
        isTrue,
      );
    });

    test('the CATEGORY — the search that used to find nothing', () {
      final catalog = [
        p(name: 'Classic Oxford', category: 'Formal'),
        p(name: 'Beach Slide', category: 'Sandals'),
      ];

      final hits = catalog
          .where((product) => matchesSearchQuery(product, 'Formal Shoes'))
          .toList();

      expect(hits.map((h) => h['name']), ['Classic Oxford']);
    });

    test('a tag word', () {
      expect(
        matchesSearchQuery(
          p(name: 'Classic Oxford', tags: const ['handmade', 'leather']),
          'handmade loafers',
        ),
        isTrue,
      );
    });

    test('is case-insensitive on both sides', () {
      expect(
        matchesSearchQuery(
          p(name: 'Classic Oxford', category: 'Formal'),
          'FORMAL',
        ),
        isTrue,
      );
      expect(matchesSearchQuery(p(name: 'Classic Oxford'), 'OXFORD'), isTrue);
    });

    test('a word the catalog has never heard of does not match', () {
      final catalog = [
        p(name: 'Classic Oxford', category: 'Formal', tags: const ['leather']),
      ];
      for (final query in ['runway pumps 3000', 'xyz123', 'sneaker']) {
        expect(catalog.any((product) => matchesSearchQuery(product, query)),
            isFalse,
            reason: '"$query" must not match anything in this catalog');
      }
    });

    test('a blank query matches NOTHING, not everything', () {
      // "No query" is not a search. A caller that wants the whole catalog
      // should ask for the catalog.
      for (final query in ['', '   ', '\n']) {
        expect(matchesSearchQuery(p(name: 'Classic Oxford'), query), isFalse);
      }
    });

    test('odd rows do not throw and simply do not match', () {
      expect(matchesSearchQuery(const {}, 'formal'), isFalse);
      expect(
        matchesSearchQuery(const {'name': 'Oxford', 'tags': 'not-a-list'},
            'handmade'),
        isFalse,
      );
      expect(
        matchesSearchQuery(const {'name': 'Oxford', 'category': null}, 'oxford'),
        isTrue,
      );
    });
  });

  group('searchSuggestionsFor — the panel under the bar', () {
    final catalog = [
      p(name: 'Classic Oxford', category: 'Formal', tags: const ['leather']),
      p(name: 'Derby Brogue', category: 'Formal', tags: const ['leather']),
      p(name: 'Hiking Boot', category: 'Boots', tags: const ['outdoor']),
      p(name: 'School Shoes', category: 'Sneakers'),
      p(name: 'Recycled Runner', category: 'Sports', tags: const ['eco']),
    ];

    test('suggests the catalog words that would actually return something', () {
      // A partially typed category, and a partially typed product name.
      expect(
        searchSuggestionsFor(catalog, query: 'form').map((s) => s.term),
        contains('Formal'),
      );
      expect(
        searchSuggestionsFor(catalog, query: 'oxford').map((s) => s.term),
        contains('Classic Oxford'),
      );
    });

    test('a word-prefix match outranks a mid-word one', () {
      final terms = searchSuggestionsFor(
        [
          // 'boo' starts the word "Boots" ...
          p(name: 'Trail Boot', category: 'Boots'),
          // ...but only appears inside "bamboo".
          p(name: 'Classic Oxford', tags: const ['bamboo']),
        ],
        query: 'boo',
      ).map((s) => s.term).toList();

      expect(terms.first, 'Boots');
      expect(terms, contains('bamboo'));
    });

    test('a term backed by more products outranks a one-off', () {
      final terms = searchSuggestionsFor(
        [
          p(name: 'A', category: 'Leather Goods'),
          p(name: 'B', category: 'Leather Goods'),
          p(name: 'C', tags: const ['leatherette']),
        ],
        query: 'leat',
      ).map((s) => s.term).toList();

      expect(terms.first, 'Leather Goods');
    });

    test('carries the kind, so the panel can label a row', () {
      final byTerm = {
        for (final s in searchSuggestionsFor(
          [p(name: 'Hiking Boot', category: 'Boots', tags: const ['outdoor'])],
          query: 'boot',
        ))
          s.term: s.kind,
      };

      expect(byTerm['Boots'], SearchSuggestionKind.category);
      expect(byTerm['Hiking Boot'], SearchSuggestionKind.product);
    });

    test('a tag is suggested as a tag', () {
      final byTerm = {
        for (final s in searchSuggestionsFor(catalog, query: 'leath'))
          s.term: s.kind,
      };

      expect(byTerm['leather'], SearchSuggestionKind.tag);
    });

    test('never suggests what the customer already typed', () {
      final terms = searchSuggestionsFor(catalog, query: 'Formal')
          .map((s) => s.term.toLowerCase())
          .toList();

      expect(terms, isNot(contains('formal')));
    });

    test('a blank query yields no suggestions (the panel shows recent terms)', () {
      expect(searchSuggestionsFor(catalog, query: ''), isEmpty);
      expect(searchSuggestionsFor(catalog, query: '   '), isEmpty);
    });

    test('honours the limit, and never exceeds the catalog vocabulary', () {
      final limited = searchSuggestionsFor(catalog, query: 'e', limit: 2);
      expect(limited.length, 2);

      final all = searchSuggestionsFor(catalog, query: 'zzz');
      expect(all, isEmpty);
    });

    test('is deterministic — same input, same order', () {
      List<String> once() =>
          searchSuggestionsFor(catalog, query: 'le').map((s) => s.term).toList();

      expect(once(), once());
    });
  });
}
