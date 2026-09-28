import 'dart:async';

import 'package:app/widgets/auth/dismiss_on_signin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The two halves of the trap that made a pushed sign-in form a dead end
/// (2026-09-28): the signal that dismisses it, and the widget that acts on it.
///
/// The route this wraps is a *second* account being added, so the account
/// signed in when it was pushed is still active — token refreshes for that
/// account fire constantly and must NOT dismiss the form someone is typing in.
void main() {
  Session session(String userId) => Session(
        accessToken: 'access-token',
        tokenType: 'bearer',
        refreshToken: 'refresh-token',
        user: User(
          id: userId,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-09-28T00:00:00Z',
        ),
      );

  group('isNewSignIn', () {
    test('a fresh sign-in dismisses, whoever it is', () {
      expect(
        isNewSignIn(
          event: AuthChangeEvent.signedIn,
          sessionUserId: 'account-a',
          pushedAsUserId: 'account-a',
        ),
        isTrue,
      );
      expect(
        isNewSignIn(
          event: AuthChangeEvent.signedIn,
          sessionUserId: 'account-b',
          pushedAsUserId: 'account-a',
        ),
        isTrue,
      );
    });

    test('a refresh for the same account does not', () {
      expect(
        isNewSignIn(
          event: AuthChangeEvent.tokenRefreshed,
          sessionUserId: 'account-a',
          pushedAsUserId: 'account-a',
        ),
        isFalse,
      );
      expect(
        isNewSignIn(
          event: AuthChangeEvent.initialSession,
          sessionUserId: 'account-a',
          pushedAsUserId: 'account-a',
        ),
        isFalse,
      );
    });

    test('a session for a different account does', () {
      expect(
        isNewSignIn(
          event: AuthChangeEvent.tokenRefreshed,
          sessionUserId: 'account-b',
          pushedAsUserId: 'account-a',
        ),
        isTrue,
      );
    });

    test('signing out never dismisses — no session yet', () {
      expect(
        isNewSignIn(
          event: AuthChangeEvent.signedOut,
          sessionUserId: null,
          pushedAsUserId: 'account-a',
        ),
        isFalse,
      );
    });
  });

  testWidgets('the pushed form dismisses itself when a new sign-in lands',
      (tester) async {
    final events = StreamController<AuthState>.broadcast();
    addTearDown(events.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DismissOnSignIn(
                      authStream: events.stream,
                      pushedAsUserId: 'account-a',
                      child: const Scaffold(
                        body: Center(child: Text('SIGN IN FORM')),
                      ),
                    ),
                  ),
                ),
                child: const Text('add account'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('add account'));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN FORM'), findsOneWidget);

    // A refresh for the account that was already signed in changes nothing.
    events.add(AuthState(AuthChangeEvent.tokenRefreshed, session('account-a')));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN FORM'), findsOneWidget);

    // The second account's sign-in dismisses the form; the shell underneath
    // is what the user should be looking at.
    events.add(AuthState(AuthChangeEvent.signedIn, session('account-b')));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN FORM'), findsNothing);
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
  });

  testWidgets('a signed-out event leaves the form alone', (tester) async {
    final events = StreamController<AuthState>.broadcast();
    addTearDown(events.close);

    await tester.pumpWidget(
      MaterialApp(
        home: DismissOnSignIn(
          authStream: events.stream,
          pushedAsUserId: 'account-a',
          child: const Scaffold(body: Center(child: Text('SIGN IN FORM'))),
        ),
      ),
    );

    events.add(AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();

    expect(find.text('SIGN IN FORM'), findsOneWidget);
  });
}
