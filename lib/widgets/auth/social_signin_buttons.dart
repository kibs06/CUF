import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../utils/auth_error_messages.dart';
import '../app_error_toast.dart';

/// Google + Facebook sign-in buttons for the auth front door.
///
/// Used in BOTH entry modes (create + sign-in): a new customer tapping one
/// gets the default `customer` profile row via `AuthService`, and AuthGate
/// swaps the root on the new session — no navigation from here.
///
/// Social identity never grants anything beyond that row: sellers still go
/// through the application flow, and there is no admin role on the app.
/// A provider account with no email (common on Facebook) still signs in —
/// the user is asked to add one in Edit Profile afterwards.
class SocialSigninButtons extends StatefulWidget {
  const SocialSigninButtons({super.key});

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
        _SocialButton(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata,
          busy: _pending == 'google',
          enabled: _pending == null,
          onTap: () => _signIn('google', auth.signInWithGoogle),
        ),
        const SizedBox(height: 10),
        _SocialButton(
          label: 'Continue with Facebook',
          icon: Icons.facebook,
          busy: _pending == 'facebook',
          enabled: _pending == null,
          onTap: () => _signIn('facebook', auth.signInWithFacebook),
        ),
      ],
    );
  }
}

/// White pill button matching the biometric-login style on the dark video
/// background — kept separate so both providers share one look.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: enabled && !busy ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.6,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: AppConstants.surfaceLight,
              borderRadius: AppConstants.buttonRadius,
              border: Border.all(
                color: AppConstants.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppConstants.primary,
                    ),
                  )
                else
                  Icon(icon, color: AppConstants.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  busy ? 'Redirecting…' : label,
                  style: AppConstants.bodyStyle(
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
