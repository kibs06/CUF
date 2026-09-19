import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/providers/product_provider.dart';
import 'package:app/screens/admin/monitor_products_screen.dart';
import 'package:app/screens/seller/manage_products_screen.dart' show missingAudience;
import 'package:app/utils/cart_helpers.dart';
import 'package:app/utils/customer_profile_fields.dart';
import 'package:app/utils/product_audience.dart';
import 'package:app/utils/size_key.dart';
import 'package:app/widgets/audience_section.dart';
import 'package:app/widgets/horizontal_product_card.dart';

/// **P5's combined regression pass** — the whole audience feature checked as one
/// system, over ONE catalog, rather than phase by phase.
///
/// Each phase had its own gate, and each gate proved its own slice. What no
/// phase could prove alone is that the slices agree: that the product the rails
/// show is the product whose label is read on that audience's chart, that the
/// products the rails *omit* are exactly the ones still sitting in the catalog
/// grid, and that the seller is being asked to fix precisely the set nobody can
/// answer for. This file is that cross-check, so a change that is right in each
/// phase and wrong in combination fails here.
///
/// The catalog is the shape a real one has after a seller starts tagging: one
/// product per audience value, plus two legacy rows that were never answered.
Map<String, dynamic> product({
  required String id,
  required String name,
  String category = 'Sneakers',
  String? audience,
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'price': 1000,
      'images': <String>[],
      // Omitted when unset — the shape a NULL `audience` row arrives in.
      'audience': ?audience,
    };

final _catalog = <Map<String, dynamic>>[
  product(id: 'm', name: 'Derby', category: 'Formal', audience: 'men'),
  product(id: 'w', name: 'Ballet Flat', category: 'Casual', audience: 'women'),
  product(id: 'k', name: 'School Shoe', category: 'Kids', audience: 'kids'),
  product(id: 'u', name: 'House Slipper', category: 'Casual', audience: 'unisex'),
  product(id: 'x1', name: 'Legacy Loafer', category: 'Formal'),
  product(id: 'x2', name: 'Legacy Slide', category: 'Sandals'),
];

/// The shopper used throughout: her OWN scale is women's, which is the whole
/// point of the label checks — the product's audience has to beat it.
const _shopper = <String, dynamic>{'foot_size_category': 'women'};

Map<String, dynamic> byId(String id) =>
    _catalog.firstWhere((p) => p['id'] == id);

Finder railOf(String audience) => find.byWidgetPredicate(
      (w) => w is AudienceSection && w.audience == audience,
    );

List<String> namesInRail(WidgetTester tester, String audience) => tester
    .widgetList<HorizontalProductCard>(
      find.descendant(
          of: railOf(audience), matching: find.byType(HorizontalProductCard)),
    )
    .map((c) => c.product['name'].toString())
    .toList();

void main() {
  group('rails + catalog grid, over one catalog', () {
    testWidgets('each rail shows its own audience, and the grid keeps '
        'everything — including what the rails skip', (tester) async {
      final provider =
          ProductProvider.seeded(products: _catalog, unitsSold: const {});

      await tester.pumpWidget(
        ChangeNotifierProvider<ProductProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    // The three rails in their shipped order.
                    for (final audience in productRailAudiences)
                      AudienceSection(audience: audience, enabled: true),
                    // Then what the customer scrolls into: the catalog grid, as
                    // the home screen renders it.
                    for (final p in provider.getFilteredProducts(''))
                      Text('GRID:${p['name']}'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(namesInRail(tester, 'men'), ['Derby']);
      expect(namesInRail(tester, 'women'), ['Ballet Flat']);
      expect(namesInRail(tester, 'kids'), ['School Shoe']);

      // Unisex is an answer the rails skip by design, and the unset rows were
      // never answered at all. Neither belongs in a rail...
      for (final audience in productRailAudiences) {
        final names = namesInRail(tester, audience);
        expect(names, isNot(contains('House Slipper')),
            reason: 'unisex would appear in all three rails at once');
        expect(names, isNot(contains('Legacy Loafer')));
        expect(names, isNot(contains('Legacy Slide')));
      }

      // ...and both are still exactly where they always were.
      expect(find.text('GRID:House Slipper'), findsOneWidget);
      expect(find.text('GRID:Legacy Loafer'), findsOneWidget);
      expect(find.text('GRID:Legacy Slide'), findsOneWidget);
      expect(find.text('GRID:Derby'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('the rails partition the stated, non-unisex products exactly once', () {
      // A product in two rails reads as a bug in the feed, and a stated product
      // in no rail is a product nobody can find by audience. This is the one
      // assertion that catches both.
      final provider =
          ProductProvider.seeded(products: _catalog, unitsSold: const {});

      final railed = [
        for (final audience in productRailAudiences)
          ...provider.productsForAudience(audience).map((p) => p['id']),
      ];
      final expected = _catalog
          .where((p) =>
              productAudienceFrom(p['audience']?.toString()) != null &&
              productAudienceFrom(p['audience']?.toString()) !=
                  kUnisexAudience)
          .map((p) => p['id'])
          .toSet();

      expect(railed.length, railed.toSet().length,
          reason: 'a product appeared in more than one rail');
      expect(railed.toSet(), expected);
    });
  });

  group('size labels, for a shopper whose own scale is women', () {
    /// The label the product page renders for EU 42, through the real pipeline:
    /// `productSizeChart` → the units that chart offers → `displaySizeInUnit`.
    String? usLabelFor(String id) {
      final chart = productSizeChart(
        product: byId(id),
        profile: _shopper,
        audienceEnabled: true,
      );
      if (!sizeUnitsForCategory(chart).contains('US')) return null;
      return displaySizeInUnit('EU 42', 'US', category: chart);
    }

    test('a stated audience beats the shopper\'s own scale', () {
      // She is a women's shopper, and the men's product is still read on the
      // men's chart — the item is sold that way.
      expect(usLabelFor('m'), 'US 9');
      // Her own scale, for the product actually sold on it.
      expect(usLabelFor('w'), 'US 10.5');
      // Unisex resolves to men's, the app's existing "nothing known" default.
      expect(usLabelFor('u'), 'US 9');
    });

    test('a kids\' product offers EU only — no US/UK conversion at all', () {
      expect(usLabelFor('k'), isNull);

      final chart = productSizeChart(
        product: byId('k'),
        profile: _shopper,
        audienceEnabled: true,
      );
      expect(sizeUnitsForCategory(chart), const ['EU']);
    });

    test('an unset product is byte-for-byte what it was before any of this',
        () {
      // The regression that has to survive the combination: every legacy row
      // takes the fallback branch, so a drift here would relabel the whole
      // un-backfilled catalog. Asserted against `savedFootSizeCategory` itself,
      // not against a restated expectation.
      for (final id in const ['x1', 'x2']) {
        expect(
          productSizeChart(
              product: byId(id), profile: _shopper, audienceEnabled: true),
          savedFootSizeCategory(_shopper),
        );
        // And identical to the value the switch being OFF produces — i.e. the
        // feature contributes nothing to an unset product either way.
        expect(
          productSizeChart(
              product: byId(id), profile: _shopper, audienceEnabled: true),
          productSizeChart(
              product: byId(id), profile: _shopper, audienceEnabled: false),
        );
      }
    });
  });

  group('the people-facing surfaces, over the same catalog', () {
    test('the seller is asked about exactly the rows nobody answered', () {
      final missing = _catalog.where(missingAudience).toList();

      expect(missing.map((p) => p['id']), ['x1', 'x2']);
      // The interesting half: `unisex` is NOT in that list, even though the
      // rails skip it. Two different questions — "has anyone answered?" versus
      // "can it be sold on one chart?" — and a nudge that conflated them would
      // tell a seller to change an answer they already gave.
      expect(missing.map((p) => p['id']), isNot(contains('u')));
      // Everything the seller is asked about is a product no rail can use.
      for (final p in missing) {
        expect(productAudienceFrom(p['audience']?.toString()), isNull);
      }
    });

    testWidgets('an admin sees every product\'s audience state', (tester) async {
      // A console tall enough for the whole catalog: its list is a lazy
      // `ListView.builder`, so on a short surface the rows below the fold are
      // never built and "the admin can see it" would be asserted only for the
      // first two products.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final provider =
          ProductProvider.seeded(products: _catalog, unitsSold: const {});

      await tester.pumpWidget(
        ChangeNotifierProvider<ProductProvider>.value(
          value: provider,
          child: const MaterialApp(home: MonitorProductsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      for (final (_, label) in productAudienceOptions) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text(kAudienceUnsetLabel), findsNWidgets(2),
          reason: 'the two legacy rows are the backlog an admin is looking for');
      expect(tester.takeException(), isNull);
    });
  });
}
