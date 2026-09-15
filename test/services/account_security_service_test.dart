import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/services/account_security_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// A real [PostgrestFilterBuilder] that resolves to [value] (or rejects with
/// [error]) — the same technique as order_service_test.dart, because
/// mocktail cannot match on a Future-implementing mock's `.then`.
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

  /// Delegates to a REAL Future rather than throwing inside `then`.
  ///
  /// Throwing here is not the same thing: `await` on a Future-implementing
  /// builder goes through `then(onValue, onError:)`, and an error thrown out
  /// of `then` bypasses the caller's `onError` path and lands in the zone as
  /// an unhandled async error — so the service's own `catch` never runs and
  /// the test hangs instead of asserting. Completing a real Future with the
  /// error reproduces what the live client does.
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

void main() {
  late MockSupabaseClient mockClient;
  late AccountSecurityService service;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    service = AccountSecurityService(client: mockClient);
  });

  void stubRpc({dynamic value, Object? error}) {
    // thenAnswer, not thenReturn: PostgrestFilterBuilder implements Future,
    // and mocktail rejects a Future from thenReturn.
    when(
      () => mockClient.rpc(any(), params: any(named: 'params')),
    ).thenAnswer((_) => FakeRpcBuilder(value: value, error: error));
  }

  group('AccountSecurityService.fetchOverview', () {
    test('calls the admin RPC with the subject as p_user_id', () async {
      stubRpc(value: {'account': {'user_id': 'u-1'}, 'devices': []});

      await service.fetchOverview('u-1');

      final captured = verify(
        () => mockClient.rpc(
          captureAny(),
          params: captureAny(named: 'params'),
        ),
      ).captured;
      // The subject's id is an ARGUMENT — an admin investigating someone
      // else's account is the entire point of this function.
      expect(captured[0], 'admin_account_security_overview');
      expect(captured[1], {'p_user_id': 'u-1'});
    });

    test('trims the id before sending it', () async {
      stubRpc(value: {'account': {'user_id': 'u-1'}});

      await service.fetchOverview('  u-1  ');

      verify(
        () => mockClient.rpc(any(), params: {'p_user_id': 'u-1'}),
      ).called(1);
    });

    test('parses the payload into the model', () async {
      stubRpc(
        value: {
          'account': {'user_id': 'u-1', 'email': 'a@b.local'},
          'enforcement': {'enabled': true},
          'devices': [
            {
              'device_id': 'phone',
              'has_secret': false,
              'secret_minted_at': null,
            },
          ],
          'cannot_answer': ['nothing about failed attempts'],
        },
      );

      final overview = await service.fetchOverview('u-1');

      expect(overview.account.email, 'a@b.local');
      expect(overview.enforcement.enabled, isTrue);
      expect(overview.devices.single.hasSecret, isFalse);
      expect(overview.cannotAnswer, hasLength(1));
    });

    test('refuses an empty id without a network round trip', () async {
      await expectLater(
        service.fetchOverview('   '),
        throwsA(
          isA<AccountSecurityException>().having(
            (e) => e.message,
            'message',
            contains('account is required'),
          ),
        ),
      );
      verifyNever(() => mockClient.rpc(any(), params: any(named: 'params')));
    });

    test('maps 42501 to a "not an admin" message carrying the code', () async {
      stubRpc(
        error: const PostgrestException(
          message: 'Only an admin can read account security diagnostics',
          code: '42501',
        ),
      );

      await expectLater(
        service.fetchOverview('u-1'),
        throwsA(
          isA<AccountSecurityException>()
              .having((e) => e.code, 'code', '42501')
              .having((e) => e.message, 'message',
                  'Only an admin account can read security diagnostics.'),
        ),
      );
    });

    test('passes the server message through for an unknown account (P0002)',
        () async {
      stubRpc(
        error: const PostgrestException(
          message: 'No account with id 00000000-0000-0000-0000-00000000dead',
          code: 'P0002',
        ),
      );

      await expectLater(
        service.fetchOverview('00000000-0000-0000-0000-00000000dead'),
        throwsA(
          isA<AccountSecurityException>()
              .having((e) => e.code, 'code', 'P0002')
              .having((e) => e.message, 'message', contains('No account with id')),
        ),
      );
    });

    test('reports a network failure as a retryable message, not a raw error',
        () async {
      stubRpc(error: Exception('socket closed'));

      await expectLater(
        service.fetchOverview('u-1'),
        throwsA(
          isA<AccountSecurityException>().having(
            (e) => e.message,
            'message',
            contains('Please try again'),
          ),
        ),
      );
    });

    test('treats an empty document as an error rather than a blank screen',
        () async {
      stubRpc(value: <String, dynamic>{});

      await expectLater(
        service.fetchOverview('u-1'),
        throwsA(
          isA<AccountSecurityException>().having(
            (e) => e.message,
            'message',
            contains('empty security report'),
          ),
        ),
      );
    });
  });
}
