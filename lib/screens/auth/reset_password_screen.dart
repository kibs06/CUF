import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/auth_error_messages.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';

/// The set-new-password screen — the last step of a password-reset e-mail.
///
/// Reached only from `AuthGate`, while `AuthProvider.pendingPasswordRecovery`
/// is set: the customer tapped the button in a reset mail, GoTrue verified the
/// token and handed the app a short-lived recovery session, and the link
/// itself is the proof it is them. All that is left is the new password.
///
/// The shape mirrors the app's other e-mail gate (`EmailOtpScreen`): one
/// column, one idea per line, the same icon badge / headline / field / primary
/// button vocabulary — and NO navigation of its own. Success is a STATE change
/// (the provider clears the pending recovery, AuthGate rebuilds into the
/// customer's shell), the same rule the OTP gates follow, so this screen never
/// races the auth stream for the route.
///
/// The recovery session is a real session, so the customer ends up signed in —
/// which is the point: the reset IS a sign-in, minus the password they have
/// forgotten.
class ResetPasswordScreen extends StatefulWidget {
  /// The account the reset link belongs to. Shown so the customer can see
  /// which account they are setting a password for (a reset link can be opened
  /// on a device that was signed in as somebody else).
  final String email;

  /// Sets the new password. Must THROW on refusal so this screen can show the
  /// mapped message — see `AuthProvider.applyRecoveredPassword`.
  final Future<void> Function(String newPassword) onSubmit;

  /// Leaves the reset without changing anything. The session is kept, so the
  /// customer is signed in with their existing password and can change it
  /// later from Account security.
  final VoidCallback? onCancel;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  /// The project's own rule, spelled exactly as the register and seller screens
  /// spell it (live `password_min_length` = 6). GoTrue enforces it again
  /// server-side, and that answer is mapped too (`weak_password`), so this is
  /// guidance rather than the only guard.
  static const int _minPasswordLength = 6;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.onSubmit(_passwordController.text);
      if (!mounted) return;
      // No navigation on success: the provider has cleared the pending
      // recovery, so AuthGate swaps this screen for the customer's shell on
      // its next build. The toast answers the one question that swap leaves
      // open — and it survives it, because the messenger sits above the
      // navigator.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated — you are signed in.'),
          backgroundColor: AppConstants.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _subtitle {
    final email = widget.email.trim();
    if (email.isEmpty) {
      return 'Your reset link signed you in. Choose a new password to finish.';
    }
    return 'Your reset link signed you in as $email. '
        'Choose a new password to finish.';
  }

  Widget get _badge => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppConstants.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.lock_reset_rounded,
          size: 28,
          color: AppConstants.primary,
        ),
      );

  Widget get _errorBox => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppConstants.error.withValues(alpha: 0.08),
            borderRadius: AppConstants.fieldRadius,
            border: Border.all(
              color: AppConstants.error.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppConstants.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error!,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _badge),
                        const SizedBox(height: 22),
                        Text(
                          'Choose a new password',
                          textAlign: TextAlign.center,
                          style: AppConstants.headlineStyle(fontSize: 24),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _subtitle,
                          textAlign: TextAlign.center,
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            color: AppConstants.secondary.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AuthTextField(
                          label: 'New password',
                          hint: 'At least $_minPasswordLength characters',
                          controller: _passwordController,
                          obscureText: true,
                          passwordField: true,
                          prefixIcon: Icons.lock_outline,
                          autofillHints: const [AutofillHints.newPassword],
                          // Rebuilds only the strength meter below; the field
                          // itself validates live through its own validator.
                          onChanged: (_) => setState(() {}),
                          validator: (val) =>
                              (val == null || val.length < _minPasswordLength)
                                  ? 'Password must be at least '
                                      '$_minPasswordLength characters'
                                  : null,
                        ),
                        const SizedBox(height: AuthSpacing.s8),
                        PasswordStrengthMeter(
                          password: _passwordController.text,
                        ),
                        const SizedBox(height: AuthSpacing.s16),
                        AuthTextField(
                          label: 'Confirm new password',
                          hint: 'Re-enter your new password',
                          controller: _confirmController,
                          obscureText: true,
                          passwordField: true,
                          prefixIcon: Icons.lock_outline,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: _submitting ? null : _submit,
                          validator: (val) => val != _passwordController.text
                              ? 'Those passwords do not match'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _errorBox,
                        ],
                        const SizedBox(height: 24),
                        SolePrimaryAuthButton(
                          label: 'Set new password',
                          isLoading: _submitting,
                          onPressed: _submitting ? null : _submit,
                        ),
                        if (widget.onCancel != null)
                          TextButton(
                            onPressed:
                                _submitting ? null : widget.onCancel,
                            style: TextButton.styleFrom(
                              foregroundColor: AppConstants.secondary,
                            ),
                            child: const Text('Not now'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
