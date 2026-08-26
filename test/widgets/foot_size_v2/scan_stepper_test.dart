import 'package:app/widgets/foot_size_v2/scan_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: ColoredBox(color: Colors.black, child: Center(child: child)),
      );

  Finder dotOf(int i) => find.byKey(ValueKey('step-dot-$i'));

  testWidgets('renders four step dots', (tester) async {
    await tester.pumpWidget(host(const ScanStepper(activeIndex: 0)));
    for (var i = 0; i < 4; i++) {
      expect(dotOf(i), findsOneWidget);
    }
  });

  testWidgets('active segment shows its label, done segments show a check',
      (tester) async {
    // Step index 2 active → steps 0 and 1 completed.
    await tester.pumpWidget(host(const ScanStepper(activeIndex: 2)));

    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    // Active + upcoming dots still show labels.
    expect(find.text('R·T'), findsOneWidget);
    expect(find.text('R·S'), findsOneWidget);
    expect(find.text('L·T'), findsNothing); // replaced by check
  });

  testWidgets('null activeIndex leaves all segments upcoming', (tester) async {
    await tester.pumpWidget(host(const ScanStepper(activeIndex: null)));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('L·T'), findsOneWidget);
    expect(find.text('R·S'), findsOneWidget);
  });
}
