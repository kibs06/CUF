import 'package:app/screens/shared/email_otp_screen.dart';
import 'package:app/services/email_otp_service.dart';
import 'package:app/widgets/otp_code_field.dart';
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

  Finder box(int index) => find.byKey(ValueKey<String>('otp-box-$index'));

  /// Keys the code in one box at a time, the way a finger would — the
  /// segmented field auto-advances, and the sixth digit auto-submits.
  Future<void> enterCode(WidgetTester tester, String code) async {
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(box(i), code[i]);
      await tester.pump();
    }
    await tester.pump();
  }

  /// What each box currently shows.
  List<String> boxes(WidgetTester tester) => List.generate(
        6,
        (i) => tester.widget<TextField>(box(i)).controller!.text,
      );

  Widget wrapSignup({
    required Future<void> Function(String) onVerify,
    Future<void> Function()? onSend,
    bool codeAlreadySent = true,
    VoidCallback? onCancel,
    String? initialError,
  }) {
    return MaterialApp(
      home: EmailOtpScreen(
        purpose: EmailOtpPurpose.signupVerification,
        email: 'maria@gmail.com',
        onVerify: onVerify,
        initialError: initialError,
        onSend: onSend,
        codeAlreadySent: codeAlreadySent,
        onCancel: onCancel,
        otpService: otp,
        now: () => clock,
      ),
    );
  }

  group('verification', () {
    testWidgets('the code is entered as six separate boxes', (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      expect(box(0), findsOneWidget);
      expect(box(5), findsOneWidget);
      expect(box(6), findsNothing, reason: 'exactly six boxes');
      await unmount(tester);
    });

    testWidgets('a 6-digit code auto-submits and calls onVerify',
        (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(wrapSignup(onVerify: (c) async => codes.add(c)));
      await tester.pump();

      await enterCode(tester, '123456');

      expect(codes, ['123456']);
      expect(find.textContaining("didn't match"), findsNothing);
      await unmount(tester);
    });

    testWidgets('a too-short code is rejected without calling onVerify',
        (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(wrapSignup(onVerify: (c) async => codes.add(c)));
      await tester.pump();

      await enterCode(tester, '12');
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

      await enterCode(tester, '000000');

      expect(
        find.text("That code didn't match or has expired. Request a new one."),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('a rejected code empties the boxes for a straight re-key',
        (tester) async {
      await tester.pumpWidget(
        wrapSignup(
          onVerify: (_) async =>
              throw AuthException('bad token', code: 'otp_expired'),
        ),
      );
      await tester.pump();

      await enterCode(tester, '123456');
      // The old digits must not have to be deleted one box at a time.
      expect(boxes(tester), ['', '', '', '', '', '']);
      await unmount(tester);
    });

    testWidgets('typing again clears the previous rejection', (tester) async {
      await tester.pumpWidget(
        wrapSignup(
          onVerify: (_) async =>
              throw AuthException('bad token', code: 'otp_expired'),
        ),
      );
      await tester.pump();

      await enterCode(tester, '123456');
      expect(find.textContaining("didn't match"), findsOneWidget);

      await tester.enterText(box(0), '9');
      await tester.pump();

      expect(find.textContaining("didn't match"), findsNothing);
      await unmount(tester);
    });

    testWidgets('a non-auth failure shows the connection message',
        (tester) async {
      await tester.pumpWidget(
        wrapSignup(onVerify: (_) async => throw Exception('socket closed')),
      );
      await tester.pump();

      await enterCode(tester, '000000');

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

    testWidgets('a resend clears any half-typed digits', (tester) async {
      await tester.pumpWidget(wrapSignup(onVerify: (_) async {}));
      await tester.pump();

      await enterCode(tester, '12345');
      expect(boxes(tester).first, '1');

      clock = clock.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump();

      expect(boxes(tester), ['', '', '', '', '', '']);
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
      // The description names the device inline (rich text, hence findRichText).
      expect(
        find.textContaining('New sign-in from', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('samsung SM-A155F', findRichText: true),
        findsOneWidget,
      );
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

      expect(
        find.textContaining('m•••@gmail.com', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('maria@gmail.com', findRichText: true),
        findsNothing,
      );

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

  /// The new-device challenge mails its code inside `AuthProvider.login`, so
  /// the failure is known BEFORE this screen exists. It has to be visible on
  /// the first frame: the alternative (measuring Sep 17, 2026) was a login
  /// that dropped the user back on "Create your account" with no message.
  group('a code that could not be sent', () {
    Widget wrapDeviceChallenge({String? initialError}) {
      return MaterialApp(
        home: EmailOtpScreen(
          purpose: EmailOtpPurpose.newDeviceChallenge,
          email: 'maria@gmail.com',
          deviceLabel: 'samsung SM-A155F · Android 14',
          initialError: initialError,
          onVerify: (_) async {},
          otpService: otp,
          now: () => clock,
        ),
      );
    }

    testWidgets('is shown straight away, not after a resend', (tester) async {
      await tester.pumpWidget(
        wrapDeviceChallenge(
          initialError: 'Too many attempts. Try again in about a minute.',
        ),
      );
      await tester.pump();

      expect(
        find.text('Too many attempts. Try again in about a minute.'),
        findsOneWidget,
      );
      // Nothing was mailed, so the screen must not say otherwise.
      expect(
        find.textContaining('We sent a', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('could not send the code', findRichText: true),
        findsOneWidget,
      );
      // The way out is still offered, and it is the caller's.
      await unmount(tester);
    });

    testWidgets('does not mark the code boxes as wrong', (tester) async {
      await tester.pumpWidget(
        wrapDeviceChallenge(initialError: 'Something went wrong.'),
      );
      await tester.pump();

      final field = tester.widget<OtpCodeField>(
        find.byType(OtpCodeField),
      );
      expect(field.hasError, isFalse);
      await unmount(tester);
    });

    testWidgets('a successful send clears the stale message', (tester) async {
      await tester.pumpWidget(
        wrapDeviceChallenge(initialError: 'Too many attempts.'),
      );
      await tester.pump();

      clock = clock.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump();

      expect(otp.loginSends, ['maria@gmail.com']);
      expect(find.text('Too many attempts.'), findsNothing);
      await unmount(tester);
    });
  });
}
