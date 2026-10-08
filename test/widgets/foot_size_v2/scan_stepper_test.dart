import 'package:app/providers/v2/scan_phase.dart';
import 'package:app/widgets/foot_size_v2/scan_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: ColoredBox(color: Colors.black, child: Center(child: child)),
      );

  Finder dotOf(int i) => find.byKey(ValueKey('step-dot-$i'));

  const bothFeet = [CaptureStep.leftTop, CaptureStep.rightTop];
  const oneFoot = [CaptureStep.rightTop];

  testWidgets('renders one dot per step of a two-foot plan', (tester) async {
    await tester.pumpWidget(
      host(const ScanStepper(activeIndex: 0, steps: bothFeet)),
    );
    expect(dotOf(0), findsOneWidget);
    expect(dotOf(1), findsOneWidget);
    expect(dotOf(2), findsNothing);
  });

  testWidgets('a one-foot plan shows a single dot', (tester) async {
    await tester.pumpWidget(
      host(const ScanStepper(activeIndex: 0, steps: oneFoot)),
    );
    expect(dotOf(0), findsOneWidget);
    expect(dotOf(1), findsNothing);
    expect(find.text('R·T'), findsOneWidget);
  });

  testWidgets('active segment shows its label, done segments show a check',
      (tester) async {
    // Step index 1 active (right top) → step 0 completed.
    await tester.pumpWidget(
      host(const ScanStepper(activeIndex: 1, steps: bothFeet)),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('R·T'), findsOneWidget);
    expect(find.text('L·T'), findsNothing); // replaced by check
  });

  testWidgets('null activeIndex leaves all segments upcoming', (tester) async {
    await tester.pumpWidget(
      host(const ScanStepper(activeIndex: null, steps: bothFeet)),
    );
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('L·T'), findsOneWidget);
    expect(find.text('R·T'), findsOneWidget);
  });
}
