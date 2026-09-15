import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/email_otp_service.dart';
import '../../utils/auth_error_messages.dart';

/// The ONE email-OTP screen in the app. Both halves of ANQUI item 16 use it
/// and differ only in [purpose] (copy + which send call is used):
///
///  • [EmailOtpPurpose.signupVerification] — the code sign-up already sent.
///  • [EmailOtpPurpose.newDeviceChallenge] — step-up for a sign-in from a
///    device the account has not been seen on.
///
/// It owns no auth state: the caller supplies [onVerify], which must throw on
/// failure, and (optionally) [onSend] for the resend button. That keeps the
/// screen reusable from the register screen, the seller flow, and the
/// new-device gate without a second, differently-behaved copy.
class EmailOtpScreen extends StatefulWidget {
  final EmailOtpPurpose purpose;

  /// Where the code was sent. Shown obfuscated (`j•••@gmail.com`).
  final String email;

  /// Best-effort device label for the new-device copy.
  final String? deviceLabel;

  /// Verifies [code]. Must THROW on a wrong/expired code so the screen can
  /// show the mapped message.
  final Future<void> Function(String code) onVerify;

  /// Sends (or resends) the code. Defaults to the [purpose]-appropriate call.
  final Future<void> Function()? onSend;

  /// False when the code still has to be sent (the new-device challenge —
  /// sign-up has already sent one by the time this screen appears). When
  /// false, the screen sends on first frame.
  final bool codeAlreadySent;

  /// Lets the user abandon the step (e.g. back to sign-in). Rendered as a
  /// text button only when non-null, so a hard gate stays hard.
  final VoidCallback? onCancel;

  /// Label for the [onCancel] button.
  final String cancelLabel;

  /// Injectable for tests; defaults to the shared singleton.
  final EmailOtpGateway? otpService;

  /// Injectable clock so cooldown/expiry behaviour is testable.
  final DateTime Function() now;

  const EmailOtpScreen({
    super.key,
    required this.purpose,
    required this.email,
    required this.onVerify,
    this.onSend,
    this.codeAlreadySent = true,
    this.onCancel,
    this.cancelLabel = 'Use a different account',
    this.otpService,
    this.now = DateTime.now,
    this.deviceLabel,
  });

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends State<EmailOtpScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  late final EmailOtpGateway _otp;
  Timer? _ticker;

  /// Single 1s ticker driving both the resend cooldown and the expiry
  /// countdown. Self-stopping when neither has anything left to count, so an
  /// idle screen is not rebuilding once a second forever.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_resendWait == 0 && _validity == 0) _ticker?.cancel();
    });
  }

  /// When the code currently in the user's inbox was sent. Drives both the
  /// resend cooldown and the expiry countdown.
  late DateTime _sentAt;

  bool _submitting = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _otp = widget.otpService ?? EmailOtpService.instance;
    _sentAt = widget.now();
    _startTicker();
    if (!widget.codeAlreadySent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial: true));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _resendWait => EmailOtpPolicy.resendWaitSeconds(_sentAt, widget.now());
  int get _validity => EmailOtpPolicy.validitySeconds(_sentAt, widget.now());

  String get _title =>
      widget.purpose == EmailOtpPurpose.signupVerification
      ? 'Verify your email'
      : 'Verify this device';

  String get _subtitle {
    if (widget.purpose == EmailOtpPurpose.signupVerification) {
      return 'We sent a ${EmailOtpPolicy.codeLength}-digit code to '
          '$_maskedEmail. Enter it to activate your account.';
    }
    final device = widget.deviceLabel?.trim();
    final where = (device == null || device.isEmpty)
        ? 'a device we have not seen before'
        : 'a new device ($device)';
    return 'You are signing in from $where. We emailed a '
        '${EmailOtpPolicy.codeLength}-digit code to $_maskedEmail to '
        'confirm it is you.';
  }

  IconData get _icon => widget.purpose == EmailOtpPurpose.signupVerification
      ? Icons.mark_email_unread_outlined
      : Icons.devices_other_outlined;

  /// `j•••@gmail.com` — enough to recognise, not enough to leak in a
  /// screenshot.
  String get _maskedEmail {
    final email = widget.email.trim();
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final name = email.substring(0, at);
    final domain = email.substring(at);
    if (name.length <= 1) return '$name•••$domain';
    return '${name[0]}•••$domain';
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (!EmailOtpPolicy.isCompleteCode(code)) {
      setState(() => _error =
          'Enter the ${EmailOtpPolicy.codeLength}-digit code we emailed you.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onVerify(code);
      if (!mounted) return;
      // The caller usually unmounts this screen; clear the spinner anyway so
      // a screen that stays put never spins forever.
      setState(() => _submitting = false);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyAuthError(e);
      });
      debugPrint('[email_otp] verify failed: ${e.code} ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Something went wrong. Check your connection and try again.';
      });
      debugPrint('[email_otp] unexpected error: $e');
    }
  }

  Future<void> _send({bool initial = false}) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final send = widget.onSend ??
          () => widget.purpose == EmailOtpPurpose.signupVerification
              ? _otp.sendSignupCode(widget.email)
              : _otp.sendLoginCode(widget.email);
      await send();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentAt = widget.now();
        _codeController.clear();
      });
      // A fresh code restarts both countdowns (the ticker self-stopped once
      // the previous code expired).
      _startTicker();
      if (!initial) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New code sent — check your inbox.'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      // Rate limits and mailer problems must be VISIBLE — a resend that
      // silently does nothing is worse than an error message.
      setState(() {
        _sending = false;
        _error = friendlyAuthError(e);
      });
      debugPrint('[email_otp] send failed: ${e.code} ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'We could not send the code. Check your connection and '
            'try again.';
      });
      debugPrint('[email_otp] unexpected send error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _resendWait == 0 && !_sending && !_submitting;
    final expired = _validity == 0;

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
                  child: Icon(_icon, size: 36, color: AppConstants.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  _title,
                  style: AppConstants.headlineStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: EmailOtpPolicy.codeLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
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
                  onSubmitted: (_) => _verify(),
                  onChanged: (value) {
                    // Auto-submit as soon as the last digit lands.
                    if (value.length == EmailOtpPolicy.codeLength &&
                        !_submitting) {
                      _verify();
                    }
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  expired
                      ? 'That code has expired — request a new one.'
                      : 'Code expires in '
                            '${EmailOtpPolicy.formatCountdown(_validity)}',
                  style: AppConstants.bodyStyle(
                    fontSize: 12.5,
                    color: expired
                        ? AppConstants.error
                        : AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
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
                    onPressed: _submitting ? null : _verify,
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
                const SizedBox(height: 8),
                TextButton(
                  onPressed: canResend ? () => _send() : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppConstants.primary,
                  ),
                  child: Text(
                    _sending
                        ? 'Sending…'
                        : _resendWait > 0
                        ? 'Resend code in ${_resendWait}s'
                        : 'Resend code',
                  ),
                ),
                if (widget.onCancel != null) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _submitting ? null : widget.onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: AppConstants.secondary,
                    ),
                    child: Text(widget.cancelLabel),
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
