import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheel_picker/wheel_picker.dart';

import 'package:app/widgets/foot_size_picker.dart';
import 'package:app/widgets/sole_primary_button.dart';

/// The manual foot-size picker panel, now a 2-step wizard: scale cards
/// first, then the size wheel.
///
/// It must never hand back a size or a shopping scale the customer did not
/// choose: EU 42 is unisex, but the scale decides whether that EU size reads
/// as US 9 (men) or US 10.5 (women), so a guessed scale mislabels the size.
/// Touching the wheel IS picking; mounting it never commits.
void main() {
  FootSizeSelection? saved;

  setUp(() => saved = null);

  Future<void> pumpPanel(
    WidgetTester tester, {
    double? initialEuSize,
    String? initialWidth,
    String? initialCategory,
    bool isSaving = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FootSizePickerPanel(
            initialEuSize: initialEuSize,
            initialWidth: initialWidth,
            initialCategory: initialCategory,
            isSaving: isSaving,
            onSave: (selection) => saved = selection,
          ),
        ),
      ),
    );
    // pump (not pumpAndSettle): the saving state shows a spinner, which
    // never settles.
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    // The size step scrolls on small screens: bring the CTA into view.
    await tester.scrollUntilVisible(find.text('Save my size'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save my size'));
    await tester.pump();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<SolePrimaryButton>(find.byType(SolePrimaryButton))
          .onPressed !=
      null;

  /// Picks a scale card and waits for the confirmation + step transition.
  Future<void> pickScale(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Taps the wheel entry just below centre: one step up the band.
  Future<void> tapWheelUp(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Reads the committed size back out of the live summary
  /// ('EU 18 - Regular - Kids' with middots -> 18). The summary is the
  /// only widget joining the size with a middot, so it stays unique.
  double wheelSummarySize(WidgetTester tester) {
    final summary = tester.widget<Text>(find.textContaining('\u00b7')).data!;
    return double.parse(summary.split(' ')[1]);
  }

  testWidgets('the first step is the scale cards, with no save yet',
      (tester) async {
    await pumpPanel(tester);

    expect(find.text('Who are you shopping for?'), findsOneWidget);
    expect(find.text("Men's"), findsOneWidget);
    expect(find.text("Women's"), findsOneWidget);
    expect(find.text("Kids'"), findsNothing);
    // Step 1 owns the CTA; nothing can be saved from the cards.
    expect(find.byType(SolePrimaryButton), findsNothing);
    expect(saved, isNull);
  });

  testWidgets('picking a scale advances to the size wheel', (tester) async {
    await pumpPanel(tester);

    await pickScale(tester, "Men's");

    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Spin the wheel to your size'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    expect(saved, isNull);
  });

  testWidgets(
      'an unrecognised saved scale is not inherited, but a valid size is kept',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'unisex');

    // The scale does not silently fall back to Men's.
    expect(find.text('Who are you shopping for?'), findsOneWidget);
    expect(find.byType(SolePrimaryButton), findsNothing);

    await pickScale(tester, "Women's");

    // 42 is a valid adult size, so it survives; only the scale was missing.
    expect(saveEnabled(tester), isTrue);
    await tapSave(tester);
    expect(saved?.euSize, 42);
    expect(saved?.sizeCategory, 'women');
  });

  testWidgets('the saved size, scale and width open on the wheel',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    // Straight to step 2, wheel centred on the saved size.
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('42'), findsWidgets);

    await tapSave(tester);

    expect(saved?.euSize, 42);
    expect(saved?.widthLabel, 'Regular');
    expect(saved?.sizeCategory, 'men');
  });

  testWidgets('touching the wheel picks a size and enables save',
      (tester) async {
    await pumpPanel(tester, initialCategory: 'men');

    expect(saveEnabled(tester), isFalse);

    // The fresh wheel rests mid-band (32); the neighbour commits on tap.
    await tapWheelUp(tester, '32.5');

    expect(
      find.text("EU 32.5 \u00b7 Regular \u00b7 Men's"),
      findsOneWidget,
    );
    expect(saveEnabled(tester), isTrue);
    await tapSave(tester);

    expect(saved?.euSize, 32.5);
    expect(saved?.sizeCategory, 'men');
  });

  testWidgets('a half size survives as a half size', (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tapWheelUp(tester, '42.5');
    await tapSave(tester);

    expect(saved?.euSize, 42.5);
  });

  testWidgets('picking a width returns it with the size', (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tester.tap(find.text('Wide'));
    await tester.pump();
    await tapSave(tester);

    expect(saved?.euSize, 42);
    expect(saved?.widthLabel, 'Wide');
    expect(saved?.sizeCategory, 'men');
  });

  testWidgets('the size can be entered in US, but the pick stays EU',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tester.tap(find.text('US'));
    await tester.pump();

    // EU 42 is US 9 on the men's chart, and the EU value is no longer
    // shown on the wheel - one list, relabelled. The summary still
    // names the EU truth, and the pick survives as EU 42.
    expect(find.text('9'), findsWidgets);
    expect(
      find.text("EU 42 \u00b7 Regular \u00b7 Men's"),
      findsOneWidget,
    );

    await tapSave(tester);
    expect(saved?.euSize, 42);
  });

  testWidgets('sizes below the adult band stay in EU even in US mode',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 36, initialCategory: 'men');

    await tester.tap(find.text('US'));
    await tester.pump();
    // EU 36 is US 3 on the men's chart.
    expect(find.text('3'), findsWidgets);

    // Step down twice on the labelled wheel: 35.5 -> US 2.5, 35 -> US 2.
    await tester.tap(find.text('2.5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    // EU 34.5 has no US chart: the entry, the readout and the summary all
    // stay in EU, and the unit switcher hides.
    await tester.tap(find.text('34.5'));
    await tester.pumpAndSettle();
    expect(find.text('US'), findsNothing);
    expect(
      find.text("EU 34.5 \u00b7 Regular \u00b7 Men's"),
      findsOneWidget,
    );
    await tapSave(tester);
    expect(saved?.euSize, 34.5);
    expect(saved?.sizeCategory, 'men');
  });

  testWidgets('the US labels follow the shopping scale', (tester) async {
    await pumpPanel(
        tester, initialEuSize: 35, initialCategory: 'women');

    await tester.tap(find.text('US'));
    await tester.pump();

    // EU 35 is US 3.5 for a woman and US 2 on the men's chart.
    expect(find.text('3.5'), findsWidgets);

    await tapSave(tester);

    expect(saved?.euSize, 35);
    expect(saved?.sizeCategory, 'women');
  });

  testWidgets('going back and switching scale keeps the size', (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await pickScale(tester, "Women's");

    // Same EU, new scale: the US label would now read 10.5.
    await tester.tap(find.text('US'));
    await tester.pump();
    expect(find.text('10.5'), findsWidgets);
    expect(
      find.text("EU 42 \u00b7 Regular \u00b7 Women's"),
      findsOneWidget,
    );

    await tapSave(tester);
    expect(saved?.euSize, 42);
    expect(saved?.sizeCategory, 'women');
  });

  testWidgets("a legacy kids' save keeps its band, with no unit switch",
      (tester) async {
    await pumpPanel(tester, initialEuSize: 23, initialCategory: 'kids');

    // Opens on the size step with the children's band and a way back.
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('US'), findsNothing);
    expect(find.text('UK'), findsNothing);
    expect(find.text('23'), findsWidgets);
    await tapSave(tester);
    expect(saved?.euSize, 23);
    expect(saved?.sizeCategory, 'kids');

    // Switching to an adult scale drops the kids-only size: 23 is not
    // offered at 35+, so it must not survive behind an enabled Save.
    // (The save CTA scrolled the step down; bring Back into view first.)
    await tester.scrollUntilVisible(find.text('Back'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await pickScale(tester, "Men's");

    expect(find.text('Spin the wheel to your size'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('picking from the US wheel stores the EU size',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tester.tap(find.text('US'));
    await tester.pump();

    // The wheel rests on EU 42 (US 9); the neighbour below centre reads
    // US 9.5 (EU 42.5 on the men's chart). Tapping the label must store EU.
    await tapWheelUp(tester, '9.5');

    expect(
      find.text("EU 42.5 \u00b7 Regular \u00b7 Men's"),
      findsOneWidget,
    );
    await tapSave(tester);
    expect(saved?.euSize, 42.5);
  });

  testWidgets('a kids size the adult band shares survives the switch',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 35, initialCategory: 'kids');

    await tapSave(tester);
    expect(saved?.euSize, 35);
    expect(saved?.sizeCategory, 'kids');

    // 35 sits in both bands, so switching scale keeps the pick armed.
    await tester.scrollUntilVisible(find.text('Back'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await pickScale(tester, "Men's");

    expect(saveEnabled(tester), isTrue);
    await tapSave(tester);
    expect(saved?.euSize, 35);
    expect(saved?.sizeCategory, 'men');
  });

  testWidgets('an unrecognised saved width falls back to Regular, not Narrow',
      (tester) async {
    await pumpPanel(
      tester,
      initialEuSize: 40,
      initialWidth: 'Extra-wide',
      initialCategory: 'men',
    );

    await tapSave(tester);

    expect(saved?.widthLabel, 'Regular');
  });

  testWidgets('the disabled save says what is missing, then confirms',
      (tester) async {
    await pumpPanel(tester);

    await pickScale(tester, "Women's");
    expect(
      find.text('Choose a size to continue.'),
      findsOneWidget,
    );

    await tapWheelUp(tester, '32.5');

    expect(
      find.text('Choose a size to continue.'),
      findsNothing,
    );
    expect(
      find.text("EU 32.5 \u00b7 Regular \u00b7 Women's"),
      findsOneWidget,
    );
  });

  testWidgets('spinning below EU 20 auto-saves to Kids and back restores',
      (tester) async {
    await pumpPanel(tester, initialCategory: 'men');

    // Spin down until the wheel drops below EU 20.
    for (var i = 0; i < 40; i++) {
      final armed = find.textContaining('\u00b7').evaluate().isNotEmpty &&
          wheelSummarySize(tester) < 20;
      if (find.text("Kids'").evaluate().isNotEmpty && armed) break;
      await tester.fling(find.byType(WheelPicker), const Offset(0, 500), 3000);
      await tester.pumpAndSettle();
    }
    expect(find.text("Kids'"), findsWidgets);
    expect(wheelSummarySize(tester), lessThan(20));

    // The toddler notice names the rule; US/UK hide; the save is armed.
    expect(find.textContaining('Under EU 20'), findsOneWidget);
    expect(find.text('US'), findsNothing);
    expect(find.text('UK'), findsNothing);
    expect(saveEnabled(tester), isTrue);
    await tapSave(tester);
    expect(saved?.euSize, lessThan(20));
    expect(saved?.sizeCategory, 'kids');

    // Spin back up: the picked scale returns with the size.
    for (var i = 0; i < 40; i++) {
      if (find.text("Men's").evaluate().isNotEmpty) break;
      await tester.fling(
          find.byType(WheelPicker), const Offset(0, -800), 4000);
      await tester.pumpAndSettle();
    }
    expect(find.text("Men's"), findsWidgets);
    await tapSave(tester);
    expect(saved?.sizeCategory, 'men');
    expect(saved?.euSize, greaterThanOrEqualTo(20));
  });

  testWidgets('a save in flight shows a spinner instead of the label',
      (tester) async {
    await pumpPanel(
      tester,
      initialEuSize: 40,
      initialCategory: 'men',
      isSaving: true,
    );

    final button = tester.widget<SolePrimaryButton>(
      find.byType(SolePrimaryButton),
    );
    expect(button.isLoading, isTrue);
    // The label is swapped for the spinner, so the CTA cannot be fired again.
    expect(find.text('Save my size'), findsNothing);
    expect(saved, isNull);
  });

  testWidgets('a saved size at the far end opens on it', (tester) async {
    await pumpPanel(tester, initialEuSize: 48, initialCategory: 'men');
    await tester.pump();
    await tester.pump();

    // EU 48 is the last entry of the adult band: the wheel opens on it.
    expect(
      find.text("EU 48 \u00b7 Regular \u00b7 Men's"),
      findsOneWidget,
    );

    await tapSave(tester);
    expect(saved?.euSize, 48);
  });
}
