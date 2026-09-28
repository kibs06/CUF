import 'dart:async';
import 'dart:io';

import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:app/providers/try_on/try_on_phase.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The V3 try-on session controller, driven without a device, a native view or
/// a network — which is the whole point of building it first: every decision
/// between "the customer taps Try on" and "the camera is live" is testable on a
/// desk, and the only parts left for a phone are the renderer and the numbers.
///
/// Three properties are non-negotiable here, and each has its own group:
///
///   1. **The switch gates side effects, not rendering** (V0 finding F19): with
///      it off there is no model read, no download and *zero* channel traffic.
///   2. **AR is never started before the view exists** (F17): a `false`
///      `arViewReady` is refused, because the alternative is the plugin's 15 s
///      timeout on every device.
///   3. **Every failure ends on the simulated screen with a reason** (D8), and
///      the reason is logged even though the customer sees nothing.
void main() {
  late Directory tempRoot;
  late Directory cacheDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('try_on_session_test');
    cacheDir = Directory('${tempRoot.path}${Platform.pathSeparator}cache');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  Uint8List bytesOf(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => (i * 7) % 256));

  String shaOf(List<int> bytes) => sha256.convert(bytes).toString();

  Map<String, dynamic> rowFor(Uint8List bytes) => <String, dynamic>{
        'id': 7,
        'variant_id': null,
        'storage_path': 'store-1/product-1/model.glb',
        'sha256': shaOf(bytes),
        'version': 2,
        'authored_length_mm': 278,
        'shoe_side': 'right',
      };

  /// A source that can serve one good model, or be told to fail on either side.
  _FakeSource sourceWith(List<Map<String, dynamic>> rows) =>
      _FakeSource()..rows = rows;

  TryOnSessionController controllerFor(
    _FakeSource source,
    _FakeChannel channel, {
    bool enabled = true,
    String productId = 'product-1',
    String? variantId,
    Future<Directory> Function()? cache,
  }) =>
      TryOnSessionController(
        productId: productId,
        variantId: variantId,
        enabled: enabled,
        channel: channel,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: cache ?? () async => cacheDir,
        ),
      );

  /// Lets the controller's broadcast stream deliver what it has announced.
  ///
  /// Its events reach a listener in a microtask, so asserting on them straight
  /// after an `await` races the delivery. One event-loop turn is enough.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  /// Collects everything the controller announces, in order.
  List<TryOnSessionEvent> recordEvents(TryOnSessionController controller) {
    final events = <TryOnSessionEvent>[];
    controller.events.listen(events.add);
    return events;
  }

  /// Collects every phase the controller passes through, in order.
  List<TryOnPhase> recordPhases(TryOnSessionController controller) {
    final phases = <TryOnPhase>[controller.phase];
    controller.addListener(() {
      if (phases.last != controller.phase) phases.add(controller.phase);
    });
    return phases;
  }

  group('the switch gates side effects, not just rendering', () {
    test('off means no read, no download and no channel traffic', () async {
      final bytes = bytesOf(128);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel, enabled: false);
      final events = recordEvents(controller);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);
      await flush();

      expect(controller.mode, TryOnMode.simulated);
      expect(controller.degradeReason, TryOnDegradeReason.featureOff);
      expect(source.rowsCalls, 0,
          reason: 'a disabled session must not touch the model table');
      expect(channel.calls, isEmpty,
          reason: 'not even startSession — a build that did not ask for try-on '
              'does nothing at all (F19)');
      expect(events.single, isA<TryOnDegradedEvent>());
    });
  });

  group('staging the model', () {
    test('a product with no model is idle, not an error', () async {
      final source = sourceWith([]);
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);
      final events = recordEvents(controller);

      await controller.prepareModel();
      await flush();

      expect(controller.phase, TryOnPhase.idle);
      expect(controller.mode, TryOnMode.simulated);
      expect(controller.degradeReason, TryOnDegradeReason.modelMissing);
      expect(controller.modelPath, isNull);
      expect(channel.calls, isEmpty);
      expect(
        (events.single as TryOnDegradedEvent).reason,
        TryOnDegradeReason.modelMissing,
      );
    });

    test('a model that cannot be resolved degrades and keeps the cause',
        () async {
      final source = sourceWith([])
        ..rowsError = Exception('relation "product_models" does not exist');
      final controller = controllerFor(source, _FakeChannel());

      await controller.prepareModel();

      expect(controller.phase, TryOnPhase.error);
      expect(controller.degradeReason, TryOnDegradeReason.modelUnavailable);
      expect(controller.failureReason, 'resolve_failed');
      expect(controller.failureMessage, contains('product_models'));
    });

    test('a model that cannot be made local degrades, and is not rendered',
        () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..downloadError = Exception('503 from storage');
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);

      await controller.prepareModel();

      expect(controller.phase, TryOnPhase.error);
      expect(controller.degradeReason, TryOnDegradeReason.modelUnavailable);
      expect(controller.modelPath, isNull);
      expect(channel.calls, isEmpty,
          reason: 'nothing unverified is ever handed to the renderer');
    });

    test('an unwritable cache directory degrades instead of throwing',
        () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final controller = controllerFor(
        source,
        _FakeChannel(),
        cache: () async => throw const FileSystemException('read-only'),
      );

      await controller.prepareModel();

      expect(controller.phase, TryOnPhase.error);
      expect(controller.degradeReason, TryOnDegradeReason.modelUnavailable);
    });

    test('the happy path stages the model and hands it over', () async {
      final bytes = bytesOf(128);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);
      final phases = recordPhases(controller);
      final events = recordEvents(controller);

      await controller.prepareModel();
      await flush();

      expect(phases, [TryOnPhase.idle, TryOnPhase.loadingModel,
          TryOnPhase.modelReady]);
      expect(controller.phase, TryOnPhase.modelReady);
      expect(controller.needsArStart, isTrue);
      expect(controller.modelPath, isNotNull);
      expect(File(controller.modelPath!).readAsBytesSync(), bytes);

      // The handover happens here, not after AR starts: if the view is not up
      // yet the native side parks it (F18), and deferring it is the bug the V0
      // plugin had.
      expect(channel.calls.single, 'setModel');
      final handed = channel.handedModel!;
      expect(handed.path, controller.modelPath);
      expect(handed.modelId, 7);
      expect(handed.sha256, shaOf(bytes));
      expect(handed.authoredLengthMm, 278);

      final ready = events.single as TryOnModelReadyEvent;
      expect(ready.path, controller.modelPath);
      expect(ready.fromCache, isFalse);
      expect(ready.stageMs, greaterThanOrEqualTo(0));

      // Staged, but AR has not run: the surface is still the fallback.
      expect(controller.mode, TryOnMode.simulated);
    });

    test('a second call is a no-op, not a second read', () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final controller = controllerFor(source, _FakeChannel());

      await controller.prepareModel();
      await controller.prepareModel();

      expect(source.rowsCalls, 1);
    });

    test('a variant id picks the variant row over the product default',
        () async {
      final defaultBytes = bytesOf(64);
      final variantBytes = bytesOf(96);
      final source = _FakeSource()
        ..rows = [
          <String, dynamic>{
            'id': 7,
            'variant_id': null,
            'storage_path': 'store-1/product-1/default.glb',
            'sha256': shaOf(defaultBytes),
            'version': 1,
            'shoe_side': 'right',
          },
          <String, dynamic>{
            'id': 9,
            'variant_id': 'variant-black-42',
            'storage_path': 'store-1/product-1/black-42.glb',
            'sha256': shaOf(variantBytes),
            'version': 1,
            'shoe_side': 'right',
          },
        ]
        ..files = {
          'store-1/product-1/default.glb': defaultBytes,
          'store-1/product-1/black-42.glb': variantBytes,
        };

      final withVariant = controllerFor(source, _FakeChannel(),
          variantId: 'variant-black-42');
      await withVariant.prepareModel();

      expect(withVariant.spec!.variantId, 'variant-black-42');
      expect(File(withVariant.modelPath!).readAsBytesSync(), variantBytes);

      // No selection means the product-level default, not the last colour's
      // asset (§2.7.2's rule 2).
      final withoutVariant = controllerFor(source, _FakeChannel());
      await withoutVariant.prepareModel();

      expect(withoutVariant.spec!.variantId, isNull);
      expect(File(withoutVariant.modelPath!).readAsBytesSync(), defaultBytes);
    });
  });

  group('starting AR is refused until the view exists (F17)', () {
    test('arViewReady false never calls startSession', () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);
      final events = recordEvents(controller);

      await controller.prepareModel();
      await controller.startAr(arViewReady: false);
      await flush();

      expect(channel.calls, ['setModel'],
          reason: 'the model handover is legal before the view exists; '
              'starting the session is not');
      expect(controller.mode, TryOnMode.simulated);
      expect(controller.degradeReason, TryOnDegradeReason.arViewNotReady);
      expect(
        (events.last as TryOnDegradedEvent).reason,
        TryOnDegradeReason.arViewNotReady,
      );
    });

    test('starting before staging does nothing at all', () async {
      final channel = _FakeChannel();
      final controller = controllerFor(sourceWith([]), channel);

      await controller.startAr(arViewReady: true);

      expect(controller.phase, TryOnPhase.idle);
      expect(channel.calls, isEmpty);
    });

    test('a failed start is not retried into a second session', () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel()
        ..nextStart = const TryOnStartResult(started: false, reason: 'timeout');
      final controller = controllerFor(source, channel);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);
      await controller.startAr(arViewReady: true);

      expect(channel.calls.where((c) => c == 'startSession').length, 1);
    });
  });

  group('the AR session decides the mode', () {
    test('a started session goes searching and renders for real', () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);
      final phases = recordPhases(controller);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);

      expect(phases, [
        TryOnPhase.idle,
        TryOnPhase.loadingModel,
        TryOnPhase.modelReady,
        TryOnPhase.arStarting,
        TryOnPhase.searching,
      ]);
      expect(controller.mode, TryOnMode.real);
      expect(controller.degradeReason, TryOnDegradeReason.none);
      expect(controller.failureReason, isNull);
    });

    test('every way ARCore can refuse lands on the stated fallback', () async {
      final cases = <String?, TryOnDegradeReason>{
        'unsupported_device': TryOnDegradeReason.arUnsupported,
        'unsupported': TryOnDegradeReason.arUnsupported,
        'needs_install': TryOnDegradeReason.arNeedsInstall,
        'user_opted_out': TryOnDegradeReason.arOptedOut,
        'timeout': TryOnDegradeReason.arFailed,
        'error': TryOnDegradeReason.arFailed,
        null: TryOnDegradeReason.arFailed,
      };

      for (final entry in cases.entries) {
        final bytes = bytesOf(64);
        final source = sourceWith([rowFor(bytes)])
          ..files = {'store-1/product-1/model.glb': bytes};
        final channel = _FakeChannel()
          ..nextStart = TryOnStartResult(
            started: false,
            reason: entry.key,
            message: 'refused',
          );
        final controller = controllerFor(source, channel);

        await controller.prepareModel();
        await controller.startAr(arViewReady: true);

        expect(controller.phase, TryOnPhase.arFailed, reason: '${entry.key}');
        expect(controller.mode, TryOnMode.simulated, reason: '${entry.key}');
        expect(controller.degradeReason, entry.value, reason: '${entry.key}');
        expect(controller.failureMessage, 'refused', reason: '${entry.key}');
      }
    });

    test('a start that throws across the channel is a fallback', () async {
      // This is today's real answer on every build: there is no native plugin,
      // so `startSession` throws MissingPluginException. It must read as "this
      // device cannot do it", not as a crash.
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel()
        ..startError = MissingPluginException(
            'No implementation found for method startSession');
      final controller = controllerFor(source, channel);
      final events = recordEvents(controller);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);
      await flush();

      expect(controller.phase, TryOnPhase.arFailed);
      expect(controller.mode, TryOnMode.simulated);
      expect(controller.degradeReason, TryOnDegradeReason.arFailed);
      expect(controller.failureMessage, contains('startSession'));
      expect(events.last, isA<TryOnDegradedEvent>());
    });

    test('a handover failure does not decide the session by itself', () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel()..handoverThrows = true;
      final controller = controllerFor(source, channel);

      await controller.prepareModel();
      expect(controller.phase, TryOnPhase.modelReady);
      expect(controller.mode, TryOnMode.simulated);

      await controller.startAr(arViewReady: true);
      expect(controller.mode, TryOnMode.real,
          reason: 'startSession is the authority on whether anything can '
              'render, not the handover');
    });
  });

  group('native events', () {
    test('a mid-session renderer failure falls back with the native reason',
        () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);
      final events = recordEvents(controller);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);
      expect(controller.mode, TryOnMode.real);

      channel.emit(const TryOnErrorEvent(
        reason: 'renderer_init_failed',
        message: 'no GL context',
      ));
      await flush();

      expect(controller.phase, TryOnPhase.arFailed);
      expect(controller.mode, TryOnMode.simulated);
      expect(controller.degradeReason, TryOnDegradeReason.arFailed);
      expect(controller.failureReason, 'renderer_init_failed');
      expect((events.last as TryOnDegradedEvent).message, 'no GL context');
    });

    test('telemetry lands in fields V5 can read', () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);

      channel.emit(const TryOnModelLoadedEvent(loadMs: 812, triangles: 41500));
      channel.emit(const TryOnPerfEvent(
        perf: TryOnPerf(avgFps: 57.5, frameMs: 17.4),
      ));
      await flush();

      expect(controller.modelLoadMs, 812);
      expect(controller.triangles, 41500);
      expect(controller.lastPerf, const TryOnPerf(avgFps: 57.5, frameMs: 17.4));
      expect(controller.mode, TryOnMode.real,
          reason: 'telemetry is not a failure');
    });

    test('an unknown event and a stray screenshot are ignored, not fatal',
        () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);

      channel.emit(ArTryOnUnknownEvent(type: 'footLock', data: const {}));
      channel.emit(TryOnScreenshotEvent(bytes: bytesOf(4)));
      await flush();

      expect(controller.mode, TryOnMode.real);
      expect(controller.phase, TryOnPhase.searching);
    });
  });

  group('teardown', () {
    test('dispose never stops the native session and survives late events',
        () async {
      final bytes = bytesOf(64);
      final source = sourceWith([rowFor(bytes)])
        ..files = {'store-1/product-1/model.glb': bytes};
      final channel = _FakeChannel();
      final controller = controllerFor(source, channel);

      await controller.prepareModel();
      await controller.startAr(arViewReady: true);

      controller.dispose();

      expect(channel.calls.contains('stopSession'), isFalse,
          reason: 'D1: native teardown is owned by the platform view, and a '
              'second stop caused a session-restart storm in the scan flow');

      // An event arriving after disposal must not reach a disposed notifier.
      channel.emit(const TryOnPerfEvent(perf: TryOnPerf(avgFps: 1, frameMs: 1)));
      await flush();

      expect(controller.mode, TryOnMode.real);
    });
  });
}

/// The channel, faked: records the calls the controller makes and lets a test
/// choose the session's answer.
class _FakeChannel extends ArTryOnChannel {
  final List<String> calls = <String>[];

  TryOnStartResult nextStart = const TryOnStartResult(started: true);
  Object? startError;
  bool handoverThrows = false;
  TryOnModelSpec? handedModel;

  final StreamController<ArTryOnEvent> _events =
      StreamController<ArTryOnEvent>.broadcast();

  void emit(ArTryOnEvent event) => _events.add(event);

  @override
  Stream<ArTryOnEvent> get events => _events.stream;

  @override
  void attach() {}

  @override
  Future<void> detach() async {}

  @override
  Future<TryOnStartResult> startSession() async {
    calls.add('startSession');
    final failure = startError;
    if (failure != null) throw failure;
    return nextStart;
  }

  @override
  Future<void> setModel(TryOnModelSpec spec) async {
    calls.add('setModel');
    if (handoverThrows) throw MissingPluginException('no setModel');
    handedModel = spec;
  }

  @override
  Future<void> stopSession() async => calls.add('stopSession');
}

/// The read seam in memory — the same fake the prefetch suite uses.
class _FakeSource implements ShoeModelDataSource {
  List<Map<String, dynamic>> rows = [];
  Map<String, Uint8List> files = {};
  Object? rowsError;
  Object? downloadError;
  int rowsCalls = 0;
  int downloadCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async {
    rowsCalls++;
    final failure = rowsError;
    if (failure != null) throw failure;
    return rows;
  }

  @override
  Future<Uint8List> download(String storagePath) async {
    downloadCalls++;
    final failure = downloadError;
    if (failure != null) throw failure;
    final bytes = files[storagePath];
    if (bytes == null) throw Exception('Object not found: $storagePath');
    return bytes;
  }
}
