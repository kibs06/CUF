import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/horizontal_product_card.dart';
import 'package:app/widgets/press_sink.dart';
import 'package:app/widgets/sole_product_card.dart';

/// Both product cards rely on a 1px neutral hairline to draw their edge: the
/// card fill and the page are the SAME pure white, so the hairline is what
/// draws the boundary and [AppConstants.productCardShadow] is what makes the
/// tile read as raised rather than printed. These tests pin the border (colour,
/// 1px, solid), the lift, the rail card's no-inset THUMBNAIL geometry, and the
/// small inset its text keeps from that edge — all of them easy to regress
/// silently: a lighter colour, a `border` instead of a `foregroundDecoration`,
/// or a text block laid out flush left still compiles and still looks "fine".

/// Deliberately terse: the test font is Ahem (every glyph a full-size
/// square), so a long name or category overflows the price row.
Map<String, dynamic> product({String? saleEndsAt}) => {
  'id': 'p1',
  'name': 'Dress Boot',
  'category': 'Boots',
  'price': 1399.0,
  'review_count': 0,
  'images': <String>['https://example.com/a.jpg'],
  'sale_ends_at': saleEndsAt,
};

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Runs the press animation to its end. Deliberately not `pumpAndSettle`: the
/// card's image is loading behind a `CircularProgressIndicator`, which never
/// settles, so waiting for the whole tree to go quiet would time out on the
/// spinner instead of measuring the shadow.
Future<void> settlePress(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(PressSink.duration);
  await tester.pump(const Duration(milliseconds: 1));
}

/// The shadow the card is drawn with right now — read off the box `PressSink`
/// paints it on, which is the card's own parent: pre-order traversal hands it
/// back before any decorated box inside the card.
List<BoxShadow>? paintedShadow(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(PressSink),
      matching: find.byType(DecoratedBox),
    ),
  );
  for (final box in boxes) {
    final shadows = (box.decoration as BoxDecoration).boxShadow;
    if (shadows != null) return shadows;
  }
  return null;
}

Border borderOf(BoxDecoration? decoration) => decoration!.border! as Border;

void main() {
  group('SoleProductCard (grid card)', () {
    testWidgets('draws a 1px neutral hairline around the card surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          // Width only: with an imageAspectRatio the masonry card is
          // self-sizing (MainAxisSize.min), exactly as the grid uses it.
          SizedBox(
            width: 240,
            child: SoleProductCard(
              product: product(),
              imageAspectRatio: 1.0,
              onTap: () {},
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(SoleProductCard.hairlineKey),
      );
      final border = borderOf(container.decoration as BoxDecoration?);

      expect(border.top.width, 1);
      expect(border.top.style, BorderStyle.solid);
      expect(
        border.top.color,
        AppConstants.cardEdge,
        reason: 'the card edge must use the neutral hairline token',
      );
      expect(
        border.top.color,
        isNot(AppConstants.surfaceLight),
        reason: 'a border matching the white page fill is invisible',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('image corners stay concentric with the bordered card', (
      tester,
    ) async {
      // The image clip is the card radius less one — the 1px difference IS
      // the border's own inset, so the two corners stay concentric. Change one
      // without the other and the image corner visibly pokes out of the
      // hairline.
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 240,
            child: SoleProductCard(
              product: product(),
              imageAspectRatio: 1.0,
              onTap: () {},
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(SoleProductCard.hairlineKey),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, AppConstants.productCardRadius);

      final clipRadii = tester
          .widgetList<ClipRRect>(
            find.descendant(
              of: find.byKey(SoleProductCard.hairlineKey),
              matching: find.byType(ClipRRect),
            ),
          )
          .map((c) => c.borderRadius)
          .toList();
      expect(clipRadii, contains(AppConstants.productCardImageRadius));
      expect(tester.takeException(), isNull);
    });
  });

  group('the lift', () {
    testWidgets('the grid card sinks under a press and comes back up', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 240,
            child: SoleProductCard(
              product: product(),
              imageAspectRatio: 1.0,
              onTap: () {},
            ),
          ),
        ),
      );

      // The shadow is painted by `PressSink`, on the box directly under the
      // card — not by the card's own keyed Container.
      expect(AppConstants.productCardShadow, isNotEmpty);
      expect(paintedShadow(tester), AppConstants.productCardShadow);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SoleProductCard)),
      );
      await settlePress(tester);
      expect(
        paintedShadow(tester),
        AppConstants.productCardShadowPressed,
        reason: 'the finger is on the card — it must be sitting down',
      );

      await gesture.up();
      await settlePress(tester);
      expect(paintedShadow(tester), AppConstants.productCardShadow);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rail card takes the same lift and the same sink', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 180,
            child: HorizontalProductCard(product: product(), onTap: () {}),
          ),
        ),
      );

      expect(paintedShadow(tester), AppConstants.productCardShadow);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HorizontalProductCard)),
      );
      await settlePress(tester);
      expect(paintedShadow(tester), AppConstants.productCardShadowPressed);

      await gesture.up();
      await settlePress(tester);
      expect(paintedShadow(tester), AppConstants.productCardShadow);
    });

    test('the poster cards stay flat', () {
      // "Based on your size" and "See more" are both `FitCard`s, and the whole
      // point of the lift is that it marks the PRODUCTS: a shadow under a
      // poster whose type is the design reads as a floating label. A shadow
      // added inside `FitCard` would land on both of them at once, so the
      // contract is pinned at the source.
      final source = File('lib/widgets/fit_card.dart').readAsStringSync();
      expect(
        source.contains('boxShadow'),
        isFalse,
        reason: 'the poster cards must not pick up the product card lift',
      );
      expect(
        RegExp(r'elevation:\s*[1-9]').hasMatch(source),
        isFalse,
        reason:
            'a Material elevation on the poster is the same shadow by '
            'another name',
      );
    });
  });

  group('HorizontalProductCard (rail card)', () {
    testWidgets('wraps the photo, name and price in the same 1px card edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 180,
            child: HorizontalProductCard(product: product(), onTap: () {}),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(HorizontalProductCard.cardEdgeKey),
      );
      final border = borderOf(container.decoration as BoxDecoration?);

      expect(border.top.width, 1);
      expect(border.top.color, AppConstants.cardEdge);
      expect(
        container.foregroundDecoration,
        isNull,
        reason:
            'the whole rail card owns the edge now; the old thumbnail-only '
            'foreground ring was the source of the mismatch',
      );
    });

    testWidgets('the card edge insets the thumbnail by exactly its own width', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 180,
            child: HorizontalProductCard(product: product(), onTap: () {}),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Image)).width, 128);
      expect(tester.getSize(find.byType(Image)).height, 124);
    });

    testWidgets('the name and the price keep a gap from the card edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 180,
            child: HorizontalProductCard(product: product(), onTap: () {}),
          ),
        ),
      );

      final card = tester.getRect(
        find.byKey(HorizontalProductCard.cardEdgeKey),
      );
      final name = tester.getRect(find.text('Dress Boot'));
      final price = tester.getRect(find.text('₱1399.00'));

      // Flush left, the first glyph of each line sat on the 1px hairline itself.
      // The inset is a real gap on both sides, and the two lines share one left
      // edge — the padding goes around the block, not around one line of it.
      expect(
        name.left - card.left,
        // The inset plus the 1px hairline, which insets the card's content.
        moreOrLessEquals(HorizontalProductCard.textInset + 1, epsilon: 0.5),
      );
      expect(price.left, moreOrLessEquals(name.left, epsilon: 0.5));
      expect(card.right - name.right, greaterThanOrEqualTo(1));
      expect(card.right - price.right, greaterThanOrEqualTo(1));
    });

    testWidgets('a sale card keeps the same thumbnail geometry', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 180,
            child: HorizontalProductCard(
              product: product(
                saleEndsAt: DateTime.now()
                    .add(const Duration(days: 2))
                    .toIso8601String(),
              ),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Image)).width, 128);
      expect(find.byKey(HorizontalProductCard.cardEdgeKey), findsOneWidget);
    });
  });

  group('the corner', () {
    test('is the product family\'s own, tighter than the app card radius', () {
      // A feed of photographic tiles wants a corner that hugs the image; the
      // rest of the app's cards (auth, seller, sheets) keep the 16 they were
      // designed with, which is why this is its own token and not an edit to
      // `cardRadius`.
      expect(
        AppConstants.productCardCorner,
        lessThan(AppConstants.cardRadius.topLeft.x),
      );
    });

    test('the image clip sits exactly the hairline\'s 1px inside the card', () {
      // Same relationship the 16/15 pair had: the border insets its child by
      // 1px, so the clip has to come in by 1px too or the image's corner
      // pokes past the card's.
      expect(
        AppConstants.productCardImageRadius.topLeft.x,
        AppConstants.productCardCorner - 1,
      );
    });
  });
}
