import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/widgets/fit_card.dart';
import 'package:app/widgets/see_more_card.dart';

/// The \"See more\" cell that closes a capped home grid.
///
/// What is pinned here is that it is *the size poster with different copy*
/// rather than a new component — a [FitCard], so it inherits the fill, the edge,
/// the radius, the font and the per-line scaling for free, and the only thing it
/// adds is the mark and the press nudge. The mark is paint, so it contributes no
/// words: the card has to announce itself, and the whole card has to be the
/// target, or the arrow is a picture nobody can activate.
Widget wrap(
  Widget card, {
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        // Applied *inside* the app, onto the real ambient data: replacing the
        // whole `MediaQueryData` from outside would zero the viewport.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: textScaler,
          ),
          child: Center(
            child: SizedBox(
              width: 168,
              child: AspectRatio(aspectRatio: FitCard.aspectRatio, child: card),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The arrow's own rect, in global coordinates — [AnimatedSlide] is a paint
/// translation, so this is where the mark is actually drawn.
Rect arrowRect(WidgetTester tester) => tester.getRect(find.byType(ArrowGlyph));

void main() {
  testWidgets('is the size poster, with different copy', (tester) async {
    await tester.pumpWidget(wrap(SeeMoreCard(onTap: () {})));

    // One card, and it is the poster: no second component, no image, no icon.
    expect(find.byType(FitCard), findsOneWidget);
    expect(find.text('See'), findsOneWidget);
    expect(find.text('more'), findsOneWidget);
    expect(find.byType(ArrowGlyph), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mark is painted in the accent ink, not the words ink', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      AppBrightness.set(brightness);
      await tester.pumpWidget(wrap(SeeMoreCard(onTap: () {})));

      expect(
        tester.widget<ArrowGlyph>(find.byType(ArrowGlyph)).color,
        AppPalette.of(brightness).primaryInk,
      );
    }
  });

  testWidgets('announces itself as the one target it is', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(SeeMoreCard(onTap: () {})));

    // Assembled from the words alone the card would say \"See more\"; the mark is
    // paint, so the label has to be spelled.
    expect(find.bySemanticsLabel('See more products'), findsOneWidget);
    expect(find.bySemanticsLabel('See more'), findsNothing);
    handle.dispose();
  });

  testWidgets('the whole card is the tap target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(SeeMoreCard(onTap: () => taps++)));

    await tester.tapAt(tester.getCenter(find.byType(FitCard)));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('pressing nudges the arrow right and releasing returns it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(SeeMoreCard(onTap: () {})));

    final atRest = arrowRect(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FitCard)),
    );
    await tester.pumpAndSettle();

    final pressed = arrowRect(tester);
    expect(
      pressed.left - atRest.left,
      moreOrLessEquals(atRest.width * 0.06, epsilon: 1.0),
      reason: 'the nudge is a fraction of the mark, not a fixed distance',
    );
    expect(pressed.top, moreOrLessEquals(atRest.top, epsilon: 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(arrowRect(tester).left, moreOrLessEquals(atRest.left, epsilon: 0.5));
  });

  testWidgets('a reduced-motion platform keeps the card still', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(SeeMoreCard(onTap: () => taps++), disableAnimations: true),
    );

    final atRest = arrowRect(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FitCard)),
    );
    await tester.pumpAndSettle();

    expect(arrowRect(tester).left, moreOrLessEquals(atRest.left, epsilon: 0.5));

    // The ripple and the action stay — only the motion is skipped.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('survives a narrow phone at a large text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(SeeMoreCard(onTap: () {}), textScaler: const TextScaler.linear(1.5)),
    );

    // The card scales with its cell, not with the OS setting, so the mark keeps
    // its proportion and nothing overflows.
    final box = arrowRect(tester);
    expect(box.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
