import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// A non-dismissable security alert dialog shown when the user's account
/// is locked due to too many failed login attempts.
///
/// Shows device details (if provided) and offers three actions:
/// - Reset password (primary)
/// - This wasn't me (secondary danger)
/// - Wait X minutes instead (tertiary)
///
/// Usage: call [LockoutOverlay.show] from any context. The dialog can
/// only be dismissed via one of its own actions.
class LockoutOverlay {
  LockoutOverlay._();

  /// Shows the lockout security overlay. Returns the user's chosen action
  /// as a [LockoutAction], or null if the dialog was dismissed.
  static Future<LockoutAction?> show(
    BuildContext context, {
    required String email,
    required int remainingMinutes,
    String? device,
    String? ipAddress,
    Future<bool> Function(String email)? onResetPassword,
    Future<bool> Function(String email)? onReportIntrusion,
  }) {
    return showGeneralDialog<LockoutAction>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Account locked',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) => _LockoutOverlayDialog(
        email: email,
        remainingMinutes: remainingMinutes,
        device: device,
        ipAddress: ipAddress,
        onResetPassword: onResetPassword,
        onReportIntrusion: onReportIntrusion,
      ),
    );
  }
}

/// The action the user chose from the lockout overlay.
enum LockoutAction { resetPassword, reportIntrusion, wait }

class _LockoutOverlayDialog extends StatefulWidget {
  const _LockoutOverlayDialog({
    required this.email,
    required this.remainingMinutes,
    this.device,
    this.ipAddress,
    this.onResetPassword,
    this.onReportIntrusion,
  });

  final String email;
  final int remainingMinutes;
  final String? device;
  final String? ipAddress;
  final Future<bool> Function(String email)? onResetPassword;
  final Future<bool> Function(String email)? onReportIntrusion;

  @override
  State<_LockoutOverlayDialog> createState() => _LockoutOverlayDialogState();
}

class _LockoutOverlayDialogState extends State<_LockoutOverlayDialog> {
  // ── Reset password state ──
  bool _resetLoading = false;
  String? _resetError;
  bool _resetSuccess = false;

  // ── Report intrusion state ──
  bool _reportConfirming = false;
  bool _reportLoading = false;
  String? _reportError;
  bool _reportSuccess = false;

  // ── Countdown timer ──
  late int _remainingSeconds;
  Timer? _countdownTimer;

  bool get _anyLoading => _resetLoading || _reportLoading;

  // ── Reset password ──
  Future<void> _handleResetPassword() async {
    if (_anyLoading) return;
    setState(() {
      _resetLoading = true;
      _resetError = null;
    });

    try {
      final success = await widget.onResetPassword?.call(widget.email) ?? true;
      if (!mounted) return;
      setState(() {
        _resetLoading = false;
        _resetSuccess = success;
        if (!success) {
          _resetError = 'Failed to send reset email. Please try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resetLoading = false;
        _resetError = 'Failed to send reset email. Please try again.';
      });
    }
  }

  // ── Report intrusion ──
  void _showReportConfirm() {
    setState(() => _reportConfirming = true);
  }

  void _cancelReportConfirm() {
    setState(() => _reportConfirming = false);
  }

  Future<void> _handleReportIntrusion() async {
    if (_anyLoading) return;
    setState(() {
      _reportLoading = true;
      _reportError = null;
      _reportConfirming = false;
    });

    try {
      final success =
          await widget.onReportIntrusion?.call(widget.email) ?? true;
      if (!mounted) return;
      setState(() {
        _reportLoading = false;
        _reportSuccess = success;
        if (!success) {
          _reportError = 'Failed to report. Please try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reportLoading = false;
        _reportError = 'Failed to report. Please try again.';
      });
    }
  }

  // ── Dismiss ──
  void _dismiss(LockoutAction action) {
    Navigator.of(context).pop(action);
  }

  late final bool _hasDeviceDetails =
      (widget.device != null && widget.device!.isNotEmpty) ||
          (widget.ipAddress != null && widget.ipAddress!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.remainingMinutes * 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _countdownTimer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _countdownText {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
        (widget.device != null && widget.device!.isNotEmpty) ||
            (widget.ipAddress != null && widget.ipAddress!.isNotEmpty);

    // If lockout already expired, adjust copy
    final mins = widget.remainingMinutes <= 0 ? 1 : widget.remainingMinutes;

    return PopScope(
      canPop: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: screenSize.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppConstants.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildIcon(),
                        _buildTitle(mins),
                        if (_hasDeviceDetails) _buildDeviceDetails(),
                        if (_resetSuccess) _buildResetSuccess(),
                        if (_reportSuccess) _buildReportSuccess(),
                        if (_resetError != null) _buildError(_resetError!),
                        if (_reportError != null) _buildError(_reportError!),
                        _buildActions(mins),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Icon ──────────────────────────────────────────────────────
  Widget _buildIcon() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppConstants.error.withValues(alpha: 0.1),
        ),
        child: Icon(
          Icons.gpp_maybe_outlined,
          size: 32,
          color: AppConstants.error,
        ),
      ),
    );
  }

  // ── Title + subtitle ─────────────────────────────────────────
  Widget _buildTitle(int mins) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Text(
            'Account temporarily locked',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.email} \u00b7 unlocks in $_countdownText',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Multiple failed login attempts were detected'
              '${_hasDeviceDetails ? ' from a device' : ''}. '
              'Reset your password if this was you, or report it if not.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Device details card ──────────────────────────────────────
  Widget _buildDeviceDetails() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.device != null && widget.device!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.phone_android,
                      size: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.device!,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.ipAddress != null && widget.ipAddress!.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.language,
                    size: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),          Expanded(
                      child: Text(
                        widget.ipAddress!,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary,
                        ).copyWith(fontFamily: 'monospace'),
                      ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Success states ───────────────────────────────────────────
  Widget _buildResetSuccess() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppConstants.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.success.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 16,
              color: AppConstants.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Check your email for a reset link.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportSuccess() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppConstants.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.success.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 16,
              color: AppConstants.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reported. Your account stays locked for your protection.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error state ──────────────────────────────────────────────
  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppConstants.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.error.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 16,
              color: AppConstants.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────
  Widget _buildActions(int mins) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          // Primary: Reset password
          if (!_reportSuccess) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _anyLoading ? null : _handleResetPassword,
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  disabledBackgroundColor:
                      AppConstants.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                  elevation: 0,
                ),
                child: _resetLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Reset password',
                        style: AppConstants.bodyStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFF5EDE4),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Secondary: This wasn't me
          if (!_reportSuccess && !_reportConfirming) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _anyLoading ? null : _showReportConfirm,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.error,
                  side: BorderSide(color: AppConstants.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: _reportLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppConstants.error,
                        ),
                      )
                    : Text(
                        "This wasn't me",
                        style: AppConstants.bodyStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.error,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Report confirmation step
          if (_reportConfirming) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppConstants.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.error.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    "Flag this as unauthorized? We'll notify the security team.",
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cancelReportConfirm,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppConstants.secondary,
                            side: BorderSide(
                              color: AppConstants.borderGray,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppConstants.buttonRadius,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.secondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _handleReportIntrusion,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppConstants.error,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppConstants.buttonRadius,
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Report',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Tertiary: Wait with countdown
          TextButton(
            onPressed:
                _anyLoading ? null : () => _dismiss(LockoutAction.wait),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: Text(
              _remainingSeconds > 0
                  ? 'Wait $_countdownText instead'
                  : 'Lockout expired',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
