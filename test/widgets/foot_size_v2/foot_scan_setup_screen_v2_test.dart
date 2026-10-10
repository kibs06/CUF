import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/customer/foot_size_v2/foot_scan_setup_screen_v2.dart';
import 'package:app/screens/customer/foot_size_v2/foot_scan_session_screen_v2.dart';
import 'package:app/screens/customer/foot_manual_measure_screen.dart';

/// The setup screen probes ARCore availability before it opens the camera, so a
/// phone that cannot run ARCore is told so here — instead of dropping into a
/// scan screen whose session start can only ever fail (which is what happened
/// on a vivo V2022: Google Play refuses to install com.google.ar.core).
///
/// Only a definitive `unsupported` answer may block the CTA; inconclusive
/// probes must leave the normal flow alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const MethodChannel arMethodChannel =
      MethodChannel('com.solevision/ar_foot_sizing');
  const MethodChannel permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  /// Availability the native probe reports, as the raw ARCore enum name.
  late String availability;

  setUp(() {
    availability = 'SUPPORTED_INSTALLED';

    mockMessenger.setMockMethodCallHandler(arMethodChannel, (call) async {
      if (call.method == 'checkAvailability') {
        return <Object?, Object?>{
          'availability': availability,
          'supported': availability.startsWith('SUPPORTED'),
          'installed': availability == 'SUPPORTED_INSTALLED',
        };
      }
      return null;
    });

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
    mockMessenger.setMockMethodCallHandler(arMethodChannel, null);
    mockMessenger.setMockMethodCallHandler(permissionsChannel, null);
  });

  Future<void> pumpSetup(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: FootScanSetupScreenV2()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a supported, installed device keeps the normal scan CTA',
      (tester) async {
    await pumpSetup(tester);

    expect(find.text('Start scanning'), findsOneWidget);
    expect(find.text('AR support needed'), findsNothing);
    expect(find.text("AR scanning isn't supported on this phone"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an inconclusive probe never blocks the CTA', (tester) async {
    availability = 'UNKNOWN_TIMED_OUT';
    await pumpSetup(tester);

    expect(find.text('Start scanning'), findsOneWidget);
    expect(find.text('AR scanning not supported here'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tap to measure swaps the CTA and drops the feet choice',
      (tester) async {
    await pumpSetup(tester);

    // Section titles are rendered uppercased.
    expect(find.text('WHICH FEET'), findsOneWidget);
    await tester.tap(find.text('Tap to measure'));
    await tester.pump();

    expect(find.text('Start tapping'), findsOneWidget);
    expect(find.text('Start scanning'), findsNothing);
    // The tap flow measures both feet itself, so the feet choice is hidden.
    expect(find.text('WHICH FEET'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tap to measure opens the manual tap flow, not the camera scan',
      (tester) async {
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
    expect(find.byType(FootScanSessionScreenV2), findsNothing);
  });

  testWidgets('an unsupported device is told before the camera ever opens',
      (tester) async {
    availability = 'UNSUPPORTED_DEVICE_NOT_CAPABLE';
    await pumpSetup(tester);

    expect(find.text('AR scanning not supported here'), findsOneWidget);
    expect(find.text("AR scanning isn't supported on this phone"), findsOneWidget);
    expect(find.textContaining('Enter size manually'), findsOneWidget);
    expect(find.text('Start scanning'), findsNothing);

    // The CTA is inert: tapping it must not open the scan screen at all.
    await tester.tap(find.text('AR scanning not supported here'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FootScanSessionScreenV2), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device that needs ARCore installed is pointed at Google Play',
      (tester) async {
    availability = 'SUPPORTED_NOT_INSTALLED';
    await pumpSetup(tester);

    expect(find.text('Install AR support'), findsOneWidget);
    expect(find.text('AR support needed'), findsOneWidget);
    expect(find.text("AR scanning isn't supported on this phone"), findsNothing);
    expect(find.text('Start scanning'), findsNothing);

    // Tapping hands off to the Play listing (no store plugin under flutter
    // test — the screen must swallow that and stay put, still not opening a
    // camera it cannot start).
    await tester.tap(find.text('Install AR support'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FootScanSessionScreenV2), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
