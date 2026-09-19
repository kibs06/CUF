import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/screens/store/widgets/cross_store_product_row.dart';
import 'package:app/utils/product_grid_ratio.dart';
import 'package:app/widgets/sole_product_card.dart';

/// The "Top Picks from a store" grid used to be a `Wrap`, and a `Wrap` lays its
/// children out in **runs**: every card in a run is as tall as the tallest one,
/// so a shorter card leaves dead space beneath it until the next run begins.
///
/// Card heights here come from `productGridRatio`, which varies per product id
/// (1.0 / 0.78 / 1.22 / 0.95) — so the gap appeared only when two neighbouring
/// products had *different* ratios, and vanished when they matched. That is why
/// it read as a bug that comes and goes: it tracked the catalog, not the code.
///
/// This test renders the real grid with deliberately mixed heights and measures
/// it, so a future "simplify it back to a Wrap" cannot ship.
Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Four products in the order `[shorter, taller, shorter, taller]` — the order
/// is the whole point. A `Wrap` puts cards 1 and 2 in one run, so card 3 lands
/// below the *taller* of them; masonry puts card 3 under card 1, one gutter
/// down. Same ids → same ratios → same layout on every run.
///
/// The ids are searched for rather than hard-coded: `productGridRatio` keys off
/// `id.hashCode`, which is not a value to bake into a test.
List<Map<String, dynamic>> mixedHeightProducts() {
  // Enough ids to land on every ratio bucket with more than one id in it —
  // stopping as soon as four ratios are seen would leave single-id buckets.
  final byRatio = <double, List<String>>{};
  for (var i = 0; i < 100; i++) {
    byRatio.putIfAbsent(productGridRatio({'id': 'p$i'}), () => []).add('p$i');
  }
  final groups =
      byRatio.entries.where((e) => e.value.length >= 2).take(2).toList()
        // Descending ratio = ascending height (the ratio is width / height).
        ..sort((a, b) => b.key.compareTo(a.key));
  expect(groups.length, 2, reason: 'need two ratios with two ids each');

  final ids = [
    groups[0].value[0], // shorter
    groups[1].value[0], // taller
    groups[0].value[1], // shorter
    groups[1].value[1], // taller
  ];
  expect(
    productGridRatio({'id': ids[0]}),
    isNot(productGridRatio({'id': ids[1]})),
    reason: 'the two neighbours must differ in height, or this cannot fail',
  );

  return [
    for (final id in ids)
      {
        'id': id,
        'name': 'Shoe $id',
        'category': 'Boots',
        'price': 1000.0,
        'review_count': 0,
        'images': <String>[],
      },
  ];
}

void main() {
  testWidgets('cards stack tight, with no dead space under a shorter card', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SingleChildScrollView(
          child: CrossStoreProductRow(
            products: mixedHeightProducts(),
            storeName: 'Valladolid Leather Co.',
          ),
        ),
      ),
    );

    final rects = [
      for (var i = 0; i < 4; i++)
        tester.getRect(find.byType(SoleProductCard).at(i)),
    ];

    // Group the cards into their two columns by left edge.
    final columns = <double, List<Rect>>{};
    for (final rect in rects) {
      columns.putIfAbsent(rect.left, () => []).add(rect);
    }
    expect(
      columns.length,
      2,
      reason:
          'two columns, and the columns must share an x edge — a card '
          'drifting horizontally would break this grouping',
    );

    for (final column in columns.values) {
      column.sort((a, b) => a.top.compareTo(b.top));
      expect(column.length, 2);
      expect(
        column[1].top - column[0].bottom,
        closeTo(AppConstants.productGridGutter, 0.01),
        reason:
            'the second card in a column must start exactly one gutter '
            'below the first. A Wrap pushes it to the bottom of the tallest '
            'card in the run instead, which is the gap between products this '
            'grid used to show',
      );
    }

    // And the two columns start level, at the shared feed margin.
    expect(rects[0].top, closeTo(rects[1].top, 0.01));
    expect(rects[0].left, AppConstants.feedMargin);
  });

  testWidgets('an evenly-heighted catalog still packs and keeps the margin', (
    tester,
  ) async {
    // The same grid with four identical ratios — the case that used to LOOK
    // fine under a Wrap, so it must not be the only thing a test covers.
    final products = mixedHeightProducts();
    final even = [
      for (final p in products.take(4)) {...p, 'id': 'even-ratio'},
    ];
    await tester.pumpWidget(
      wrap(
        SingleChildScrollView(
          child: CrossStoreProductRow(
            products: even,
            storeName: 'Valladolid Leather Co.',
          ),
        ),
      ),
    );

    final first = tester.getRect(find.byType(SoleProductCard).at(0));
    final second = tester.getRect(find.byType(SoleProductCard).at(1));

    expect(first.left, AppConstants.feedMargin);
    expect(second.top - first.top, 0, reason: 'a level row stays level');
  });

  testWidgets('the section renders nothing at all when there are no products', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const CrossStoreProductRow(
          products: [],
          storeName: 'Valladolid Leather Co.',
        ),
      ),
    );

    expect(find.byType(SoleProductCard), findsNothing);
    expect(
      find.text('Top Picks'),
      findsNothing,
      reason:
          'no products means no header either — not an empty label over '
          'an empty grid',
    );
  });
}
