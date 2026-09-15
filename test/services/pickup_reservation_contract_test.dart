import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/pickup_reservation_service.dart';

/// Cross-artifact guards for the FREE pickup reservation flow (ANQUI item 14).
///
/// Three things the Dart side and the SQL side must agree on and nothing
/// checks at compile time: the CAP, the STATUS vocabulary, and the RPC names.
/// Plus one rule from the brief itself, which is easy to break by accident
/// and impossible to notice: **this flow must stay separate from the
/// deposit-gated bulk reservation system.**
void main() {
  const migrationPath =
      'supabase/migrations/20260915170000_add_pickup_reservations.sql';
  const servicePath = 'lib/services/pickup_reservation_service.dart';
  const sheetPath =
      'lib/screens/customer/widgets/pickup_reservation_sheet.dart';
  const customerScreenPath =
      'lib/screens/customer/my_pickup_reservations_screen.dart';

  late String sql;
  late String service;
  late String sqlCode;
  late String serviceCode;
  late String customerUi;

  /// Comments are allowed to NAME the other system — the header of the
  /// migration and the doc comments of the service exist precisely to explain
  /// how the two differ. What must never happen is an executable reference,
  /// so the separation guards below run against the code with comments
  /// stripped.
  String withoutLineComments(String source) => source
      .split('\n')
      .where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('--') && !trimmed.startsWith('//');
      })
      .join('\n');

  setUpAll(() {
    final migration = File(migrationPath);
    expect(
      migration.existsSync(),
      isTrue,
      reason: 'the pickup-reservation migration should exist at $migrationPath',
    );
    sql = migration.readAsStringSync();
    service = File(servicePath).readAsStringSync();
    customerUi = File(sheetPath).readAsStringSync() +
        File(customerScreenPath).readAsStringSync();
    sqlCode = withoutLineComments(sql);
    serviceCode = withoutLineComments(service);
  });

  group('the cap', () {
    test('the Dart constant is the same number as the SQL function', () {
      // Read the SQL value rather than trusting the doc comment: the point of
      // this test is to fail when one side is edited alone.
      final match = RegExp(r'pickup_reservation_max_quantity\(\)[\s\S]{0,120}?SELECT (\d+)')
          .firstMatch(sql);
      expect(
        match,
        isNotNull,
        reason: 'pickup_reservation_max_quantity() no longer returns a '
            'literal SELECT — update this guard, do not delete it',
      );
      expect(
        PickupReservation.maxQuantity,
        int.parse(match!.group(1)!),
        reason: 'the app and the server disagree on how many pairs a free '
            'hold may take; the sheet would offer a quantity the RPC rejects',
      );
    });

    test('the sheet never lets the stepper exceed the cap', () {
      // The stepper's upper bound is min(cap, live stock) — if the cap is
      // dropped from that expression the UI would offer 3 and the customer
      // would get a rejection instead of a disabled button.
      expect(customerUi, contains('PickupReservation.maxQuantity'));
      expect(customerUi, contains('_maxForSelectedSize'));
    });

    test('above the cap the app points at the bulk flow, not a dead end', () {
      expect(customerUi, contains('bulk reservation'));
    });
  });

  group('the extension rules', () {
    /// Reads the number a `$$ SELECT n; $$` constant actually returns, rather
    /// than trusting a doc comment — the point is to fail when one side is
    /// edited alone.
    ///
    /// Anchored on the DECLARATION (prose above these functions names them
    /// freely), and it follows one level of indirection, because
    /// `pickup_reservation_extension_hours()` deliberately returns
    /// `pickup_reservation_hold_hours()` instead of a second literal 24.
    int sqlConstant(String functionName, [int depth = 0]) {
      final start = sql.indexOf('FUNCTION public.$functionName()');
      expect(start, isNot(-1),
          reason: '$functionName() is gone from the migration — update this '
              'guard, do not delete it');
      final body = sql.substring(start, start + 240);
      final match = RegExp(r'SELECT ([\w.() ]+?);').firstMatch(body);
      expect(match, isNotNull,
          reason: '$functionName() no longer starts with a SELECT literal');
      final value = match!.group(1)!.trim();

      final literal = int.tryParse(value);
      if (literal != null) return literal;

      final callee = RegExp(r'public\.(\w+)\(\)').firstMatch(value)?.group(1);
      expect(callee, isNotNull,
          reason: '$functionName() returns "$value", which this guard cannot '
              'read as a number');
      expect(depth < 3, isTrue,
          reason: '$functionName() resolves in a circle');
      return sqlConstant(callee!, depth + 1);
    }

    test('the Dart window constants are the SQL functions', () {
      expect(PickupReservation.holdHours,
          sqlConstant('pickup_reservation_hold_hours'));
      expect(PickupReservation.maxExtensions,
          sqlConstant('pickup_reservation_max_extensions'));
      expect(PickupReservation.extensionHours,
          sqlConstant('pickup_reservation_extension_hours'));
    });

    test('the app never promises a longer hold than the server allows', () {
      // maxHoldHours is what the copy quotes to the customer. The server caps
      // the real deadline with a CHECK, so a drift here would have the app
      // advertising time the RPC can never grant.
      expect(
        PickupReservation.maxHoldHours,
        PickupReservation.holdHours * (1 + PickupReservation.maxExtensions),
      );
      expect(
        sql,
        contains('pickup_reservations_within_max_window'),
        reason: 'the ceiling stopped being a table CHECK — the "a store can '
            'never be made to wait longer than this" claim would become a '
            'rule inside one RPC again',
      );
      expect(sql, contains('pickup_reservations_within_extension_cap'));
    });

    test('the customer UI offers the extension and says who it costs', () {
      // The action and the honest note both have to survive edits: an "Extend"
      // button with no explanation is exactly the copy a store would object to.
      expect(customerUi, contains('_extend'));
      expect(customerUi, contains('PickupReservation.extensionHours'));
      expect(customerUi, contains('extensionNote'));
    });
  });

  group('the vocabulary', () {
    test('the status enum matches what the model parses', () {
      final match =
          RegExp(r'CREATE TYPE pickup_reservation_status AS ENUM \(([\s\S]*?)\);')
              .firstMatch(sql);
      expect(match, isNotNull, reason: 'the status enum moved or was renamed');
      final sqlStatuses = RegExp("'([a-z]+)'")
          .allMatches(match!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(sqlStatuses, ['active', 'fulfilled', 'cancelled', 'expired']);
      for (final status in sqlStatuses) {
        expect(
          service.contains("'$status'"),
          isTrue,
          reason: 'the service never mentions the SQL status "$status" — the '
              'model would show it as an unknown status',
        );
      }
    });

    test('every error code the server raises is mapped to friendly copy', () {
      // The RPCs raise stable codes as P0001 messages; a code with no case in
      // the mapper reaches the customer as a generic failure.
      const codes = [
        'NOT_AUTHENTICATED',
        'INVALID_QUANTITY',
        'ABOVE_PICKUP_CAP',
        'PRODUCT_NOT_FOUND',
        'SIZE_REQUIRED',
        'INSUFFICIENT_STOCK',
        'RESERVATION_ALREADY_EXISTS',
        'INVALID_PAYMENT_METHOD',
        'FORBIDDEN',
        'ALREADY_RESOLVED',
        'NOT_FOUND',
        'EXTENSION_LIMIT_REACHED',
        'HOLD_LAPSED',
      ];
      for (final code in codes) {
        expect(sql, contains("'$code"),
            reason: '$code is no longer raised by the migration');
        expect(service, contains(code),
            reason: '$code is raised but not mapped to customer copy');
      }
    });

    test('the RPC names the service calls exist in the migration', () {
      for (final rpc in [
        'request_pickup_reservation',
        'cancel_pickup_reservation',
        'extend_pickup_reservation',
        'fulfill_pickup_reservation',
        'expire_pickup_reservations',
        'send_pickup_reservation_reminders',
      ]) {
        expect(service, contains(rpc), reason: '$rpc is not called anywhere');
        expect(sql, contains('FUNCTION public.$rpc'),
            reason: '$rpc is called but not defined in the migration');
      }
    });

    test('the service sends the parameter names the RPCs declare', () {
      // A renamed parameter is a silent 404-shaped failure at runtime.
      for (final param in [
        'p_product_id',
        'p_size',
        'p_quantity',
        'p_reservation_id',
        'p_payment_method',
      ]) {
        expect(service, contains("'$param'"));
        expect(sql, contains(param),
            reason: '$param is sent by the client but not declared in SQL');
      }
    });
  });

  group('the two reservation systems stay separate', () {
    test('the pickup service never touches a bulk table or RPC', () {
      // The brief's hardest constraint: it is easy for a later edit to
      // "reuse" the deposit-gated path here and quietly make a free hold
      // cost money. This is the tripwire.
      for (final forbidden in [
        'bulk_reservations',
        'bulk_reservation_deposits',
        'request_bulk_reservation',
        'decide_bulk_reservation',
        'fulfill_bulk_reservation',
        'cancel_bulk_reservation',
        'confirm_bulk_reservation_deposit',
        'submit_bulk_reservation_deposit_proof',
      ]) {
        expect(
          serviceCode.contains(forbidden),
          isFalse,
          reason: 'pickup_reservation_service.dart calls "$forbidden" — the '
              'free pickup hold must not depend on the deposit-gated bulk flow',
        );
      }
    });

    test('the migration never touches a bulk table', () {
      expect(sqlCode.contains('public.bulk_reservations'), isFalse);
      expect(sqlCode.contains('public.bulk_reservation_deposits'), isFalse);
      expect(sqlCode.contains('bulk_reservation_status'), isFalse);
    });

    test('the customer-facing copy never asks for a deposit', () {
      // Saying "no deposit" is the POINT of this flow, so the word itself is
      // fine — what must never appear is copy that asks the customer to pay
      // one, or imports the bulk flow's non-refundable wording.
      final lower = customerUi.toLowerCase();
      for (final forbidden in [
        'deposit required',
        'pay a deposit',
        'pay the deposit',
        'non-refundable',
        'forfeit',
      ]) {
        expect(
          lower.contains(forbidden),
          isFalse,
          reason: 'the pickup copy says "$forbidden" — this hold is FREE and '
              'must not read like the deposit-gated bulk flow',
        );
      }
      // …and it DOES say what it actually is.
      expect(lower, contains('free'));
      expect(lower, contains('no deposit'));
      expect(customerUi, contains('24'));
    });

    test('the pickup flow does not write sales_transactions', () {
      // POS sales live in `orders WHERE source = 'pos'` (the legacy
      // sales_transactions path is dead). Fulfil must write the live shape.
      expect(sqlCode, contains("'pos'"));
      expect(sqlCode.contains('sales_transactions'), isFalse);
    });
  });
}
