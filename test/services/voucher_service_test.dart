import 'package:app/services/voucher_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoucherQuote.fromJson', () {
    test('parses an applied quote and its money lines', () {
      final quote = VoucherQuote.fromJson({
        'ok': true,
        'reason': 'ok',
        'message': 'Voucher applied.',
        'code': 'ANQUI10',
        'store_id': 'store-1',
        'subtotal': 1000,
        'delivery_fee': 100,
        'discount_amount': 100.0,
        'total': 1000.0,
      });

      expect(quote.ok, isTrue);
      expect(quote.reason, VoucherReason.ok);
      expect(quote.code, 'ANQUI10');
      expect(quote.storeId, 'store-1');
      expect(quote.subtotal, 1000.0);
      expect(quote.deliveryFee, 100.0);
      expect(quote.discountAmount, 100.0);
      expect(quote.total, 1000.0);
      expect(quote.hasDiscount, isTrue);
    });

    test('coerces numeric fields that arrive as strings or ints', () {
      final quote = VoucherQuote.fromJson({
        'ok': true,
        'subtotal': '800.50',
        'delivery_fee': 100,
        'discount_amount': '50',
        'total': 850.5,
      });

      expect(quote.subtotal, 800.5);
      expect(quote.deliveryFee, 100.0);
      expect(quote.discountAmount, 50.0);
      expect(quote.total, 850.5);
    });

    test('surfaces the server reason and message on rejection', () {
      final quote = VoucherQuote.fromJson({
        'ok': false,
        'reason': 'below_minimum',
        'message': 'Spend at least ₱1,000.00 to use that code.',
        'code': 'ANQUI10',
        'subtotal': 400,
        'delivery_fee': 100,
        'discount_amount': 0,
        'total': 500,
      });

      expect(quote.ok, isFalse);
      expect(quote.reason, VoucherReason.belowMinimum);
      expect(quote.message, contains('Spend at least'));
      expect(quote.hasDiscount, isFalse);
    });

    test('a zero discount never counts as applied', () {
      final quote = VoucherQuote.fromJson({
        'ok': true,
        'reason': 'ok',
        'discount_amount': 0,
      });

      expect(quote.hasDiscount, isFalse);
    });

    test('tolerates an empty payload', () {
      final quote = VoucherQuote.fromJson(const {});

      expect(quote.ok, isFalse);
      expect(quote.reason, VoucherReason.invalidCode);
      expect(quote.message, isEmpty);
      expect(quote.discountAmount, 0);
      expect(quote.hasDiscount, isFalse);
    });

    test('failure() builds the offline/unreachable state', () {
      final quote = VoucherQuote.failure(
        VoucherReason.invalidCode,
        'We could not check that code.',
      );

      expect(quote.ok, isFalse);
      expect(quote.message, 'We could not check that code.');
    });
  });

  group('VoucherReason', () {
    test('mirrors every reason the server can return', () {
      // Keep these in sync with public.voucher_evaluate (migration
      // 20260915130000) — a missing entry means the UI cannot tell the
      // customer why their code failed.
      expect(VoucherReason.ok, 'ok');
      expect(VoucherReason.invalidCode, 'invalid_code');
      expect(VoucherReason.inactive, 'inactive');
      expect(VoucherReason.notStarted, 'not_started');
      expect(VoucherReason.expired, 'expired');
      expect(VoucherReason.maxUsesReached, 'max_uses_reached');
      expect(VoucherReason.perUserLimitReached, 'per_user_limit_reached');
      expect(VoucherReason.belowMinimum, 'below_minimum');
      expect(VoucherReason.wrongStore, 'wrong_store');
      expect(VoucherReason.emptyCart, 'empty_cart');
    });

    test('the fatal set is the "never work for this customer" reasons', () {
      expect(VoucherReason.fatal, contains(VoucherReason.invalidCode));
      expect(VoucherReason.fatal, contains(VoucherReason.expired));
      expect(VoucherReason.fatal, contains(VoucherReason.perUserLimitReached));
      // A below-minimum code becomes valid once the cart grows bigger, so it
      // is a correctable failure rather than a dead end.
      expect(VoucherReason.fatal, isNot(contains(VoucherReason.belowMinimum)));
      expect(VoucherReason.fatal, isNot(contains(VoucherReason.emptyCart)));
      expect(VoucherReason.fatal, isNot(contains(VoucherReason.ok)));
    });
  });
}
