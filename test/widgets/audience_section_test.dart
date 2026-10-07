import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/utils/product_audience.dart';
import 'package:app/screens/customer/audience_listing_screen.dart';
import 'package:app/widgets/audience_section.dart';
import 'package:app/widgets/product_image_pager.dart';
import 'package:app/widgets/product_section_header.dart';
import 'package:app/widgets/sole_product_card.dart';
import 'package:app/widgets/two_column_masonry.dart';

/// The Men's / Women's / Kids' home sections — the first customer-facing surface
/// of the product-audience feature, and (since 2026-10-06) one row of them.
///
/// The rules pinned here are the ones that would be silent if they broke:
/// per-section isolation, `unisex` in NO section (the same card three times down
/// the feed), an unset product staying in the catalog grid while staying out of
/// the sections, one photo per row inside a narrow column and two inside a wide
/// one, and the row never leaving a blank column for an audience that has
/// nothing. The kill switch is ON in production, but the OFF case is still pinned
/// by passing `enabled: false` deliberately — see [AudienceSection.enabled].
Map<String, dynamic> product({
  required String id,
  required String name,
  String? audience,
}) {
  return {
    'id': id,
    'name': name,
    'category': 'Sneakers',
    'price': 1000,
    'images': <String>[],
    // Omitted when unset — the shape a NULL `audience` row arrives in.
    'audience': ?audience,
    'inventory': [
      {'size': 'EU 42', 'stock': 3},
    ],
  };
}

/// The sections **stacked**, one per audience — the shape this widget had before
/// the audience row, kept because it is still how a lone section is read: one
/// audience across the whole page.
///
/// The three sections in their fixed home-feed order, optionally followed by the
/// catalog grid's rows (a plain text stand-in for `SoleProductCard`, so the
/// assertion is about *which feed the product is in* rather than about card
/// rendering).
Widget wrap(
  ProductProvider provider, {
  List<String> audiences = productRailAudiences,
  bool showCatalog = false,
  bool enabled = true,
  double textScale = 1.0,
}) {
  return ChangeNotifierProvider<ProductProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final audience in audiences)
                    AudienceSection(audience: audience, enabled: enabled),
                  if (showCatalog)
                    for (final p in provider.getFilteredProducts(''))
                      Text(p['name'].toString()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The row as the home feed actually renders it: `AudienceSections` and nothing
/// else, so every assertion below is about the arrangement rather than about a
/// harness that stands in for it.
Widget wrapRow(ProductProvider provider, {bool enabled = true}) =>
    ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AudienceSections(enabled: enabled)),
        ),
      ),
    );

/// A phone-shaped surface, in logical pixels, for the row's own measurements.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder sectionOf(String audience) => find.byWidgetPredicate(
      (w) => w is AudienceSection && w.audience == audience,
    );

/// The tiles in one section, in DOM order.
Finder tilesIn(String audience) => find.descendant(
      of: sectionOf(audience),
      matching: find.byType(SoleProductCard),
    );

/// The rectangle of every tile in one section, in DOM order.
List<Rect> tileRects(WidgetTester tester, String audience) {
  final finder = tilesIn(audience);
  return [
    for (var i = 0; i < tester.widgetList<SoleProductCard>(finder).length; i++)
      tester.getRect(finder.at(i)),
  ];
}

/// Product names carried by one section's tiles, in DOM order.
///
/// Read off the CARD rather than off rendered text, because the tiles deliberately
/// draw no name at all — the image-only assertion below is that same absence.
List<String> namesInSection(WidgetTester tester, String audience) => tester
    .widgetList<SoleProductCard>(tilesIn(audience))
    .map((c) => c.product['name'].toString())
    .toList();

const double _gutter = AppConstants.productGridGutter;
const double _margin = AppConstants.feedMargin;

void main() {
  test('the tile-count rule is "two" only when two cards still fit', () {
    // The breakpoint is the protected minimum doubled, plus the seam between
    // them — stated that way so the test moves with the number it protects.
    final twoFit = kAudienceTileMinWidth * 2 + _gutter;

    expect(audienceTileColumnsFor(twoFit), 2);
    expect(audienceTileColumnsFor(twoFit + 1), 2);
    expect(audienceTileColumnsFor(twoFit - 0.5), 1,
        reason: 'half a pixel short is one tile per row, not two squeezed ones');
    expect(audienceTileColumnsFor(0), 1);
    expect(audienceTileColumnsFor(119), 1,
        reason: 'a third of a phone — the audience row on the small screen');
    expect(audienceTileColumnsFor(374), 2,
        reason: 'a phone, one audience across the page');
  });

  testWidgets('each section shows only its own audience', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Men's"), findsOneWidget);
    expect(find.text("Women's"), findsOneWidget);
    expect(find.text("Kids'"), findsOneWidget);

    expect(namesInSection(tester, 'men'), ['Derby']);
    expect(namesInSection(tester, 'women'), ['Ballet Flat']);
    expect(namesInSection(tester, 'kids'), ['School Shoe']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the labels come from the shared vocabulary, in fixed order',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    // Labels are productAudienceLabel's, not strings typed into the widget.
    for (final audience in productRailAudiences) {
      expect(find.text(productAudienceLabel(audience)!), findsOneWidget);
    }
    // Fixed order: each section's header is below the previous one's when the
    // sections are stacked.
    final menY = tester.getTopLeft(find.text("Men's")).dy;
    expect(menY, lessThan(tester.getTopLeft(find.text("Women's")).dy));
    expect(tester.getTopLeft(find.text("Women's")).dy,
        lessThan(tester.getTopLeft(find.text("Kids'")).dy));
  });

  testWidgets('a unisex product appears in none of the three sections',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'any', name: 'House Slipper', audience: 'unisex')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    for (final audience in productRailAudiences) {
      expect(namesInSection(tester, audience), isEmpty,
          reason: 'unisex must stay out of the $audience section');
    }
    // Nothing left behind at all — not even a header.
    expect(find.byType(SoleProductCard), findsNothing);
    expect(find.byType(ProductSectionHeader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unset product stays out of the sections but keeps its place in '
      'the catalog grid', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'legacy', name: 'Legacy Pair'),
        product(id: 'm', name: 'Derby', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, showCatalog: true));
    await tester.pump(const Duration(milliseconds: 300));

    // In a section? No.
    for (final audience in productRailAudiences) {
      expect(namesInSection(tester, audience), isNot(contains('Legacy Pair')));
    }
    expect(namesInSection(tester, 'men'), ['Derby']);

    // Still in the catalog grid? Yes — this is the regression the phase must
    // not cause, asserted rather than assumed.
    expect(find.text('Legacy Pair'), findsOneWidget);
  });

  testWidgets('a section with nothing to show renders nothing — no header, and '
      'no gap where it would have been', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'w', name: 'Ballet Flat', audience: 'women')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Men's"), findsNothing);
    expect(find.text("Kids'"), findsNothing);
    // A hidden section occupies nothing and leaves no strip behind.
    expect(tester.getSize(sectionOf('men')), Size.zero);
    expect(tester.getSize(sectionOf('kids')), Size.zero);
    expect(find.byType(SoleProductCard), findsOneWidget);

    // ...and the surviving section is exactly as tall as it is on its own, so
    // the two hidden sections contributed no spacing.
    final withHidden = tester.getSize(sectionOf('women'));
    await tester.pumpWidget(wrap(provider, audiences: const ['women']));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(sectionOf('women')), withHidden);
  });

  testWidgets('with the kill switch off nothing renders, even with matches',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
      ],
      unitsSold: const {},
    );

    // `enabled: false` is the rollback: one constant flip and every section
    // behaves as though it does not exist.
    await tester.pumpWidget(wrap(provider, enabled: false));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProductSectionHeader), findsNothing);
    expect(find.byType(SoleProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an audience that is not a section renders nothing', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    await tester.pumpWidget(
      wrap(provider, audiences: const ['unisex', 'nonsense']),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SoleProductCard), findsNothing);
    expect(find.text('Unisex'), findsNothing);
  });

  testWidgets('header survives a narrow phone at a large text scale',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    useSurface(tester, const Size(320, 640));

    // The scale is copied onto the real ambient data rather than replacing it:
    // `MediaQueryData(textScaler: …)` zeroes `size` and every other field, which
    // would make any size-dependent layout meaningless here.
    await tester.pumpWidget(
      wrap(provider, textScale: 1.3),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Men's"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile is the photo alone — no name, no price, no rating',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audiences: const ['men']));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tilesIn('men'), findsOneWidget);
    expect(tester.widget<SoleProductCard>(tilesIn('men')).imageOnly, isTrue);

    // The name and the price are the card's caption, and the caption is gone.
    // This is the whole difference between a door and a listing.
    final drawn = tester
        .widgetList<Text>(
          find.descendant(of: sectionOf('men'), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .toList();
    expect(drawn, isNot(contains('Derby')),
        reason: 'an image-only tile must not draw the product name');
    expect(drawn, isNot(contains('₱1000.00')),
        reason: 'an image-only tile must not draw the price');

    // ...and nothing is left RESERVED for a caption either. The card is its
    // photo, give or take the 1px hairline each side — a tile that merely hid
    // the words would still show an empty band under every photograph.
    final tile = tester.getRect(tilesIn('men'));
    final photo = tester.getRect(find.descendant(
      of: tilesIn('men'),
      matching: find.byType(ProductImagePager),
    ));
    expect(tile.width - photo.width, lessThanOrEqualTo(2),
        reason: 'the photo spans the card');
    expect(tile.height - photo.height, lessThanOrEqualTo(2),
        reason: 'no band is reserved under the photo for a caption');
    expect(find.byKey(const ValueKey('product_info_m')), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile draws no words, so it says what it is out loud',
      (tester) async {
    final handle = tester.ensureSemantics();

    final provider = ProductProvider.seeded(
      products: [
        for (var i = 0; i < 6; i++)
          product(id: 'm$i', name: 'Derby $i', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audiences: const ['men']));
    await tester.pump(const Duration(milliseconds: 300));

    // Six on the shelf, four doors to it — and every door is named. Four
    // buttons under one identical label would be four buttons a screen reader
    // cannot choose between, which is why the index is in the label.
    for (final i in const [1, 2, 3, 4]) {
      expect(find.bySemanticsLabel("See the Men's shelf, $i of 4"),
          findsOneWidget,
          reason: 'tile $i of 4 is unnamed');
    }
    expect(find.bySemanticsLabel("See the Men's shelf, 5 of 4"), findsNothing);

    // And nothing promises the product whose photo it is: the tile opens the
    // shelf, so the name is not announced either.
    expect(find.bySemanticsLabel('Derby 0'), findsNothing);

    // Disposed in the body rather than through addTearDown: the framework
    // asserts no handle is left open when the test ends, and that check runs
    // before a tearDown does. Same shape as see_more_card_test.dart.
    handle.dispose();
  });

  testWidgets('the section stops at four tiles, whatever the shelf holds',
      (tester) async {
    expect(kAudiencePreviewCount, 4);

    final provider = ProductProvider.seeded(
      products: [
        for (var i = 0; i < 9; i++)
          product(id: 'm$i', name: 'Derby $i', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audiences: const ['men']));
    await tester.pump(const Duration(milliseconds: 300));

    expect(namesInSection(tester, 'men').length, kAudiencePreviewCount,
        reason: 'nine on the shelf, four in the preview');
  });

  testWidgets('tapping a tile opens that audience shelf, not the product page',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audiences: const ['men']));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(tilesIn('men'));

    // Pump rather than pumpAndSettle: a card's photo is a `CachedNetworkImage`
    // whose placeholder is a `CircularProgressIndicator`, which animates for as
    // long as the image is unresolved — and in a widget test it never resolves.
    // Settling is therefore impossible anywhere a product card is on screen, so
    // this file pumps the route transition by hand (as every test above does).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(AudienceListingScreen), findsOneWidget);
    expect(
      tester.widget<AudienceListingScreen>(find.byType(AudienceListingScreen)).audience,
      'men',
    );
  });

  // ── The shape of a column: two across, or one ──

  testWidgets('a wide column lays its photos two across', (tester) async {
    useSurface(tester, const Size(800, 600));

    final provider = ProductProvider.seeded(
      products: [
        for (var i = 0; i < 4; i++)
          product(id: 'm$i', name: 'Derby $i', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audiences: const ['men']));
    await tester.pump(const Duration(milliseconds: 300));

    // 784px of column is room for two 150px cards and the seam between them.
    expect(find.byType(TwoColumnMasonry), findsOneWidget);

    final rects = tileRects(tester, 'men');
    expect(rects, hasLength(4));
    expect(rects[1].top, moreOrLessEquals(rects[0].top, epsilon: 0.5),
        reason: 'the second photo sits beside the first, not under it');
    expect(rects[1].left, greaterThan(rects[0].right - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow column stacks its photos instead', (tester) async {
    // A third of a phone: the audience row's own column width.
    useSurface(tester, const Size(390, 844));

    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm0', name: 'Derby', audience: 'men'),
        product(id: 'w0', name: 'Ballet Flat', audience: 'women'),
        for (var i = 0; i < 3; i++)
          product(id: 'm${i + 1}', name: 'Loafer $i', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider));
    await tester.pump(const Duration(milliseconds: 300));

    // Two cards side by side would be ~55px each here, so the section does not
    // try: every photo gets the whole column.
    expect(find.byType(TwoColumnMasonry), findsNothing);

    final rects = tileRects(tester, 'men');
    expect(rects, hasLength(4));
    for (final rect in rects) {
      expect(rect.left, moreOrLessEquals(rects.first.left, epsilon: 0.5),
          reason: 'one photo per row, all on the same left edge');
      expect(rect.width, moreOrLessEquals(rects.first.width, epsilon: 0.5));
    }
    expect(rects[1].top, greaterThan(rects[0].bottom),
        reason: 'stacked, not beside');
    expect(tester.takeException(), isNull);
  });

  // ── The row itself ──

  testWidgets('three audiences with products stand side by side, in order',
      (tester) async {
    useSurface(tester, const Size(390, 844));

    final provider = ProductProvider.seeded(
      products: [
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider));
    await tester.pump(const Duration(milliseconds: 300));

    final men = tester.getTopLeft(find.text("Men's"));
    final women = tester.getTopLeft(find.text("Women's"));
    final kids = tester.getTopLeft(find.text("Kids'"));

    // One row: three headings at the same height, left to right in the fixed
    // order — not three stacked sections.
    expect(women.dy, moreOrLessEquals(men.dy, epsilon: 0.5));
    expect(kids.dy, moreOrLessEquals(men.dy, epsilon: 0.5));
    expect(men.dx, lessThan(women.dx));
    expect(women.dx, lessThan(kids.dx));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the columns are equal and fill the page, gutters included',
      (tester) async {
    useSurface(tester, const Size(390, 844));

    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider));
    await tester.pump(const Duration(milliseconds: 300));

    final men = tester.getRect(sectionOf('men'));
    final women = tester.getRect(sectionOf('women'));
    final kids = tester.getRect(sectionOf('kids'));

    expect(women.width, moreOrLessEquals(men.width, epsilon: 0.5));
    expect(kids.width, moreOrLessEquals(men.width, epsilon: 0.5));

    // The number itself, so a change to the margin, the gutter or the column
    // count cannot pass by being "still equal to each other".
    expect(men.width,
        moreOrLessEquals((390 - 2 * _margin - 2 * _gutter) / 3, epsilon: 0.5));

    // The page margin is the row's, and the seam between two columns is the
    // grid's own gutter — so the row closes flush with the feed either side.
    expect(men.left, moreOrLessEquals(_margin, epsilon: 0.5));
    expect(women.left - men.right, moreOrLessEquals(_gutter, epsilon: 0.5));
    expect(kids.left - women.right, moreOrLessEquals(_gutter, epsilon: 0.5));
    expect(kids.right, moreOrLessEquals(390 - _margin, epsilon: 0.5));
  });

  testWidgets('a heading sits over its own column, inset like its photos',
      (tester) async {
    useSurface(tester, const Size(390, 844));

    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider));
    await tester.pump(const Duration(milliseconds: 300));

    // The header's inset is 0 inside the row (the row already carries the page
    // margin), so a heading starts on the same edge as the photos under it.
    // Without that it would sit 8px further in than its own column.
    final heading = tester.getTopLeft(find.text("Men's"));
    final firstTile = tester.getTopLeft(tilesIn('men'));
    expect(heading.dx, moreOrLessEquals(firstTile.dx, epsilon: 1.5));
    expect(heading.dy, lessThan(firstTile.dy));
  });

  testWidgets('an audience with nothing leaves no blank column behind',
      (tester) async {
    useSurface(tester, const Size(390, 844));

    // Kids' has no products — its state in the live catalog — so the row has two
    // columns, not three with a hole where the third would be.
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Kids'"), findsNothing);

    final men = tester.getRect(sectionOf('men'));
    final women = tester.getRect(sectionOf('women'));

    // Not merely zero-sized: there is no third column in the tree at all, so
    // nothing can be reserving its width.
    expect(sectionOf('kids'), findsNothing);

    // Two columns share the whole width: the survivors grow into the space the
    // absent column would have taken.
    expect(men.left, moreOrLessEquals(_margin, epsilon: 0.5));
    expect(women.right, moreOrLessEquals(390 - _margin, epsilon: 0.5));
    expect(women.left - men.right, moreOrLessEquals(_gutter, epsilon: 0.5));

    // Two columns share what three would have split, which is the whole reason
    // an absent audience leaves nothing behind: 183px here, the width of a
    // catalog card — and because the column is too narrow to pair tiles, each
    // photo is that full width rather than half of it.
    final expected = (390 - 2 * _margin - _gutter) / 2;
    expect(men.width, moreOrLessEquals(expected, epsilon: 0.5));
    expect(tileRects(tester, 'men').first.width,
        moreOrLessEquals(expected, epsilon: 1.5));
  });

  testWidgets('the row is nothing at all when no audience has anything',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'legacy', name: 'Legacy Pair'),
        product(id: 'any', name: 'House Slipper', audience: 'unisex'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getSize(find.byType(AudienceSections)), Size.zero);
    expect(find.byType(SoleProductCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the row obeys the kill switch on its own', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrapRow(provider, enabled: false));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getSize(find.byType(AudienceSections)), Size.zero);
    expect(find.byType(SoleProductCard), findsNothing);
  });

  test('the home feed renders the row, and the row owns the order', () {
    // A widget test cannot stand up `CustomerHomeScreen` — it needs the auth,
    // product, banner, cart and message providers plus Supabase — so the wiring
    // that exists ONLY there is pinned at the source, the same move
    // `workshop_collection_card_test.dart` makes for the collection card. Without
    // this, dropping the row from the feed would break nothing in any test.
    final home =
        File('lib/screens/customer/customer_home_screen.dart').readAsStringSync();

    expect(
      home.contains('const AudienceSections(),'),
      isTrue,
      reason: 'the feed must render the audience row',
    );
    expect(
      home.contains('for (final audience in productRailAudiences)'),
      isFalse,
      reason: 'the feed no longer lays the audiences out itself — the order, '
          'the unisex exclusion and the geometry belong to AudienceSections',
    );

    // And the row really does read the shared list, so the fixed order and the
    // `unisex` exclusion are still decided in one place.
    final widget =
        File('lib/widgets/audience_section.dart').readAsStringSync();
    expect(widget.contains('productRailAudiences'), isTrue,
        reason: 'the row iterates the one list that fixes the order');
    expect(widget.contains('audiencesInCatalog'), isTrue,
        reason: 'and asks the provider which audiences are here in its own '
            'single pass, rather than re-filtering the catalog per audience');
  });

  group('dual-brightness check', () {
    tearDown(AppBrightness.reset);

    testWidgets('the header ink follows the published brightness',
        (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'm', name: 'Derby', audience: 'men')],
        unitsSold: const {},
      );

      await tester.pumpWidget(wrap(provider));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.text("Men's")).style!.color,
          AppPalette.light.onPage);

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap(provider));
      await tester.pump(const Duration(milliseconds: 300));
      // Same token, dark role — no theme lookup in the section, and no mode where
      // the title renders in light-mode ink on a dark page.
      expect(tester.widget<Text>(find.text("Men's")).style!.color,
          AppPalette.dark.onPage);
      expect(tester.takeException(), isNull);
    });
  });
}
