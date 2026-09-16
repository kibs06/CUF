import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A ratchet on notification RECIPIENTS in the SQL migrations.
///
/// **Why this exists.** `notifications.user_id` is `NOT NULL REFERENCES
/// profiles(id)`. So a recipient that resolves to NULL is not a notification
/// that quietly fails to send — it is a 23502 that aborts the enclosing
/// statement, and where that statement sits in a loop it rolls back the whole
/// batch. That was reproduced for real: one customer-less order in the GCash
/// expiry sweep left EVERY order in the batch uncancelled, because the loop is
/// one statement. See `docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md`.
///
/// The recipient is always read from a column that is NULLABLE in this schema
/// (`orders.customer_id`, `stores.owner_id`) or from a variable holding one, so
/// every site needs a guard — and the guard is invisible at the call site,
/// which is exactly how it gets dropped when code is copied.
///
/// **What this is, honestly.** A ratchet over the *known dangerous shapes*, not
/// a proof. It cannot tell whether a guard is *correct*, only that one is
/// present for the shapes that have actually gone wrong. The behavioural proof
/// is `supabase/tests/notification_recipients.test.sql`; this file exists to
/// cover what that suite cannot reach — the `cron.schedule()` body in
/// `20260809000000`, which no test can call — and to fail loudly if a future
/// insert copies an unguarded recipient.
/// Strip SQL comments before looking for a guard.
///
/// This is not tidiness — it is the difference between a working guard and a
/// decorative one. The first version of this file searched raw text, and the
/// comment explaining the rule (*"\`owner_id IS NOT NULL\` everywhere a store is
/// notified"*) **satisfied the search for the rule itself**: deleting the real
/// `AND s.owner_id IS NOT NULL` still passed, because the prose still matched.
/// A guard that reads comments is worse than no guard, since it reports success
/// while the code is broken.
String stripSqlComments(String sql) {
  // Block comments first, then line comments. String literals containing `--`
  // would defeat this, but no migration message does, and the cost of being
  // wrong here is a false POSITIVE (a guard reported missing), never a false pass.
  var out = sql.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  out = out.replaceAll(RegExp(r'--[^\n]*'), ' ');
  return out;
}

void main() {
  final dir = Directory('supabase/migrations');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Every `INSERT INTO public.notifications …` / `…seller_notifications …`
  /// statement in the migrations, as (file, line, statement text).
  ///
  /// The statement runs from the `INSERT` keyword to the terminating `;` at the
  /// end of a line — none of these inserts contains a nested statement, and a
  /// `;` inside the message text would have to be quoted, which the schema's
  /// text columns never need.
  final inserts = <({String file, int line, String text})>[];
  for (final f in files) {
    final lines = f.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('INSERT INTO public.notifications') &&
          !lines[i].contains('INSERT INTO public.seller_notifications')) {
        continue;
      }
      final buf = StringBuffer();
      for (var j = i; j < lines.length; j++) {
        buf.writeln(lines[j]);
        if (lines[j].trimRight().endsWith(';')) break;
      }
      inserts.add((
        file: f.path.replaceAll(r'\', '/').split('/').last,
        line: i + 1,
        text: stripSqlComments(buf.toString()),
      ));
    }
  }

  /// The body of the function/trigger enclosing [line], so a guard is searched
  /// for where it can actually apply.
  ///
  /// A fixed line-window was tried first and was the wrong tool: the guard sits
  /// an arbitrary distance above the insert (a long explanatory comment can push
  /// it out of the window), and widening the window trades a false failure for a
  /// false pass. The enclosing function is the real scope of a local variable.
  String enclosingFunctionBody(String fileName, int line) {
    final f = files.firstWhere((f) => f.path.replaceAll(r'\', '/').endsWith(fileName));
    final lines = f.readAsStringSync().split('\n');
    var start = 0;
    for (var i = line - 1; i >= 0; i--) {
      if (RegExp(r'CREATE (OR REPLACE )?FUNCTION').hasMatch(lines[i])) {
        start = i;
        break;
      }
    }
    final buf = StringBuffer();
    for (var i = start; i < lines.length; i++) {
      buf.writeln(lines[i]);
      if (i > start && lines[i].trimRight().endsWith(r'$$;')) break;
    }
    return stripSqlComments(buf.toString());
  }

  /// A function body, for the trigger guards.
  String functionBody(String fileName, String name) {
    final f = files.firstWhere((f) => f.path.replaceAll(r'\', '/').endsWith(fileName));
    final src = f.readAsStringSync();
    final start = src.indexOf('FUNCTION public.$name');
    expect(start, greaterThan(-1), reason: 'no function $name in $fileName');
    final end = src.indexOf(r'$$;', start);
    return stripSqlComments(src.substring(start, end == -1 ? src.length : end));
  }

  test('the scanner actually finds the inserts (a silent no-op guard is worse '
      'than none)', () {
    // 39 in `notifications` + 1 in `seller_notifications` when this was written.
    // A floor, not an exact count: adding notifications must not fail this test,
    // removing them by accident should.
    expect(inserts.length, greaterThanOrEqualTo(39));
    expect(inserts.map((e) => e.file).toSet().length, greaterThanOrEqualTo(10));
  });

  group('a NULL recipient is a failed transaction, so every site is guarded',
      () {
    test('store-owner recipients filter on owner_id (stores.owner_id is '
        'NULLABLE)', () {
      // `INSERT … SELECT s.owner_id …` — the WHERE has to exclude a store with
      // no owner, or the insert raises instead of sending nothing.
      final offenders = inserts
          .where((e) => RegExp(r'SELECT\s+\w+\.owner_id\s*,').hasMatch(e.text))
          .where((e) => !e.text.contains('owner_id IS NOT NULL'))
          .toList();
      expect(
        offenders.map((e) => '${e.file}:${e.line}').toList(),
        isEmpty,
        reason: 'an unguarded SELECT owner_id in a notification insert',
      );
    });

    test('order-customer recipients filter on customer_id in a SELECT '
        '(orders.customer_id is NULLABLE)', () {
      final offenders = inserts
          .where((e) => RegExp(r'SELECT\s+\w+\.customer_id\s*,').hasMatch(e.text))
          .where((e) => !e.text.contains('customer_id IS NOT NULL'))
          .toList();
      expect(
        offenders.map((e) => '${e.file}:${e.line}').toList(),
        isEmpty,
        reason: 'an unguarded SELECT customer_id in a notification insert',
      );
    });

    test("the order triggers check new.customer_id before using it (they fire "
        'AFTER INSERT/UPDATE, so a raise rejects the ORDER)', () {
      final body = functionBody('20260702_notifications.sql',
          'notify_on_order_insert');
      expect(body, contains('new.customer_id'));
      expect(
        body.contains('new.customer_id IS NOT NULL') ||
            body.contains('new.customer_id IS NULL'),
        isTrue,
        reason: 'notify_on_order_insert notifies new.customer_id unguarded',
      );

      final statusBody = functionBody(
          '20260702_notifications.sql', 'notify_on_order_status_change');
      expect(
        statusBody.contains('new.customer_id IS NOT NULL') ||
            statusBody.contains('new.customer_id IS NULL'),
        isTrue,
        reason: 'notify_on_order_status_change notifies new.customer_id '
            'unguarded',
      );
    });

    test('a VALUES insert whose recipient is a variable carries a guard NAMED '
        'for that variable, in the scope that variable lives in', () {
      // These are the sites that read a nullable column (or `auth.uid()`) into
      // a local and then use it as the recipient, so the guard has to name the
      // variable — `IF v_customer_id IS NOT NULL THEN`. Searching for a bare
      // `IS NOT NULL` anywhere nearby would be satisfied by an unrelated check
      // (`IF v_updated = 0`), and searching a line-window would miss a guard
      // pushed down by a comment.
      final pattern = RegExp(
        r'VALUES\s*\(\s*(\n\s*)?'
        r'(v_customer_id|v_owner_id|v_owner|v_recipient|v_customer|v_store_owner|CASE)\b',
      );
      // `v_owners[v_at]` is the ONE accumulator in the codebase: it is appended
      // to only inside `IF v_row.owner_id IS NOT NULL THEN`, so it cannot hold a
      // NULL. The pgTAP suite asserts that behaviour directly (the "store gets
      // ONE aggregated summary" case); a per-variable name search would demand
      // `v_owners IS NOT NULL`, which does not exist and should not.
      const exempt = {'v_owners'};

      final offenders = <String>[];
      for (final e in inserts) {
        final m = pattern.firstMatch(e.text);
        if (m == null) continue;
        final variable = m.group(2)!;
        if (exempt.contains(variable)) continue;
        final body = enclosingFunctionBody(e.file, e.line);
        if (!body.contains('$variable IS NOT NULL') &&
            !body.contains('$variable IS NULL')) {
          offenders.add('${e.file}:${e.line} ($variable)');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'a variable recipient with no guard naming it',
      );
    });

    test('a VALUES insert whose recipient is a raw column is guarded too '
        '(seller_notifications.store_id is NOT NULL)', () {
      // `seller_notifications` is keyed by STORE, not user, so the failure is
      // the same shape: `orders.store_id` is nullable and the insert is inside
      // the customer's own transaction.
      final storeInserts = inserts
          .where((e) => e.text.contains('INSERT INTO public.seller_notifications'))
          .toList();
      expect(storeInserts, isNotEmpty, reason: 'expected at least one site');
      for (final e in storeInserts) {
        final body = enclosingFunctionBody(e.file, e.line);
        expect(
          body.contains('v_store_id IS NOT NULL') ||
              e.text.contains('store_id IS NOT NULL'),
          isTrue,
          reason: '${e.file}:${e.line} uses a nullable store_id unguarded',
        );
      }
    });
  });

  test('the two expiry paths that send a customer notification are both '
      'guarded — including the one no test can call', () {
    // `cancel_my_pending_payment_intent` is callable; the pg_cron body in
    // 20260809000000 is a string handed to `cron.schedule()` and cannot be
    // invoked from a test at all, which is precisely why the source is checked.
    final cronFile = files.firstWhere(
        (f) => f.path.replaceAll(r'\', '/').endsWith('20260809000000_revive_paymongo_online_gcash.sql'));
    final src = cronFile.readAsStringSync();
    expect(src, contains(r'cron.schedule('));
    expect(src, contains('o.customer_id IS NOT NULL'),
        reason: 'the cron-body sweep lost its recipient guard');
  });
}
