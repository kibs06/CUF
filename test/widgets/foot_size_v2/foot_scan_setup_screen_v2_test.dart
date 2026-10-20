import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/customer/foot_capture_screen.dart';
import 'package:app/screens/customer/foot_size_v2/foot_scan_setup_screen_v2.dart';
import 'package:app/screens/customer/foot_manual_measure_screen.dart';

/// Setup screen coverage after the AR camera scan removal: the default mode
/// is Card scan, Tap swaps the CTA, and each CTA opens its own flow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const MethodChannel permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    // The screen pre-flights camera permission as it mounts.
    mockMessenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      if (call.method == 'checkPermissionStatus' ||
          call.method == 'requestPermissions') {
        return 1; // PermissionStatus.granted
      }
      return null;
    });
  });

  tearDown(() {
    mockMessenger.setMockMethodCallHandler(permissionsChannel, null);
  });

  Future<void> pumpSetup(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: FootScanSetupScreenV2()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('defaults to Card scan with card guidance', (tester) async {
    await pumpSetup(tester);

    expect(find.text('Card scan'), findsOneWidget);
    expect(find.text('Tap to measure'), findsOneWidget);
    expect(find.text('Camera scan'), findsNothing);
    expect(find.text('Start card scan'), findsOneWidget);
    expect(find.text('Start scanning'), findsNothing);
    expect(find.text('Start tapping'), findsNothing);
    // Row titles render as-is; only section labels are uppercased.
    expect(find.text('Place a card flat beside your foot'), findsOneWidget);
    // Both remaining modes measure both feet themselves: no feet choice.
    expect(find.text('WHICH FEET'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tap to measure swaps the CTA and guidance', (tester) async {
    await pumpSetup(tester);

    await tester.tap(find.text('Tap to measure'));
    await tester.pump();

    expect(find.text('Start tapping'), findsOneWidget);
    expect(find.text('Start card scan'), findsNothing);
    expect(find.text('Tap the widest points'), findsOneWidget);
    expect(find.text('Place a card flat beside your foot'), findsNothing);
    expect(find.text('WHICH FEET'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tap to measure opens the manual tap flow', (tester) async {
    // The manual flow asks for the camera with requestPermissions, which
    // answers with a map of permission -> status (camera = 0, granted = 1).
    mockMessenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      if (call.method == 'requestPermissions') return <int, int>{0: 1};
      if (call.method == 'checkPermissionStatus') return 1;
      return null;
    });

    await pumpSetup(tester);

    await tester.tap(find.text('Tap to measure'));
    await tester.pump();
    await tester.tap(find.text('Start tapping'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(FootManualMeasureScreen), findsOneWidget);
    expect(find.byType(FootCaptureScreen), findsNothing);
  });

  testWidgets('Card scan opens the card capture flow', (tester) async {
    // The capture screen requests camera permission with requestPermissions,
    // which answers with a map of permission -> status (camera = 0).
    mockMessenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      if (call.method == 'requestPermissions') return <int, int>{0: 1};
      if (call.method == 'checkPermissionStatus') return 1;
      return null;
    });

    await pumpSetup(tester);

    await tester.tap(find.text('Start card scan'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(FootCaptureScreen), findsOneWidget);
    expect(find.byType(FootManualMeasureScreen), findsNothing);
  });
}
