import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/double_back_to_exit.dart';

/// The double-back contract: the first system back only warns, the second one
/// inside the grace exits, and a late second press starts over.
void main() {
  Widget wrap(DoubleBackToExit guard) {
    return MaterialApp(home: guard);
  }

  Future<List<MethodCall>> backTwice(
    WidgetTester tester, {
    Duration gap = Duration.zero,
    bool realTimeGap = false,
  }) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      wrap(const DoubleBackToExit(child: Scaffold(body: Text('shell root')))),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    if (gap > Duration.zero) {
      if (realTimeGap) {
        // The grace is measured in wall-clock time, so fake-async pumps
        // cannot age it out — wait it out for real instead.
        await tester.runAsync(() => Future<void>.delayed(gap));
      }
      await tester.pump(gap);
    }
    await tester.binding.handlePopRoute();
    await tester.pump();
    return calls;
  }

  bool popped(List<MethodCall> calls) =>
      calls.any((c) => c.method == 'SystemNavigator.pop');

  testWidgets('the first back only warns — the shell stays', (tester) async {
    await tester.pumpWidget(
      wrap(const DoubleBackToExit(child: Scaffold(body: Text('shell root')))),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('shell root'), findsOneWidget);
  });

  testWidgets('a second back inside the grace exits', (tester) async {
    final calls = await backTwice(tester);

    expect(popped(calls), isTrue);
  });

  testWidgets('a second back after the grace starts over instead of exiting', (
    tester,
  ) async {
    final calls = await backTwice(
      tester,
      gap: const Duration(seconds: 3),
      realTimeGap: true,
    );

    expect(popped(calls), isFalse);
    // A fresh warning, not an exit: the shell is still what is on screen.
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('shell root'), findsOneWidget);
  });
}
