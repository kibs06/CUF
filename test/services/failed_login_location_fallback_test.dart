import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/services/auth_service.dart';

/// The rule that decides whether a lockout keeps its device/IP evidence when
/// the location columns are not in the database yet.
///
/// `advanceFailedCounter` writes the geo fields in the SAME upsert as
/// `ip_address`/`user_agent`, and PostgREST refuses the whole row when any one
/// of them is unknown. So this predicate is the difference between "the lockout
/// is recorded without a location" and "the lockout is not recorded at all" —
/// and between a fallback and a real failure being swallowed.
void main() {
  PostgrestException error({String? code, required String message}) =>
      PostgrestException(message: message, code: code);

  group('AuthService.isUnknownLocationColumn — the migration is missing', () {
    test('names the column, in the wording PostgREST actually uses', () {
      // Measured shape of the answer when a payload column does not exist.
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: 'PGRST204',
            message:
                "Could not find the 'location' column of 'failed_logins' in "
                'the schema cache',
          ),
        ),
        isTrue,
      );
    });

    test('recognises the LATITUDE wording, which is the one it really sends',
        () {
      // Copied verbatim from a live PostgREST answer (local stack, columns
      // dropped, the app's own payload posted, 2026-10-12). PostgREST reports
      // the FIRST unknown key, and in this payload that is `latitude` — a
      // message containing the string "location" nowhere at all. Matching on
      // `location` alone let the write fail instead of falling back.
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: 'PGRST204',
            message: "Could not find the 'latitude' column of 'failed_logins' "
                'in the schema cache',
          ),
        ),
        isTrue,
      );

      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: 'PGRST204',
            message: "Could not find the 'longitude' column of 'failed_logins' "
                'in the schema cache',
          ),
        ),
        isTrue,
      );
    });

    test('accepts Postgres\' own undefined_column (42703)', () {
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: '42703',
            message: 'column "location" of relation "failed_logins" '
                'does not exist',
          ),
        ),
        isTrue,
      );
    });

    test('does not depend on the code, only on the diagnosis', () {
      // A managed client can report the same failure without a code.
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            message: 'column "location" does not exist',
          ),
        ),
        isTrue,
      );
    });
  });

  group('AuthService.isUnknownLocationColumn — it is a real failure', () {
    test('a policy refusal is not a missing column', () {
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: '42501',
            message: 'new row violates row-level security policy for table '
                '"failed_logins"',
          ),
        ),
        isFalse,
      );
    });

    test('a missing column that is NOT the location one is not ours to fix',
        () {
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: 'PGRST204',
            message: "Could not find the 'attempt_count' column of "
                "'failed_logins' in the schema cache",
          ),
        ),
        isFalse,
      );
    });

    test('a constraint violation is not a missing column', () {
      expect(
        AuthService.isUnknownLocationColumn(
          error(
            code: '23505',
            message: 'duplicate key value violates unique constraint '
                '"uq_user_active_failed"',
          ),
        ),
        isFalse,
      );
    });

    test('a network fault carries no diagnosis to act on', () {
      expect(
        AuthService.isUnknownLocationColumn(
          error(message: 'Connection refused'),
        ),
        isFalse,
      );
    });
  });

  /// A source contract, in the same spirit as `device_gate_contract_test.dart`:
  /// the lockout write is the one place a whole security feature's evidence is
  /// persisted, and the mechanism it must NOT go back to is invisible from the
  /// outside — it fails inside Postgres and the caller treats the write as
  /// best-effort.
  group('the lockout write — the mechanism, checked against the source', () {
    late String advance;

    /// The code, without the commentary: the helper's own doc explains the
    /// upsert it replaced, and a contract about what the code DOES must not
    /// trip over a sentence describing what it does not do. (`//` is a comment
    /// marker and not part of any string in this window.)
    String codeOnly(String text) => text
        .split('\n')
        .map((line) {
          final marker = line.indexOf('//');
          return marker >= 0 ? line.substring(0, marker) : line;
        })
        .join('\n');

    setUpAll(() {
      final source = File('lib/services/auth_service.dart').readAsStringSync();
      final start = source.indexOf('advanceFailedCounter({');
      expect(start, greaterThan(-1), reason: 'the method is still there');
      // To the end of the write helper: `resetFailedCounter` is the next method
      // after it, and the write itself lives in the helper.
      final end = source.indexOf('Future<void> resetFailedCounter');
      expect(end, greaterThan(start));
      advance = codeOnly(source.substring(start, end));
    });

    test('the lockout write does not use an upsert on user_id', () {
      // Measured against a real PostgREST (local stack, 2026-10-12): the only
      // unique index on `user_id` is PARTIAL, so `on_conflict=user_id` answers
      // 42P10 and EVERY lockout write failed — silently, because the caller
      // catches it. Device, IP and location were never recorded.
      expect(advance, isNot(contains("onConflict: 'user_id'")));
      expect(advance, isNot(contains('upsert(')));
    });

    test('it updates the account\'s existing row by id, or inserts one', () {
      expect(advance, contains('.insert(values)'));
      expect(advance, contains(".update(values).eq('id', existingId)"));
      // The id has to be READ for that, from the same row lookup the counter
      // already does.
      expect(
        advance,
        contains(".select('id, attempt_count, locked_until, status')"),
      );
    });

    test('the fallback drops all three geo keys before retrying', () {
      // Only `location` mattered to the predicate's first draft; the column
      // that has to go is whichever PostgREST names first, so all three are
      // removed from the payload.
      expect(advance, contains("row.remove('location')"));
      expect(advance, contains("row.remove('latitude')"));
      expect(advance, contains("row.remove('longitude')"));
    });
  });
}
