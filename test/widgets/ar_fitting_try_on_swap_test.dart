import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/models/foot_measurement.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:app/providers/try_on/try_on_phase.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/screens/customer/ar_fitting_screen.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:app/utils/shoe_model_resolver.dart';
import 'package:app/utils/try_on_fit.dart';
import 'package:crypto/crypto.dart';
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

  Widget wrap(
    Widget page, {
    Map<String, dynamic>? profile,
    FootMeasurement? measurement,
  }) {
    final cart = _MockCartProvider();
    when(() => cart.itemCount).thenReturn(0);
    final products = _MockProductProvider();
    when(() => products.products).thenReturn(const []);

    // V4.7's card reads both of these; the screen itself does not. With no
    // profile it never asks for a measurement, which is what every existing
    // test in this file exercises.
    final auth = _MockAuthProvider();
    when(() => auth.profile).thenReturn(profile);
    when(() => auth.currentUser).thenReturn(const {'id': 'user-1'});
    final foot = _MockFootMeasurementProvider();
    when(() => foot.latestMeasurement).thenReturn(measurement);
    when(() => foot.loadLatest(any())).thenAnswer((_) async {});

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CartProvider>.value(value: cart),
        ChangeNotifierProvider<ProductProvider>.value(value: products),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<FootMeasurementProvider>.value(value: foot),
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
    Map<String, dynamic> product = _product,
  }) =>
      ARVirtualFitScreen(
        preselectedProduct: product,
        tryOnEnabled: tryOnEnabled,
        modelAvailable: modelAvailable,
        tryOnSessionController: controller,
        tryOnViewBuilder: () =>
            const ColoredBox(color: Colors.black, key: fakeViewKey),
      );

  Future<void> pump(
    WidgetTester tester,
    ARVirtualFitScreen page, {
    Map<String, dynamic>? profile,
    FootMeasurement? measurement,
  }) async {
    await tester.pumpWidget(
      wrap(page, profile: profile, measurement: measurement),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Advances past the screen's simulated lock-on timer (2.5 s) so later
  /// assertions see the settled state. Since V4.8 that timer is a cancellable
  /// `Timer`, so this is about frame time rather than about the binding's
  /// pending-timer check — the check is what the 20-cycle test in
  /// `ar_fitting_lifecycle_test.dart` uses as its leak detector.
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

  // ── V4.6: the live verdict is wired to the reading, and gated ───────────

  testWidgets('the live verdict appears when a measured foot is locked',
      (tester) async {
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      footTrackEnabled: true,
      channel: _QuietChannel(),
      models: ShoeModelService(dataSource: _NeverResolvingSource()),
    );
    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: true,
        controller: controller,
        product: _productWithSpecs,
      ),
    );

    expect(find.byKey(const ValueKey('try-on-fit-verdict')), findsNothing,
        reason: 'no reading has arrived yet, so the card must be silent');

    // What the native `footMeasure` + `footLock` pair would publish.
    controller.liveFoot.value = const TryOnLiveFoot(
      lengthMm: 265,
      quality: 0.9,
      locked: true,
    );
    await tester.pump();

    expect(find.text('True to size'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('try-on-fit-verdict')),
        matching: find.text('EU 42'),
      ),
      findsOneWidget,
      reason: 'the bottom panel prints its own size label; the chip must be '
          "the verdict card's",
    );
    await settle(tester);
  });

  testWidgets('no foot tracking, no live verdict — even with a reading',
      (tester) async {
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      // footTrackEnabled defaults to false: the V4.1 switch is the gate, the
      // same one the coach card reads.
      channel: _QuietChannel(),
      models: ShoeModelService(dataSource: _NeverResolvingSource()),
    );
    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: true,
        controller: controller,
        product: _productWithSpecs,
      ),
    );

    controller.liveFoot.value = const TryOnLiveFoot(
      lengthMm: 265,
      quality: 0.9,
      locked: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('try-on-fit-verdict')), findsNothing);
    expect(find.text('True to size'), findsNothing);
    await settle(tester);
  });

  // ── V4.7: the saved-size suggestion, and where it sits ──────────────────

  testWidgets('a saved scan that disagrees with the live foot is offered a '
      'rescan', (tester) async {
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      footTrackEnabled: true,
      channel: _QuietChannel(),
      models: ShoeModelService(dataSource: _NeverResolvingSource()),
    );
    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: true,
        controller: controller,
        product: _productWithSpecs,
      ),
      profile: const {'foot_size_ph': 42, 'foot_profile_source': 'ar_scan'},
      measurement: _savedFoot(264),
    );

    expect(find.byKey(const ValueKey('try-on-saved-size')), findsNothing);

    controller.liveFoot.value = const TryOnLiveFoot(
      lengthMm: 273.4,
      quality: 0.9,
      locked: true,
    );
    await tester.pump();

    expect(
      find.text('Your saved size may be stale — rescan?'),
      findsOneWidget,
    );
    // The suggestion is first in the column, above the verdict: the two cards
    // the customer is acting on must not be displaced by a hint about old
    // data appearing and disappearing.
    final notice = tester.getRect(
      find.byKey(const ValueKey('try-on-saved-size')),
    );
    final verdict = tester.getRect(
      find.byKey(const ValueKey('try-on-fit-verdict')),
    );
    expect(notice.bottom, lessThanOrEqualTo(verdict.top + 1));
    await settle(tester);
  });

  testWidgets('a saved scan that agrees keeps the suggestion off the screen',
      (tester) async {
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      footTrackEnabled: true,
      channel: _QuietChannel(),
      models: ShoeModelService(dataSource: _NeverResolvingSource()),
    );
    await pump(
      tester,
      screen(
        tryOnEnabled: true,
        modelAvailable: true,
        controller: controller,
        product: _productWithSpecs,
      ),
      profile: const {'foot_size_ph': 42, 'foot_profile_source': 'ar_scan'},
      measurement: _savedFoot(268),
    );

    controller.liveFoot.value = const TryOnLiveFoot(
      lengthMm: 273.4,
      quality: 0.9,
      locked: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('try-on-saved-size')), findsNothing);
    expect(
      find.byKey(const ValueKey('try-on-fit-verdict')),
      findsOneWidget,
      reason: 'the verdict is still the V4.6 card; only the saved-size hint is silent',
    );
    await settle(tester);
  });

  // ── V4.9: the start that the view beat, and the retry that answers it ────
  //
  // The defect these two pin is why the AR camera went black on a device
  // (QA, 2026-10-05). The screen calls `startAr` from the platform view's
  // creation; `prepareModel` hands the model over asynchronously. When the view
  // wins that race `startAr` returns at its `modelReady` gate, and nothing calls
  // it again — the QA phone sat on exactly that screen for 48 minutes: no
  // session, no camera, 173,660 frames of a black rectangle.

  testWidgets('the model landing after the view still starts AR', (tester) async {
    final source = _GatedRowSource(
      Uint8List.fromList(List<int>.generate(96, (i) => (i * 11) % 256)),
    );
    final channel = _RecordingChannel();
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      channel: channel,
      models: _MemoryModelService(source, source.bytes),
    );

    await pump(
      tester,
      screen(tryOnEnabled: true, modelAvailable: true, controller: controller),
    );

    // The ordering a phone really produces: the view is up (the injected builder
    // stands in for it) while the handover is still running.
    expect(controller.phase, TryOnPhase.loadingModel);
    expect(channel.calls, isEmpty,
        reason: 'nothing to start yet — startAr is gated on modelReady');

    // The handover lands. The row wait is a gate here rather than a network
    // round trip, but everything after it is the production path: the row is
    // parsed, the spec resolved and the model handed over.
    source.gate.complete();
    await tester.pump();

    expect(controller.modelPath, isNotNull,
        reason: 'the handover itself has to have finished, or this test is '
            'measuring a phase that never landed');
    expect(channel.calls, contains('startSession'),
        reason: 'the phase reaching modelReady is the second chance F17 left '
            'the screen, and without it the camera never starts');
    expect(controller.mode, TryOnMode.real);
    await settle(tester);
  });

  testWidgets('a view with no model to show never starts a camera',
      (tester) async {
    // The retry's other half: it waits for the model, so a session that is still
    // staging cannot start a camera the customer has nothing to see in.
    final channel = _RecordingChannel();
    final controller = TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      channel: channel,
      models: ShoeModelService(dataSource: _NeverResolvingSource()),
    );

    await pump(
      tester,
      screen(tryOnEnabled: true, modelAvailable: true, controller: controller),
    );
    await settle(tester);

    expect(controller.phase, TryOnPhase.loadingModel);
    expect(channel.calls, isEmpty);
  });

  // ── V4.1's switch, pinned as source because no test can define it ────────
  //
  // `AppConstants.tryOnFootTrackEnabled` is a `bool.fromEnvironment`, so the
  // `--dart-define=TRY_ON_FOOT_TRACK=true` path cannot be exercised here — and
  // the switch's own doc says it can turn the loop on. That is only true while
  // the screen's construction site reads it (the call sites that must not drift
  // are the V3.9 gate tests' subject too). The controller's runtime behaviour
  // under either flag value is pinned in `try_on_foot_track_test.dart`.
  test('the screen hands the foot-tracking switch to the controller', () {
    final source = File(
      'lib/screens/customer/ar_fitting_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('footTrackEnabled: AppConstants.tryOnFootTrackEnabled'),
      reason: 'the switch is inert unless the only construction site reads it',
    );
  });

  // ── V4.9's readout switch, pinned for the same reason ────────────────────
  //
  // The defect this phase fixed was that the V4 heartbeat could not be switched
  // on for the try-on session at all. The screen reading the QA define is the
  // half that keeps it reachable: a refactor that dropped this line would take
  // the whole device session's evidence with it, silently.
  test('the screen hands the QA readout switch to the controller', () {
    final source = File(
      'lib/screens/customer/ar_fitting_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('diagnostics: AppConstants.shoePreviewDiagnosticsEnabled'),
      reason: 'the readout is unreachable on a device unless the only '
          'construction site passes the switch',
    );
  });
}

const Map<String, dynamic> _product = {
  'id': 'product-1',
  'name': 'Test Oxford',
  'price': 1099.0,
  'images': <String>[],
  'sizes': <String, int>{'39': 5},
};

/// The same product with the last spec the fit engine grades — V4.6's card has
/// nothing to say without one (the V1 rule, unchanged).
const Map<String, dynamic> _productWithSpecs = {
  'id': 'product-1',
  'name': 'Test Spec Oxford',
  'price': 1099.0,
  'images': <String>[],
  'sizes': <String, int>{'42': 5},
  'last_length_mm': 275.0,
  'fit_ref_size_eu': 42.0,
  'last_width_mm': 100.0,
};

/// V4.7's saved profile: 264 mm on the sizing (right) foot — the number
/// `maxFootLength` returns and therefore the number the engine grades with.
FootMeasurement _savedFoot(double lengthMm) => FootMeasurement(
      userId: 'user-1',
      sizingFootSide: 'right',
      footLengthRightMm: lengthMm,
      paperSizeUsed: 'ar',
      scanDate: DateTime(2026, 9, 27),
    );

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

/// The channel for tests where no session may start: `startSession` answers a
/// refusal, so a screen that reached one would degrade rather than quietly pass.
/// It must not be the default channel either, or a screen that does start a
/// session would reach a real platform channel from a test.
class _QuietChannel extends ArTryOnChannel {
  @override
  Future<TryOnStartResult> startSession() async =>
      const TryOnStartResult(started: false, reason: 'error', message: 'test');

  @override
  void attach() {}
}

/// Records what the screen asked the native side to do, and answers the two
/// calls a started session makes.
///
/// Both answers matter for the same reason: under `flutter test` there is no
/// platform behind the channel, and an unanswered `invokeMethod` is a future
/// that never completes — which would leave the model handover mid-await and
/// make this file measure the harness instead of the screen.
class _RecordingChannel extends ArTryOnChannel {
  final List<String> calls = <String>[];

  @override
  Future<void> setModel(TryOnModelSpec spec) async {
    calls.add('setModel');
  }

  @override
  Future<TryOnStartResult> startSession() async {
    calls.add('startSession');
    return const TryOnStartResult(started: true);
  }

  @override
  void attach() {}
}

/// One real model row, held until the test opens [gate]: the handover has to
/// succeed for the phase to reach `modelReady`, and the row carries bytes whose
/// digest the production resolver can actually accept.
///
/// The gate is what makes the ordering deliberate rather than incidental — the
/// screen's view exists before the model lands, which is what a phone does
/// (a network round trip, then a file check) and what the fake clock would
/// otherwise collapse into the same frame.
class _GatedRowSource implements ShoeModelDataSource {
  _GatedRowSource(this.bytes);

  final Uint8List bytes;
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async {
    await gate.future;
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 7,
        'variant_id': null,
        'storage_path': 'store-1/product-1/model.glb',
        'sha256': sha256.convert(bytes).toString(),
        'version': 2,
        'authored_length_mm': 278,
        'shoe_side': 'right',
      },
    ];
  }

  @override
  Future<Uint8List> download(String storagePath) async => bytes;
}

/// The production service with its one disk-bound step answered from memory.
///
/// `ensureLocal` is where a phone spends the time this race turns on:
/// `File.exists` and `readAsBytes`, real I/O that cannot complete under the
/// fake clock. Everything the screen's retry depends on — the resolved spec, the
/// handed-over path, the `modelReady` phase — still comes from the real code
/// above it.
class _MemoryModelService extends ShoeModelService {
  _MemoryModelService(ShoeModelDataSource source, this.bytes)
      : super(dataSource: source);

  final Uint8List bytes;

  @override
  Future<ShoeModelFile> ensureLocal(
    ShoeModelSpec spec, {
    bool force = false,
  }) async =>
      ShoeModelFile(
        path: 'try-on/model.glb',
        fromCache: true,
        bytes: bytes.length,
      );
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
