import 'package:app/providers/auth_provider.dart';
import 'package:app/widgets/auth/require_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// Regression test for the guest sign-in flow's dead end: the gate hands back a
/// state it renders itself (new-device code, sign-up code, password recovery)
/// while the pushed sign-in form is still on top, so the code screen renders
/// invisibly underneath and a sign-in that worked looks like it did nothing.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

_MockAuthProvider _authProvider() {
  final auth = _MockAuthProvider();
  when(() => auth.isAuthenticated).thenReturn(false);
  when(() => auth.pendingSignupVerification).thenReturn(null);
  when(() => auth.pendingDeviceChallenge).thenReturn(null);
  when(() => auth.pendingPasswordRecovery).thenReturn(null);
  return auth;
}

void main() {
  group('gateTakesOver', () {
    test('no pending hand-off leaves the form alone', () {
      expect(gateTakesOver(_authProvider()), isFalse);
    });

    test('a new-device challenge moves the screen to the gate', () {
      final auth = _authProvider();
      when(() => auth.pendingDeviceChallenge)
          .thenReturn({'email': 'shopper@example.com'});
      expect(gateTakesOver(auth), isTrue);
    });

    test('an emailed sign-up code moves the screen to the gate', () {
      final auth = _authProvider();
      when(() => auth.pendingSignupVerification)
          .thenReturn({'email': 'shopper@example.com'});
      expect(gateTakesOver(auth), isTrue);
    });

    test('a recovery session moves the screen to the gate', () {
      final auth = _authProvider();
      when(() => auth.pendingPasswordRecovery)
          .thenReturn({'email': 'shopper@example.com'});
      expect(gateTakesOver(auth), isTrue);
    });
  });

  group('PopsWhenGateTakesOver', () {
    /// Opens the form from the gate; when [registerOnTop] is set the form also
    /// pushes a register screen above itself, as the create-account flow does.
    Future<_MockAuthProvider> pumpForm(
      WidgetTester tester, {
      bool registerOnTop = false,
    }) async {
      final auth = _authProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (formContext) {
                          if (registerOnTop) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              Navigator.of(formContext).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const Scaffold(
                                    body: Center(child: Text('REGISTER')),
                                  ),
                                ),
                              );
                            });
                          }
                          return const PopsWhenGateTakesOver(
                            child: Scaffold(
                              body: Center(child: Text('SIGN IN FORM')),
                            ),
                          );
                        },
                      ),
                    ),
                    child: const Text('GATE'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('GATE'));
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('dismisses itself when a new-device code takes over',
        (tester) async {
      final auth = await pumpForm(tester);
      expect(find.text('SIGN IN FORM'), findsOneWidget);

      when(() => auth.pendingDeviceChallenge)
          .thenReturn({'email': 'shopper@example.com'});
      auth.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('SIGN IN FORM'), findsNothing);
      // The gate's route is the only one left: nothing was popped past it.
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });

    testWidgets('a register screen above the form is dropped too',
        (tester) async {
      final auth = await pumpForm(tester, registerOnTop: true);
      expect(find.text('REGISTER'), findsOneWidget);

      when(() => auth.pendingSignupVerification)
          .thenReturn({'email': 'shopper@example.com'});
      auth.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('REGISTER'), findsNothing);
      expect(find.text('SIGN IN FORM'), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });

    testWidgets('an unrelated provider update leaves the form alone',
        (tester) async {
      final auth = await pumpForm(tester);

      auth.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('SIGN IN FORM'), findsOneWidget);
    });
  });
}
