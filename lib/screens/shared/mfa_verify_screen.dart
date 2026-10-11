import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/email_otp_service.dart';
import '../../services/mfa_service.dart';

/// Shown between password entry and the shell when the signed-in user
/// has MFA enrolled but the session is still AAL1. The session already
/// exists — verifying here upgrades it to AAL2 and the auth stream
/// emits `mfaChallengeVerified`, so AuthGate routes onward by itself.
///
/// Shared by every role — the gate is one screen, not one per shell.
///
/// Two ways out besides the code itself:
///  · **Sign out** — for the wrong account. Supplied by the gate.
///  · **Lost your authenticator app?** — emails a code to [email], and
///    entering it turns 2FA off for the account (see
///    `supabase/functions/reset-two-factor`). The user then signs in again
///    with their password. This is weaker than the authenticator on purpose:
///    anyone who has the password AND the inbox can do it.
class MfaVerifyScreen extends StatefulWidget {
  final String factorId;
  final VoidCallback onVerified;

  /// Signs the user out. When null the "Sign out" action is not shown. The
  /// gate supplies it from `AuthProvider.logout`, so this screen itself never
  /// reaches for the provider and stays testable without one.
  final Future<void> Function()? onSignOut;

  /// The account's email, used by the lost-authenticator recovery. When null
  /// or empty the recovery action is not shown.
  final String? email;

  /// Injectable for tests; defaults to the shared singleton.
  final MfaGateway? mfaService;

  /// Injectable for tests; defaults to the shared singleton.
  final EmailOtpGateway? otpService;

  const MfaVerifyScreen({
    super.key,
    required this.factorId,
    required this.onVerified,
    this.onSignOut,
    this.email,
    this.mfaService,
    this.otpService,
  });

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  late final MfaGateway _mfa;
  late final EmailOtpGateway _otp;
  bool _submitting = false;
  String? _error;

  /// True once the user has asked for the email code. The same code field is
  /// reused, but submitting it turns 2FA off instead of checking an app code.
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    _mfa = widget.mfaService ?? MfaService.instance;
    _otp = widget.otpService ?? EmailOtpService.instance;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canRecover => (widget.email ?? '').isNotEmpty;

  Future<void> _submit() async {
    if (_recovering) {
      await _submitRecovery();
      return;
    }
    final code = _codeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _mfa.verifyChallenge(factorId: widget.factorId, code: code);
      if (!mounted) return;
      // Clear the spinner before notifying — the caller usually unmounts
      // this screen, but if it doesn't, the button must not spin forever.
      setState(() => _submitting = false);
      widget.onVerified();
    } on AuthException catch (e) {
      // Supabase returns 422 for a wrong/expired code — show a friendly
      // inline error and let the user retry (rate limits still apply
      // server-side after several misses).
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'That code didn\'t match or has expired. Try the next one.';
      });
      debugPrint('[mfa_verify] verify failed: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Something went wrong. Check your connection and try again.';
      });
      debugPrint('[mfa_verify] unexpected error: $e');
    }
  }

  /// Emails a code to the account and switches the screen into recovery mode.
  Future<void> _startRecovery() async {
    final email = widget.email;
    if (email == null || email.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _otp.sendLoginCode(email);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _recovering = true;
        _codeController.clear();
      });
      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not send a code right now. Try again in a minute.';
      });
      debugPrint('[mfa_verify] recovery send failed: $e');
    }
  }

  /// Checks the emailed code, then turns 2FA off on the server. Both steps
  /// must succeed; the server logs every session out once the factor is gone,
  /// so the user is signed out afterwards and signs in with their password.
  Future<void> _submitRecovery() async {
    final email = widget.email;
    final code = _codeController.text.trim();
    if (email == null || email.isEmpty) return;
    if (!EmailOtpPolicy.isCompleteCode(code)) {
      setState(() => _error = 'Enter the 6-digit code we emailed you.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _otp.verifyLoginCode(email: email, token: code);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'That code didn\'t match or has expired. Try the next one.';
      });
      debugPrint('[mfa_verify] recovery code failed: ${e.message}');
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Something went wrong. Check your connection and try again.';
      });
      debugPrint('[mfa_verify] recovery code error: $e');
      return;
    }

    try {
      await _mfa.resetTwoFactor();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not turn off 2FA. Try again.';
      });
      debugPrint('[mfa_verify] reset failed: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    // The factor is gone and the server ended every session, so the only
    // sensible next step is the sign-in screen.
    await widget.onSignOut?.call();
  }

  void _cancelRecovery() {
    setState(() {
      _recovering = false;
      _error = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _recovering ? 'Turn off two-step verification?' : 'Two-Step Verification';
    final subtitle = _recovering
        ? 'We emailed a 6-digit code to ${widget.email}. Entering it turns off '
            '2FA for this account. You will sign in again with your password.'
        : 'Enter the 6-digit code from your authenticator app.';

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppConstants.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _recovering ? Icons.mail_outline : Icons.shield_outlined,
                    size: 36,
                    color: AppConstants.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: AppConstants.headlineStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _codeController,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: AppConstants.surfaceLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppConstants.borderGray.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppConstants.primary,
                        width: 1.5,
                      ),
                    ),
                    hintText: '••••••',
                  ),
                  onSubmitted: (_) => _submit(),
                  onChanged: (value) {
                    // Auto-submit the authenticator code as soon as the 6th
                    // digit lands. The recovery code is NOT auto-submitted:
                    // it turns 2FA off, so it needs a deliberate tap.
                    if (!_recovering && value.length == 6 && !_submitting) {
                      _submit();
                    }
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppConstants.buttonRadius,
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(_recovering ? 'Turn off 2FA' : 'Verify'),
                  ),
                ),
                if (_canRecover && !_recovering) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    key: const ValueKey('mfa_lost_authenticator'),
                    onPressed: _submitting ? null : _startRecovery,
                    child: Text(
                      'Lost your authenticator app?',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.primary,
                      ),
                    ),
                  ),
                ],
                if (_recovering) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    key: const ValueKey('mfa_use_authenticator'),
                    onPressed: _submitting ? null : _cancelRecovery,
                    child: Text(
                      'Use my authenticator app instead',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
                if (widget.onSignOut != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting ? null : widget.onSignOut,
                    child: Text(
                      'Sign out',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
