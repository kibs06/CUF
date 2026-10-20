import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/customer/foot_capture_screen.dart';
import 'package:app/screens/customer/foot_manual_measure_screen.dart';
import 'package:app/services/ar_core_channel.dart';

/// The manual screen's AR error branch through the real surface: transient
/// failures offer "Try again" (routed via retrySession), unsupported devices
/// offer card scan with the same prefs, and "Go Back" always pops.
///
/// The AR platform view is stubbed at the channel ('create' answers a fake
/// texture id); smart-assist is off so no sampler timer can fire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const MethodChannel arChannel =
      MethodChannel('com.solevision/ar_foot_sizing');
  const MethodChannel permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  const MethodChannel platformViewsChannel =
      MethodChannel('flutter/platform_views');

  /// Scripted native answers for the current test.
  late Map<String, Object?> startResult;
  late Map<String, Object?> retryResult;
  late int retryCalls;

  Map<String, Object?> okStart() =>
      <String, Object?>{'started': true};
  Map<String, Object?> failStart(String reason) =>
      <String, Object?>{'started': false, 'reason': reason};

  setUp(() async {
    await ArCoreChannel.instance.stopSession();
    startResult = okStart();
    retryResult = okStart();
    retryCalls = 0;

    mockMessenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      if (call.method == 'requestPermissions') return <int, int>{1: 1};
      if (call.method == 'checkPermissionStatus') return 1;
      return null;
    });

    mockMessenger.setMockMethodCallHandler(arChannel, (call) async {
      switch (call.method) {
        case 'startSession':
          return startResult;
        case 'retrySession':
          retryCalls++;
          return retryResult;
        case 'acquireCameraFrame':
          return <dynamic, dynamic>{
            'bytes': Uint8List(0),
            'width': 480,
            'height': 640,
            'rotationDegrees': 90,
          };
        default:
          return null;
      }
    });

    mockMessenger.setMockMethodCallHandler(platformViewsChannel, (call) async {
      if (call.method == 'create') return <dynamic, dynamic>{'id': 0};
      return null;
    });
  });

  tearDown(() async {
    mockMessenger.setMockMethodCallHandler(arChannel, null);
    mockMessenger.setMockMethodCallHandler(permissionsChannel, null);
    mockMessenger.setMockMethodCallHandler(platformViewsChannel, null);
    await ArCoreChannel.instance.stopSession();
  });

  /// Drive the permission + session-start chain to its terminal outcome.
  Future<void> settleStart(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Widget manualScreen() => const FootManualMeasureScreen(
        footCondition: 'bare',
        shoeCategory: 'women',
        smartAssistEnabled: false,
      );

  testWidgets('transient failure offers Try again, which retries the session',
      (tester) async {
    startResult = failStart('timeout');
    await tester.pumpWidget(MaterialApp(home: manualScreen()));
    await settleStart(tester);

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Use card scan instead'), findsNothing);
    expect(find.text('Go Back'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settleStart(tester);

    expect(retryCalls, 1);
    // Recovery: geometry arrived, the error state is gone.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Go Back'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported device offers card scan with the same prefs',
      (tester) async {
    startResult = failStart('unsupported_device');
    await tester.pumpWidget(MaterialApp(home: manualScreen()));
    await settleStart(tester);

    expect(find.text('Use card scan instead'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);

    await tester.tap(find.text('Use card scan instead'));
    await settleStart(tester);

    final capture =
        tester.widget<FootCaptureScreen>(find.byType(FootCaptureScreen));
    expect(capture.paperSize, 'card');
    expect(capture.footCondition, 'bare');
    expect(capture.shoeCategory, 'women');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Go Back pops back to the previous screen', (tester) async {
    startResult = failStart('timeout');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => manualScreen()),
            ),
            child: const Text('open-manual'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open-manual'));
    await settleStart(tester);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Go Back'));
    await tester.pump();
    await tester.pump();

    expect(find.text('open-manual'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
