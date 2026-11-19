import 'package:app/utils/pos_receipt_email.dart';
import 'package:flutter_test/flutter_test.dart';

/// The email is the customer's only copy once they walk out, so it has to
/// carry the same facts as the printed receipt — the code they will be asked
/// for, every item, and what was actually paid.
void main() {
  Map<String, dynamic> cashSale() => {
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
      };

  test('the subject names the receipt code and the store', () {
    final mail = buildPosReceiptEmail(
      order: cashSale(),
      storeName: 'CUFMAI Flagship',
    );

    expect(mail.subject, 'Receipt #16C13EA7 from CUFMAI Flagship');
  });

  test('the body carries the store, code, cashier and every line item', () {
    final mail = buildPosReceiptEmail(
      order: cashSale(),
      storeName: 'CUFMAI Flagship',
      storeLocation: 'Level 2, Ayala Center Cebu',
      sellerName: 'Keith Vincent D. Abalo',
    );

    expect(mail.body, contains('CUFMAI Flagship'));
    expect(mail.body, contains('Level 2, Ayala Center Cebu'));
    expect(mail.body, contains('SALES RECEIPT · #16C13EA7'));
    expect(mail.body, contains('Cashier: Keith Vincent D. Abalo'));
    expect(
      mail.body,
      contains(
        '2 × PrimeStep Trail Stitch Sandals (Size 9) — ₱1,200.00',
      ),
    );
    expect(
      mail.body,
      contains('1 × Velux Classic Leather Sandals (Size 8) — ₱1,350.00'),
    );
    expect(mail.body, contains('TOTAL: ₱2,550.00'));
    expect(mail.body, contains('Paid via: Cash'));
    expect(mail.body, contains('Cash tendered: ₱3,000.00'));
    expect(mail.body, contains('Change: ₱450.00'));
    expect(mail.body, contains('quote receipt #16C13EA7'));
  });

  test('a GCash sale shows the reference and no cash lines', () {
    final mail = buildPosReceiptEmail(
      order: {
        'id': 'abcdef12-0000-0000-0000-000000000000',
        'total_amount': 500,
        'payment_method': 'gcash',
        'gcash_reference_number': '0011223344556',
        'order_items': [
          {'product_name': 'EcoStride Double Strap Sandals', 'size': '7'},
        ],
      },
      storeName: 'CUFMAI Flagship',
    );

    expect(mail.body, contains('Paid via: GCash'));
    expect(mail.body, contains('GCash ref: 0011223344556'));
    expect(mail.body, isNot(contains('Cash tendered')));
    expect(mail.body, isNot(contains('Change:')));
  });

  test('a sale with no readable items still reads as a receipt', () {
    final mail = buildPosReceiptEmail(
      order: {'id': 'no-items', 'total_amount': 0},
      storeName: '',
    );

    expect(mail.subject, 'Receipt #NO-ITEMS from Store');
    expect(mail.body, contains('(no line items recorded)'));
    expect(mail.body, contains('TOTAL: ₱0.00'));
  });
}
