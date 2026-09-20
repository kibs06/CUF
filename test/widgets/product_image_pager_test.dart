import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/product_image_pager.dart';

/// The card's photo area. What matters is that it is a *photo browser* and not a
/// second tap target: a swipe must page the photos, and a tap must still reach
/// the card underneath and open the product — which is what the ancestor
/// `GestureDetector` here stands in for.
Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 180, height: 180, child: child)),
  ),
);

const List<String> twoPhotos = [
  'https://example.com/one.jpg',
  'https://example.com/two.jpg',
];
const List<String> threePhotos = [
  ...twoPhotos,
  'https://example.com/three.jpg',
];

/// The page the pager is resting on, read off the controller the pager built.
double currentPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

/// A drag far enough to snap to the next page, then the time its ballistic
/// phase needs. Deliberately not `pumpAndSettle`: the photos load behind a
/// `CircularProgressIndicator`, which never settles.
Future<void> swipeForward(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-180, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('a product with one photo has no dots and does not move', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const ProductImagePager(images: ['a.jpg'])));

    expect(find.byKey(ProductImagePager.dotsKey), findsNothing);

    await swipeForward(tester);
    expect(currentPage(tester), moreOrLessEquals(0, epsilon: 0.01));
  });

  testWidgets('one dot per photo, the current one widened into a pill', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const ProductImagePager(images: threePhotos)));

    expect(find.byKey(ProductImagePager.dotsKey), findsOneWidget);
    for (var index = 0; index < threePhotos.length; index++) {
      expect(
        find.byKey(ValueKey('product-image-dot-$index')),
        findsOneWidget,
        reason: 'every photo gets a mark',
      );
    }

    expect(
      tester.getSize(find.byKey(const ValueKey('product-image-dot-0'))).width,
      ProductImagePager.activeDotWidth,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('product-image-dot-1'))).width,
      ProductImagePager.dotSize,
    );
  });

  testWidgets('a swipe pages the photos and the dots follow', (tester) async {
    await tester.pumpWidget(wrap(const ProductImagePager(images: threePhotos)));

    await swipeForward(tester);
    expect(currentPage(tester), moreOrLessEquals(1, epsilon: 0.01));
    expect(
      tester.getSize(find.byKey(const ValueKey('product-image-dot-1'))).width,
      ProductImagePager.activeDotWidth,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('product-image-dot-0'))).width,
      ProductImagePager.dotSize,
    );

    await swipeForward(tester);
    expect(currentPage(tester), moreOrLessEquals(2, epsilon: 0.01));
  });

  testWidgets('a tap on the photo still reaches the card underneath', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        GestureDetector(
          onTap: () => taps++,
          child: const ProductImagePager(images: threePhotos),
        ),
      ),
    );

    await tester.tap(find.byType(PageView));
    await tester.pump();
    expect(taps, 1);

    // And it is a tap, not a page change: opening the product must never look
    // like a swipe the customer did not make.
    expect(currentPage(tester), moreOrLessEquals(0, epsilon: 0.01));
  });

  testWidgets('the dots stack above the band rather than over it', (
    tester,
  ) async {
    const band = SizedBox(
      key: Key('test-band'),
      height: 20,
      width: double.infinity,
      child: ColoredBox(color: Colors.amber),
    );

    await tester.pumpWidget(
      wrap(const ProductImagePager(images: threePhotos, bottomOverlay: band)),
    );

    final pager = tester.getRect(find.byType(ProductImagePager));
    final dots = tester.getRect(find.byKey(ProductImagePager.dotsKey));
    final bandRect = tester.getRect(find.byKey(const Key('test-band')));

    expect(
      dots.bottom,
      lessThanOrEqualTo(bandRect.top),
      reason: 'the sale band owns the bottom edge; the dots sit on top of it',
    );
    expect(
      bandRect.bottom,
      moreOrLessEquals(pager.bottom, epsilon: 0.5),
      reason: 'the band still reaches the photo\'s bottom edge',
    );
  });

  testWidgets('a single photo with a band shows the band and no dots', (
    tester,
  ) async {
    const band = SizedBox(
      key: Key('test-band'),
      height: 20,
      width: double.infinity,
      child: ColoredBox(color: Colors.amber),
    );

    await tester.pumpWidget(
      wrap(const ProductImagePager(images: ['a.jpg'], bottomOverlay: band)),
    );

    expect(find.byKey(ProductImagePager.dotsKey), findsNothing);
    expect(find.byKey(const Key('test-band')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
