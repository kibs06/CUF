import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../constants/app_constants.dart';
import '../../services/mfa_service.dart';

/// Settings screen for two-factor authentication — shared by customers,
/// sellers, and admins (MFA is per-user at Supabase Auth).
///
/// States:
///  · MFA off  → "Enable" walks through enroll: QR (SVG from Supabase)
///               + manual secret → confirm with a 6-digit code.
///  · MFA on   → shows the enrolled factor with a Disable action.
class MfaSettingsScreen extends StatefulWidget {
  const MfaSettingsScreen({super.key});

  @override
  State<MfaSettingsScreen> createState() => _MfaSettingsScreenState();
}

class _MfaSettingsScreenState extends State<MfaSettingsScreen> {
  final MfaService _mfa = MfaService.instance;

  bool _loading = true;
  List<MfaFactorInfo> _factors = const [];

  @override
  void initState() {
    super.initState();
    _loadFactors();
  }

  Future<void> _loadFactors() async {
    setState(() => _loading = true);
    try {
      final factors = await _mfa.listFactors();
      if (!mounted) return;
      setState(() {
        _factors = factors;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[mfa_settings] listFactors failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load your 2FA status. Pull to retry.');
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppConstants.error : AppConstants.success,
      ),
    );
  }

  Future<void> _startEnrollment() async {
    MfaEnrollment? enrollment;

    // 1) Create the (unverified) factor BEFORE pushing the sheet so a
    //    failure surfaces as a snackbar on this screen, not inside the
    //    enrollment sheet.
    try {
      enrollment = await _mfa.enroll();
    } catch (e) {
      debugPrint('[mfa_settings] enroll failed: $e');
      _showMessage('Could not start 2FA setup. Please try again.', isError: true);
      return;
    }

    if (!mounted) {
      // User left the screen mid-flight — clean up the dangling factor.
      _mfa.cancelEnrollment(enrollment.factorId).catchError((_) {});
      return;
    }

    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _EnrollSheet(enrollment: enrollment!),
    );

    if (verified == true) {
      _showMessage('Two-factor authentication enabled');
    } else {
      // Abandoned or failed enrollment — remove the unverified factor.
      _mfa.cancelEnrollment(enrollment.factorId).catchError((_) {});
    }
    _loadFactors();
  }

  Future<void> _disableFactor(MfaFactorInfo factor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Turn off 2FA?',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Your account will be protected by your password only. '
          'You can turn 2FA back on at any time.',
          style: AppConstants.bodyStyle(
            fontSize: 14,
            color: AppConstants.secondary.withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Turn Off',
              style: TextStyle(color: AppConstants.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _mfa.unenroll(factor.id);
      _showMessage('Two-factor authentication disabled');
    } catch (e) {
      debugPrint('[mfa_settings] unenroll failed: $e');
      _showMessage('Could not disable 2FA. Please try again.', isError: true);
    }
    _loadFactors();
  }

  @override
  Widget build(BuildContext context) {
    final verifiedFactors = _factors.where((f) => f.verified).toList();
    final enabled = verifiedFactors.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'Two-Factor Authentication',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppConstants.primary,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Status card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppConstants.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: (enabled ? AppConstants.success : AppConstants.secondary)
                              .withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          enabled ? Icons.shield_rounded : Icons.shield_outlined,
                          color: enabled ? AppConstants.success : AppConstants.secondary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              enabled ? '2FA is on' : '2FA is off',
                              style: AppConstants.bodyStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              enabled
                                  ? 'Your sign-ins require a code from your authenticator app.'
                                  : 'Add an extra layer of protection with an authenticator app (Google Authenticator, Authy, 1Password…).',
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: AppConstants.secondary.withValues(alpha: 0.6),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (!enabled)
                  FilledButton.icon(
                    onPressed: _startEnrollment,
                    icon: const Icon(Icons.add_moderator_outlined, size: 18),
                    label: const Text('Enable 2FA'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppConstants.buttonRadius,
                      ),
                    ),
                  )
                else
                  ...verifiedFactors.map(
                    (f) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppConstants.borderGray.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.smartphone_outlined,
                              color: AppConstants.secondary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.friendlyName ?? 'Authenticator app',
                                  style: AppConstants.bodyStyle(fontSize: 15),
                                ),
                                Text(
                                  'Verified · requires a code at every sign-in',
                                  style: AppConstants.bodyStyle(
                                    fontSize: 12,
                                    color: AppConstants.secondary.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _disableFactor(f),
                            child: Text(
                              'Disable',
                              style: TextStyle(color: AppConstants.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

}

// ─── Enrollment bottom sheet: QR + secret + confirm ─────────────────
class _EnrollSheet extends StatefulWidget {
  final MfaEnrollment enrollment;

  const _EnrollSheet({required this.enrollment});

  @override
  State<_EnrollSheet> createState() => _EnrollSheetState();
}

class _EnrollSheetState extends State<_EnrollSheet> {
  final _codeController = TextEditingController();
  final MfaService _mfa = MfaService.instance;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code to confirm.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _mfa.verifyEnrollment(
        factorId: widget.enrollment.factorId,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'That code didn\'t match. Try the next one.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Set up your authenticator',
                style: AppConstants.bodyStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '1. Scan the QR with your authenticator app\n'
                '2. Enter the 6-digit code it shows',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppConstants.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
                  // Supabase returns the QR as a raw SVG string.
                  child: SvgPicture.string(widget.enrollment.qrCodeSvg),
                ),
              ),
              const SizedBox(height: 12),
              // Manual fallback for users who can't scan.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      'Can\'t scan? Enter this code in your app:',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      widget.enrollment.secret,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  hintText: '123456',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppConstants.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  minimumSize: const Size.fromHeight(48),
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
                    : const Text('Confirm & Turn On'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppConstants.secondary.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
