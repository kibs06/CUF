import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/customer/foot_capture_screen.dart';

/// The capture screen gates each foot behind an intro overlay ("Scan your
/// left foot" + "I understand") so the customer always knows which foot to
/// scan. Detection only starts on dismissal.
///
/// Camera permission is denied here on purpose: the overlay sits above the
/// error state, so show/dismiss is testable without a camera mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const MethodChannel permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    mockMessenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      if (call.method == 'requestPermissions') return <int, int>{0: 0};
      if (call.method == 'checkPermissionStatus') return 0;
      return null;
    });
  });

  tearDown(() {
    mockMessenger.setMockMethodCallHandler(permissionsChannel, null);
  });

  testWidgets('left-foot intro appears on entry and dismisses on confirm',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FootCaptureScreen(paperSize: 'card', footCondition: 'bare'),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Scan your left foot'), findsOneWidget);
    expect(find.text('I understand'), findsOneWidget);

    await tester.tap(find.text('I understand'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Scan your left foot'), findsNothing);
    expect(find.text('I understand'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
