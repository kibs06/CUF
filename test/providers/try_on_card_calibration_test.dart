import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:app/providers/try_on/try_on_phase.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Card-calibrated Capture-to-Fit at the controller seam: a card measurement
/// seeds the live reading the verdict cards grade (same notifier the tracker
/// writes), without ever claiming the tracker's lock — and bad numbers are
/// refused exactly like the native stream's.
void main() {
  late Directory tempRoot;
  late Directory cacheDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('try_on_card_cal_test');
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

  Future<TryOnSessionController> realController(
    _FakeChannel channel,
    Uint8List bytes,
  ) async {
    final source = _FakeSource()
      ..rows = [rowFor(bytes)]
      ..files = {'store-1/product-1/model.glb': bytes};
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      channel: channel,
      models: ShoeModelService(
        dataSource: source,
        cacheDirectoryProvider: () async => cacheDir,
      ),
    );
    await controller.prepareModel();
    await controller.startAr(arViewReady: true);
    expect(controller.mode, TryOnMode.real);
    return controller;
  }

  Map<String, dynamic> productWithSpecs() => <String, dynamic>{
        'last_length_mm': 276.0,
        'fit_ref_size_eu': 42.0,
      };

  group('selectSize', () {
    test('forwards the fitted size with the last spec', () async {
      final channel = _FakeChannel();
      final controller = await realController(channel, bytesOf(64));

      await controller.selectSize(sizeEu: '43', product: productWithSpecs());

      expect(channel.sizes, hasLength(1));
      expect(channel.sizes.single['sizeEu'], '43');
      expect(channel.sizes.single['refSizeEu'], 42.0);
      expect(channel.sizes.single['lastLengthMm'], 276.0);
      controller.dispose();
    });

    test('refuses a bad size, a spec-less product and a non-real session',
        () async {
      final channel = _FakeChannel();
      final controller = await realController(channel, bytesOf(64));

      await controller.selectSize(sizeEu: 'Other', product: productWithSpecs());
      await controller.selectSize(sizeEu: '42', product: const {});
      expect(channel.sizes, isEmpty);
      controller.dispose();

      final simChannel = _FakeChannel();
      final source = _FakeSource()..rows = [];
      final sim = TryOnSessionController(
        productId: 'product-1',
        enabled: true,
        channel: simChannel,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: () async => cacheDir,
        ),
      );
      await sim.prepareModel();
      await sim.selectSize(sizeEu: '42', product: productWithSpecs());
      expect(simChannel.sizes, isEmpty);
      sim.dispose();
    });

    test('a channel fault never becomes the session failure', () async {
      final channel = _FakeChannel()..failSetSize = true;
      final controller = await realController(channel, bytesOf(64));

      await controller.selectSize(sizeEu: '42', product: productWithSpecs());

      expect(controller.mode, TryOnMode.real);
      expect(controller.degradeReason, TryOnDegradeReason.none);
      controller.dispose();
    });
  });

  group('applyCardCalibration', () {
    test('seeds the live reading without claiming a lock', () async {
      final channel = _FakeChannel();
      final controller = await realController(channel, bytesOf(64));

      // The tracker is searching: a reading exists (or not) but no lock.
      expect(controller.liveFoot.value.locked, isFalse);

      controller.applyCardCalibration(lengthMm: 268.0, quality: 0.9);

      expect(controller.liveFoot.value.lengthMm, 268.0);
      expect(controller.liveFoot.value.quality, 0.9);
      expect(controller.liveFoot.value.locked, isFalse,
          reason: 'only the native tracker can claim it is following a foot');
      expect(controller.phase, TryOnPhase.searching);
      controller.dispose();
    });

    test('non-finite quality clamps, bad lengths are refused', () async {
      final channel = _FakeChannel();
      final controller = await realController(channel, bytesOf(64));

      controller.applyCardCalibration(lengthMm: 268.0, quality: double.nan);
      expect(controller.liveFoot.value.lengthMm, 268.0);
      expect(controller.liveFoot.value.quality, 0.0);

      controller.applyCardCalibration(lengthMm: 0, quality: 0.9);
      expect(controller.liveFoot.value.lengthMm, 268.0,
          reason: 'a zero length must not overwrite the seed');
      controller.applyCardCalibration(
          lengthMm: double.nan, quality: 0.9);
      expect(controller.liveFoot.value.lengthMm, 268.0);
      controller.dispose();
    });

    test('a non-real session ignores the call', () async {
      final channel = _FakeChannel();
      final source = _FakeSource()..rows = [];
      final controller = TryOnSessionController(
        productId: 'product-1',
        enabled: true,
        channel: channel,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: () async => cacheDir,
        ),
      );
      await controller.prepareModel();
      expect(controller.mode, TryOnMode.simulated);

      controller.applyCardCalibration(lengthMm: 268.0, quality: 0.9);

      expect(controller.liveFoot.value.lengthMm, isNull);
      controller.dispose();
    });
  });
}

/// The channel, faked: a started session with no further behaviour — the
/// calibration tests never need frames, poses or events.
class _FakeChannel extends ArTryOnChannel {
  final StreamController<ArTryOnEvent> _events =
      StreamController<ArTryOnEvent>.broadcast();

  @override
  Stream<ArTryOnEvent> get events => _events.stream;

  @override
  void attach() {}

  @override
  Future<void> detach() async {}

  @override
  Future<TryOnStartResult> startSession() async =>
      const TryOnStartResult(started: true);

  @override
  Future<void> setModel(TryOnModelSpec spec) async {}

  final List<Map<String, Object?>> sizes = [];
  bool failSetSize = false;

  @override
  Future<void> setSize({
    required String sizeEu,
    num? refSizeEu,
    num? lastLengthMm,
  }) async {
    if (failSetSize) throw Exception('no native view');
    sizes.add({
      'sizeEu': sizeEu,
      'refSizeEu': refSizeEu,
      'lastLengthMm': lastLengthMm,
    });
  }
}

/// The read seam in memory — the same fake the prefetch suite uses.
class _FakeSource implements ShoeModelDataSource {
  List<Map<String, dynamic>> rows = [];
  Map<String, Uint8List> files = {};

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async =>
      rows;

  @override
  Future<Uint8List> download(String storagePath) async {
    final bytes = files[storagePath];
    if (bytes == null) throw Exception('Object not found: $storagePath');
    return bytes;
  }
}
