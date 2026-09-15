import 'package:app/screens/shared/email_otp_screen.dart';
import 'package:app/services/email_otp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeOtp implements EmailOtpGateway {
  final List<String> loginSends = [];
  final List<String> signupSends = [];
  Object? sendError;
  Object? verifyError;

  @override
  Future<void> sendLoginCode(String email) async {
    loginSends.add(email);
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> sendSignupCode(String email) async {
    signupSends.add(email);
    if (sendError != null) throw sendError!;
  }

  @override
  Future<AuthResponse> verifyLoginCode({
    required String email,
    required String token,
  }) async => AuthResponse();

  @override
  Future<AuthResponse> verifySignupCode({
    required String email,
    required String token,
  }) async => AuthResponse();
}

void main() {
  late FakeOtp otp;
  late DateTime clock;

  setUp(() {
    otp = FakeOtp();
    clock = DateTime(2026, 9, 15, 12, 0, 0);
  });

  /// The ticker is a 1s `Timer.periodic` that is cancelled in `dispose`, so
  /// every test must unmount the screen before it ends — otherwise the
  /// framework reports a pending timer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Widget wrapSignup({
    required Future<void> Function(String) onVerify,
    Future<void> Function()? onSend,
    bool codeAlreadySent = true,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: EmailOtpScreen(
        purpose: EmailOtpPurpose.signupVerification,
        email: 'maria@gmail.com',
        onVerify: onVerify,
        onSend: onSend,
        codeAlreadySent: codeAlreadySent,
        onCancel: onCancel,
        otpService: otp,
        now: () => clock,
      ),
    );
  }

  group('verification', () {
    testWidgets('a 6-digit code auto-submits and calls onVerify',
        (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(wrapSignup(onVerify: (c) async => codes.add(c)));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump();

      expect(codes, ['123456']);
      expect(find.textContaining("didn't match"), findsNothing);
      await unmount(tester);
    });

    testWidgets('a too-short code is rejected without calling onVerify',
        (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(wrapSignup(onVerify: (c) async => codes.add(c)));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Verify'));
      await tester.pump();

      expect(codes, isEmpty);
      expect(
        find.text('Enter the 6-digit code we emailed you.'),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('a wrong/expired code shows the mapped auth message',
        (tester) async {
      await tester.pumpWidget(
        wrapSignup(
          onVerify: (_) async =>
              throw AuthException('bad token', code: 'otp_expired'),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.pump();

      expect(
        find.text("That code didn't match or has expired. Request a new one."),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('a non-auth failure shows the connection message',
        (tester) async {
      await tester.pumpWidget(
        wrapSignup(onVerify: (_) async => throw Exception('socket closed')),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Something went wrong. Check your connection and try again.'),
        findsOneWidget,
      );
      await unmount(tester);
    });
  });

  group('resend + expiry', () {
    testWidgets('resend is disabled for the cooldown, then works',
        (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      expect(find.text('Resend code in 60s'), findsOneWidget);

      // Mid-cooldown the button is inert.
      await tester.tap(find.text('Resend code in 60s'));
      await tester.pump();
      expect(otp.signupSends, isEmpty);

      clock = clock.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Resend code'), findsOneWidget);
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump();

      expect(otp.signupSends, ['maria@gmail.com']);
      await unmount(tester);
    });

    testWidgets('a rate-limited resend surfaces the message, not silence',
        (tester) async {
      otp.sendError = AuthException(
        'too many',
        code: 'over_email_send_rate_limit',
      );
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      clock = clock.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Too many attempts. Try again in about a minute.'),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('the countdown starts at the configured otp_expiry',
        (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      expect(find.text('Code expires in 60:00'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an elapsed code says so and offers a resend', (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      clock = clock.add(const Duration(seconds: 3601));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('That code has expired — request a new one.'),
        findsOneWidget,
      );
      expect(find.text('Resend code'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('sending and cancelling', () {
    testWidgets('the new-device variant sends its own code on first frame',
        (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: EmailOtpScreen(
            purpose: EmailOtpPurpose.newDeviceChallenge,
            email: 'maria@gmail.com',
            deviceLabel: 'samsung SM-A155F · Android 14',
            codeAlreadySent: false,
            onVerify: (c) async => codes.add(c),
            otpService: otp,
            now: () => clock,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The LOGIN sender was used, not the signup one.
      expect(otp.loginSends, ['maria@gmail.com']);
      expect(otp.signupSends, isEmpty);
      expect(find.textContaining('new device'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the signup variant does not auto-send (signUp already did)',
        (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();
      expect(otp.signupSends, isEmpty);
      await unmount(tester);
    });

    testWidgets('the email is masked and cancel is wired', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        wrapSignup(onVerify: (_) async {}, onCancel: () => cancelled = true),
      );
      await tester.pump();

      expect(find.textContaining('m•••@gmail.com'), findsOneWidget);
      expect(find.textContaining('maria@gmail.com'), findsNothing);

      await tester.tap(find.text('Use a different account'));
      await tester.pump();
      expect(cancelled, isTrue);
      await unmount(tester);
    });

    testWidgets('no cancel button when the caller does not offer an escape',
        (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      expect(find.text('Use a different account'), findsNothing);
      await unmount(tester);
    });
  });
}
