import 'package:app/screens/shared/shoe_preview_screen.dart';
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:app/services/shoe_preview_channel.dart';
import 'package:app/services/try_on_prefetch.dart';
import 'package:app/utils/shoe_model_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// **The full-screen 3D viewer** — what the product photo's 3D icon opens for a
/// customer, and what the seller's "3D fitting ready" row opens too.
///
/// What is asserted here is the framing, not the renderer: that the box really
/// does get the size of a screen rather than the 240 px frame the page used to
/// give it (the reason this file exists at all), that the section's header and
/// its AR escalation come with it, and that the model is handed over on the way
/// in over the real channel. The renderer states — the refusal, the QA readout,
/// the pause during AR — belong to `ShoePreviewSection` and are pinned in
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
  /// is reached through the same `viewBuilder` seam the box documents.
  Widget harness() => MaterialApp(
        home: ShoePreviewScreen(
          model: model,
          product: product,
          viewBuilder: () => const SizedBox(key: Key('fake-3d'), height: 240),
        ),
      );

  /// The seller door: no model in hand, a product id instead.
  Widget sellerHarness(TryOnPrefetch prefetch) => MaterialApp(
        home: ShoePreviewScreen.forProduct(
          productId: 'product-1',
          product: product,
          prefetch: prefetch,
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
      // Edge to edge, less the screen's own 20 px gutters — the shoe is not in a
      // card, it is the surface.
      expect(box.width, tester.getSize(find.byType(Scaffold)).width - 40);

      // And it fits: no scroll, no cut-off shoe.
      expect(tester.takeException(), isNull);
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

    testWidgets('hands the model over on the way in', (tester) async {
      await tester.pumpWidget(harness());

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setPreviewModel');
      final args = Map<String, Object?>.from(calls.single.arguments as Map);
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
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setPreviewModel');
      final args = Map<String, Object?>.from(calls.single.arguments as Map);
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
