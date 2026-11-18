import 'package:app/widgets/order_confirmation_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared post-checkout screen. Both payment paths render it, so the
/// receipt must be readable and the actions wired regardless of how the
/// order was paid.
///
/// The success mark used to be animated by `checkout_screen.dart` only —
/// the GCash path passed no animation and showed it static. It now owns its
/// animation, which is why these tests exercise the widget directly.
void main() {
  Widget host({
    bool reduceMotion = false,
    VoidCallback? onTrack,
    VoidCallback? onHome,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: OrderConfirmationView(
            orderId: 'order-12345678',
            total: 500,
            paymentLabel: 'Cash on Pickup',
            onTrackOrder: onTrack ?? () {},
            onBackHome: onHome ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows the receipt a customer can check', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Thank You!'), findsOneWidget);
    expect(
      find.text('#12345678'),
      findsOneWidget,
      reason:
          'the short order id is the only handle the customer has if they '
          'need to ask about the order',
    );
    expect(find.text('₱500.00'), findsOneWidget);
    expect(find.text('Cash on Pickup'), findsOneWidget);
  });

  testWidgets('the success mark animates, then settles', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason: 'the circle/tick animation should be running this early',
    );

    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, isZero);
  });

  testWidgets('reduced motion skips straight to the finished mark', (
    tester,
  ) async {
    await tester.pumpWidget(host(reduceMotion: true));
    await tester.pump();

    expect(
      tester.binding.transientCallbackCount,
      isZero,
      reason:
          'the tick is information; a reduced-motion user must not wait '
          'for decoration to finish before the screen is usable',
    );
  });

  testWidgets('a short screen scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the receipt is taller than a 420dp viewport; it must scroll, '
          'not paint a RenderFlex overflow',
    );

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
      reason: 'the bottom actions have to be reachable on a short screen',
    );
  });

  testWidgets('both actions are wired', (tester) async {
    var tracked = false;
    var wentHome = false;

    await tester.pumpWidget(
      host(onTrack: () => tracked = true, onHome: () => wentHome = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Track My Order'));
    expect(tracked, isTrue);

    await tester.tap(find.text('Back to Home'));
    expect(wentHome, isTrue);
  });
}
