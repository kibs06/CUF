import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/customer/foot_size_v2/foot_scan_session_screen_v2.dart';

/// Regression guard for the "camera never opens" cold-start deadlock.
///
/// The native ARCore session is created BY the `ar_foot_scan` platform view
/// (ArFootSizingView.getView → createSession), and the `startSession` method
/// reply stays parked native-side until that view reports an outcome. A screen
/// that waits for a started phase before mounting the view deadlocks the two:
/// no view → no reply → the native 15 s timeout fires and the scan opens
/// straight onto "AR took too long to start" with no camera. These tests pin
/// the ordering the fix relies on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const MethodChannel methodChannel =
      MethodChannel('com.solevision/ar_foot_sizing');
  const EventChannel eventChannel =
      EventChannel('com.solevision/ar_foot_sizing/events');

  late List<String> calls;
  Completer<Object?>? startSessionReply;

  /// Staged terminal failure the native view already reported — answered to
  /// `startSession` immediately, like the plugin does.
  Object? startFailure;

  /// Answer to `retrySession` (the real restart call the sheet's Retry uses),
  /// plus how many times it was invoked.
  Object? retryAnswer;
  int retryCalls = 0;

  /// Deliver a native ARCore event exactly the way the engine does — a message
  /// from the platform to this channel's inbound handler.
  void emitArEvent(Map<Object?, Object?> event) {
    mockMessenger.handlePlatformMessage(
      eventChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      null,
    );
  }

  setUp(() {
    calls = <String>[];
    startSessionReply = null;
    startFailure = null;
    retryAnswer = null;
    retryCalls = 0;

    mockMessenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'startSession') {
        // Staged failure → the view already reported its terminal outcome,
        // so the reply comes straight back. Otherwise this models the native
        // side waiting for the AR view, parked until the test releases it.
        if (startFailure != null) return startFailure;
        startSessionReply = Completer<Object?>();
        return startSessionReply!.future;
      }
      if (call.method == 'retrySession') {
        retryCalls++;
        return retryAnswer;
      }
      if (call.method == 'hitTestBatch') {
        // Guide-box probes all "hit the floor" so area tracking can lock.
        final List<Object?> points =
            ((call.arguments as Map<Object?, Object?>?)?['points']
                    as List<Object?>?) ??
                const <Object?>[];
        return List<Object?>.filled(
          points.length,
          <Object?, Object?>{
            'x': 0.0,
            'y': 0.0,
            'z': 0.0,
            'distance': 0.3,
          },
        );
      }
      if (call.method == 'getTrackingState') return 'tracking';
      return null;
    });

    // A no-op stream handler keeps the EventChannel's `listen`/`cancel`
    // activation traffic answered (an unanswered `listen` reports an
    // activation error). Events themselves are injected via [emitArEvent].
    mockMessenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );

    // Hybrid-composition plumbing: there is no engine under `flutter test` to
    // create a real platform view, so every platform_views call is answered
    // the way the engine answers hybrid composition (null — the view is
    // composed by the view hierarchy rather than drawn through a texture).
    mockMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      calls.add('platform_views.${call.method}');
      return null;
    });
  });

  tearDown(() {
    mockMessenger.setMockMethodCallHandler(methodChannel, null);
    mockMessenger.setMockStreamHandler(eventChannel, null);
    mockMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FootScanSessionScreenV2(footCondition: 'bare', shoeCategory: 'men'),
    ));
    // A couple of frames: the first builds, the second delivers the platform
    // view creation and the parked startSession call.
    await tester.pump();
    await tester.pump();
  }

  void completeStart() {
    startSessionReply!.complete(<Object?, Object?>{
      'started': true,
      'reason': null,
      'message': null,
    });
  }

  testWidgets(
      'mounts the AR view while startSession is still parked — the deadlock '
      'guard', (tester) async {
    await pumpScreen(tester);

    // The native side has not answered yet…
    expect(calls, contains('startSession'));
    expect(startSessionReply, isNotNull);
    expect(startSessionReply!.isCompleted, isFalse);

    // …and the platform view is already in the tree. This is the assertion
    // that fails when the screen regresses to gating the view on a started
    // phase (which is what left the camera closed on a cold first scan).
    expect(find.byType(PlatformViewLink), findsOneWidget);
    expect(find.text('Looking for the floor…'), findsOneWidget);
    expect(calls, contains('platform_views.create'));

    // Releasing the session — what the view's createSession does natively —
    // moves the screen on without an exception, view still mounted.
    completeStart();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(PlatformViewLink), findsOneWidget);
    expect(find.text('Move your phone slowly over the floor'), findsOneWidget);
  });

  testWidgets(
      'tracking + floor lock turn the warmed-up session into a live Measure '
      'button', (tester) async {
    await pumpScreen(tester);
    completeStart();
    await tester.pump();

    // ARCore's tracking and plane events, then the guide-box probes hit the
    // floor (production polls area tracking every 500 ms).
    emitArEvent(<Object?, Object?>{
      'type': 'tracking',
      'data': <Object?, Object?>{'state': 'tracking'},
    });
    emitArEvent(<Object?, Object?>{
      'type': 'plane',
      'data': <Object?, Object?>{},
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('Measure left foot · top'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ═══════════════════════════════════════════════════════════════
  // START-FAILURE SHEET
  // ═══════════════════════════════════════════════════════════════

  testWidgets(
      'needs_install explains what to install and still offers a retry',
      (tester) async {
    startFailure = <Object?, Object?>{
      'started': false,
      'reason': 'needs_install',
      'message': 'ARCore is being installed from Google Play.',
    };
    await pumpScreen(tester);

    expect(find.text('AR support needed'), findsOneWidget);
    expect(find.text('Get AR support'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported devices are offered Close, not Retry — retrying a '
      'device limitation can never work', (tester) async {
    startFailure = <Object?, Object?>{
      'started': false,
      'reason': 'unsupported_device',
      'message': 'ARCore is not supported on this device',
    };
    await pumpScreen(tester);

    expect(find.text('AR not available'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Get AR support'), findsNothing);
  });

  testWidgets(
      'Retry re-runs the native session start and recovers after the ARCore '
      'install', (tester) async {
    startFailure = <Object?, Object?>{
      'started': false,
      'reason': 'needs_install',
      'message': 'ARCore is being installed from Google Play.',
    };
    await pumpScreen(tester);
    expect(calls, contains('startSession'));

    // The customer installed ARCore from Play and tapped Retry.
    retryAnswer = <Object?, Object?>{'started': true};
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(retryCalls, 1,
        reason: 'Retry must ask native for a FRESH session — startSession '
            'would replay the cached failure');
    expect(find.text('AR support needed'), findsNothing);
    expect(find.text('Move your phone slowly over the floor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a Play trip that did not install ARCore escalates to the device '
      'limitation instead of looping', (tester) async {
    startFailure = <Object?, Object?>{
      'started': false,
      'reason': 'needs_install',
      'message': 'ARCore is being installed from Google Play.',
    };
    await pumpScreen(tester);

    await tester.tap(find.text('Get AR support'));
    await tester.pump();

    // Back from Play, ARCore is still missing: the retry reports the same
    // reason, so the sheet names the real cause instead of promising more.
    retryAnswer = <Object?, Object?>{
      'started': false,
      'reason': 'needs_install',
      'message': 'ARCore is being installed from Google Play.',
    };
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text("AR scanning isn't available on this phone"),
        findsOneWidget);
    expect(find.text('Get AR support'), findsNothing,
        reason: 'Play already said it has nothing for this device');
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
