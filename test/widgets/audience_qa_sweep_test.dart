import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/screens/customer/audience_listing_screen.dart';
import 'package:app/screens/customer/widgets/home_category_row.dart';
import 'package:app/utils/product_audience.dart';
import 'package:app/widgets/audience_section.dart';

/// **P5's device-variation sweep** over the new customer-visible audience
/// surfaces: the home rails, the shelf chips, and a shelf page.
///
/// Every configuration below is the same assertion — nothing overflows, nothing
/// is clipped, and the surface is actually still readable at that size — run
/// across the matrix a real customer's device can land in. It is written as a
/// loop over data rather than one test per combination so the coverage is
/// visible and gaps are obvious: add a size to [_sizes] and every surface and
/// mode is exercised at it.
///
/// Two things this file deliberately does NOT claim:
///
///  * **The product page's size-label area is not swept here.** That screen
///    cannot be instantiated in a widget test — its `initState` reaches
///    `Supabase.instance` (uninitialized in tests) and it needs three
///    providers — so its layout at these configurations remains a device check.
///    What the label side *can* verify is its values, which
///    `audience_end_to_end_test.dart` does across every audience and shopper.
///    See the phase report; this is a testability limit, not a pass.
///  * **Nothing here is a golden test.** No goldens exist in this codebase
///    (device fonts differ), so "no overflow" is asserted the way the rest of
///    the suite does it: `tester.takeException()` plus the text still being
///    findable.
const _sizes = <String, Size>{
  'narrow phone (portrait)': Size(320, 640),
  'phone (landscape)': Size(640, 360),
  'tablet (landscape)': Size(1280, 800),
};

const _modes = <String, Brightness>{
  'light': Brightness.light,
  'dark': Brightness.dark,
};

const _scales = <String, double>{'1.0': 1.0, '1.3': 1.3};

Map<String, dynamic> product({
  required String id,
  required String name,
  String? audience,
}) =>
    {
      'id': id,
      'name': name,
      'category': 'Sneakers',
      'price': 1099.50,
      'avg_rating': 4.5,
      'review_count': 12,
      'images': <String>[],
      'audience': ?audience,
    };

/// The catalog every surface in this file renders: one product per audience,
/// plus an unset row, so a rail header, a chip and a grid are all populated.
ProductProvider seed() => ProductProvider.seeded(
      products: [
        product(id: 'm', name: 'Derby', audience: 'men'),
        product(id: 'w', name: 'Ballet Flat', audience: 'women'),
        product(id: 'k', name: 'School Shoe', audience: 'kids'),
        product(id: 'u', name: 'House Slipper', audience: 'unisex'),
        product(id: 'x', name: 'Legacy Loafer'),
      ],
      unitsSold: const {'m': 40, 'w': 30, 'k': 20, 'u': 10},
    );

/// Applies a configuration to the test view and the ambient MediaQuery.
///
/// The scale is copied onto the real data (`copyWith`), never substituted
/// wholesale: replacing `MediaQueryData` zeroes `size`, which would make every
/// size-dependent layout in this sweep meaningless.
void configure(
  WidgetTester tester,
  Size size,
  Brightness brightness,
  double scale,
) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppBrightness.set(brightness);
}

Widget host(Widget child, double scale) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child,
        ),
      ),
    );

/// The sweep: every surface × every configuration.
void sweep(
  String surfaceName,
  Widget Function(ProductProvider provider) build,
  List<Finder> expectations,
) {
  for (final size in _sizes.entries) {
    for (final mode in _modes.entries) {
      for (final scale in _scales.entries) {
        testWidgets(
            '$surfaceName · ${size.key} · ${mode.key} · ${scale.key}x',
            (tester) async {
          configure(tester, size.value, mode.value, scale.value);
          final provider = seed();

          await tester.pumpWidget(host(
            Builder(builder: (_) => build(provider)),
            scale.value,
          ));
          await tester.pump(const Duration(milliseconds: 300));

          for (final expectation in expectations) {
            expect(expectation, findsWidgets,
                reason: '$surfaceName lost content at ${size.key}, '
                    '${mode.key}, ${scale.key}x');
          }
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${size.key}, ${mode.key}, ${scale.key}x');
        });
      }
    }
  }
}

void main() {
  tearDown(AppBrightness.reset);

  sweep(
    'audience rail',
    (provider) => ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final audience in productRailAudiences)
                AudienceSection(audience: audience, enabled: true),
            ],
          ),
        ),
      ),
    ),
    [find.text("Men's"), find.text("Women's"), find.text("Kids'")],
  );

  sweep(
    'home shelf chips',
    (provider) => ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: Scaffold(
        backgroundColor: Colors.black,
        // `audienceChipsEnabled: true` pinned, exactly as the rails pin
        // `enabled: true`: this sweep is about layout across device
        // configurations, and a sweep whose content depends on the feature
        // switch silently stops sweeping anything the day the switch is off.
        // (It did — this assertion failed under the P5 rollback check, which is
        // how the implicit dependency was found. The switch's own behaviour,
        // both on and off, is asserted in `home_category_row_test.dart`.)
        body: HomeCategoryRow(
          categories: const ['All', 'Casual', 'Formal'],
          selectedCategory: 'All',
          onSelect: (_) {},
          audiences: const ['men', 'women', 'kids', 'unisex'],
          onAudienceTap: (_) {},
          audienceChipsEnabled: true,
        ),
      ),
    ),
    [find.text('All'), find.text("Men's"), find.text('Unisex')],
  );

  sweep(
    'audience shelf page',
    (provider) => ChangeNotifierProvider<ProductProvider>.value(
      value: provider,
      child: const AudienceListingScreen(audience: 'men'),
    ),
    [find.text("Men's"), find.text('1 pair')],
  );

  // The one combination the matrix above cannot reach: an audience with nothing
  // in it, on the smallest surface at the largest scale — the empty state is the
  // layout most likely to be written once and never looked at again.
  testWidgets('an empty shelf page survives the narrowest, largest-text case',
      (tester) async {
    configure(tester, const Size(320, 640), Brightness.dark, 1.3);
    final provider = seed();

    await tester.pumpWidget(host(
      ChangeNotifierProvider<ProductProvider>.value(
        value: provider,
        child: const AudienceListingScreen(audience: 'women'),
      ),
      1.3,
    ));
    await tester.pump();

    // 'women' has a product, so this is not the empty state — assert the page
    // renders rather than claiming a case it did not exercise.
    expect(find.text("Women's"), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(
      ChangeNotifierProvider<ProductProvider>.value(
        value: ProductProvider.seeded(products: const [], unitsSold: const {}),
        child: const AudienceListingScreen(audience: 'kids'),
      ),
      1.3,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text("Nothing in Kids' yet"), findsOneWidget);
    expect(find.text('Browse All Styles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the sweep covers every combination it claims to', () {
    // Guards the matrix itself: 3 surfaces × 3 sizes × 2 modes × 2 scales, so a
    // future edit that quietly drops a size or a mode fails here instead of
    // shrinking the sweep without anyone noticing.
    expect(_sizes.length * _modes.length * _scales.length, 12);
    expect(_sizes.values.map((s) => s.width).toSet().length, 3,
        reason: 'each surface must be swept at three distinct widths');
    expect(_sizes.values.any((s) => s.height < s.width), isTrue,
        reason: 'at least one landscape configuration must be covered');
  });
}
