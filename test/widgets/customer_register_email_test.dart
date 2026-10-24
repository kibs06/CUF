import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/auth/customer_register_screen.dart';
import 'package:app/screens/shared/terms_privacy_screen.dart';
import 'package:app/widgets/sole_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// Customer registration email field: a brand-new address must never show
/// the duplicate-email inline error, and typing after an inline error must
/// clear it (the stale-`_emailExistsError` bug: the validator returns the
/// stored error verbatim, so without an `onChanged` clear it sticks to
/// every later keystroke — the seller flow already clears it, this locks
/// the customer flow to the same contract).
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

void main() {
  _MockAuthProvider stubAuth() {
    final auth = _MockAuthProvider();
    when(() => auth.isLoading).thenReturn(false);
    return auth;
  }

  Future<void> pumpRegister(
    WidgetTester tester, {
    Future<bool> Function(String email)? emailExistsOverride,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: stubAuth(),
        child: MaterialApp(
          home: CustomerRegisterScreen(
            emailExistsOverride: emailExistsOverride,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder emailField() => find.widgetWithText(
        TextFormField,
        'e.g. maria@gmail.com',
      );

  testWidgets('a brand-new email shows no already-exists error', (
    tester,
  ) async {
    await pumpRegister(tester);

    expect(find.text('Email Address'), findsOneWidget);
    await tester.enterText(
      emailField(),
      'brandnewuser9247@gmail.com',
    );
    await tester.pump();

    expect(find.textContaining('already exists'), findsNothing);
    // Live validation passes: green check, no red error icon.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('editing the email re-validates without sticking an error', (
    tester,
  ) async {
    await pumpRegister(tester);

    // Type an invalid address first: live validation must complain via the
    // red error icon (the text only appears after form submit)…
    await tester.enterText(emailField(), 'not-an-email');
    await tester.pump();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

    // …then correcting it to a fresh address clears the complaint — the
    // `onChanged` path must not leave any previous error behind.
    await tester.enterText(
      emailField(),
      'anotherfresh9247@gmail.com',
    );
    // pumpAndSettle: the suffix icon cross-fades via AnimatedSwitcher, so
    // a single pump still holds the outgoing error icon in the tree.
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.text('Please enter a valid email'), findsNothing);
    expect(find.textContaining('already exists'), findsNothing);
  });

  testWidgets('duplicate submit shows the error, next keystroke clears it', (
    tester,
  ) async {
    // Force the duplicate path without Supabase: the exact bug report — a
    // taken address submits, the inline error appears, then typing a new
    // address must clear it (fails without the `onChanged` clear).
    await pumpRegister(
      tester,
      emailExistsOverride: (_) async => true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. Maria Cobarrubias'),
      'Test User',
    );
    await tester.enterText(emailField(), 'taken@gmail.com');

    // Birthday is required: pick the default (25 years ago) from the picker.
    final birthday = find.widgetWithText(
      TextFormField,
      'Tap to select your date of birth',
    );
    await tester.ensureVisible(birthday);
    await tester.tap(birthday);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'At least 6 characters'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Re-enter your password'),
      'password123',
    );

    // Terms require the read-and-agree flow: open the policy, scroll to the
    // bottom to unlock the button, agree, back on the form.
    final termsTile = find.bySemanticsLabel(
      'I agree to the Customer Terms & Privacy Policy of CUFMAI.',
    );
    await tester.ensureVisible(termsTile);
    await tester.tap(termsTile);
    await tester.pumpAndSettle();
    // The read-and-agree policy screen must have opened.
    expect(find.byType(TermsPrivacyScreen), findsOneWidget);
    final policyScroll = find.descendant(
      of: find.byType(TermsPrivacyScreen),
      matching: find.byType(SingleChildScrollView),
    );
    // Fling until the bottom unlocks the agree button (one drag may not
    // reach the end of the full document).
    for (var i = 0; i < 6; i++) {
      if (find.text('I have read and I agree').evaluate().isNotEmpty) break;
      await tester.fling(policyScroll, const Offset(0, -2000), 4000);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('I have read and I agree'));
    await tester.pumpAndSettle();

    // The scaffold header shares the title text — target the button itself.
    final createAccount = find.widgetWithText(
      SolePrimaryButton,
      'Create account',
    );
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    // The duplicate submit surfaces the inline error on the email field…
    expect(find.textContaining('already exists'), findsOneWidget);

    // …and the very next keystroke — a brand-new address — clears it.
    await tester.enterText(emailField(), 'brandnew9247@gmail.com');
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsNothing);
  });
}
