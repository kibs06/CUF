import 'package:app/utils/in_store_barcode.dart';
import 'package:app/widgets/seller/barcode_label_dialog.dart';
import 'package:app/widgets/seller/in_store_barcode_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The label dialog has two states: a valid system EAN-13 shows the scannable
/// preview with working Share/Print, while a legacy seller-entered code shows
/// the repair card with Share and Print disabled — tapping Share must never
/// die silently inside the PNG renderer again.
void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required String code,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeLabelDialog(
            productName: 'Woven Fringe Mules',
            code: code,
            productId: 'product-id',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton shareButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Share'));

  OutlinedButton printButton(WidgetTester tester) => tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Print'));

  group('BarcodeLabelDialog', () {
    testWidgets('a valid code previews with Share and Print enabled',
        (tester) async {
      await pumpDialog(
        tester,
        code: generateInStoreBarcode(storeSeed: 'seed'),
      );

      expect(find.byType(InStoreBarcodeLabel), findsOneWidget);
      expect(find.text('Assign system code'), findsNothing);
      expect(shareButton(tester).onPressed, isNotNull);
      expect(printButton(tester).onPressed, isNotNull);
    });

    testWidgets('a legacy code shows the repair card and parks Share/Print',
        (tester) async {
      await pumpDialog(tester, code: 'MULES-001');

      expect(find.byType(InStoreBarcodeLabel), findsNothing);
      expect(find.text('MULES-001'), findsOneWidget);
      expect(find.text('Assign system code'), findsOneWidget);
      expect(
        shareButton(tester).onPressed,
        isNull,
        reason: 'no valid symbol means nothing to render or send',
      );
      expect(printButton(tester).onPressed, isNull);
      // Copy still works — the digits are real, just not an EAN-13.
      expect(find.widgetWithText(TextButton, 'Copy').evaluate().isNotEmpty,
          isTrue);
    });
  });
}
