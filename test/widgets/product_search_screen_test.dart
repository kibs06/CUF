import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/product_search_screen.dart';
import 'package:app/screens/customer/search_results_screen.dart';
import 'package:app/widgets/sole_product_card.dart';

/// The search page: the field is the only place a customer types, so it is
/// where the suggestion panel belongs.
///
/// Two things matter here. The panel must be **live and catalog-derived** (no
/// query, no network — it updates on every keystroke), and committing a term
/// must **push a results page**, not hand the term back to Home: that hand-off
/// is what used to filter the feed in place and leave no way back.
Map<String, dynamic> product({
  required String id,
  required String name,
  String category = 'Sneakers',
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'price': 1000,
      'images': <String>[],
    };

Widget wrap(ProductProvider provider) =>
    ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: const MaterialApp(home: ProductSearchScreen()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('typing shows a suggestion panel for what was typed',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    // Nothing typed yet: discovery, not suggestions.
    expect(find.text('Search Discovery'), findsOneWidget);
    expect(find.text('Suggestions'), findsNothing);

    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump();

    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.text('Search Discovery'), findsNothing);
    // The typed term itself is offered first (a tappable row, not just the
    // field), then the catalog's own word for those products.
    expect(find.byKey(const ValueKey('search-suggestion-query')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-suggestion-Formal')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a query with no suggestions says so instead of going blank',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'Classic Oxford', category: 'Formal')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.textContaining('No suggestions for that'), findsOneWidget);
    // The term is still searchable — as a row, not only in the field.
    expect(find.byKey(const ValueKey('search-suggestion-query')), findsOneWidget);
  });

  testWidgets('committing a term pushes the results page', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'formal');
    await tester.pump();
    // The top bar's filled button — the query row also draws a magnifier.
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(find.text('1 result for "formal"'), findsOneWidget);
    expect(find.byType(SoleProductCard), findsOneWidget);

    // Back returns to the search field, not to a filtered Home feed.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SearchResultsScreen), findsNothing);
    // The field keeps the term, so it can be refined instead of retyped...
    expect(
      find.byKey(const ValueKey('search-suggestion-query')),
      findsOneWidget,
    );
    // ...and clearing it shows the term has been recorded in history.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recently Searched'), findsOneWidget);
  });

  testWidgets('tapping a suggestion searches that term', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'a', name: 'Classic Oxford', category: 'Formal'),
        product(id: 'b', name: 'Beach Slide', category: 'Sandals'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'san');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('search-suggestion-Sandals')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(find.text('1 result for "Sandals"'), findsOneWidget);
  });

  testWidgets('the clear button empties the field and brings discovery back',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'a', name: 'Classic Oxford', category: 'Formal')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'formal');
    await tester.pump();
    expect(find.text('Suggestions'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Suggestions'), findsNothing);
    expect(find.text('Search Discovery'), findsOneWidget);
  });
}
