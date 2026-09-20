import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/press_sink.dart';

/// `PressSink` is the press feedback every product card uses. Its whole reason
/// for existing is *when* the pressed state is on: a press ends four ways
/// (`onTapUp`, `onTapCancel`, a finger that drifts off the card, or a lost
/// gesture arena) and a card left sunk after any of them is the bug this pins
/// away. The shadow itself is lerped — one shadow moving, not two swapping —
/// which is why the two lists have to pair up layer for layer.

const BoxShadow idle = BoxShadow(
  color: Color(0x1A8B5A2B),
  blurRadius: 16,
  offset: Offset(0, 6),
  spreadRadius: -4,
);
const BoxShadow contactIdle = BoxShadow(
  color: Color(0x0D8B5A2B),
  blurRadius: 3,
  offset: Offset(0, 1),
);
const BoxShadow pressed = BoxShadow(
  color: Color(0x128B5A2B),
  blurRadius: 6,
  offset: Offset(0, 2),
  spreadRadius: -2,
);
const BoxShadow contactPressed = BoxShadow(
  color: Color(0x0D8B5A2B),
  blurRadius: 2,
  offset: Offset(0, 1),
);

const List<BoxShadow> idleShadow = [idle, contactIdle];
const List<BoxShadow> pressedShadow = [pressed, contactPressed];

const Key cardKey = Key('card');

Widget harness({
  VoidCallback? onTap,
  bool reducedMotion = false,
}) {
  Widget sink = PressSink(
    onTap: onTap,
    idle: idleShadow,
    pressed: pressedShadow,
    borderRadius: BorderRadius.circular(16),
    child: const SizedBox(key: cardKey, width: 200, height: 200),
  );
  if (reducedMotion) {
    sink = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: sink,
    );
  }
  return Directionality(
    textDirection: TextDirection.ltr,
    // Centered so the card keeps the 200x200 it asks for instead of being
    // stretched by the test view's tight constraints.
    child: Center(child: sink),
  );
}

/// The shadow the sink is painting right now.
List<BoxShadow>? painted(WidgetTester tester) =>
    (tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration)
        .boxShadow;

void main() {
  testWidgets('the card rests on the idle shadow', (tester) async {
    await tester.pumpWidget(harness());

    expect(painted(tester), idleShadow);
    expect(
      tester.getSize(find.byKey(cardKey)),
      const Size(200, 200),
      reason: 'the sink must not resize the card it wraps',
    );
  });

  testWidgets('a finger on the card sinks it, and letting go lifts it back', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cardKey)),
    );
    await tester.pumpAndSettle();
    expect(painted(tester), pressedShadow);

    // Both layers move together: the ambient one pulls in and drops, the
    // contact one tightens — the press is an interpolation of one shadow.
    expect(painted(tester)!.first.blurRadius, lessThan(idle.blurRadius));
    expect(painted(tester)!.first.offset.dy, lessThan(idle.offset.dy));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(painted(tester), idleShadow);
  });

  testWidgets('it moves while the finger is down rather than jumping', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cardKey)),
    );
    await tester.pump();
    await tester.pump(PressSink.duration ~/ 2);
    final midway = painted(tester)!.first.blurRadius;
    expect(
      midway,
      lessThan(idle.blurRadius),
      reason: 'the shadow must have started moving',
    );
    expect(
      midway,
      greaterThan(pressed.blurRadius),
      reason: 'and must not have already arrived',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a finger that leaves the card lifts it back too', (
    tester,
  ) async {
    // This is `onTapCancel`: press, drag well off the card, release. Only
    // `onTapUp` would have been enough to miss it, and the card would have
    // stayed sunk for the rest of the session.
    await tester.pumpWidget(harness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cardKey)),
    );
    await tester.pumpAndSettle();
    expect(painted(tester), pressedShadow);

    await gesture.moveBy(const Offset(0, 400));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(painted(tester), idleShadow);
  });

  testWidgets('the tap still fires, after the press', (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(onTap: () => taps++));

    // `tapAt` rather than `tap`: the bare `SizedBox` is not part of the hit
    // test result (only the sink's own boxes are), and tapping it by finder
    // would warn about a "miss" that is exactly the hit we want.
    await tester.tapAt(tester.getCenter(find.byKey(cardKey)));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(painted(tester), idleShadow);
  });

  testWidgets('reduced motion swaps the shadows without animating', (
    tester,
  ) async {
    await tester.pumpWidget(harness(reducedMotion: true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cardKey)),
    );
    // No settle: one frame is all a zero-duration animation needs, and that is
    // the assertion — the state arrives at once, it just does not travel.
    await tester.pump();
    expect(painted(tester), pressedShadow);

    await gesture.up();
    await tester.pump();
    expect(painted(tester), idleShadow);
  });

  test('the two shadows must pair up layer for layer', () {
    expect(
      () => PressSink(
        idle: idleShadow,
        pressed: const [pressed],
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox(),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
