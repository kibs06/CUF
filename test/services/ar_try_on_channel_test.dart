import 'package:app/services/ar_try_on_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the production try-on channel
/// (`VIRTUAL_FITTING_ARCHITECTURE.md` §2.8).
///
/// The native half is not written yet, which is exactly why these tests matter:
/// the wire format is the one thing both sides must agree on *before* either can
/// be debugged on a device, and every value here crosses a platform boundary
/// where a null, an int and a double are easy to confuse.
///
/// The parsing half is tested against `fromMap`/`fromNative` directly, and the
/// sending half against a mocked `MethodChannel`, so no native code is involved
/// either way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(kArTryOnMethodChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Every method call the channel made, in order.
  late List<MethodCall> calls;

  late ArTryOnChannel channel;

  /// Answers every method call with [reply], recording what was asked.
  void respond(Object? reply) {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return reply;
    });
  }

  String hex64(String character) => List.filled(64, character).join();

  setUp(() {
    calls = <MethodCall>[];
    channel = ArTryOnChannel();
  });

  tearDown(() async {
    await channel.detach();
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  group('TryOnStartResult.fromNative', () {
    test('reads the native reply map', () {
      final result = TryOnStartResult.fromNative(<Object?, Object?>{
        'started': true,
        'reason': null,
        'message': null,
      });

      expect(result.started, isTrue);
      expect(result.reason, isNull);
      expect(result.message, isNull);
    });

    test('carries the failure vocabulary the shipped scan already uses', () {
      final result = TryOnStartResult.fromNative(<Object?, Object?>{
        'started': false,
        'reason': 'unsupported_device',
        'message': 'ARCore is not available on this device',
      });

      expect(result.started, isFalse);
      expect(result.reason, 'unsupported_device');
      expect(result.message, contains('ARCore'));
    });

    test('treats a bare bool as the whole answer', () {
      expect(TryOnStartResult.fromNative(true).started, isTrue);
      expect(TryOnStartResult.fromNative(false).started, isFalse);
    });

    test('never crashes on a malformed or missing reply', () {
      for (final Object? native in <Object?>[null, 'yes', <Object?>[], 42]) {
        final result = TryOnStartResult.fromNative(native);
        expect(result.started, isFalse, reason: 'native: $native');
        expect(result.reason, 'error', reason: 'native: $native');
        expect(result.message, isNotNull, reason: 'native: $native');
      }
    });

    test('a string "true" fails closed rather than throwing', () {
      // The failure mode this guards: a native build that sends the string.
      // `as bool?` would throw across the channel boundary; a false start lands
      // the customer on the simulated screen, which is the safe direction.
      final result = TryOnStartResult.fromNative(<Object?, Object?>{
        'started': 'true',
      });

      expect(result.started, isFalse);
    });
  });

  group('Dart → native method calls', () {
    test('startSession parses the native reply', () async {
      respond(<Object?, Object?>{
        'started': false,
        'reason': 'needs_install',
        'message': 'Google Play Services for AR is missing',
      });

      final result = await channel.startSession();

      expect(calls.single.method, 'startSession');
      expect(result.started, isFalse);
      expect(result.reason, 'needs_install');
    });

    test('setModel sends the whole spec under the keys native reads', () async {
      respond(true);

      await channel.setModel(TryOnModelSpec(
        path: '/data/shoe_models/7_v2_abc.glb',
        modelId: 7,
        sha256: hex64('a'),
        authoredLengthMm: 278,
        alignmentJson: {'heelOffsetMm': 3.0},
      ));

      expect(calls.single.method, 'setModel');
      expect(calls.single.arguments, <String, Object?>{
        'path': '/data/shoe_models/7_v2_abc.glb',
        'modelId': 7,
        'sha256': hex64('a'),
        'authoredLengthMm': 278,
        'alignmentJson': {'heelOffsetMm': 3.0},
      });
    });

    test('setModel sends nulls rather than omitting the keys', () async {
      // Native reads one shape, always: a missing key and a null key are
      // different bugs on the other side of the channel.
      respond(true);

      await channel.setModel(TryOnModelSpec(
        path: '/tmp/a.glb',
        modelId: 1,
        sha256: hex64('b'),
      ));

      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments.containsKey('authoredLengthMm'), isTrue);
      expect(arguments.containsKey('alignmentJson'), isTrue);
      expect(arguments['authoredLengthMm'], isNull);
      expect(arguments['alignmentJson'], isNull);
    });

    test('setSize sends the size, the reference size and the last length',
        () async {
      respond(true);

      await channel.setSize(sizeEu: 'EU 43', refSizeEu: 42, lastLengthMm: 278);

      expect(calls.single.method, 'setSize');
      expect(calls.single.arguments, <String, Object?>{
        'sizeEu': 'EU 43',
        'refSizeEu': 42,
        'lastLengthMm': 278,
      });
    });

    test('setSize can say "no reference" for a product without fit specs',
        () async {
      respond(true);

      await channel.setSize(sizeEu: 'EU 42');

      expect(calls.single.arguments, <String, Object?>{
        'sizeEu': 'EU 42',
        'refSizeEu': null,
        'lastLengthMm': null,
      });
    });

    test('setColor sends the overrides as one map', () async {
      respond(true);

      await channel.setColor({
        'upper': {'baseColorHex': '#1B1B1B'},
      });

      expect(calls.single.method, 'setColor');
      expect(calls.single.arguments, <String, Object?>{
        'materialOverrides': {
          'upper': {'baseColorHex': '#1B1B1B'},
        },
      });
    });

    test('placeShoe sends the screen point', () async {
      respond(true);

      await channel.placeShoe(x: 120.5, y: 480.25);

      expect(calls.single.method, 'placeShoe');
      expect(calls.single.arguments, <String, Object?>{'x': 120.5, 'y': 480.25});
    });

    test('setTryOnMode uses the wire words §2.8 fixes', () async {
      respond(true);

      await channel.setTryOnMode(TryOnInteractionMode.floor);
      expect(calls.single.method, 'setTryOnMode');
      expect(calls.single.arguments, <String, Object?>{'mode': 'floor'});

      await channel.setTryOnMode(TryOnInteractionMode.foot);
      expect(calls.last.arguments, <String, Object?>{'mode': 'foot'});
    });

    test('setDiagnostics asks for the readout as one named bit', () async {
      respond(true);

      await channel.setDiagnostics(true);
      expect(calls.single.method, 'setDiagnostics');
      expect(calls.single.arguments, <String, Object?>{'enabled': true});

      await channel.setDiagnostics(false);
      expect(calls.last.arguments, <String, Object?>{'enabled': false});
    });

    test('stopSession is callable but is not part of teardown', () async {
      respond(true);

      await channel.stopSession();

      expect(calls.single.method, 'stopSession');
    });

    test('captureScreenshot returns the PNG bytes', () async {
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      respond(bytes);

      expect(await channel.captureScreenshot(), bytes);
    });

    test('captureScreenshot is null, not an exception, with no native PNG',
        () async {
      respond(null);

      expect(await channel.captureScreenshot(), isNull);
    });
  });

  group('native → Dart events', () {
    test('a model load is parsed with its timing', () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'modelLoaded',
        'data': <Object?, Object?>{'loadMs': 812, 'triangles': 41500},
      });

      expect(event, isA<TryOnModelLoadedEvent>());
      final loaded = event as TryOnModelLoadedEvent;
      expect(loaded.loadMs, 812);
      expect(loaded.triangles, 41500);
    });

    test('a perf sample arrives as a typed rate', () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'perf',
        'data': <Object?, Object?>{'avgFps': 57.5, 'frameMs': 17.4},
      });

      expect(event, isA<TryOnPerfEvent>());
      expect(
        (event as TryOnPerfEvent).perf,
        const TryOnPerf(avgFps: 57.5, frameMs: 17.4),
      );
    });

    test('an error carries native vocabulary', () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'error',
        'data': <Object?, Object?>{
          'reason': 'renderer_init_failed',
          'message': 'no GL context',
        },
      });

      expect(event, isA<TryOnErrorEvent>());
      final error = event as TryOnErrorEvent;
      expect(error.reason, 'renderer_init_failed');
      expect(error.message, 'no GL context');
    });

    test('a screenshot event carries bytes, and an empty list without them', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final withBytes = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'screenshot',
        'data': <Object?, Object?>{'bytes': bytes},
      });
      expect((withBytes as TryOnScreenshotEvent).bytes, bytes);

      final without = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'screenshot',
        'data': <Object?, Object?>{},
      });
      expect((without as TryOnScreenshotEvent).bytes, isEmpty);
    });

    test('an event type this build has never heard of is not a crash', () {
      // A V5/V6 event reaches a Dart build that predates it as an unknown
      // rather than as an exception — the property that let `footLock` be added
      // without breaking anything (V4), and the one the next addition needs.
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'depthReady',
        'data': <Object?, Object?>{'available': true},
      });

      expect(event, isA<ArTryOnUnknownEvent>());
      expect((event as ArTryOnUnknownEvent).type, 'depthReady');
      expect(event.data['available'], isTrue);
    });

    test('missing, malformed and non-numeric payloads never throw', () {
      final noType = ArTryOnEvent.fromMap(<Object?, Object?>{});
      final noData = ArTryOnEvent.fromMap(<Object?, Object?>{'type': 'modelLoaded'});
      final stringy = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'modelLoaded',
        'data': <Object?, Object?>{'loadMs': 'fast', 'triangles': null},
      });
      final notAMap = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'perf',
        'data': 'not-a-map',
      });

      expect(noType, isA<ArTryOnUnknownEvent>());
      expect(noData, isA<TryOnModelLoadedEvent>());
      expect((noData as TryOnModelLoadedEvent).loadMs, -1);
      expect(noData.triangles, -1);

      expect((stringy as TryOnModelLoadedEvent).loadMs, -1,
          reason: 'an unreadable number is "unknown", never an exception');
      expect(stringy.triangles, -1);

      final perf = notAMap as TryOnPerfEvent;
      expect(perf.perf.avgFps, 0);
      expect(perf.perf.frameMs, 0);
    });
  });

  group('attach and detach', () {
    test('attach is idempotent and detach is safe to repeat', () async {
      channel.attach();
      channel.attach();
      await channel.detach();
      await channel.detach();

      expect(channel.events, isA<Stream<ArTryOnEvent>>());
    });
  });

  group('the V4 foot-tracking contract', () {
    test('a footLock names the state, the post-smoothing quality and the side',
        () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'footLock',
        'data': <Object?, Object?>{
          'locked': true,
          'quality': 0.83,
          'side': 'right',
        },
      });

      expect(event, isA<TryOnFootLockEvent>());
      final lock = event as TryOnFootLockEvent;
      expect(lock.locked, isTrue);
      expect(lock.quality, 0.83);
      expect(lock.side, 'right');
    });

    test('a lost lock and a malformed payload both parse as unlocked', () {
      final lost = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'footLock',
        'data': <Object?, Object?>{'locked': false, 'quality': 0.4},
      }) as TryOnFootLockEvent;

      expect(lost.locked, isFalse);
      expect(lost.quality, 0.4);
      expect(lost.side, isNull);

      final malformed = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'footLock',
        'data': <Object?, Object?>{'locked': 'yes', 'quality': 'high'},
      }) as TryOnFootLockEvent;

      expect(malformed.locked, isFalse,
          reason: 'only a real bool means locked');
      expect(malformed.quality, 0);
    });

    test('a footMeasure carries the live length and quality', () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'footMeasure',
        'data': <Object?, Object?>{'lengthMm': 264.7, 'quality': 0.82},
      });

      expect(event, isA<TryOnFootMeasureEvent>());
      final measure = event as TryOnFootMeasureEvent;
      expect(measure.lengthMm, 264.7);
      expect(measure.quality, 0.82);
    });

    test('a malformed footMeasure degrades to zeros the controller refuses',
        () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'footMeasure',
        'data': <Object?, Object?>{'lengthMm': 'long', 'quality': null},
      }) as TryOnFootMeasureEvent;

      expect(event.lengthMm, 0,
          reason: 'a missing number is 0 here; the controller is what refuses '
              'it, so a malformed payload can never reach the fit engine');
      expect(event.quality, 0);
    });

    test('a status event carries the heartbeat line verbatim (V4.9)', () {
      const line = 'loop=on iter=61 present=58 foot=locked quality=0.82 '
          'len=264mm scale=1.024 mask=ready thermal=none';
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'status',
        'data': <Object?, Object?>{'line': line, 'loopRunning': true},
      });

      expect(event, isA<TryOnStatusEvent>());
      expect((event as TryOnStatusEvent).line, line);
    });

    test('a status with no line degrades to empty, which the controller '
        'ignores rather than drawing', () {
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'status',
        'data': <Object?, Object?>{'loopRunning': false},
      }) as TryOnStatusEvent;

      expect(event.line, isEmpty);
    });

    test('a pose frame serializes to the §2.8 payload', () {
      const frame = FootPoseFrame(
        heelUv: Offset(0.25, 0.75),
        toeUv: Offset(0.30, 0.20),
        widthUv: <Offset>[Offset(0.22, 0.5), Offset(0.34, 0.5)],
        confidence: 0.81,
        footSide: 'left',
      );

      final map = frame.toMap();

      expect(map['heelUv'], <String, double>{'x': 0.25, 'y': 0.75});
      expect(map['toeUv'], <String, double>{'x': 0.30, 'y': 0.20});
      expect(map['widthUv'], <Map<String, double>>[
        <String, double>{'x': 0.22, 'y': 0.5},
        <String, double>{'x': 0.34, 'y': 0.5},
      ]);
      expect(map['confidence'], 0.81);
      expect(map['footSide'], 'left');
    });

    test('an empty width pair is a legal payload, not a missing key', () {
      const frame = FootPoseFrame(
        heelUv: Offset(0.1, 0.9),
        toeUv: Offset(0.2, 0.3),
        confidence: 0.7,
      );

      final map = frame.toMap();

      expect(map.containsKey('widthUv'), isTrue);
      expect(map['widthUv'], isEmpty);
      expect(map['footSide'], isNull);
    });

    test('setFootPose sends the frame as its own argument map', () async {
      respond(true);
      const frame = FootPoseFrame(
        heelUv: Offset(0.4, 0.8),
        toeUv: Offset(0.4, 0.2),
        confidence: 0.9,
        footSide: 'right',
      );

      await channel.setFootPose(frame);

      expect(calls.single.method, 'setFootPose');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect((args['heelUv'] as Map<Object?, Object?>)['y'], 0.8);
      expect(args['confidence'], 0.9);
      expect(args['footSide'], 'right');
    });

    test('setFootMask sends bytes and a confidence, nothing else', () async {
      respond(true);
      final mask = Uint8List.fromList(List<int>.filled(32 * 32, 255));

      await channel.setFootMask(bytes32x32: mask, confidence: 0.77);

      expect(calls.single.method, 'setFootMask');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['bytes'], mask);
      expect(args['confidence'], 0.77);
      expect(args.keys.toSet(), <String>{'bytes', 'confidence'});
    });

    test('acquireCameraFrame parses the scan frame shape', () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      respond(<Object?, Object?>{
        'bytes': bytes,
        'width': 640,
        'height': 480,
        'rotationDegrees': 90,
      });

      final frame = await channel.acquireCameraFrame();

      expect(frame, isNotNull);
      expect(frame!.nv21Bytes, bytes);
      expect(frame.width, 640);
      expect(frame.height, 480);
      expect(frame.rotationDegrees, 90);
    });

    test('acquireCameraFrame answers null when there is no frame yet',
        () async {
      respond(null);

      expect(await channel.acquireCameraFrame(), isNull);
    });
  });
}
