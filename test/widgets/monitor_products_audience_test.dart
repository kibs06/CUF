import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/screens/admin/monitor_products_screen.dart';
import 'package:app/utils/product_audience.dart';

/// The admin console's audience line — the admin's half of the backfill picture.
///
/// The seller's own screen counts what is missing; this one says *which* is
/// which, so an admin can answer "what is left to fill in?" without opening the
/// seller's editor. What is pinned here is that the value comes from the shared
/// vocabulary (so the console can never call a value something the seller form
/// and the customer's rails do not), that unset is visibly distinct from set
/// rather than silently blank, and that a stored value the vocabulary does not
/// recognise reads as unset for exactly the reason the rails drop it.
Map<String, dynamic> product({
  required String id,
  String name = 'Artisan Shoe',
  String? audience,
  String category = 'Sneakers',
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'price': 1000,
      'sizes': <String, dynamic>{},
      // Omitted when unset — the shape a NULL `audience` row arrives in.
      'audience': ?audience,
    };

Future<void> pumpConsole(
  WidgetTester tester,
  List<Map<String, dynamic>> products,
) async {
  // Tall enough for the whole catalog: the console's list is a lazy
  // `ListView.builder`, so on a default 600px surface the rows below the fold
  // are never built — and an assertion about them would silently be about the
  // first two products only.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = ProductProvider.seeded(products: products, unitsSold: const {});
  await tester.pumpWidget(
    ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: const MaterialApp(home: MonitorProductsScreen()),
    ),
  );
  // Two frames: the screen loads the catalog in a post-frame callback, and the
  // seeded rows survive it (the fetch fails silently in a test, and `loadProducts`
  // keeps what it has on failure).
  await tester.pump();
  await tester.pump();
}

/// The ink the value after `'Audience: '` is painted in.
Color audienceInkFor(WidgetTester tester, String value) =>
    tester.widget<Text>(find.text(value)).style!.color!;

void main() {
  testWidgets('every stated audience prints as the shared vocabulary calls it',
      (tester) async {
    // One product per value, named so the assertions cannot pass by accident.
    await pumpConsole(tester, [
      for (final (value, label) in productAudienceOptions)
        product(id: value, name: 'Shoe $label', audience: value),
    ]);

    for (final (_, label) in productAudienceOptions) {
      expect(find.text(label), findsOneWidget,
          reason: 'the console must print "$label" for its own value');
    }
    // The label is not re-spelled here: it is whatever the vocabulary says.
    expect(find.textContaining('Audience: '), findsWidgets);
  });

  testWidgets('an unset product reads as "Not set" — the seller form\'s own '
      'words — and stands out', (tester) async {
    await pumpConsole(tester, [
      product(id: 'a', name: 'Derby', audience: 'men'),
      product(id: 'b', name: 'Unknown Pair'),
    ]);

    expect(find.text('Men\'s'), findsOneWidget);
    expect(find.text(kAudienceUnsetLabel), findsOneWidget);

    // The one value an admin opens this screen to find is the missing one, so
    // unset is the amber attention tone rather than muted grey.
    expect(audienceInkFor(tester, kAudienceUnsetLabel),
        AppConstants.statusPendingColor);
    expect(audienceInkFor(tester, 'Men\'s'), isNot(AppConstants.statusPendingColor));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a value the vocabulary does not recognise reads as unset',
      (tester) async {
    // Same rule as everywhere else in the app: the column's CHECK is an exact
    // comparison, so 'Men' is not one of our values and must not be printed as
    // though it were. Counting it as *set* would be worse than either extreme —
    // an admin would see a filled field for a product no rail will ever show.
    await pumpConsole(tester, [
      product(id: 'a', name: 'A', audience: 'Men'),
      product(id: 'b', name: 'B', audience: 'unisex '),
      product(id: 'c', name: 'C', audience: ''),
      product(id: 'd', name: 'D', audience: 'men'),
    ]);

    expect(find.text(kAudienceUnsetLabel), findsNWidgets(3));
    expect(find.text('Men\'s'), findsOneWidget);
    expect(find.text('Men'), findsNothing);
  });

  testWidgets('a catalog with nothing stated is all "Not set", not blank',
      (tester) async {
    // Today's live catalog, exactly: 15 of 15 products unset.
    await pumpConsole(tester, [
      for (var i = 0; i < 3; i++) product(id: 'p$i', name: 'Shoe $i'),
    ]);

    expect(find.text(kAudienceUnsetLabel), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the line survives the whole console being empty', (tester) async {
    await pumpConsole(tester, []);
    expect(find.text('No products tracked.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
