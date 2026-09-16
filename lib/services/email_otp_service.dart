import 'package:supabase_flutter/supabase_flutter.dart';

import 'deep_link_service.dart';

/// What an email OTP is being used for. The scope is deliberately narrow
/// (client decision, ANQUI item 16): this is NOT passwordless login.
enum EmailOtpPurpose {
  /// Proves the address is real right after sign-up. Nothing else in the
  /// app is reachable until it clears.
  signupVerification,

  /// Step-up challenge for a password login from a device the account has
  /// never been seen on (`public.trusted_devices`).
  newDeviceChallenge,
}

/// Pure, I/O-free rules for the email OTP screens: code shape, resend
/// cooldown, and how long a code stays valid.
///
/// Kept separate from [EmailOtpService] so the counts-down UI and the
/// resend button are unit-testable without a Supabase client.
class EmailOtpPolicy {
  EmailOtpPolicy._();

  /// Digit count Supabase is configured to send. Must match
  /// `supabase/config.toml` → `[auth.email] otp_length` (6).
  static const int codeLength = 6;

  /// How long a code stays valid, in seconds. Must match
  /// `supabase/config.toml` → `[auth.email] otp_expiry` (3600 = 1 hour).
  /// If that config changes, change this — the screen's countdown is only
  /// honest if the two agree.
  static const int expirySeconds = 3600;

  /// Client-side pause before the resend button re-enables. Supabase's own
  /// `[auth.email] max_frequency` is 1s per address, but a 60s pause keeps
  /// users from burning the (also per-IP) server rate limit while still
  /// feeling responsive; a 429 is surfaced explicitly if it still happens.
  static const int resendCooldownSeconds = 60;

  /// True when [code] is exactly [codeLength] digits.
  static bool isCompleteCode(String code) {
    final trimmed = code.trim();
    if (trimmed.length != codeLength) return false;
    for (final unit in trimmed.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  /// Seconds still to wait before [sentAt] allows another send. 0 = ready.
  static int resendWaitSeconds(DateTime sentAt, DateTime now) {
    final elapsed = now.difference(sentAt).inSeconds;
    final remaining = resendCooldownSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Seconds left before a code sent at [sentAt] expires. 0 = expired.
  static int validitySeconds(DateTime sentAt, DateTime now) {
    final remaining = expirySeconds - now.difference(sentAt).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// `59:59` / `12:03` — the countdown label next to "code expires in".
  static String formatCountdown(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final minutes = (safe ~/ 60).toString().padLeft(2, '0');
    final secs = (safe % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}

/// Interface over the two GoTrue OTP calls the app needs — lets widget and
/// provider tests inject a fake instead of touching the real Supabase API
/// (same convention as `MfaGateway` in `mfa_service.dart`).
abstract class EmailOtpGateway {
  /// Sends/refreshes the sign-up confirmation code for [email].
  Future<void> sendSignupCode(String email);

  /// Verifies the sign-up code. On success the response carries a session,
  /// which is what finally lets the `profiles` row be written (the table's
  /// INSERT policy requires `auth.uid() = id`).
  Future<AuthResponse> verifySignupCode({
    required String email,
    required String token,
  });

  /// Sends a sign-in code for an EXISTING account ([email] is never created
  /// by this call — `shouldCreateUser: false`).
  Future<void> sendLoginCode(String email);

  /// Verifies the sign-in code and establishes the session.
  Future<AuthResponse> verifyLoginCode({
    required String email,
    required String token,
  });
}

/// Thin wrapper over Supabase Auth's email OTP API (`supabase_flutter`
/// 2.10 / gotrue 2.22). Both purposes reuse the SAME GoTrue endpoints —
/// only the [OtpType] and the send call differ:
///
/// | purpose            | send                  | verify                    |
/// |--------------------|-----------------------|---------------------------|
/// | signupVerification | `resend(type: signup)`| `verifyOTP(type: signup)` |
/// | newDeviceChallenge | `signInWithOtp`       | `verifyOTP(type: email)`  |
///
/// Throwing methods rethrow the underlying [AuthException]; the UI maps the
/// stable `error.code` to copy via `utils/auth_error_messages.dart`.
///
/// ⚠️ OPERATIONAL REQUIREMENT: the 6-digit code only reaches the user if the
/// project's email templates render `{{ .Token }}`. The default sign-up
/// template does; the default **magic link** template renders
/// `{{ .ConfirmationURL }}` instead, so the new-device challenge needs the
/// template edited to include the code (see
/// `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md`).
class EmailOtpService implements EmailOtpGateway {
  EmailOtpService._();
  static final EmailOtpService instance = EmailOtpService._();

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _client.auth;

  // ── Part A — sign-up confirmation ─────────────────────────────

  @override
  Future<void> sendSignupCode(String email) async {
    // `resend` (not a second signUp) is the supported "send it again" call
    // for signup confirmations — it works while the account is unconfirmed
    // and is what the resend button uses.
    //
    // It needs the same redirect as `signUp`: the link embedded in THIS
    // e-mail is built from this call's `emailRedirectTo`, so leaving it out
    // would send a resent confirmation back to the site URL — the exact
    // browser dead end the deep link exists to remove. (`resend` accepts it
    // for `OtpType.signup` only, which is the only type used here.)
    await _auth.resend(
      email: email.trim(),
      type: OtpType.signup,
      emailRedirectTo: DeepLinkService.authConfirmRedirect,
    );
  }

  @override
  Future<AuthResponse> verifySignupCode({
    required String email,
    required String token,
  }) async {
    return _auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.signup,
    );
  }

  // ── Part B — new-device step-up ───────────────────────────────

  @override
  Future<void> sendLoginCode(String email) async {
    await _auth.signInWithOtp(
      email: email.trim(),
      // An unknown device must never be able to create an account.
      shouldCreateUser: false,
    );
  }

  @override
  Future<AuthResponse> verifyLoginCode({
    required String email,
    required String token,
  }) async {
    // OtpType.email is the OTP half of the magic-link flow: email + token
    // verifies the one-time code and returns a real session.
    return _auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }
}
