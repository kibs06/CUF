import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/size_listing_screen.dart';
import 'package:app/utils/product_grid_ratio.dart';
import 'package:app/widgets/product_shelf_toolbar.dart';
import 'package:app/widgets/sole_product_card.dart';
import 'package:app/widgets/underline_category_chip.dart';

/// The whole shelf behind the home feed's **See more** card.
///
/// What is pinned here: it is the *same* shelf — same inclusion rule, same
/// ranking, same card, same per-product ratio — with nothing taken away (that is
/// the whole reason the card exists); it cannot be narrowed *out* of its own
/// rule by its own search, filter and sort (searching the shelf never widens it
/// to the catalog, and sorting it never touches the Home feed's order); it is
/// absent-safe like every other size surface; and a search that matches nothing
/// is not confused with a shelf that holds nothing.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

class _MockFootMeasurementProvider extends Mock
    with ChangeNotifier
    implements FootMeasurementProvider {}

Map<String, dynamic> product({
  required String id,
  required String name,
  List<(String, int)> stock = const [],
  String category = 'Sneakers',
  double price = 1000,
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
    'price': price,
    'images': <String>[],
    'inventory': [
      for (final (size, units) in stock) {'size': size, 'stock': units},
    ],
  };
}

/// A shelf of three, deliberately mixed — two categories, three prices, and a
/// name order that matches neither — so a filter and a sort can be told apart
/// from the shelf's own ranking.
ProductProvider mixedShelf() => ProductProvider.seeded(
  products: [
    product(
      id: 'b1',
      name: 'Chelsea Boot',
      category: 'Boots',
      price: 300,
      stock: [('EU 42', 1)],
    ),
    product(
      id: 's1',
      name: 'Penny Loafer',
      category: 'Sneakers',
      price: 100,
      stock: [('EU 42', 1)],
    ),
    product(
      id: 'b2',
      name: 'Desert Boot',
      category: 'Boots',
      price: 200,
      stock: [('EU 42', 1)],
    ),
  ],
  unitsSold: {'b1': 30, 's1': 20, 'b2': 10},
);

/// The names of the cards on the page, in the order they are laid out — the
/// only honest way to assert a *sort* from a widget test.
List<String> cardOrder(WidgetTester tester) => tester
    .widgetList<SoleProductCard>(find.byType(SoleProductCard))
    .map((card) => card.product['name'] as String)
    .toList();

/// The page's own scroll view.
///
/// Named, not `find.byType(Scrollable).first`: the shelf toolbar's category
/// chips are a horizontal `ListView`, the grid is a `MasonryGridView`, and
/// every card carries a photo pager — so the first `Scrollable` on the page is
/// no longer the list being scrolled (the same correction the size listing
/// test already made once for the photo pager).
Finder shelfScroll() => find
    .descendant(
      of: find.byType(MasonryGridView),
      matching: find.byType(Scrollable),
    )
    // The grid's own scroller, which is its first (the cards' photo pagers are
    // Scrollables inside it and are matched too, one per card).
    .first;

/// A window tall enough to lay out a whole small shelf, since the grid is lazy
/// and a card below the fold is genuinely not built.
void useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A category chip by its label — `find.text` alone also matches the category a
/// product card prints beside its price.
Finder chip(String label) => find.widgetWithText(UnderlineCategoryChip, label);

/// A shelf of [count] products in EU 42, ranked by distinct sales counts.
ProductProvider shelfOf(int count) => ProductProvider.seeded(
  products: [
    for (var i = 0; i < count; i++)
      product(id: 'p$i', name: 'P$i', stock: [('EU 42', 1)]),
  ],
  unitsSold: {for (var i = 0; i < count; i++) 'p$i': i + 1},
);

Widget wrap(
  ProductProvider provider, {
  Map<String, dynamic>? profile,
  bool pushed = false,
}) {
  final auth = _MockAuthProvider();
  when(() => auth.profile).thenReturn(profile);

  final foot = _MockFootMeasurementProvider();
  when(() => foot.latestMeasurement).thenReturn(null);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductProvider>.value(value: provider),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<FootMeasurementProvider>.value(value: foot),
    ],
    child: MaterialApp(
      // The page is reached by pushing, and the empty state's way out is a pop —
      // so the test has to have something underneath it to pop back to.
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SizeListingScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            )
          : const SizeListingScreen(),
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('lists the whole shelf, uncapped, headed by the size', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(shelfOf(15), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Based on your size'), findsOneWidget);
    // Fifteen, not the ten the home preview could show — and the number is the
    // shelf's length, so the page is not quietly a second preview.
    expect(find.text('15 pairs · EU 42'), findsOneWidget);

    // The end of the shelf is reachable, in the preview's ranking: the very
    // product the arrow stood for is on the page.
    // Named explicitly: every product card carries its own photo pager now, so
    // `find.byType(Scrollable)` is no longer the page's scroll view alone.
    // `.first` is the page's, being the ancestor of the cards'.
    await tester.scrollUntilVisible(
      find.text('P0'),
      400,
      scrollable: shelfScroll(),
    );
    expect(find.text('P0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the same card and the same ratio as the home grid', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(shelfOf(4), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    final cards = tester.widgetList<SoleProductCard>(
      find.byType(SoleProductCard),
    );
    expect(cards, isNotEmpty);
    for (final card in cards) {
      // Keyed off the product id, exactly like the feed's grid, so a product
      // looks identical on both sides of the arrow.
      expect(card.imageAspectRatio, productGridRatio(card.product));
    }
  });

  testWidgets('searches the shelf in place, and the count follows the grid', (
    tester,
  ) async {
    useTallWindow(tester);
    await tester.pumpWidget(wrap(mixedShelf(), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProductShelfToolbar), findsOneWidget);
    expect(find.text('3 pairs · EU 42'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'boot');
    await tester.pump();

    // Only the shelf's matches, and the heading says so rather than still
    // counting the pair it is not showing.
    expect(cardOrder(tester), ['Chelsea Boot', 'Desert Boot']);
    expect(find.text('2 of 3 pairs · EU 42'), findsOneWidget);

    // The clear button empties the field AND the search — a narrowed shelf the
    // customer cannot widen again is the defect the search page already fixed
    // once.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(cardOrder(tester).length, 3);
    expect(find.text('3 pairs · EU 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters by a category the shelf actually holds', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(wrap(mixedShelf(), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // The chips are the shelf's own categories — 'All' plus what is in it — and
    // never the catalog's vocabulary.
    expect(chip('All'), findsOneWidget);
    expect(chip('Boots'), findsOneWidget);
    expect(chip('Sneakers'), findsOneWidget);

    await tester.tap(chip('Boots'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cardOrder(tester), ['Chelsea Boot', 'Desert Boot']);
    expect(find.text('2 of 3 pairs · EU 42'), findsOneWidget);

    await tester.tap(chip('All'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cardOrder(tester).length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sorts the shelf, in the app\'s own orders', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(wrap(mixedShelf(), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // Featured: the shelf's own ranking (most sold first), which is the order
    // the home preview showed.
    expect(cardOrder(tester), ['Chelsea Boot', 'Penny Loafer', 'Desert Boot']);
    expect(find.text('Featured'), findsOneWidget);

    // NOT pumpAndSettle anywhere below: the cards' image placeholders spin
    // forever, so the sheet's animation is waited out by hand (the convention
    // the search results and audience shelf tests already use).
    await tester.tap(find.text('Featured'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Price: Low to High').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(cardOrder(tester), ['Penny Loafer', 'Desert Boot', 'Chelsea Boot']);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search that matches nothing is not an empty shelf', (
    tester,
  ) async {
    useTallWindow(tester);
    await tester.pumpWidget(wrap(mixedShelf(), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'derby');
    await tester.pump();

    expect(find.byType(SoleProductCard), findsNothing);
    // Its own words — the shelf is fine and the way back is in the panel, not
    // the way out of the page.
    expect(find.text('Nothing in your size matches "derby"'), findsOneWidget);
    expect(find.text('Nothing in your size right now'), findsNothing);
    expect(find.text('0 of 3 pairs · EU 42'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(cardOrder(tester).length, 3);
    expect(find.text('3 pairs · EU 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty shelf gets no toolbar at all', (tester) async {
    await tester.pumpWidget(wrap(shelfOf(0), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // Nothing to search, filter or sort — and the empty state says what to do
    // instead of offering three controls over an empty grid.
    expect(find.byType(ProductShelfToolbar), findsNothing);
    expect(find.text('Nothing in your size right now'), findsOneWidget);
  });

  testWidgets('says so when nothing in the catalog stocks the size', (
    tester,
  ) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'other', name: 'Other', stock: [('EU 40', 3)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SoleProductCard), findsNothing);
    expect(find.text('Nothing in your size right now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no size on file is an explanation, never a guessed size', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(shelfOf(3), profile: {'foot_profile_source': 'skipped'}),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SoleProductCard), findsNothing);
    expect(find.text('Nothing in your size right now'), findsOneWidget);
  });

  testWidgets('the way out of the empty state closes the page', (tester) async {
    await tester.pumpWidget(
      wrap(
        shelfOf(3),
        profile: {'foot_profile_source': 'skipped'},
        pushed: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await open(tester);
    expect(find.byType(SizeListingScreen), findsOneWidget);

    // Safe to settle here: the empty state has no product cards, so nothing on
    // screen animates forever.
    await tester.tap(find.text('Browse All Styles'));
    await tester.pumpAndSettle();

    expect(find.byType(SizeListingScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
