import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown when the request never reached GoTrue at all (no route to the
/// server, DNS failure, timeout). Deliberately says nothing about the
/// password: we do not know anything about it yet.
const String authErrorNetwork =
    "We couldn't reach CUFMAI. Check your connection and try again.";

/// Shown when the request DID reach CUFMAI's auth service and that service
/// failed (HTTP 5xx) in a way whose reason we could not read.
///
/// The connection is fine, so telling the user to check it is wrong — but this
/// is the FALLBACK, not the 5xx message: a 5xx body that names its
/// `error_code` is answered by that code instead ([friendlyAuthErrorMessage]),
/// which is what keeps a mailer refusal from reading as "try again in a few
/// minutes".
const String authErrorServer =
    "CUFMAI couldn't finish that request. Please try again in a few minutes.";

/// Shared copy for a message OUR mailer could not deliver, whatever GoTrue
/// calls it. Two codes reach it on this project:
///
///  * `email_address_not_authorized` — the built-in mailer refusing a
///    recipient outside the Supabase organization;
///  * `unexpected_failure` — GoTrue's catch-all for a 5xx it raised itself,
///    measured here as `"Error sending recovery email"` (see the case below).
///
/// One constant for both, because both are server-side and unfixable by the
/// user: the wording must never blame their address, and it must never promise
/// that trying again helps. Deliberately "that email" rather than "to that
/// address" — the recipient is not what went wrong in either case.
const String authErrorMailNotSent =
    "We couldn't deliver that email — that one is on us. Contact support and we "
    'will sort it out.';

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
    case 'same_password':
      // Reachable from the recovery screen: GoTrue refuses a "new" password
      // that matches the current one. "Too weak" would be the wrong story —
      // the password is fine, it is just not NEW — and the customer has no way
      // to guess that from a generic failure, so the copy names it.
      return 'That is already your password — choose a different one.';
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
      return authErrorMailNotSent;
    case 'unexpected_failure':
      // GoTrue's catch-all for a 5xx it raised itself, and on this project the
      // reachable cause is the mailer. Measured on the live project (Oct 12,
      // 2026), the exact call "Forgot password?" makes:
      //
      //   POST /auth/v1/recover  {"email":"<an existing account>"}
      //   → 500 {"code":500,"error_code":"unexpected_failure",
      //          "msg":"Error sending recovery email"}
      //
      // while an address with no account answers 200 (GoTrue short-circuits
      // and mails nothing), so the 500 is a SEND failure, not a bad address.
      //
      // The auth log holds the reason the client never sees — the SMTP
      // handshake itself was refused:
      //
      //   error: 535 "5.7.8 Username and Password not accepted … - gsmtp"
      //
      // i.e. a stale Gmail App Password on the project's configured SMTP (see
      // docs/AI/FORGOT_PASSWORD_ARCHITECTURE.md for the full log row).
      //
      // This must not read as "try again in a few minutes": retrying is the
      // one thing that cannot work while the mailer cannot send, and it is
      // what makes the app look broken instead of unset-up.
      return authErrorMailNotSent;
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

/// The `error_code` inside a gotrue error BODY, or null when the body carries
/// none to read.
///
/// Only needed for 5xx — see [friendlyAuthErrorMessage], which is the single
/// caller. A body that is not the expected JSON object (an HTML error page
/// from a proxy, a truncated response, an empty body) answers null rather than
/// throwing, so the caller keeps its generic fallback.
String? _errorCodeFromBody(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final code = decoded['error_code'];
      if (code is String && code.isNotEmpty) return code;
    }
  } on FormatException {
    // Not JSON. Nothing to read — not an error in itself.
  }
  return null;
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
    if (error is AuthRetryableFetchException) {
      // gotrue throws this type for BOTH a lost connection (no status code) and
      // an HTTP 5xx from the server (status code set). Only the first means we
      // never reached it, so only the first gets the connection message.
      debugPrint('[AuthError] Fetch failed: $error');
      if (error.statusCode == null) return authErrorNetwork;
      // A 5xx DID reach us — but gotrue's `GotrueFetch._handleError` turns
      // EVERY status >= 500 into this same exception type and never reads the
      // body's `error_code`, so the code-keyed branches above are unreachable
      // for exactly the failures this project hits (a mailer that cannot
      // send). The body survives on the exception (`message: response.body`),
      // so recover the code from it and let the shared mapper answer.
      final code = _errorCodeFromBody(error.message);
      if (code != null) {
        return friendlyAuthError(
          AuthApiException(
            error.message,
            statusCode: error.statusCode,
            code: code,
          ),
        );
      }
      return authErrorServer;
    }
    return friendlyAuthError(error);
  }
  if (error is SocketException || error is TimeoutException) {
    debugPrint('[AuthError] Transport failure: $error');
    return authErrorNetwork;
  }
  // Social sign-in (Google / Facebook) throws plain Exceptions whose text IS
  // the user-safe copy — the native SDKs are not AuthExceptions, so without
  // this they all collapse into the generic fallback and the user can never
  // tell "not switched on yet" apart from a real failure. Only the exact
  // copy our own AuthService throws is passed through; everything else stays
  // generic so internal paths never leak to the UI.
  final socialMessage = _socialUserSafeMessage(error);
  if (socialMessage != null) return socialMessage;
  debugPrint('[AuthError] Non-auth error: $error');
  if (stackTrace != null) {
    debugPrint('[AuthError] $stackTrace');
  }
  return 'Something went wrong. Please try again.';
}

/// Returns the user-safe copy for a social-sign-in failure, or null when
/// [error] is not one of the known user-safe social failures.
///
/// Pass-through is deliberately narrow: only messages constructed by
/// `AuthService` ("Google/Facebook sign-in …") plus a user-cancelled sign-in
/// (which every provider SDK can produce) are shown. Anything else keeps the
/// generic fallback so SDK internals never reach the UI.
String? _socialUserSafeMessage(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  // The user backed out of the account picker / Login dialog. Not a failure:
  // say so instead of "something went wrong". Checked first so a cancelled
  // flow never matches anything below it.
  if (lower.contains('cancel')) return 'Sign-in was cancelled.';
  // Strip the "Exception: " prefix so the UI reads clean copy.
  final stripped =
      text.replaceFirst(RegExp(r'^[\w.]*Exception:\s*'), '').trim();
  if (stripped.isEmpty) return null;
  final strippedLower = stripped.toLowerCase();
  if (strippedLower.startsWith('google sign-in') ||
      strippedLower.startsWith('facebook sign-in') ||
      strippedLower.startsWith('facebook did not')) {
    return stripped;
  }
  return null;
}
