import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/email_otp_service.dart';
import '../../utils/auth_error_messages.dart';
import '../../widgets/otp_code_field.dart';

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
///
/// **Shape of the screen.** One column, one idea per line: a warm icon badge,
/// the headline, a single sentence with the device emphasised inline, the
/// segmented code field, the expiry countdown, then the primary action. The
/// previous version gave the device its own parenthetical paragraph and put the
/// code in one masked field, so the eye had to hunt for the position of the
/// next digit and the device line competed with the headline.
///
/// Everything below the layout is unchanged: the same `EmailOtpPolicy` rules,
/// the same single 1-second ticker, the same error mapping, and the same
/// auto-submit as soon as the last digit lands.
class EmailOtpScreen extends StatefulWidget {
  final EmailOtpPurpose purpose;

  /// Where the code was sent. Shown obfuscated (`j•••@gmail.com`).
  final String email;

  /// Best-effort device label for the new-device copy.
  final String? deviceLabel;

  /// Verifies [code]. Must THROW on a wrong/expired code so the screen can
  /// show the mapped message.
  final Future<void> Function(String code) onVerify;

  /// A send failure the CALLER already hit — currently the new-device
  /// challenge whose code could not be mailed inside `AuthProvider.login`
  /// (rate limit, mailer rejection). Shown from the first frame, because the
  /// user is staring at a screen whose whole premise is "a code is on its way";
  /// without this the gate would look like it simply swallowed their login.
  /// The user recovers with Resend (or leaves with the cancel button), so a
  /// send failure does not have to fail the step-up silently.
  final String? initialError;

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
    this.initialError,
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
  /// Handle on the segmented field, used only to empty it (after a resend, and
  /// after a rejected code). The digits themselves are mirrored in [_code] so
  /// the Verify button can read them without reaching into the widget.
  final _codeKey = GlobalKey<OtpCodeFieldState>();

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

  /// The digits entered so far.
  String _code = '';

  bool _submitting = false;
  bool _sending = false;

  /// Set while a rejection is on screen, so the boxes themselves show what the
  /// message is about instead of the message floating on its own.
  bool _rejected = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _otp = widget.otpService ?? EmailOtpService.instance;
    _sentAt = widget.now();
    // Deliberately does NOT set `_rejected`: the red code boxes mean "the code
    // you typed is wrong", and nothing has been typed yet.
    _error = widget.initialError;
    _startTicker();
    if (!widget.codeAlreadySent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial: true));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int get _resendWait => EmailOtpPolicy.resendWaitSeconds(_sentAt, widget.now());
  int get _validity => EmailOtpPolicy.validitySeconds(_sentAt, widget.now());

  bool get _isComplete => _code.length == EmailOtpPolicy.codeLength;

  String get _title =>
      widget.purpose == EmailOtpPurpose.signupVerification
      ? 'Verify your email'
      : 'Verify this device';

  IconData get _icon => widget.purpose == EmailOtpPurpose.signupVerification
      ? Icons.mark_email_unread_outlined
      // A shield-with-a-check reads as "confirm this is really you" without
      // implying a new device is necessarily a problem.
      : Icons.verified_user_outlined;

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

  // ── Ink tones ───────────────────────────────────────────────────
  // Measured against the white page, not picked by eye: the description sits
  // at ~7.1:1 and the timers at ~4.9:1, so both clear AA for normal text.
  // Going lighter for the "tertiary" tiers would slip 13px text under 4.5:1, so
  // the hierarchy is carried by size and spacing rather than by fading text out.

  /// The description sentence.
  Color get _descriptionInk =>
      AppConstants.secondary.withValues(alpha: 0.70);

  /// Expiry countdown + resend row.
  Color get _mutedInk => AppConstants.secondary.withValues(alpha: 0.60);

  /// One sentence, with the device name emphasised inline rather than given
  /// its own parenthetical paragraph. Kept as spans so it still line-breaks as
  /// a single sentence.
  List<InlineSpan> get _descriptionSpans {
    if (widget.purpose == EmailOtpPurpose.signupVerification) {
      return [
        TextSpan(
          text:
              'We sent a ${EmailOtpPolicy.codeLength}-digit code to '
              '$_maskedEmail. Enter it to activate your account.',
        ),
      ];
    }

    final device = widget.deviceLabel?.trim();
    final label = (device == null || device.isEmpty)
        ? 'a device we have not seen before'
        : device;

    return [
      const TextSpan(text: 'New sign-in from '),
      TextSpan(
        text: label,
        style: AppConstants.bodyStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.secondary,
          height: 1.5,
        ),
      ),
      TextSpan(
        // A send that already failed must not be narrated as a success — the
        // paragraph would contradict the error line right under the boxes.
        text: widget.initialError == null
            ? '. We sent a ${EmailOtpPolicy.codeLength}-digit code to '
                  '$_maskedEmail.'
            : '. We could not send the code to $_maskedEmail yet — '
                  'use Resend below.',
      ),
    ];
  }

  /// User edits clear the previous rejection, so the message and the red
  /// borders always describe the digits currently on screen. Programmatic
  /// clears (after a failed verify) do not fire this, which is why the
  /// rejection survives that one.
  void _onCodeChanged(String value) {
    setState(() {
      _code = value;
      if (_error != null || _rejected) {
        _error = null;
        _rejected = false;
      }
    });
  }

  Future<void> _verify() async {
    // Guards the auto-submit path: a re-completion while a verify is already
    // in flight must not fire a second request.
    if (_submitting) return;

    final code = _code.trim();
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
        _rejected = true;
      });
      // Empty the row so the next attempt is a straight re-key instead of six
      // backspaces. Cleared AFTER the messaging is set, and programmatic, so
      // _onCodeChanged does not wipe the message we just showed.
      _code = '';
      _codeKey.currentState?.clear();
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
      _rejected = false;
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
        _code = '';
      });
      _codeKey.currentState?.clear();
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

  Widget get _iconBadge => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppConstants.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(_icon, size: 28, color: AppConstants.primary),
      );

  Widget get _expiryLine {
    final expired = _validity == 0;
    final color = expired ? AppConstants.error : _mutedInk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          expired ? Icons.error_outline : Icons.schedule,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          expired
              ? 'That code has expired — request a new one.'
              : 'Code expires in '
                    '${EmailOtpPolicy.formatCountdown(_validity)}',
          style: AppConstants.bodyStyle(fontSize: 13, color: color),
        ),
      ],
    );
  }

  Widget get _verifyButton {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        // Deliberately still ENABLED with an incomplete code: tapping it is how
        // the user learns what is missing, which beats a dead button that says
        // nothing. The low-emphasis fill is the visual cue, matching the
        // `SolePrimaryButton` disabled convention (primary at 60%).
        onPressed: _submitting ? null : _verify,
        style: FilledButton.styleFrom(
          backgroundColor: _isComplete
              ? AppConstants.primary
              : AppConstants.primary.withValues(alpha: 0.6),
          disabledBackgroundColor: AppConstants.primary.withValues(alpha: 0.6),
          foregroundColor: AppConstants.inkInverse,
          shape: RoundedRectangleBorder(
            borderRadius: AppConstants.buttonRadius,
          ),
        ),
        child: _submitting
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppConstants.inkInverse,
                ),
              )
            : Text(
                'Verify',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.inkInverse,
                ),
              ),
      ),
    );
  }

  /// One control in both states so the row never shifts: inert and muted while
  /// the cooldown runs, an active accent link the moment it reaches zero.
  Widget get _resendRow {
    final ready = _resendWait == 0 && !_sending && !_submitting;
    return TextButton(
      onPressed: ready ? () => _send() : null,
      style: TextButton.styleFrom(
        foregroundColor: AppConstants.primary,
        disabledForegroundColor: _mutedInk,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: const Size(0, 44),
        textStyle: AppConstants.bodyStyle(fontSize: 13),
      ),
      child: Text(
        _sending
            ? 'Sending…'
            : _resendWait > 0
            ? 'Resend code in ${_resendWait}s'
            : 'Resend code',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // 16px gutters, not 32: six 48px code boxes plus their gaps need
            // 328px, which is exactly what a 360dp phone has left here. The
            // code row is the one thing on this page the user has to hit, so
            // it gets the width; the text still wraps comfortably.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconBadge,
                const SizedBox(height: 24),
                Text(
                  _title,
                  style: AppConstants.headlineStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(children: _descriptionSpans),
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: _descriptionInk,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                OtpCodeField(
                  key: _codeKey,
                  length: EmailOtpPolicy.codeLength,
                  hasError: _rejected,
                  onChanged: _onCodeChanged,
                  onCompleted: (_) => _verify(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                _expiryLine,
                const SizedBox(height: 24),
                _verifyButton,
                const SizedBox(height: 16),
                _resendRow,
                if (widget.onCancel != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _submitting ? null : widget.onCancel,
                    style: TextButton.styleFrom(
                      // Accent, not ink: this IS an escape hatch, and it used
                      // to read as static text.
                      foregroundColor: AppConstants.primary,
                      disabledForegroundColor: _mutedInk,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      minimumSize: const Size(0, 44),
                      textStyle: AppConstants.bodyStyle(fontSize: 14),
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
