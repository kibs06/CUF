import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/account_entry_screen.dart';
import 'dismiss_on_signin.dart';

/// True when the shopper already has an account behind this session.
///
/// Reads the provider first (it is what the UI routes from) and falls back to
/// the live Supabase session, because a just-completed sign-in can land one
/// build before [AuthProvider] publishes its snapshot.
bool hasAccount(BuildContext context) {
  if (context.read<AuthProvider>().isAuthenticated) return true;
  return SupabaseSession.exists;
}

/// Guards an action that needs an account.
///
/// **Browsing is open to everyone; acting is not.** A fresh install lands in
/// the storefront with no account (the Shopee/Lazada model, and what the
/// customer portal does with `RequireAuth`), so the moment a shopper reaches
/// for something that belongs to a person — the cart, checkout, their profile
/// — the app asks for an account instead of failing quietly.
///
/// Returns `true` when the caller may proceed: already signed in, or signed in
/// from the prompt this call just showed. Returns `false` when the shopper
/// backed out or the form was dismissed without a session, in which case the
/// caller must do nothing at all.
///
/// The form is pushed ABOVE the caller (product page, store page) and closes
/// itself once it hands the screen back to the gate — either because a session
/// appeared ([DismissOnSignIn]) or because the gate took over with a state it
/// renders itself ([PopsWhenGateTakesOver]) — so the shopper comes back to
/// exactly where they were aiming, and the original action then runs against
/// the new session.
Future<bool> requireSignIn(BuildContext context, {String? reason}) async {
  final auth = context.read<AuthProvider>();
  if (auth.isAuthenticated) return true;

  // Captured before any await: the caller's context must not be touched after
  // the sheet and the form have been on screen.
  final navigator = Navigator.of(context);

  final wantsToSignIn = await showSignInPrompt(context, reason: reason);
  if (wantsToSignIn != true) return false;

  await navigator.push(_signInRoute());

  return auth.isAuthenticated || SupabaseSession.exists;
}

/// Opens the create-account / sign-in front door without the explanatory
/// sheet — for screens that are already the prompt (the guest Profile and
/// Notifications tabs).
Future<bool> openSignIn(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final navigator = Navigator.of(context);

  await navigator.push(_signInRoute());

  return auth.isAuthenticated || SupabaseSession.exists;
}

/// The account form, wrapped in the two hand-off rules that decide when it is
/// finished with the screen:
///
///  * a session appeared → dismiss ([DismissOnSignIn]);
///  * the gate has a state it renders itself → dismiss
///    ([PopsWhenGateTakesOver]).
Route<void> _signInRoute() => MaterialPageRoute<void>(
      builder: (_) => const PopsWhenGateTakesOver(
        child: DismissOnSignIn(child: AccountEntryScreen()),
      ),
    );

/// True when AuthGate has taken the screen over and must be visible.
///
/// These states are not shell states: the gate renders them itself — an emailed
/// sign-up confirmation code, a new-device challenge, or a password-recovery
/// session waiting for a new password. Any of them means the shopper has to see
/// the gate right now, not a form sitting on top of it.
bool gateTakesOver(AuthProvider auth) =>
    auth.pendingSignupVerification != null ||
    auth.pendingDeviceChallenge != null ||
    auth.pendingPasswordRecovery != null;

/// Steps a pushed auth screen aside the moment AuthGate owns the screen.
///
/// Pushing [AccountEntryScreen] above the gate is what returns the shopper to
/// the page they were on after signing in. But the gate has states it renders
/// UNDERNEATH that route, and a pushed form then hides them: a login that lands
/// in the new-device step-up withdrew its own session, so the form sits there
/// looking like a sign-in that did nothing while the code screen waits
/// invisibly below it. The same trap applies to a sign-up that moved on to its
/// emailed code, and to a recovery link.
///
/// Everything from this form upward is dismissed — the create-account flow can
/// push a register screen of its own above it — which reveals the gate.
class PopsWhenGateTakesOver extends StatefulWidget {
  const PopsWhenGateTakesOver({super.key, required this.child});

  final Widget child;

  @override
  State<PopsWhenGateTakesOver> createState() => _PopsWhenGateTakesOverState();
}

class _PopsWhenGateTakesOverState extends State<PopsWhenGateTakesOver> {
  /// One dismissal is enough: after it, this route is gone (or going), and a
  /// second pass would pop the gate's own route out from under the app.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final bool gateOwnsScreen =
        context.select<AuthProvider, bool>(gateTakesOver);

    if (gateOwnsScreen && !_dismissed) {
      _dismissed = true;
      // Never pop during build: the gate is swapping its own child in this
      // very frame, and the navigator must not be touched mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dismiss();
      });
    }

    return widget.child;
  }

  void _dismiss() {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route == null) return;

    // Drop anything the form pushed (register / seller application) so this
    // form is the top route again, then drop it. What is left is the gate.
    if (route.isActive) {
      navigator.popUntil((r) => r == route);
    }
    navigator.maybePop();
  }
}

/// The one-line reason sheet shown before the form.
///
/// Deliberately a bottom sheet, not a dialog: it is the same interruption
/// pattern as "add to cart" feedback, it can be dismissed by dragging, and it
/// keeps "Keep browsing" as an obvious, non-punitive exit.
Future<bool?> showSignInPrompt(BuildContext context, {String? reason}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppConstants.surfaceLight,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppConstants.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 30,
                  color: AppConstants.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sign in to continue',
                textAlign: TextAlign.center,
                style: AppConstants.headlineStyle(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                reason ??
                    'Create a free CUFMAI account or sign in to your existing '
                        'one. You can keep browsing without an account.',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppConstants.buttonRadius,
                    ),
                  ),
                  child: Text(
                    'Sign in or create account',
                    style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold,
                      color: AppConstants.inkInverse,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(
                  'Keep browsing',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Session presence without a BuildContext, so the check stays valid after the
/// pushed form closes.
abstract final class SupabaseSession {
  static bool get exists {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      // Supabase not initialized (widget tests): no session to report.
      return false;
    }
  }
}
