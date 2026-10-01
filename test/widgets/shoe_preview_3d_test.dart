import 'dart:async';

import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/widgets/shoe_preview_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The inline 3D box and the AR button under it.
///
/// `AndroidView` cannot be mounted under `flutter test` — there is no
/// platform-view registry — so the view is reached through the same seam the AR
/// screen documents (`ShoePreview3D.viewBuilder`). What is *not* faked is the
/// channel: the handover runs through the real `ShoePreviewChannel` against a
/// mock binary messenger, so the payload the native side will receive is the
/// payload asserted here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kShoePreviewMethodChannel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const model = TryOnModelSpec(
    path: '/cache/shoe_models/7_v1_abc.glb',
    modelId: 7,
    sha256: 'abc',
    authoredLengthMm: 270,
  );

  /// The refusal exactly as a level-1 renderer sends it, including the facts
  /// `ArTryOnView.describeRenderer` appends — a device that advertises GLES 3.2
  /// whose *context* Filament still received as level 1 is the case that decides
  /// whether the level can be raised at all (Filament asks for an ES2 context and
  /// takes what the driver returns).
  const refusalEvent = <String, dynamic>{
    'type': 'error',
    'data': <String, dynamic>{
      'reason': kRendererUnsupportedReason,
      'message': 'glTF loading needs FEATURE_LEVEL_2; this renderer is '
          'FEATURE_LEVEL_1 (OPENGL supported=FEATURE_LEVEL_1 '
          'active=FEATURE_LEVEL_1 · device GLES 3.2)',
    },
  };

  Widget harness({
    TryOnModelSpec spec = model,
    Widget Function()? viewBuilder,
    VoidCallback? onTryOnInAr,
    Stream<Map<String, dynamic>>? events,
    Widget? child,
    bool showDiagnostics = false,
    bool showTryOn = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: child ??
                ShoePreviewSection(
                  model: spec,
                  onTryOnInAr: onTryOnInAr ?? () {},
                  events: events,
                  showDiagnostics: showDiagnostics,
                  showTryOn: showTryOn,
                  viewBuilder: viewBuilder ??
                      () => const SizedBox(key: Key('fake-3d'), height: 240),
                ),
          ),
        ),
      ),
    );
  }

  group('the box', () {
    testWidgets('names itself, says how to use it, and holds the model',
        (tester) async {
      await tester.pumpWidget(harness());

      expect(find.text('View in 3D'), findsOneWidget);
      expect(find.text('Drag to rotate'), findsOneWidget);
      expect(find.byKey(const Key('fake-3d')), findsOneWidget);

      // The handover, over the real channel: same payload shape the AR session
      // sends, because both feed the same renderer.
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setPreviewModel');
      final args = Map<String, Object?>.from(calls.single.arguments as Map);
      expect(args['path'], '/cache/shoe_models/7_v1_abc.glb');
      expect(args['modelId'], 7);
      expect(args['sha256'], 'abc');
      expect(args['authoredLengthMm'], 270);
    });

    testWidgets('hands a different model over again, and the same one not at all',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(calls, hasLength(1));

      // A rebuild with the same bytes (a size tap, a provider notification) must
      // not re-send: the native side would destroy and re-parse the asset.
      await tester.pumpWidget(harness());
      expect(calls, hasLength(1));

      await tester.pumpWidget(harness(
        spec: const TryOnModelSpec(
          path: '/cache/shoe_models/9_v1_def.glb',
          modelId: 9,
          sha256: 'def',
        ),
      ));
      expect(calls, hasLength(2));
      expect(calls.last.arguments['modelId'], 9);
    });

    testWidgets('unmounts the native view while it is paused, without moving',
        (tester) async {
      // ⚠️ The property that keeps two Filament engines from running at once.
      // The viewer that mounts this section sets `paused` while the AR screen is
      // on top (`ShoePreviewScreen._openArTryOn`) — a route check inside this
      // widget would *not* have worked, because a push does not rebuild the route
      // underneath it, and the product-page contract test pins that reasoning at
      // the call site.
      var built = 0;
      Widget box({required bool paused}) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: ShoePreviewSection(
                  model: model,
                  paused: paused,
                  onTryOnInAr: () {},
                  viewBuilder: () {
                    built++;
                    return const SizedBox(key: Key('fake-3d'), height: 240);
                  },
                ),
              ),
            ),
          );

      await tester.pumpWidget(box(paused: false));
      expect(built, 1);
      final liveHeight = tester.getSize(find.byKey(const Key('fake-3d')));

      await tester.pumpWidget(box(paused: true));
      // The engine is gone…
      expect(find.byKey(const Key('fake-3d')), findsNothing);
      expect(find.byType(ShoePreviewIdle), findsOneWidget);
      // …and the box kept its size, so coming back does not jump the page.
      expect(tester.getSize(find.byType(ShoePreviewIdle)), liveHeight);
      expect(built, 1);

      await tester.pumpWidget(box(paused: false));
      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(built, 2);
    });

    testWidgets('a build with no native plugin renders nothing and breaks nothing',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      await tester.pumpWidget(harness());

      expect(tester.takeException(), isNull);
      expect(find.text('View in 3D'), findsOneWidget);
    });
  });

  group('a renderer that cannot draw takes the section off the page', () {
    // ⚠️ Reproduced for real on 2026-09-29: on the Pixel_4 emulator the engine came
    // up at FEATURE_LEVEL_1 and loading the first model was a SIGSEGV inside
    // libfilament-jni.so — the app died on the product page. `ArTryOnView` now
    // refuses to load below feature level 2 and reports this reason instead, and
    // this is what the Dart side has to do with it.
    testWidgets('the box and the button both go', (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));
      expect(find.text('View in 3D'), findsOneWidget);
      expect(find.text('Try On in AR'), findsOneWidget);

      events.add(<String, dynamic>{
        'type': 'error',
        'data': <String, dynamic>{
          'reason': kRendererUnsupportedReason,
          'message': 'glTF loading needs FEATURE_LEVEL_2; this renderer is FEATURE_LEVEL_1',
        },
      });
      await tester.pump();

      // Unmounting the box is the point rather than a side effect: it disposes the
      // native view, and with it the engine.
      expect(find.byKey(const Key('fake-3d')), findsNothing);
      expect(find.text('View in 3D'), findsNothing);

      // What stays is the honest line — the difference between "this product
      // has no model" (most of the catalogue) and "your phone cannot draw one"
      // (a bug report we can otherwise never answer; the phones this market
      // holds have no logcat).
      expect(find.text('3D preview isn\'t supported on this phone.'), findsOneWidget);
      expect(find.byType(ShoePreviewHint), findsOneWidget);

      // ⚠️ And the AR pill STAYS — the owner's decision after a real phone
      // showed the original all-or-nothing rule eating it mid-visit (open AR,
      // come back, no AR entry anywhere: the gate now said "shown" while the
      // section said "gone"). The AR screen degrades to its simulated mode with
      // its own notice on such a phone, so the entry stays honestly usable.
      // Originally the test pinned the opposite — "offering a camera would be a
      // promise we cannot keep" — which was true only while the simulated
      // fallback was the placeholder feed and not a stated degradation.
      expect(
        find.text('Try On in AR'),
        findsOneWidget,
        reason: 'the AR entry must survive the renderer refusal — the customer who '
            'just came back from AR is exactly the one still looking for it',
      );
    });

    testWidgets('any other preview error leaves the section alone', (tester) async {
      // A preview that failed to load a model it could have drawn is not a reason
      // to remove a working surface from the page.
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));

      for (final event in <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'error',
          'data': <String, dynamic>{'reason': 'model_parse_failed'},
        },
        <String, dynamic>{'type': 'modelLoaded', 'data': <String, dynamic>{'loadMs': 12}},
        <String, dynamic>{'type': 'perf', 'data': <String, dynamic>{'avgFps': 60.0}},
      ]) {
        events.add(event);
        await tester.pump();
      }

      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(find.text('Try On in AR'), findsOneWidget);
      expect(find.byType(ShoePreviewHint), findsNothing);
    });

    testWidgets('a customer build prints the sentence and none of the numbers',
        (tester) async {
      // The measured facts are a diagnosis, not copy: a shopper is owed the honest
      // sentence, and the GL strings belong on a QA phone's screen (see
      // `SHOE_PREVIEW_DIAGNOSTICS` and `ShoePreviewHint.detail`).
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));
      events.add(refusalEvent);
      await tester.pump();

      expect(find.text('3D preview isn\'t supported on this phone.'), findsOneWidget);
      expect(find.textContaining('device GLES'), findsNothing);
      expect(find.textContaining('QA'), findsNothing);
    });

    testWidgets('the QA readout puts the measured facts under that sentence',
        (tester) async {
      // ⚠️ The reason this exists at all: the phone this investigation runs on
      // (Huawei P30 Pro) has developer options locked behind a forgotten
      // password, so no `adb logcat` will ever be read from it. The message the
      // native side already carries — which renderer, at which feature level,
      // with or without cube-map arrays — is the readout, and the page is the
      // only channel that reaches it.
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream, showDiagnostics: true));
      events.add(refusalEvent);
      await tester.pump();

      expect(find.text('3D preview isn\'t supported on this phone.'), findsOneWidget);
      expect(
        find.textContaining('device GLES 3.2'),
        findsOneWidget,
        reason: 'the device half of the readout — "device 3.2, supported 1" is what '
            'says the context came back below what the phone can do',
      );
      expect(find.textContaining('supported=FEATURE_LEVEL_1'), findsOneWidget);
      expect(find.textContaining('renderer_feature_level_unsupported'), findsOneWidget);
      expect(find.text('Try On in AR'), findsOneWidget);
    });

    testWidgets('a QA build also prints the failure that is not the refusal',
        (tester) async {
      // The level-1 override's whole question is what happens *after* the refusal
      // stops refusing. A load that fails to parse is the measurement on that
      // build, and a customer build stays silent about it (the test above).
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream, showDiagnostics: true));
      events.add(<String, dynamic>{
        'type': 'error',
        'data': <String, dynamic>{
          'reason': 'model_parse_failed',
          'message': 'loader returned null · OPENGL supported=FEATURE_LEVEL_1 '
              'active=FEATURE_LEVEL_1 · device GLES 3.0',
        },
      });
      await tester.pump();

      expect(find.text('3D preview failed on this build.'), findsOneWidget);
      expect(find.textContaining('model_parse_failed'), findsOneWidget);
      // No box over a model that did not load, and the AR entry still there.
      expect(find.byKey(const Key('fake-3d')), findsNothing);
      expect(find.text('Try On in AR'), findsOneWidget);
    });

    testWidgets('the renderer\'s own heartbeat lands on the QA line',
        (tester) async {
      // ⚠️ Added 2026-10-01, from the first render anyone has seen on hardware: the
      // sandal *did* draw at `FEATURE_LEVEL_1` (so F14/D10's "nothing loads at level
      // 1" is an emulator answer rather than a device one), and then two faults
      // appeared that a screenshot of the render cannot explain — the box froze
      // after about a second, and the app died when the same box was opened a
      // second time. The phone has no logcat, so the renderer reports itself into
      // this line: "running and presenting nothing" has to have a number.
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream, showDiagnostics: true));
      events.add(<String, dynamic>{
        'type': 'status',
        'data': <String, dynamic>{
          'line': 'loop=on frames=0 engine=1/0 chain=NULL creates=2 touch=3 ',
          'loopRunning': true,
          'fromLastRun': 'loop=on frames=58 engine=2/1 chain=ok creates=1 touch=0',
          'lastSwapChainError': 'IllegalStateException: surface abandoned',
        },
      });
      await tester.pump();

      // The live heartbeat, the failure it recorded, and the *previous* process's
      // last words — the last one is the only evidence that survives the crash it
      // was describing, which is why it is printed first.
      expect(find.textContaining('loop=on frames=0'), findsOneWidget);
      expect(find.textContaining('chain=NULL'), findsOneWidget);
      expect(find.textContaining('prev: loop=on frames=58'), findsOneWidget);
      expect(find.textContaining('surface abandoned'), findsOneWidget);
      // The box is still there: a heartbeat is information, not a fault.
      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(find.byType(ShoePreviewHint), findsNothing);
    });

    testWidgets('a customer build prints no heartbeat at all', (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));
      events.add(<String, dynamic>{
        'type': 'status',
        'data': <String, dynamic>{'line': 'loop=on frames=60 engine=1/0 chain=ok'},
      });
      await tester.pump();

      expect(find.textContaining('loop=on'), findsNothing);
      expect(find.textContaining('frames='), findsNothing);
    });

    testWidgets('the hint is a pure widget: message plus optional action',
        (tester) async {
      // Mounted directly — it has no channel, no gate and no state of its own;
      // the page decides when it exists.
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShoePreviewHint(
            message: '3D preview couldn\'t load just now.',
            actionLabel: 'Retry',
            onAction: () => taps++,
          ),
        ),
      ));

      expect(find.text('3D preview couldn\'t load just now.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(taps, 1);

      // No action = no button (the unsupported-renderer state).
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ShoePreviewHint(message: '3D preview isn\'t supported on this phone.'),
        ),
      ));
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('the QA banner says which switch is on', () {
    // The banner is the only evidence a *photo* of a QA run carries, and the two
    // switches mean different things: a lowered engine that then drew a shoe is
    // the experiment working, while the load override alone on a modern phone
    // measures nothing at all (the guard never fires there). So the sentence is
    // composed rather than fixed, and it is asserted here rather than eyeballed.
    Future<void> pumpBanner(
      WidgetTester tester, {
      required bool loadOverride,
      required bool engineLowered,
    }) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ShoePreviewQaBanner(
              loadOverride: loadOverride,
              engineLowered: engineLowered,
            ),
          ),
        ));

    testWidgets('the load override is named as the one that can abort',
        (tester) async {
      await pumpBanner(tester, loadOverride: true, engineLowered: false);
      expect(
        find.text('QA build · level-1 load override on — may abort the process'),
        findsOneWidget,
      );
    });

    testWidgets('a lowered engine is a separate claim, and says so', (tester) async {
      await pumpBanner(tester, loadOverride: false, engineLowered: true);
      expect(
        find.text('QA build · engine pinned to level 1'),
        findsOneWidget,
        reason: 'a lowered engine must not read like a crashing load: one is a '
            'worse renderer on a QA phone, the other can kill the process',
      );
    });

    testWidgets('both switches read as both', (tester) async {
      await pumpBanner(tester, loadOverride: true, engineLowered: true);
      expect(
        find.text('QA build · engine pinned to level 1 · level-1 load override on '
            '— may abort the process'),
        findsOneWidget,
        reason: 'this is the pair that is meant to be run together: lower the '
            'renderer, then let the load it forbids happen',
      );
    });
  });

  group('the AR button under it', () {
    testWidgets('is the only AR entry the section offers, and it is below the box',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(harness(onTryOnInAr: () => taps++));

      expect(find.text('Try On in AR'), findsOneWidget);

      // Below the box, not above it: the customer looks at the shoe first, and
      // the camera is the escalation.
      final box = tester.getBottomLeft(find.byKey(const Key('fake-3d')));
      final button = tester.getTopLeft(find.text('Try On in AR'));
      expect(button.dy, greaterThan(box.dy));

      await tester.tap(find.text('Try On in AR'));
      expect(taps, 1);
    });
  });

  group('the seller\'s view of the same box', () {
    // The seller's door to this section (`ShoePreviewScreen.forProduct`) is a
    // seller checking what the shop is selling. Nobody there can try the pair
    // on, so the escalation is dropped — including in the refusal state, which
    // is the branch built around "the AR entry survives".
    testWidgets('draws the box and no AR pill', (tester) async {
      await tester.pumpWidget(harness(showTryOn: false));

      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(find.text('View in 3D'), findsOneWidget);
      expect(find.text('Try On in AR'), findsNothing);
    });

    testWidgets('keeps the honest refusal line, and still no pill',
        (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream, showTryOn: false));
      events.add(refusalEvent);
      await tester.pump();

      expect(find.text('3D preview isn\'t supported on this phone.'), findsOneWidget);
      expect(find.byType(ShoePreviewHint), findsOneWidget);
      expect(
        find.text('Try On in AR'),
        findsNothing,
        reason: 'the branch that exists to keep the AR entry must not put it on '
            'a screen where the AR flow has no meaning',
      );
    });
  });

  group('the 3D icon on the photograph', () {
    // The product page's whole entry into the 3D viewer since 2026-10-01: the
    // icon rides on the hero image and the viewer is one tap away.
    testWidgets('is an icon-only control with a name and a 44 px target',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: Sole3DIconButton(onPressed: () => taps++)),
        ),
      ));

      expect(find.byIcon(Icons.threed_rotation), findsOneWidget);
      expect(
        find.byTooltip('View in 3D'),
        findsOneWidget,
        reason: 'an icon with no words is invisible to a screen reader, and this '
            'control has no label beside it on the photo',
      );
      expect(
        tester.getSize(find.byType(Sole3DIconButton)),
        greaterThanOrEqualTo(const Size(44, 44)),
        reason: 'the minimum touch target — it sits over a photograph, where a '
            'near miss pans the image instead',
      );

      await tester.tap(find.byType(Sole3DIconButton));
      expect(taps, 1);
    });

    testWidgets('carries the label as a real accessibility name', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: Sole3DIconButton(onPressed: () {}))),
      ));

      expect(
        find.bySemanticsLabel('View in 3D'),
        findsOneWidget,
        reason: 'the tooltip is a sighted-thumb aid; the accessible name is the '
            'explicit label, and it is the only description this control has',
      );

      handle.dispose();
    });
  });
}
