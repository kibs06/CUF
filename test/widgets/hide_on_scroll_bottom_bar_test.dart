import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/hide_on_scroll_bottom_bar.dart';

/// The bar that gets out of the way: away on a downward drag, back on an
/// upward one, and never taken by a fling, a stray bounce or a horizontal
/// strip.
///
/// The [AnimatedSize]'s height *is* the assertion. The bar is collapsed and
/// clipped rather than removed from the tree, so `find` still finds it at every
/// moment — measuring the box is the honest way to ask whether it is on screen.

/// The page: a horizontal strip above a long vertical list, so a drag can be
/// aimed at either axis by key.
Widget page() => Column(
  children: [
    SizedBox(
      height: 60,
      child: ListView(
        key: const ValueKey('strip'),
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 20; i++)
            const SizedBox(width: 80, height: 60, child: Text('Chip')),
        ],
      ),
    ),
    Expanded(
      child: ListView.builder(
        key: const ValueKey('page'),
        itemCount: 40,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('Item $i')),
      ),
    ),
  ],
);

Widget host({
  Object? resetOn,
  double threshold = 24,
  ScrollController? controller,
}) => MaterialApp(
  home: Scaffold(
    body: HideOnScrollBottomBar(
      resetOn: resetOn,
      threshold: threshold,
      bar: const SizedBox(
        key: ValueKey('bar'),
        height: 80,
        width: double.infinity,
        child: ColoredBox(color: Color(0xFF123456)),
      ),
      child: controller == null ? page() : pageWith(controller),
    ),
  ),
);

Widget pageWith(ScrollController controller) => Column(
  children: [
    SizedBox(
      height: 60,
      child: ListView(
        key: const ValueKey('strip'),
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 20; i++)
            const SizedBox(width: 80, height: 60, child: Text('Chip')),
        ],
      ),
    ),
    Expanded(
      child: ListView.builder(
        key: const ValueKey('page'),
        controller: controller,
        itemCount: 40,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('Item $i')),
      ),
    ),
  ],
);

/// The bar's on-screen height — 80 while it is showing, 0 once it has left.
double barHeight(WidgetTester tester) =>
    tester.getSize(find.byType(AnimatedSize)).height;

Future<void> scrollPage(WidgetTester tester, double dy) async {
  await tester.drag(find.byKey(const ValueKey('page')), Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bar starts showing', (tester) async {
    await tester.pumpWidget(host());

    expect(barHeight(tester), 80);
  });

  testWidgets('a downward drag puts the bar away', (tester) async {
    await tester.pumpWidget(host());

    await scrollPage(tester, -200);

    expect(
      barHeight(tester),
      0,
      reason: 'the page should be readable on a full screen while scrolling',
    );
  });

  testWidgets('the first upward drag brings it back', (tester) async {
    await tester.pumpWidget(host());
    await scrollPage(tester, -200);
    expect(barHeight(tester), 0);

    await scrollPage(tester, 200);

    expect(
      barHeight(tester),
      80,
      reason: 'scrolling up is the gesture that means "take me somewhere"',
    );
  });

  testWidgets('a drag shorter than the threshold leaves it alone', (
    tester,
  ) async {
    await tester.pumpWidget(host(threshold: 100));

    await scrollPage(tester, -60);

    expect(
      barHeight(tester),
      80,
      reason: 'every-pixel reactions are what make an auto-hiding bar flicker',
    );
  });

  testWidgets('a direction reversal clears the travel it had built up', (
    tester,
  ) async {
    // 60 down, then 60 back up: neither direction ever reaches the 100px
    // threshold, so the bar must not move — this is the hysteresis that stops
    // a dithering drag from adding up to a move.
    await tester.pumpWidget(host(threshold: 100));

    await scrollPage(tester, -60);
    await scrollPage(tester, 60);

    expect(barHeight(tester), 80);
  });

  testWidgets('a programmatic return to the top restores it', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller: controller));
    await scrollPage(tester, -200);
    expect(barHeight(tester), 0);

    controller.jumpTo(0);
    await tester.pumpAndSettle();

    expect(
      barHeight(tester),
      80,
      reason: 'the top is where someone who lost the bar starts looking',
    );
  });

  testWidgets('a horizontal strip does not move the bar', (tester) async {
    await tester.pumpWidget(host());

    await tester.drag(
      find.byKey(const ValueKey('strip')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(
      barHeight(tester),
      80,
      reason: 'the category chips are not the page scrolling',
    );
  });

  testWidgets('changing the reset value brings the bar back', (tester) async {
    await tester.pumpWidget(host(resetOn: 0));
    await scrollPage(tester, -200);
    expect(barHeight(tester), 0);

    // The shell passes the active tab here, so switching tabs can never strand
    // the customer on a page whose bar is still hiding from the last one.
    await tester.pumpWidget(host(resetOn: 1));
    await tester.pumpAndSettle();

    expect(barHeight(tester), 80);
  });
}
