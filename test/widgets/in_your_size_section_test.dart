import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:app/widgets/two_column_masonry.dart';

/// The "Based on your size" home section — the first surface where the saved foot
/// profile actually changes what the customer is shown while shopping.
///
/// What is pinned here is the absent-safety (no size on file, nothing in the
/// catalog in that size, and no size data on a product must all render
/// NOTHING — never a guessed size, never a near size offered as theirs) and the
/// shape: it is The Workshop Collection's 2-column grid, not a horizontal
/// strip, so
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

  testWidgets('lays the tile and the matches on The Workshop Collection grid', (
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
    expect(find.byType(TwoColumnMasonry), findsOneWidget);

    // The catalog's own geometry, not a rail's: two columns inset by the feed
    // margin and seamed by the shared gutter.
    final gridWidth = tester.getSize(find.byType(TwoColumnMasonry)).width;
    final cardWidth =
        (gridWidth -
            AppConstants.feedMargin * 2 -
            AppConstants.productGridGutter) /
        2;
    // The tile is the first cell: left column, full cell width, and the
    // reference proportion rather than a height of its own. Scoped to the
    // poster — the shelf's door is a FitCard too.
    final poster = find.ancestor(
      of: find.text('Based'),
      matching: find.byType(FitCard),
    );
    final tile = tester.getRect(poster);

    // The poster bleeds: no inset, so its words span the cell edge to edge
    // (every other FitCard, the door included, keeps FitCard's own 16).
    expect(tester.widget<FitCard>(poster).padding, 0);
    final firstCard = tester.getRect(find.byType(SoleProductCard).at(0));

    // The tile is the first cell: left column, full cell width, and a height
    // that is its own copy's — NOT a capped proportion.
    expect(tile.left, moreOrLessEquals(AppConstants.feedMargin, epsilon: 0.5));
    expect(tile.width, moreOrLessEquals(cardWidth, epsilon: 0.5));

    // And nothing is squeezed: the poster's outer `scaleDown` FittedBox holds
    // content that already fits its box, so its lines are never shrunk as a
    // block. (This guard is structural rather than metric-dependent — the test
    // font is not DM Sans, so the cap that caused the squeeze cannot be seen
    // from here; 'the poster is its own box' pins it at the source instead.)
    final shrinkWrap = find
        .descendant(of: poster, matching: find.byType(FittedBox))
        .first;
    final wrapSize = tester.getSize(shrinkWrap);
    final contentSize = tester.getSize(
      find.descendant(of: shrinkWrap, matching: find.byType(SizedBox)).first,
    );
    expect(contentSize.height, lessThanOrEqualTo(wrapSize.height + 0.5));
    expect(contentSize.width, lessThanOrEqualTo(wrapSize.width + 0.5));

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

  test('the poster is its own box — the tile carries no proportion cap', () {
    // Read from the source, because the failure is invisible from a widget
    // test: at the reference `505/800` the poster's copy comes out taller than
    // the box IN DM SANS, so `FitCard`'s outer `scaleDown` shrinks the whole
    // card and every line stops short of the right edge by the same band (the
    // test font's metrics fit, so no widget test can catch this).
    final code = File(
      'lib/widgets/in_your_size_section.dart',
    ).readAsStringSync();

    expect(
      code.contains('tile: FitCard('),
      isTrue,
      reason: 'the size poster must be handed to the grid uncapped',
    );
    expect(
      RegExp(r'tile:\s*AspectRatio').hasMatch(code),
      isFalse,
      reason:
          'capping the tile pulls every poster line short of the right edge',
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

  testWidgets('the door closes the grid in its own column, on one bottom edge', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(shelfOf(11), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byType(SeeMoreCard));
    await tester.pump();

    final gridWidth = tester.getSize(find.byType(TwoColumnMasonry)).width;
    final cellWidth =
        (gridWidth -
            AppConstants.feedMargin * 2 -
            AppConstants.productGridGutter) /
        2;
    final grid = tester.getRect(find.byType(TwoColumnMasonry));
    final arrow = tester.getRect(find.byType(SeeMoreCard));
    final anchor = tester.getRect(find.byType(SoleProductCard).last);

    // One cell wide, in the RIGHT column whatever the flow above it did: its
    // left edge is one cell + one gutter past the grid's left edge, and its
    // right edge is the grid's own right edge. This is the regression the
    // placed pair exists for — a packed door landed in the LEFT column whenever
    // the left column of the flow ran short.
    expect(arrow.width, moreOrLessEquals(cellWidth, epsilon: 0.5));
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

    // It hangs off its OWN column — one gutter under the deepest cell in the
    // right column, never leaving the shorter column's leftover height showing
    // as a hole above the pair. (The last product anchors the left column at
    // the same time, which is what leaves nothing to fill.)
    final rightColumn = tester
        .widgetList<SoleProductCard>(find.byType(SoleProductCard))
        .map(
          (card) => tester.getRect(
            find.byWidgetPredicate(
              (widget) => widget is SoleProductCard && identical(widget, card),
            ),
          ),
        )
        .where((rect) => (rect.left - arrow.left).abs() < 0.5)
        .map((rect) => rect.bottom)
        .where((bottom) => bottom <= arrow.top + 0.5);
    final underTheDoor =
        rightColumn.isEmpty ? grid.top : rightColumn.reduce((a, b) => a > b ? a : b);
    expect(
      arrow.top,
      moreOrLessEquals(
        underTheDoor + AppConstants.productGridGutter,
        epsilon: 0.5,
      ),
    );

    // And the pair closes on ONE bottom edge: the door is sized to the anchor's
    // bottom, so the section does not end on a ragged step.
    expect(anchor.bottom, moreOrLessEquals(arrow.bottom, epsilon: 0.5));
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
