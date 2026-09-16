import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/utils/auth_error_messages.dart';

void main() {
  group('friendlyAuthError — keyed on error.code', () {
    test('invalid_credentials → actionable sign-in message', () {
      const e = AuthException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
      expect(
        friendlyAuthError(e),
        "That email or password isn't right. Double-check and try again, "
        'or reset your password.',
      );
    });

    test('user_not_found shares the invalid_credentials message '
        '(no account-existence leak)', () {
      const notFound =
          AuthException('User not found', code: 'user_not_found');
      const badCreds =
          AuthException('Invalid login credentials', code: 'invalid_credentials');
      expect(friendlyAuthError(notFound), friendlyAuthError(badCreds));
    });

    test('email_not_confirmed → check your inbox', () {
      const e = AuthException('Email not confirmed', code: 'email_not_confirmed');
      expect(
        friendlyAuthError(e),
        'Confirm your email first — check your inbox for the link we sent.',
      );
    });

    test('user_already_exists and email_exists map to the same message', () {
      const existing =
          AuthException('already exists', code: 'user_already_exists');
      const emailExisting =
          AuthException('already exists', code: 'email_exists');
      final expected = 'An account with this email already exists. '
          'Try logging in instead.';
      expect(friendlyAuthError(existing), expected);
      expect(friendlyAuthError(emailExisting), expected);
    });

    test('weak_password by code', () {
      const e = AuthException(
        'Password should be at least 6 characters',
        code: 'weak_password',
      );
      expect(
        friendlyAuthError(e),
        "That password's too weak. Use at least 6 characters.",
      );
    });

    test('AuthWeakPasswordException (SDK subtype) maps the same way', () {
      final e = AuthWeakPasswordException(
        message: 'Password should be at least 6 characters',
        statusCode: '422',
        reasons: const ['6 characters'],
      );
      expect(
        friendlyAuthError(e),
        "That password's too weak. Use at least 6 characters.",
      );
    });

    test('email_address_invalid does not assume the address is malformed', () {
      // GoTrue returned this for a well-formed Gmail address on the live
      // project, so the copy must fit a correct address too — it may only
      // point at the possibility of a typo.
      const e = AuthException('Malformed email', code: 'email_address_invalid');
      final message = friendlyAuthError(e);
      expect(message, contains('rejected'));
      expect(message, contains('typos'));
      expect(message, isNot(contains("doesn't look like")));
    });

    test('email_address_not_authorized reads as a delivery problem, not the '
        'user\'s address', () {
      const e = AuthException(
        'Email address not authorized',
        statusCode: '422',
        code: 'email_address_not_authorized',
      );
      final message = friendlyAuthError(e);
      expect(message, contains("couldn't deliver"));
      expect(message, contains('support'));
      // The tempting-but-wrong copy: the user cannot fix a server refusal by
      // re-typing their own address.
      expect(message, isNot(contains('check it for typos')));
    });

    test('over_email_send_rate_limit', () {
      const e =
          AuthException('Rate limit', code: 'over_email_send_rate_limit');
      expect(
        friendlyAuthError(e),
        'Too many attempts. Try again in about a minute.',
      );
    });

    test('over_request_rate_limit', () {
      const e = AuthException('Rate limit', code: 'over_request_rate_limit');
      expect(
        friendlyAuthError(e),
        'Too many attempts. Wait a moment and try again.',
      );
    });

    test('signup_disabled', () {
      const e = AuthException('Signups disabled', code: 'signup_disabled');
      expect(
        friendlyAuthError(e),
        'New sign-ups are temporarily unavailable. Please try again later.',
      );
    });

    test('unknown code falls back to generic and hides raw details', () {
      final message = friendlyAuthError(
        const AuthException('secret server detail', statusCode: '418', code: 'mystery_code'),
      );
      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('secret server detail')));
      expect(message, isNot(contains('mystery_code')));
      expect(message, isNot(contains('418')));
    });

    test('missing code (pre-response network failure) is generic', () {
      final message = friendlyAuthError(const AuthException('network hiccup'));
      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('network hiccup')));
    });
  });

  group('friendlyAuthErrorMessage — anything thrown from an auth call', () {
    test('routes AuthException through the code-keyed mapper', () {
      const e = AuthException('nope', code: 'invalid_credentials');
      expect(
        friendlyAuthErrorMessage(e),
        friendlyAuthError(e),
      );
    });

    test('non-auth exceptions reduce to a generic message without leaking', () {
      final message = friendlyAuthErrorMessage(
        StateError('boom at file.dart:42'),
      );
      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('boom')));
      expect(message, isNot(contains('file.dart')));
    });

    test('a transport failure never reads as a rejected password', () {
      // Measured on the emulator: with the device offline, five taps on
      // "Log In" locked the account out for 30 minutes. The copy the user
      // saw blamed their password, which the device never sent.
      for (final error in <Object>[
        AuthRetryableFetchException(),
        SocketException('Failed host lookup: psczvbfoybqhjeqssimw.supabase.co'),
        TimeoutException('no response', const Duration(seconds: 30)),
      ]) {
        final message = friendlyAuthErrorMessage(error);
        expect(message, authErrorNetwork, reason: '$error');
        expect(message, contains('connection'));
        expect(message, isNot(contains("isn't right")));
        expect(message, isNot(contains('reset your password')));
      }
    });
  });

  group('isCredentialRejection — what may move the lockout counter', () {
    test('a wrong password (or an unknown account) counts', () {
      expect(
        isCredentialRejection(
          const AuthException('Invalid login credentials',
              statusCode: '400', code: 'invalid_credentials'),
        ),
        isTrue,
      );
      expect(
        isCredentialRejection(
          const AuthException('User not found', code: 'user_not_found'),
        ),
        isTrue,
      );
    });

    test('transport failures do not — the password was never judged', () {
      expect(isCredentialRejection(AuthRetryableFetchException()), isFalse);
      expect(isCredentialRejection(SocketException('unreachable')), isFalse);
      expect(
        isCredentialRejection(
          TimeoutException('timed out', const Duration(seconds: 8)),
        ),
        isFalse,
      );
    });

    test('server-side refusals that are not about the password do not count',
        () {
      // Rate limits, a mailer refusal or a 5xx are not brute-force evidence;
      // counting them locks out users who typed nothing wrong.
      for (final code in <String>[
        'over_request_rate_limit',
        'over_email_send_rate_limit',
        'email_address_invalid',
        'email_address_not_authorized',
        'signup_disabled',
      ]) {
        expect(
          isCredentialRejection(AuthException('server said no', code: code)),
          isFalse,
          reason: code,
        );
      }
      expect(
        isCredentialRejection(const AuthException('fetch failed')),
        isFalse,
      );
      expect(isCredentialRejection(StateError('boom')), isFalse);
    });
  });
}
