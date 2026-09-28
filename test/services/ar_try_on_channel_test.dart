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
      // V4's `footLock` will arrive this way on a Dart build that predates it.
      final event = ArTryOnEvent.fromMap(<Object?, Object?>{
        'type': 'footLock',
        'data': <Object?, Object?>{'locked': true, 'quality': 0.8},
      });

      expect(event, isA<ArTryOnUnknownEvent>());
      expect((event as ArTryOnUnknownEvent).type, 'footLock');
      expect(event.data['locked'], isTrue);
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
}
