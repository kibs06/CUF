import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/utils/product_audience.dart';
import 'package:app/widgets/audience_section.dart';
import 'package:app/widgets/horizontal_product_card.dart';
import 'package:app/widgets/product_rail_section.dart';

/// The Men's / Women's / Kids' home rails — the first customer-facing surface
/// of the product-audience feature.
///
/// The rules pinned here are the ones that would be silent if they broke:
/// per-rail isolation, `unisex` in NO rail (the same card three times down the
/// feed), and an unset product staying in the catalog grid while staying out of
/// the rails. The kill switch is now ON in production, but the OFF case is still
/// pinned here by passing `enabled: false` deliberately — see
/// [AudienceSection.enabled].
Map<String, dynamic> product({
  required String id,
  required String name,
  String? audience,
}) {
  return {
    'id': id,
    'name': name,
    'category': 'Sneakers',
    'price': 1000,
    'images': <String>[],
    // Omitted when unset — the shape a NULL `audience` row arrives in.
    'audience': ?audience,
    'inventory': [
      {'size': 'EU 42', 'stock': 3},
    ],
  };
}

/// The three rails in their fixed home-feed order, optionally followed by the
/// catalog grid's rows (a plain text stand-in for `SoleProductCard`, so the
/// assertion is about *which feed the product is in* rather than about card
/// rendering).
Widget wrap(
  ProductProvider provider, {
  List<String> audiences = productRailAudiences,
  bool showCatalog = false,
  bool enabled = true,
  double textScale = 1.0,
}) {
  return ChangeNotifierProvider<ProductProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final audience in audiences)
                    AudienceSection(audience: audience, enabled: enabled),
                  if (showCatalog)
                    for (final p in provider.getFilteredProducts(''))
                      Text(p['name'].toString()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder railOf(String audience) => find.byWidgetPredicate(
      (w) => w is AudienceSection && w.audience == audience,
    );

/// Product names rendered by one rail, in DOM order.
List<String> namesInRail(WidgetTester tester, String audience) => tester
    .widgetList<HorizontalProductCard>(
      find.descendant(of: railOf(audience), matching: find.byType(HorizontalProductCard)),
    )
    .map((c) => c.product['name'].toString())
    .toList();

void main() {
  testWidgets('each rail shows only its own audience', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Men's"), findsOneWidget);
    expect(find.text("Women's"), findsOneWidget);
    expect(find.text("Kids'"), findsOneWidget);

    expect(namesInRail(tester, 'men'), ['Derby']);
    expect(namesInRail(tester, 'women'), ['Ballet Flat']);
    expect(namesInRail(tester, 'kids'), ['School Shoe']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the labels come from the shared vocabulary, in fixed order',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    // Labels are productAudienceLabel's, not strings typed into the widget.
    for (final audience in productRailAudiences) {
      expect(find.text(productAudienceLabel(audience)!), findsOneWidget);
    }
    // Fixed order: each rail's header is below the previous one's.
    final menY = tester.getTopLeft(find.text("Men's")).dy;
    expect(menY, lessThan(tester.getTopLeft(find.text("Women's")).dy));
    expect(tester.getTopLeft(find.text("Women's")).dy,
        lessThan(tester.getTopLeft(find.text("Kids'")).dy));
  });

  testWidgets('a unisex product appears in none of the three rails',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'any', name: 'House Slipper', audience: 'unisex')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    for (final audience in productRailAudiences) {
      expect(namesInRail(tester, audience), isEmpty,
          reason: 'unisex must stay out of the $audience rail');
    }
    // Nothing left behind at all — not even an empty strip.
    expect(find.byType(ProductRailSection), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unset product stays out of the rails but keeps its place in '
      'the catalog grid', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'legacy', name: 'Legacy Pair'),
        product(id: 'm', name: 'Derby', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, showCatalog: true));
    await tester.pump(const Duration(milliseconds: 300));

    // In a rail? No.
    for (final audience in productRailAudiences) {
      expect(namesInRail(tester, audience), isNot(contains('Legacy Pair')));
    }
    expect(namesInRail(tester, 'men'), ['Derby']);

    // Still in the catalog grid? Yes — this is the regression the phase must
    // not cause, asserted rather than assumed.
    expect(find.text('Legacy Pair'), findsOneWidget);
  });

  testWidgets('a rail with nothing to show renders nothing — no header, and '
      'no gap where it would have been', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'w', name: 'Ballet Flat', audience: 'women')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Men's"), findsNothing);
    expect(find.text("Kids'"), findsNothing);
    // A hidden section occupies nothing and leaves no strip behind.
    expect(tester.getSize(railOf('men')), Size.zero);
    expect(tester.getSize(railOf('kids')), Size.zero);
    expect(find.byType(ProductRailSection), findsOneWidget);

    // ...and the surviving rail is exactly as tall as it is on its own, so the
    // two hidden rails contributed no spacing.
    final withHiddenRails =
        tester.getSize(find.byType(ProductRailSection));
    await tester.pumpWidget(wrap(provider, audiences: const ['women']));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(ProductRailSection)), withHiddenRails);
  });

  testWidgets('with the kill switch off nothing renders, even with matches',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
      ],
      unitsSold: const {},
    );

    // `enabled: false` is the rollback: one constant flip and every rail
    // behaves as though it does not exist.
    await tester.pumpWidget(wrap(provider, enabled: false));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProductRailSection), findsNothing);
    expect(find.byType(HorizontalProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an audience that is not a rail renders nothing', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    await tester.pumpWidget(
      wrap(provider, audiences: const ['unisex', 'nonsense']),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProductRailSection), findsNothing);
    expect(find.text('Unisex'), findsNothing);
  });

  testWidgets('header survives a narrow phone at a large text scale',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The scale is copied onto the real ambient data rather than replacing it:
    // `MediaQueryData(textScaler: …)` zeroes `size` and every other field, which
    // would make any size-dependent layout meaningless here.
    await tester.pumpWidget(
      wrap(provider, textScale: 1.3),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Men's"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('dual-brightness check', () {
    tearDown(AppBrightness.reset);

    testWidgets('the header ink follows the published brightness',
        (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'm', name: 'Derby', audience: 'men')],
        unitsSold: const {},
      );

      await tester.pumpWidget(wrap(provider));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.text("Men's")).style!.color,
          AppPalette.light.onPage);

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap(provider));
      await tester.pump(const Duration(milliseconds: 300));
      // Same token, dark role — no theme lookup in the rail, and no mode where
      // the title renders in light-mode ink on a dark page.
      expect(tester.widget<Text>(find.text("Men's")).style!.color,
          AppPalette.dark.onPage);
      expect(tester.takeException(), isNull);
    });
  });
}
