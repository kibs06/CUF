import 'package:app/utils/pos_receipt_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// The receipt is the thing the customer takes home, so the builder has to
/// survive the worst row the POS can hand it — two line items, a quantity, a
/// cash tender with change, and a store name with an em dash — and still come
/// back as a real PDF. Layout errors inside `pdf` throw at build time, which
/// is exactly what this catches.
void main() {
  test('a cash sale with change renders a PDF receipt', () async {
    final bytes = await buildPosReceiptPdf(
      order: {
        'id': '16c13ea7-1234-5678-9abc-def012345678',
        'created_at': '2026-11-19T08:12:00Z',
        'total_amount': 2550.0,
        'payment_method': 'Cash',
        'amount_tendered': 3000.0,
        'change_amount': 450.0,
        'order_items': [
          {
            'product_name': 'PrimeStep Trail Stitch Sandals',
            'size': '9',
            'quantity': 2,
            'unit_price': 600.0,
          },
          {
            'product_name': 'Velux Classic Leather Sandals',
            'size': '8',
            'quantity': 1,
            'unit_price': 1350.0,
          },
        ],
      },
      storeName: 'CUFMAI Flagship — Ayala Center Cebu',
      storeLocation: 'Level 2, Ayala Center Cebu',
      sellerName: 'Keith Vincent D. Abalo',
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  test('a GCash sale with a reference renders, and so does an empty one',
      () async {
    final gcash = await buildPosReceiptPdf(
      order: {
        'id': 'short',
        'total_amount': 500,
        'payment_method': 'gcash',
        'gcash_reference_number': '0011223344556',
        'order_items': [
          {'product_name': 'EcoStride Double Strap Sandals', 'size': '7'},
        ],
      },
      storeName: 'CUFMAI Flagship',
    );
    expect(gcash.length, greaterThan(2000));

    // A sale whose items could not be read must still print something a
    // cashier can hand over, not an exception on the print button.
    final empty = await buildPosReceiptPdf(
      order: {'id': 'no-items', 'total_amount': 0},
      storeName: '',
    );
    expect(String.fromCharCodes(empty.take(5)), '%PDF-');
  });
}
