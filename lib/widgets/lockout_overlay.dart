import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

  /// A non-dismissable security alert dialog shown when the user's account
  /// is locked due to too many failed login attempts.
  ///
  /// Shows where the attempts came from (the location the attempt's IP
  /// resolves to, its coordinates, the network that owns it) and the device
  /// details, if provided, then offers three actions:
  /// - Reset password (primary)
  /// - This wasn't me (secondary danger)
  /// - Wait X minutes instead (tertiary)
  ///
  /// When the lockout timer expires while the overlay is showing,
  /// the UI automatically transitions to an expired state informing
  /// the user that their account is unlocked and they can try again.
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
    /// Where the attempts came from: `Manila, National Capital Region,
    /// Philippines`, its coordinate pair, and the network that owns the
    /// address. **City-level only** — see [IpGeolocationService]; the card
    /// says so to the customer rather than implying a street address.
    String? location,
    String? coordinates,
    String? network,
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
        location: location,
        coordinates: coordinates,
        network: network,
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
    this.location,
    this.coordinates,
    this.network,
    this.onResetPassword,
    this.onReportIntrusion,
  });

  final String email;
  final int remainingMinutes;
  final String? device;
  final String? ipAddress;
  final String? location;
  final String? coordinates;
  final String? network;
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
  bool _isExpired = false;

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

  bool get _hasLocation => _place.isNotEmpty;

  String get _place => widget.location?.trim() ?? '';

  /// `14.6042° N, 120.9822° E · Globe Telecom Inc. (AS132199)`, or ''.
  String get _locationDetail => [
    widget.coordinates ?? '',
    widget.network ?? '',
  ].where((part) => part.trim().isNotEmpty).join(' · ');

  late final bool _hasDeviceDetails =
      _hasLocation ||
      _locationDetail.isNotEmpty ||
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
          _isExpired = true;
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

    final mins = widget.remainingMinutes <= 0 ? 1 : widget.remainingMinutes;

    if (_isExpired) {
      return _buildExpiredState();
    }

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

  // ── Expired state ──────────────────────────────────────────
  Widget _buildExpiredState() {
    return PopScope(
      canPop: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: 4096,
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
                        _buildExpiredIcon(),
                        _buildExpiredTitle(),
                        _buildExpiredMessage(),
                        _buildExpiredActions(),
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

  Widget _buildExpiredIcon() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppConstants.success.withValues(alpha: 0.1),
        ),
        child: Icon(
          Icons.lock_open_outlined,
          size: 32,
          color: AppConstants.success,
        ),
      ),
    );
  }

  Widget _buildExpiredTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Text(
            'Lockout expired',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.email} \u00b7 your account is now unlocked',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredMessage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Text(
        'You can now try to log in again.',
        textAlign: TextAlign.center,
        style: AppConstants.bodyStyle(
          fontSize: 13,
          color: AppConstants.secondary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildExpiredActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => _dismiss(LockoutAction.wait),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppConstants.buttonRadius,
                ),
                elevation: 0,
              ),
              child: Text(
                'Try again',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF5EDE4),
                ),
              ),
            ),
          ),
        ],
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
            // The location leads: it is the answer to "where was this?", and
            // it is the one line an owner with a stolen password reads first.
            if (_hasLocation || _locationDetail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_hasLocation)
                            Text(
                              _place,
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.secondary,
                              ),
                            ),
                          if (_locationDetail.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: _hasLocation ? 2 : 0),
                              child: Text(
                                _locationDetail,
                                style: AppConstants.bodyStyle(
                                  fontSize: 11,
                                  color: AppConstants.secondary.withValues(
                                    alpha: 0.6,
                                  ),
                                ).copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
            // Said out loud, on the card, because "we know where they are" is
            // the one thing this data cannot support. It is a city centroid
            // from an IP block, not a device position.
            if (_hasLocation || _locationDetail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Location comes from the IP address, so it is city-level — '
                  'not a street address.',
                  style: AppConstants.bodyStyle(
                    fontSize: 10,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
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
