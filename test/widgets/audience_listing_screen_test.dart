import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/audience_listing_screen.dart';
import 'package:app/widgets/sole_product_card.dart';

/// WCAG relative luminance — the dark-mode assertions measure legibility
/// rather than restating a token.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The ink the sort chip's label is painted in.
Color sortInk(WidgetTester tester) =>
    tester.widget<Text>(find.text('Featured')).style!.color!;

Color titleInk(WidgetTester tester, String title) =>
    tester.widget<Text>(find.text(title)).style!.color!;

/// The audience listing page — where a Home shelf chip (Men's / Women's /
/// Kids' / Unisex) goes.
///
/// What is pinned here: the page lists that shelf's products and no others, it
/// can be left again, its sort is local (a customer sorting a shelf must not
/// quietly re-sort Home), and an empty shelf explains itself rather than
/// rendering blank space.
Map<String, dynamic> product({
  required String id,
  required String name,
  String? audience,
  double price = 1000,
  double? salePrice,
  num? avgRating,
  int reviewCount = 0,
  String category = 'Sneakers',
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'sale_price': ?salePrice,
      'avg_rating': ?avgRating,
      'review_count': reviewCount,
      'images': <String>[],
      // Omitted when unset — the shape a NULL `audience` row arrives in.
      'audience': ?audience,
    };

/// The page under test at a given text scale.
///
/// The scale is applied with `copyWith` from *inside* the `MaterialApp`, i.e.
/// onto the real ambient data. Replacing the whole `MediaQueryData` with
/// `MediaQueryData(textScaler: …)` silently zeroes `size`, and this page opens a
/// modal bottom sheet whose height cap is `MediaQuery.size.height * 0.7` — so
/// the sheet would be laid out against a 0-tall screen and its last rows would
/// sit far below the viewport, which is exactly the kind of thing a test must
/// not be measuring by accident.
Widget wrap(
  ProductProvider provider, {
  String audience = 'men',
  double scale = 1.0,
}) =>
    ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: AudienceListingScreen(audience: audience),
          ),
        ),
      ),
    );

/// Product names in the grid, in DOM order.
List<String> gridNames(WidgetTester tester) => tester
    .widgetList<SoleProductCard>(find.byType(SoleProductCard))
    .map((c) => c.product['name'].toString())
    .toList();

void main() {
  testWidgets('lists that shelf only, and says how big it is', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'm2', name: 'Oxford', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'none', name: 'Legacy Pair'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    expect(find.text("Men's"), findsOneWidget);
    expect(find.text('2 pairs'), findsOneWidget);
    expect(gridNames(tester), containsAll(['Derby', 'Oxford']));
    expect(gridNames(tester), isNot(contains('Ballet Flat')));
    // An untagged product is not part of any shelf.
    expect(gridNames(tester), isNot(contains('Legacy Pair')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Unisex shelf holds the unisex products — the rail it cannot '
      'have', (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'u', name: 'House Slipper', audience: 'unisex'),
        product(id: 'u2', name: 'Plain Sandal', audience: 'unisex'),
        product(id: 'm', name: 'Derby', audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audience: 'unisex'));
    await tester.pump();

    expect(find.text('Unisex'), findsOneWidget);
    // A rail skips unisex (it would put the same card in three rails at once);
    // the shelf a customer chose on purpose is where they can be seen together.
    expect(gridNames(tester), containsAll(['House Slipper', 'Plain Sandal']));
    expect(gridNames(tester), isNot(contains('Derby')));
  });

  testWidgets('an empty shelf explains itself instead of rendering blank space',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'w', name: 'Ballet Flat', audience: 'women')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audience: 'kids'));
    await tester.pump();

    expect(find.text("Nothing in Kids' yet"), findsOneWidget);
    expect(find.text('Browse All Styles'), findsOneWidget);
    expect(find.byType(SoleProductCard), findsNothing);
    // The header count stays honest rather than disappearing with the grid.
    expect(find.text('0 pairs'), findsOneWidget);
  });

  testWidgets('sorting reorders the shelf and leaves the catalog sort alone',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [
        product(id: 'pricey', name: 'Oxford Deluxe', price: 3000, audience: 'men'),
        product(id: 'cheap', name: 'Oxford Basic', price: 900, audience: 'men'),
      ],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    await tester.tap(find.text('Featured'));
    // Two frames: one to start the sheet's transition, one to finish it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sort by'), findsOneWidget);

    await tester.tap(find.text('Price: Low to High'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(gridNames(tester), ['Oxford Basic', 'Oxford Deluxe']);
    expect(find.text('Price: Low to High'), findsOneWidget);
    // The page's sort is local — Home is untouched.
    expect(provider.sortMode, SortMode.featured);
    expect(provider.selectedCategory, 'All');
  });

  testWidgets('back returns the customer to the feed they came from',
      (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ProductProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AudienceListingScreen(audience: 'men'),
                    ),
                  ),
                  child: const Text('open shelf'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Plain pumps, not pumpAndSettle: the cards animate indefinitely (image
    // placeholders), so settling never completes.
    await tester.tap(find.text('open shelf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Men's"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    // Settling is safe once the cards are gone — it was the cards' own
    // indefinite animation that kept pumpAndSettle from finishing above.
    await tester.pumpAndSettle();

    expect(find.text('open shelf'), findsOneWidget);
    expect(find.byType(SoleProductCard), findsNothing);
  });

  /// The page paints from theme tokens, so both modes have to be measured —
  /// and the accent ink is the one token with a trap in it (see below).
  group('dual-brightness check', () {
    tearDown(AppBrightness.reset);

    testWidgets('the page surface and its ink follow the published brightness',
        (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'm', name: 'Derby', audience: 'men')],
        unitsSold: const {},
      );

      await tester.pumpWidget(wrap(provider));
      await tester.pump();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppPalette.light.page);
      expect(titleInk(tester, "Men's"), AppPalette.light.onPage);

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap(provider));
      await tester.pump();

      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppPalette.dark.page);
      expect(titleInk(tester, "Men's"), AppPalette.dark.onPage);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the accent ink clears AA on dark — the pinned brand clay does '
        'not', (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'm', name: 'Derby', audience: 'men')],
        unitsSold: const {},
      );

      await tester.pumpWidget(wrap(provider));
      await tester.pump();
      expect(sortInk(tester), AppPalette.light.primaryInk);
      expect(_contrast(sortInk(tester), AppPalette.light.page),
          greaterThanOrEqualTo(4.5));

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap(provider));
      await tester.pump();

      // The measured reason this uses `primaryInk` and not `AppConstants.primary`:
      // the brand clay is pinned, and at #8B5A2B it only manages ~3.3:1 on the
      // dark page — under AA for an 11px label. Token disagreement, settled by
      // arithmetic rather than taste.
      expect(_contrast(AppConstants.primary, AppPalette.dark.page),
          lessThan(4.5));
      expect(sortInk(tester), AppPalette.dark.primaryInk);
      expect(sortInk(tester), isNot(AppConstants.primary));
      expect(_contrast(sortInk(tester), AppPalette.dark.page),
          greaterThanOrEqualTo(4.5));
    });

    testWidgets('the empty state is legible on dark', (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'w', name: 'Ballet Flat', audience: 'women')],
        unitsSold: const {},
      );

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap(provider, audience: 'kids'));
      await tester.pump();

      expect(find.text("Nothing in Kids' yet"), findsOneWidget);
      final pillInk = tester
          .widget<Text>(find.text('Browse All Styles'))
          .style!
          .color!;
      expect(pillInk, AppPalette.dark.primaryInk);
      expect(_contrast(pillInk, AppPalette.dark.page),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('large text scale', () {
    /// Pumps the page at [scale] on a 320-wide phone by default. [size] is
    /// overridden by the one test that has to reach a sheet option first —
    /// driving a bottom sheet is not what is under test there.
    Future<void> pumpAt(
      WidgetTester tester,
      ProductProvider provider,
      double scale, {
      String audience = 'men',
      Size size = const Size(320, 640),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(provider, audience: audience, scale: scale));
      await tester.pump();
    }

    testWidgets('the header and grid survive it on a narrow phone',
        (tester) async {
      final provider = ProductProvider.seeded(
        products: [
          // Rated and sold, so the card's densest rows render too — the price
          // and category row is what overflowed here before it wrapped.
          product(
            id: 'm',
            name: 'Artisan Penny Loafer',
            audience: 'men',
            price: 1099.50,
            avgRating: 4.5,
            reviewCount: 12,
          ),
          // On sale, so the densest card (tape + two prices + rating row) is
          // what the scale is tested against, not the easy one.
          product(
            id: 'm2',
            name: 'Oxford',
            audience: 'men',
            price: 1899.0,
            salePrice: 1299.0,
            avgRating: 5.0,
            reviewCount: 3,
          ),
        ],
        unitsSold: const {'m': 1200},
      );

      for (final scale in const [1.3, 2.0]) {
        await pumpAt(tester, provider, scale);
        expect(find.text("Men's"), findsOneWidget,
            reason: 'header missing at ${scale}x');
        expect(find.text('2 pairs'), findsOneWidget);
        expect(find.byType(SoleProductCard), findsWidgets);
        expect(tester.takeException(), isNull,
            reason: 'overflow at ${scale}x');
      }
    });

    testWidgets('the empty-state pill wraps instead of overflowing',
        (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'w', name: 'Ballet Flat', audience: 'women')],
        unitsSold: const {},
      );

      for (final scale in const [1.3, 2.0]) {
        await pumpAt(tester, provider, scale, audience: 'kids');
        expect(find.text('Browse All Styles'), findsOneWidget,
            reason: 'pill missing at ${scale}x');
        expect(tester.takeException(), isNull,
            reason: 'overflow at ${scale}x');
      }
    });

    testWidgets('the longest sort label still fits the header', (tester) async {
      final provider = ProductProvider.seeded(
        products: [product(id: 'm', name: 'Derby', audience: 'men')],
        unitsSold: const {},
      );

      // Pick the longest label on a viewport tall enough to hold the whole sort
      // sheet at 2x, then shrink back to a phone. The page keeps its state
      // across the re-pump (same tree, same widget type), so what is measured
      // at the end is the HEADER holding 'Price: Low to High' at 2x — not an
      // off-screen sheet row, which is what a tap-without-scrolling would have
      // quietly asserted against.
      await pumpAt(tester, provider, 2.0, size: const Size(320, 1400));
      await tester.tap(find.text('Featured'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sort by'), findsOneWidget);
      await tester.tap(find.text('Price: Low to High'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sort by'), findsNothing,
          reason: 'the sheet should have closed on selection');
      expect(find.text('Price: Low to High'), findsOneWidget,
          reason: 'that text is now the chip');

      await pumpAt(tester, provider, 2.0);

      expect(find.text("Men's"), findsOneWidget);
      expect(find.text('Price: Low to High'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an unrecognised audience renders the empty state, never a '
      'default shelf', (tester) async {
    final provider = ProductProvider.seeded(
      products: [product(id: 'm', name: 'Derby', audience: 'men')],
      unitsSold: const {},
    );

    await tester.pumpWidget(wrap(provider, audience: 'Men'));

    await tester.pump();

    expect(find.byType(SoleProductCard), findsNothing);
    // No label exists for a non-canonical value, so the page says 'Shelf'
    // rather than claiming to be one it is not.
    expect(find.text('Nothing in Shelf yet'), findsOneWidget);
  });
}
