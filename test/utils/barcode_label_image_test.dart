import 'package:app/utils/barcode_label_image.dart';
import 'package:app/utils/in_store_barcode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('renderBarcodeLabelPng', () {
    test('renders a real PNG for a valid in-store code', () async {
      final png = await renderBarcodeLabelPng(
        productName: 'Woven Fringe Mules',
        code: generateInStoreBarcode(storeSeed: '0001'),
      );

      expect(png.isNotEmpty, isTrue);
      // PNG magic bytes — what Messenger and friends sniff to accept the file.
      expect(
        png.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
    });

    test('refuses to render a broken code as a wrong symbol', () async {
      await expectLater(
        renderBarcodeLabelPng(productName: 'Loafer', code: 'not-a-barcode'),
        throwsArgumentError,
      );
    });
  });
}
