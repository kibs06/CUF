import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/search_results_screen.dart';
import 'package:app/widgets/horizontal_product_card.dart';
import 'package:app/widgets/sole_product_card.dart';

/// The search results page — the destination that replaced filtering the Home
/// feed in place.
///
/// What is pinned here is that a search never ends in a dead end: it lists what
/// matched, it can be narrowed and re-ordered without disturbing the Home feed,
/// and when nothing matches it offers products instead of blank space.
Map<String, dynamic> product({
  required String id,
  required String name,
  String category = 'Sneakers',
  double price = 1000,
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'images': <String>[],
    };

Widget wrap(ProductProvider provider, {String query = 'oxford'}) =>
    ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: MaterialApp(home: SearchResultsScreen(initialQuery: query)),
    );

/// Product names in the grid, in DOM order.
List<String> gridNames(WidgetTester tester) => tester
    .widgetList<SoleProductCard>(find.byType(SoleProductCard))
    .map((c) => c.product['name'].toString())
    .toList();

/// A filter-bar chip. Scoped to the chip row, because the cards also print
/// their category.
Finder chip(String label) => find.descendant(
      of: find.byType(ListView).first,
      matching: find.text(label),
    );

/// The painted width of the underline under [label] — the active-category
/// indicator. 0 means "not active": the underline animates out from nothing,
/// which a filled/bordered box could not do.
double underlineWidth(WidgetTester tester, String label) =>
    tester.getSize(find.byKey(ValueKey('search-underline-$label'))).width;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists what matched, and says how many', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Oxford Slide', category: 'Sandals'),
        product(id: 'c', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    expect(find.text('2 results for "oxford"'), findsOneWidget);
    expect(gridNames(tester), containsAll(['Classic Oxford', 'Oxford Slide']));
    expect(find.byType(SoleProductCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category chip narrows the results', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Oxford Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.tap(chip('Sandals'));
    await tester.pump();

    expect(find.text('1 result for "oxford"'), findsOneWidget);
    expect(gridNames(tester), ['Oxford Slide']);
  });

  testWidgets('there is exactly ONE All chip, and only for categories that '
      'actually matched', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Formal Loafer', category: 'Formal'),
        product(id: 'c', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, query: 'formal'));
    await tester.pump();

    // `ProductProvider.categories` starts with 'All' — reusing it printed a
    // second All chip next to the page's own.
    expect(chip('All'), findsOneWidget);
    expect(chip('Formal'), findsOneWidget);
    // Sandals matched nothing for "formal", so it is not a chip here.
    expect(chip('Sandals'), findsNothing);
  });

  testWidgets('the active category is marked by an underline under the label, '
      'not by filling or bordering the whole box', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Oxford Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    // 'All' is the active filter on open, so it alone carries an underline.
    expect(underlineWidth(tester, 'All'), greaterThan(0));
    expect(underlineWidth(tester, 'Formal'), 0);
    expect(underlineWidth(tester, 'Sandals'), 0);

    await tester.tap(chip('Sandals'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The indicator moved, rather than a second box appearing.
    expect(underlineWidth(tester, 'Sandals'), greaterThan(0));
    expect(underlineWidth(tester, 'All'), 0);
    // And it spans the label exactly — measured from the text, not a fixed
    // width and not the chip's tap padding.
    expect(
      underlineWidth(tester, 'Sandals'),
      closeTo(tester.getSize(chip('Sandals')).width, 0.5),
    );
  });

  testWidgets('sorting reorders the results and leaves the catalog sort alone',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'pricey', name: 'Oxford Deluxe', price: 3000),
        product(id: 'cheap', name: 'Oxford Basic', price: 900),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.tap(find.text('Featured'));
    // Two frames: one to start the sheet's transition, one to finish it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sort by'), findsOneWidget);

    await tester.tap(find.text('Price: Low to High'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(gridNames(tester), ['Oxford Basic', 'Oxford Deluxe']);
    // Home's own order must not have been changed by a search.
    expect(provider.sortMode, SortMode.featured);
  });

  testWidgets('a query that matches nothing offers products, not a dead end',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford'),
        product(id: 'b', name: 'Beach Slide'),
      ],
      unitsSold: const {'b': 10},
    );

    await tester.pumpWidget(wrap(provider, query: 'formal shoes xyz'));
    await tester.pump();

    expect(find.text('No matches for "formal shoes xyz"'), findsOneWidget);
    // The panel carries the shop's own picks — a rail, so it is tappable
    // through to the product page, and the page has no blank space.
    expect(find.text('Popular right now'), findsOneWidget);
    expect(find.byType(HorizontalProductCard), findsWidgets);
    expect(find.text('Browse All Styles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search by the catalog\'s own vocabulary is not a dead end',
      (tester) async {
    // The reported bug: "Formal Shoes" matched nothing because `Formal` is a
    // CATEGORY, which the old rule never consulted.
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, query: 'Formal Shoes'));
    await tester.pump();

    expect(find.text('No matches for "Formal Shoes"'), findsNothing);
    expect(gridNames(tester), ['Classic Oxford']);
  });

  testWidgets('the clear button empties the query and the page', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'Classic Oxford')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();
    expect(find.byType(SoleProductCard), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.byType(SoleProductCard), findsNothing);
    // ...and the page invites a new search rather than claiming a failure.
    expect(find.text('Search the artisan catalog'), findsOneWidget);
    expect(find.text('Popular right now'), findsOneWidget);
  });

  testWidgets('a new query typed here re-runs the search in place',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford'),
        product(id: 'b', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'slide');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(find.text('1 result for "slide"'), findsOneWidget);
    expect(gridNames(tester), ['Beach Slide']);
  });

  testWidgets('no query at all invites one instead of reporting a failure',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'Classic Oxford')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, query: ''));
    await tester.pump();

    expect(find.text('Search the artisan catalog'), findsOneWidget);
    expect(find.textContaining('No matches'), findsNothing);
    // The filter bar is hidden when there is no query to filter.
    expect(find.text('Featured'), findsNothing);
  });
}
