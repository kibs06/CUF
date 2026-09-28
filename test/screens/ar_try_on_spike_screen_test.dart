import 'dart:async';
import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/screens/customer/ar_try_on_spike_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the V0 spike screen (`docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`).
///
/// The interesting behaviour is an *ordering* one. The native AR view has to be
/// rendered before the session can start, and the session is what `startSession`
/// resolves on — so a screen that awaits `startSession` before showing the view
/// deadlocks itself and reports `timeout` after 15 s on every device. These tests
/// pin that order so the bug cannot come back.
///
/// The screen is behind the compile-time dev flag, so the flag-dependent tests
/// declare themselves skipped unless the flag is on. Run them with:
///
/// ```bash
/// flutter test --dart-define=AR_TRY_ON_SPIKE=true test/screens/ar_try_on_spike_screen_test.dart
/// ```
///
/// In a normal run (flag off) the same file asserts the defence-in-depth
/// behaviour instead: the screen must be inert in a build that did not ask for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const MethodChannel methodChannel =
      MethodChannel('com.solevision/ar_try_on_spike');
  const EventChannel eventChannel =
      EventChannel('com.solevision/ar_try_on_spike/events');
  // permission_handler's platform implementation talks over this channel; status
  // `1` is `PermissionStatus.granted`. `requestPermissions` answers with a map of
  // permission value → status (not a bare int), which is what this plugin version
  // decodes.
  const MethodChannel permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  const int granted = 1; // PermissionStatus.granted
  // Staged models go to app storage; in a test that is a temp directory. This is
  // the channel `path_provider` reaches for when no platform implementation is
  // registered (which is the case under `flutter test`).
  const MethodChannel pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');

  // `testWidgets`'s `skip` is a bool only, so the reason for the skip lives in the
  // descriptions above: the flag-dependent tests need --dart-define=AR_TRY_ON_SPIKE=true.
  final bool flagOn = AppConstants.arTryOnSpikeEnabled;

  late Directory tempDir;
  late List<String> calls;
  Completer<Object?>? startSessionReply;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ar_try_on_spike_test');
    calls = <String>[];
    startSessionReply = null;

    mockMessenger.setMockMethodCallHandler(pathProviderChannel, (call) async =>
        call.method == 'getApplicationSupportDirectory' ? tempDir.path : null);

    mockMessenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      if (call.method == 'requestPermissions') {
        // This plugin version sends the permission values as a bare List<int>
        // (`Permission.camera.value == 1`) and decodes `{value: status}` back.
        final Object? arguments = call.arguments;
        final List<int> requested = arguments is List
            ? arguments.whereType<int>().toList()
            : const <int>[1];
        return <int, int>{for (final int value in requested) value: granted};
      }
      if (call.method == 'checkPermissionStatus') return granted;
      if (call.method == 'shouldShowRequestPermissionRationale') return false;
      return null;
    });

    mockMessenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'startSession') {
        // Models the native side: it cannot answer until the AR view exists, so
        // the reply stays pending until the test releases it.
        startSessionReply = Completer<Object?>();
        return startSessionReply!.future;
      }
      return true;
    });

    mockMessenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );

    // Hybrid-composition plumbing: the test has no engine to create a real
    // platform view, so answer `create` the way the engine answers it for hybrid
    // composition (null = handled by the view hierarchy, not a texture).
    mockMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      calls.add('platform_views.${call.method}');
      return null;
    });
  });

  tearDown(() async {
    mockMessenger.setMockMethodCallHandler(permissionsChannel, null);
    mockMessenger.setMockMethodCallHandler(pathProviderChannel, null);
    mockMessenger.setMockMethodCallHandler(methodChannel, null);
    mockMessenger.setMockStreamHandler(eventChannel, null);
    mockMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    // A staging future that never completed would otherwise hold the directory
    // open on Windows; the assertion for that case is inside the test.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // ignored: the test already reported whatever went wrong
    }
  });

  Future<void> settlePreparation(WidgetTester tester) async {
    // Staging does real file I/O, which the fake-async test zone does not run by
    // itself, so let real async run between pumps. `pumpAndSettle` is not an
    // option: the spinner animates forever while the session reply is
    // deliberately left pending.
    for (int i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets(
    'renders the AR view before awaiting startSession — the deadlock guard',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ArTryOnSpikeScreen()));
      await settlePreparation(tester);

      // The native side has not answered yet…
      expect(startSessionReply, isNotNull);
      expect(startSessionReply!.isCompleted, isFalse);

      // …and the view is already on screen. This is the assertion that fails if
      // the screen regresses to awaiting `startSession` first.
      expect(find.byType(PlatformViewLink), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('phase:'), findsOneWidget);

      // The model is handed over before the session is asked to start, so the
      // plugin can park it and apply it to the view it is about to create.
      expect(calls, contains('setModel'));
      expect(calls, contains('setModelScale'));
      expect(calls, contains('startSession'));
      expect(
          calls.indexOf('setModel'), lessThan(calls.indexOf('startSession')));

      // A granted session then flips the phase to `ready` without a rebuild storm.
      startSessionReply!.complete(<Object?, Object?>{
        'started': true,
        'reason': null,
        'message': null,
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    skip: !flagOn,
  );

  testWidgets(
    'reload stages a fresh file so a cold load can be measured again',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ArTryOnSpikeScreen()));
      await settlePreparation(tester);

      final stageDir = Directory('${tempDir.path}/spike');
      expect(stageDir.listSync().whereType<File>().length, 1);

      await tester.tap(find.text('Reload model'));
      await settlePreparation(tester);

      // Exactly one file: the later staging replaces the earlier one instead of
      // letting staged models pile up in app storage (they are much larger in V2).
      expect(stageDir.listSync().whereType<File>().length, 1);
      expect(calls.where((String m) => m == 'setModel').length, 2);
    },
    skip: !flagOn,
  );

  testWidgets(
    'is inert in a normal build and says how to enable it',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ArTryOnSpikeScreen()));
      await tester.pump();

      expect(find.textContaining('development build only'), findsOneWidget);
      expect(find.byType(PlatformViewLink), findsNothing);
      // Nothing was staged, and no AR session was asked for.
      expect(calls, isEmpty);
      expect(Directory('${tempDir.path}/spike').existsSync(), isFalse);
    },
    skip: flagOn,
  );
}
