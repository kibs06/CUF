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

    test('email_address_invalid', () {
      const e = AuthException('Malformed email', code: 'email_address_invalid');
      expect(
        friendlyAuthError(e),
        "That doesn't look like a valid email address.",
      );
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
  });
}
