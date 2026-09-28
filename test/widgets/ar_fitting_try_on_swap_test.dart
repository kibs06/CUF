import 'dart:async';
import 'dart:typed_data';

import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/screens/customer/ar_fitting_screen.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// **V3.5's swap, and the three ways it must not happen.**
///
/// The screen has exactly one job here: put the platform view in the camera-feed
/// slot when the capability gate says there is something real to render, and keep
/// today's simulated feed in every other case (D8). The cases below are the
/// interesting ones — the switch off, no model behind the entry, and a session
/// that has already degraded — because those are the ones a customer actually
/// meets, and the failure mode of getting them wrong is a black rectangle rather
/// than an exception.
///
/// **Two seams, both deliberate.** `tryOnViewBuilder` stands in for `AndroidView`
/// (there is no platform-view registry under `flutter test`), and the model source
/// never completes, because in the fake-async zone a real `ensureLocal` would hang
/// at its first `File.exists()` and make this file test the harness instead of the
/// screen — the boundary the V2.6 page tests already documented.
void main() {
  const fakeViewKey = Key('fake-ar-view');

  Widget wrap(Widget page) {
    final cart = _MockCartProvider();
    when(() => cart.itemCount).thenReturn(0);
    final products = _MockProductProvider();
    when(() => products.products).thenReturn(const []);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CartProvider>.value(value: cart),
        ChangeNotifierProvider<ProductProvider>.value(value: products),
      ],
      child: MaterialApp(home: page),
    );
  }

  /// A controller that is enabled and **still preparing** — the state the screen
  /// really sees for its first frames, and the only non-degraded state reachable
  /// without file I/O.
  TryOnSessionController preparingController() => TryOnSessionController(
        productId: 'product-1',
        enabled: true,
        channel: _QuietChannel(),
        models: ShoeModelService(dataSource: _NeverResolvingSource()),
      );

  /// A controller that has already degraded, without touching the network:
  /// `enabled: false` lands on `featureOff` on the first `prepareModel()`.
  TryOnSessionController degradedController() => TryOnSessionController(
        productId: 'product-1',
        enabled: false,
        channel: _QuietChannel(),
        models: ShoeModelService(dataSource: _NeverResolvingSource()),
      );

  ARVirtualFitScreen screen({
    required bool tryOnEnabled,
    required bool modelAvailable,
    TryOnSessionController? controller,
  }) =>
      ARVirtualFitScreen(
        preselectedProduct: _product,
        tryOnEnabled: tryOnEnabled,
        modelAvailable: modelAvailable,
        tryOnSessionController: controller,
        tryOnViewBuilder: () =>
            const ColoredBox(color: Colors.black, key: fakeViewKey),
      );

  Future<void> pump(WidgetTester tester, ARVirtualFitScreen page) async {
    await tester.pumpWidget(wrap(page));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Drains the screen's simulated lock-on timer (2.5 s), which `initState` arms
  /// unconditionally. Without this the binding reports "a Timer is still pending"
  /// after the tree is disposed — a property of the screen as shipped, not of the
  /// swap under test.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 3));

  bool simulatedFeedShown() =>
      find.text('Place Foot Inside Box').evaluate().isNotEmpty;

  testWidgets('the switch off keeps the simulated feed and builds no view',
      (tester) async {
    // F19: with the flag off the platform view is not built and no controller is
    // constructed, so nothing can make a channel call.
    await pump(tester, screen(tryOnEnabled: false, modelAvailable: true));

    expect(find.byKey(fakeViewKey), findsNothing);
    expect(simulatedFeedShown(), isTrue);
    await settle(tester);
  });

  testWidgets('the switch on with a model takes the camera-feed slot',
      (tester) async {
    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: true,
        controller: preparingController(),
      ),
    );

    expect(find.byKey(fakeViewKey), findsOneWidget);
    expect(simulatedFeedShown(), isFalse);
    await settle(tester);
  });

  testWidgets('no model behind the entry keeps the simulated feed',
      (tester) async {
    // Most of the catalogue, today: `product_models` has no row, so the entry
    // answers false and the customer gets the placeholder — not a dead end.
    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: false,
        controller: preparingController(),
      ),
    );

    expect(find.byKey(fakeViewKey), findsNothing);
    expect(simulatedFeedShown(), isTrue);
    await settle(tester);
  });

  testWidgets('a degraded session falls back rather than sticking on a blank view',
      (tester) async {
    // ARCore refusing is the ordinary case on an unsupported phone, and what the
    // customer must see is the simulated feed with a reason — never the platform
    // view sitting there empty.
    final controller = degradedController();
    await controller.prepareModel();

    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: true,
        controller: controller,
      ),
    );

    expect(controller.degradeReason, TryOnDegradeReason.featureOff);
    expect(find.byKey(fakeViewKey), findsNothing);
    expect(simulatedFeedShown(), isTrue);
    await settle(tester);
  });

  testWidgets('a degradation that arrives after the first frame replaces the view',
      (tester) async {
    // The swap is driven by the controller's notifications, not by the initial gate
    // answer alone. This controller is enabled and reads an empty model table, so
    // its resolution comes back in a microtask and degrades to `modelMissing` — the
    // state every product in the catalogue is in today, reached here with no file
    // I/O at all.
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      channel: _QuietChannel(),
      models: ShoeModelService(dataSource: _EmptyRowsSource()),
    );

    await tester.pumpWidget(
      wrap(
        screen(
          tryOnEnabled: true,
          modelAvailable: true,
          controller: controller,
        ),
      ),
    );
    // First frame: still preparing, so the real view owns the slot rather than a
    // fake feed flashing before it.
    expect(find.byKey(fakeViewKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.degradeReason, TryOnDegradeReason.modelMissing);
    expect(find.byKey(fakeViewKey), findsNothing);
    expect(simulatedFeedShown(), isTrue);
    await settle(tester);
  });
}

const Map<String, dynamic> _product = {
  'id': 'product-1',
  'name': 'Test Oxford',
  'price': 1099.0,
  'images': <String>[],
  'sizes': <String, int>{'39': 5},
};

/// The model read never resolves, so `prepareModel` stays in flight and the
/// session is neither ready nor degraded — the real state at mount.
class _NeverResolvingSource implements ShoeModelDataSource {
  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) =>
      Completer<List<Map<String, dynamic>>>().future;

  @override
  Future<Uint8List> download(String storagePath) =>
      Completer<Uint8List>().future;
}

/// A model table with no rows for this product: resolution returns null in memory,
/// which degrades the session to `modelMissing` after a microtask.
class _EmptyRowsSource implements ShoeModelDataSource {
  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async =>
      const [];

  @override
  Future<Uint8List> download(String storagePath) async => Uint8List(0);
}

/// The screen never calls `startAr` under this harness (no platform view is
/// created), so the channel only has to exist — but it must not be the default
/// one, or a future refactor that does start a session would reach a real
/// platform channel from a test.
class _QuietChannel extends ArTryOnChannel {
  @override
  Future<TryOnStartResult> startSession() async =>
      const TryOnStartResult(started: false, reason: 'error', message: 'test');

  @override
  void attach() {}
}

class _MockCartProvider extends Mock with ChangeNotifier implements CartProvider {}

class _MockProductProvider extends Mock
    with ChangeNotifier
    implements ProductProvider {}
