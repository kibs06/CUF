import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/screens/customer/widgets/home_category_row.dart';
import 'package:app/utils/product_audience.dart';

/// WCAG relative luminance, so the dark-mode assertions measure legibility
/// instead of restating a token.
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

/// The Home hero's category row, now carrying the audience chips too.
///
/// The rules pinned here are the ones a later layout edit could quietly break:
/// where the audience chips sit relative to `All` and the categories, that a
/// chip only exists for an audience with products (the reason turning the
/// feature on changed nothing on Home), and that a shelf chip navigates while a
/// category chip filters — the one behavioural difference between two chip
/// kinds that otherwise look identical.
///
/// Driven with plain values so no Supabase client is needed: this widget reads
/// no providers, which is exactly why it was extracted out of `HomeHero` (that
/// widget cannot be built in a test — `BannerProvider` constructs a live client).
const kCategories = ['All', 'Casual', 'Formal'];

/// The row at a given text scale.
///
/// The scale is applied with `copyWith` onto the real ambient data, from inside
/// the `MaterialApp` — replacing the whole `MediaQueryData` with
/// `MediaQueryData(textScaler: …)` silently zeroes `size` and every other field,
/// which would make any layout that consults them meaningless in the test.
Widget wrap({
  List<String> categories = kCategories,
  String? selected = 'All',
  List<String> audiences = const [],
  bool enabled = true,
  double scale = 1.0,
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onAudienceTap,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          // The hero's dark, image-backed band — the row's ink is white.
          backgroundColor: Colors.black,
          body: HomeCategoryRow(
            categories: categories,
            selectedCategory: selected,
            onSelect: onSelect ?? (_) {},
            audiences: audiences,
            onAudienceTap: onAudienceTap,
            audienceChipsEnabled: enabled,
          ),
        ),
      ),
    ),
  );
}

/// The underline slots in the row, in chip order. Only category chips have one.
Finder underlines() => find.descendant(
      of: find.byType(HomeCategoryRow),
      matching: find.byType(AnimatedContainer),
    );

void main() {
  testWidgets('the shelf chips sit between All and the product categories',
      (tester) async {
    await tester.pumpWidget(wrap(audiences: const ['men', 'unisex']));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('All'), findsOneWidget);
    expect(find.text("Men's"), findsOneWidget);
    expect(find.text('Unisex'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);

    // Left to right: All → the audiences → the categories. The audiences are
    // second on purpose, so they are on screen without a horizontal scroll.
    expect(tester.getTopLeft(find.text('All')).dx,
        lessThan(tester.getTopLeft(find.text("Men's")).dx));
    expect(tester.getTopLeft(find.text("Men's")).dx,
        lessThan(tester.getTopLeft(find.text('Unisex')).dx));
    expect(tester.getTopLeft(find.text('Unisex')).dx,
        lessThan(tester.getTopLeft(find.text('Casual')).dx));
  });

  testWidgets('offers only the audiences it is handed — an audience with no '
      'products is not a chip', (tester) async {
    await tester.pumpWidget(wrap(audiences: const ['kids']));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Kids'"), findsOneWidget);
    // Nothing tagged for these in the catalog, so nothing is offered — a chip
    // that can only lead to an empty shelf is worse than no chip.
    expect(find.text("Men's"), findsNothing);
    expect(find.text("Women's"), findsNothing);
    expect(find.text('Unisex'), findsNothing);
  });

  testWidgets('with the switch off the row is exactly the category chips',
      (tester) async {
    await tester.pumpWidget(
      wrap(audiences: const ['men', 'women', 'kids', 'unisex'], enabled: false),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    for (final label in const ["Men's", "Women's", "Kids'", 'Unisex']) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('the labels come from the shared vocabulary', (tester) async {
    await tester.pumpWidget(
      wrap(audiences: [for (final (value, _) in productAudienceOptions) value]),
    );
    await tester.pump(const Duration(milliseconds: 300));

    for (final (_, label) in productAudienceOptions) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a shelf chip opens its audience; a category chip filters',
      (tester) async {
    final opened = <String>[];
    final filtered = <String>[];

    await tester.pumpWidget(wrap(
      audiences: const ['women'],
      onSelect: filtered.add,
      onAudienceTap: opened.add,
    ));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text("Women's"));
    await tester.pump(const Duration(milliseconds: 300));
    // The canonical value, not the label — the listing page looks up the shelf.
    expect(opened, ['women']);
    expect(filtered, isEmpty, reason: 'a shelf chip must not narrow this feed');

    await tester.tap(find.text('Casual'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(filtered, ['Casual']);
    expect(opened, ['women'], reason: 'a category chip must not navigate');
  });

  testWidgets('a category chip is underlined when active; a shelf chip never is',
      (tester) async {
    await tester.pumpWidget(wrap(audiences: const ['men', 'unisex']));
    await tester.pump(const Duration(milliseconds: 300));

    // One underline slot per category chip and none at all for the two shelf
    // chips — so a shelf chip cannot ever look like the active filter.
    expect(underlines(), findsNWidgets(kCategories.length));
    expect(tester.getSize(underlines().at(0)).width, greaterThan(0),
        reason: "'All' is the active filter");
    expect(tester.getSize(underlines().at(1)).width, 0);
    expect(tester.getSize(underlines().at(2)).width, 0);
  });

  testWidgets('the underline moves to whichever category is selected',
      (tester) async {
    await tester.pumpWidget(wrap(selected: 'Formal'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getSize(underlines().at(0)).width, 0);
    expect(tester.getSize(underlines().at(2)).width, greaterThan(0));
  });

  testWidgets('survives a narrow phone at a large text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(
      audiences: const ['men', 'women', 'kids', 'unisex'],
      scale: 1.3,
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // The row scrolls horizontally, so the shelf chips simply move off screen
    // rather than overflowing the hero, and the strip sizes to the scaled label
    // instead of clipping it.
    expect(find.text('All'), findsOneWidget);
    expect(tester.getSize(find.text('All')).height, greaterThan(13 * 1.3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrecognised audience value renders no chip', (tester) async {
    await tester.pumpWidget(wrap(audiences: const ['nonsense', 'Men']));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('nonsense'), findsNothing);
    expect(find.text('Men'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rows of the live catalog are untouched by the feature',
      (tester) async {
    // Every product in the live catalog is `audience = null`, so this is the row
    // the customer sees today: `audiencesInCatalog` is empty and nothing above
    // changes. (The switch itself is asserted separately.)
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(milliseconds: 300));

    expect(underlines(), findsNWidgets(kCategories.length));
    for (final (_, label) in productAudienceOptions) {
      expect(find.text(label), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  /// The hero's band is a photo with a dark overlay — dark in BOTH
  /// brightnesses — so nothing in this row may follow the theme.
  group('dual-brightness check', () {
    tearDown(AppBrightness.reset);

    Color underlineColor(WidgetTester tester) {
      final decoration = tester
          .widgetList<AnimatedContainer>(underlines())
          .first
          .decoration as BoxDecoration;
      return decoration.color!;
    }

    testWidgets('the active-tab indicator does not flip with the theme',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump(const Duration(milliseconds: 300));
      final light = underlineColor(tester);

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap());
      await tester.pump(const Duration(milliseconds: 300));
      final dark = underlineColor(tester);

      expect(dark, light);
      // It used to be `surfaceLight`, which is brightness-aware and resolves to
      // the near-black *page* on dark — an indicator that disappeared into the
      // photo behind it. Pinned ink is the only correct answer on a band that
      // never changes.
      expect(light, AppConstants.inkInverse);
      expect(dark, isNot(AppConstants.surfaceLight));
      expect(
        _contrast(dark, AppPalette.dark.page),
        greaterThanOrEqualTo(3.0),
        reason: 'a 2px indicator must clear the 3:1 graphic bar against the '
            'dark band it sits on',
      );
    });

    testWidgets('the chip labels stay white in both modes', (tester) async {
      Color labelColor(WidgetTester tester) =>
          tester.widget<Text>(find.text('Casual')).style!.color!;

      await tester.pumpWidget(wrap());
      await tester.pump(const Duration(milliseconds: 300));
      final light = labelColor(tester);

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap());
      await tester.pump(const Duration(milliseconds: 300));

      expect(labelColor(tester), light);
      expect(light, Colors.white.withValues(alpha: 0.6));
    });

    testWidgets('the shelf chips are legible in dark mode too', (tester) async {
      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(wrap(audiences: const ['men', 'unisex']));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("Men's"), findsOneWidget);
      expect(find.text('Unisex'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no overflow on the largest text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 2.0 is the platform maximum, not a comfortable "large".
    await tester.pumpWidget(wrap(audiences: const ['men'], scale: 2.0));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('All'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the chip row follows the feature switch', () {
    // No production call site passes `audienceChipsEnabled` — the default is
    // the switch, so flipping it is the whole rollout.
    const row = HomeCategoryRow(
      categories: kCategories,
      selectedCategory: 'All',
      onSelect: _noop,
    );
    expect(row.audienceChipsEnabled, AppConstants.productAudienceEnabled);
  });
}

void _noop(String _) {}
