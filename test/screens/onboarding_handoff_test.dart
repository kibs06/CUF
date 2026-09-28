import 'package:app/screens/auth/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for AuthGate's `_FirstTimeOrLoginRouter`: the onboarding screen is
/// a CHILD of the host, and the host is the route on the navigator stack.
///
/// Regression test for the fresh-install login bug (2026-09-28). Completing
/// onboarding used to call `Navigator.pushReplacement(AccountEntryScreen)` from
/// inside this child. Because the child is not a route of its own, that call
/// replaced the HOST's route and unmounted the host — on a fresh install that
/// host is AuthGate, so the app had nothing left listening for the new session:
/// the user signed in and stayed on the sign-in form until they force-closed
/// the app. The characterization run before the fix printed
/// `HOST still mounted: false`.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    // Mirrors the router: onboarding until it reports completion, then the
    // front door — both as the host's own child, never as a pushed route.
    if (!_finished) {
      return OnboardingScreen(
        onFinished: () => setState(() => _finished = true),
      );
    }
    return const Scaffold(body: Center(child: Text('FRONT DOOR')));
  }
}

void main() {
  testWidgets(
      'completing onboarding swaps the host in place and pushes no route',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();

    // Skip to the last slide, then finish.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // The host decided what came next...
    expect(find.text('FRONT DOOR'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);

    // ...and nothing was pushed: the host is still the only route, so the
    // widget above it (AuthGate) is still mounted and still listening.
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('has_seen_onboarding'), isTrue);
  });
}
