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
  const sellerScreenPath =
      'lib/screens/seller/pickup_reservations_screen.dart';
  const goodwillScreenPath =
      'lib/screens/customer/pickup_goodwill_screen.dart';

  /// The store's goodwill grant is its own migration: the constants it spends
  /// live in the base file (the ceiling CHECK needs them), while the trail and
  /// the RPC are here. Both files are read, and they are kept SEPARATE rather
  /// than concatenated because the base file's convergence guards walk every
  /// `ADD COLUMN IF NOT EXISTS` in `sqlCode` — concatenating would drag this
  /// file's second table into a test about the first one's shape.
  const storeMigrationPath =
      'supabase/migrations/20260916120000_add_store_pickup_extensions.sql';

  /// The counter code is its own migration too: the COLUMN and its CHECK live in
  /// the base file (an existing table converges its columns there), while the
  /// alphabet, the generator, the lookup and the one-action fulfil are here.
  const codeMigrationPath =
      'supabase/migrations/20260916140000_add_pickup_codes.sql';

  late String sql;
  late String service;
  late String sqlCode;
  late String serviceCode;
  late String customerUi;
  late String sellerUi;
  late String customerGoodwillUi;
  late String storeSql;
  late String storeSqlCode;
  late String codeSql;
  late String codeSqlCode;

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
    final storeMigration = File(storeMigrationPath);
    expect(
      storeMigration.existsSync(),
      isTrue,
      reason: 'the store-grant migration should exist at $storeMigrationPath',
    );
    storeSql = storeMigration.readAsStringSync();
    storeSqlCode = withoutLineComments(storeSql);

    final codeMigration = File(codeMigrationPath);
    expect(
      codeMigration.existsSync(),
      isTrue,
      reason: 'the pickup-code migration should exist at $codeMigrationPath',
    );
    codeSql = codeMigration.readAsStringSync();
    codeSqlCode = withoutLineComments(codeSql);

    final sellerScreen = File(sellerScreenPath);
    expect(sellerScreen.existsSync(), isTrue,
        reason: 'the seller pickup screen should exist at $sellerScreenPath');
    // The seller screen alone: the reason bound is quoted by the DIALOG, and
    // scanning a second file for it would let a missing bound pass because the
    // other screen happens to contain the same two numbers.
    sellerUi = sellerScreen.readAsStringSync();

    final goodwillScreen = File(goodwillScreenPath);
    expect(goodwillScreen.existsSync(), isTrue,
        reason: 'the goodwill history screen should exist at $goodwillScreenPath');
    customerGoodwillUi = goodwillScreen.readAsStringSync();

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

  /// Reads the number a `$$ SELECT n; $$` constant actually returns, rather
  /// than trusting a doc comment — the point is to fail when one side is
  /// edited alone.
  ///
  /// Anchored on the DECLARATION (prose above these functions names them
  /// freely), and it follows one level of indirection, because
  /// `pickup_reservation_extension_hours()` deliberately returns
  /// `pickup_reservation_hold_hours()` instead of a second literal 24.
  ///
  /// It reads a PLAIN literal or a single call, so the one function that is an
  /// ARITHMETIC EXPRESSION (`pickup_reservation_max_window_hours()`, which sums
  /// every budget) is checked by its parts instead — see the ceiling test below.
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

  group('the extension rules', () {
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

  // ── the re-apply hazard ──────────────────────────────────────────────
  // This file is applied BY HAND through the SQL Editor, so "idempotent" has
  // to mean more than "does not error where it already ran at this revision".
  // `CREATE TABLE IF NOT EXISTS` is a NO-OP on an existing table, so a column
  // that exists in §3 but not in §3b is INVISIBLE on any database that already
  // holds the table — which is not hypothetical: a live re-apply died with
  // `42703: column "extension_count" does not exist`, naming the constraint
  // rather than the CREATE TABLE that quietly did nothing.
  group('the schema converges when the file is re-applied', () {
    /// Columns §3 (`CREATE TABLE IF NOT EXISTS`) declares: a line that STARTS
    /// with `name <TYPE>`, so continuation clauses (`ON DELETE SET NULL,`) and
    /// the `--` prose between columns are both ignored.
    List<String> declaredColumns() {
      final start =
          sqlCode.indexOf('CREATE TABLE IF NOT EXISTS public.pickup_reservations');
      expect(start, isNot(-1),
          reason: '§3 moved or was renamed — update this guard, do not delete it');
      final end = sqlCode.indexOf('\n);', start);
      expect(end, isNot(-1), reason: '§3 has no terminating `);`');
      // The TYPE is matched loosely on purpose: a fixed list of built-in types
      // silently skipped `status pickup_reservation_status` (the enum) when this
      // guard was first written, and a guard that quietly under-reads its own
      // input is worse than no guard. Uppercase simple/parameterized types
      // (`UUID`, `NUMERIC(2,1)`) or a lowercase named type (the enum) both match;
      // a continuation clause starting with a keyword (`ON DELETE …`) does not,
      // because it would have to begin the line with a lowercase identifier.
      return RegExp(
        r'^\s*([a-z_][a-z0-9_]*)\s+(?:[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?|[a-z_][a-z0-9_]*)',
        multiLine: true,
      )
          .allMatches(sqlCode.substring(start, end))
          .map((m) => m.group(1)!)
          .toList();
    }

    /// Columns §3b (`ALTER TABLE … ADD COLUMN IF NOT EXISTS`) converges.
    List<String> convergedColumns() =>
        RegExp(r'ADD COLUMN IF NOT EXISTS ([a-z_][a-z0-9_]*)')
            .allMatches(sqlCode)
            .map((m) => m.group(1)!)
            .toList();

    test('§3b converges exactly the columns §3 declares', () {
      final declared = declaredColumns();
      expect(declared, isNotEmpty,
          reason: 'this guard stopped parsing §3 — fix the pattern rather '
              'than deleting the guard');
      final converged = convergedColumns();

      expect(
        converged.toSet(),
        declared.toSet(),
        reason: 'every column §3 declares must also be converged by §3b, or a '
            're-apply over a table that predates it fails with 42703 — and '
            'nothing in §3b that §3 does not declare either, or it is '
            'converging a column nothing creates',
      );
      expect(converged.length, declared.length,
          reason: 'a column is converged twice — one line is dead');
    });

    test('§3b runs before the constraints that read its columns', () {
      final convergence = sqlCode.indexOf('ADD COLUMN IF NOT EXISTS');
      final window =
          sqlCode.indexOf('ADD CONSTRAINT pickup_reservations_within_max_window');
      final cap =
          sqlCode.indexOf('ADD CONSTRAINT pickup_reservations_within_extension_cap');
      expect([convergence, window, cap], everyElement(isNot(-1)));

      expect(convergence, lessThan(cap),
          reason: 'the extension-count CHECK reads `extension_count`, so it '
              'must run AFTER §3b or the file cannot be re-applied over a '
              'table that predates that column (the 42703 above)');
      expect(convergence, lessThan(window),
          reason: 'the window CHECK reads `created_at`/`pickup_deadline` — '
              'same ordering requirement');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // The store's GOODWILL grant (the second budget). Split across two files
  // by design: the ceiling CHECK needs the constants, so they live in the base
  // migration, while the trail and the RPC get their own.
  // ══════════════════════════════════════════════════════════════════
  group('the store goodwill grant', () {
    /// Columns the grant trail's `CREATE TABLE IF NOT EXISTS` declares — the
    /// same reader as §3 above, pointed at the second table.
    List<String> grantColumns() {
      final start = storeSqlCode.indexOf(
          'CREATE TABLE IF NOT EXISTS '
          'public.pickup_reservation_extension_grants');
      expect(start, isNot(-1),
          reason: 'the trail table moved or was renamed — update this guard, '
              'do not delete it');
      final end = storeSqlCode.indexOf('\n);', start);
      expect(end, isNot(-1), reason: 'the trail table has no terminating `);`');
      return RegExp(
        r'^\s*([a-z_][a-z0-9_]*)\s+(?:[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?|[a-z_][a-z0-9_]*)',
        multiLine: true,
      )
          .allMatches(storeSqlCode.substring(start, end))
          .map((m) => m.group(1)!)
          .toList();
    }

    /// The body of `grant_pickup_extension`, from its declaration to its
    /// GRANT. Everything a grant does — the checks, the deadline move, the
    /// trail row, the notification — has to happen inside this one function, so
    /// the guards below read it as a unit rather than as a fixed-size window
    /// that silently slides out of range when a comment grows.
    String grantRpc() {
      final start = storeSql.indexOf('FUNCTION public.grant_pickup_extension');
      final end = storeSql.indexOf('REVOKE ALL ON FUNCTION', start);
      expect([start, end], everyElement(isNot(-1)),
          reason: 'the grant RPC moved — update this guard, do not delete it');
      return storeSql.substring(start, end);
    }

    /// The columns the Dart model's select asks for, read out of the service so
    /// the list cannot be tested against a copy of itself.
    List<String> selectedColumns() {
      final match =
          RegExp(r"_grantColumns = '([\s\S]*?)';").firstMatch(serviceCode);
      expect(match, isNotNull,
          reason: 'the model no longer selects an explicit column list — a '
              'schema change would start feeding the UI silent nulls');
      return match!
          .group(1)!
          .replaceAll("'", '')
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
    }

    test('the store budget and hours are the SQL functions', () {
      expect(PickupReservation.maxStoreExtensions,
          sqlConstant('pickup_reservation_max_store_extensions'));
      expect(PickupReservation.storeExtensionHours,
          sqlConstant('pickup_reservation_store_extension_hours'));
    });

    test('the absolute ceiling sums EVERY budget, on both sides', () {
      final hold = sqlConstant('pickup_reservation_hold_hours');
      final customer = sqlConstant('pickup_reservation_max_extensions');
      final store = sqlConstant('pickup_reservation_max_store_extensions');

      expect(PickupReservation.maxWindowHours, hold * (1 + customer + store),
          reason: 'the Dart ceiling and the SQL budgets have drifted apart — '
              'the app would promise (or hide) time the CHECK does not allow');
      // The customer's OWN ceiling is unchanged: a store's goodwill is an extra
      // budget, not a re-basing of the customer's.
      expect(PickupReservation.maxHoldHours, hold * (1 + customer));

      // The SQL side must actually SUM all three, or the CHECK could be widened
      // for one budget and forgotten for the other.
      final start = sql
          .indexOf('FUNCTION public.pickup_reservation_max_window_hours()');
      expect(start, isNot(-1), reason: 'the ceiling function is gone');
      final body = sql.substring(start, start + 400);
      for (final budget in [
        'pickup_reservation_hold_hours',
        'pickup_reservation_max_extensions',
        'pickup_reservation_max_store_extensions',
      ]) {
        expect(body, contains(budget),
            reason: '$budget is not part of the ceiling function — a budget that '
                'the ceiling ignores is a budget the CHECK refuses, so the RPC '
                'would raise a constraint violation instead of granting');
      }
      // ...and the CHECK must read that ceiling rather than the customer's.
      expect(
        sql,
        contains('pickup_reservation_max_window_hours() * interval'),
        reason: 'the table CHECK stopped using the summed ceiling — a store '
            'grant would then fail as an unexplained 23514',
      );
    });

    test('both budgets are capped by their OWN CHECK constraint', () {
      // The customer's cap and the store's cap are separate columns, so they are
      // separate constraints: one counter reaching its ceiling must not consume
      // the other's.
      expect(sql, contains('pickup_reservations_within_extension_cap'));
      expect(
        sql,
        contains('store_extension_count <='
            ' public.pickup_reservation_max_store_extensions()'),
        reason: 'the store counter is not bounded by the store budget, so a '
            'hand-written UPDATE could grant unlimited goodwill',
      );
    });

    test('the grant RPC and its parameters exist on the server', () {
      expect(service, contains('grant_pickup_extension'));
      expect(storeSql, contains('FUNCTION public.grant_pickup_extension'),
          reason: 'the service calls an RPC the migration does not define');
      for (final param in ['p_reservation_id', 'p_reason']) {
        expect(service, contains("'$param'"),
            reason: '$param is declared in SQL but never sent');
        expect(storeSql, contains(param),
            reason: '$param is sent by the client but not declared in SQL');
      }
      // The client must be able to read its own trail back.
      expect(serviceCode,
          contains("from('pickup_reservation_extension_grants')"));
      expect(storeSqlCode, contains('public.pickup_reservation_extension_grants'));
    });

    test('the two extension paths stay two RPCs', () {
      // "The customer asked" and "we chose to give them more time" must never be
      // one call with a flag: the reason and the separate budget are what make a
      // goodwill grant auditable. Each RPC is defined in exactly one file, so
      // re-applying one can never shadow the other.
      expect(
        sqlCode,
        contains('CREATE OR REPLACE FUNCTION public.extend_pickup_reservation'),
      );
      expect(
        storeSqlCode,
        isNot(contains('CREATE OR REPLACE FUNCTION public.extend_pickup_reservation')),
        reason: 'the store migration REDEFINES the customer RPC — the two paths '
            'would then be one function with two meanings, and re-applying this '
            'file would silently revert edits to the customer one',
      );
      expect(storeSqlCode,
          contains('CREATE OR REPLACE FUNCTION public.grant_pickup_extension'));
      expect(
        sqlCode,
        isNot(contains('grant_pickup_extension')),
        reason: 'the grant RPC lives in the base file too — the budget it spends '
            'is a LATER decision than the ceiling CHECK that must allow for it',
      );
    });

    test('a grant spends the STORE budget only', () {
      // The UPDATE is the one place the two counters could be crossed, and a
      // crossed counter is invisible: the hold still moves, but the customer's
      // own extension disappears (or the store gets a second grant for free).
      final rpc = grantRpc();
      final start = rpc.indexOf('UPDATE public.pickup_reservations');
      expect(start, isNot(-1), reason: 'the grant RPC no longer moves a hold');
      final update = rpc.substring(start);
      expect(
        RegExp(r'store_extension_count\s*=\s*store_extension_count \+ 1')
            .hasMatch(update),
        isTrue,
        reason: 'the grant does not spend the store\'s own budget — it would '
            'be unbounded',
      );
      // The lookbehind matters: `store_extension_count` CONTAINS
      // `extension_count`, so a plain substring check here would fail on the
      // correct code and pass on the bug.
      expect(
        RegExp(r'(?<!_)extension_count\s*=').hasMatch(update),
        isFalse,
        reason: 'the grant touches the CUSTOMER\'s counter — the two budgets '
            'are meant to be independent',
      );
      // And it must re-arm the reminder, or the granted deadline is the one
      // deadline nobody is warned about.
      expect(
        RegExp(r'reminder_sent_at\s*=\s*NULL').hasMatch(update),
        isTrue,
        reason: 'the new deadline needs its own T-2h warning',
      );
    });

    test('every code the grant RPC raises is mapped to friendly copy', () {
      final raised = RegExp(r"RAISE EXCEPTION '([A-Z_]+)")
          .allMatches(storeSqlCode)
          .map((m) => m.group(1)!)
          .toSet();
      expect(raised, isNotEmpty,
          reason: 'this guard stopped reading the RPC — fix it, do not delete it');
      for (final code in raised) {
        expect(serviceCode, contains(code),
            reason: '$code is raised by grant_pickup_extension but has no case '
                'in the mapper, so it reaches the seller as a generic failure');
      }
      // The two codes that only this path can produce.
      expect(raised, contains('STORE_EXTENSION_LIMIT_REACHED'));
      expect(raised, contains('INVALID_REASON'));
    });

    test('the reason bound is the same on both sides', () {
      // SQL is authoritative: a row must be impossible to insert unexplained.
      expect(storeSqlCode,
          contains('CHECK (length(btrim(reason)) BETWEEN 3 AND 280)'));
      // ...and the dialog must neither accept what the server refuses nor
      // refuse what the server would accept.
      expect(sellerUi, contains('280'));
      expect(sellerUi, contains('reason.length < 3'),
          reason: 'the dialog would let an empty reason through to a server '
              'rejection — after the seller has already explained themselves to '
              'a customer on the phone');
      // The copy the seller sees on that rejection quotes the same bound.
      expect(serviceCode, contains('3-280'));
    });

    test('the audit trail records who, what and why', () {
      final columns = grantColumns();
      expect(columns, isNotEmpty,
          reason: 'this guard stopped parsing the trail table');
      for (final column in ['granted_by', 'reason', 'previous_deadline',
        'new_deadline', 'hours_granted']) {
        expect(columns, contains(column),
            reason: 'the trail lost `$column`, which is what makes a moved '
                'deadline explainable');
      }
      // The actor's name may be lost, the record may not: an admin deleting the
      // seller account must not delete the fact that a favour happened.
      expect(
        RegExp(r'granted_by\s+UUID REFERENCES public\.profiles\(id\)\s+'
                r'ON DELETE SET NULL')
            .hasMatch(storeSqlCode),
        isTrue,
        reason: 'deleting the granting seller now deletes the grant itself',
      );
    });

    test('the columns the model selects are the columns the table has', () {
      // A renamed column would otherwise reach the UI as a silent null: the
      // grant renders with no reason, which is exactly the state this feature
      // exists to prevent.
      final declared = grantColumns();
      final selected = selectedColumns();
      expect(selected, contains('reason'));
      for (final column in selected) {
        expect(declared, contains(column),
            reason: 'the app selects `$column`, which the trail table does not '
                'declare');
      }
      // Both sides should cover the whole row, not a lucky subset.
      expect(selected.toSet(), declared.toSet());
    });

    test('the trail is SELECT-only, private and device-gated', () {
      expect(
        storeSql,
        contains('ALTER TABLE public.pickup_reservation_extension_grants '
            'ENABLE ROW LEVEL SECURITY'),
      );
      // One write path (the RPC), so a hand-crafted INSERT cannot fabricate a
      // trail — the same stance the hold table takes about stock.
      for (final verb in ['INSERT', 'UPDATE', 'DELETE']) {
        expect(
          RegExp('ON public\\.pickup_reservation_extension_grants\\s+FOR $verb')
              .hasMatch(storeSqlCode),
          isFalse,
          reason: 'the trail is writable through a $verb policy — a grant would '
              'then exist with no deadline change behind it',
        );
      }
      // The trail names customers and stores, so it joins the gate rather than
      // being exempted.
      expect(storeSqlCode, contains('install_device_gate_policies()'),
          reason: 'a new RLS table must be folded into the device gate, or the '
              'pgTAP "every RLS table is gated or exempt" invariant fails and '
              'the table is readable without a trusted device');
    });

    test('the trail is written in the same transaction as the move', () {
      // A grant with no record (or a record with no grant) is the one failure
      // mode an audit trail must not have, so the INSERT has to sit in the RPC
      // that moves the deadline — not in the client, where a dropped response
      // would leave a later deadline unexplained forever.
      final rpc = grantRpc();
      expect(rpc, contains('UPDATE public.pickup_reservations'));
      expect(rpc, contains('INSERT INTO public.pickup_reservation_extension_grants'));
      // ...and the client never writes the table itself.
      expect(serviceCode, isNot(contains('.insert(')),
          reason: 'the trail is being written from the app — a dropped response '
              'would leave a moved deadline with no explanation');
    });

    test('the customer is told WHY, not just that it moved', () {
      // The whole point of making the store's favour explicit is that the
      // customer can see the gesture. A notification without the reason reads
      // like a glitch.
      final rpc = grantRpc();
      expect(RegExp(r'INSERT INTO public\.notifications').hasMatch(rpc), isTrue,
          reason: 'the customer is never told their hold grew');
      expect(rpc, contains('v_reason'),
          reason: 'the notification does not include the reason');
      // ...and it is the customer, not the seller, receiving it.
      expect(rpc, contains("'The store extended your pickup hold'"));
    });
  });

  group('the counter code', () {
    /// The literal `pickup_code_alphabet()` returns, read from the function
    /// rather than from its doc comment.
    String alphabetLiteral() {
      final match = RegExp(r"pickup_code_alphabet\(\)[\s\S]{0,140}?SELECT '([^']+)'")
          .firstMatch(codeSql);
      expect(
        match,
        isNotNull,
        reason: 'pickup_code_alphabet() no longer returns a literal SELECT — '
            'update this guard, do not delete it',
      );
      return match!.group(1)!;
    }

    test('the app, the generator and the column CHECK share one alphabet', () {
      // Three copies of the same 30 symbols, and none is the source of truth:
      // the generator draws codes from the SQL one, the CHECK decides whether a
      // row may exist at all, and the app validates and groups with the Dart
      // one. If they drift, a generated code is rejected by the CHECK (every
      // request fails) or the app's grouping silently changes which code the
      // seller is shown.
      expect(PickupReservation.codeAlphabet, alphabetLiteral(),
          reason: 'the app and the SQL generator disagree on the alphabet');

      final check = RegExp(r"pickup_code ~ '\^\[([^\]]+)\]\{(\d+)\}\$'")
          .firstMatch(sqlCode);
      expect(
        check,
        isNotNull,
        reason: 'the pickup_code CHECK is no longer a plain character class '
            'this guard can read',
      );
      expect(check!.group(1), PickupReservation.codeAlphabet,
          reason: 'the column CHECK accepts symbols the generator can produce '
              '(or rejects ones it does) — a generated code would be '
              'un-insertable');
      expect(int.parse(check.group(2)!), PickupReservation.codeLength,
          reason: 'the code length in the CHECK and in the app have drifted');
    });

    test('the code length is the SQL function, not a second literal', () {
      final match =
          RegExp(r'pickup_code_length\(\)[\s\S]{0,140}?SELECT (\d+)')
              .firstMatch(codeSql);
      expect(match, isNotNull,
          reason: 'pickup_code_length() no longer returns a literal SELECT');
      expect(PickupReservation.codeLength, int.parse(match!.group(1)!));

      // The label groups exactly one code length's worth of characters, so a
      // length that drifts would mis-group every code the customer reads out.
      expect(customerUi, contains('pickupCodeLabel'),
          reason: 'the customer is never shown the code they are meant to read '
              'out at the counter');
    });

    test('the app normalises the way the server does, and invents nothing', () {
      // Both sides upper-case and strip separators; NEITHER folds look-alikes,
      // so a mistyped code can never normalise into somebody else's hold.
      final body = codeSql.substring(
          codeSql.indexOf('FUNCTION public.normalize_pickup_code'));
      expect(body, contains("'[^A-Za-z0-9]'"),
          reason: 'the server stopped stripping only separators');
      expect(body, contains('upper('));
      expect(PickupReservation.normalizeCode(' 4f 7k-2q '), '4F7K2Q');
      expect(PickupReservation.normalizeCode('0O1IL'), '0O1IL');
    });

    test('the seller reaches a hold through the server, one call at a time',
        () {
      // The store scoping is the RPC's (`stores.owner_id = auth.uid()`), so a
      // hand-crafted client cannot look up another store's code — and the app
      // must not try to do that filtering itself.
      expect(codeSqlCode, contains('find_pickup_reservation_by_code'));
      // The scope is ownership, checked by a JOIN rather than by trusting a
      // store id the caller passed in.
      expect(codeSqlCode, contains('JOIN public.stores s ON s.id = r.store_id'));
      expect(codeSqlCode, contains('AND s.owner_id = v_actor'));
      expect(codeSqlCode, contains('v_actor uuid := auth.uid()'));
      expect(sellerUi, contains('resolveCode'));

      // Fulfilment from a code is ONE call, and it delegates rather than
      // repeating the rules: a second copy of the stock/order logic is how the
      // two would quietly diverge.
      final fulfil = codeSqlCode.substring(
          codeSqlCode.indexOf('FUNCTION public.fulfill_pickup_reservation_by_code'));
      expect(fulfil, contains('fulfill_pickup_reservation('),
          reason: 'the counter flow re-implements fulfilment instead of '
              'delegating to it');
      expect(sellerUi, contains('fulfillByCode'));
    });

    test('the app never mints or stores a code itself', () {
      // A code is what proves a hold is the customer's, so it is assigned by the
      // BEFORE INSERT trigger (`assign_pickup_code`) — not by the client, whose
      // dropped response would leave a hold the customer cannot collect.
      expect(codeSqlCode, contains('assign_pickup_code'));
      expect(codeSqlCode, contains('BEFORE INSERT ON public.pickup_reservations'));
      expect(serviceCode, isNot(contains('generate')),
          reason: 'the app is generating pickup codes; the server assigns them');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // The customer's GOODWILL HISTORY: every grant on their holds, with the
  // reason — including grants whose hold is no longer in the holds list.
  // App-only (the trail is already readable to the customer through RLS), so
  // what needs pinning is the QUERY the screen depends on.
  // ══════════════════════════════════════════════════════════════════
  group("the customer's goodwill history", () {
    /// The customer trail's select, read out of the service: the trail's own
    /// columns plus the embed the history renders from.
    String trailSelect() {
      final start = serviceCode.indexOf('_grantTrailColumns =');
      expect(start, isNot(-1),
          reason: 'the customer trail lost its explicit column list — a schema '
              'rename would start feeding the history silent nulls');
      return serviceCode.substring(start, start + 200);
    }

    test('the history embeds the hold, its product and its store', () {
      // None of those names is on the trail table: it carries ids, the reason
      // and the deadline move. They arrive by embedding the hold, so the embed
      // path is load-bearing. A renamed column renders an empty history instead
      // of failing; a renamed relation is a 400 on the whole query.
      expect(
        trailSelect(),
        contains('pickup_reservations(size, products(name, stores(name)))'),
      );

      // ...and it can only resolve at all through the trail's own FK to the hold.
      expect(
        RegExp(r'reservation_id\s+UUID NOT NULL REFERENCES '
                r'public\.pickup_reservations\(id\)')
            .hasMatch(storeSqlCode),
        isTrue,
        reason: 'the trail no longer FKs the hold, so the embed cannot be '
            'resolved and the history dies rather than degrading',
      );
    });

    test('the embedded `size` is a column the hold actually declares', () {
      // Read from the base migration's table rather than from the select's own
      // text, so this is a check against the schema and not a copy of itself.
      final start = sqlCode.indexOf(
          'CREATE TABLE IF NOT EXISTS public.pickup_reservations');
      expect(start, isNot(-1), reason: 'the hold table moved or was renamed');
      final end = sqlCode.indexOf('\n);', start);
      expect(end, isNot(-1));
      expect(sqlCode.substring(start, end), contains('size'));
    });

    test('the store\'s trail and the customer\'s history are different reads', () {
      // The seller's trail is deliberately a single-table read: the names it
      // needs are on the holds it already has. If one select were shared, either
      // the embed would be dragged into the seller query or the history would
      // lose the names it exists to show.
      expect(
        RegExp(r'\.select\(_grantTrailColumns\)').allMatches(serviceCode).length,
        1,
        reason: 'exactly one query should ask for the embed (the customer\'s)',
      );
      expect(
        RegExp(r'\.select\(_grantColumns\)').allMatches(serviceCode).length,
        1,
        reason: 'the store\'s trail should be the flat one',
      );
    });

    test('the history is never fetched from the holds list', () {
      // The whole point: a grant must stay visible after its hold is collected,
      // released, or past the holds query's LIMIT. A history built by filtering
      // the loaded holds would lose exactly those rows, silently.
      expect(
        RegExp(r'class PickupGoodwillScreen').hasMatch(customerGoodwillUi),
        isTrue,
        reason: 'the history screen moved — update this guard, do not delete it',
      );
      expect(customerGoodwillUi, contains('grants'),
          reason: 'the history no longer renders the trail it is given');
      expect(customerUi, contains('PickupGoodwillScreen('),
          reason: 'the customer screen no longer links to the history');
    });
  });
}
