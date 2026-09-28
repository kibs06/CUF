import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps a sign-in screen that was pushed **above** `AuthGate` and dismisses it
/// once a new sign-in happens.
///
/// AuthGate owns routing: its `StreamBuilder` swaps the root widget to the
/// right shell when a session appears. That only works for screens the gate
/// itself shows — a route pushed on top of the gate (Settings → Switch Account
/// → Add account) sits above whatever the gate swaps to, so the user signs in
/// and then stares at the form while the shell renders underneath, until they
/// force-close the app. Dismissing the pushed route is the one piece of
/// navigation the push site owns; this widget does exactly that and nothing
/// else.
///
/// Do NOT use this to make a screen navigate to a shell — that is AuthGate's
/// job. See `docs/AI/SIGN_IN_ARCHITECTURE.md`.
class DismissOnSignIn extends StatefulWidget {
  const DismissOnSignIn({
    super.key,
    required this.child,
    this.authStream,
    this.pushedAsUserId,
  });

  final Widget child;

  /// The auth events to watch. Defaults to `Supabase.instance.client.auth`,
  /// which is uninitialized in widget tests — pass a stream there.
  final Stream<AuthState>? authStream;

  /// The account this route was pushed for. Read from the live session when
  /// omitted; [authStream] callers (tests) pass it explicitly.
  final String? pushedAsUserId;

  @override
  State<DismissOnSignIn> createState() => _DismissOnSignInState();
}

class _DismissOnSignInState extends State<DismissOnSignIn> {
  StreamSubscription<AuthState>? _subscription;

  /// The account that was signed in when this route was pushed (the one being
  /// left behind, in the "add another account" flow).
  late final String? _userIdAtPush;

  @override
  void initState() {
    super.initState();
    // An injected stream keeps Supabase out of the picture entirely, so this
    // widget can be driven by a test without a live client.
    final injected = widget.authStream;
    if (injected == null) {
      final auth = Supabase.instance.client.auth;
      _userIdAtPush = widget.pushedAsUserId ?? auth.currentUser?.id;
      _subscription = auth.onAuthStateChange.listen(_onAuthStateChange);
    } else {
      _userIdAtPush = widget.pushedAsUserId;
      _subscription = injected.listen(_onAuthStateChange);
    }
  }

  void _onAuthStateChange(AuthState state) {
    if (!isNewSignIn(
      event: state.event,
      sessionUserId: state.session?.user.id,
      pushedAsUserId: _userIdAtPush,
    )) {
      return;
    }
    if (!mounted) return;
    // Guarded rather than forced: a route that has already been popped (or one
    // that refuses to pop) must never take the app down with it.
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Whether an auth event means "someone has just signed in *here*", which is
/// the only thing that should dismiss a pushed sign-in route.
///
/// Deliberately narrow: a token refresh (or a same-user session recovery) fires
/// constantly while a session is alive, and dismissing on those would make the
/// form vanish mid-typing.
@visibleForTesting
bool isNewSignIn({
  required AuthChangeEvent event,
  required String? sessionUserId,
  required String? pushedAsUserId,
}) {
  if (sessionUserId == null) return false; // signed out, or no session yet
  if (event == AuthChangeEvent.signedIn) return true; // a fresh sign-in
  // Any other event with a session only counts when the account actually
  // changed (e.g. a session restored for a different user).
  return sessionUserId != pushedAsUserId;
}
