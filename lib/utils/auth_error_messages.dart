import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown when the request never reached GoTrue at all (no route to the
/// server, DNS failure, timeout). Deliberately says nothing about the
/// password: we do not know anything about it yet.
const String authErrorNetwork =
    "We couldn't reach CUFMAI. Check your connection and try again.";

/// Shared copy for an already-registered email — used by BOTH the code-keyed
/// mapper (user_already_exists / email_exists) and the register screen's
/// inline pre-submit duplicate-email check, so the two paths can never drift
/// into inconsistent wording.
const String authErrorEmailExists =
    'An account with this email already exists. Try logging in instead.';

/// Maps a Supabase [AuthException] to a human-readable message, keyed on the
/// stable `error.code` — NEVER on `error.message` text, which can change
/// between Supabase versions (codes are the stable contract).
///
/// Security note: `invalid_credentials` and `user_not_found` intentionally
/// share one message so a sign-in attempt can never reveal whether an email
/// exists in the system.
String friendlyAuthError(AuthException e) {
  // AuthWeakPasswordException already carries code 'weak_password' via
  // ErrorCode.weakPassword, but the explicit type check keeps the copy
  // correct even if a future SDK stops stamping it.
  if (e is AuthWeakPasswordException) {
    return "That password's too weak. Use at least 6 characters.";
  }

  switch (e.code) {
    case 'invalid_credentials':
    case 'user_not_found':
      return "That email or password isn't right. Double-check and try again, "
          'or reset your password.';
    case 'email_not_confirmed':
      return 'Confirm your email first — check your inbox for the link we sent.';
    case 'user_already_exists':
    case 'email_exists':
      return authErrorEmailExists;
    case 'weak_password':
      return "That password's too weak. Use at least 6 characters.";
    case 'email_address_invalid':
      // Server-side rejection, NOT necessarily a typo: GoTrue returned this for
      // a well-formed Gmail address on the live project (Sep 16, 2026, see
      // docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md §5.1), so the copy
      // must stay true for BOTH a typo and a correct address we cannot mail.
      return 'That email address was rejected — check it for typos, or try a '
          'different address.';
    case 'email_address_not_authorized':
      // The mailer refusing the RECIPIENT (the built-in SMTP only serves
      // addresses inside the Supabase organization). Nothing the user typed
      // caused this, and no amount of retrying fixes it — so say so instead of
      // blaming the address. Both codes here are server-side only: the Dart
      // SDK's ErrorCode enum does not list them, hence the raw strings.
      return "We couldn't deliver email to that address — that one is on us. "
          'Contact support and we will sort it out.';
    case 'over_email_send_rate_limit':
      // Reached by the email-OTP resend button too — Supabase rate-limits
      // per address AND per IP, so this must never fail silently.
      return 'Too many attempts. Try again in about a minute.';
    case 'otp_expired':
    case 'otp_invalid':
    case 'invalid_token':
      // GoTrue reports a wrong OR expired email OTP as one of these.
      return "That code didn't match or has expired. Request a new one.";
    case 'otp_disabled':
      return 'Email codes are not available right now. Please contact support.';
    case 'over_request_rate_limit':
      return 'Too many attempts. Wait a moment and try again.';
    case 'signup_disabled':
      return 'New sign-ups are temporarily unavailable. Please try again later.';
    default:
      // Unknown/absent code — log the real details for debugging (the app's
      // existing logging surface is debugPrint; nothing goes to the UI).
      debugPrint(
        '[AuthError] Unmapped auth error — code="${e.code}" '
        'message="${e.message}" status=${e.statusCode}',
      );
      return 'Something went wrong. Please try again.';
  }
}

/// True when [error] PROVES the server rejected the credentials themselves.
///
/// This is the only shape of failure a brute-force counter may count: a wrong
/// password, or an account GoTrue declines to confirm exists (the two share
/// one message so sign-in can never enumerate addresses).
///
/// Everything else — a socket that never opened, a DNS failure, a timeout, a
/// 429, a 5xx — says nothing about whether the password was right, so it must
/// not move the lockout machinery. Measured Sep 17, 2026 on the Pixel 4
/// emulator: with the device in airplane mode (the login screen's own banner
/// already read "No internet connection") five taps on "Log In" produced the
/// full 30-minute "Multiple failed login attempts were detected from a
/// device" lockout — plus the warning e-mail, the push and the admin
/// `failed_logins` row — without one password ever leaving the device. The
/// correct password is then refused locally for the whole 30 minutes.
///
/// `AuthRetryableFetchException` (gotrue's transport failure) carries a NULL
/// `code`, so the code test below excludes it by construction.
bool isCredentialRejection(Object error) {
  if (error is! AuthException) return false;
  return error.code == 'invalid_credentials' || error.code == 'user_not_found';
}

/// Maps ANY error thrown from an auth call to a user-safe string.
///
/// [AuthException]s are translated by code via [friendlyAuthError]; anything
/// else (network failures, unexpected exceptions) is logged and reduced to a
/// generic message. Raw exception text, codes and stack traces never reach
/// the UI from here.
String friendlyAuthErrorMessage(Object error, {StackTrace? stackTrace}) {
  if (error is AuthException) {
    // A gotrue TRANSPORT failure is an AuthException with no code. It must
    // not be read as a rejected credential ("check your typing") when the
    // request never reached the server.
    if (error is AuthRetryableFetchException) return authErrorNetwork;
    return friendlyAuthError(error);
  }
  if (error is SocketException || error is TimeoutException) {
    debugPrint('[AuthError] Transport failure: $error');
    return authErrorNetwork;
  }
  debugPrint('[AuthError] Non-auth error: $error');
  if (stackTrace != null) {
    debugPrint('[AuthError] $stackTrace');
  }
  return 'Something went wrong. Please try again.';
}
