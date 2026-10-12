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

    test('same_password names the real problem (recovery screen)', () {
      // Reachable from ResetPasswordScreen: GoTrue refuses a "new" password
      // that matches the current one. "Too weak" would be the wrong story, and
      // a generic failure leaves the customer with no idea what to change.
      const e = AuthException(
        'New password should be different from the old password.',
        code: 'same_password',
      );
      expect(
        friendlyAuthError(e),
        'That is already your password — choose a different one.',
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

    test('a server 5xx is not reported as a connection problem', () {
      // gotrue throws AuthRetryableFetchException for HTTP 500 too, with the
      // status set. The reset-password 500 (a broken mail relay) used to read
      // "couldn't reach CUFMAI" while the connection was fine.
      final message = friendlyAuthErrorMessage(
        AuthRetryableFetchException(
          message: 'Unable to process request',
          statusCode: '500',
        ),
      );
      expect(message, authErrorServer);
      expect(message, isNot(contains('connection')));
      expect(message, isNot(contains("couldn't reach")));
    });

    test('a 5xx body keeps its own error_code — it is not flattened', () {
      // gotrue's `_handleError` turns EVERY status >= 500 into an
      // AuthRetryableFetchException and never reads the body's `error_code`,
      // so before this the mapper's code-keyed branches were unreachable for
      // the failures this project actually hits. Measured on the live project
      // (Oct 12, 2026), `POST /auth/v1/recover` answers exactly:
      //   500 {"code":500,"error_code":"unexpected_failure",
      //        "msg":"Error sending recovery email"}
      final message = friendlyAuthErrorMessage(
        AuthRetryableFetchException(
          message: '{"code":500,"error_code":"unexpected_failure",'
              '"msg":"Error sending recovery email",'
              '"error_id":"01a12f97-68f6-7eb2-8b0e-7f214a2d9c5a"}',
          statusCode: '500',
        ),
      );
      expect(message, authErrorMailNotSent);
      // The wrong advice for a mailer that cannot send: retrying is the one
      // thing that cannot work, so the copy must not offer it.
      expect(message, isNot(contains('try again')));
      expect(message, isNot(contains('connection')));
      // ...and none of the server's own text reaches the user.
      expect(message, isNot(contains('unexpected_failure')));
      expect(message, isNot(contains('Error sending recovery email')));
      expect(message, isNot(contains('01a12f97')));
    });

    test('a rate limit carried in a 5xx body still reads as a rate limit', () {
      final message = friendlyAuthErrorMessage(
        AuthRetryableFetchException(
          message:
              '{"code":500,"error_code":"over_email_send_rate_limit",'
              '"msg":"email rate limit exceeded"}',
          statusCode: '500',
        ),
      );
      expect(message, 'Too many attempts. Try again in about a minute.');
    });

    test('a 5xx body that is not JSON falls back to the server copy', () {
      // An HTML error page from a proxy, a truncated body, an empty one: there
      // is no code to read, so the generic server message still applies.
      for (final body in <String?>[
        '<html><body>502 Bad Gateway</body></html>',
        '{"code":500,',
        '',
        null,
      ]) {
        final message = friendlyAuthErrorMessage(
          AuthRetryableFetchException(
            message: body ?? 'AuthRetryableFetchException',
            statusCode: '502',
          ),
        );
        expect(message, authErrorServer, reason: '$body');
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
