import 'package:flutter_test/flutter_test.dart';

import 'package:app/providers/order_provider.dart';

/// Tests for the My Orders tab filter predicates and per-tab counts.
///
/// These pure functions power both the tab list filtering and the Profile
/// "My Orders" panel badge counts, so they must stay in sync with each other
/// (see [matchesMyOrdersFilter] / [computeMyOrdersCounts]). Like
/// cart_provider_test, we test the pure computation in isolation rather than
/// instantiating OrderProvider (which touches Supabase).

Map<String, dynamic> order({
  String? status,
  String? paymentStatus,
}) {
  return {
    'status': status,
    'payment_status': paymentStatus,
  };
}

void main() {
  group('matchesMyOrdersFilter', () {
    test('unpaid: payment_status unpaid and not cancelled', () {
      expect(
        matchesMyOrdersFilter(
          order(status: 'pending', paymentStatus: 'unpaid'),
          'unpaid',
        ),
        isTrue,
      );
      expect(
        matchesMyOrdersFilter(
          order(status: 'cancelled', paymentStatus: 'unpaid'),
          'unpaid',
        ),
        isFalse,
      );
      expect(
        matchesMyOrdersFilter(
          order(status: 'pending', paymentStatus: 'paid'),
          'unpaid',
        ),
        isFalse,
      );
    });

    test('processing: pending, placed, or preparing', () {
      for (final status in ['pending', 'placed', 'preparing']) {
        expect(
          matchesMyOrdersFilter(order(status: status), 'processing'),
          isTrue,
          reason: '$status should be in Processing',
        );
      }
      expect(
        matchesMyOrdersFilter(order(status: 'ready'), 'processing'),
        isFalse,
      );
      expect(
        matchesMyOrdersFilter(order(status: 'delivered'), 'processing'),
        isFalse,
      );
    });

    test('shipped: ready only', () {
      expect(
        matchesMyOrdersFilter(order(status: 'ready'), 'shipped'),
        isTrue,
      );
      expect(
        matchesMyOrdersFilter(order(status: 'preparing'), 'shipped'),
        isFalse,
      );
    });

    test('review: received only', () {
      expect(
        matchesMyOrdersFilter(order(status: 'received'), 'review'),
        isTrue,
      );
      // delivered requires the customer to confirm receipt first
      expect(
        matchesMyOrdersFilter(order(status: 'delivered'), 'review'),
        isFalse,
      );
    });

    test('returns: cancelled only', () {
      expect(
        matchesMyOrdersFilter(order(status: 'cancelled'), 'returns'),
        isTrue,
      );
      expect(
        matchesMyOrdersFilter(order(status: 'received'), 'returns'),
        isFalse,
      );
    });

    test('all matches every order (even delivered/cancellation_requested)', () {
      for (final status in [
        'pending',
        'preparing',
        'ready',
        'delivered',
        'received',
        'cancelled',
        'cancellation_requested',
        'unknown_status',
      ]) {
        expect(
          matchesMyOrdersFilter(order(status: status), 'all'),
          isTrue,
          reason: '$status should be in All orders',
        );
      }
    });

    test('status and payment_status are matched case-insensitively', () {
      expect(
        matchesMyOrdersFilter(
          order(status: 'PENDING', paymentStatus: 'UNPAID'),
          'unpaid',
        ),
        isTrue,
      );
      expect(
        matchesMyOrdersFilter(
          order(status: 'READY', paymentStatus: 'PAID'),
          'shipped',
        ),
        isTrue,
      );
    });

    test('null status/payment_status never match a named tab', () {
      expect(matchesMyOrdersFilter(order(), 'unpaid'), isFalse);
      expect(matchesMyOrdersFilter(order(), 'processing'), isFalse);
      expect(matchesMyOrdersFilter(order(), 'shipped'), isFalse);
      expect(matchesMyOrdersFilter(order(), 'review'), isFalse);
      expect(matchesMyOrdersFilter(order(), 'returns'), isFalse);
      expect(matchesMyOrdersFilter(order(), 'all'), isTrue);
    });
  });

  group('computeMyOrdersCounts', () {
    test('counts every order in exactly the right tab(s)', () {
      final orders = [
        order(status: 'pending', paymentStatus: 'unpaid'), // unpaid + processing
        order(status: 'preparing', paymentStatus: 'paid'), // processing
        order(status: 'placed', paymentStatus: 'paid'), // processing
        order(status: 'ready', paymentStatus: 'paid'), // shipped
        order(status: 'received', paymentStatus: 'paid'), // review
        order(status: 'cancelled', paymentStatus: 'unpaid'), // returns (NOT unpaid)
        order(status: 'delivered', paymentStatus: 'paid'), // all only
        order(status: 'cancellation_requested', paymentStatus: 'paid'), // all only
      ];

      final counts = computeMyOrdersCounts(orders);

      expect(counts['all'], 8);
      expect(counts['unpaid'], 1);
      expect(counts['processing'], 3);
      expect(counts['shipped'], 1);
      expect(counts['review'], 1);
      expect(counts['returns'], 1);
    });

    test('paid delivered orders do not inflate any named tab', () {
      final counts = computeMyOrdersCounts([
        order(status: 'delivered', paymentStatus: 'paid'),
        order(status: 'delivered', paymentStatus: 'paid'),
      ]);

      // delivered has no home tab of its own (customer must confirm receipt)
      expect(counts['all'], 2);
      expect(counts['unpaid'], 0);
      expect(counts['processing'], 0);
      expect(counts['shipped'], 0);
      expect(counts['review'], 0);
      expect(counts['returns'], 0);
    });

    test('delivered-but-unpaid still counts as Unpaid (matches tab predicate)',
        () {
      final counts = computeMyOrdersCounts([
        order(status: 'delivered', paymentStatus: 'unpaid'),
      ]);

      expect(counts['all'], 1);
      expect(counts['unpaid'], 1);
      expect(counts['processing'], 0);
      expect(counts['shipped'], 0);
      expect(counts['review'], 0);
      expect(counts['returns'], 0);
    });

    test('empty list yields all-zero counts', () {
      final counts = computeMyOrdersCounts([]);

      expect(counts, {
        'all': 0,
        'unpaid': 0,
        'processing': 0,
        'shipped': 0,
        'review': 0,
        'returns': 0,
      });
    });

    test('returns map contains every tab key', () {
      final counts = computeMyOrdersCounts([]);
      expect(counts.keys.toSet(), myOrdersFilterKeys.toSet());
    });
  });
}
