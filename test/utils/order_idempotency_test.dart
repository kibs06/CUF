import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/utils/order_idempotency.dart';

// The decision the order service makes when an insert fails. Getting it wrong
// is expensive in both directions: a false negative places a duplicate order,
// a false positive swallows a real stock or GCash error and tells the customer
// their order went through.
void main() {
  group('isOrderIdempotencyConflict', () {
    test('accepts the checkout-key index with a 23505', () {
      expect(
        isOrderIdempotencyConflict(
          const PostgrestException(
            message:
                'duplicate key value violates unique constraint '
                '"uq_orders_customer_idempotency_key"',
            code: '23505',
          ),
        ),
        isTrue,
      );
    });

    test('finds the index when Postgres puts it in details instead', () {
      expect(
        isOrderIdempotencyConflict(
          const PostgrestException(
            message: 'duplicate key value violates unique constraint',
            code: '23505',
            details: 'Key (customer_id, idempotency_key)='
                '(f100…, key-cash-a-0001) already exists.',
            hint: 'uq_orders_customer_idempotency_key',
          ),
        ),
        isTrue,
      );
    });

    test('rejects a different 23505 — the GCash one-open-checkout cap', () {
      expect(
        isOrderIdempotencyConflict(
          const PostgrestException(
            message:
                'duplicate key value violates unique constraint '
                '"uq_orders_one_awaiting_payment_confirmation_per_customer"',
            code: '23505',
          ),
        ),
        isFalse,
      );
    });

    test('rejects a stock or RLS failure', () {
      expect(
        isOrderIdempotencyConflict(
          const PostgrestException(
            message: 'insufficient stock for size 40',
            code: 'P0001',
          ),
        ),
        isFalse,
      );
      expect(
        isOrderIdempotencyConflict(
          const PostgrestException(message: 'permission denied', code: '42501'),
        ),
        isFalse,
      );
    });

    test('rejects anything that is not a Postgrest error', () {
      expect(isOrderIdempotencyConflict(null), isFalse);
      expect(isOrderIdempotencyConflict(Exception('timeout')), isFalse);
      expect(isOrderIdempotencyConflict('uq_orders_customer_idempotency_key'),
          isFalse);
    });
  });

  group('newOrderIdempotencyKey', () {
    test('is a UUID that fits the column constraint', () {
      final key = newOrderIdempotencyKey();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                r'[0-9a-f]{12}$')
            .hasMatch(key),
        isTrue,
        reason: 'the migration allows 8–64 chars; a v4 UUID must land in it',
      );
      expect(key.length, greaterThanOrEqualTo(8));
      expect(key.length, lessThanOrEqualTo(64));
    });

    test('does not repeat, so two checkouts are two orders', () {
      final keys = List.generate(50, (_) => newOrderIdempotencyKey()).toSet();
      expect(keys, hasLength(50));
    });
  });
}
