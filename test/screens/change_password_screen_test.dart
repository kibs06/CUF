import 'package:app/screens/shared/change_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cover for the app's NO-E-MAIL password change — the signed-in half of
/// "forgot password".
///
/// The e-mail link is still the signed-out path (see
/// `password_reset_redirect_test.dart`); this screen exists because a customer
/// who is still signed in on this device can set a new password on the live
/// session, which is exactly what Supabase's `updateUser` is for.
///
/// Three things are user-facing and testable without a server: it must not ask
/// for the old password (the customer using it forgot it), it must hand
/// `onSubmit` exactly the new one, and the two outcomes after the password has
/// changed — other sessions ended, or the sign-out follow-up failed — must read
/// differently. The last one matters: a failed follow-up must never look like a
/// failed password change.
void main() {
  Widget host({
    required Future<bool?> Function(String) onSubmit,
    String email = 'jane@example.com',
  }) {
    return MaterialApp(
      home: ChangePasswordScreen(email: email, onSubmit: onSubmit),
    );
  }

  Future<void> fill(
    WidgetTester tester,
    String password,
    String confirm,
  ) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, password);
    await tester.enterText(fields.last, confirm);
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the account and promises no email', (tester) async {
    await tester.pumpWidget(host(onSubmit: (_) async => null));
    await tester.pumpAndSettle();

    expect(find.text('Change password'), findsOneWidget);
    expect(find.textContaining('jane@example.com'), findsOneWidget);
    expect(
      find.textContaining('Nothing is emailed'),
      findsOneWidget,
      reason:
          'the whole point of this screen is that it does not depend on '
          'the reset mailer',
    );
    expect(
      find.text('Current password'),
      findsNothing,
      reason:
          'the customer using this screen forgot the old password, so '
          'asking for it would send them back to the email link',
    );
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('refuses a password the project would refuse', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        onSubmit: (_) async {
          calls++;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, '12345', '12345');
    await tapSubmit(tester);

    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(calls, 0, reason: 'a too-short password never reaches the server');
  });

  testWidgets('refuses a confirmation that does not match', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        onSubmit: (_) async {
          calls++;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, 'correct horse', 'correct hrose');
    await tapSubmit(tester);

    expect(find.text('Those passwords do not match'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('hands the typed password to onSubmit and confirms it stuck', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      host(
        onSubmit: (password) async {
          submitted = password;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, 'new-password-9', 'new-password-9');
    await tapSubmit(tester);

    expect(submitted, 'new-password-9');
    expect(find.text('Password updated.'), findsOneWidget);
  });

  testWidgets(
    'a failed sign-out of other sessions is a warning, not a failure',
    (tester) async {
      await tester.pumpWidget(host(onSubmit: (_) async => false));
      await tester.pumpAndSettle();

      await fill(tester, 'new-password-9', 'new-password-9');
      await tapSubmit(tester);

      expect(
        find.textContaining(
          'Password updated, but we could not end your other '
          'sessions',
        ),
        findsOneWidget,
        reason:
            'the password HAS changed; reporting a failure here would send '
            'the customer to retry something that already succeeded',
      );
      expect(
        find.text('Password updated.'),
        findsNothing,
        reason:
            'the follow-up did not happen, so the copy must not claim it did',
      );
    },
  );

  testWidgets('shows the server’s own reason when it refuses the password', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSubmit: (_) async => throw const AuthException(
          'Password should be at least 6 characters.',
          code: 'weak_password',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, 'shorty', 'shorty');
    await tapSubmit(tester);

    expect(
      find.textContaining("That password's too weak"),
      findsOneWidget,
      reason: 'a refusal must name the reason, not "something went wrong"',
    );
    expect(
      find.text('Update password'),
      findsOneWidget,
      reason: 'the form stays usable so the customer can choose another one',
    );
  });

  testWidgets('an expired session is named, not left as a generic failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onSubmit: (_) async => throw const AuthException(
          'Sign in again to change your password.',
          code: 'session_missing',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, 'new-password-9', 'new-password-9');
    await tapSubmit(tester);

    expect(find.textContaining('session ended'), findsOneWidget);
  });
}
