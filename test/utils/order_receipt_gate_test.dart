import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/order_receipt_gate.dart';

void main() {
  group('orderReceiptEmail', () {
    test('prefers the address the till recorded for the sale', () {
      final order = {
        'customer_email': 'till@example.com',
        'profiles': {'email': 'account@example.com'},
      };
      expect(orderReceiptEmail(order), 'till@example.com');
    });

    test('falls back to the customer account email', () {
      final order = {
        'profiles': {'email': 'account@example.com'},
      };
      expect(orderReceiptEmail(order), 'account@example.com');
    });

    test('is null when there is no address at all', () {
      expect(orderReceiptEmail({'profiles': null}), isNull);
      expect(orderReceiptEmail(const {}), isNull);
      expect(orderReceiptEmail({'customer_email': '   '}), isNull);
    });
  });

  group('orderNeedsReceiptBeforeDelivery', () {
    final readyWithEmail = <String, dynamic>{
      'receipt_emailed_at': null,
      'profiles': {'email': 'account@example.com'},
    };

    test('blocks a ready order whose receipt has not gone out', () {
      expect(orderNeedsReceiptBeforeDelivery(readyWithEmail, 'ready'), isTrue);
    });

    test('allows it once the stamp is written', () {
      final sent = {
        ...readyWithEmail,
        'receipt_emailed_at': '2026-11-19T06:00:00Z',
      };
      expect(orderNeedsReceiptBeforeDelivery(sent, 'ready'), isFalse);
    });

    test('only guards the ready stage', () {
      expect(
        orderNeedsReceiptBeforeDelivery(readyWithEmail, 'pending'),
        isFalse,
      );
      expect(
        orderNeedsReceiptBeforeDelivery(readyWithEmail, 'preparing'),
        isFalse,
      );
    });

    test('does not block a guest order with no address on file', () {
      final guest = <String, dynamic>{'receipt_emailed_at': null};
      expect(orderNeedsReceiptBeforeDelivery(guest, 'ready'), isFalse);
    });

    test('does not block a server without the receipt columns', () {
      final old = <String, dynamic>{
        'profiles': {'email': 'account@example.com'},
      };
      expect(orderNeedsReceiptBeforeDelivery(old, 'ready'), isFalse);
    });
  });
}
