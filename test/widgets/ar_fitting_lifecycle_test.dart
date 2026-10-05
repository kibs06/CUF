import 'dart:async';

import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/screens/customer/ar_fitting_screen.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// **V4.8's stability contract for the try-on screen, held on a desk.**
///
/// The phase is a perf/stability pass, and the parts of it a desk can hold are
/// exactly these three:
///
///   1. **Rotation lock.** The screen pins the app to portrait while it is
///      open and restores the platform default when it closes, so no other
///      route inherits the lock and no customer rotates an AR session the
///      renderer has never been run in.
///   2. **Backgrounding.** Every lifecycle change reaches the controller as a
///      foreground/background fact. What a pause means for the loop (a pause
///      is not a stop; a failure stop is not undone) is the controller's own
///      contract, pinned in `test/providers/try_on_foot_track_test.dart`.
///   3. **Twenty open/close cycles.** Opening and closing the screen twenty
///      times leaves no timer armed and no listener behind. The binding's own
///      teardown check ("A Timer is still pending…") is the leak detector for
///      the timers; the listener half is counted through a spy controller.
///
/// What this file cannot hold is what needs a device: whether the AR session
/// actually resumes after the system backgrounds it, whether a phone that is
/// hot enough to throttle still renders, and whether the session's memory
/// returns to its baseline across those twenty cycles (roadmap V4.8's device
/// half — §2.11 puts the number at ≤ 250 MB).
void main() {
  Widget wrap(Widget page, {List<Map<String, dynamic>> products = const []}) {
    final cart = _MockCartProvider();
    when(() => cart.itemCount).thenReturn(0);
    final productProvider = _MockProductProvider();
    when(() => productProvider.products).thenReturn(products);
    final auth = _MockAuthProvider();
    when(() => auth.profile).thenReturn(null);
    when(() => auth.currentUser).thenReturn(const {'id': 'user-1'});
    final foot = _MockFootMeasurementProvider();
    when(() => foot.latestMeasurement).thenReturn(null);
    when(() => foot.loadLatest(any())).thenAnswer((_) async {});

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CartProvider>.value(value: cart),
        ChangeNotifierProvider<ProductProvider>.value(value: productProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<FootMeasurementProvider>.value(value: foot),
      ],
      child: MaterialApp(home: page),
    );
  }

  ARVirtualFitScreen screen({
    bool tryOnEnabled = false,
    bool modelAvailable = false,
    TryOnSessionController? controller,
  }) =>
      ARVirtualFitScreen(
        preselectedProduct: _product,
        tryOnEnabled: tryOnEnabled,
        modelAvailable: modelAvailable,
        tryOnSessionController: controller,
        tryOnViewBuilder: () => const ColoredBox(color: Colors.black),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // Rotation lock
  // ═══════════════════════════════════════════════════════════════════════

  group('rotation lock', () {
    testWidgets('the screen pins portrait while open and restores the default '
        'on close', (tester) async {
      final orientations = <List<String>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add((call.arguments as List).cast<String>());
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(wrap(screen()));
      await tester.pump();

      expect(
        orientations,
        <List<String>>[
          <String>['DeviceOrientation.portraitUp'],
        ],
        reason: 'an AR session may not be rotated into a layout nobody has '
            'run on a device',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(
        orientations.last,
        <String>[
          'DeviceOrientation.portraitUp',
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.portraitDown',
          'DeviceOrientation.landscapeRight',
        ],
        reason: 'the lock lives and dies with this route — a customer who '
            'leaves the try-on can rotate the rest of the app again',
      );
      expect(orientations, hasLength(2),
          reason: 'exactly one lock and one restore, not one per rebuild');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Backgrounding
  // ═══════════════════════════════════════════════════════════════════════

  group('backgrounding', () {
    testWidgets('every lifecycle change reaches the controller as '
        'foreground/background', (tester) async {
      final controller = _SpyController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(
        screen(tryOnEnabled: true, modelAvailable: true, controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      // The canonical Android order down and back up.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(controller.foreground, <bool>[false]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(controller.foreground, <bool>[false, false]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(controller.foreground, <bool>[false, false, false]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(controller.foreground, <bool>[false, false, false, true],
          reason: 'only a real resume is foreground; every other state means '
              'the customer is not looking at the session');
    });

    testWidgets('with no session the lifecycle change is inert', (tester) async {
      // The switch off means no controller exists; the observer must not
      // require one (or a build that never asked for try-on would crash on
      // the first backgrounding).
      await tester.pumpWidget(wrap(screen()));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.takeException(), isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Twenty open/close cycles
  // ═══════════════════════════════════════════════════════════════════════

  group('twenty open/close cycles', () {
    testWidgets('the simulated screen arms no timer that outlives it',
        (tester) async {
      // Each cycle pumps 100 ms and then closes, so the screen's 2.5 s
      // simulated-lock timer is still armed at every unmount if dispose did
      // not cancel it — which is exactly what makes a regression fail the
      // binding's own teardown check at the end of this test rather than
      // pass silently.
      for (var cycle = 0; cycle < 20; cycle++) {
        await tester.pumpWidget(wrap(screen()));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(ARVirtualFitScreen), findsNothing);
    });

    testWidgets('the live-session path keeps addListener and removeListener '
        'balanced', (tester) async {
      // One controller, twenty mounts: the screen is the only listener, and a
      // close that only *stops* listening when it also owns the controller
      // would leave nineteen dead states on an injected controller. The spy
      // counts both sides.
      final controller = _SpyController();
      addTearDown(controller.dispose);

      for (var cycle = 0; cycle < 20; cycle++) {
        await tester.pumpWidget(wrap(
          screen(
            tryOnEnabled: true,
            modelAvailable: true,
            controller: controller,
          ),
        ));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        expect(controller.adds, cycle + 1,
            reason: 'cycle $cycle mounted without adding its listener');
        expect(controller.removes, cycle + 1,
            reason: 'cycle $cycle closed without removing its listener');
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('a product switch arms its relock timer through the cancelling '
        'field too', (tester) async {
      await tester.pumpWidget(wrap(screen(), products: const [_otherProduct]));
      await tester.pump(const Duration(milliseconds: 100));

      // The first-run guide overlays the whole screen; dismiss it before trying
      // to reach the switcher underneath.
      await tester.tap(find.text('Got It'));
      await tester.pump();
      expect(find.text('Test Oxford'), findsOneWidget);

      // The bottom panel's variant switcher: the screen's first ListView.
      final switcher = find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(GestureDetector),
      );
      expect(switcher, findsOneWidget);

      await tester.tap(switcher);
      await tester.pump();
      expect(find.text('Test Derby'), findsOneWidget,
          reason: 'the tap must really switch products — the relock timer is '
              'only armed by a real switch, and a missed tap would make this '
              'test vacuous');
      // The thumbnail is a `NetworkImage` and `flutter_test`'s HTTP client
      // answers 400 for it; that load failure belongs to the harness, not the
      // screen.
      tester.takeException();

      // Close before the 1.8 s relock deadline: a `Future.delayed` regression
      // leaves a timer the binding reports at teardown, exactly like the
      // simulated lock above.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // V4.9: the readout seam
  // ═══════════════════════════════════════════════════════════════════════

  group('V4.9: the heartbeat readout', () {
    testWidgets('draws nothing until the controller has a line, then draws it '
        'verbatim', (tester) async {
      final controller = _SpyController();
      await tester.pumpWidget(wrap(screen(controller: controller)));
      await tester.pump();

      expect(find.textContaining('loop='), findsNothing,
          reason: 'a session that has not received a heartbeat draws no strip '
              'over the camera — and in a customer build the native side is '
              'never even asked for one');

      const line = 'loop=on iter=61 present=58 foot=locked len=264mm '
          'scale=1.024 mask=ready thermal=none';
      controller.nativeStatusLine.value = line;
      await tester.pump();

      expect(find.text(line), findsOneWidget,
          reason: 'the line is the whole evidence a phone with no adb can '
              'carry out in a screenshot, so it is drawn verbatim');
    });
  });
}

const Map<String, dynamic> _product = {
  'id': 'product-1',
  'name': 'Test Oxford',
  'price': 1099.0,
  'images': <String>[],
  'sizes': <String, int>{'39': 5},
};

/// A second product for the switcher, so `_switchProduct` is reachable from the
/// UI rather than only from the source.
const Map<String, dynamic> _otherProduct = {
  'id': 'product-2',
  'name': 'Test Derby',
  'price': 1299.0,
  'images': <String>[],
  'sizes': <String, int>{'40': 3},
};

/// The screen's controller, watched: lifecycle calls recorded, and the listener
/// count on both sides of [ChangeNotifier].
class _SpyController extends TryOnSessionController {
  _SpyController()
      : super(
          productId: 'product-1',
          enabled: true,
          channel: _QuietChannel(),
          models: ShoeModelService(dataSource: _NeverResolvingSource()),
        );

  final List<bool> foreground = <bool>[];
  int adds = 0;
  int removes = 0;

  @override
  void setAppForeground({required bool foreground}) {
    this.foreground.add(foreground);
    super.setAppForeground(foreground: foreground);
  }

  @override
  void addListener(VoidCallback listener) {
    adds++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removes++;
    super.removeListener(listener);
  }
}

/// The model read never resolves, so `prepareModel` stays in flight and the
/// session is neither ready nor degraded — the state a screen really sees at
/// mount, with no database, download or file I/O.
class _NeverResolvingSource implements ShoeModelDataSource {
  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) =>
      Completer<List<Map<String, dynamic>>>().future;

  @override
  Future<Uint8List> download(String storagePath) =>
      Completer<Uint8List>().future;
}

/// The screen never calls `startAr` under this harness (no platform view is
/// created), so the channel only has to exist — and it must not be the default
/// one, or a future refactor that does start a session would reach a real
/// platform channel from a test.
class _QuietChannel extends ArTryOnChannel {
  @override
  Future<TryOnStartResult> startSession() async =>
      const TryOnStartResult(started: false, reason: 'error', message: 'test');

  @override
  void attach() {}
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
