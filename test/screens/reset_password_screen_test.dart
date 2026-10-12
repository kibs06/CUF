import 'package:app/screens/auth/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cover for the screen a password-reset link lands on — the app's end of the
/// recovery flow (`solvision://auth/recovery` → `AuthGate` →
/// `ResetPasswordScreen`).
///
/// Two of its jobs are user-facing and both are testable without a server: it
/// must refuse what the project refuses (GoTrue's `password_min_length` is 6 on
/// the live project, and the register screen spells the same rule the same
/// way), and it must hand `onSubmit` exactly what was typed. The third is what
/// happens when the SERVER is the one saying no — the mapped reason, not
/// "something went wrong" — which is the difference between a customer
/// choosing a different password and a customer staring at a dead form.
///
/// Deliberately provider-free: the screen takes callbacks (`onSubmit`,
/// `onCancel`) so it can be driven like this, exactly as `EmailOtpScreen` is.
void main() {
  Widget host({
    required Future<void> Function(String) onSubmit,
    VoidCallback? onCancel,
    String email = 'jane@example.com',
  }) {
    return MaterialApp(
      home: ResetPasswordScreen(
        email: email,
        onSubmit: onSubmit,
        onCancel: onCancel,
      ),
    );
  }

  Future<void> fill(WidgetTester tester, String password, String confirm) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, password);
    await tester.enterText(fields.last, confirm);
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the account the link belongs to', (tester) async {
    await tester.pumpWidget(host(onSubmit: (_) async {}));
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password'), findsOneWidget);
    expect(
      find.textContaining('jane@example.com'),
      findsOneWidget,
      reason: 'a reset link can be opened on a device that was signed in as '
          'somebody else, so the screen has to say whose password it is',
    );
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm new password'), findsOneWidget);
    expect(
      find.text('Not now'),
      findsNothing,
      reason: 'without an onCancel the escape hatch must not be drawn',
    );
  });

  testWidgets('refuses a password the project would refuse', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(onSubmit: (_) async => calls++));
    await tester.pumpAndSettle();

    await fill(tester, 'short', 'short');
    await tapSubmit(tester);

    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(calls, 0, reason: 'the server must never see an input that fails '
        'the project’s own rule');
  });

  testWidgets('refuses a confirmation that does not match', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(onSubmit: (_) async => calls++));
    await tester.pumpAndSettle();

    await fill(tester, 'longenough1', 'longenough2');
    await tapSubmit(tester);

    expect(find.text('Those passwords do not match'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('hands the typed password to onSubmit and confirms it stuck',
      (tester) async {
    String? seen;
    await tester.pumpWidget(
      host(
        onSubmit: (password) async => seen = password,
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, 'hunter22222', 'hunter22222');
    await tapSubmit(tester);

    expect(seen, 'hunter22222');
    // The customer's shell replaces this screen on the provider's state change;
    // the toast is what says the reset actually went through.
    expect(
      find.text('Password updated — you are signed in.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the server’s own reason when it refuses the password',
      (tester) async {
    await tester.pumpWidget(
      host(
        onSubmit: (_) async => throw const AuthException(
          'New password should be different from the old password.',
          code: 'same_password',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fill(tester, 'hunter22222', 'hunter22222');
    await tapSubmit(tester);

    expect(
      find.text('That is already your password — choose a different one.'),
      findsOneWidget,
    );
    expect(
      find.text('Set new password'),
      findsOneWidget,
      reason: 'a refused password leaves the form usable — the customer '
          'retries here, they are not sent back to the sign-in screen',
    );
  });

  testWidgets('leaves the reset without keeping the customer trapped',
      (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      host(onSubmit: (_) async {}, onCancel: () => cancelled++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(cancelled, 1);
  });
}
