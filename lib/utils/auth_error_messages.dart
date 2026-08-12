import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      return "That doesn't look like a valid email address.";
    case 'over_email_send_rate_limit':
      return 'Too many attempts. Try again in about a minute.';
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

/// Maps ANY error thrown from an auth call to a user-safe string.
///
/// [AuthException]s are translated by code via [friendlyAuthError]; anything
/// else (network failures, unexpected exceptions) is logged and reduced to a
/// generic message. Raw exception text, codes and stack traces never reach
/// the UI from here.
String friendlyAuthErrorMessage(Object error, {StackTrace? stackTrace}) {
  if (error is AuthException) return friendlyAuthError(error);
  debugPrint('[AuthError] Non-auth error: $error');
  if (stackTrace != null) {
    debugPrint('[AuthError] $stackTrace');
  }
  return 'Something went wrong. Please try again.';
}
