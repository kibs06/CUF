import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/widgets/fit_card.dart';

/// The "Fit Card" poster tile — the reference card is "Based on your size · EU
/// 42".
///
/// What is pinned here is the thing that makes the design work rather than how
/// it looks in a golden: every line is scaled to the **full inner width** (no
/// ragged space on the right), the hero value **fills the height left under the
/// lines** (no dead area at the bottom), nothing depends on a hardcoded font
/// size, the OS text scale cannot distort it, and the ink on the fill clears AA
/// in both brightnesses.
///
/// Font metrics deliberately play no part: the assertions are about laid-out
/// boxes, so a fallback font in the test environment cannot make them lie.
const List<String> kLines = ['Based', 'on your', 'size'];

/// Relative luminance + contrast, the same measurement the palette tests use.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The card in a parent that bounds it the way a grid cell does: a fixed width
/// and the reference proportion.
Widget wrap(
  Widget card, {
  double width = 168,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
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

/// Every [FittedBox] in the card, in visual order: the lines, then the hero
/// value's.
Finder fittedBoxes() =>
    find.descendant(of: find.byType(FitCard), matching: find.byType(FittedBox));

/// The box a line is scaled into — `.first` is the closest ancestor, i.e. the
/// line's own box rather than the `scaleDown` guard rail around the words.
Finder boxOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(FittedBox)).first;

void main() {
  const card = FitCard(lines: kLines, heroLabel: 'EU', heroValue: '42');

  testWidgets('renders every line, the label and the hero value', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(card));

    for (final line in kLines) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text('EU'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wears the product family\'s corner by default', (tester) async {
    // The posters sit in the same grid as the product tiles, so they share the
    // tiles' corner rather than the app's wider `cardRadius`; a section that
    // mixed the two would read as two designs.
    await tester.pumpWidget(wrap(card));

    final shape =
        tester
                .widget<Material>(
                  find
                      .descendant(
                        of: find.byType(FitCard),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .shape
            as RoundedRectangleBorder;
    expect(shape.borderRadius, AppConstants.productCardRadius);
  });

  testWidgets('every line is scaled to the full inner width', (tester) async {
    await tester.pumpWidget(wrap(card));

    const innerWidth = 168.0 - 32; // card width − 16 padding on each side

    for (final line in [...kLines, '42']) {
      // `BoxFit.fitWidth` inside a stretched Column: each line answers exactly
      // to the inner width, which is what removes the ragged right edge. A
      // short word therefore renders bigger than a long one — that is the
      // design, not an accident.
      expect(
        tester.getSize(boxOf(line)).width,
        moreOrLessEquals(innerWidth, epsilon: 0.5),
        reason: '"$line" must span the card edge to edge',
      );
    }

    // Short line, tall glyphs: 'size' is drawn larger than the longer 'on
    // your', which is the whole point of scaling each line independently.
    expect(
      tester.getSize(boxOf('size')).height,
      greaterThan(tester.getSize(boxOf('on your')).height),
    );
  });
  testWidgets('the declared leading is what the words are actually stacked on', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(card));

    // Font-independent by construction: a line's rendered box height, over the
    // font size it ended up rendered at, IS its leading factor — and both are
    // readable here, because the paragraph is laid out at the 100px reference
    // size inside the FittedBox (so the scale is inner width / natural width).
    //
    // This is the assertion that would have caught the real defect: with a
    // `TextHeightBehavior` that turns off first-ascent/last-descent, the height
    // multiplier stops applying to a one-line Text and the ratio comes out at
    // the font's own line box (~1.0em here, ~1.27em on DM Sans) — words a third
    // of a line apart, and no height left for the value.
    const innerWidth = 168.0 - 32;
    final referenceFontSize = tester
        .widget<Text>(find.text('on your'))
        .style!
        .fontSize!;
    final naturalWidth = tester
        .renderObject<RenderParagraph>(find.text('on your'))
        .size
        .width;
    final renderedFontSize = referenceFontSize * (innerWidth / naturalWidth);
    final leading = tester.getSize(boxOf('on your')).height / renderedFontSize;

    expect(leading, moreOrLessEquals(FitCard.lineHeight, epsilon: 0.02));
    expect(
      leading,
      lessThan(0.95),
      reason: 'the leading must beat the font\'s own line box, not restate it',
    );
  });

  testWidgets('the value is scaled to the card just like the words', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(card));

    const innerWidth = 168.0 - 32;
    final cardBox = tester.getRect(find.byType(FitCard));
    final hero = tester.getRect(boxOf('42'));

    // The same `fitWidth` treatment the copy above it gets: the number carries
    // the card instead of sitting in a corner of it.
    expect(
      hero.width,
      moreOrLessEquals(innerWidth, epsilon: 0.5),
      reason: 'the value must span the card edge to edge',
    );
    expect(hero.left, moreOrLessEquals(cardBox.left + 16, epsilon: 0.5));

    // And it is pinned to the bottom edge, with the label directly above it.
    expect(
      hero.bottom,
      moreOrLessEquals(cardBox.bottom - 16, epsilon: 0.5),
      reason: 'the value must sit on the card\'s bottom padding',
    );
    expect(
      tester.getRect(find.text('EU')).bottom,
      lessThanOrEqualTo(hero.top + 0.5),
    );
  });

  group('a hero value with a mark of its own', () {
    // The ON SALE poster's number: `61` is what the card is about, `%` only
    // says what it counts — so it rides at the top of the digits, small.
    const sale = FitCard(
      lines: ['ON', 'SALE'],
      heroValue: '61',
      heroValueSuffix: '%',
    );

    testWidgets('draws the mark at the top of the digits, sized from the card', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(sale));

      const innerWidth = 168.0 - 32;
      final cardBox = tester.getRect(find.byType(FitCard));
      final number = tester.getRect(boxOf('61'));
      final mark = tester.getRect(find.text('%'));

      // A fraction of the card like the caption and the footer — so it scales
      // with its cell instead of reading huge on a small tile.
      expect(
        tester.widget<Text>(find.text('%')).style!.fontSize!,
        moreOrLessEquals(
          innerWidth * FitCard.heroSuffixSizeOfWidth,
          epsilon: 0.01,
        ),
      );

      // Raised: its top is the digits' top and its own short line box stops
      // well above their bottom — a superscript, not a character sitting on the
      // digits' baseline.
      expect(mark.top, moreOrLessEquals(number.top, epsilon: 0.5));
      expect(mark.bottom, lessThan(number.bottom));
      expect(mark.height, lessThan(number.height));

      // It takes the last fraction of the line, and the digits carry the rest.
      expect(mark.right, moreOrLessEquals(cardBox.right - 16, epsilon: 0.5));
      expect(number.left, moreOrLessEquals(cardBox.left + 16, epsilon: 0.5));
      expect(number.width, greaterThan(innerWidth * 0.7));

      // And the pair is one line, so the number still lands on the bottom edge.
      expect(
        number.bottom,
        moreOrLessEquals(cardBox.bottom - 16, epsilon: 0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mark is part of the value when the card is announced', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(sale));

      // `61%` is one word to a listener, not a value and a fragment after it.
      expect(find.bySemanticsLabel('ON SALE 61%'), findsOneWidget);
      expect(find.bySemanticsLabel('61'), findsNothing);
      handle.dispose();
    });

    testWidgets('a mark needs a value to sit on', (tester) async {
      expect(
        () => FitCard(lines: kLines, heroValueSuffix: '%'),
        throwsAssertionError,
      );
    });
  });

  testWidgets('the label stays a caption and scales with the card', (
    tester,
  ) async {
    double labelSize() => tester.widget<Text>(find.text('EU')).style!.fontSize!;

    await tester.pumpWidget(wrap(card, width: 120));
    final onSmall = labelSize();
    await tester.pumpWidget(wrap(card, width: 400));
    final onLarge = labelSize();

    // Proportional, not a fixed pixel size that would read huge on a small tile
    // and get lost on a large one. The ratio is the *inner* widths' — the
    // padding does not scale, so a 400px card's caption is 4.2× a 120px card's.
    expect(
      onLarge / onSmall,
      moreOrLessEquals((400 - 32) / (120 - 32), epsilon: 0.1),
    );
    // And it stays a caption: a fraction of the card, unlike the value under it.
    expect(onSmall, lessThan(0.2 * (120 - 32)));
  });

  testWidgets('the lines stack with no space between them', (tester) async {
    await tester.pumpWidget(wrap(card));

    // Adjacent boxes in the Column: the bottom of one IS the top of the next.
    // A stray SizedBox would show up here as a gap.
    for (var i = 0; i < kLines.length - 1; i++) {
      expect(
        tester.getRect(boxOf(kLines[i])).bottom,
        moreOrLessEquals(
          tester.getRect(boxOf(kLines[i + 1])).top,
          epsilon: 0.5,
        ),
      );
    }
  });

  testWidgets('the OS text scale cannot distort the card', (tester) async {
    await tester.pumpWidget(wrap(card));
    final atDefault = [
      for (final line in kLines) tester.getSize(boxOf(line)),
      tester.getSize(boxOf('42')),
    ];

    await tester.pumpWidget(
      wrap(card, textScaler: const TextScaler.linear(2.0)),
    );
    final atMaxScale = [
      for (final line in kLines) tester.getSize(boxOf(line)),
      tester.getSize(boxOf('42')),
    ];

    // The card scales with its cell, not with the system setting — so the two
    // must be identical. (This is why the Texts carry noScaling.)
    expect(atMaxScale, atDefault);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long hero value still fits without overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const FitCard(lines: kLines, heroLabel: 'EU', heroValue: '42.5')),
    );

    final cardBox = tester.getRect(find.byType(FitCard));
    final hero = tester.getRect(boxOf('42.5'));
    expect(hero.width, lessThanOrEqualTo(cardBox.width - 32 + 0.5));
    expect(hero.bottom, moreOrLessEquals(cardBox.bottom - 16, epsilon: 0.5));
    expect(find.text('42.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in const [120.0, 168.0, 320.0, 430.0]) {
    testWidgets('lays out at ${width}px wide with no overflow', (tester) async {
      await tester.pumpWidget(wrap(card, width: width));

      for (final line in kLines) {
        expect(
          tester.getSize(boxOf(line)).width,
          moreOrLessEquals(width - 32, epsilon: 0.5),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a value and its label survive a card that is too short for them',
    (tester) async {
      // The failure this guards: on device the three words consumed the whole
      // card, so the value was squeezed to nothing and a sub-pixel overflow was
      // reported. A cell far worse than that must still keep the value on the
      // card, and must never overflow.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 200, height: 90, child: card)),
          ),
        ),
      );

      expect(find.text('42'), findsOneWidget);
      expect(tester.getSize(boxOf('42')).height, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'exposes one combined label, and only claims a button when tappable',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(card));

      expect(find.bySemanticsLabel('Based on your size EU 42'), findsOneWidget);
      // Fragments must not be announced separately.
      expect(find.bySemanticsLabel('Based'), findsNothing);

      await tester.pumpWidget(
        wrap(
          FitCard(
            lines: kLines,
            heroLabel: 'EU',
            heroValue: '42',
            onTap: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Based on your size EU 42'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('the whole card is the tap target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        FitCard(
          lines: kLines,
          heroLabel: 'EU',
          heroValue: '42',
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(FitCard)));
    await tester.pump();
    expect(taps, 1);
  });

  group('a hero widget', () {
    // A mark, not a word: the "See more" arrow's contract is a fixed intrinsic
    // size (140×100) that the card scales as a block.
    const mark = SizedBox(
      key: ValueKey('mark'),
      width: 140,
      height: 100,
      child: ColoredBox(color: Colors.blue),
    );

    const seeMore = FitCard(
      lines: ['See', 'more'],
      heroWidget: mark,
      semanticsLabel: 'See more products',
    );

    /// The box the mark is scaled into — its own sizes are the mark's, not the
    /// box's, so this is what says how big the mark is drawn.
    Finder markBox() => find
        .ancestor(
          of: find.byKey(const ValueKey('mark')),
          matching: find.byType(FittedBox),
        )
        .first;

    testWidgets('keeps its own proportion, bottom-left, on part of the width', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(seeMore));

      final cardBox = tester.getRect(find.byType(FitCard));
      final box = tester.getRect(markBox());
      const innerWidth = 168.0 - 32;

      // A fraction of the inner width rather than all of it: a glyph stretched
      // edge to edge would read as a banner, not as part of the poster.
      expect(box.width, moreOrLessEquals(innerWidth * 0.68, epsilon: 0.5));
      expect(box.left, moreOrLessEquals(cardBox.left + 16, epsilon: 0.5));
      // And it sits on the bottom edge the value would sit on, so a card with
      // a widget hero has no dead space under it either.
      expect(box.bottom, moreOrLessEquals(cardBox.bottom - 16, epsilon: 0.5));
      // Its own 140×100 proportion survives — it is not fitted to the card's.
      expect(box.height, moreOrLessEquals(box.width * 100 / 140, epsilon: 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scales with the card rather than at a fixed size', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(seeMore, width: 120));
      final onSmall = tester.getRect(markBox()).width;
      await tester.pumpWidget(wrap(seeMore, width: 400));
      final onLarge = tester.getRect(markBox()).width;

      expect(
        onLarge / onSmall,
        moreOrLessEquals((400 - 32) / (120 - 32), epsilon: 0.1),
      );
    });

    testWidgets('the words stay the loudest thing on the card', (tester) async {
      await tester.pumpWidget(wrap(seeMore));

      // The mark carries the card without taking it over: both words are still
      // scaled to the full inner width. ('See' is the shortest line, so it is
      // the tallest box — the same rhythm the reference tile has.)
      for (final line in const ['See', 'more']) {
        expect(
          tester.getSize(boxOf(line)).width,
          moreOrLessEquals(168.0 - 32, epsilon: 0.5),
        );
      }
      expect(
        tester.getSize(boxOf('See')).height,
        greaterThan(tester.getSize(boxOf('more')).height),
      );
      expect(
        tester.getRect(boxOf('more')).bottom,
        lessThanOrEqualTo(tester.getRect(markBox()).top + 0.5),
      );
    });

    testWidgets('a caller label wins, since a mark contributes no words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(seeMore));

      expect(find.bySemanticsLabel('See more products'), findsOneWidget);
      expect(find.bySemanticsLabel('See more'), findsNothing);
      handle.dispose();
    });

    testWidgets('a card never carries two heroes', (tester) async {
      expect(
        () => FitCard(lines: kLines, heroValue: '42', heroWidget: mark),
        throwsAssertionError,
      );
    });
  });

  group('a footer', () {
    // The "The Workshop Collection" poster's shape: the words, then a quiet
    // word in the corner, and no hero between them. Four lines, because this is
    // the one card whose name is spelled out.
    const poster = FitCard(
      lines: ['THE', 'WORK', 'SHOP', 'COLLECTION'],
      footerLabel: 'Low to High',
      semanticsLabel: 'The Workshop Collection, sorted by Price: Low to High.',
    );

    testWidgets('closes the card in the bottom-right corner', (tester) async {
      await tester.pumpWidget(wrap(poster));

      final cardBox = tester.getRect(find.byType(FitCard));
      final footer = tester.getRect(find.text('Low to High'));

      // The inner box's edge (16 padding) less the footer's own inset, which
      // holds the word off the corner's clip.
      expect(
        footer.right,
        moreOrLessEquals(
          cardBox.right - 16 - (168 - 32) * FitCard.footerInsetOfWidth,
          epsilon: 0.5,
        ),
      );
      expect(
        footer.bottom,
        moreOrLessEquals(cardBox.bottom - 16, epsilon: 0.5),
        reason: 'the footer takes the bottom edge the hero would have taken',
      );
      // The words stay against the top, and the height between them is the
      // poster's own gap — the footer is not pushed up under them.
      expect(
        tester.getRect(boxOf('THE')).top,
        moreOrLessEquals(cardBox.top + 16, epsilon: 0.5),
      );
      expect(
        footer.top,
        greaterThan(tester.getRect(boxOf('COLLECTION')).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('four lines are allowed, each still scaled to the width', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(poster));

      const innerWidth = 168.0 - 32;
      for (final line in const ['THE', 'WORK', 'SHOP', 'COLLECTION']) {
        expect(
          tester.getSize(boxOf(line)).width,
          moreOrLessEquals(innerWidth, epsilon: 0.5),
        );
      }
      // The rhythm the poster depends on: shorter word, bigger glyphs.
      expect(
        tester.getSize(boxOf('WORK')).height,
        greaterThan(tester.getSize(boxOf('COLLECTION')).height),
      );
    });

    testWidgets('is sized from the card rather than in pixels', (tester) async {
      double size() =>
          tester.widget<Text>(find.text('Low to High')).style!.fontSize!;

      await tester.pumpWidget(wrap(poster, width: 120));
      final onSmall = size();
      await tester.pumpWidget(wrap(poster, width: 400));
      final onLarge = size();

      // The same rule the `EU` label follows: a fraction of the card, so it
      // stays a caption on any tile instead of a fixed size that reads huge on
      // a small one and gets lost on a large one.
      expect(
        onLarge / onSmall,
        moreOrLessEquals((400 - 32) / (120 - 32), epsilon: 0.1),
      );
      expect(
        onSmall,
        moreOrLessEquals((120 - 32) * FitCard.footerSizeOfWidth, epsilon: 0.01),
      );
      // And it stays a caption: a corner mark, not a second headline.
      expect(onSmall, lessThan(0.2 * (120 - 32)));
    });

    testWidgets('a card of words alone is legal, and has no closer', (
      tester,
    ) async {
      // Both closers are optional now: `lines` is the only required thing.
      await tester.pumpWidget(
        wrap(
          const FitCard(lines: kLines, semanticsLabel: 'Based on your size'),
        ),
      );

      expect(find.text('Based'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a footer and a hero are mutually exclusive', (tester) async {
      expect(
        () => FitCard(lines: kLines, heroValue: '42', footerLabel: 'Featured'),
        throwsAssertionError,
      );
      // The label belongs to the hero it sits above, so a footer cannot take
      // one silently.
      expect(
        () => FitCard(lines: kLines, heroLabel: 'EU', footerLabel: 'Featured'),
        throwsAssertionError,
      );
    });
  });

  group('the ink clears AA on the fill in both brightnesses', () {
    for (final (name, brightness, palette) in [
      ('light', Brightness.light, AppPalette.light),
      ('dark', Brightness.dark, AppPalette.dark),
    ]) {
      testWidgets(name, (tester) async {
        AppBrightness.set(brightness);
        await tester.pumpWidget(wrap(card));

        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(FitCard),
            matching: find.byType(Material),
          ),
        );
        final fill = material.color!;
        final ink = tester.widget<Text>(find.text('Based')).style!.color!;
        final accent = tester.widget<Text>(find.text('42')).style!.color!;

        expect(fill, palette.subtle);
        expect(accent, palette.primaryInk);
        expect(_contrast(ink, fill), greaterThanOrEqualTo(4.5));
        expect(_contrast(accent, fill), greaterThanOrEqualTo(4.5));
      });
    }
  });
}
