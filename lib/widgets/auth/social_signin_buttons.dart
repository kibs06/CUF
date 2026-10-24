import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../utils/auth_error_messages.dart';
import '../app_error_toast.dart';

/// Google + Facebook sign-in buttons for the auth front door.
///
/// Logo-only circles: a white circle with the Google "G" and a blue circle
/// with the Facebook "f". Used in BOTH entry modes (create + sign-in): a new
/// customer tapping one gets the default `customer` profile row via
/// `AuthService`, and AuthGate swaps the root on the new session — no
/// navigation from here.
///
/// Social identity never grants anything beyond that row: sellers still go
/// through the application flow, and there is no admin role on the app.
/// A provider account with no email (common on Facebook) still signs in —
/// the user is asked to add one in Edit Profile afterwards.
class SocialSigninButtons extends StatefulWidget {
  const SocialSigninButtons({
    super.key,
    this.requireExistingAccount = false,
    this.onNeedsRegistration,
  });

  /// When true (the Sign in screen), a Gmail with no account routes to
  /// account creation instead of auto-provisioning a customer. The Create
  /// screen leaves this false so one tap still registers instantly.
  final bool requireExistingAccount;

  /// Called with the Gmail address when [requireExistingAccount] bounces an
  /// unknown address — the host switches to create mode and explains why.
  final ValueChanged<String?>? onNeedsRegistration;

  @override
  State<SocialSigninButtons> createState() => _SocialSigninButtonsState();
}

class _SocialSigninButtonsState extends State<SocialSigninButtons> {
  /// Which provider is mid-flight ('google', 'facebook', or null).
  String? _pending;

  Future<void> _signIn(
    String provider,
    Future<Map<String, dynamic>> Function() call,
  ) async {
    if (_pending != null) return;
    setState(() => _pending = provider);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final result = await call();
      if (!mounted) return;
      if (result['needsRegistration'] == true) {
        widget.onNeedsRegistration?.call(result['email'] as String?);
        return;
      }
      if (result['browserLaunched'] == true) {
        // Hosted OAuth: the browser now owns the login. The session arrives
        // on solvision://auth/callback and AuthGate routes to the shell —
        // nothing more to do here but release the button and say so.
        AppErrorToast.show(
          context,
          message: 'Continue signing in with Facebook in your browser — '
              'you will return here automatically.',
        );
        return;
      }
      if (result['success'] == true) {
        // AuthGate owns the post-login swap — nothing to push here.
        if (result['emailMissing'] == true) {
          AppErrorToast.show(
            context,
            message:
                'Signed in — please add your email in Edit Profile so order updates can reach you.',
          );
        }
      } else {
        AppErrorToast.show(
          context,
          message:
              auth.errorMessage ?? 'Social sign-in failed. Please try again.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppErrorToast.show(context, message: friendlyAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 24),
            Expanded(
              child: Divider(
                  color: Colors.white.withValues(alpha: 0.22)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Text(
                'OR',
                style: AppConstants.monoStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
            Expanded(
              child: Divider(
                  color: Colors.white.withValues(alpha: 0.22)),
            ),
            const SizedBox(width: 24),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LogoButton(
              semanticsLabel: 'Continue with Google',
              busy: _pending == 'google',
              enabled: _pending == null,
              background: Colors.white,
              border: Border.all(
                color: AppConstants.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
              onTap: () => _signIn(
                'google',
                () => auth.signInWithGoogle(
                  serverClientId: AppConstants.googleServerClientId.isEmpty
                      ? null
                      : AppConstants.googleServerClientId,
                  requireExistingAccount: widget.requireExistingAccount,
                ),
              ),
              child: SvgPicture.string(
                _googleGsvg,
                width: 26,
                height: 26,
              ),
            ),
            const SizedBox(width: 16),
            _LogoButton(
              semanticsLabel: 'Continue with Facebook',
              busy: _pending == 'facebook',
              enabled: _pending == null,
              background: const Color(0xFF1877F2),
              onTap: () =>
                  _signIn('facebook', auth.signInWithFacebookOAuth),
              child: const Icon(
                Icons.facebook,
                color: Colors.white,
                size: 30,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular logo-only button shared by both providers.
///
/// The spoken / test label lives in [semanticsLabel] so the visible UI stays
/// logo-only without losing accessibility.
class _LogoButton extends StatelessWidget {
  const _LogoButton({
    required this.semanticsLabel,
    required this.busy,
    required this.enabled,
    required this.background,
    required this.onTap,
    required this.child,
    this.border,
  });

  final String semanticsLabel;
  final bool busy;
  final bool enabled;
  final Color background;
  final Border? border;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: GestureDetector(
        onTap: enabled && !busy ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.6,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: border,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Official Google "G" mark (multicolor, 48x48 viewBox).
const String _googleGsvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/>
<path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/>
<path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238A11.91 11.91 0 0 1 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/>
<path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303a12.04 12.04 0 0 1-4.087 4.452l.003-.002 6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/>
</svg>
''';
