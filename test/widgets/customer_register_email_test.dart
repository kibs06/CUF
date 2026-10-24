import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/auth/customer_register_screen.dart';
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

  Future<void> pumpRegister(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: stubAuth(),
        child: const MaterialApp(home: CustomerRegisterScreen()),
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
}
