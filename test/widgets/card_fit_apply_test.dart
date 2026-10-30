import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/models/card_fit_result.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/screens/customer/ar_fitting_screen.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// The try-on half of card Capture-to-Fit, at the screen seam: applying a
/// [CardFitResult] picks the size, rescales the renderer through `setSize`
/// (visible from the first frame — no tracker lock needed), and says which
/// of the three outcomes landed.
///
/// Navigation is deliberately out of scope here (the capture screen owns the
/// camera); [applyCardFitResult] is the seam under test. The controller is
/// real and staged to a live session, so a recorded `setSize` proves the
/// shoe — not just the chip — moved.
void main() {
  // Staging touches the real filesystem (model bytes in a temp cache dir),
  // which cannot run in `testWidgets`' fake-async zone — so setup and
  // teardown run in the real zone via `runAsync`, and only the pumped
  // assertions stay fake.
  late Directory tempRoot;
  late Directory cacheDir;

  Future<void> stageTemp(WidgetTester tester) => tester.runAsync(() async {
        tempRoot = await Directory.systemTemp.createTemp('card_fit_apply_test');
        cacheDir =
            Directory('${tempRoot.path}${Platform.pathSeparator}cache');
      });

  Future<void> unstageTemp(WidgetTester tester) => tester.runAsync(() async {
        if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
      });

  Uint8List bytesOf(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => (i * 7) % 256));

  Map<String, dynamic> productWith(Map<String, int> sizes) =>
      <String, dynamic>{
        'id': 'product-1',
        'name': 'Test Spec Oxford',
        'price': 1099.0,
        'images': <String>[],
        'sizes': sizes,
        'last_length_mm': 275.0,
        'fit_ref_size_eu': 42.0,
        'last_width_mm': 100.0,
      };

  CardFitResult resultFor(String sizeEu) => CardFitResult(
        compensatedLengthMm: 268.0,
        widthMm: 102.0,
        sizeEu: sizeEu,
        scaleMedian: 0.42,
        scaleIqrMmPerPx: 0.001,
        burstFrames: 6,
        confidenceLevel: 'high',
        footSide: 'left',
      );

  Future<TryOnSessionController> liveController(
    WidgetTester tester,
    _RecordingChannel channel,
  ) async {
    await stageTemp(tester);
    final bytes = bytesOf(64);
    final source = _FakeSource()
      ..rows = [
        <String, dynamic>{
          'id': 7,
          'variant_id': null,
          'storage_path': 'store-1/product-1/model.glb',
          'sha256': sha256.convert(bytes).toString(),
          'version': 2,
          'authored_length_mm': 278,
          'shoe_side': 'right',
        },
      ]
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
    await tester.runAsync(() async {
      await controller.prepareModel();
      await controller.startAr(arViewReady: true);
    });
    expect(controller.mode, TryOnMode.real);
    return controller;
  }

  Future<dynamic> pumpWith(
    WidgetTester tester,
    TryOnSessionController controller,
    Map<String, dynamic> product,
  ) async {
    final cart = _MockCartProvider();
    when(() => cart.itemCount).thenReturn(0);
    final products = _MockProductProvider();
    when(() => products.products).thenReturn(const []);
    final auth = _MockAuthProvider();
    when(() => auth.profile).thenReturn(null);
    final foot = _MockFootMeasurementProvider();
    when(() => foot.latestMeasurement).thenReturn(null);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CartProvider>.value(value: cart),
          ChangeNotifierProvider<ProductProvider>.value(value: products),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<FootMeasurementProvider>.value(value: foot),
        ],
        child: MaterialApp(
          home: ARVirtualFitScreen(
            preselectedProduct: product,
            tryOnEnabled: true,
            modelAvailable: true,
            tryOnSessionController: controller,
            tryOnViewBuilder: () => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return tester.state(find.byType(ARVirtualFitScreen));
  }

  group('applyCardFitResult', () {
    testWidgets('exact in-stock size applies, rescales and says so',
        (tester) async {
      final channel = _RecordingChannel();
      final controller = await liveController(tester, channel);
      final state = await pumpWith(
        tester,
        controller,
        productWith({'41': 2, '42': 5}),
      );

      await state.applyCardFitResult(resultFor('42'));
      await tester.pump();

      expect(channel.sizes, hasLength(1));
      expect(channel.sizes.single['sizeEu'], '42');
      expect(channel.sizes.single['refSizeEu'], 42.0);
      expect(find.text('Card fit applied: EU 42'), findsOneWidget);
      controller.dispose();
      await unstageTemp(tester);
    });

    testWidgets('nearest in-stock size rescales and names the substitution',
        (tester) async {
      final channel = _RecordingChannel();
      final controller = await liveController(tester, channel);
      final state = await pumpWith(
        tester,
        controller,
        productWith({'41': 0, '42.5': 4}),
      );

      await state.applyCardFitResult(resultFor('42'));
      await tester.pump();

      expect(channel.sizes, hasLength(1));
      expect(channel.sizes.single['sizeEu'], '42.5');
      expect(
        find.text('Card fit measured EU 42 — nearest in stock is EU 42.5'),
        findsOneWidget,
      );
      controller.dispose();
      await unstageTemp(tester);
    });

    testWidgets('nothing in stock keeps the size and says so', (tester) async {
      final channel = _RecordingChannel();
      final controller = await liveController(tester, channel);
      final state = await pumpWith(
        tester,
        controller,
        productWith({'38': 4}),
      );

      await state.applyCardFitResult(resultFor('42'));
      await tester.pump();

      expect(channel.sizes, isEmpty);
      expect(
        find.text('Card fit measured EU 42 — not in stock for this shoe'),
        findsOneWidget,
      );
      controller.dispose();
      await unstageTemp(tester);
    });
  });
}

/// Records the native calls a started session makes; the event stream stays
/// silent because these tests never need one.
class _RecordingChannel extends ArTryOnChannel {
  final List<Map<String, Object?>> sizes = [];

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

  @override
  Future<void> setSize({
    required String sizeEu,
    num? refSizeEu,
    num? lastLengthMm,
  }) async {
    sizes.add({
      'sizeEu': sizeEu,
      'refSizeEu': refSizeEu,
      'lastLengthMm': lastLengthMm,
    });
  }
}

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

class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

class _MockFootMeasurementProvider extends Mock
    with ChangeNotifier
    implements FootMeasurementProvider {}

class _MockCartProvider extends Mock with ChangeNotifier implements CartProvider {}

class _MockProductProvider extends Mock
    with ChangeNotifier
    implements ProductProvider {}
