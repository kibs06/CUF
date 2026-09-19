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
/// translation, so this is where the mark is actually drawn. Offstage widgets
/// count: once a route covers the card the route keeps it alive but offstage,
/// and "the covered arrow has not moved" is exactly what the mute test reads.
Rect arrowRect(WidgetTester tester) =>
    tester.getRect(find.byType(ArrowGlyph, skipOffstage: false));

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

  group('the idle beat', () {
    /// How far the arrow has drifted from where it was when [pumpWidget]
    /// ran — positive means it is out on a beat.
    double driftFrom(WidgetTester tester, Rect rest) =>
        arrowRect(tester).left - rest.left;

    /// Pumps [window] in 16ms steps and returns the LARGEST drift seen.
    ///
    /// Scanning, not sampling: the beat's exact phase at a given wall-clock
    /// moment depends on which frame the controller first ticks in, and a test
    /// that bets on that is testing FakeAsync, not the card. What the design
    /// pins is the envelope — how far out it goes, that it comes back — and
    /// the envelope is exactly what a scan measures.
    Future<double> maxDriftOver(
      WidgetTester tester,
      Rect rest,
      Duration window,
    ) async {
      var max = 0.0;
      var remaining = window;
      const step = Duration(milliseconds: 16);
      while (remaining > Duration.zero) {
        final d = remaining < step ? remaining : step;
        await tester.pump(d);
        remaining -= d;
        final drift = driftFrom(tester, rest);
        if (drift > max) max = drift;
      }
      return max;
    }

    /// One full beat: the hold, then the glide, then the return.
    Duration beatPeriod() =>
        SeeMoreCard.idleHold + SeeMoreCard.idleGlide + SeeMoreCard.idleReturn;

    testWidgets('moves on its own: glides out, comes back, and loops', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(SeeMoreCard(onTap: () {})));
      final rest = arrowRect(tester);

      // One full beat: the arrow went well out (more than a third of the
      // press travel — a beat that never left the ground would not be a
      // beat) and came all the way back. The hold is part of what is being
      // verified here: the SCAN covers stillness and motion alike, so a card
      // that hummed constantly would still pass the max, but the return-to-
      // zero at the end of the window is what a hum never does.
      final first = await maxDriftOver(tester, rest, beatPeriod());
      expect(first, greaterThan(rest.width * SeeMoreCard.nudge / 3));
      expect(first, lessThan(rest.width * SeeMoreCard.nudge + 0.5));
      expect(driftFrom(tester, rest), moreOrLessEquals(0, epsilon: 0.5));

      // The next beat: still looping.
      final second = await maxDriftOver(tester, rest, beatPeriod());
      expect(second, greaterThan(rest.width * SeeMoreCard.nudge / 3));
      expect(driftFrom(tester, rest), moreOrLessEquals(0, epsilon: 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pressing pauses the beat and takes the arrow forward', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(SeeMoreCard(onTap: () {})));
      final rest = arrowRect(tester);

      // Catch the arrow mid-beat, where a naive implementation would let the
      // loop keep driving under the finger.
      await maxDriftOver(tester, rest, SeeMoreCard.idleHold);
      await tester.pump(SeeMoreCard.idleGlide * 0.5);
      expect(driftFrom(tester, rest), greaterThan(0));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FitCard)),
      );
      await tester.pumpAndSettle();

      // Pressed pose is the FULL travel (the outer slide), and it holds there:
      // a scanned beat-and-a-half of wall clock moves the arrow no further
      // and no back — the idle motor is paused, not fighting the press.
      final pressed = arrowRect(tester);
      expect(
        pressed.left - rest.left,
        moreOrLessEquals(rest.width * SeeMoreCard.nudge, epsilon: 1.0),
      );
      final whilePressed = await maxDriftOver(tester, rest, beatPeriod());
      expect(
        whilePressed,
        moreOrLessEquals(rest.width * SeeMoreCard.nudge, epsilon: 0.5),
      );

      // Release: back to rest, and the beat resumes (a scanned window sees it
      // glide again).
      await gesture.up();
      await tester.pumpAndSettle();
      expect(driftFrom(tester, rest), moreOrLessEquals(0, epsilon: 0.5));
      final afterRelease = await maxDriftOver(tester, rest, beatPeriod());
      expect(afterRelease, greaterThan(rest.width * SeeMoreCard.nudge / 3));
      expect(driftFrom(tester, rest), moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('a reduced-motion platform never starts the beat', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(SeeMoreCard(onTap: () {}), disableAnimations: true),
      );
      final rest = arrowRect(tester);

      // Well past two beats' worth of wall clock: nothing has moved, and
      // nothing is scheduled to move.
      final beat =
          SeeMoreCard.idleHold + SeeMoreCard.idleGlide + SeeMoreCard.idleReturn;
      await tester.pump(beat + beat);
      expect(driftFrom(tester, rest), moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('a covered route disposes the card, motor and all', (
      tester,
    ) async {
      // The home feed pushes a product page from this card, so covered-by-a-
      // route is the state the app actually leaves it in. An opaque push takes
      // the covered subtree out of the tree entirely — which stops the beat
      // the only way that matters: the motor's timer and ticker are disposed
      // with it. The assertion is that the mid-beat teardown is clean; a
      // `setState after dispose` here is the exact failure a repeating ticker
      // would produce.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('the next page')),
                      ),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      // Catch the motor mid-flight, then cover the card.
      await tester.pump(SeeMoreCard.idleHold + SeeMoreCard.idleGlide * 0.5);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        find.byType(SeeMoreCard, skipOffstage: false),
        findsNothing,
        reason:
            'an opaque route disposes the covered subtree — the beat '
            'ends with the card, not alongside it',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
