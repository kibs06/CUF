import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/catalog_end_cap.dart';

/// The home feed's finish line.
///
/// It exists because the tail of the feed was the same product card repeated to
/// the last item and then blank space, which reads as the grid breaking rather
/// than the shelf ending. What is pinned here is that it signs off and names how
/// much the customer got through — and that it stays a signpost: no CTA, and no
/// invented figure when the catalog or the store ids are not known.
void main() {
  Future<void> pumpCap(
    WidgetTester tester, {
    int productCount = 128,
    int storeCount = 6,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogEndCap(
            productCount: productCount,
            storeCount: storeCount,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('catalogSignpostLine', () {
    test('names both the pairs and the workshops', () {
      expect(
        catalogSignpostLine(productCount: 128, storeCount: 6),
        '128 pairs · 6 workshops',
      );
    });

    test('singulars stay singular', () {
      expect(
        catalogSignpostLine(productCount: 1, storeCount: 1),
        '1 pair · 1 workshop',
      );
    });

    test('an unknown shop count drops the figure, not the pairs', () {
      // A catalog whose products carry no store_id has no honest shop count.
      expect(catalogSignpostLine(productCount: 12, storeCount: 0), '12 pairs');
    });

    test('no products at all yields no line', () {
      expect(catalogSignpostLine(productCount: 0, storeCount: 6), '');
    });
  });

  testWidgets('signs off the catalog and counts what was on it', (tester) async {
    await pumpCap(tester);

    expect(find.text("That's the whole shelf"), findsOneWidget);
    expect(find.text('128 pairs · 6 workshops'), findsOneWidget);
  });

  testWidgets('stays a signpost — no call to action', (tester) async {
    await pumpCap(tester);

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('renders without a count when the shop count is unknown',
      (tester) async {
    await pumpCap(tester, productCount: 1, storeCount: 0);

    expect(find.text("That's the whole shelf"), findsOneWidget);
    expect(find.text('1 pair'), findsOneWidget);
  });
}
