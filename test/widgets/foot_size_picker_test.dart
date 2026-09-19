import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/foot_size_picker.dart';
import 'package:app/widgets/sole_primary_button.dart';

/// The manual foot-size picker panel (the manual panel of `SizeYourFootPanel`).
///
/// It must never hand back a size or a shopping scale the customer did not
/// choose: EU 42 is unisex, but the scale decides whether that EU size reads
/// as US 9 (men) or US 10.5 (women), so a guessed scale mislabels the size.
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
    await tester.tap(find.text('Save my size'));
    await tester.pump();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<SolePrimaryButton>(find.byType(SolePrimaryButton))
          .onPressed !=
      null;

  testWidgets('cannot save until something is picked', (tester) async {
    await pumpPanel(tester);

    expect(saveEnabled(tester), isFalse);
    await tapSave(tester);
    expect(saved, isNull);
  });

  testWidgets('a size alone is not enough — the scale must be chosen too',
      (tester) async {
    await pumpPanel(tester);

    // 35 is the first chip, so it is on screen without scrolling.
    await tester.tap(find.text('35'));
    await tester.pump();

    expect(saveEnabled(tester), isFalse);
    expect(saved, isNull);
  });

  testWidgets('the saved size, scale and width are preselected and returned',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tapSave(tester);

    expect(saved?.euSize, 42);
    expect(saved?.widthLabel, 'Regular');
    expect(saved?.sizeCategory, 'men');
  });

  testWidgets('picking a size, a scale and a width returns all three',
      (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');

    await tester.tap(find.text('35'));
    await tester.pump();
    await tester.tap(find.text("Women's"));
    await tester.pump();
    await tester.tap(find.text('Wide'));
    await tester.pump();
    await tapSave(tester);

    expect(saved?.euSize, 35);
    expect(saved?.widthLabel, 'Wide');
    expect(saved?.sizeCategory, 'women');
  });

  testWidgets('an unrecognised saved scale is not inherited', (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'unisex');

    // The row does not silently fall back to Men's.
    expect(saveEnabled(tester), isFalse);

    await tester.tap(find.text("Women's"));
    await tester.pump();

    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('the size can be entered in US, but the pick stays EU',
      (tester) async {
    await pumpPanel(tester, initialCategory: 'men');

    await tester.tap(find.text('35'));
    await tester.pump();
    await tester.tap(find.text('US'));
    await tester.pump();

    // EU 35 is US 2 on the men's chart, and the EU value is no longer shown —
    // one list, relabelled, not a second list.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('35'), findsNothing);

    // Switching the unit is display-only: the pick survives as EU 35.
    await tapSave(tester);
    expect(saved?.euSize, 35);
  });

  testWidgets("the US list follows the shopping scale", (tester) async {
    await pumpPanel(tester, initialCategory: 'women');

    await tester.tap(find.text('US'));
    await tester.pump();

    // EU 35 is US 3.5 for a woman and US 2 on the men's chart.
    expect(find.text('3.5'), findsOneWidget);

    await tester.tap(find.text('3.5'));
    await tester.pump();
    await tapSave(tester);

    expect(saved?.euSize, 35);
    expect(saved?.sizeCategory, 'women');
  });

  testWidgets("Kids' offers the children's band and no unit to choose",
      (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text("Kids'"));
    await tester.pump();

    // No US/UK chart exists for kids, so there is nothing to switch between.
    expect(find.text('US'), findsNothing);
    expect(find.text('UK'), findsNothing);
    // The band starts at 22 — a child's size, not 35.
    expect(find.text('22'), findsOneWidget);

    // 23 is near the start of the band, so it is on screen without scrolling.
    await tester.tap(find.text('23'));
    await tester.pump();
    await tapSave(tester);

    expect(saved?.euSize, 23);
    expect(saved?.sizeCategory, 'kids');
  });

  testWidgets('a pick the new scale does not offer is dropped', (tester) async {
    await pumpPanel(tester, initialEuSize: 42, initialCategory: 'men');
    expect(saveEnabled(tester), isTrue);

    await tester.tap(find.text("Kids'"));
    await tester.pump();

    // EU 42 is not a kids' size and is not on screen any more, so it must not
    // survive as an invisible selection behind an enabled Save.
    expect(find.text('42'), findsNothing);
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('an unrecognised saved width falls back to Regular, not Narrow',
      (tester) async {
    await pumpPanel(tester, initialWidth: 'Extra-wide', initialCategory: 'men');

    await tester.tap(find.text('36'));
    await tester.pump();
    await tapSave(tester);

    expect(saved?.widthLabel, 'Regular');
  });

  testWidgets('a half size survives as a half size', (tester) async {
    await pumpPanel(tester, initialCategory: 'men');

    // 35.5 is the second chip, so it is on screen without scrolling.
    await tester.tap(find.text('35.5'));
    await tester.pump();
    await tapSave(tester);

    expect(saved?.euSize, 35.5);
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
}
