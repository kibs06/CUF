import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/auth_error_messages.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';

/// Change the signed-in account's password WITHOUT sending an e-mail.
///
/// This is the app's no-mail half of "forgot password": a customer who is
/// still signed in on this device (biometric sign-in, a session restored from
/// a previous launch, a lockout that is local rather than server-side) can set
/// a new password right here. Supabase permits it because `updateUser` acts on
/// the live session — its contract is explicit that the user must be signed in
/// (https://supabase.com/docs/reference/dart/auth-updateuser).
///
/// It deliberately does NOT ask for the old password: the customer using this
/// screen is the one who forgot it, so requiring it would send them back to
/// the e-mail link this path exists to avoid. Possession of the session is the
/// proof, exactly as it is for every other signed-in action.
///
/// The signed-OUT case is different and is not something a client can fix
/// safely: proving the account is yours without a delivered link or OTP would
/// mean letting anyone who types an address take the account over. That is why
/// the login screen's "Forgot password?" still mails a link, and why this
/// screen says so plainly instead of pretending otherwise.
class ChangePasswordScreen extends StatefulWidget {
  /// The account whose password is being changed. Shown so a customer on a
  /// shared or handed-down device can see whose password they are setting.
  final String email;

  /// Sets the new password. Must THROW on refusal so this screen can show the
  /// mapped message, and returns whether any requested "end other sessions"
  /// step succeeded — `false` is reported as a warning, never as a failed
  /// change, because the password has already been updated by then.
  final Future<bool?> Function(String newPassword) onSubmit;

  const ChangePasswordScreen({
    super.key,
    required this.onSubmit,
    this.email = '',
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  /// The project's own rule, spelled as the register and reset screens spell
  /// it (live `password_min_length` = 6). GoTrue enforces it again server-side.
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
      final otherSessionsEnded = await widget.onSubmit(
        _passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        otherSessionsEnded == false
            ? const SnackBar(
                content: Text(
                  'Password updated, but we could not end your other sessions. '
                  'Sign out those devices from Manage Login Device.',
                ),
                backgroundColor: AppConstants.statusPendingColor,
              )
            : const SnackBar(
                content: Text('Password updated.'),
                backgroundColor: AppConstants.success,
              ),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _subtitle {
    final email = widget.email.trim();
    final whose = email.isEmpty ? 'your account' : email;
    return 'Choose a new password for $whose. Nothing is emailed — you are '
        'already signed in on this device.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        foregroundColor: AppConstants.secondary,
        title: Text(
          'Change password',
          style: AppConstants.bodyStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: AppConstants.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.password_rounded,
                        size: 28,
                        color: AppConstants.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _subtitle,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    PasswordStrengthMeter(password: _passwordController.text),
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
                      Semantics(
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
                      ),
                    ],
                    const SizedBox(height: 24),
                    SolePrimaryAuthButton(
                      label: 'Update password',
                      isLoading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Signed out and forgot it? Use “Forgot password?” on the '
                      'sign-in screen — recovery needs a verified email.',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
