import 'package:app/services/reservation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('the seller queue reads the profile column that exists', () {
    // The live schema has `profiles.full_name` and no `profiles.name`, so a
    // `profiles(name)` embed fails the request with 42703 and the queue shows
    // its generic error state instead of the rows the dashboard counted.
    test('parses the customer name from full_name', () {
      final r = BulkReservation.fromJson({
        'id': 'res-9',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 4,
        'status': 'pending',
        'products': {'name': 'Runner'},
        'profiles': {'full_name': 'Ana Cruz'},
      });

      expect(r.customerName, 'Ana Cruz');
      expect(r.productName, 'Runner');
      expect(r.isPending, isTrue);
    });

    test('a missing join leaves the name null, not blank', () {
      // The queue renders `customerName ?? 'A customer'`; an empty string
      // would print an empty line instead.
      final r = BulkReservation.fromJson(const {'id': 'res-10'});

      expect(r.customerName, isNull);
    });
  });

  group('BulkReservation deposit fields', () {
    test('parses deposit columns from a fetched row', () {
      final r = BulkReservation.fromJson({
        'id': 'res-1',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 10,
        'reserved_stock': 0,
        'status': 'awaiting_deposit',
        'deposit_amount': 200.0,
        'deposit_status': 'unpaid',
        'deposit_deadline': '2026-09-14T10:00:00.000Z',
        'created_at': '2026-09-13T09:00:00.000Z',
        'products': {
          'name': 'Dep Product',
          'stores': {'name': 'Dep Store'},
        },
      });

      expect(r.depositAmount, 200.0);
      expect(r.depositStatus, 'unpaid');
      expect(r.depositDeadline, isNotNull);
      expect(r.depositPaidAt, isNull);
      expect(r.isAwaitingDeposit, isTrue);
      expect(r.needsDeposit, isTrue);
      expect(r.statusLabel, 'Deposit needed');
    });

    test('defaults deposit fields for legacy/terminal rows', () {
      final r = BulkReservation.fromJson({
        'id': 'res-2',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 3,
        'reserved_stock': 3,
        'status': 'fulfilled',
        'created_at': '2026-09-01T09:00:00.000Z',
      });

      expect(r.depositAmount, isNull);
      expect(r.depositStatus, 'not_required');
      expect(r.depositDeadline, isNull);
      expect(r.depositPaidAt, isNull);
      expect(r.needsDeposit, isFalse);
      expect(r.isTerminal, isTrue);
      expect(r.statusLabel, 'Fulfilled');
    });

    test('depositExpired is driven by the 24h deadline', () {
      final past = BulkReservation.fromJson({
        'id': 'res-3',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 5,
        'status': 'awaiting_deposit',
        'deposit_status': 'unpaid',
        'deposit_deadline': '2026-01-01T00:00:00.000Z',
      });
      final future = BulkReservation.fromJson({
        'id': 'res-4',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 5,
        'status': 'awaiting_deposit',
        'deposit_status': 'unpaid',
        'deposit_deadline': '2999-01-01T00:00:00.000Z',
      });

      expect(past.depositExpired, isTrue);
      expect(past.needsDeposit, isTrue); // sweep will resolve it server-side
      expect(future.depositExpired, isFalse);
    });

    test('paid hold keeps approved semantics', () {
      final r = BulkReservation.fromJson({
        'id': 'res-5',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 7,
        'reserved_stock': 7,
        'status': 'approved',
        'deposit_status': 'paid',
        'deposit_amount': 140.0,
        'deposit_paid_at': '2026-09-13T11:00:00.000Z',
      });

      expect(r.isApproved, isTrue);
      expect(r.isAwaitingDeposit, isFalse);
      expect(r.needsDeposit, isFalse);
      expect(r.statusLabel, 'Reserved');
    });
  });

  group('voucher on a bulk request', () {
    test('reads the code and the discount the server resolved', () {
      final r = BulkReservation.fromJson({
        'id': 'res-6',
        'customer_id': 'c1',
        'store_id': 's1',
        'product_id': 'p1',
        'quantity': 12,
        'status': 'pending',
        'voucher_code': 'SAVE50',
        'voucher_discount': 50.0,
      });

      expect(r.voucherCode, 'SAVE50');
      expect(r.voucherDiscount, 50.0);
    });

    test('no voucher stays null instead of a zero discount', () {
      final r = BulkReservation.fromJson(const {'id': 'res-7'});

      expect(r.voucherCode, isNull);
      expect(r.voucherDiscount, isNull);
    });
  });

  group('friendlyReservationError — a voucher rejected at request time', () {
    test('tells the customer to remove the code and resend', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "VOUCHER_REJECTED max_uses_reached: That code has been fully claimed.")',
        ),
        contains('Remove it'),
      );
    });
  });

  group('friendlyReservationError — deposit error codes', () {
    // The RPCs RAISE EXCEPTION with stable short codes; the mapper
    // extracts them from the PostgREST error text (quoted token, same
    // convention as the pre-existing reservation codes).
    test('maps DEPOSIT_DEADLINE_PASSED', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "DEPOSIT_DEADLINE_PASSED")',
        ),
        'The 24-hour deposit window for this reservation has closed.',
      );
    });

    test('maps DEPOSIT_PROOF_REQUIRED', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "DEPOSIT_PROOF_REQUIRED")',
        ),
        contains('proof'),
      );
    });

    test('maps DEPOSIT_ALREADY_SUBMITTED', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "DEPOSIT_ALREADY_SUBMITTED")',
        ),
        contains('already'),
      );
    });

    test('maps PROOF_COOLDOWN', () {
      // 20261118120000: the deposit RPC now shares the per-customer proof
      // window with the order flow, so this code has to read as a wait, not
      // as a failure the customer should retry immediately.
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "PROOF_COOLDOWN")',
        ),
        contains('minute'),
      );
    });

    test('maps INVALID_PROOF_REFERENCE', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "INVALID_PROOF_REFERENCE")',
        ),
        contains('12–13 digit'),
      );
    });

    test('maps INVALID_PROOF_SCREENSHOT', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "INVALID_PROOF_SCREENSHOT")',
        ),
        contains('screenshot'),
      );
    });

    test('maps REFERENCE_ALREADY_USED', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "REFERENCE_ALREADY_USED")',
        ),
        contains('already been used'),
      );
    });

    test('still maps the pre-existing codes (no regression)', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "ALREADY_RESOLVED")',
        ),
        'This reservation was already resolved.',
      );
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "RESERVATION_ALREADY_EXISTS")',
        ),
        contains('already have an open reservation'),
      );
    });

    test('INSUFFICIENT_STOCK family stays handled (any suffix)', () {
      expect(
        friendlyReservationError('INSUFFICIENT_STOCK_MISSING_2'),
        contains('Not enough stock'),
      );
    });

    test('unknown codes fall back to the generic message', () {
      expect(
        friendlyReservationError(
          'PostgrestException(code: P0001, message: "SOMETHING_NEW")',
        ),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('bulkReservationDeclinedPushBody', () {
    test('names the quantity and repeats the seller\'s reason', () {
      expect(
        bulkReservationDeclinedPushBody(quantity: 10, reason: 'too many units'),
        'The seller declined your 10-unit reservation request: too many units',
      );
    });

    test('a plain decline (empty reason) still reads as a sentence', () {
      // `decide_bulk_reservation` stores p_rejection_reason verbatim, so a
      // seller who declines without typing anything leaves '' on the row.
      expect(
        bulkReservationDeclinedPushBody(quantity: 3, reason: ''),
        'The seller declined your 3-unit reservation request.',
      );
      expect(
        bulkReservationDeclinedPushBody(quantity: 3),
        'The seller declined your 3-unit reservation request.',
      );
    });

    test('does not double the separator on whitespace-only reasons', () {
      expect(
        bulkReservationDeclinedPushBody(quantity: 1, reason: '   '),
        'The seller declined your 1-unit reservation request.',
      );
    });
  });

  group('bulkReservationDepositDeclinedPushBody', () {
    test('carries the reason, the quantity and the no-stock reassurance', () {
      final body = bulkReservationDepositDeclinedPushBody(
        quantity: 7,
        reason: 'reference does not match the amount',
      );

      expect(
        body,
        'The seller could not verify your deposit payment for the 7-unit '
        'reservation: reference does not match the amount'
        ' No stock was held. If you already sent money, contact the store '
        'directly to resolve it.',
      );
    });

    test('falls back to the RPC\'s own default reason', () {
      // `reject_bulk_reservation_deposit` stores
      // COALESCE(NULLIF(p_reason, ''), 'Deposit payment could not be
      // verified'), and the client reads that stored value back — so this is
      // the text a reason-less rejection actually pushes.
      expect(
        bulkReservationDepositDeclinedPushBody(
          quantity: 4,
          reason: 'Deposit payment could not be verified',
        ),
        contains('4-unit reservation: Deposit payment could not be verified'),
      );
    });

    test('always says no stock moved, even with no reason at all', () {
      final body = bulkReservationDepositDeclinedPushBody(quantity: 2);
      expect(
        body,
        'The seller could not verify your deposit payment for the '
        '2-unit reservation. No stock was held. If you already sent money, '
        'contact the store directly to resolve it.',
      );
    });
  });

  group('bulkReservationDepositConfirmedPushBody', () {
    test('leads with the money, then the units and the hold deadline', () {
      final body = bulkReservationDepositConfirmedPushBody(
        quantity: 63,
        deposit: 12474,
        heldUntil: 'Nov 27, 01:40 UTC',
      );

      expect(
        body,
        'The store confirmed your ₱12474 deposit. Your 63-unit '
        'reservation is now held for you until Nov 27, 01:40 UTC. Pick the '
        'units up at the store — bulk holds are not shipped. The '
        'deposit stays non-refundable — cancel before the hold ends to avoid '
        'losing it.',
      );
    });

    test('drops the deadline clause instead of saying "until null"', () {
      final body = bulkReservationDepositConfirmedPushBody(
        quantity: 12,
        deposit: 500,
      );

      expect(body, contains('reservation is now held for you. Pick the units'));
      expect(body, isNot(contains('until')));
      expect(body, contains('bulk holds are not shipped'));
    });
  });

  group('friendlyReservationError', () {
    test('names the bulk minimum the server refused on', () {
      // request_bulk_reservation raises BULK_MINIMUM_QUANTITY (10); the sheet's
      // own button is disabled below ten, so this is the message a client that
      // slipped past that guard (or an older build) actually sees.
      expect(
        friendlyReservationError(
          const PostgrestException(
            message: 'BULK_MINIMUM_QUANTITY (10)',
            code: 'P0001',
          ),
        ),
        'Bulk buying starts at 10 pairs. Add more pairs to request a hold, '
        'or order normally below that.',
      );
    });

    test('keeps the stock message separate from the bulk floor', () {
      expect(
        friendlyReservationError(
          const PostgrestException(
            message: 'INSUFFICIENT_STOCK (4) < 10',
            code: 'P0001',
          ),
        ),
        'Not enough stock is available right now — try a smaller quantity.',
      );
    });
  });

  group('depositReceiptResultLine', () {
    // The deposit receipt is the customer's only proof they paid. The seller's
    // toast is the one place a failed send surfaces, so every outcome the
    // edge function can answer with has to read as an answer — never as a
    // silent "Deposit confirmed".
    test('names the address a sent receipt went to', () {
      expect(
        depositReceiptResultLine({
          'sent': true,
          'to': 'ana@example.com',
          'reservation_code': 'BR-1234ABCD',
        }),
        'Receipt emailed to ana@example.com.',
      );
    });

    test('stays a success when the function sent to no reported address', () {
      expect(depositReceiptResultLine({'sent': true}), 'Receipt emailed.');
    });

    test('says why an unsent receipt was not sent', () {
      expect(
        depositReceiptResultLine({'sent': false, 'reason': 'no_email'}),
        'No email on file - receipt not sent.',
      );
      expect(
        depositReceiptResultLine({'sent': false, 'reason': 'already_sent'}),
        'Receipt was already emailed.',
      );
      expect(
        depositReceiptResultLine({
          'sent': false,
          'reason': 'email_not_configured',
        }),
        'Receipt not sent: mail is not set up on the server.',
      );
    });

    test('never claims the confirmation failed', () {
      for (final reason in ['smtp_failed', 'error', 'unexpected_response']) {
        expect(
          depositReceiptResultLine({'sent': false, 'reason': reason}),
          'Receipt not sent - the deposit is still confirmed.',
        );
      }
    });
  });
}
