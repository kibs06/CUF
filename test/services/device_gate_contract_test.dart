import 'dart:io';

import 'package:app/services/device_trust_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-artifact guards for the server-side device gate.
///
/// The Flutter client and the SQL it talks to agree on four things that no
/// compiler or type checks: a header NAME, a TOKEN FORMAT, the rollout
/// DEFAULT, and which tables must stay outside the gate. A rename or a
/// "tidy-up" on either side fails silently and loudly respectively — a
/// renamed header means the app is gated out of its own orders, and dropping
/// a bootstrap table from the exemption list deadlocks the step-up against
/// itself (the challenge reads `trusted_devices`).
///
/// These assertions read the migration that implements the gate, so they fail
/// at test time instead of in production.
void main() {
  // The migration that installs the gate — see
  // docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md.
  const migrationPath =
      'supabase/migrations/20260915150000_enforce_trusted_devices.sql';

  late String sql;

  setUpAll(() {
    final file = File(migrationPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'the device-gate migration should exist at $migrationPath',
    );
    sql = file.readAsStringSync();
  });

  /// The body of `device_gate_exempt_tables()` — the exemption list.
  ///
  /// Read from the FUNCTION, not from a local array literal: the list was
  /// hoisted into a function so the installer sweep, the pgTAP guard and
  /// this test all read one source. Anchoring on a literal that no longer
  /// exists is how this guard broke once already (it threw a RangeError
  /// instead of telling anyone the list had moved), so a missing anchor is
  /// reported as a named failure here.
  String exemptionList() {
    final fn = sql.indexOf('device_gate_exempt_tables()');
    expect(
      fn,
      greaterThan(-1),
      reason: 'the device_gate_exempt_tables() function is gone — the '
          'exemption list moved, and whatever holds it now must be checked',
    );
    final start = sql.indexOf('SELECT ARRAY[', fn);
    expect(
      start,
      greaterThan(-1),
      reason: 'the exemption list is no longer a `SELECT ARRAY[...]` inside '
          'device_gate_exempt_tables() — update this guard, do not delete it',
    );
    final end = sql.indexOf('];', start);
    expect(end, greaterThan(start), reason: 'unterminated exemption list');
    return sql.substring(start, end);
  }

  group('the request header name', () {
    test('is the literal the SQL reads out of request.headers', () {
      // The client sends this; PostgREST exposes it as a JSON key under the
      // `request.headers` setting; device_is_trusted() looks it up by name.
      expect(DeviceTrustService.deviceHeaderName, 'x-cufmai-device');
      expect(
        sql,
        contains("->> '${DeviceTrustService.deviceHeaderName}'"),
        reason: 'the migration no longer reads the header the app sends — '
            'every gated table would return empty for every user',
      );
    });
  });

  group('the credential format', () {
    test('is "<device_id>:<secret>"', () {
      expect(
        DeviceTrustService.formatToken('device-1', 'a' * 64),
        'device-1:${'a' * 64}',
      );
    });

    test('splits on the FIRST colon, which is what the SQL assumes', () {
      // device ids are UUIDs today, but if one ever contained a colon the
      // client must still be the one that decides the boundary.
      expect(sql, contains("position(':' in v_raw)"));
      expect(sql, contains('substring(v_raw from v_sep + 1)'));
    });

    test('the server stores a SHA-256 of the secret, never the secret', () {
      expect(sql, contains("extensions.digest(v_secret, 'sha256')"));
      expect(
        sql,
        contains("v_hash = extensions.digest(v_secret, 'sha256')"),
        reason: 'the gate must compare hashes, not plaintext',
      );
    });
  });

  group('the rollout default', () {
    test('enforcement is OFF in the migration, so applying is safe', () {
      // Load-bearing: with it ON from the start, every already-installed
      // client (which sends no header) would lose access to every private
      // table the moment the migration was applied.
      expect(
        sql,
        contains('INSERT INTO public.device_enforcement_policy '
            '(id, enforcement_enabled)\nVALUES (true, false)'),
      );
      expect(
        RegExp(r'enforcement_enabled\s+boolean\s+NOT NULL DEFAULT false')
            .hasMatch(sql),
        isTrue,
        reason: 'the column default is the safety net if the seed row is '
            'ever re-created',
      );
    });
  });

  group('the mint gate', () {
    test('accepts exactly the sessions that proved possession', () {
      // amr otp covers BOTH the signup verification and the new-device
      // challenge (verified against a real stack); magiclink is the same code
      // delivered as a link; aal2 is TOTP MFA.
      expect(sql, contains('@> \'[{"method":"otp"}]\'::jsonb'));
      expect(sql, contains('@> \'[{"method":"magiclink"}]\'::jsonb'));
      expect(sql, contains("(auth.jwt() ->> 'aal') = 'aal2'"));
      // A password-only session must never be in that set.
      expect(
        sql,
        isNot(contains('"method":"password"')),
        reason: 'a password-only session must not be able to mint a secret',
      );
    });

    test('the mint gate is enforced before anything is written', () {
      final gate = sql.indexOf('session_proves_possession()');
      final firstWrite = sql.indexOf(
        'INSERT INTO public.trusted_devices AS td',
      );
      expect(gate, greaterThan(-1));
      expect(firstWrite, greaterThan(-1));
      expect(
        gate,
        lessThan(firstWrite),
        reason: 'the step-up check must come before the row write, or a '
            'password-only session could mint a secret',
      );
    });
  });

  group('bootstrap tables stay outside the gate', () {
    test('every table the step-up itself needs is exempt', () {
      // Each name here has a concrete failure if it is dropped from the
      // exemption list:
      //   profiles / trusted_devices / failed_logins — the app cannot even
      //     render the challenge without them (the challenge reads
      //     trusted_devices, and the lockout counter runs before any step-up)
      //   device_secrets / device_enforcement_policy — internal, no grants
      const required = [
        'profiles',
        'trusted_devices',
        'device_secrets',
        'device_enforcement_policy',
        'failed_logins',
      ];
      final exemptBlock = exemptionList();
      for (final table in required) {
        expect(
          exemptBlock,
          contains("'$table'"),
          reason: '$table must stay exempt or the step-up locks itself out',
        );
      }
    });

    test('the genuinely private tables are NEVER exempt', () {
      // The other half of the pgTAP invariant. That suite proves every RLS
      // table is gated OR exempt — it cannot tell a correct exemption from a
      // careless one, because it reads the same list it is checking. Adding
      // one of these to the list would silently un-protect it everywhere and
      // still pass there; here it fails.
      const mustStayGated = [
        'orders',
        'order_items',
        'cart_items',
        'customer_addresses',
        'payment_intents',
        'messages',
        'conversations',
        'vouchers',
        'voucher_redemptions',
        'sales_transactions',
        'seller_business_docs',
        'deletion_requests',
        'foot_measurements',
      ];
      final exemptBlock = exemptionList();
      for (final table in mustStayGated) {
        expect(
          exemptBlock,
          isNot(contains("'$table'")),
          reason: '$table holds customer-private data — exempting it from the '
              'device gate removes the credential requirement from it',
        );
      }
    });

    test('the installer and the guard read the SAME exemption list', () {
      // The sweep must consume the function rather than re-listing the
      // tables, or the list and the sweep can drift apart.
      expect(
        sql,
        contains('v_exempt  text[] := public.device_gate_exempt_tables()'),
        reason: 'the sweep no longer reads device_gate_exempt_tables() — the '
            'exemption list and the policy sweep can now disagree',
      );
    });

    test('device_secrets is never granted to a client role', () {
      expect(
        sql,
        contains('REVOKE ALL ON public.device_secrets '
            'FROM anon, authenticated, PUBLIC'),
      );
    });

    test('the gate requires a RESTRICTIVE policy, and gates writes too', () {
      // A permissive policy could ADD access; RESTRICTIVE can only subtract.
      // Both USING and WITH CHECK are needed so INSERT/UPDATE are gated too,
      // not just reads.
      expect(sql, contains('AS RESTRICTIVE FOR ALL TO authenticated'));
      expect(sql, contains('WITH CHECK (public.device_is_trusted()'));
    });
  });
}
