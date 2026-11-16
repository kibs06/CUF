import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/utils/auth_error_messages.dart';

/// Stand-in for the process-wide Google SDK singleton, which cannot be built in
/// a test (private constructor, platform plugin behind every call).
class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

/// The two contracts `google_sign_in` 7.x puts on this app, neither of which a
/// build check can see:
///
///  1. `initialize()` runs exactly once per process ("calling this method more
///     than once will result in undefined behavior"). The old code initialised
///     on every tap, so a retry after a cancelled picker re-initialised the
///     singleton.
///  2. The SDK's `GoogleSignInException` is not user copy. A Google-console
///     misconfiguration (`[28444]`) used to reach the customer as "Something
///     went wrong. Please try again."
void main() {
  const clientId = AppConstants.googleServerClientId;

  group('initialize() happens exactly once', () {
    late _MockGoogleSignIn google;
    late AuthService auth;

    setUp(() {
      google = _MockGoogleSignIn();
      auth = AuthService.forTest(google);
      when(
        () => google.initialize(serverClientId: any(named: 'serverClientId')),
      ).thenAnswer((_) async {});
      when(() => google.authenticate()).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
    });

    test('a retried sign-in reuses the first initialisation', () async {
      await expectLater(
        auth.authenticateWithGoogle(serverClientId: clientId),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        auth.authenticateWithGoogle(serverClientId: clientId),
        throwsA(isA<Exception>()),
      );

      verify(() => google.initialize(serverClientId: clientId)).called(1);
      verify(() => google.authenticate()).called(2);
    });
  });

  group('googleFailureMessage', () {
    test('a cancelled picker reads as cancelled, not as a failure', () {
      final message = AuthService.googleFailureMessage(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );

      expect(message, 'Google sign-in was cancelled.');
      expect(
        friendlyAuthErrorMessage(Exception(message)),
        'Sign-in was cancelled.',
      );
    });

    test('every other code names Google instead of "something went wrong"',
        () {
      const otherCodes = [
        GoogleSignInExceptionCode.unknownError,
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
        GoogleSignInExceptionCode.userMismatch,
        GoogleSignInExceptionCode.uiUnavailable,
        GoogleSignInExceptionCode.interrupted,
      ];

      for (final code in otherCodes) {
        final shown = friendlyAuthErrorMessage(
          Exception(
            AuthService.googleFailureMessage(
              GoogleSignInException(
                code: code,
                description: '[28444] Developer console is not set up '
                    'correctly.',
              ),
            ),
          ),
        );

        expect(
          shown,
          'Google sign-in is not available right now. Use your email and '
          'password for now.',
          reason: '$code',
        );
        // Raw SDK internals must never reach the UI.
        expect(shown, isNot(contains('28444')), reason: '$code');
      }
    });

    test('only the canceled code reads as a cancellation', () {
      // A misconfiguration whose description happens to mention cancelling
      // must not be shown to the customer as "you cancelled" — the decision is
      // keyed on the enum, not on the SDK's prose.
      final shown = AuthService.googleFailureMessage(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'Account reauth failed: canceled',
        ),
      );

      expect(shown, startsWith('Google sign-in is not available'));
    });
  });
}
