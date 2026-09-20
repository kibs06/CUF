import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/size_listing_screen.dart';
import 'package:app/utils/product_grid_ratio.dart';
import 'package:app/widgets/sole_product_card.dart';

/// The whole shelf behind the home feed's **See more** card.
///
/// What is pinned here: it is the *same* shelf — same inclusion rule, same
/// ranking, same card, same per-product ratio — with nothing taken away (that is
/// the whole reason the card exists), it invents no controls the section it came
/// from does not have, and it is absent-safe like every other size surface:
/// no size on file, or nothing in that size, explains itself instead of
/// rendering a blank page or a guessed size.
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
}) {
  return {
    'id': id,
    'name': name,
    'category': 'Sneakers',
    'price': 1000,
    'images': <String>[],
    'inventory': [
      for (final (size, units) in stock) {'size': size, 'stock': units},
    ],
  };
}

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
      scrollable: find.byType(Scrollable).first,
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

  testWidgets('invents no sort control of its own', (tester) async {
    await tester.pumpWidget(wrap(shelfOf(4), profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    // The section that opens this page has no sort either: the list a customer
    // tapped is the list they get.
    expect(find.text('Featured'), findsNothing);
    expect(find.text('Sort'), findsNothing);
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
