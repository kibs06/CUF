import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/widgets/product_image_pager.dart';
import 'package:app/widgets/sale_countdown_overlay.dart';
import 'package:app/widgets/sole_product_card.dart';

const String _one = 'https://example.com/one.jpg';
const String _two = 'https://example.com/two.jpg';
const String _three = 'https://example.com/three.jpg';

/// A card-shaped product map. The photos arrive the way the mapped model hands
/// them over: a flat `images` list in the seller's order.
Map<String, dynamic> product({
  List<String> images = const [_one, _two, _three],
  String? saleEndsAt,
}) => {
  'id': 'p1',
  'name': 'Dress Boot',
  'category': 'Boots',
  'price': 1399.0,
  if (saleEndsAt != null) 'sale_price': 999.0,
  'sale_ends_at': saleEndsAt,
  'review_count': 0,
  'images': images,
};

/// The card at the width of a grid cell, self-sizing the way the masonry uses
/// it (no `imageAspectRatio` here: the image is the `Expanded` half).
Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 240, height: 300, child: child)),
  ),
);

/// A sideways drag on the photo, then the time its ballistic phase needs.
/// Deliberately not `pumpAndSettle`: the photo loads behind a
/// `CircularProgressIndicator`, which never settles.
Future<void> swipe(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-180, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    // The shared one-second ticker must never leak into the next test.
    SaleCountdownTicker.instance.debugReset();
  });

  testWidgets('a product with several photos offers the swipe, and says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(SoleProductCard(product: product(), onTap: () {})),
    );

    expect(find.byKey(ProductImagePager.dotsKey), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      expect(find.byKey(ValueKey('product-image-dot-$index')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a product with one photo has nothing to swipe', (tester) async {
    await tester.pumpWidget(
      wrap(
        SoleProductCard(
          product: product(images: const [_one]),
          onTap: () {},
        ),
      ),
    );

    expect(find.byKey(ProductImagePager.dotsKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping the photo browses the photos, and does NOT open it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(SoleProductCard(product: product(), onTap: () => taps++)),
    );

    await swipe(tester);

    final page = tester
        .widget<PageView>(find.byType(PageView))
        .controller!
        .page!;
    expect(page, moreOrLessEquals(1, epsilon: 0.01));
    expect(taps, 0, reason: 'a swipe is a preview, not a purchase decision');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the photo still opens the product', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(SoleProductCard(product: product(), onTap: () => taps++)),
    );

    await tester.tap(find.byType(PageView));
    await tester.pump();

    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the swipe dots sit above the sale countdown band', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SoleProductCard(
          product: product(
            saleEndsAt: DateTime.now()
                .add(const Duration(days: 2))
                .toIso8601String(),
          ),
          onTap: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('sale-countdown-band')), findsOneWidget);

    final pager = tester.getRect(find.byType(ProductImagePager));
    final dots = tester.getRect(find.byKey(ProductImagePager.dotsKey));
    final band = tester.getRect(find.byKey(const Key('sale-countdown-band')));

    // The band keeps the photo's bottom edge — the card's own contract — and
    // the dots are stacked above it rather than dropped on top of the text.
    expect(dots.bottom, lessThanOrEqualTo(band.top));
    expect(band.bottom, moreOrLessEquals(pager.bottom, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });
}
