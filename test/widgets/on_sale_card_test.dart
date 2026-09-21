import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/fit_card.dart';
import 'package:app/widgets/on_sale_card.dart';

/// The "ON SALE" poster: the section's name over the best discount in the
/// catalog, as the On Sale grid's first cell.
///
/// What is pinned here:
///
///  * it **is** a [FitCard] — the card is data, not a second component, so the
///    design cannot drift from the posters beside it;
///  * the number on it comes from the caller and is never hardcoded, and the
///    card has no decoration of its own (no icon, badge or timer);
///  * it is **full bleed** (`padding: 0`), the size poster's treatment, so its
///    type reaches the card's own edges and the block fills the cell;
///  * the `%` is a small mark raised on the top of the digits, not part of the
///    number — the digits keep the line — and the number lands on the card's
///    bottom edge like every other poster's, with each line spanning the card;
///  * the whole card is one tap target that opens the sale list — and the
///    home screen wires it as the grid's first cell, with the old heading row
///    (and its HOT DEALS badge) gone.
///
/// Font metrics play no part: the assertions are about laid-out boxes, so a
/// fallback font in the test environment cannot make them lie.
const double kCellWidth = 168;

/// The card in a parent that bounds it the way the On Sale grid's fixed cell
/// does — a width and the section's own cell proportion.
Widget wrap(Widget card, {double width = kCellWidth}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Center(
          child: SizedBox(
            width: width,
            child: AspectRatio(aspectRatio: FitCard.aspectRatio, child: card),
          ),
        ),
      ),
    ),
  );
}

/// The box a line is scaled into — `.first` is the closest ancestor, i.e. the
/// line's own box rather than the `scaleDown` guard around the block.
Finder boxOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(FittedBox)).first;

void main() {
  Widget card({int percent = 30, VoidCallback? onTap}) =>
      OnSaleCard(discountPercent: percent, onTap: onTap ?? () {});

  testWidgets('is a FitCard, and carries only its copy', (tester) async {
    await tester.pumpWidget(wrap(card()));

    // The one card component: this widget is data, so the poster cannot become
    // a second design. If this ever fails, the card was forked.
    expect(find.byType(FitCard), findsOneWidget);

    expect(find.text('ON'), findsOneWidget);
    expect(find.text('SALE'), findsOneWidget);
    expect(find.text('UP TO'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text(OnSaleCard.valueSuffix), findsOneWidget);

    // No icons, badges or timers on it — the words and the number are the
    // whole card.
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Image), findsNothing);

    // And nothing beyond the copy is handed to the card: every colour and the
    // corner are `FitCard`'s own, which is what keeps this poster identical to
    // the ones beside it. A per-card override of those would be the start of a
    // second design. The one thing this poster does set is `padding: 0` —
    // full bleed, which is the SIZE poster's treatment, not an invention of
    // this card's (see the full-bleed test below).
    final fit = tester.widget<FitCard>(find.byType(FitCard));
    expect(fit.lines, OnSaleCard.lines);
    expect(fit.heroLabel, OnSaleCard.label);
    expect(fit.heroValue, '30');
    expect(fit.heroValueSuffix, OnSaleCard.valueSuffix);
    expect(fit.heroWidget, isNull);
    expect(fit.footerLabel, isNull);
    expect(fit.backgroundColor, isNull);
    expect(fit.borderColor, isNull);
    expect(fit.inkColor, isNull);
    expect(fit.accentColor, isNull);
    expect(fit.borderRadius, isNull);
    expect(fit.padding, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is full bleed, the way the size poster is', (tester) async {
    await tester.pumpWidget(wrap(card()));

    final cardBox = tester.getRect(find.byType(FitCard));
    const innerWidth = kCellWidth; // padding: 0, so the cell IS the inner box

    // Type measured against the whole cell, not a cell with a frame inside it:
    // that is what makes this poster's words the same size as the size poster's
    // at the same cell width (`in_your_size_section.dart` passes the same 0).
    for (final line in OnSaleCard.lines) {
      expect(
        tester.getRect(boxOf(line)).left,
        moreOrLessEquals(cardBox.left, epsilon: 0.5),
        reason: '$line must reach the card\'s own edge',
      );
      expect(
        tester.getRect(boxOf(line)).width,
        moreOrLessEquals(innerWidth, epsilon: 0.5),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the discount it is given, never a number of its own', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(card(percent: 7)));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('30'), findsNothing);

    // A three-digit figure scales down like anything else: a 100% shelf is not
    // a special case, and must not overflow.
    await tester.pumpWidget(wrap(card(percent: 100), width: 120));
    expect(find.text('100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sign is small and sits at the top of the number', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(card(percent: 61)));

    const innerWidth = kCellWidth; // full bleed
    final cardBox = tester.getRect(find.byType(FitCard));
    final number = tester.getRect(boxOf('61'));
    final sign = tester.getRect(find.text(OnSaleCard.valueSuffix));

    // Sized from the cell like the caption and the footer, so it scales with
    // the card and never reads as a second, equally loud character.
    expect(
      tester.widget<Text>(find.text(OnSaleCard.valueSuffix)).style!.fontSize!,
      moreOrLessEquals(
        innerWidth * FitCard.heroSuffixSizeOfWidth,
        epsilon: 0.01,
      ),
    );
    // And it is a mark on the number, not a word beside it: it is smaller than
    // the digits it belongs to.
    expect(sign.height, lessThan(number.height));

    // Raised: its top is the number's top, not its baseline.
    expect(sign.top, moreOrLessEquals(number.top, epsilon: 0.5));
    expect(
      sign.bottom,
      lessThan(number.bottom),
      reason: 'it must read as a superscript, above the digits\' own line',
    );

    // The digits take everything the mark does not — that is the point of
    // taking `%` out of the value's string.
    expect(
      number.width,
      greaterThan(innerWidth * 0.7),
      reason: 'the number still carries the card',
    );
    expect(sign.right, moreOrLessEquals(cardBox.right, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every line spans the card, and the value lands on the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(card()));

    const innerWidth = kCellWidth; // full bleed (padding: 0)
    final cardBox = tester.getRect(find.byType(FitCard));

    for (final line in OnSaleCard.lines) {
      expect(
        tester.getRect(boxOf(line)).width,
        moreOrLessEquals(innerWidth, epsilon: 0.5),
        reason: '$line must touch both edges of the card',
      );
    }

    // The hero fills the height the words leave and sits on the card's bottom
    // edge — the same contract as every other FitCard poster, so there is no
    // dead band under the number.
    final hero = tester.getRect(boxOf('30'));
    expect(
      hero.width,
      lessThan(innerWidth),
      reason: 'the digits share the line with the mark beside them',
    );
    expect(
      hero.bottom,
      moreOrLessEquals(cardBox.bottom, epsilon: 0.5),
      reason: 'the number must sit on the card\'s bottom edge',
    );
    expect(
      tester.getRect(find.text('UP TO')).bottom,
      lessThanOrEqualTo(hero.top + 0.5),
      reason: 'the caption sits directly above the value',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fills the cell better than the same copy with a frame around it', (
    tester,
  ) async {
    /// The band between the words and the caption — the leftover height the
    /// poster's fixed cell opens, and the thing "fill the block" is about.
    Future<double> bandWith(Widget poster) async {
      await tester.pumpWidget(wrap(poster));
      return tester.getRect(find.text('UP TO')).top -
          tester.getRect(boxOf('SALE')).bottom;
    }

    final fullBleed = await bandWith(card());

    // The same copy on the card's default 16px padding — what the poster looked
    // like before it followed the size poster. Two things make the full-bleed
    // version fill its cell: the type is measured against the whole cell (so
    // every line is bigger), and the sign is out of the value's string (so the
    // digits take the line the `%` was sharing with them).
    final framed = await bandWith(
      const FitCard(
        lines: OnSaleCard.lines,
        heroLabel: OnSaleCard.label,
        heroValue: '30%',
      ),
    );

    expect(fullBleed, greaterThanOrEqualTo(0));
    expect(
      fullBleed,
      lessThan(framed),
      reason: 'the poster must fill more of its cell than the framed card',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a small cell shrinks the whole poster, never wraps it', (
    tester,
  ) async {
    // A narrow cell: the sign is a fraction of the width like everything else,
    // so it stays a mark instead of pushing the number onto a second line, and
    // nothing overflows.
    await tester.pumpWidget(wrap(card(), width: 96));

    final cardBox = tester.getRect(find.byType(FitCard));
    expect(find.text('UP TO'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(
      tester.getSize(find.text('UP TO')).height,
      lessThan(0.12 * 96),
      reason: 'the caption is one small line, not a wrapped block',
    );
    // Nothing reaches past the card's own edges, at a cell far narrower than
    // the one the poster is designed for.
    expect(
      tester.getRect(find.text('UP TO')).right,
      lessThanOrEqualTo(cardBox.right + 0.5),
    );
    expect(
      tester.getRect(find.text(OnSaleCard.valueSuffix)).right,
      lessThanOrEqualTo(cardBox.right + 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('announces one label that names the real percentage', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(card(percent: 42)));

    expect(
      find.bySemanticsLabel(OnSaleCard.semanticsLabelFor(42)),
      findsOneWidget,
    );
    // The fragments must not be announced separately.
    expect(find.bySemanticsLabel('ON'), findsNothing);

    final node = tester
        .getSemantics(find.bySemanticsLabel(OnSaleCard.semanticsLabelFor(42)))
        .getSemanticsData();
    expect(
      node.flagsCollection.isButton,
      isTrue,
      reason: 'the card is a button, because the whole card is the target',
    );
    handle.dispose();
  });

  testWidgets('the whole card is the target, and the number is not a button', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(wrap(card(onTap: () => taps++)));

    // Tapping the corner the number sits in is still the card's tap: there is
    // no second, smaller control inside it.
    await tester.tapAt(tester.getCenter(find.byType(FitCard)));
    await tester.pump();
    expect(taps, 1);

    // The number's own corner, just inside the edge.
    await tester.tapAt(
      tester.getBottomRight(find.byType(FitCard)) - const Offset(8, 8),
    );
    await tester.pump();
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });

  /// A widget test cannot stand up `CustomerHomeScreen` (it needs the auth,
  /// product, banner, cart and message providers plus Supabase), so the part
  /// that only exists there is pinned at the source: the poster is the On Sale
  /// grid's FIRST cell, its tap opens the sale list, and the heading row it
  /// replaced is gone.
  group('the home feed wires it as the section\'s heading', () {
    late String home;

    setUpAll(() {
      home = File(
        'lib/screens/customer/customer_home_screen.dart',
      ).readAsStringSync();
    });

    test('the old heading row is gone, with its badge', () {
      expect(
        home.contains('_PriceTagBadge'),
        isFalse,
        reason: 'the HOT DEALS badge went with the heading row',
      );
      // The text heading lived in a Row beside that badge. What is left of
      // "On Sale" on this screen is the section comment and the listing page.
      expect(
        RegExp(r"Text\(\s*'On Sale',").hasMatch(home),
        isFalse,
        reason: 'the section is named by the poster now, not a 16px title',
      );
    });

    test('the card is cell zero of the On Sale grid, not an overlay', () {
      expect(
        home.contains('OnSaleCard('),
        isTrue,
        reason: 'the feed must render the poster',
      );
      expect(
        RegExp(r'if \(maxDiscount != null && index == 0\)').hasMatch(home),
        isTrue,
        reason: 'the poster is the first cell, so a sale card sits beside it',
      );
      expect(
        RegExp(
          r'itemCount:\s*\n\s*saleProducts\.length \+\s*\n\s*\(maxDiscount == null \? 0 : 1\)',
        ).hasMatch(home),
        isTrue,
        reason: 'the poster is an extra cell, and is dropped when unknown',
      );
      expect(
        RegExp(r'saleProducts\[index -').hasMatch(home),
        isTrue,
        reason: 'the products follow the poster, none of them dropped',
      );
    });

    test('its number is derived live from the sale set', () {
      // Never a literal: the figure comes from the products that are on sale.
      expect(
        RegExp(r'maxDiscountPercent\(saleProducts\)').hasMatch(home),
        isTrue,
        reason: 'the discount is computed from live data',
      );
      expect(
        RegExp(r'productProvider\.isLoading\s*\n\s*\? null').hasMatch(home),
        isTrue,
        reason: 'no card while the catalog is still loading',
      );
    });

    test('its tap opens the full sale list', () {
      expect(home.contains('OnSaleListingScreen'), isTrue);
      expect(
        RegExp(r"import 'on_sale_listing_screen\.dart';").hasMatch(home),
        isTrue,
      );
    });
  });
}
