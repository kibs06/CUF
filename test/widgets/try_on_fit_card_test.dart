import 'package:app/utils/try_on_fit.dart';
import 'package:app/widgets/foot_size_v2/glass_card.dart';
import 'package:app/widgets/try_on/try_on_fit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **V4.6's card.** The rules decide the state (`try_on_fit_test.dart`); this
/// file decides that the card renders that state's own sentences — the band,
/// the size chip, the engine's reasons, the live footer — and that a hidden
/// state draws *nothing at all*, which is every second before a lock.
///
/// The last group repeats the scan's own lesson: every state is laid out at
/// 320 px with 1.6× text, because a card over a camera has no scroll view to
/// rescue it.
void main() {
  Map<String, dynamic> productWithSpec() => <String, dynamic>{
        'last_length_mm': 275.0,
        'fit_ref_size_eu': 42.0,
        'last_width_mm': 100.0,
      };

  Widget wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) =>
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: MediaQuery(
            data: MediaQueryData(textScaler: textScaler),
            child: Center(
              child: SizedBox(width: 320, child: child),
            ),
          ),
        ),
      );

  TryOnFitCard card({
    double? lengthMm = 265.0,
    double quality = 0.9,
    bool locked = true,
    String? size = '42',
  }) =>
      TryOnFitCard(
        product: productWithSpec(),
        selectedSize: size,
        live: TryOnLiveFoot(
          lengthMm: lengthMm,
          quality: quality,
          locked: locked,
        ),
      );

  GlassTone toneOf(WidgetTester tester) =>
      tester.widget<GlassCard>(find.byType(GlassCard)).tone;

  testWidgets('nothing to say draws nothing — not an empty glass panel', (tester) async {
    await tester.pumpWidget(wrap(card(locked: false)));
    expect(find.byType(GlassCard), findsNothing);
    expect(find.byType(Text), findsNothing);

    await tester.pumpWidget(wrap(card(lengthMm: null)));
    expect(find.byType(GlassCard), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the verdict says the band, the size and the millimetres',
      (tester) async {
    await tester.pumpWidget(wrap(card()));

    expect(find.byKey(const ValueKey('try-on-fit-verdict')), findsOneWidget);
    expect(find.text('True to size'), findsOneWidget);
    expect(find.text('EU 42'), findsOneWidget);
    expect(find.text('10 mm of toe room — true to size'), findsOneWidget);
    expect(
      find.textContaining('width not compared'),
      findsOneWidget,
      reason: 'the live reading has no width, and the card must not imply one',
    );
  });

  testWidgets('the reading is live and the card says so, not "saved"',
      (tester) async {
    await tester.pumpWidget(wrap(card()));

    expect(
      find.text('Live fit — measured from your foot in view'),
      findsOneWidget,
    );
    expect(
      find.text('Based on your saved foot measurements'),
      findsNothing,
      reason: 'the product-page card owns that sentence; this surface grades '
          'the foot in the frame',
    );
  });

  testWidgets('the tone follows the band', (tester) async {
    await tester.pumpWidget(wrap(card()));
    expect(toneOf(tester), GlassTone.success);

    await tester.pumpWidget(wrap(card(lengthMm: 270)));
    expect(toneOf(tester), GlassTone.warning);

    await tester.pumpWidget(wrap(card(lengthMm: 280)));
    expect(toneOf(tester), GlassTone.error);
  });

  testWidgets('a reading that is not confident asks for a better one',
      (tester) async {
    await tester.pumpWidget(wrap(card(quality: 0.7)));

    expect(find.byKey(const ValueKey('try-on-fit-nudge')), findsOneWidget);
    expect(find.text('Scan a bit closer for a better verdict'), findsOneWidget);
    expect(find.byKey(const ValueKey('try-on-fit-verdict')), findsNothing,
        reason: 'the hint and the answer must never be on screen together');
  });

  testWidgets('every state fits a 320 px screen at 1.6× text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The target band, an off band, a wrong band and the nudge — the four
    // shapes with different sentence counts.
    for (final live in <TryOnFitCard>[
      card(),
      card(lengthMm: 270),
      card(lengthMm: 280),
      card(quality: 0.7),
    ]) {
      await tester.pumpWidget(
        wrap(live, textScaler: const TextScaler.linear(1.6)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '${live.live} must fit without overflow');
    }
  });
}
