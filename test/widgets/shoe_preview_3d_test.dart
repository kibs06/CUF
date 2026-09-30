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

  Widget harness({
    TryOnModelSpec spec = model,
    Widget Function()? viewBuilder,
    VoidCallback? onTryOnInAr,
    Stream<Map<String, dynamic>>? events,
    Widget? child,
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
      // The page sets `paused` while the AR screen is on top (`_openArTryOn`) —
      // a route check inside this widget would *not* have worked, because a push
      // does not rebuild the route underneath it, and the product-page contract
      // test pins that reasoning at the call site.
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
}
