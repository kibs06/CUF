import 'dart:async';

import 'package:app/providers/auth_provider.dart';
import 'package:app/widgets/auth/social_signin_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// Logo-only Google/Facebook buttons: what a customer actually sees and
/// touches — two circles with no visible words, the words kept as
/// screen-reader labels, and a second tap ignored while one is pending.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

void main() {
  _MockAuthProvider stubAuth() {
    final auth = _MockAuthProvider();
    when(() => auth.signInWithGoogle(
          serverClientId: any(named: 'serverClientId'),
        )).thenAnswer((_) async => {'success': true, 'emailMissing': false});
    when(() => auth.signInWithFacebook())
        .thenAnswer((_) async => {'success': true, 'emailMissing': false});
    return auth;
  }

  Widget wrap(_MockAuthProvider auth) =>
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(
          home: Scaffold(body: SocialSigninButtons()),
        ),
      );

  testWidgets('renders two logo-only circles with semantics labels',
      (tester) async {
    await tester.pumpWidget(wrap(stubAuth()));
    await tester.pump();

    expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
    expect(find.bySemanticsLabel('Continue with Facebook'), findsOneWidget);
    // Logos, not words: the G svg plus the Facebook glyph, and no visible
    // "Continue with …" text anywhere.
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.facebook), findsOneWidget);
    expect(find.textContaining('Continue with'), findsNothing);
    expect(find.text('OR'), findsOneWidget);
  });

  testWidgets('tapping the Google logo calls signInWithGoogle once',
      (tester) async {
    final auth = stubAuth();
    await tester.pumpWidget(wrap(auth));
    await tester.pump();

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();

    verify(() => auth.signInWithGoogle(
          serverClientId: any(named: 'serverClientId'),
        )).called(1);
  });

  testWidgets('a second tap is ignored while the first is pending',
      (tester) async {
    final auth = _MockAuthProvider();
    final pending = Completer<Map<String, dynamic>>();
    when(() => auth.signInWithGoogle(
          serverClientId: any(named: 'serverClientId'),
        )).thenAnswer((_) => pending.future);

    await tester.pumpWidget(wrap(auth));
    await tester.pump();

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    // The tapped circle swaps its logo for a spinner…
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // …and the Facebook tap lands nowhere while Google is in flight.
    await tester.tap(find.byType(GestureDetector).at(1));
    await tester.pump();
    verifyNever(() => auth.signInWithFacebook());

    pending.complete({'success': true, 'emailMissing': false});
    await tester.pump();
    verify(() => auth.signInWithGoogle(
          serverClientId: any(named: 'serverClientId'),
        )).called(1);
  });
}
