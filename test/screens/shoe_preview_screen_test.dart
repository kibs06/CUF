import 'dart:async';

import 'package:app/screens/shared/shoe_preview_screen.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/services/try_on_prefetch.dart';
import 'package:app/utils/shoe_model_resolver.dart';
import 'package:app/widgets/shoe_preview_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// **The full-screen 3D viewer** — what the product photo's 3D icon opens for a
/// customer, and what the seller's "3D fitting ready" row opens too.
///
/// What is asserted here is the framing, not the renderer: that the box really
/// does get the size of a screen rather than the 240 px frame the page used to
/// give it (the reason this file exists at all), that the section's header comes
/// with it, that the AR escalation is the page's own bottom action and survives a
/// renderer that refuses, and that the model is handed over on the way in over the
/// real channel. The renderer states — the refusal sentence, the QA readout, the
/// pause during AR — belong to `ShoePreviewSection` and are pinned in
/// `shoe_preview_3d_test.dart` and the product-page contract test.
///
/// The **seller door** gets its own group: it is the one that resolves a model
/// it was not handed, and it is the only place the honest "there is nothing to
/// draw" sentence is reachable from a seller's tap.
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

  /// The model handovers, in the order they were sent. The box also hands its
  /// stage colour over (`setPreviewBackground`, asserted in
  /// `shoe_preview_3d_test.dart`), so "what did this screen send the renderer"
  /// is asked per method rather than by the whole list.
  List<MethodCall> modelCalls() =>
      calls.where((call) => call.method == 'setPreviewModel').toList();

  const model = TryOnModelSpec(
    path: '/cache/shoe_models/7_v1_abc.glb',
    modelId: 7,
    sha256: 'abc',
    authoredLengthMm: 270,
  );

  final product = <String, dynamic>{
    'id': 'product-1',
    'name': 'JBC Crown Leather Sandals',
  };

  /// `AndroidView` cannot be mounted under `flutter test`, so the platform view
  /// is reached through the same `viewBuilder` seam the box documents. `events`
  /// is the section's native stream, forwarded by the screen — the refusal tests
  /// below send on it.
  Widget harness({Stream<Map<String, dynamic>>? events}) => MaterialApp(
        home: ShoePreviewScreen(
          model: model,
          product: product,
          events: events,
          viewBuilder: () => const SizedBox(key: Key('fake-3d'), height: 240),
        ),
      );

  /// The seller door: no model in hand, a product id instead.
  Widget sellerHarness(
    TryOnPrefetch prefetch, {
    Stream<Map<String, dynamic>>? events,
  }) =>
      MaterialApp(
        home: ShoePreviewScreen.forProduct(
          productId: 'product-1',
          product: product,
          prefetch: prefetch,
          events: events,
          note: 'Change it any time from the product form.',
          viewBuilder: () => const SizedBox(key: Key('fake-3d'), height: 240),
        ),
      );

  ShoeModelSpec spec() => const ShoeModelSpec(
        id: 7,
        storagePath: 'models/7/v1.glb',
        sha256: 'abc',
        version: 1,
        authoredLengthMm: 270,
      );

  /// A prefetch driven by stubbed calls rather than a socket: the point of the
  /// seller door is *policy* — what it does with a row, a cache miss and a
  /// failure — and each of those is one stub away.
  TryOnPrefetch prefetchThat({
    required ShoeModelSpec? resolved,
    bool ensures = true,
  }) {
    final models = _MockShoeModelService();
    when(() => models.resolveForProduct(
          any(),
          variantId: any(named: 'variantId'),
          // The seller's door asks the product-level question, so the stub has
          // to answer *that* call — `anyVariant` is part of the invocation.
          anyVariant: any(named: 'anyVariant'),
        )).thenAnswer((_) async => resolved);
    if (resolved != null && ensures) {
      when(() => models.ensureLocal(resolved)).thenAnswer(
        (_) async => const ShoeModelFile(
          path: '/cache/shoe_models/7_v1_abc.glb',
          fromCache: false,
          bytes: 1024,
        ),
      );
    }
    return TryOnPrefetch(enabled: true, models: models);
  }

  group('the viewer', () {
    testWidgets('gives the shoe the screen, not the page row it used to get',
        (tester) async {
      await tester.pumpWidget(harness());

      expect(find.byKey(const Key('fake-3d')), findsOneWidget);

      // The whole point of leaving the page: the box is a landscape of its own
      // instead of the 240 px strip that left the shoe competing with the size
      // grid for the same screen.
      final box = tester.getSize(find.byKey(const Key('fake-3d')));
      expect(
        box.height,
        greaterThan(240),
        reason: 'a screen whose box is the page row it already had is a route '
            'that costs a tap and shows nothing new',
      );
      // ⚠️ And the whole width of the page, gutters included: they came off on
      // 2026-10-03, when the owner asked for more room to turn and zoom the shoe
      // (the model itself is untouched — see the group below).
      final page = tester.getSize(find.byType(Scaffold));
      expect(box.width, page.width);

      // And it fits: no scroll, no cut-off shoe.
      expect(tester.takeException(), isNull);
    });

    testWidgets('and the room the pill used to leave empty', (tester) async {
      // ⚠️ On a **phone-sized** surface on purpose: the stage was capped at
      // 520 px, and on a tall screen that left a band of empty page between the
      // box and the pinned pill — the same dead space the pill's own move was
      // about. The default 600 px test surface is too short for that ceiling to
      // have bitten, so this is the size that can show the change at all.
      tester.view.physicalSize = const Size(1080, 2408);
      tester.view.devicePixelRatio = 2.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness());

      final box = tester.getSize(find.byKey(const Key('fake-3d')));
      final boxBottom = tester.getBottomLeft(find.byKey(const Key('fake-3d')));
      final pill = tester.getTopLeft(find.text('Try On in AR'));

      expect(
        box.height,
        greaterThan(520),
        reason: 'the old ceiling is what left the band of empty page under it',
      );
      expect(
        pill.dy - boxBottom.dy,
        lessThan(80),
        reason: 'a stage that stops well short of the pill is the empty band '
            'this move was asked to remove',
      );
    });

    testWidgets('while the words keep the page\'s own gutter', (tester) async {
      // The other half of the rule: the stage is the page, the text is not. The
      // header row is drawn inside `ShoePreview3D`, so it insets itself with the
      // same number the page insets the note with (`kShoePreviewGutter`).
      await tester.pumpWidget(harness());

      final page = tester.getSize(find.byType(Scaffold));
      expect(
        tester.getTopRight(find.text('Drag to rotate')).dx,
        page.width - kShoePreviewGutter,
        reason: 'the header has to line up with the sentences below it — two '
            'gutters drifting apart is what kShoePreviewGutter exists to stop',
      );
    });

    testWidgets('names the product and keeps the section, with its AR entry',
        (tester) async {
      await tester.pumpWidget(harness());

      expect(find.text('JBC Crown Leather Sandals'), findsOneWidget);
      // The section's own words come with it: what this surface is, and how to
      // use it.
      expect(find.text('View in 3D'), findsOneWidget);
      expect(find.text('Drag to rotate'), findsOneWidget);
      // And the camera stays one tap deeper — the escalation rather than a
      // second entry the customer had to choose between on the page.
      expect(find.text('Try On in AR'), findsOneWidget);
    });

    testWidgets('pins the AR escalation to the bottom edge of the page',
        (tester) async {
      // The owner's request, 2026-10-03: directly under the box the pill left a
      // dead half-page beneath it. It is the page's bottom action now — the
      // treatment it had on the product page before the viewer existed (a
      // floating CTA above the buy bar) — and it stays pinned at any height,
      // because it is outside the scroll area.
      await tester.pumpWidget(harness());

      final box = tester.getBottomLeft(find.byKey(const Key('fake-3d')));
      final button = tester.getBottomLeft(find.text('Try On in AR'));
      final page = tester.getSize(find.byType(Scaffold));

      // The customer still looks at the shoe first: the camera is the escalation.
      expect(button.dy, greaterThan(box.dy));
      // …and the escalation sits at the foot of the page rather than in the flow.
      expect(
        page.height - button.dy,
        lessThan(120),
        reason: 'a button halfway up the screen with nothing under it is the '
            'layout this move was asked for',
      );
    });

    testWidgets('and a renderer that refuses does not take it with it',
        (tester) async {
      // ⚠️ The property the old button-in-the-section arrangement existed to
      // protect — a customer who opens AR and comes back must still find the
      // entry (the owner's decision of 2026-09-30, from a real phone that lost
      // it) — now holds structurally: the pill is outside the section that swaps
      // its box for the honest sentence, so no branch in there can drop it.
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(harness(events: events.stream));
      expect(find.byKey(const Key('fake-3d')), findsOneWidget);

      events.add(<String, dynamic>{
        'type': 'error',
        'data': <String, dynamic>{
          'reason': kRendererUnsupportedReason,
          'message': 'glTF loading needs FEATURE_LEVEL_2; this renderer is '
              'FEATURE_LEVEL_1',
        },
      });
      await tester.pump();

      expect(find.text('3D preview isn\'t supported on this phone.'),
          findsOneWidget);
      expect(find.byKey(const Key('fake-3d')), findsNothing);
      expect(
        find.text('Try On in AR'),
        findsOneWidget,
        reason: 'the AR screen degrades to its simulated mode on such a phone, so '
            'the entry stays honestly usable',
      );
    });

    testWidgets('hands the model over on the way in', (tester) async {
      await tester.pumpWidget(harness());

      expect(modelCalls(), hasLength(1));
      final args = Map<String, Object?>.from(modelCalls().single.arguments as Map);
      expect(args['path'], '/cache/shoe_models/7_v1_abc.glb');
      expect(args['modelId'], 7);
    });

    testWidgets('leaves the AR entry out on the seller\'s door', (tester) async {
      // A seller cannot try the pair on — the customer can. The escalation is
      // the customer's, so the seller's viewer is the shoe and nothing else.
      await tester.pumpWidget(sellerHarness(
        prefetchThat(resolved: spec()),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(find.text('Try On in AR'), findsNothing);
      expect(
        find.text('Change it any time from the product form.'),
        findsOneWidget,
        reason: 'the sentence the deleted ready sheet carried, where the seller '
            'now actually is',
      );
    });

    testWidgets('and none appears when the renderer refuses either',
        (tester) async {
      // The refusal branch was built around "the AR entry survives". The seller's
      // door is the one place that rule must never reach: nobody there can try
      // the pair on.
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(sellerHarness(
        prefetchThat(resolved: spec()),
        events: events.stream,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-3d')), findsOneWidget);

      events.add(<String, dynamic>{
        'type': 'error',
        'data': <String, dynamic>{
          'reason': kRendererUnsupportedReason,
          'message': 'FEATURE_LEVEL_1',
        },
      });
      // ⚠️ Two pumps: the first flushes the event (and is the frame that gets
      // skipped, because nothing had a frame scheduled), the second is the build
      // the section's `setState` asked for.
      await tester.pump();
      await tester.pump();

      expect(find.text('3D preview isn\'t supported on this phone.'),
          findsOneWidget);
      expect(find.byKey(const Key('fake-3d')), findsNothing);
      expect(
        find.text('Try On in AR'),
        findsNothing,
        reason: 'a camera button on the seller\'s screen launches a fitting flow '
            'on the wrong side of the shop',
      );
    });

    testWidgets('pops back to the page it was opened from', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ShoePreviewScreen(
                    model: model,
                    product: product,
                    viewBuilder: () =>
                        const SizedBox(key: Key('fake-3d'), height: 240),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ShoePreviewScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(
        find.byType(ShoePreviewScreen),
        findsNothing,
        reason: 'a viewer the customer cannot leave in one tap is a trap on the '
            'page they were comparing sizes on',
      );
    });
  });

  group('the seller\'s door', () {
    testWidgets('resolves the model itself, then draws it', (tester) async {
      final models = _MockShoeModelService();
      final resolved = spec();
      when(() => models.resolveForProduct(
            any(),
            variantId: any(named: 'variantId'),
            anyVariant: any(named: 'anyVariant'),
          )).thenAnswer((_) async => resolved);
      when(() => models.ensureLocal(resolved)).thenAnswer(
        (_) async => const ShoeModelFile(
          path: '/cache/shoe_models/7_v1_abc.glb',
          fromCache: false,
          bytes: 1024,
        ),
      );

      await tester.pumpWidget(
        sellerHarness(TryOnPrefetch(enabled: true, models: models)),
      );

      // The wait is stated rather than left as an empty page: the download is a
      // few megabytes on a phone connection.
      expect(find.text('Fetching the 3D model…'), findsOneWidget);
      expect(find.byKey(const Key('fake-3d')), findsNothing);

      await tester.pumpAndSettle();

      expect(find.text('Fetching the 3D model…'), findsNothing);
      expect(find.byKey(const Key('fake-3d')), findsOneWidget);
      expect(find.text('View in 3D'), findsOneWidget);

      // ⚠️ And it asked the product-level question. `anyVariant` is the whole
      // reason a product whose models are colour-scoped does not answer "no
      // model" to the seller who owns the row saying otherwise.
      verify(() => models.resolveForProduct(
            'product-1',
            variantId: null,
            anyVariant: true,
          )).called(1);

      // …and the bytes went to the renderer over the real channel, in the same
      // payload the customer path sends.
      expect(modelCalls(), hasLength(1));
      final args = Map<String, Object?>.from(modelCalls().single.arguments as Map);
      expect(args['path'], '/cache/shoe_models/7_v1_abc.glb');
      expect(args['modelId'], 7);
    });

    testWidgets('says so, without a retry, when the product has no model left',
        (tester) async {
      // ⚠️ The state the seller door exists to make findable. "3D fitting ready"
      // is a claim about a `product_models` row; a row is not a shoe, and a
      // seller who taps to check is the only one who can catch it. Offering
      // Retry here would send them round a loop that cannot succeed.
      await tester.pumpWidget(sellerHarness(prefetchThat(resolved: null)));
      await tester.pumpAndSettle();

      expect(
        find.text('No 3D model is on this product any more.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(find.byKey(const Key('fake-3d')), findsNothing);
    });

    testWidgets('offers one more attempt when the fetch itself failed',
        (tester) async {
      // A row that is there but bytes that did not arrive is worth a retry —
      // mobile data, a cold cache, a hash that did not match.
      final models = _MockShoeModelService();
      when(() => models.resolveForProduct(
            any(),
            variantId: any(named: 'variantId'),
            anyVariant: any(named: 'anyVariant'),
          )).thenThrow(Exception('offline'));

      await tester.pumpWidget(sellerHarness(
        TryOnPrefetch(enabled: true, models: models),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('The 3D model could not be fetched just now.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

class _MockShoeModelService extends Mock implements ShoeModelService {}
