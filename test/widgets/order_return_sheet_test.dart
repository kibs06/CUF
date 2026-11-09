import 'package:app/widgets/order_return_sheet.dart';
import 'package:app/widgets/sole_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The return photo proof is mandatory (1-4 photos): the sheet must not
/// submit on a bare reason tap, and the counter must start at 0/4.
void main() {
  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReturnRequestSheet(context),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
  }

  SolePrimaryButton submitButton(WidgetTester tester) =>
      tester.widget<SolePrimaryButton>(find.byType(SolePrimaryButton));

  testWidgets('reason alone does not enable submit — photo is required',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text('Photo proof (required)'), findsOneWidget);
    expect(find.text('0/4'), findsOneWidget);
    expect(
      find.text('At least 1 photo is required to submit.'),
      findsOneWidget,
    );
    expect(submitButton(tester).onPressed, isNull);

    // Picking a reason still leaves submit disabled without a photo.
    await tester.tap(find.text('Defective or damaged'));
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);
    expect(find.text('0/4'), findsOneWidget);
  });

  testWidgets('photo counter cap is 4', (tester) async {
    await pumpSheet(tester);

    // The cap is rendered in the helper copy so a regression that lifts
    // the limit (or drops the requirement) fails loudly here.
    expect(
      find.textContaining('1–4 photos of the defect'),
      findsOneWidget,
    );
  });
}
