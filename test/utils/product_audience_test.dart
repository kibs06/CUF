import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/cart_helpers.dart';
import 'package:app/utils/customer_profile_fields.dart';
import 'package:app/utils/product_audience.dart';
import 'package:app/utils/size_key.dart';

/// The product-audience vocabulary — the one place that decides what a stored
/// `products.audience` value means.
///
/// Three guarantees are pinned here, and they are the whole point of Phase 0:
///
///  1. the four values and their labels are exactly as specified, and survive a
///     label → value → label round trip;
///  2. a malformed, mis-cased, whitespace-padded or unknown value resolves to
///     **null** — never to a guessed audience, because a guessed one would put
///     a product in a section nobody chose for it;
///  3. the rail-eligible list is exactly the three shopper scales and does NOT
///     contain `unisex` (a unisex product in all three rails would appear three
///     times down the feed).
void main() {
  group('the four canonical values', () {
    test('are exactly men / women / kids / unisex, with their labels', () {
      expect(productAudienceOptions, const [
        ('men', "Men's"),
        ('women', "Women's"),
        ('kids', "Kids'"),
        ('unisex', 'Unisex'),
      ]);
    });

    test('round-trip through productAudienceFrom and back', () {
      for (final (value, label) in productAudienceOptions) {
        expect(productAudienceFrom(value), value);
        expect(productAudienceLabel(productAudienceFrom(value)), label);
      }
    });

    test('the shared three reuse the shopper vocabulary verbatim', () {
      // Not a second spelling of the same words: the first three ARE
      // customerFootSizeCategories, so `'women'` cannot mean one thing on a
      // profile and another on a product.
      expect(
        productAudienceOptions.take(3).toList(),
        customerFootSizeCategories,
      );
      expect(productAudienceOptions.map((o) => o.$1), contains(kUnisexAudience));
    });

    test('productAudienceLabel is null for null and for anything unknown', () {
      expect(productAudienceLabel(null), isNull);
      expect(productAudienceLabel(''), isNull);
      expect(productAudienceLabel('Men'), isNull);
      expect(productAudienceLabel('unisex'), 'Unisex');
    });
  });

  group('productAudienceFrom never guesses', () {
    test('null and empty resolve to null', () {
      expect(productAudienceFrom(null), isNull);
      expect(productAudienceFrom(''), isNull);
      expect(productAudienceFrom('   '), isNull);
    });

    test('wrong case resolves to null (the column CHECK is exact too)', () {
      expect(productAudienceFrom('Men'), isNull);
      expect(productAudienceFrom('MEN'), isNull);
      expect(productAudienceFrom("Men's"), isNull);
      expect(productAudienceFrom('WOMEN'), isNull);
    });

    test('surrounding whitespace resolves to null, not to the trimmed value',
        () {
      // The stored value comes from a closed chip list and a CHECK constraint
      // that compare exactly, so 'unisex ' is not one of our values — trimming
      // it here would invent a meaning the database does not hold.
      expect(productAudienceFrom('unisex '), isNull);
      expect(productAudienceFrom(' unisex'), isNull);
      expect(productAudienceFrom('kids\t'), isNull);
    });

    test('garbage resolves to null', () {
      expect(productAudienceFrom('xyz123'), isNull);
      expect(productAudienceFrom('unisex-maybe'), isNull);
      expect(productAudienceFrom('both'), isNull);
      expect(productAudienceFrom('null'), isNull);
    });

    test('the shopper-side identity vocabulary is not an audience', () {
      // `profiles.gender` answers a different question and its values are not
      // audiences.
      expect(productAudienceFrom('Woman'), isNull);
      expect(productAudienceFrom('Man'), isNull);
      expect(productAudienceFrom('Prefer not to say'), isNull);
      expect(productAudienceFrom('Self-describe'), isNull);
    });
  });

  group('productRailAudiences — the rails, and what is not a rail', () {
    test('is exactly men, women, kids', () {
      expect(productRailAudiences, ['men', 'women', 'kids']);
    });

    test('does NOT contain unisex', () {
      // This is the assertion that must fail if someone later adds kUnisexAudience
      // to the rail list — a unisex product would otherwise be listed in all
      // three rails.
      expect(productRailAudiences, isNot(contains(kUnisexAudience)));
      expect(productRailAudiences.length, 3);
    });

    test('matches the shopper-side scales — one vocabulary, both directions',
        () {
      // Guards drift both ways: a fourth shopper scale (or a removed one) must
      // force a decision here rather than silently changing what the rails show.
      expect(
        productRailAudiences,
        customerFootSizeCategories.map((c) => c.$1).toList(),
      );
    });

    test('every rail audience has a label to render, and is a valid value', () {
      for (final audience in productRailAudiences) {
        expect(productAudienceFrom(audience), audience);
        expect(productAudienceLabel(audience), isNotNull);
      }
    });
  });

  group('audienceSizeMismatch — the Kids\' band check', () {
    /// The exact case the seller form warns about: a product marked Kids' whose
    /// stocked sizes are all adult sizes.
    test('is true for a kids product stocked only in adult sizes', () {
      expect(
        audienceSizeMismatch(
          audience: 'kids',
          sizes: const ['EU 40', 'EU 42', 'EU 44'],
        ),
        isTrue,
      );
    });

    test('is false as soon as one size is a real kids size', () {
      // The band is not a majority vote: one believable size is enough to
      // confirm the seller's answer, and mixed catalogs are legitimate.
      expect(
        audienceSizeMismatch(audience: 'kids', sizes: const ['EU 28']),
        isFalse,
      );
      expect(
        audienceSizeMismatch(audience: 'kids', sizes: const ['EU 42', 'EU 28']),
        isFalse,
      );
    });

    test('the band boundary is 22–35, the picker\'s own kids band', () {
      expect(
        audienceSizeMismatch(
          audience: 'kids',
          sizes: [customerKidsEuSizes.first, customerKidsEuSizes.last],
        ),
        isFalse,
      );
      // EU 36 is the first size the chart hands to the women's/men's bands.
      expect(
        audienceSizeMismatch(audience: 'kids', sizes: const ['EU 36']),
        isTrue,
      );
    });

    test('sizes are read in EU, through the shared parser', () {
      // A bare number defaults to EU and a US size converts, both via
      // `sizeNumberInEu` — the same parser the rest of the app uses, so this
      // check can never disagree with the catalog.
      expect(
        audienceSizeMismatch(audience: 'kids', sizes: const ['28']),
        isFalse,
      );
      expect(
        audienceSizeMismatch(audience: 'kids', sizes: const ['US 9']),
        isTrue,
      );
    });

    test('claims nothing when it cannot read a size, or has none', () {
      expect(audienceSizeMismatch(audience: 'kids', sizes: const []), isFalse);
      expect(
        audienceSizeMismatch(
          audience: 'kids',
          sizes: const ['EU 42', 'Other'],
        ),
        isFalse,
      );
      expect(
        audienceSizeMismatch(audience: 'kids', sizes: const ['']),
        isFalse,
      );
    });

    test('only Kids\' is checkable — adult and unset audiences never warn', () {
      // Men's and Women's share the ENTIRE adult band (EU is unisex), and
      // unisex/not-set claim no band at all, so there is nothing a size could
      // contradict. Adult sizes are the correct sizes for all of them.
      for (final audience in <String?>['men', 'women', 'unisex', null]) {
        expect(
          audienceSizeMismatch(
            audience: audience,
            sizes: const ['EU 42', 'EU 43'],
          ),
          isFalse,
          reason: 'audience $audience must not be size-checked',
        );
      }
    });
  });

  /// Phase 3: which chart a product's US/UK labels are drawn on.
  ///
  /// The three cases below are the ones the plan names, and the third is the
  /// regression risk: every product in the catalog is currently unset, so the
  /// fallback branch is the one the whole catalog takes. It is asserted against
  /// `savedFootSizeCategory` itself — the function the product page passed
  /// before this helper existed — rather than against a restated expectation.
  group('productSizeChart — which chart a product is sold on', () {
    Map<String, dynamic> product(String? audience) => {
      'id': 'p',
      'name': 'Artisan Shoe',
      'audience': ?audience,
    };

    /// The label the product page would render, through the real pipeline.
    String? labelFor(Map<String, dynamic>? p, Map<String, dynamic>? profile) {
      final chart = productSizeChart(
        product: p,
        profile: profile,
        audienceEnabled: true,
      );
      if (!sizeUnitsForCategory(chart).contains('US')) return null;
      return displaySizeInUnit('EU 42', 'US', category: chart);
    }

    test('a men\'s product reads US 9 for EU 42 for EVERY shopper', () {
      final men = product('men');
      // Including a shopper whose own saved scale is women's — the product's
      // chart wins, because the item is sold on the men's chart. This is the
      // behaviour change of the phase.
      for (final profile in <Map<String, dynamic>?>[
        null,
        const {},
        const {'foot_size_category': 'women'},
        const {'foot_size_category': 'men'},
        const {'foot_size_category': 'kids'},
      ]) {
        expect(labelFor(men, profile), 'US 9',
            reason: 'profile $profile must not change a men\'s label');
      }
    });

    test('a women\'s product reads US 10.5 for EU 42 for every shopper', () {
      final women = product('women');
      for (final profile in <Map<String, dynamic>?>[
        null,
        const {'foot_size_category': 'men'},
      ]) {
        expect(labelFor(women, profile), 'US 10.5');
      }
    });

    test('a kids\' product offers EU only — no US/UK chart exists', () {
      final kids = product('kids');
      for (final profile in <Map<String, dynamic>?>[
        null,
        const {'foot_size_category': 'men'},
        const {'foot_size_category': 'women'},
      ]) {
        final chart = productSizeChart(
          product: kids,
          profile: profile,
          audienceEnabled: true,
        );
        expect(chart, 'kids');
        // The existing "EU only" convention, not a new representation.
        expect(sizeUnitsForCategory(chart), const ['EU']);
        expect(labelFor(kids, profile), isNull,
            reason: 'no US label may be offered for a kids\' product');
      }
    });

    test('an unset product falls back to today\'s exact value — the whole '
        'catalog', () {
      final unset = product(null);
      for (final profile in <Map<String, dynamic>?>[
        null,
        const {},
        const {'foot_size_category': 'men'},
        const {'foot_size_category': 'women'},
        const {'foot_size_category': 'kids'},
        const {'foot_size_category': 'unisex'},
      ]) {
        expect(
          productSizeChart(
            product: unset,
            profile: profile,
            audienceEnabled: true,
          ),
          // The value the product page passed before this helper existed,
          // null included — null is what makes the label fall back to men's
          // downstream instead of to a guessed women's chart.
          savedFootSizeCategory(profile),
          reason: 'profile $profile must resolve exactly as it did before',
        );
      }
      // ...and therefore the same labels, for a shopper who picked nothing
      // (men's fallback) and for a woman (women's chart).
      expect(labelFor(unset, const {'foot_size_category': 'women'}), 'US 10.5');
      expect(labelFor(unset, const {}), 'US 9');
      expect(labelFor(unset, null), 'US 9');
    });

    test('unisex resolves to the men\'s chart — the app\'s no-knowledge '
        'default', () {
      expect(
        productSizeChart(
          product: product('unisex'),
          profile: const {'foot_size_category': 'women'},
          audienceEnabled: true,
        ),
        kDefaultSizeCategory,
      );
      expect(labelFor(product('unisex'), const {'foot_size_category': 'women'}),
          'US 9');
    });

    test('an unrecognised audience is treated as unset, never guessed', () {
      for (final raw in <String?>['Men', '', 'kids ', 'xyz123']) {
        expect(
          productSizeChart(
            product: {'audience': raw},
            profile: const {'foot_size_category': 'women'},
            audienceEnabled: true,
          ),
          'women',
          reason: '$raw is not canonical, so the shopper\'s scale stands',
        );
      }
      // A product map with no `audience` key at all is the same case.
      expect(
        productSizeChart(
          product: const {'id': 'p'},
          profile: const {'foot_size_category': 'women'},
          audienceEnabled: true,
        ),
        'women',
      );
    });

    test('with the feature switch off, the audience is never consulted', () {
      for (final audience in <String?>['men', 'women', 'kids', 'unisex', null]) {
        for (final profile in <Map<String, dynamic>?>[
          null,
          const {'foot_size_category': 'women'},
        ]) {
          expect(
            productSizeChart(
              product: product(audience),
              profile: profile,
              audienceEnabled: false,
            ),
            savedFootSizeCategory(profile),
            reason: 'switch off: $audience / $profile keeps the old chart',
          );
        }
      }
    });
  });
}
