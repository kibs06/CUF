import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/store.dart';
import 'package:app/screens/store/widgets/store_hero_card.dart';

/// The store banner is now the ONLY way into a store — the full-width "Enter
/// Store" button that used to sit in the info strip below it is gone — so the
/// gesture is load-bearing and pinned here rather than left to a manual pass:
///
///   * a single tap fires,
///   * a flick across the card does NOT (it is a page of the carousel, and a
///     tap only completes when the finger stays put),
///   * the hit area is the card and nothing else — the 6px margin either side
///     is the carousel's peek gutter and belongs to the neighbouring store,
///   * holding the card dips it and releasing puts it back, because a tap
///     whose only feedback is a screen change 300ms later reads as ignored,
///   * removing the callback (the card used on its own) crashes nothing.
///
/// No `bannerUrl` / `logoUrl`: those render through `CachedNetworkImage`, which
/// has no image to fetch in a widget test. The card's own gradient stands in,
/// and the layers above it are exactly the ones a real tap has to get through.
Store store() => Store(
  id: 's1',
  name: 'Valladolid Leather Co.',
  tagline: 'Tradition stitched into every sole',
  location: 'Valladolid, Carcar City, Cebu',
  createdAt: DateTime(2026, 1, 1),
);

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  /// The card's own scale, as the widget receives it. The card has exactly one
  /// [AnimatedScale] — the page scale and the press dip are multiplied into it
  /// rather than nested, so there is nothing to disambiguate here.
  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('a tap on the banner enters the store', (tester) async {
    var entered = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(store: store(), productCount: 9, onTap: () => entered++),
      ),
    );

    await tester.tap(find.byType(StoreHeroCard));
    await tester.pumpAndSettle();

    expect(entered, 1);
  });

  testWidgets('a flick across the card does not', (tester) async {
    var entered = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(store: store(), productCount: 9, onTap: () => entered++),
      ),
    );

    // The same surface is the page the carousel is flicked through: a drag
    // beyond the touch slop must cancel the tap, or every swipe would land in
    // whichever store the finger lifted on.
    await tester.drag(find.byType(StoreHeroCard), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(entered, 0);
    expect(
      scaleOf(tester),
      1.0,
      reason:
          'a cancelled press must not leave the card stuck sunken — the '
          'drag starts as a press-down, so this is the onTapCancel path',
    );
  });

  testWidgets('the peek gutter beside the card is not part of the target', (
    tester,
  ) async {
    var entered = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(store: store(), productCount: 9, onTap: () => entered++),
      ),
    );

    // The card is drawn 6px in from its own box on each side (the carousel's
    // peek gutter). Both edges must be dead.
    final box = tester.getRect(find.byType(StoreHeroCard));
    for (final probe in [
      box.topLeft + const Offset(2, 130), // inside the left gutter
      box.topRight + const Offset(-2, 130), // inside the right gutter
    ]) {
      await tester.tapAt(probe);
      await tester.pumpAndSettle();
    }

    expect(entered, 0);
  });

  testWidgets('a press dips the card, and releasing puts it back', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(StoreHeroCard(store: store(), productCount: 9, onTap: () {})),
    );
    expect(scaleOf(tester), 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StoreHeroCard)),
    );
    // Past the tap-down deadline, still held: no tap has fired yet.
    await tester.pump(const Duration(milliseconds: 150));
    final pressed = scaleOf(tester);
    expect(
      pressed,
      lessThan(1.0),
      reason:
          'holding the card must dip it — a tap with no feedback until '
          'the navigation lands feels ignored',
    );
    expect(
      pressed,
      greaterThan(0.9),
      reason: 'a whole storefront should not visibly shrink',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      scaleOf(tester),
      1.0,
      reason: 'the card must return to the page scale after the press',
    );
  });

  testWidgets('a press does not dip a card with no action', (tester) async {
    await tester.pumpWidget(
      wrap(StoreHeroCard(store: store(), productCount: 9)),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StoreHeroCard)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      scaleOf(tester),
      1.0,
      reason: 'feedback for an action must not fire when there is none',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the press dip keeps the page scale underneath it', (
    tester,
  ) async {
    // The carousel scales the focused card up/down as it swipes; the dip is a
    // *factor* on that, not a replacement for it.
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          scale: 0.95, // a card that is not the focused page
          productCount: 9,
          onTap: () {},
        ),
      ),
    );
    expect(scaleOf(tester), closeTo(0.95, 0.0001));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StoreHeroCard)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      scaleOf(tester),
      closeTo(0.95 * 0.97, 0.0001),
      reason: 'the dip must compound with the page scale, not override it',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the card renders without a callback', (tester) async {
    await tester.pumpWidget(
      wrap(StoreHeroCard(store: store(), productCount: 9)),
    );

    await tester.tap(find.byType(StoreHeroCard));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
