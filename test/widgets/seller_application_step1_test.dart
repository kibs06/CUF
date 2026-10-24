import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/auth/seller_application_flow.dart';
import 'package:app/screens/shared/terms_privacy_screen.dart';
import 'package:app/widgets/auth/sole_primary_auth_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seller application step 1 (account): the Continue guard must validate
/// before touching the network, and a failing duplicate-email check must
/// surface a human message instead of dying silently.
///
/// The second test is the regression lock for the missing-catch fix: the
/// check runs inside try/finally with no catch, so any transport failure
/// (offline, DNS, timeout, 5xx — uninitialized Supabase here) escaped to
/// the gesture handler and the spinner just stopped on a dead step.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

/// Finder and pump helpers live inside [main] (like the social-button
/// suite) so no private type leaks into a public API — the repo lints
/// `library_private_types_in_public_api` even under test/.
void main() {
  _MockAuthProvider stubAuth() {
    final auth = _MockAuthProvider();
    when(() => auth.isLoading).thenReturn(false);
    when(() => auth.currentUser).thenReturn(null);
    return auth;
  }

  Finder field(String hint) => find.widgetWithText(TextFormField, hint);

  Future<void> pickBirthday(WidgetTester tester) async {
    final birthday = field('Tap to select your date of birth');
    await tester.ensureVisible(birthday);
    await tester.tap(birthday);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> acceptSellerTerms(WidgetTester tester) async {
    final tile = find.bySemanticsLabel(
      'I agree to the Seller Terms & Privacy Policy of CUFMAI.',
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(TermsPrivacyScreen), findsOneWidget);
    final scroll = find.descendant(
      of: find.byType(TermsPrivacyScreen),
      matching: find.byType(SingleChildScrollView),
    );
    for (var i = 0; i < 6; i++) {
      if (find.text('I have read and I agree').evaluate().isNotEmpty) break;
      await tester.fling(scroll, const Offset(0, -2000), 4000);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('I have read and I agree'));
    await tester.pumpAndSettle();
  }

  Future<void> tapContinue(WidgetTester tester) async {
    final cont = find.widgetWithText(SolePrimaryAuthButton, 'Continue');
    await tester.ensureVisible(cont.first);
    await tester.tap(cont.first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty continue validates, never touches the network',
      (tester) async {
    // Supabase is NOT initialized in tests: if the flow reached
    // emailExists with invalid input, this would throw instead.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: stubAuth(),
        child: const MaterialApp(home: SellerApplicationFlow()),
      ),
    );
    await tester.pump();

    await tapContinue(tester);

    expect(find.text('Please enter your full name'), findsOneWidget);
  });

  testWidgets('a failing duplicate-email check shows a message, not silence',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: stubAuth(),
        child: const MaterialApp(home: SellerApplicationFlow()),
      ),
    );
    await tester.pump();

    await tester.enterText(field('e.g. Josefa Reyes'), 'Seller User');
    await tester.enterText(field('e.g. josefa@gmail.com'), 'seller9247@gmail.com');
    await tester.enterText(field('e.g. 09XX-XXX-XXXX'), '09171234567');
    await pickBirthday(tester);
    await tester.enterText(field('At least 6 characters'), 'password123');
    await tester.enterText(field('Re-enter your password'), 'password123');
    await acceptSellerTerms(tester);
    await tapContinue(tester);

    // Supabase is unreachable here, so the check throws: the user must
    // still get a human message (mapped by friendlyAuthErrorMessage)
    // instead of a spinner that just stops on a dead step.
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    // …and the flow stays on step 1 rather than advancing blindly.
    expect(
      find.widgetWithText(SolePrimaryAuthButton, 'Continue'),
      findsWidgets,
    );
  });
}
