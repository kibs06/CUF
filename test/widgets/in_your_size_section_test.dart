import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/widgets/horizontal_product_card.dart';
import 'package:app/widgets/in_your_size_section.dart';

/// The "In your size" home rail — the first surface where the saved foot
/// profile actually changes what the customer is shown while shopping.
///
/// What is pinned here is the absent-safety: no size on file, nothing in the
/// catalog in that size, and no size data on a product must all render
/// NOTHING (never a guessed size, never a near size offered as theirs), while a
/// genuine match renders the header, the size badge and the cards.
class _MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

/// The rail only READS the measurement provider (the profile snapshot is the
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

Widget wrap(
  ProductProvider provider, {
  Map<String, dynamic>? profile,
}) {
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
      home: Scaffold(
        body: SingleChildScrollView(child: InYourSizeSection()),
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

  testWidgets('renders the header, the size and one card per match',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'fit', name: 'In Size', stock: [('EU 42', 3)]),
        product(id: 'other', name: 'Other Size', stock: [('EU 40', 3)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('In your size'), findsOneWidget);
    // The size names what the app believes, so a wrong one is visible.
    expect(find.text('EU 42'), findsOneWidget);
    expect(renderedNames(tester), ['In Size']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing with no size on file', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'fit', name: 'In Size', stock: [('EU 42', 3)])],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_profile_source': 'skipped'}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('In your size'), findsNothing);
    expect(find.byType(HorizontalProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when no product stocks the size', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'sold-out', name: 'Sold Out', stock: [('EU 42', 0)]),
        product(id: 'near', name: 'Nearly', stock: [('EU 41.5', 4)]),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, profile: {'foot_size_ph': 42}));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('In your size'), findsNothing);
    expect(find.byType(HorizontalProductCard), findsNothing);
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

    expect(find.text('EU 42.5'), findsOneWidget);
    expect(renderedNames(tester), ['Half']);
  });

  testWidgets('header survives a narrow phone at a large text scale',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'fit', name: 'In Size', stock: [('EU 42', 3)])],
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

    expect(find.text('In your size'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
