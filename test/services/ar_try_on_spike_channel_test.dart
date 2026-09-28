import 'package:app/services/ar_try_on_spike_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the V0 spike's platform channel.
///
/// The spike itself is throwaway, but this wrapper is deliberately shaped to be lifted into
/// the production `ArTryOnChannel` (`VIRTUAL_FITTING_ARCHITECTURE.md` §2.8), so the wire
/// format is worth pinning down now: every value here crosses the platform boundary where a
/// null, an int and a double are easy to confuse, and where a newer native build may send an
/// event this Dart build has never heard of.
void main() {
  const methodChannel = MethodChannel('com.solevision/ar_try_on_spike');
  const eventChannel = EventChannel('com.solevision/ar_try_on_spike/events');

  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
    await ArTryOnSpikeChannel.instance.detach();
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

    test('a map without "started" fails closed', () {
      final result = TryOnStartResult.fromNative(<Object?, Object?>{'reason': 'timeout'});
      expect(result.started, isFalse);
    });

    test('a non-bool "started" fails closed instead of throwing', () {
      for (final Object? value in <Object?>['true', 1, <Object?>[]]) {
        final result = TryOnStartResult.fromNative(<Object?, Object?>{'started': value});
        expect(result.started, isFalse, reason: 'started: $value');
      }
    });
  });

  group('TryOnSpikeEvent.fromMap', () {
    test('status events keep phase, reason and message', () {
      final event = TryOnSpikeEvent.fromMap(<Object?, Object?>{
        'type': 'status',
        'data': <Object?, Object?>{'phase': 'failed', 'reason': 'timeout', 'message': 'no session'},
      });
      expect(event, isA<TryOnStatusEvent>());
      final status = event as TryOnStatusEvent;
      expect(status.phase, 'failed');
      expect(status.reason, 'timeout');
      expect(status.message, 'no session');
    });

    test('model-loaded events keep the measured milliseconds', () {
      final event = TryOnSpikeEvent.fromMap(<Object?, Object?>{
        'type': 'modelLoaded',
        'data': <Object?, Object?>{'loadMs': 412, 'source': 'file:///models/a.glb'},
      });
      expect(event, isA<TryOnModelLoadedEvent>());
      final loaded = event as TryOnModelLoadedEvent;
      expect(loaded.loadMs, 412);
      expect(loaded.source, 'file:///models/a.glb');
    });

    test('perf events accept ints and doubles from the native side', () {
      final event = TryOnSpikeEvent.fromMap(<Object?, Object?>{
        'type': 'perf',
        'data': <Object?, Object?>{'avgFps': 30, 'frameMs': 33.4},
      });
      expect(event, isA<TryOnPerfEvent>());
      final perf = event as TryOnPerfEvent;
      expect(perf.avgFps, 30.0);
      expect(perf.frameMs, 33.4);
    });

    test('an unknown type is preserved instead of thrown away', () {
      final event = TryOnSpikeEvent.fromMap(<Object?, Object?>{
        'type': 'depthReady',
        'data': <Object?, Object?>{'supported': true},
      });
      expect(event, isA<TryOnUnknownEvent>());
      final unknown = event as TryOnUnknownEvent;
      expect(unknown.type, 'depthReady');
      expect(unknown.data['supported'], isTrue);
    });

    test('missing or malformed payloads degrade rather than crash', () {
      final noType = TryOnSpikeEvent.fromMap(<Object?, Object?>{});
      expect((noType as TryOnUnknownEvent).type, 'unknown');

      final noData = TryOnSpikeEvent.fromMap(<Object?, Object?>{'type': 'perf'});
      expect((noData as TryOnPerfEvent).avgFps, 0);

      final badLoad = TryOnSpikeEvent.fromMap(<Object?, Object?>{
        'type': 'modelLoaded',
        'data': <Object?, Object?>{'loadMs': 'soon'},
      });
      expect((badLoad as TryOnModelLoadedEvent).loadMs, -1);
    });
  });

  group('method channel contract', () {
    test('setModelScale sends the scale under the key native reads', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        seen = call;
        return null;
      });

      await ArTryOnSpikeChannel.instance.setModelScale(0.85);

      expect(seen!.method, 'setModelScale');
      expect(seen!.arguments, <String, Object?>{'scale': 0.85});
    });

    test('setModel sends the path under the key native reads', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        seen = call;
        return null;
      });

      await ArTryOnSpikeChannel.instance.setModel('file:///data/spike/shoe_1.glb');

      expect(seen!.method, 'setModel');
      expect(seen!.arguments, <String, Object?>{'path': 'file:///data/spike/shoe_1.glb'});
    });

    test('startSession parses a parked reply into a result', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'startSession');
        return <Object?, Object?>{
          'started': false,
          'reason': 'needs_install',
          'message': 'Google Play Services for AR is missing',
        };
      });

      final result = await ArTryOnSpikeChannel.instance.startSession();

      expect(result.started, isFalse);
      expect(result.reason, 'needs_install');
    });

    test('getStatus tolerates a null snapshot', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

      expect(await ArTryOnSpikeChannel.instance.getStatus(), isEmpty);
    });
  });

  group('event stream', () {
    test('native events reach listeners as parsed events', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {
          sink.success(<Object?, Object?>{
            'type': 'status',
            'data': <Object?, Object?>{'phase': 'placed'},
          });
        }),
      );

      final channel = ArTryOnSpikeChannel.instance;
      channel.attach();
      final event = await channel.events.first;

      expect(event, isA<TryOnStatusEvent>());
      expect((event as TryOnStatusEvent).phase, 'placed');
    });

    test('a platform stream error surfaces as a failed status event', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {
          sink.error(code: 'arcore_lost', message: 'ARCore lost');
        }),
      );

      final channel = ArTryOnSpikeChannel.instance;
      channel.attach();
      final event = await channel.events.first;

      expect(event, isA<TryOnStatusEvent>());
      final status = event as TryOnStatusEvent;
      expect(status.phase, 'failed');
      expect(status.reason, 'error');
      expect(status.message, contains('ARCore lost'));
    });

    test('attach is idempotent — two mounts must not double-subscribe', () async {
      var listens = 0;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {
          listens++;
          sink.success(<Object?, Object?>{'type': 'status', 'data': <Object?, Object?>{'phase': 'ready'}});
        }),
      );

      final channel = ArTryOnSpikeChannel.instance;
      channel.attach();
      channel.attach();
      await channel.events.first;

      expect(listens, 1);
    });
  });
}
