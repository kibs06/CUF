import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthResponse;

import 'package:app/screens/shared/mfa_verify_screen.dart';
import 'package:app/services/email_otp_service.dart';
import 'package:app/services/mfa_service.dart';

/// Fake MFA gateway — no Supabase network involved.
class FakeMfaGateway implements MfaGateway {
  String? nextError; // when set, verifyChallenge/verifyEnrollment throw it
  Object? resetError; // when set, resetTwoFactor throws it
  int resetCalls = 0;

  @override
  Future<bool> isMfaEnabled() async => false;

  @override
  Future<MfaEnrollment> enroll({String? friendlyName}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> verifyEnrollment({
    required String factorId,
    required String code,
  }) async {
    if (nextError != null) throw AuthException(nextError!);
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {}

  @override
  Future<void> unenroll(String factorId) async {}

  @override
  Future<MfaFactorInfo?> verifiedFactor() async => null;

  @override
  Future<void> verifyChallenge({
    required String factorId,
    required String code,
  }) async {
    if (nextError != null) throw AuthException(nextError!);
  }

  @override
  Future<void> resetTwoFactor() async {
    resetCalls++;
    if (resetError != null) throw resetError!;
  }
}

/// Fake email-OTP gateway for the lost-authenticator recovery path.
class FakeOtp implements EmailOtpGateway {
  int sentCodes = 0;
  String? sentTo;
  String? verifiedToken;
  Object? sendError;
  Object? verifyError;

  @override
  Future<void> sendLoginCode(String email) async {
    if (sendError != null) throw sendError!;
    sentCodes++;
    sentTo = email;
  }

  @override
  Future<AuthResponse> verifyLoginCode({
    required String email,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
    verifiedToken = token;
    return AuthResponse();
  }

  @override
  Future<void> sendSignupCode(String email) async => throw UnimplementedError();

  @override
  Future<AuthResponse> verifySignupCode({
    required String email,
    required String token,
  }) async => throw UnimplementedError();
}

String _buildJwt(String payload) {
  final enc = base64Url.encode(utf8.encode(payload));
  return 'header.$enc.signature';
}

void main() {
  group('MfaService.jwtPayload', () {
    test('decodes a valid payload', () {
      final payload = MfaService.jwtPayload(
        _buildJwt(jsonEncode({'sub': 'u1', 'aal': 'aal2'})),
      );
      expect(payload, isNotNull);
      expect(payload!['sub'], 'u1');
      expect(payload['aal'], 'aal2');
    });

    test('returns null for malformed tokens', () {
      expect(MfaService.jwtPayload(''), isNull);
      expect(MfaService.jwtPayload('not-a-jwt'), isNull);
      expect(MfaService.jwtPayload('a.b'), isNull);
      // Invalid base64/json payload
      expect(MfaService.jwtPayload('header.!!!.sig'), isNull);
      expect(MfaService.jwtPayload('header.abc.sig'), isNull);
    });
  });

  group('MfaService.aalFromJwtPayload / mfaRequiredForAal', () {
    test('aal2 maps to aal2 and opens', () {
      expect(
        MfaService.aalFromJwtPayload(const {'aal': 'aal2'}),
        'aal2',
      );
      expect(MfaService.mfaRequiredForAal('aal2'), isFalse);
    });

    test('aal1 / missing / garbage all require a code (fail closed)', () {
      for (final payload in <Map<String, dynamic>?>[
        const {'aal': 'aal1'},
        const {},
        null,
      ]) {
        expect(MfaService.aalFromJwtPayload(payload), 'aal1');
        expect(MfaService.mfaRequiredForAal('aal1'), isTrue);
      }
    });

    test('matches aal2 case-insensitively (server sends lowercase)', () {
      expect(
        MfaService.aalFromJwtPayload(const {'aal': 'AAL2'}),
        'aal2',
      );
      expect(MfaService.mfaRequiredForAal('aal2'), isFalse);
    });
  });

  group('MfaVerifyScreen', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: child));

    testWidgets('verifies a 6-digit code and calls onVerified', (tester) async {
      final fake = FakeMfaGateway();
      var verified = false;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        mfaService: fake,
        onVerified: () => verified = true,
      )));

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verified, isTrue);
      expect(find.textContaining("didn't match"), findsNothing);
    });

    testWidgets('rejects a non-6-digit code', (tester) async {
      final fake = FakeMfaGateway();
      var verified = false;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        mfaService: fake,
        onVerified: () => verified = true,
      )));

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verified, isFalse);
      expect(find.text('Enter the 6-digit code from your app.'), findsOneWidget);
    });

    testWidgets('shows a friendly error when the code is wrong', (tester) async {
      final fake = FakeMfaGateway()
        ..nextError = 'Invalid TOTP code entered';
      var verified = false;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        mfaService: fake,
        onVerified: () => verified = true,
      )));

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verified, isFalse);
      expect(
        find.text("That code didn't match or has expired. Try the next one."),
        findsOneWidget,
      );
    });

    testWidgets('shows no sign-out action when none is supplied', (tester) async {
      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        mfaService: FakeMfaGateway(),
        onVerified: () {},
      )));

      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('sign out calls the supplied handler and does not verify',
        (tester) async {
      var signedOut = 0;
      var verified = false;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        mfaService: FakeMfaGateway(),
        onVerified: () => verified = true,
        onSignOut: () async => signedOut++,
      )));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(signedOut, 1);
      expect(verified, isFalse);
    });

    testWidgets('lost-authenticator action is hidden without an email',
        (tester) async {
      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        mfaService: FakeMfaGateway(),
        otpService: FakeOtp(),
        onVerified: () {},
      )));

      expect(find.byKey(const ValueKey('mfa_lost_authenticator')), findsNothing);
    });

    testWidgets('recovery: emailed code turns 2FA off, then signs out',
        (tester) async {
      final mfa = FakeMfaGateway();
      final otp = FakeOtp();
      var signedOut = 0;
      var verified = false;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        email: 'user@example.com',
        mfaService: mfa,
        otpService: otp,
        onVerified: () => verified = true,
        onSignOut: () async => signedOut++,
      )));

      await tester.tap(find.byKey(const ValueKey('mfa_lost_authenticator')));
      await tester.pumpAndSettle();

      expect(otp.sentCodes, 1);
      expect(otp.sentTo, 'user@example.com');
      expect(find.text('Turn off 2FA'), findsOneWidget);

      // Recovery never auto-submits on the sixth digit: it turns 2FA off.
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      expect(otp.verifiedToken, isNull);
      expect(mfa.resetCalls, 0);

      await tester.tap(find.text('Turn off 2FA'));
      await tester.pumpAndSettle();

      expect(otp.verifiedToken, '123456');
      expect(mfa.resetCalls, 1);
      expect(signedOut, 1);
      expect(verified, isFalse);
    });

    testWidgets('recovery: a wrong emailed code leaves 2FA on and does not sign out',
        (tester) async {
      final mfa = FakeMfaGateway();
      final otp = FakeOtp()
        ..verifyError = const AuthException('Token has expired or is invalid');
      var signedOut = 0;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        email: 'user@example.com',
        mfaService: mfa,
        otpService: otp,
        onVerified: () {},
        onSignOut: () async => signedOut++,
      )));

      await tester.tap(find.byKey(const ValueKey('mfa_lost_authenticator')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Turn off 2FA'));
      await tester.pumpAndSettle();

      expect(mfa.resetCalls, 0);
      expect(signedOut, 0);
      expect(
        find.text("That code didn't match or has expired. Try the next one."),
        findsOneWidget,
      );
    });

    testWidgets('recovery: a failed server reset does not sign out',
        (tester) async {
      final mfa = FakeMfaGateway()..resetError = Exception('boom');
      final otp = FakeOtp();
      var signedOut = 0;

      await tester.pumpWidget(wrap(MfaVerifyScreen(
        factorId: 'factor-1',
        email: 'user@example.com',
        mfaService: mfa,
        otpService: otp,
        onVerified: () {},
        onSignOut: () async => signedOut++,
      )));

      await tester.tap(find.byKey(const ValueKey('mfa_lost_authenticator')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Turn off 2FA'));
      await tester.pumpAndSettle();

      expect(mfa.resetCalls, 1);
      expect(signedOut, 0);
      expect(find.text('Could not turn off 2FA. Try again.'), findsOneWidget);
    });
  });
}