import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/utils/product_grid_ratio.dart';
import 'package:app/widgets/product_grid_section.dart';
import 'package:app/widgets/sole_product_card.dart';

/// The home feed carries more than one product grid: "Based on your size" (a
/// [ProductGridSection]) sits above the Artisan Catalog's own
/// `MasonryGridView.count`, both inside the same `CustomScrollView`.
///
/// That pairing used to be documented as unsafe — a note in
/// `customer_home_screen.dart` claimed two masonry grids in one scroll view
/// trigger a scroll-offset-correction loop in `flutter_staggered_grid_view`
/// 0.7.0 that yanks the viewport back and makes the bottom of the catalog
/// unreachable. It is not reproducible with the box-level grids the feed
/// actually uses (two `MasonryGridView.count`s, `shrinkWrap` +
/// `NeverScrollableScrollPhysics`), and the failure it describes is exactly the
/// one that would strand a customer mid-feed, so the behaviour is pinned rather
/// than re-argued in a comment.
///
/// What is asserted: the feed's extent covers every card, dragging reaches that
/// end, the offset stays put on idle frames instead of being corrected
/// backwards, and the drag still works in the other direction.
List<Map<String, dynamic>> products(int n) => [
  for (var i = 0; i < n; i++)
    {
      'id': 'p$i',
      'name': 'Product $i',
      'category': 'Sneakers',
      'price': 1000.0,
      'images': <String>[],
      'inventory': <Map<String, dynamic>>[],
    },
];

/// The catalog's grid, exactly as `customer_home_screen.dart` builds it.
Widget catalogGrid(List<Map<String, dynamic>> items) {
  return MasonryGridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: AppConstants.feedMargin),
    crossAxisCount: 2,
    crossAxisSpacing: AppConstants.productGridGutter,
    mainAxisSpacing: AppConstants.productGridGutter,
    itemCount: items.length,
    itemBuilder: (context, index) {
      final prod = items[index];
      return SoleProductCard(
        product: prod,
        imageAspectRatio: productGridRatio(prod),
        onTap: () {},
      );
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the feed reaches its last card with two grids on it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // "Based on your size" — the section previews it to
                    // kHomePreviewCount, so this is the real worst case.
                    ProductGridSection(
                      title: 'Based on your size',
                      meta: 'EU 42',
                      products: products(12),
                    ),
                    catalogGrid(products(20)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // NOT pumpAndSettle: the cards' image placeholders spin forever.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    // Drag to the end. A correction loop shows up here as an offset that never
    // arrives (each drag is partly undone before the next one).
    for (var i = 0; i < 60; i++) {
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
    }
    expect(
      position.pixels,
      moreOrLessEquals(position.maxScrollExtent, epsilon: 1.0),
      reason: 'the feed must be able to reach its last row',
    );

    // Idle frames: the offset must stay where the customer left it.
    final settled = position.pixels;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, settled);

    // And the other direction still scrolls.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pump();
    expect(position.pixels, lessThan(settled));

    expect(tester.takeException(), isNull);
  });
}
