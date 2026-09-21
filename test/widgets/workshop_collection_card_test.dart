import 'dart:io';
// `Tristate` is what the flag collection reports; `flutter/semantics.dart`
// re-exports it from here.
import 'dart:ui' show Tristate;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/services/workshop_sort_hint_service.dart';
import 'package:app/widgets/fit_card.dart';
import 'package:app/widgets/workshop_collection_card.dart';

/// The "The Workshop Collection" card: the section's name on the front, the
/// section's sort list on the back, and it turns over between them.
///
/// Two halves of the contract, and both matter:
///
///  * the **front** is a poster — four words each spanning the whole card
///    (loudest first), full bleed, with the sort in force as a word in the
///    corner that is sized from the card rather than in pixels;
///  * the **back** is the sort list — every order, the one in force marked, each
///    row a real button, and the whole face a way back out.
///
/// Font metrics play no part (the test font is a full-size square per glyph), so
/// the assertions are about laid-out boxes and cannot be fooled by a fallback
/// font.
const double kCellWidth = 168;

Widget wrap(
  Widget card, {
  double width = kCellWidth,
  TextScaler textScaler = TextScaler.noScaling,
  bool reducedMotion = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: textScaler,
          disableAnimations: reducedMotion,
        ),
        child: Center(
          child: SizedBox(
            width: width,
            child: AspectRatio(
              aspectRatio: WorkshopCollectionCard.aspectRatio,
              child: card,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The box a line is scaled into — `.first` is the closest ancestor, so the
/// line's own `FittedBox` rather than the `scaleDown` guard around the words.
Finder boxOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(FittedBox)).first;

Rect cardRect(WidgetTester tester) =>
    tester.getRect(find.byType(WorkshopCollectionCard));

/// Turns the card over and waits for the turn to finish.
Future<void> flip(WidgetTester tester) async {
  await tester.tap(find.byType(WorkshopCollectionCard));
  await tester.pumpAndSettle();
}

/// The box carrying the turn under the card: the FIRST `Transform` below it,
/// which is the rotating one (the back's own mirror is nested inside it).
Finder turnTransform() => find
    .descendant(
      of: find.byType(WorkshopCollectionCard),
      matching: find.byType(Transform),
    )
    .first;

/// The angle the card is turned to right now, in radians.
///
/// Read off the turn's own matrix rather than inferred from a rotated box's
/// projected width: a few degrees of lean and a rounding error cannot hide
/// inside it.
///
/// `Matrix4.rotateY(θ)` puts `cos θ` at storage[0] and `-sin θ` at storage[2].
double turnAngle(WidgetTester tester) {
  final m = tester.widget<Transform>(turnTransform()).transform.storage;
  return math.atan2(-m[2], m[0]);
}

/// The container carrying the poster's lift — the only decorated box under the
/// card with a shadow on it.
Finder liftBox() => find
    .descendant(
      of: find.byType(WorkshopCollectionCard),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (((w.decoration! as BoxDecoration).boxShadow?.isNotEmpty) ??
                false),
      ),
    )
    .first;

/// Whether the one-time hint has been spent in the store.
Future<bool> hintSpent() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(WorkshopSortHintService.key) ?? false;
}

void main() {
  Widget card(SortMode sort, {ValueChanged<SortMode>? onSelected}) =>
      WorkshopCollectionCard(sort: sort, onSelected: onSelected ?? (_) {});

  group('the front', () {
    testWidgets('says the name on four lines and the sort in the corner', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      for (final line in WorkshopCollectionCard.titleLines) {
        expect(find.text(line), findsOneWidget);
      }
      expect(WorkshopCollectionCard.titleLines, const [
        'THE',
        'WORK',
        'SHOP',
        'COLLECTION',
      ]);
      expect(find.text('Featured'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the corner word tracks the sort, in its short form', (
      tester,
    ) async {
      for (final mode in SortMode.values) {
        await tester.pumpWidget(wrap(card(mode)));
        expect(
          find.text(sortModeShortLabel(mode)),
          findsOneWidget,
          reason: '$mode must show its short label',
        );
        // The long form is what the row (and the system's reader) says, not what
        // the corner has room for.
        if (sortModeShortLabel(mode) != sortModeLabel(mode)) {
          expect(find.text(sortModeLabel(mode)), findsNothing);
        }
      }
    });

    testWidgets('every line spans the whole card, loudest first', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      // Full bleed: no inner inset, so the words answer to the CARD's width —
      // the same treatment the "Based on your size" poster gets.
      for (final line in WorkshopCollectionCard.titleLines) {
        expect(
          tester.getSize(boxOf(line)).width,
          moreOrLessEquals(kCellWidth, epsilon: 0.5),
          reason: '"$line" must span the card edge to edge',
        );
      }

      double heightOf(String line) => tester.getSize(boxOf(line)).height;
      expect(heightOf('THE'), greaterThan(heightOf('SHOP')));
      expect(heightOf('SHOP'), greaterThan(heightOf('COLLECTION')));
    });

    testWidgets('the sort word is a mark in the bottom-right, not a button', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      final cardBox = cardRect(tester);
      final word = tester.getRect(boxOf('Featured'));

      // On the bottom edge the way the block is, and held that one gutter off
      // the right edge so the corner's own clip cannot shave the last glyph
      // (the words are full bleed; a caption in the corner is not).
      expect(
        word.right,
        moreOrLessEquals(
          cardBox.right - kCellWidth * FitCard.footerInsetOfWidth,
          epsilon: 0.5,
        ),
      );
      expect(word.bottom, moreOrLessEquals(cardBox.bottom, epsilon: 0.5));
      expect(word.top, greaterThan(tester.getRect(boxOf('COLLECTION')).bottom));
      expect(
        tester.getRect(boxOf('THE')).top,
        moreOrLessEquals(cardBox.top, epsilon: 0.5),
      );

      // No control of its own: the card's `InkWell` is the only one, and the
      // word brings no icon, fill or underline with it.
      expect(
        find.descendant(
          of: find.byType(WorkshopCollectionCard),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(WorkshopCollectionCard),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      final style = tester.widget<Text>(find.text('Featured')).style!;
      expect(style.decoration, isNull);
      expect(style.backgroundColor, isNull);
      expect(style.color, AppPalette.light.primaryInk);
      expect(
        style.fontSize,
        moreOrLessEquals(kCellWidth * FitCard.footerSizeOfWidth, epsilon: 0.01),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the OS text scale cannot distort the poster', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.bestSelling)));
      final atDefault = [
        for (final line in WorkshopCollectionCard.titleLines)
          tester.getSize(boxOf(line)),
        tester.getSize(boxOf('Best Selling')),
      ];

      await tester.pumpWidget(
        wrap(
          card(SortMode.bestSelling),
          textScaler: const TextScaler.linear(2),
        ),
      );
      final atMaxScale = [
        for (final line in WorkshopCollectionCard.titleLines)
          tester.getSize(boxOf(line)),
        tester.getSize(boxOf('Best Selling')),
      ];

      expect(atMaxScale, atDefault);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing is announced from the other side of the card', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(card(SortMode.topRated)));

      expect(
        find.bySemanticsLabel(
          'The Workshop Collection, sorted by Top Rated. '
          'Double tap to change sort.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(WorkshopCollectionCard.backTitle),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('the turn', () {
    testWidgets('tapping the card anywhere turns it over', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      expect(find.text(WorkshopCollectionCard.backTitle), findsNothing);

      // The corner the word sits in, and the opposite one: the whole card is
      // the target, not a chip in it.
      final cardBox = cardRect(tester);
      await tester.tapAt(Offset(cardBox.right - 6, cardBox.bottom - 6));
      await tester.pumpAndSettle();
      expect(find.text(WorkshopCollectionCard.backTitle), findsOneWidget);

      // And back, then over again from the other corner.
      await tester.tapAt(Offset(cardBox.left + 6, cardBox.top + 6));
      await tester.pumpAndSettle();
      expect(find.text(WorkshopCollectionCard.backTitle), findsNothing);

      await tester.tapAt(Offset(cardBox.left + 6, cardBox.top + 6));
      await tester.pumpAndSettle();
      expect(find.text(WorkshopCollectionCard.backTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion turns it over without animating', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(card(SortMode.featured), reducedMotion: true),
      );

      await tester.tap(find.byType(WorkshopCollectionCard));
      // One frame is all a zero-duration turn needs, and that is the assertion:
      // the state arrives at once, it just does not travel.
      await tester.pump();
      expect(find.text(WorkshopCollectionCard.backTitle), findsOneWidget);
    });

    testWidgets('the back is not left mirrored', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));
      await flip(tester);

      // Two half turns make a whole one: the card's own rotation, and the one
      // that keeps the back readable rather than mirror-written. Both are -1 on
      // the X axis at rest; drop either and the list reads backwards.
      final turns = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.text(WorkshopCollectionCard.backTitle),
              matching: find.byType(Transform),
            ),
          )
          .toList();
      expect(turns.length, greaterThanOrEqualTo(2));
      expect(
        turns.first.transform.entry(0, 0),
        moreOrLessEquals(-1, epsilon: 0.01),
        reason: 'the back carries its own half turn',
      );
      expect(
        turns.last.transform.entry(0, 0),
        moreOrLessEquals(-1, epsilon: 0.01),
        reason: 'and the card has turned the other half',
      );
      // Upright: no leftover skew on the Y axis of the net transform.
      final net = turns.first.transform * turns.last.transform;
      expect(net.entry(0, 0), moreOrLessEquals(1, epsilon: 0.01));
    });
  });

  group('the back', () {
    testWidgets('lists every order and marks the one in force', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.topRated)));
      await flip(tester);

      expect(find.text(WorkshopCollectionCard.backTitle), findsOneWidget);
      for (final mode in SortMode.values) {
        expect(
          find.text(sortModeShortLabel(mode)),
          findsOneWidget,
          reason: '$mode must be offered on the back',
        );
      }

      // Exactly one mark, and it is on the order in force — drawn in clay and
      // bold, the sheet's own convention.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(
        find.byIcon(Icons.radio_button_unchecked),
        findsNWidgets(SortMode.values.length - 1),
      );
      final active = tester.widget<Text>(find.text('Top Rated')).style!;
      final other = tester.widget<Text>(find.text('Best Selling')).style!;
      expect(active.color, AppConstants.primary);
      expect(active.fontWeight, FontWeight.bold);
      expect(other.color, isNot(AppConstants.primary));
      expect(other.fontWeight, FontWeight.normal);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing an order reports it once and turns the card back', (
      tester,
    ) async {
      final chosen = <SortMode>[];
      await tester.pumpWidget(
        wrap(card(SortMode.featured, onSelected: chosen.add)),
      );
      await flip(tester);

      await tester.tap(find.text('Low to High'));
      await tester.pumpAndSettle();

      expect(chosen, [SortMode.priceLowToHigh]);
      // Back on the poster. Its corner word is still the order it was GIVEN —
      // the card reports, it does not hold state — and the feed's next rebuild
      // is what moves it (see the test below).
      expect(find.text(WorkshopCollectionCard.backTitle), findsNothing);
      for (final line in WorkshopCollectionCard.titleLines) {
        expect(find.text(line), findsOneWidget);
      }
    });

    testWidgets('the corner word follows the choice once the feed applies it', (
      tester,
    ) async {
      final chosen = <SortMode>[];
      await tester.pumpWidget(
        wrap(card(SortMode.featured, onSelected: chosen.add)),
      );
      await flip(tester);
      await tester.tap(find.text('A to Z'));
      await tester.pumpAndSettle();

      // What the feed does with the report: re-render the card with the new
      // order. The corner is the state, so it must be the new word.
      await tester.pumpWidget(wrap(card(chosen.single)));
      expect(find.text('A to Z'), findsOneWidget);
      expect(find.text('Featured'), findsNothing);
    });

    testWidgets(
      're-picking the order already in force closes without a report',
      (tester) async {
        final chosen = <SortMode>[];
        await tester.pumpWidget(
          wrap(card(SortMode.topRated, onSelected: chosen.add)),
        );
        await flip(tester);

        await tester.tap(find.text('Top Rated'));
        await tester.pumpAndSettle();

        expect(
          chosen,
          isEmpty,
          reason: 'nothing changed, so nothing is re-sorted',
        );
        expect(find.text(WorkshopCollectionCard.backTitle), findsNothing);
      },
    );

    testWidgets('a tap that is not an order is the way back', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));
      await flip(tester);

      // The back's own padding, under the last row and clear of the rounded
      // corner: the card can always be closed, or a customer who opened it is
      // stuck with it.
      final cardBox = cardRect(tester);
      await tester.tapAt(Offset(cardBox.center.dx, cardBox.bottom - 6));
      await tester.pumpAndSettle();

      expect(find.text(WorkshopCollectionCard.backTitle), findsNothing);
      expect(find.text('Featured'), findsOneWidget);
    });

    testWidgets('the list scales with the cell and never overflows', (
      tester,
    ) async {
      // A phone's 2-column cell, a narrow one, and a tablet-wide one.
      for (final width in const [120.0, 148.0, 183.0, 430.0]) {
        await tester.pumpWidget(wrap(card(SortMode.featured), width: width));
        // `pumpWidget` keeps the State (same widget type, same slot), so the
        // card is still turned over from the previous width.
        if (find.text(WorkshopCollectionCard.backTitle).evaluate().isEmpty) {
          await flip(tester);
        }

        final cardBox = cardRect(tester);
        for (final mode in SortMode.values) {
          final row = tester.getRect(find.text(sortModeShortLabel(mode)));
          expect(
            row.bottom,
            lessThanOrEqualTo(cardBox.bottom + 0.5),
            reason: 'the list must fit the card at ${width}px',
          );
          expect(row.right, lessThanOrEqualTo(cardBox.right + 0.5));
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('each order is announced by its full name and its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(card(SortMode.nameAZ)));
      await flip(tester);

      // The card shows `A to Z` because that is what fits; what is announced is
      // the name of the order.
      expect(find.bySemanticsLabel('Name: A to Z'), findsOneWidget);
      expect(find.bySemanticsLabel('Price: High to Low'), findsOneWidget);
      expect(find.bySemanticsLabel('A to Z'), findsNothing);

      final node = tester
          .getSemantics(find.bySemanticsLabel('Name: A to Z'))
          .getSemanticsData();
      expect(
        node.flagsCollection.isSelected,
        Tristate.isTrue,
        reason: 'the order in force is announced as the selected one',
      );
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  testWidgets('the back is the card, not a second surface', (tester) async {
    AppBrightness.set(Brightness.dark);
    addTearDown(AppBrightness.reset);

    await tester.pumpWidget(wrap(card(SortMode.featured)));
    await flip(tester);

    // Same fill and edge as the front — the card has two sides, not two widgets
    // — and the back is the only `Material` built while it is showing.
    final materials = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(WorkshopCollectionCard),
        matching: find.byType(Material),
      ),
    );
    expect(materials, hasLength(1));
    // The poster family's own defaults (`FitCard.backgroundColor` /
    // `borderColor`): the page tone, and the poster's thin line rather than the
    // product cards' heavier frame. With the fill off the page it is the edge
    // that draws the tile, on the front and on the back alike.
    expect(materials.first.color, AppPalette.dark.page);
    final backSide =
        (materials.first.shape! as RoundedRectangleBorder).side;
    expect(backSide.color, AppPalette.dark.hairline);
    expect(backSide.width, FitCard.edgeWidth);
  });

  group('in the feed', () {
    // A widget test cannot stand up `CustomerHomeScreen` (it needs the auth,
    // product, banner, cart and message providers plus Supabase), so the things
    // that only exist there are pinned at the source: the card is the grid's
    // FIRST cell, it sorts the feed itself, and the heading row, its chip and
    // the sort sheet are gone from this screen.
    late String home;

    setUpAll(() {
      home = File(
        'lib/screens/customer/customer_home_screen.dart',
      ).readAsStringSync();
    });

    test('the card opens the collection, as the grid\'s first cell', () {
      expect(
        home.contains('WorkshopCollectionCard('),
        isTrue,
        reason: 'the feed must render the card',
      );
      expect(
        RegExp(r'itemCount:\s*filteredProducts\.length \+ 1').hasMatch(home),
        isTrue,
        reason: 'the card is an extra cell, not an overlay',
      );
      expect(
        RegExp(r'if \(index == 0\)').hasMatch(home),
        isTrue,
        reason: 'the card is cell zero — the first product sits beside it',
      );
      expect(
        RegExp(r'filteredProducts\[index - 1\]').hasMatch(home),
        isTrue,
        reason: 'the products follow the card, none of them dropped',
      );
    });

    test('the feed sorts from the card, and no longer from a sheet', () {
      expect(
        RegExp(
          r'onSelected:\s*context\.read<ProductProvider>\(\)\.setSortMode',
        ).hasMatch(home),
        isTrue,
        reason: 'choosing an order on the back must re-sort this feed',
      );
      expect(
        home.contains('_showSortSheet'),
        isFalse,
        reason: 'the card is the sort control now',
      );
      expect(
        home.contains('showProductSortSheet'),
        isFalse,
        reason: 'and it opens no sheet over the feed',
      );
      expect(
        home.contains('product_sort_sheet.dart'),
        isFalse,
        reason: 'the shared sheet is for the other lists, not this one',
      );
    });

    test('the old heading row and its sort chip are gone', () {
      expect(
        home.contains("'The Workshop Collection'"),
        isFalse,
        reason: 'the name lives on the card now, not in a heading',
      );
      expect(
        home.contains('Icons.sort_outlined'),
        isFalse,
        reason: 'the bordered sort chip was replaced by the card',
      );
      expect(
        home.contains('sortModeLabel('),
        isFalse,
        reason: 'the card shows the short label; the sheet owns the long one',
      );
    });
  });

  group('saying out loud that it turns over', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('the hint arrives on a first run, and a tap spends it', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));
      // The store answering is a frame, not a wait: the card is usable the whole
      // time — the hint is only ever an addition to it.
      await tester.pump();

      expect(find.text(WorkshopCollectionCard.hintLabel), findsOneWidget);

      await flip(tester);
      await tester.pump();

      expect(find.text(WorkshopCollectionCard.hintLabel), findsNothing);
      expect(
        await hintSpent(),
        isTrue,
        reason: 'one turn of the card is all the hint gets',
      );
    });

    testWidgets('a customer who has turned it over before never sees it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        WorkshopSortHintService.key: true,
      });

      await tester.pumpWidget(wrap(card(SortMode.featured)));
      await tester.pump();

      expect(find.text(WorkshopCollectionCard.hintLabel), findsNothing);
    });

    testWidgets('the hint leaves on its own, and stays gone', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));
      await tester.pump();
      expect(find.text(WorkshopCollectionCard.hintLabel), findsOneWidget);

      await tester.pump(WorkshopCollectionCard.hintLifetime);
      await tester.pump();

      expect(find.text(WorkshopCollectionCard.hintLabel), findsNothing);
      expect(
        await hintSpent(),
        isTrue,
        reason: 'a hint that has had its turn on screen is spent',
      );
    });

    testWidgets('it is a label on the card — clear of the words, opposite the '
        'corner word, and still the card\'s to tap', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));
      await tester.pump();

      final hint = tester.getRect(find.text(WorkshopCollectionCard.hintLabel));
      final poster = tester.getRect(find.byType(FitCard));
      final words = tester.getRect(boxOf('COLLECTION'));
      final corner = tester.getRect(
        boxOf(sortModeShortLabel(SortMode.featured)),
      );

      // Inside the card, under its words — the bottom band is the only empty
      // space a full-bleed poster has — and opposite the word it is about.
      expect(hint.left, greaterThanOrEqualTo(poster.left));
      expect(hint.right, lessThanOrEqualTo(poster.right));
      expect(
        hint.top,
        greaterThanOrEqualTo(words.bottom),
        reason: 'the hint must not sit on the poster',
      );
      expect(
        hint.left,
        lessThan(corner.left),
        reason: 'the hint belongs opposite the corner word it explains',
      );

      // A label, not a second control: a tap on it is a tap on the card. The
      // hint sits behind an `IgnorePointer`, so the tap is reported as missing
      // it and landing on the card underneath — which is exactly the contract.
      await tester.tap(
        find.text(WorkshopCollectionCard.hintLabel),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text(WorkshopCollectionCard.backTitle), findsOneWidget);
      await tester.pump();
      expect(await hintSpent(), isTrue);
    });

    testWidgets('the idle beat leans the card over and squares it again', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      expect(turnAngle(tester), moreOrLessEquals(0, epsilon: 1e-6));

      // The hold, then the lean: the beat's peak is the flip's first few
      // degrees, and the turn is the only thing that goes any further.
      await tester.pump(WorkshopCollectionCard.teaseHold);
      await tester.pump(WorkshopCollectionCard.teaseOut);
      expect(
        turnAngle(tester),
        moreOrLessEquals(
          WorkshopCollectionCard.teaseFraction * math.pi,
          epsilon: 0.002,
        ),
        reason: 'the beat must actually tip the card',
      );
      expect(
        find.text(WorkshopCollectionCard.backTitle),
        findsNothing,
        reason: 'a hint, never a flip',
      );
      expect(find.text('THE'), findsOneWidget);

      // ...and the settle: square again, with nothing left over.
      await tester.pump(WorkshopCollectionCard.teaseBack);
      expect(turnAngle(tester), moreOrLessEquals(0, epsilon: 1e-6));
    });

    testWidgets('a tap mid-beat still lands the card square on its back', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      // Catch the card mid-lean, where a beat left running would ride into the
      // flip and leave the back a few degrees off square.
      await tester.pump(WorkshopCollectionCard.teaseHold);
      await tester.pump(WorkshopCollectionCard.teaseOut);
      expect(
        turnAngle(tester),
        greaterThan(0.01),
        reason: 'the card must be mid-lean here',
      );

      await flip(tester);

      expect(find.text(WorkshopCollectionCard.backTitle), findsOneWidget);
      expect(turnAngle(tester), moreOrLessEquals(math.pi, epsilon: 1e-3));

      // The beat belongs to the poster: with the back up, nothing leans.
      await tester.pump(WorkshopCollectionCard.teaseHold);
      await tester.pump(WorkshopCollectionCard.teaseOut);
      expect(turnAngle(tester), moreOrLessEquals(math.pi, epsilon: 1e-3));
    });

    testWidgets('a reduced-motion platform never starts the beat', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(card(SortMode.featured), reducedMotion: true),
      );

      // A whole beat's worth of wall clock: the card has not leaned, and the
      // hint still arrives — state, not travel.
      await tester.pump(WorkshopCollectionCard.teaseHold);
      await tester.pump(WorkshopCollectionCard.teaseOut);
      await tester.pump(WorkshopCollectionCard.teaseBack);
      expect(turnAngle(tester), moreOrLessEquals(0, epsilon: 1e-6));

      await tester.pump();
      expect(find.text(WorkshopCollectionCard.hintLabel), findsOneWidget);
    });

    testWidgets('the poster is lifted off the page, and the lift is under the '
        'turn', (tester) async {
      await tester.pumpWidget(wrap(card(SortMode.featured)));

      final decoration =
          tester.widget<Container>(liftBox()).decoration! as BoxDecoration;

      // The product cards' own lift: a card with two sides is an object
      // standing on the page, not printed type.
      expect(decoration.boxShadow, AppConstants.productCardShadow);
      expect(decoration.borderRadius, AppConstants.productCardRadius);

      // ...and it is cast from OUTSIDE the turn, so it stays where it is while
      // the card turns over above it.
      expect(
        find.ancestor(of: turnTransform(), matching: liftBox()),
        findsOneWidget,
      );
    });
  });
}
