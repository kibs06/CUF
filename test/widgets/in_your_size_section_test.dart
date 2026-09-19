import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/size_listing_screen.dart';
import 'package:app/utils/product_grid_ratio.dart';
import 'package:app/widgets/fit_card.dart';
import 'package:app/widgets/horizontal_product_card.dart';
import 'package:app/widgets/in_your_size_section.dart';
import 'package:app/widgets/see_more_card.dart';
import 'package:app/widgets/sole_product_card.dart';

/// The "Based on your size" home section — the first surface where the saved foot
/// profile actually changes what the customer is shown while shopping.
///
/// What is pinned here is the absent-safety (no size on file, nothing in the
/// catalog in that size, and no size data on a product must all render
/// NOTHING — never a guessed size, never a near size offered as theirs) and the
/// shape: it is the Artisan Catalog's 2-column grid, not a horizontal strip, so
/// it must lay out on the feed's own geometry and take the catalog's per-product
/// aspect ratio rather than a rail's fixed 130x180 card.
///
/// The heading is the poster tile (a `FitCard` in the grid's first cell), which
/// is why there is no text header left to find: the size it reports lives on the
/// card as the `EU` label over the customer's own number.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

/// The section only READS the measurement provider (the profile snapshot is the
/// primary source), so a stub with no scan is enough — and constructing the
/// real provider would reach for a Supabase instance the test has not set up.
class _MockFootMeasurementProvider extends Mock
    with ChangeNotifier
    implements FootMeasurementProvider {}

Map<String, dynamic> product({
  required String id,
  required String name,
  double price = 1000,
  List<(String, int)> stock = const [],
}) {
  return {
    'id': id,
    'name': name,
    'category': 'Sneakers',
    'price': price,
    'images': <String>[],
    'inventory': [
      for (final (size, units) in stock) {'size': size, 'stock': units},
    ],
  };
}

Widget wrap(ProductProvider provider, {Map<String, dynamic>? profile}) {
  final auth = _MockAuthProvider();
  when(() => auth.profile).thenReturn(profile);

  // No scan in memory: the signed-in-but-no-scan-this-session state, where the
  // profile snapshot has to be enough on its own.
  final foot = _MockFootMeasurementProvider();
  when(() => foot.latestMeasurement).thenReturn(null);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductProvider>.value(value: provider),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<FootMeasurementProvider>.value(value: foot),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: InYourSizeSection())),
    ),
  );
}

/// Product names as rendered by the section, in card (DOM) order.
List<String> renderedNames(WidgetTester tester) => tester
    .widgetList<SoleProductCard>(find.byType(SoleProductCard))
    .map((c) => c.product['name'].toString())
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the size card and one card per match', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'fit', name: 'In Size', stock: [('EU 42', 3)]),
        product(id: 'other', name: 'Other Size', stock: [('EU 40', 3)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // The heading is the poster tile, not a line of text above the grid — and
    // the grid now closes with the shelf's door, which is the second FitCard.
    expect(find.byType(FitCard), findsNWidgets(2));
    for (final line in const ['Based', 'on your', 'size']) {
      expect(find.text(line), findsOneWidget);
    }
    // And the size it was built on is the card's hero value, so a wrong one is
    // visible (and correctable in Settings → Size Your Foot).
    expect(find.text('EU'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(renderedNames(tester), ['In Size']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing with no size on file', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'fit', name: 'In Size', stock: [('EU 42', 3)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(
      wrap(provider, profile: {'foot_profile_source': 'skipped'}),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FitCard), findsNothing);
    expect(find.byType(SoleProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when no product stocks the size', (
    tester,
  ) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'sold-out', name: 'Sold Out', stock: [('EU 42', 0)]),
        product(id: 'near', name: 'Nearly', stock: [('EU 41.5', 4)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FitCard), findsNothing);
    expect(find.byType(SoleProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('presents matches most-sold first', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'low', name: 'Low', stock: [('EU 42', 1)]),
        product(id: 'high', name: 'High', stock: [('EU 42', 1)]),
      ],
      unitsSold: const {'low': 1, 'high': 30},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(renderedNames(tester), ['High', 'Low']);
  });

  testWidgets('a string size on the profile works the same', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'half', name: 'Half', stock: [('EU 42.5', 2)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': '42.5'}));
    await tester.pump(const Duration(milliseconds: 300));

    // A half size is four characters on the hero line — the card scales rather
    // than overflowing, and the unit stays on its own label.
    expect(find.text('EU'), findsOneWidget);
    expect(find.text('42.5'), findsOneWidget);
    expect(renderedNames(tester), ['Half']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card survives a narrow phone at a large text scale', (
    tester,
  ) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'fit', name: 'In Size', stock: [('EU 42', 3)]),
      ],
      unitsSold: const {},
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: wrap(provider, profile: {'foot_size_ph': 42}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FitCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays the tile and the matches on the Artisan Catalog grid', (
    tester,
  ) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'First', stock: [('EU 42', 3)]),
        product(id: 'b', name: 'Second', stock: [('EU 42', 3)]),
        product(id: 'c', name: 'Third', stock: [('EU 42', 3)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // The strip is gone for good: nothing horizontal, nothing left to swipe.
    expect(find.byType(HorizontalProductCard), findsNothing);
    expect(find.byType(MasonryGridView), findsOneWidget);

    // The catalog's own geometry, not a rail's: two columns inset by the feed
    // margin and seamed by the shared gutter.
    final gridWidth = tester.getSize(find.byType(MasonryGridView)).width;
    final cardWidth =
        (gridWidth -
            AppConstants.feedMargin * 2 -
            AppConstants.productGridGutter) /
        2;
    // The tile is the first cell: left column, full cell width, and the
    // reference proportion rather than a height of its own. Scoped to the
    // poster — the shelf's door is a FitCard too.
    final tile = tester.getRect(
      find.ancestor(of: find.text('Based'), matching: find.byType(FitCard)),
    );
    final firstCard = tester.getRect(find.byType(SoleProductCard).at(0));

    // The tile is the first cell: left column, full cell width, and the
    // reference proportion rather than a height of its own.
    expect(tile.left, moreOrLessEquals(AppConstants.feedMargin, epsilon: 0.5));
    expect(tile.width, moreOrLessEquals(cardWidth, epsilon: 0.5));
    expect(
      tile.height,
      moreOrLessEquals(cardWidth / FitCard.aspectRatio, epsilon: 0.5),
    );

    // The first product then takes the row's other cell — same line as the
    // tile, one cell + one gutter to its right — so the tile reads as part of
    // the grid rather than as a spacer above it.
    expect(firstCard.top, moreOrLessEquals(tile.top, epsilon: 0.5));
    expect(
      firstCard.left,
      moreOrLessEquals(
        tile.left + cardWidth + AppConstants.productGridGutter,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('every card takes the catalog aspect ratio for its product', (
    tester,
  ) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'First', stock: [('EU 42', 3)]),
        product(id: 'b', name: 'Second', stock: [('EU 42', 3)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    for (final card in tester.widgetList<SoleProductCard>(
      find.byType(SoleProductCard),
    )) {
      // Same rule the catalog grid applies, keyed off the product id — so a
      // product is the same height here as it is in the feed below.
      expect(card.imageAspectRatio, productGridRatio(card.product));
    }
  });

  /// A shelf of [count] products, ranked by distinct sales counts — so "the
  /// preview kept the top ten" is checkable by name.
  ProductProvider shelfOf(int count) => ProductProvider.seeded(
    products: [
      for (var i = 0; i < count; i++)
        product(id: 'p$i', name: 'P$i', stock: [('EU 42', 1)]),
    ],
    unitsSold: {for (var i = 0; i < count; i++) 'p$i': i + 1},
  );

  testWidgets('previews ten products, then hands over to the arrow', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(shelfOf(11), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // Ten, most-sold first: the eleventh match is what the arrow stands for on
    // a shelf longer than the preview, so the section is a taste of the shelf
    // rather than a second catalog above the real one.
    expect(renderedNames(tester).length, kHomePreviewCount);
    expect(renderedNames(tester).first, 'P10');
    expect(renderedNames(tester), isNot(contains('P0')));
    expect(find.byType(SeeMoreCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the arrow is there at any shelf length, even the whole shelf', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(shelfOf(10), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // The card is the shelf's door, not a "there is more" promise: with the
    // whole shelf already on screen it still opens the shelf as a place — and
    // on a short catalog that is the only way in, so the section never ends on
    // products with no way to say "all of mine live here".
    expect(renderedNames(tester).length, 10);
    expect(find.byType(SeeMoreCard), findsOneWidget);

    // And it really is the door: tapping it lands on the shelf page. (It sits
    // below the fold on this shelf, so scroll it into view first.)
    await tester.ensureVisible(find.byType(SeeMoreCard));
    await tester.pump();
    await tester.tap(find.byType(SeeMoreCard));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(SizeListingScreen), findsOneWidget);
    expect(find.text('10 pairs · EU 42'), findsOneWidget);
  });

  testWidgets('the arrow is pinned to the bottom-RIGHT, one cell wide', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(shelfOf(11), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byType(SeeMoreCard));
    await tester.pump();

    final gridWidth = tester.getSize(find.byType(MasonryGridView)).width;
    final cellWidth =
        (gridWidth -
            AppConstants.feedMargin * 2 -
            AppConstants.productGridGutter) /
        2;
    final grid = tester.getRect(find.byType(MasonryGridView));
    final arrow = tester.getRect(find.byType(SeeMoreCard));

    // One cell, on the reference proportion — the same slot the size poster
    // opens the grid with, so the section closes the way it starts.
    expect(arrow.width, moreOrLessEquals(cellWidth, epsilon: 0.5));
    expect(
      arrow.height,
      moreOrLessEquals(cellWidth / FitCard.aspectRatio, epsilon: 0.5),
    );
    // RIGHT column, whatever the masonry flow above it did: its left edge is
    // one cell + one gutter past the flow's left edge, and its right edge is
    // the flow's own right edge. This is the regression the pinned position
    // exists for — the packed version landed in the LEFT column whenever the
    // left column of the flow ran short.
    expect(
      arrow.left,
      moreOrLessEquals(
        grid.left +
            AppConstants.feedMargin +
            cellWidth +
            AppConstants.productGridGutter,
        epsilon: 0.5,
      ),
    );
    expect(
      arrow.right,
      moreOrLessEquals(grid.right - AppConstants.feedMargin, epsilon: 0.5),
    );
    // And it hangs BELOW the flow, one gutter under it — its own row, not a
    // packed cell.
    expect(arrow.top, greaterThanOrEqualTo(grid.bottom - 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the arrow opens the whole shelf', (tester) async {
    await tester.pumpWidget(wrap(shelfOf(11), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byType(SeeMoreCard));
    await tester.pump();

    await tester.tap(find.byType(SeeMoreCard));
    // NOT pumpAndSettle: the product cards' image placeholders spin forever.
    // Four frames is well past the route transition.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(SizeListingScreen), findsOneWidget);
    // The shelf it was built on stays named at the top of it, with the size and
    // the count the preview could not show: eleven, not the ten on the feed.
    expect(find.text('Based on your size'), findsOneWidget);
    expect(find.text('11 pairs · EU 42'), findsOneWidget);
    // The ranking is the preview's, so the first card is the one the preview
    // also opened with rather than a reshuffled shelf.
    expect(
      tester
          .widget<SoleProductCard>(find.byType(SoleProductCard).first)
          .product['name'],
      'P10',
    );
    expect(tester.takeException(), isNull);
  });
}
