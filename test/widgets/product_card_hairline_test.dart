import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/horizontal_product_card.dart';
import 'package:app/widgets/sole_product_card.dart';

/// Both product cards now rely on a 1px neutral hairline to draw their edge:
/// the card fill and the page are the SAME pure white, so without it the card
/// has no visible boundary. These tests pin the border (colour, 1px, solid)
/// and the rail card's no-inset geometry, because both are easy to regress
/// silently — a lighter colour or a `border` instead of a
/// `foregroundDecoration` still compiles and still looks "fine" on a photo.

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

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Border borderOf(BoxDecoration? decoration) => decoration!.border! as Border;

void main() {
  group('SoleProductCard (grid card)', () {
    testWidgets('draws a 1px neutral hairline around the card surface',
        (tester) async {
      await tester.pumpWidget(wrap(
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
      ));

      final container =
          tester.widget<Container>(find.byKey(SoleProductCard.hairlineKey));
      final border = borderOf(container.decoration as BoxDecoration?);

      expect(border.top.width, 1);
      expect(border.top.style, BorderStyle.solid);
      expect(border.top.color, AppConstants.borderGray,
          reason: 'the card edge must use the neutral hairline token');
      expect(border.top.color, isNot(AppConstants.surfaceLight),
          reason: 'a border matching the white page fill is invisible');
      expect(tester.takeException(), isNull);
    });

    testWidgets('image corners stay concentric with the bordered card',
        (tester) async {
      // The card radius is 16 and the image clip is 15 — the 1px difference
      // IS the border's own inset, so the two corners stay concentric. Change
      // one without the other and the image corner visibly pokes out of the
      // hairline.
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 240,
          child: SoleProductCard(
            product: product(),
            imageAspectRatio: 1.0,
            onTap: () {},
          ),
        ),
      ));

      final container =
          tester.widget<Container>(find.byKey(SoleProductCard.hairlineKey));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, AppConstants.cardRadius);

      final clipRadii = tester
          .widgetList<ClipRRect>(find.descendant(
            of: find.byKey(SoleProductCard.hairlineKey),
            matching: find.byType(ClipRRect),
          ))
          .map((c) => c.borderRadius)
          .toList();
      expect(
        clipRadii,
        contains(const BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        )),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('HorizontalProductCard (rail card)', () {
    testWidgets('rings the thumbnail with the same 1px neutral hairline',
        (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          height: 180,
          child: HorizontalProductCard(product: product(), onTap: () {}),
        ),
      ));

      final container = tester
          .widget<Container>(find.byKey(HorizontalProductCard.thumbnailHairlineKey));
      final border = borderOf(container.foregroundDecoration as BoxDecoration?);

      expect(border.top.width, 1);
      expect(border.top.color, AppConstants.borderGray);
      expect(container.decoration, isNull,
          reason: 'a background border would inset the child and break the '
              '130x180 rail contract — it must be a foregroundDecoration');
    });

    testWidgets('the hairline does not resize the 130x124 thumbnail',
        (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          height: 180,
          child: HorizontalProductCard(product: product(), onTap: () {}),
        ),
      ));

      expect(tester.getSize(find.byType(Image)).width, 130);
      expect(tester.getSize(find.byType(Image)).height, 124);
    });

    testWidgets('a sale card keeps the same thumbnail geometry',
        (tester) async {
      await tester.pumpWidget(wrap(
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
      ));

      expect(tester.getSize(find.byType(Image)).width, 130);
      expect(find.byKey(HorizontalProductCard.thumbnailHairlineKey),
          findsOneWidget);
    });
  });
}
