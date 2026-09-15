import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/services/pickup_reservation_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// A real [PostgrestFilterBuilder] that records its `eq` chain and resolves the
/// rows it was given — the same technique `order_service_test.dart` uses,
/// because `PostgrestFilterBuilder` IS a Future and mocktail cannot `thenReturn`
/// on one.
class RecordingRowsBuilder extends PostgrestFilterBuilder<PostgrestList> {
  RecordingRowsBuilder(this.rows)
    : super(
        PostgrestBuilder<PostgrestList, PostgrestList, PostgrestList>(
          url: Uri.parse('https://test.local'),
          headers: const <String, String>{},
        ),
      );

  final PostgrestList rows;
  final List<(String, Object)> eqCalls = [];

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) {
    eqCalls.add((column, value));
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(PostgrestList value) onValue, {
    Function? onError,
  }) async {
    return onValue(rows);
  }
}

/// A real [PostgrestFilterBuilder] that resolves to [value] (or rejects with
/// [error]) — same technique as `account_security_service_test.dart`, because
/// `PostgrestFilterBuilder` IS a Future, so mocktail rejects `thenReturn`, and
/// throwing out of `then` bypasses the caller's `onError`.
class FakeRpcBuilder extends PostgrestFilterBuilder<dynamic> {
  FakeRpcBuilder({this.value, this.error})
    : super(
        PostgrestBuilder<dynamic, dynamic, dynamic>(
          url: Uri.parse('https://test.local'),
          headers: const <String, String>{},
        ),
      );

  final dynamic value;
  final Object? error;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    final failure = error;
    final Future<dynamic> source = failure != null
        ? Future<dynamic>.error(failure)
        : Future<dynamic>.value(value);
    return source.then(onValue, onError: onError);
  }
}

/// A row shaped like the customer-side query
/// (`*, products(name, stores(name), product_images(...))`).
Map<String, dynamic> row({
  String status = 'active',
  String size = '40',
  int quantity = 2,
  String? deadline,
  String? image,
  List<Map<String, dynamic>>? images,
}) => {
  'id': 'r-1',
  'customer_id': 'u-1',
  'store_id': 's-1',
  'product_id': 'p-1',
  'size': size,
  'quantity': quantity,
  'reserved_stock': quantity,
  'status': status,
  'pickup_deadline': deadline ?? '2099-01-01T00:00:00Z',
  'created_at': '2026-09-15T09:00:00Z',
  'fulfilled_at': null,
  'fulfilled_order_id': null,
  'reminder_sent_at': null,
  'products': {
    'name': 'Sole Runner',
    'stores': {'name': 'CUFMAI Store'},
    'product_images': images ??
        [
          {'image_url': 'https://cdn/second.jpg', 'display_order': 2},
          {'image_url': 'https://cdn/first.jpg', 'display_order': 1},
        ],
  },
};

void main() {
  late MockSupabaseClient mockClient;
  late PickupReservationService service;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    service = PickupReservationService(client: mockClient);
  });

  void stubRpc({dynamic value, Object? error}) {
    when(
      () => mockClient.rpc(any(), params: any(named: 'params')),
    ).thenAnswer((_) => FakeRpcBuilder(value: value, error: error));
  }

  group('request', () {
    test('sends the product, size and quantity the RPC declares', () async {
      stubRpc(value: 'r-99');

      final id = await service.request(
        productId: 'p-1',
        size: '40',
        quantity: 2,
      );

      expect(id, 'r-99');
      final captured = verify(
        () => mockClient.rpc(captureAny(), params: captureAny(named: 'params')),
      ).captured;
      expect(captured[0], 'request_pickup_reservation');
      expect(captured[1], {
        'p_product_id': 'p-1',
        'p_size': '40',
        'p_quantity': 2,
      });
    });

    test('propagates the server rejection so the UI can explain it', () async {
      stubRpc(
        error: const PostgrestException(
          message: 'ABOVE_PICKUP_CAP (2) — for 3 or more units request a '
              'bulk reservation instead',
          code: 'P0001',
        ),
      );

      await expectLater(
        service.request(productId: 'p-1', size: '40', quantity: 3),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('cancel and fulfill', () {
    test('cancel sends the reservation id', () async {
      stubRpc(value: null);

      await service.cancel('r-1');

      verify(
        () => mockClient.rpc('cancel_pickup_reservation',
            params: {'p_reservation_id': 'r-1'}),
      ).called(1);
    });

    test('fulfill defaults to cash and returns the new order id', () async {
      stubRpc(value: 'order-7');

      final orderId = await service.fulfill('r-1');

      expect(orderId, 'order-7');
      verify(
        () => mockClient.rpc('fulfill_pickup_reservation', params: {
          'p_reservation_id': 'r-1',
          'p_payment_method': 'cash',
        }),
      ).called(1);
    });

    test('fulfill passes the seller-chosen method through', () async {
      stubRpc(value: 'order-8');

      await service.fulfill('r-1', paymentMethod: 'gcash');

      verify(
        () => mockClient.rpc('fulfill_pickup_reservation', params: {
          'p_reservation_id': 'r-1',
          'p_payment_method': 'gcash',
        }),
      ).called(1);
    });

    test('fulfill tolerates a null order id', () async {
      stubRpc(value: null);
      expect(await service.fulfill('r-1'), isNull);
    });
  });

  group('the opportunistic sweeps are never fatal', () {
    test('expireStale returns 0 when the RPC fails', () async {
      stubRpc(error: Exception('offline'));
      expect(await service.expireStale(), 0);
    });

    test('expireStale returns the released count', () async {
      stubRpc(value: 3);
      expect(await service.expireStale(), 3);
    });

    test('sendReminders returns 0 when the RPC fails', () async {
      stubRpc(error: Exception('offline'));
      expect(await service.sendReminders(), 0);
    });

    test('sendReminders returns the sent count', () async {
      stubRpc(value: 1);
      expect(await service.sendReminders(), 1);
    });

    test('the sweeps are the two sweeps the server implements', () async {
      stubRpc(value: 0);
      await service.expireStale();
      await service.sendReminders();

      verify(() => mockClient.rpc('expire_pickup_reservations')).called(1);
      verify(() => mockClient.rpc('send_pickup_reservation_reminders'))
          .called(1);
    });
  });

  group('the model', () {
    test('parses a row with the nested product join', () {
      final r = PickupReservation.fromJson(row());

      expect(r.id, 'r-1');
      expect(r.size, '40');
      expect(r.quantity, 2);
      expect(r.status, 'active');
      expect(r.productName, 'Sole Runner');
      expect(r.storeName, 'CUFMAI Store');
      // The lowest display_order image wins, not the first in the list.
      expect(r.productImage, 'https://cdn/first.jpg');
      expect(r.pickupDeadline, isNotNull);
      expect(r.isActive, isTrue);
      expect(r.isTerminal, isFalse);
    });

    test('parses without a product join (the seller-side shape)', () {
      final r = PickupReservation.fromJson({
        'id': 'r-2',
        'customer_id': 'u-9',
        'store_id': 's-1',
        'product_id': 'p-1',
        'size': '41',
        'quantity': 1,
        'status': 'fulfilled',
        'pickup_deadline': '2026-09-16T09:00:00Z',
        'profiles': {'name': 'Ana'},
      });

      expect(r.productName, '');
      expect(r.productImage, isNull);
      expect(r.customerName, 'Ana');
      expect(r.isFulfilled, isTrue);
      expect(r.isTerminal, isTrue);
      expect(r.statusLabel, 'Collected');
    });

    test('statuses map to human labels', () {
      String label(String status) =>
          PickupReservation.fromJson(row(status: status)).statusLabel;
      expect(label('active'), 'Holding for pickup');
      expect(label('fulfilled'), 'Collected');
      expect(label('cancelled'), 'Cancelled');
      expect(label('expired'), 'Expired');
    });

    test('survives junk instead of throwing', () {
      final r = PickupReservation.fromJson(const {});
      expect(r.id, '');
      expect(r.quantity, 0);
      expect(r.status, 'active');
      expect(r.pickupDeadline, isNull);
    });
  });

  group('the countdown', () {
    final now = DateTime(2026, 9, 15, 12, 0, 0);
    PickupReservation withDeadline(DateTime? d, {String status = 'active'}) =>
        PickupReservation(
          id: 'r',
          customerId: 'u',
          storeId: 's',
          productId: 'p',
          size: '40',
          quantity: 1,
          status: status,
          pickupDeadline: d,
        );

    test('counts down in hours and minutes', () {
      final r = withDeadline(now.add(const Duration(hours: 5, minutes: 12)));
      expect(r.countdownLabelAt(now), '5h 12m left');
    });

    test('switches to minutes inside the last hour', () {
      final r = withDeadline(now.add(const Duration(minutes: 42)));
      expect(r.countdownLabelAt(now), '42m left');
    });

    test('does not say "0m left" in the final minute', () {
      final r = withDeadline(now.add(const Duration(seconds: 30)));
      expect(r.countdownLabelAt(now), 'Expires in under a minute');
    });

    test('reports a lapsed hold as expired', () {
      final r = withDeadline(now.subtract(const Duration(minutes: 1)));
      expect(r.countdownLabelAt(now), 'Expired');
      expect(r.hasLapsedAt(now), isTrue);
      expect(r.isExpiringSoonAt(now), isFalse);
    });

    test('"expiring soon" is the last two hours, matching the reminder', () {
      expect(
        withDeadline(now.add(const Duration(hours: 2)))
            .isExpiringSoonAt(now),
        isTrue,
        reason: 'exactly 2h is inside the window the server reminds at',
      );
      expect(
        withDeadline(now.add(const Duration(hours: 2, minutes: 1)))
            .isExpiringSoonAt(now),
        isFalse,
      );
    });

    test('a resolved hold never reports itself as expiring', () {
      final r = withDeadline(now.add(const Duration(minutes: 5)),
          status: 'fulfilled');
      expect(r.isExpiringSoonAt(now), isFalse);
      expect(r.countdownLabelAt(now), 'Collected');
    });

    test('a missing deadline is neither lapsed nor "expired"', () {
      // A malformed row must not tell the customer their hold is gone.
      final r = withDeadline(null);
      expect(r.hasLapsedAt(now), isFalse);
      expect(r.isExpiringSoonAt(now), isFalse);
      expect(r.countdownLabelAt(now), 'Deadline unavailable');
    });
  });

  group('fetchStoreStats — the dashboard in ONE query', () {
    late MockSupabaseQueryBuilder query;
    late RecordingRowsBuilder filter;

    setUp(() {
      query = MockSupabaseQueryBuilder();
      filter = RecordingRowsBuilder([]);
      when(() => mockClient.from('pickup_reservations')).thenAnswer((_) => query);
      when(() => query.select(any())).thenAnswer((_) => filter);
    });

    test('asks for only the columns the counts need', () async {
      await service.fetchStoreStats('s-1');
      // No joins: the dashboard needs counts, not names.
      verify(() => query.select('quantity, pickup_deadline, status')).called(1);
    });

    test('scopes to the store and to live holds', () async {
      await service.fetchStoreStats('s-1');
      expect(filter.eqCalls, [('store_id', 's-1'), ('status', 'active')]);
    });

    test('the headline count and the lapsing badge come from the same rows',
        () async {
      final now = DateTime.now();
      filter = RecordingRowsBuilder([
        {
          'quantity': 2,
          'status': 'active',
          'pickup_deadline': now.add(const Duration(minutes: 90)).toUtc().toIso8601String(),
        },
        {
          'quantity': 1,
          'status': 'active',
          'pickup_deadline': now.add(const Duration(hours: 20)).toUtc().toIso8601String(),
        },
      ]);

      final stats = await service.fetchStoreStats('s-1');
      expect(stats.active, 2);
      expect(stats.lapsing, 1);
      expect(stats.returningUnits, 2);
    });
  });

  group('PickupHoldSummary — what the store is told', () {
    final now = DateTime.utc(2026, 9, 15, 12, 0);

    PickupReservation hold({
      String status = 'active',
      int quantity = 1,
      Duration? left,
      DateTime? deadline,
    }) =>
        PickupReservation(
          id: 'r-$quantity-$status-$left',
          customerId: 'u-1',
          storeId: 's-1',
          productId: 'p-1',
          size: '40',
          quantity: quantity,
          status: status,
          pickupDeadline: deadline ??
              (left == null ? null : now.add(left)),
        );

    test('counts what is off the shelf now', () {
      final s = PickupHoldSummary.from(
        [hold(quantity: 2, left: const Duration(hours: 20)), hold(left: const Duration(hours: 10))],
        now,
      );
      expect(s.activeHolds, 2);
      expect(s.activeUnits, 3);
      expect(s.heldLabel, '2 holds · 3 pairs held');
      expect(s.hasReturning, isFalse);
      expect(s.returningLabel, isNull);
    });

    test('a hold inside the 2-hour window is stock coming back', () {
      final s = PickupHoldSummary.from(
        [hold(quantity: 2, left: const Duration(minutes: 90))],
        now,
      );
      expect(s.lapsingHolds, 1);
      expect(s.lapsingUnits, 2);
      expect(s.returningUnits, 2);
      expect(s.returningLabel, '2 pairs back within 2h');
      expect(s.lapsedLabel, isNull);
    });

    test('the window boundary is inclusive at exactly 2 hours', () {
      expect(
        PickupHoldSummary.from([hold(left: const Duration(hours: 2))], now)
            .lapsingHolds,
        1,
      );
      expect(
        PickupHoldSummary.from(
          [hold(left: const Duration(hours: 2, seconds: 1))],
          now,
        ).lapsingHolds,
        0,
      );
    });

    test('an already-lapsed hold counts as stock coming back too', () {
      // Past its deadline but not yet swept: those units ARE still out of
      // stock, so a store must not be told they are available — but they are
      // the ones returning first, and the seller can release them now.
      final s = PickupHoldSummary.from(
        [hold(left: const Duration(minutes: -5))],
        now,
      );
      expect(s.activeHolds, 1, reason: 'still holding stock until the sweep runs');
      expect(s.lapsedHolds, 1);
      expect(s.lapsingHolds, 0, reason: 'lapsed is not the same as lapsing');
      expect(s.returningUnits, 1);
      expect(s.lapsedLabel, '1 lapsed — releases on the next load');
    });

    test('returns are summed across lapsing AND lapsed holds', () {
      final s = PickupHoldSummary.from(
        [
          hold(quantity: 2, left: const Duration(minutes: 30)),
          hold(quantity: 1, left: const Duration(minutes: -1)),
          hold(quantity: 2, left: const Duration(hours: 18)),
        ],
        now,
      );
      expect(s.activeUnits, 5);
      expect(s.returningHolds, 2);
      expect(s.returningUnits, 3);
    });

    test('resolved holds are ignored entirely', () {
      final s = PickupHoldSummary.from(
        [
          hold(status: 'fulfilled', quantity: 2, left: const Duration(minutes: 5)),
          hold(status: 'cancelled', quantity: 2, left: const Duration(minutes: 5)),
          hold(status: 'expired', quantity: 2, left: const Duration(minutes: -60)),
        ],
        now,
      );
      expect(s.isEmpty, isTrue);
      expect(s.returningUnits, 0);
    });

    test('a missing deadline is held, but never called lapsing', () {
      // `pickup_deadline` is NOT NULL in SQL; this is the malformed-row case,
      // and inventing a countdown for it would be a guess.
      final s = PickupHoldSummary.from([hold(deadline: null)], now);
      expect(s.activeHolds, 1);
      expect(s.lapsingHolds, 0);
      expect(s.lapsedHolds, 0);
      expect(s.returningUnits, 0);
    });

    test('an active row with no quantity still counts as one pair', () {
      // Under-reporting stock that is about to come back is the worse error:
      // nobody goes looking for it.
      final s = PickupHoldSummary.fromRows([
        {'status': 'active', 'pickup_deadline': now.add(const Duration(hours: 1)).toUtc().toIso8601String()},
      ], now);
      expect(s.activeUnits, 1);
      expect(s.returningUnits, 1);
    });

    test('singular wording, and no zero-line to render', () {
      final s = PickupHoldSummary.from([hold(left: const Duration(minutes: 45))], now);
      expect(s.heldLabel, '1 hold · 1 pair held');
      expect(s.returningLabel, '1 pair back within 2h');
      expect(PickupHoldSummary().heldLabel, '0 holds · 0 pairs held');
      expect(PickupHoldSummary().returningLabel, isNull);
      expect(PickupHoldSummary().lapsedLabel, isNull);
    });

    test('the two entry points agree on the same data', () {
      // The seller screen passes objects, the dashboard passes partial rows.
      // If they ever disagree, the screen and the badge would tell a store two
      // different things about the same holds.
      final rows = [
        {
          'status': 'active',
          'quantity': 2,
          'pickup_deadline': now.add(const Duration(minutes: 40)).toUtc().toIso8601String(),
        },
        {
          'status': 'active',
          'quantity': 1,
          'pickup_deadline': now.subtract(const Duration(minutes: 10)).toUtc().toIso8601String(),
        },
      ];
      final fromRows = PickupHoldSummary.fromRows(rows, now);
      final fromObjects = PickupHoldSummary.from(
        [
          hold(quantity: 2, left: const Duration(minutes: 40)),
          hold(quantity: 1, left: const Duration(minutes: -10)),
        ],
        now,
      );
      expect(fromRows.activeUnits, fromObjects.activeUnits);
      expect(fromRows.lapsingHolds, fromObjects.lapsingHolds);
      expect(fromRows.lapsedHolds, fromObjects.lapsedHolds);
      expect(fromRows.returningUnits, fromObjects.returningUnits);
      expect(fromRows.heldLabel, fromObjects.heldLabel);
    });
  });

  group('the extension rules', () {
    final now = DateTime.utc(2026, 9, 15, 12, 0);

    PickupReservation hold({
      String status = 'active',
      int extensionCount = 0,
      Duration? left,
      DateTime? deadline,
    }) =>
        PickupReservation(
          id: 'r-1',
          customerId: 'u-1',
          storeId: 's-1',
          productId: 'p-1',
          size: '40',
          quantity: 1,
          status: status,
          extensionCount: extensionCount,
          pickupDeadline: deadline ??
              (left == null ? null : now.add(left)),
        );

    test('the window constants multiply out to the server ceiling', () {
      expect(PickupReservation.holdHours, 24);
      expect(PickupReservation.maxExtensions, 1);
      expect(PickupReservation.extensionHours, 24);
      expect(PickupReservation.maxHoldHours, 48);
    });

    test('a fresh live hold can be extended once', () {
      final r = hold(left: const Duration(hours: 20));
      expect(r.extensionsLeft, 1);
      expect(r.canExtendAt(now), isTrue);
      expect(r.extendActionLabel, 'Extend 24h');
      expect(r.extensionNote, contains('Extend once for 24h'));
      expect(r.extensionNote, contains('48h total'));
    });

    test('the cap is spent after one extension, and the UI says so', () {
      final r = hold(left: const Duration(hours: 20), extensionCount: 1);
      expect(r.extensionsLeft, 0);
      expect(r.canExtendAt(now), isFalse);
      expect(r.extendActionLabel, isNull);
      // The note stays: a later deadline on the seller's side needs an
      // explanation the customer can see.
      expect(r.extensionNote, contains('cannot be extended twice'));
    });

    test('a LAPSED hold can never be extended, even with the cap unused', () {
      // The sweep may release these units at any moment, so more time is not
      // ours to give — this is the rule that keeps the promise honest.
      final r = hold(left: const Duration(minutes: -5));
      expect(r.isActive, isTrue, reason: 'still holding stock until the sweep');
      expect(r.extensionsLeft, 1);
      expect(r.canExtendAt(now), isFalse);
    });

    test('a resolved hold cannot be extended', () {
      for (final status in ['fulfilled', 'cancelled', 'expired']) {
        final r = hold(status: status, left: const Duration(hours: 5));
        expect(r.canExtendAt(now), isFalse, reason: status);
        expect(r.extensionNote, isNull, reason: status);
      }
    });

    test('a hold with no known deadline is not offered an extension', () {
      // "Before it expires" cannot be answered without a deadline, and the
      // server would refuse — so the button must not appear.
      final r = hold(deadline: null);
      expect(r.canExtendAt(now), isFalse);
    });

    test('an unknown extension count is treated as none used', () {
      // A row fetched by a partial select has no `extension_count`; assuming
      // the cap was spent would hide a legitimate action.
      expect(PickupReservation.fromJson({'id': 'r'}).extensionCount, 0);
      expect(
        PickupReservation.fromJson({'id': 'r', 'extension_count': 1})
            .extensionCount,
        1,
      );
    });

    test('extend() calls the RPC by name and reads the new deadline back',
        () async {
      stubRpc(value: '2026-09-17T10:00:00Z');

      final deadline = await service.extend('r-1');

      verify(() => mockClient.rpc(
            'extend_pickup_reservation',
            params: {'p_reservation_id': 'r-1'},
          )).called(1);
      expect(deadline, isNotNull);
      expect(deadline!.toUtc().hour, 10);
    });

    test('extend() tolerates a response with no deadline in it', () async {
      // The deadline is what the confirmation says, so a missing one must
      // degrade to "Hold extended." rather than crash or invent a time.
      stubRpc(value: null);
      expect(await service.extend('r-1'), isNull);
      stubRpc(value: 'not a date');
      expect(await service.extend('r-1'), isNull);
    });
  });

  group('friendlyPickupReservationError', () {
    String mapped(String message) =>
        friendlyPickupReservationError(
          PostgrestException(message: message, code: 'P0001'),
        );

    test('above the cap points at the bulk flow, not a dead end', () {
      final copy = mapped('ABOVE_PICKUP_CAP (2) — for 3 or more units request '
          'a bulk reservation instead');
      expect(copy, contains('2 pairs'));
      expect(copy.toLowerCase(), contains('bulk reservation'));
      // It must not read as a generic failure.
      expect(copy, isNot(contains('Something went wrong')));
    });

    test('an already-held size explains the rule', () {
      expect(mapped('RESERVATION_ALREADY_EXISTS'),
          contains('already have an active pickup hold'));
    });

    test('a lost concurrent double-submit reads as the same rule', () {
      // Two simultaneous submits both pass the RPC's serial duplicate check;
      // the loser is stopped by the partial unique index and arrives as 23505
      // ("duplicate key value violates unique constraint …"). It is the same
      // situation, so it must not surface as a generic failure.
      final copy = friendlyPickupReservationError(
        PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"idx_pickup_reservations_one_active_per_customer_product_size"',
          code: '23505',
        ),
      );
      expect(copy, contains('already have an active pickup hold'));
      expect(copy, isNot(contains('duplicate key')));
      expect(copy, isNot(contains('constraint')));
      // Byte-identical to the serial path, so the two cannot drift apart.
      expect(copy, kPickupAlreadyHoldingCopy);
    });

    test('insufficient stock is actionable, not alarming', () {
      final copy = mapped('INSUFFICIENT_STOCK (1) < 2');
      expect(copy, contains('another size'));
      expect(copy, isNot(contains('1) < 2')), reason: 'no raw SQL leaks');
    });

    test('a spent extension cap explains the cap, not just "no"', () {
      final copy = mapped('EXTENSION_LIMIT_REACHED (1) — this hold has already been extended');
      expect(copy, contains('already been extended'));
      expect(copy, contains('48 hours'));
      expect(copy, contains('Reserve again'));
    });

    test('a lapsed hold is not blamed on the customer', () {
      final copy = mapped('HOLD_LAPSED — this hold has already run out; reserve again');
      expect(copy, contains('run out of time'));
      expect(copy, isNot(contains('HOLD_LAPSED')));
    });

    test('an expired sweep release tells the customer to refresh', () {
      expect(mapped('ALREADY_RESOLVED'), contains('Pull to refresh.'));
    });

    test('a session problem asks for a fresh sign-in', () {
      expect(mapped('NOT_AUTHENTICATED'), contains('sign in again'));
    });

    test('a size is required for a hold', () {
      expect(mapped('SIZE_REQUIRED'), contains('Choose a size'));
    });

    test('the payment method is validated with the seller in mind', () {
      expect(mapped('INVALID_PAYMENT_METHOD'), contains('cash or GCash'));
    });

    test('the remaining codes each get their own copy', () {
      expect(mapped('FORBIDDEN'), contains('cannot change'));
      expect(mapped('PRODUCT_NOT_FOUND'), contains('no longer available'));
      expect(mapped('INVALID_QUANTITY'), contains('at least one pair'));
      expect(mapped('NOT_FOUND'), contains('no longer exists'));
    });

    test('an unknown failure stays generic instead of leaking SQL', () {
      final copy = mapped('some raw postgres detail');
      expect(copy, 'Something went wrong with the pickup reservation. '
          'Please try again.');
    });

    test('a plain non-Postgrest error also maps to generic copy', () {
      expect(
        friendlyPickupReservationError(Exception('socket exploded')),
        contains('Something went wrong'),
      );
    });
  });
}
