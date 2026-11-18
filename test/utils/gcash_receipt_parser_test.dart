import 'package:app/utils/gcash_receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GcashReceiptParser.parse — a real send receipt', () {
    test('reads the Ref No. and the amount sent', () {
      const lines = [
        'GCash',
        'Sent Money',
        'Amount Sent',
        'PHP 650.00',
        'Send Money to KEITH VINCENT D. ABALO',
        'Ref No. 4043 676 687260',
        'Nov 17, 2026 07:41 AM',
      ];
      final parsed = GcashReceiptParser.parse(lines);
      expect(parsed.reference.reference, '4043676687260');
      expect(parsed.amount, 650.00);
      expect(parsed.amountLine, 'PHP 650.00');
      expect(parsed.isEmpty, isFalse);
    });

    test('handles thousands separators and a peso sign', () {
      final parsed = GcashReceiptParser.parse(const [
        'Amount Sent',
        '₱1,250.00',
        'Ref No. 1234567890123',
      ]);
      expect(parsed.amount, 1250.00);
    });

    test('"Amount Sent" beats a balance and a fee on the same receipt', () {
      final parsed = GcashReceiptParser.parse(const [
        'Available Balance',
        '₱9,999.00',
        'Service Fee',
        '₱15.00',
        'Amount Sent',
        '₱650.00',
      ]);
      expect(parsed.amount, 650.00);
    });

    test('a bare figure on its own line is read as the amount', () {
      final parsed = GcashReceiptParser.parse(const [
        'You sent',
        '₱300.00',
      ]);
      expect(parsed.amount, 300.00);
    });
  });

  group('GcashReceiptParser.parse — what it must not do', () {
    test('never treats the reference number as the amount', () {
      final parsed = GcashReceiptParser.parse(const [
        'Ref No. 4043 676 687260',
        'Amount Sent 650.00',
      ]);
      // The 13-digit ref carries no decimals, so it can never satisfy the
      // money pattern; the transfer figure beside it does.
      expect(parsed.reference.reference, '4043676687260');
      expect(parsed.amount, 650.00);
    });

    test('a 4-digit whole part is read whole, not truncated', () {
      final parsed = GcashReceiptParser.parse(const [
        'Amount Sent',
        '₱4043.67',
      ]);
      expect(parsed.amount, 4043.67);
    });

    test('a reference label above a figure does not hide that figure', () {
      final parsed = GcashReceiptParser.parse(const [
        'Ref No. 4043 676 687260',
        '₱650.00',
      ]);
      expect(parsed.reference.reference, '4043676687260');
      expect(parsed.amount, 650.00);
    });

    test('a receipt with no money figure leaves the amount null', () {
      final parsed = GcashReceiptParser.parse(const [
        'Ref No. 4043 676 687260',
        'Transaction complete',
      ]);
      expect(parsed.reference.reference, '4043676687260');
      expect(parsed.amount, isNull);
      expect(parsed.isEmpty, isFalse);
    });

    test('a balance-only line is ignored when nothing else reads as money', () {
      final parsed = GcashReceiptParser.parse(const [
        'Available Balance ₱2,000.00',
      ]);
      expect(parsed.amount, isNull);
      expect(parsed.isEmpty, isTrue);
    });

    test('unreadable text yields an empty parse', () {
      final parsed = GcashReceiptParser.parse(const ['', '   ', 'Thanks']);
      expect(parsed.isEmpty, isTrue);
      expect(parsed.amount, isNull);
      expect(parsed.reference.detected, isFalse);
    });
  });
}
