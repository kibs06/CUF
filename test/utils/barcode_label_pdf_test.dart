import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/barcode_label_pdf.dart';

void main() {
  test('builds a non-empty label PDF for a valid in-store code', () async {
    final bytes = await buildBarcodeLabelPdf(
      productName: 'Artisan Penny Loafer',
      barcode: '2001234567893',
    );

    expect(bytes, isNotEmpty);
    // A PDF file always opens with the %PDF- magic bytes.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('falls back to a placeholder name when the product is unnamed',
      () async {
    final bytes = await buildBarcodeLabelPdf(
      productName: '   ',
      barcode: '2001234567893',
    );

    expect(bytes, isNotEmpty);
  });

  test('refuses to build a label for an invalid code', () async {
    await expectLater(
      buildBarcodeLabelPdf(productName: 'Loafer', barcode: 'not-a-barcode'),
      throwsArgumentError,
    );
  });
}
