import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/seller/manage_products_screen.dart';
import 'package:app/utils/product_audience.dart';

/// The seller-facing half of the backfill picture: the products whose "Who is it
/// for?" is still unset, and the nudge that says how many.
///
/// Two things are pinned here.
///
/// **The rule itself.** `missingAudience` is the only place that decides what
/// counts as missing, and it must agree with the parser the customer-facing
/// rails use — otherwise a seller gets nagged about a product the catalog is
/// perfectly happy with, or worse, is not nagged about one no rail will ever
/// show. `unisex` is the case worth staring at: it is *stated*, so it is not
/// missing, even though the rails deliberately skip it.
///
/// **The wiring.** The banner's number and the filter it links to must be the
/// same rule. If one of them ever grows its own `audience == null` check they
/// drift silently — the banner says "12 products", tapping it shows 9 — so this
/// is asserted against the screen's source. The screen itself cannot be built in
/// a widget test (`Supabase.instance` is not initialized in the test
/// environment), which is why the codebase already reaches for source-level
/// contract tests on this particular file.
///
/// Nothing here (or anywhere in the app) infers an audience from size: see
/// `docs/AI/PRODUCT_AUDIENCE_PLAN.md` §1.1 for why the stocked sizes cannot
/// answer this question.
Map<String, dynamic> product({Object? audience, bool includeKey = true}) => {
      'id': 'p',
      'name': 'Artisan Shoe',
      if (includeKey) 'audience': audience,
    };

String get _source => File('lib/screens/seller/manage_products_screen.dart')
    .readAsStringSync();

/// The text from [start] up to [end] — used to assert *where* a rule is applied
/// rather than merely that the file mentions it somewhere.
String _slice(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNot(-1), reason: 'marker "$start" not found — was the code '
      'moved or the structure renamed? If so, update this test to match rather '
      'than deleting the assertion.');
  final to = source.indexOf(end, from + start.length);
  return source.substring(from, to == -1 ? source.length : to);
}

void main() {
  group('missingAudience — the one rule behind the count and the filter', () {
    test('every value the vocabulary knows is a stated answer', () {
      for (final (value, label) in productAudienceOptions) {
        expect(missingAudience(product(audience: value)), isFalse,
            reason: '"$label" is an answer a seller gave — nagging them about '
                'it is how a nudge turns into noise');
      }
    });

    test('unisex is stated, even though no rail lists it', () {
      // Deliberately NOT a bug: `unisex` is excluded from the Men's/Women's/
      // Kids' rails (one house slipper would appear in all three), but it is a
      // real answer to "Who is it for?" — so it is not missing, and the seller
      // must not be prompted to change it.
      expect(missingAudience(product(audience: kUnisexAudience)), isFalse);
      expect(productAudienceFrom(kUnisexAudience), kUnisexAudience);
    });

    test('null, absent, empty and unrecognised all count as missing', () {
      for (final raw in <Object?>[null, '', 'Men', 'MEN', 'men ', ' men',
        'men,women', 'unisex ', 'shoes', 0]) {
        expect(missingAudience(product(audience: raw)), isTrue,
            reason: '${raw == null ? 'null' : '"$raw"'} is not a value the '
                'column can hold');
      }
      // A legacy row shape with no key at all.
      expect(missingAudience(product(includeKey: false)), isTrue);
    });

    test('counting a catalog matches the parser the rails use', () {
      final catalog = [
        product(audience: 'men'),
        product(audience: kUnisexAudience),
        product(audience: 'kids'),
        product(includeKey: false),
        product(audience: 'Women'),
      ];

      expect(catalog.where(missingAudience).length, 2);
      // Same parser, so the two can never disagree about what a value means:
      // a product is missing here exactly when the parser rejects its value.
      for (final p in catalog) {
        expect(
          missingAudience(p),
          productAudienceFrom(p['audience']?.toString()) == null,
        );
      }
    });

    test('a catalog that is entirely unset counts every product', () {
      // Today's live catalog: 15 of 15 unset, across 3 stores.
      final catalog = [for (var i = 0; i < 15; i++) product()];
      expect(catalog.where(missingAudience).length, 15);
    });
  });

  group('the nudge cannot advertise a number the filter will not show', () {
    test('the filter case and the count use missingAudience, not their own rule',
        () {
      final filter = _slice(_source, 'get _filteredProducts', 'int _countFor');
      expect(filter, contains('missingAudience'),
          reason: "the 'Not Set' filter must select exactly what the rule "
              'selects');

      final count = _slice(_source, 'int _countFor(String filter)',
          '// ─── ACTIONS');
      expect(count, contains('missingAudience'),
          reason: 'the chip count and the banner count must be the same '
              'arithmetic as the filter');
      // The same constants, so a rename cannot leave one site behind.
      expect(filter, contains('_noAudienceFilter'));
      expect(count, contains('_noAudienceFilter'));
    });

    test('the alert exists, uses that filter, and speaks the seller\'s language',
        () {
      final alerts = _slice(
          _source, 'List<_AlertData> _buildAlerts()', 'Widget _buildAlertBanner');

      expect(alerts, contains('missingAudience'));
      expect(alerts, contains('filter: _noAudienceFilter'),
          reason: 'tapping the nudge must land on the filtered list');
      // "Who is it for?" is what the seller form calls the field; 'audience' is
      // our word for the column, not theirs, so the label quotes the form.
      expect(alerts, contains('missing "Who is it for?"'));
      expect(alerts, isNot(contains('no audience')));

      // Only offered when there is something to fix — the pattern every other
      // alert on this screen follows.
      expect(alerts, contains('if (noAudience > 0)'));
    });

    test('the filter chip is in the bar, so the list stays reachable', () {
      final bar = _slice(_source, 'Widget _buildFilterBar', 'Widget _buildShimmer');
      expect(bar, contains('_noAudienceFilter'),
          reason: 'the banner rotates away after a few seconds; the chip is '
              'what keeps the unset products findable');
    });

    test('every read of the column goes through the shared parser', () {
      // The plan's hard "do not": the kids' band runs to EU 35 and an adult
      // style can sit at EU 39, so any size-based guess is a guess. The property
      // that keeps this file honest is not "reads the column once" — it reads it
      // twice, once in the predicate and once on the card's metadata line, both
      // of which are display — but that **every** read is parsed by the shared
      // vocabulary. A raw comparison is how an unrecognised value, or a
      // heuristic of some future shape, gets treated as a stated answer.
      final code = _source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      final reads = RegExp(r"\['audience'\]").allMatches(code).length;
      // Every read is wrapped in the parser itself. Comparing raw values (`p
      // ['audience'] == ...`) is what this forbids.
      final parsed =
          RegExp(r"productAudienceFrom\(\s*product\['audience'\]")
              .allMatches(code)
              .length;

      expect(reads, greaterThan(0), reason: 'the rule lives in this file');
      expect(parsed, reads,
          reason: 'every read of the column must be parsed by the shared '
              'vocabulary, not compared raw');
      expect(code, isNot(contains("['audience'] =")));
    });
  });
}
