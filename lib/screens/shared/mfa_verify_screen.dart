import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/mfa_service.dart';

/// Shown between password entry and the shell when the signed-in user
/// has MFA enrolled but the session is still AAL1. The session already
/// exists — verifying here upgrades it to AAL2 and the auth stream
/// emits `mfaChallengeVerified`, so AuthGate routes onward by itself.
///
/// Shared by every role — the gate is one screen, not one per shell.
class MfaVerifyScreen extends StatefulWidget {
  final String factorId;
  final VoidCallback onVerified;

  /// Injectable for tests; defaults to the shared singleton.
  final MfaGateway? mfaService;

  const MfaVerifyScreen({
    super.key,
    required this.factorId,
    required this.onVerified,
    this.mfaService,
  });

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  late final MfaGateway _mfa;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mfa = widget.mfaService ?? MfaService.instance;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

  @override
  Widget build(BuildContext context) {
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
                    Icons.shield_outlined,
                    size: 36,
                    color: AppConstants.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Two-Step Verification',
                  style: AppConstants.headlineStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code from your authenticator app.',
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
                    fillColor: Colors.white,
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
                    // Auto-submit as soon as the 6th digit lands.
                    if (value.length == 6 && !_submitting) _submit();
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
                        : const Text('Verify'),
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
