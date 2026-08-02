import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('SoleVision app startup smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SoleVisionApp());

    // Verify that our app name exists on the Splash screen
    expect(find.text('SoleVision'), findsOneWidget);

    // Advance virtual time clock to let the Splash timer complete
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
