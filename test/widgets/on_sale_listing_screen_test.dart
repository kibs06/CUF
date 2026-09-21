import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/on_sale_listing_screen.dart';
import 'package:app/utils/product_grid_ratio.dart';
import 'package:app/utils/sale_price.dart';
import 'package:app/widgets/on_sale_card.dart';
import 'package:app/widgets/product_shelf_toolbar.dart';
import 'package:app/widgets/sole_product_card.dart';
import 'package:app/widgets/underline_category_chip.dart';

/// The whole shelf behind the home feed's **ON SALE** card.
///
/// What is pinned here: it is the *same* shelf — same inclusion rule, same card,
/// same per-product ratio — with nothing taken away (that is the whole reason
/// the card exists); it searches, filters and sorts *itself* without ever
/// narrowing its own rule (a search here never reaches past the sale); and a
/// sale ending while the page is open explains itself instead of rendering a
/// blank page.
Map<String, dynamic> product({
  required String id,
  required String name,
  double price = 1000,
  double? salePrice,
}) {
  return {
    'id': id,
    'name': name,
    'category': 'Sneakers',
    'price': price,
    'sale_price': ?salePrice,
    'images': <String>[],
    'inventory': const [
      {'size': 'EU 42', 'stock': 2},
    ],
  };
}

/// [count] products on sale, each at a distinct (increasing) discount, plus one
/// that is not on sale at all.
ProductProvider saleShelfOf(int count) => ProductProvider.seeded(
  products: [
    for (var i = 0; i < count; i++)
      product(
        id: 'p$i',
        name: 'P$i',
        // 10% off, 11% off, 12% off … so the best discount is deterministic.
        salePrice: 1000 - (10 + i) * 10,
      ),
    product(id: 'full', name: 'Full Price'),
  ],
);

/// The page's own scroll view.
///
/// Named, not `find.byType(Scrollable).first`: the shelf toolbar's category
/// chips are a horizontal `ListView` and every card carries a photo pager, so
/// the first `Scrollable` on the page is no longer the list being scrolled.
Finder shelfScroll() => find
    .descendant(
      of: find.byType(MasonryGridView),
      matching: find.byType(Scrollable),
    )
    .first;

/// A window tall enough to lay out a whole small shelf, since the grid is lazy
/// and a card below the fold is genuinely not built.
void useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The names of the cards on the page, in the order they are laid out — the
/// only honest way to assert a *sort* from a widget test.
List<String> cardOrder(WidgetTester tester) => tester
    .widgetList<SoleProductCard>(find.byType(SoleProductCard))
    .map((card) => card.product['name'] as String)
    .toList();

/// A category chip by its label — `find.text` alone also matches the category a
/// card prints beside its price.
Finder chip(String label) => find.widgetWithText(UnderlineCategoryChip, label);

Widget wrap(ProductProvider provider, {bool pushed = false}) {
  return ChangeNotifierProvider<ProductProvider>.value(
    value: provider,
    child: MaterialApp(
      // The empty state's way out is a pop — so the test needs something
      // underneath it to pop back to.
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OnSaleListingScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            )
          : const OnSaleListingScreen(),
    ),
  );
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  // NOT pumpAndSettle: the product cards' image placeholders spin forever.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('lists the whole sale shelf, uncapped, headed by the discount', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(saleShelfOf(15)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('On Sale'), findsOneWidget);
    // Fifteen (all but the full-price one), and the best discount is the 15th
    // product's 24% — floored from the shelf, named on the page.
    expect(find.text('15 pairs · up to 24% off'), findsOneWidget);

    // The end of the shelf is reachable: this is the whole list, not a preview.
    // Named explicitly: every product card carries its own photo pager now, so
    // the page's scroll view is found by its type rather than by `first`.
    await tester.scrollUntilVisible(
      find.text('P14'),
      400,
      scrollable: shelfScroll(),
    );
    expect(find.text('P14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows only what is on sale — the rule is the shared one', (
    tester,
  ) async {
    final provider = saleShelfOf(3);
    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Full Price'), findsNothing);
    final cards = tester.widgetList<SoleProductCard>(
      find.byType(SoleProductCard),
    );
    expect(cards.length, 3);
    for (final card in cards) {
      expect(isOnSale(card.product), isTrue);
    }
  });

  testWidgets('uses the same card and the same ratio as the home grid', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(saleShelfOf(4)));
    await tester.pump(const Duration(milliseconds: 300));

    final cards = tester.widgetList<SoleProductCard>(
      find.byType(SoleProductCard),
    );
    expect(cards, isNotEmpty);
    for (final card in cards) {
      // Keyed off the product id, exactly like the feed's grid, so a product
      // looks identical on both sides of the card.
      expect(card.imageAspectRatio, productGridRatio(card.product));
    }
    // And no poster inside the list: the ON SALE card is the section's heading,
    // not a repeated banner.
    expect(find.byType(OnSaleCard), findsNothing);
  });

  testWidgets('searches the sale shelf in place, and the discount stands', (
    tester,
  ) async {
    useTallWindow(tester);
    await tester.pumpWidget(wrap(saleShelfOf(3)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProductShelfToolbar), findsOneWidget);
    // The chips name the categories the *sale* holds — never the catalog's
    // vocabulary, which here would offer a 'Full Price' category that is not on
    // this shelf at all.
    expect(chip('Sneakers'), findsOneWidget);
    expect(find.text('3 pairs · up to 12% off'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'p1');
    await tester.pump();

    expect(cardOrder(tester), ['P1']);
    expect(find.text('1 of 3 pairs · up to 12% off'), findsOneWidget);
    // The heading still names the *shelf's* best discount, not the one card's:
    // a heading that re-derived it from the visible list would change the page's
    // own claim as the customer typed.
    expect(find.text('up to 11% off'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(cardOrder(tester).length, 3);
    expect(find.text('3 pairs · up to 12% off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters by a category, and sorts, without leaving the sale', (
    tester,
  ) async {
    useTallWindow(tester);
    final provider = ProductProvider.seeded(
      products: [
        // One Sneaker and two Boots, so a category chip is a real choice and
        // the price order is not the catalog order.
        product(id: 'p0', name: 'Sneaker A', price: 900, salePrice: 700),
        {
          ...product(id: 'p1', name: 'Boot B', price: 500, salePrice: 300),
          'category': 'Boots',
        },
        {
          ...product(id: 'p2', name: 'Boot C', price: 300, salePrice: 100),
          'category': 'Boots',
        },
        product(id: 'full', name: 'Full Price'),
      ],
    );
    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    // The chips are the categories the *sale* holds, never the catalog's.
    expect(chip('All'), findsOneWidget);
    expect(chip('Boots'), findsOneWidget);
    expect(chip('Sneakers'), findsOneWidget);

    await tester.tap(chip('Boots'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cardOrder(tester), ['Boot B', 'Boot C']);
    expect(find.text('Full Price'), findsNothing);

    await tester.tap(chip('All'));
    await tester.pump(const Duration(milliseconds: 300));

    // Sorting here orders this page only — the feed's own order is untouched.
    await tester.tap(find.text('Featured'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Price: Low to High').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(cardOrder(tester), ['Boot C', 'Boot B', 'Sneaker A']);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(provider.sortMode, SortMode.featured);
    expect(find.text('Full Price'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search that matches nothing is not an ended sale', (
    tester,
  ) async {
    useTallWindow(tester);
    await tester.pumpWidget(wrap(saleShelfOf(3)));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'boot');
    await tester.pump();

    expect(find.byType(SoleProductCard), findsNothing);
    // Its own words: the sale is fine, the question was too narrow.
    expect(find.text('Nothing on sale matches "boot"'), findsOneWidget);
    expect(find.text('Nothing on sale right now'), findsNothing);

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(cardOrder(tester).length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty sale shelf gets no toolbar at all', (tester) async {
    await tester.pumpWidget(wrap(ProductProvider.seeded()));
    await tester.pump(const Duration(milliseconds: 300));

    // Nothing to search, filter or sort — and the empty state says what to do
    // instead of offering three controls over an empty grid.
    expect(find.byType(ProductShelfToolbar), findsNothing);
    expect(find.text('Nothing on sale right now'), findsOneWidget);
  });

  testWidgets('says so when the last sale ends while the page is open', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(ProductProvider.seeded()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SoleProductCard), findsNothing);
    expect(find.text('Nothing on sale right now'), findsOneWidget);
    expect(find.text('0 pairs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the way out of the empty state closes the page', (tester) async {
    await tester.pumpWidget(wrap(ProductProvider.seeded(), pushed: true));
    await tester.pump(const Duration(milliseconds: 300));

    await open(tester);
    expect(find.byType(OnSaleListingScreen), findsOneWidget);

    // Safe to settle here: the empty state has no product cards, so nothing on
    // screen animates forever.
    await tester.tap(find.text('Browse All Styles'));
    await tester.pumpAndSettle();

    expect(find.byType(OnSaleListingScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
