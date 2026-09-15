import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/product_provider.dart';
import 'package:app/widgets/best_sellers_section.dart';
import 'package:app/widgets/horizontal_product_card.dart';

/// The "Best Sellers" home rail — rendering, the empty state, the header
/// action, and the order it presents products in.
///
/// Uses the [ProductProvider.seeded] test seam so the rail reads a fixed
/// catalog + `units_sold` aggregation with no network access.

Map<String, dynamic> product({
  required String id,
  required String name,
  double price = 1000,
}) {
  return {
    'id': id,
    'name': name,
    'category': 'Sneakers',
    'price': price,
    'images': <String>[],
  };
}

Widget wrap(ProductProvider provider, {VoidCallback? onSeeAll}) {
  return ChangeNotifierProvider<ProductProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BestSellersSection(onSeeAll: onSeeAll),
        ),
      ),
    ),
  );
}

/// Product names as rendered by the rail, in horizontal (DOM) order.
List<String> renderedNames(WidgetTester tester) => tester
    .widgetList<HorizontalProductCard>(find.byType(HorizontalProductCard))
    .map((c) => c.product['name'].toString())
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders nothing at all when nothing has sold', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'Unsold A')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));

    expect(find.text('Best Sellers'), findsNothing);
    expect(find.text('MOST SOLD'), findsNothing);
    expect(find.byType(HorizontalProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the header, badge and one card per best seller',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'top', name: 'Top Seller'),
        product(id: 'mid', name: 'Mid Seller'),
        product(id: 'never', name: 'Never Sold'),
      ],
      unitsSold: const {'top': 30, 'mid': 4},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Best Sellers'), findsOneWidget);
    expect(find.text('MOST SOLD'), findsOneWidget);
    expect(find.byType(HorizontalProductCard), findsNWidgets(2));
    expect(find.text('Never Sold'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('presents products most-sold first', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'low', name: 'Low'),
        product(id: 'high', name: 'High'),
        product(id: 'mid', name: 'Mid'),
      ],
      // Deliberately not in catalog order: the rail must rank by units sold.
      unitsSold: const {'low': 1, 'high': 50, 'mid': 10},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(renderedNames(tester), ['High', 'Mid', 'Low']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail scrolls horizontally without overflow',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        for (var i = 0; i < kBestSellerLimit; i++)
          product(id: 'p$i', name: 'Product $i'),
      ],
      unitsSold: {for (var i = 0; i < kBestSellerLimit; i++) 'p$i': i + 1},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);

    final before = tester.getTopLeft(find.byType(HorizontalProductCard).first);
    await tester.drag(
      find.byType(HorizontalProductCard).first,
      const Offset(-200, 0),
    );
    await tester.pump();
    final after = tester.getTopLeft(find.byType(HorizontalProductCard).first);

    expect(after.dx, lessThan(before.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no "See all" action when the caller supplies none',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'A')],
      unitsSold: const {'a': 1},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('See all'), findsNothing);
  });

  testWidgets('header survives a narrow phone at a large text scale',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'A')],
      unitsSold: const {'a': 1},
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: wrap(provider, onSeeAll: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Best Sellers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"See all" runs the caller action', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'A')],
      unitsSold: const {'a': 1},
    );
    var taps = 0;

    await tester.pumpWidget(wrap(provider, onSeeAll: () => taps++));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('See all'), findsOneWidget);
    await tester.tap(find.text('See all'));
    await tester.pump();

    expect(taps, 1);
  });
}
