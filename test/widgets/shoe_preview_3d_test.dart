import 'dart:async';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/constants/app_theme.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/widgets/shoe_preview_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The box itself: the handover, the stage it clears to, the gesture tutorial,
/// and the honest line a renderer that cannot draw leaves behind. The AR entry
/// is not here any more — it is the viewer's bottom bar — so the tests below
/// guard that the box draws none of its own.
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

  /// The stage handovers (`setPreviewBackground`), in the order they were sent.
  List<MethodCall> stageCalls() =>
      calls.where((call) => call.method == 'setPreviewBackground').toList();

  /// The model handovers (`setPreviewModel`). The box sends two different things
  /// now — the model and the stage colour — so each is counted on its own rather
  /// than by the length of the whole call list.
  List<MethodCall> modelCalls() =>
      calls.where((call) => call.method == 'setPreviewModel').toList();

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
    Stream<Map<String, dynamic>>? events,
    Widget? child,
    bool showDiagnostics = false,
    bool useWebViewEngine = false,
    bool paused = false,
    bool bleed = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: child ??
                ShoePreviewSection(
                  model: spec,
                  events: events,
                  showDiagnostics: showDiagnostics,
                  paused: paused,
                  bleed: bleed,
                  useWebViewEngine: useWebViewEngine,
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
      expect(modelCalls(), hasLength(1));
      final args = Map<String, Object?>.from(modelCalls().single.arguments as Map);
      expect(args['path'], '/cache/shoe_models/7_v1_abc.glb');
      expect(args['modelId'], 7);
      expect(args['sha256'], 'abc');
      expect(args['authoredLengthMm'], 270);
    });

    testWidgets('hands a different model over again, and the same one not at all',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(modelCalls(), hasLength(1));

      // A rebuild with the same bytes (a size tap, a provider notification) must
      // not re-send: the native side would destroy and re-parse the asset.
      await tester.pumpWidget(harness());
      expect(modelCalls(), hasLength(1));

      await tester.pumpWidget(harness(
        spec: const TryOnModelSpec(
          path: '/cache/shoe_models/9_v1_def.glb',
          modelId: 9,
          sha256: 'def',
        ),
      ));
      expect(modelCalls(), hasLength(2));
      expect(modelCalls().last.arguments['modelId'], 9);
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
    testWidgets('the box goes, and the honest sentence stays', (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));
      expect(find.text('View in 3D'), findsOneWidget);

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

      // ⚠️ **And no AR entry — that is not this widget's to lose any more.** The
      // pill lives outside the section since 2026-10-03 (the viewer's bottom
      // bar), which is the stronger form of the same guarantee the old "the
      // button survives the refusal" rule was reaching for: there is no branch in
      // here that can drop it. `shoe_preview_screen_test.dart` asserts it survives
      // the refusal from the page that draws it.
      expect(
        find.text('Try On in AR'),
        findsNothing,
        reason: 'a second AR entry in the box is a second way into the same camera',
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
      // No box over a model that did not load.
      expect(find.byKey(const Key('fake-3d')), findsNothing);
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

  group('a box that is handed the page\'s full width', () {
    // The viewer hands it the full width on 2026-10-03 (the owner asked for more
    // room to turn and zoom the shoe). What that moves is the *window*: the box
    // spans the page, the header row — which this widget draws — carries the page
    // gutter by insetting itself, and the renderer is handed exactly the same
    // model as before.
    testWidgets('is that width, with the header still off the screen edge',
        (tester) async {
      await tester.pumpWidget(harness(bleed: true));

      final page = tester.getSize(find.byType(Scaffold));
      expect(tester.getSize(find.byKey(const Key('fake-3d'))).width, page.width);
      expect(
        tester.getTopRight(find.text('Drag to rotate')).dx,
        page.width - kShoePreviewGutter,
        reason: 'the row that names the surface is text, and text at 0 px from a '
            'screen edge is a different widget\'s problem',
      );
      // The handover is untouched by any of this: same asset, same payload.
      expect(modelCalls(), hasLength(1));
      expect(modelCalls().single.arguments['path'], model.path);
    });

    testWidgets('and an inset box keeps its own gutter to itself', (tester) async {
      // The default (the box inside a page that has already inset the section)
      // is unchanged: the header starts where the box does. The number to pin is
      // the *difference*, not a position — the row begins with an 18 px icon.
      await tester.pumpWidget(harness());
      final inset = tester.getTopLeft(find.text('View in 3D')).dx;

      await tester.pumpWidget(harness(bleed: true));
      final bled = tester.getTopLeft(find.text('View in 3D')).dx;

      expect(
        bled - inset,
        kShoePreviewGutter,
        reason: 'the box takes the page width and the header pays the page gutter '
            'for it — one number, not two that drift apart',
      );
    });
  });

  group('the box draws no AR entry of its own', () {
    // ⚠️ It was the section's own last child until 2026-10-03. The pill is the
    // viewer's bottom bar now (`ShoePreviewScreen`), and this is the guard that
    // it cannot come back here: a second pill is a second way into the same
    // camera, and the refusal branch is exactly where the old arrangement had to
    // remember to keep it.
    testWidgets('not under the box', (tester) async {
      await tester.pumpWidget(harness());

      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(find.text('View in 3D'), findsOneWidget);
      expect(
        find.text('Try On in AR'),
        findsNothing,
        reason: 'the escalation is the page\'s, at the foot of the page',
      );
    });

    testWidgets('and not in the refusal state either', (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));
      events.add(refusalEvent);
      await tester.pump();

      expect(find.text('3D preview isn\'t supported on this phone.'),
          findsOneWidget);
      expect(find.byType(ShoePreviewHint), findsOneWidget);
      expect(
        find.text('Try On in AR'),
        findsNothing,
        reason: 'the branch that once kept the AR entry has none to keep now — '
            'the viewer draws it, outside every branch in here',
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

  group('the engine switch', () {
    // ⚠️ The two engines are reached through `useWebViewEngine`, a constructor
    // parameter that defaults to the compile-time switch, the same shape
    // `showDiagnostics` uses. Without the parameter a test could only ever assert
    // whichever engine this build happens to be compiled with — so the routing
    // itself would be the one thing never covered.

    testWidgets('the WebView engine is the default, and it is a real switch',
        (tester) async {
      // ⚠️ **The default flipped on a device measurement, not on a preference.** On
      // a vivo V2022 the native engine killed the app on 2 of 3 attempts to open
      // the 3D box (`SIGSEGV` in `TransformManager_nSetTransform+64`); the WebView
      // engine ran five opens in one process with no crash. `false` is still the
      // rollback, and the section below asserts it.
      expect(AppConstants.shoePreviewWebViewEnabled, isTrue);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShoePreview3D(
              model: model,
              // No `viewBuilder`: this exercises the real routing decision.
            ),
          ),
        ),
      ));

      // ⚠️ Asserted **negatively** through the native marker and **positively**
      // through the WebView branch's own early exit. The model path does not exist
      // under `flutter test`, and the WebView branch checks the disk before it
      // builds a server, a controller or a renderer — so this sentence appearing is
      // proof that the *WebView* branch ran, not merely that no `AndroidView` did.
      expect(
        find.byType(AndroidView),
        findsNothing,
        reason: 'the native platform view is now the opt-in path',
      );
      expect(find.text('The 3D model is not on this device.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the native engine is one parameter away, and still builds',
        (tester) async {
      // The rollback path, and the one the AR screen still needs: `Mode.AR` requires
      // a GL surface and ARCore, which a WebView cannot give it.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShoePreview3D(
              model: model,
              useWebViewEngine: false,
            ),
          ),
        ),
      ));

      // Asserted by *type* rather than by whether mounting it throws: under
      // `flutter test` there is no platform-view registry, and whether that surfaces
      // as an exception is a Flutter-version detail rather than a fact about this
      // widget.
      expect(find.byType(AndroidView), findsOneWidget);
      expect(
        find.text('The 3D model is not on this device.'),
        findsNothing,
        reason: 'the WebView branch was taken with `useWebViewEngine: false`',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing model on the WebView path says so, and never mounts',
        (tester) async {
      // The path this test can actually reach without a WebView: the disk check
      // runs before any server, controller or renderer is built, so a model that
      // is not where the handover said it was is reported on the box rather than
      // surfacing as a blank frame.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShoePreview3D(
              model: model,
              useWebViewEngine: true,
            ),
          ),
        ),
      ));

      expect(find.text('The 3D model is not on this device.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the section forwards the engine choice rather than re-deciding it',
        (tester) async {
      // A section that defaulted the flag itself could disagree with the box it
      // mounts — the exact class of bug a forwarded parameter prevents.
      await tester.pumpWidget(harness(
        useWebViewEngine: true,
        viewBuilder: () => const SizedBox(key: Key('fake-webview'), height: 240),
      ));

      expect(find.byKey(const Key('fake-webview')), findsOneWidget);
    });
  });

  group('the gesture tutorial', () {
    // ⚠️ **The fault this answers, and it is the owner's report on 2026-10-03.** The
    // box carries one line of instruction — "Drag to rotate" — in the section's
    // header, at the edge of a surface whose whole content is a shoe that *spins on
    // its own* (both engines idle-rotate). A customer who reads the shoe as a
    // picture, which is what every other product surface on this page is, taps the
    // AR pill underneath and never learns it turns. So after
    // [ShoePreview3D.hintAfterIdle] of stillness the box performs the gesture itself
    // ([ShoePreviewGestureHint]): a hand sweeping over the pill, the words for both
    // gestures, and `IgnorePointer` so the drag it is teaching still reaches the
    // renderer.
    testWidgets('the box says nothing until it has been ignored for ten seconds',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(find.byType(ShoePreviewGestureHint), findsNothing);

      // Nine seconds is not ten: the wait is asserted, not eyeballed.
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(ShoePreviewGestureHint), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ShoePreviewGestureHint), findsOneWidget);
      // Scoped to the pill: the section's own header carries the same words
      // ("Drag to rotate"), which is exactly why the pill shows the gesture rather
      // than repeating the sentence.
      Finder inPill(String label) => find.descendant(
            of: find.byType(ShoePreviewGestureHint),
            matching: find.text(label),
          );
      expect(inPill(ShoePreviewGestureHint.dragLabel), findsOneWidget);
      expect(inPill(ShoePreviewGestureHint.pinchLabel), findsOneWidget,
          reason: 'both engines answer a pinch and nothing else on the surface '
              'says so');
    });

    testWidgets('the sweep is a real animation, and it is not on the shoe',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump(ShoePreview3D.hintAfterIdle);

      double handX() => tester
          .widget<Transform>(find.descendant(
            of: find.byType(ShoePreviewGestureHint),
            matching: find.byType(Transform),
          ))
          .transform
          .getTranslation()
          .x;

      final before = handX();
      await tester.pump(const Duration(milliseconds: 300));
      expect(handX(), isNot(before), reason: 'a still hand teaches nothing');
    });

    testWidgets('the pill never swallows the drag it teaches', (tester) async {
      // ⚠️ The property that makes it a tutorial rather than a wall. The fake view
      // stands in for a renderer that answers a horizontal drag, and the drag lands
      // on the *same finger down* that dismisses the hint — which is the whole
      // lesson: do the thing and the lesson stops.
      var drags = 0;
      await tester.pumpWidget(harness(
        viewBuilder: () => GestureDetector(
          key: const Key('drag-target'),
          // `opaque` on purpose: the stand-in paints nothing, and a `deferToChild`
          // detector over an empty box is never hit — which would make this test
          // pass for the wrong reason ("nothing swallowed the drag" instead of
          // "the drag arrived").
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => drags++,
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump(ShoePreview3D.hintAfterIdle);
      expect(find.byType(ShoePreviewGestureHint), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('drag-target')),
        const Offset(40, 0),
      );

      expect(drags, greaterThan(0),
          reason: 'an overlay that eats the gesture is worse than no overlay');

      // `tester.drag` drives the pointer without pumping, so the dismissal it caused
      // is asserted on the frame after it.
      await tester.pump();
      expect(find.byType(ShoePreviewGestureHint), findsNothing);
    });

    testWidgets('a touch spends it, and the next idle stretch brings it back',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump(ShoePreview3D.hintAfterIdle);
      expect(find.byType(ShoePreviewGestureHint), findsOneWidget);

      await tester.tap(find.byKey(const Key('fake-3d')));
      await tester.pump();
      expect(find.byType(ShoePreviewGestureHint), findsNothing);

      // The countdown restarts from the release rather than resuming, so half a
      // wait is not enough…
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ShoePreviewGestureHint), findsNothing);

      // …and a full one is. (The owner's rule: every idle stretch, not once per
      // visit — a customer who taps around and then stops again is exactly the one
      // who needs reminding.)
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ShoePreviewGestureHint), findsOneWidget);
    });

    testWidgets('a paused box never counts down, and starts fresh on return',
        (tester) async {
      // While AR is on top the native view is unmounted and the box shows its idle
      // face — a hand waving over that would be teaching a screen nobody is looking
      // at, and the customer comes back to AR, not to a tutorial.
      await tester.pumpWidget(harness(paused: true));
      await tester.pump(ShoePreview3D.hintAfterIdle);
      await tester.pump(ShoePreview3D.hintAfterIdle);
      expect(find.byType(ShoePreviewGestureHint), findsNothing);

      await tester.pumpWidget(harness());
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(ShoePreviewGestureHint), findsNothing,
          reason: 'coming back starts a full wait, not a resumed one');

      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ShoePreviewGestureHint), findsOneWidget);
    });

    testWidgets('a box that cannot draw never teaches a gesture', (tester) async {
      // The one state where the box paints a sentence instead of a shoe: the WebView
      // engine checked the disk and the bytes are gone (they can be evicted between
      // the page's prefetch and this mount). A hand sweeping over "The 3D model is
      // not on this device." is a tutorial for a shoe that is not there.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShoePreview3D(model: model, useWebViewEngine: true),
          ),
        ),
      ));
      await tester.pump(ShoePreview3D.hintAfterIdle);

      expect(find.text('The 3D model is not on this device.'), findsOneWidget);
      expect(
        find.byType(ShoePreviewGestureHint),
        findsNothing,
        reason: 'the tutorial is only ever drawn over something a finger can turn',
      );
    });

    testWidgets('reduced motion keeps the pill and parks the hand', (tester) async {
      // `MediaQuery.disableAnimations` is a customer's request, not a bug: the
      // tutorial still has to be *readable* — it is the only thing on this surface
      // that says a finger does anything — so the pill stays, the sweep stops, and
      // the hand is parked mid-travel (a still frame still reads as motion).
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Center(child: ShoePreviewGestureHint()),
          ),
        ),
      ));

      expect(
        find.descendant(
          of: find.byType(ShoePreviewGestureHint),
          matching: find.text(ShoePreviewGestureHint.dragLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ShoePreviewGestureHint),
          matching: find.text(ShoePreviewGestureHint.pinchLabel),
        ),
        findsOneWidget,
      );

      double handX() => tester
          .widget<Transform>(find.descendant(
            of: find.byType(ShoePreviewGestureHint),
            matching: find.byType(Transform),
          ))
          .transform
          .getTranslation()
          .x;

      final parked = handX();
      await tester.pump(const Duration(milliseconds: 500));
      expect(handX(), parked,
          reason: 'a customer who asked for less motion asked for this too');
    });
  });

  group('the stage follows the customer\'s appearance', () {
    // ⚠️ The box used to be pinned dark in both brightnesses: the renderer cleared
    // to `#0E0F12`, a light-mode customer got a black rectangle inside a white
    // page, and the choice was invisible to them. The stage is a brightness-aware
    // token now (`AppConstants.stage`), read by every face the box has — the idle
    // face, the WebView engine's page, and the native renderer's own clear colour,
    // which is handed over the preview channel — and this group pins that it
    // reaches all of them.

    testWidgets('the idle face is the tone the renderer clears to, per brightness',
        (tester) async {
      addTearDown(AppBrightness.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: const ShoePreviewIdle())),
      ));

      for (final brightness in Brightness.values) {
        AppBrightness.set(brightness);
        // What the app root does after a brightness change, and the only thing
        // that reaches a *const* child: `updateChild` short-circuits identical
        // widgets, so a plain re-pump would leave the first tone on screen.
        AppThemeRefresh.rebuildAll();
        await tester.pump();

        expect(
          tester
              .widget<ColoredBox>(find.descendant(
                of: find.byType(ShoePreviewIdle),
                matching: find.byType(ColoredBox),
              ))
              .color,
          AppPalette.of(brightness).stage,
          reason: 'the empty box is the same rectangle the engine will draw in, '
              'or the engine start flashes from one tone to another',
        );
      }

      // The two tones, pinned: light is a paper surface rather than a slab, and
      // dark keeps exactly the value this feature has always cleared to. (Pinned
      // here rather than trusted to `AppPalette`, because they are the two values
      // the native renderer and the WebView page are set from.)
      expect(AppPalette.light.stage.computeLuminance(), greaterThan(0.8));
      expect(AppPalette.dark.stage, const Color(0xFF0E0F12));
    });

    testWidgets('the native renderer is restaged at mount and on a theme flip',
        (tester) async {
      // ⚠️ Sent from `build`, and that is the non-obvious half: a brightness change
      // repaints the tree element by element (`AppThemeRefresh.rebuildAll` in
      // `main.dart`) rather than re-creating or updating these widgets, so
      // `initState` and `didUpdateWidget` never run — and a renderer that is
      // already alive would keep clearing to the tone the customer just left.
      addTearDown(AppBrightness.reset);

      AppBrightness.set(Brightness.light);
      await tester.pumpWidget(harness());

      // Before the platform view exists, which is why the native side parks it
      // (F18): the handover is Dart's, not the view's.
      expect(stageCalls(), hasLength(1));
      expect(
        stageCalls().single.arguments['argb'],
        AppPalette.light.stage.toARGB32(),
      );

      AppBrightness.set(Brightness.dark);
      // What the app root does after a brightness change.
      AppThemeRefresh.rebuildAll();
      await tester.pump();

      expect(
        stageCalls(),
        hasLength(2),
        reason: 'a renderer that already exists keeps clearing to the old tone '
            'unless the change is handed to it',
      );
      expect(
        stageCalls().last.arguments['argb'],
        AppPalette.dark.stage.toARGB32(),
      );
    });

    testWidgets('a rebuild that changed nothing re-sends nothing', (tester) async {
      // The guard matters on this channel for the same reason `setModel` has one:
      // every rebuild of the section (a size tap, a provider notification) must not
      // put a redundant call on the wire.
      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(harness());
      expect(stageCalls(), hasLength(1));

      await tester.pumpWidget(harness());
      expect(stageCalls(), hasLength(1));
    });
  });
}
