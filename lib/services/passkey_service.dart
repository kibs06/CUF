// Supabase's Dart passkey API is annotated @experimental while the feature is
// in beta. Suppress the preview-API hint for this integration boundary only.
// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/exceptions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The operations the passkey UI needs. Exists so widget tests can inject a
/// fake instead of invoking Android Credential Manager (or Supabase).
abstract class PasskeyGateway {
  Future<bool> isSupported();
  Future<List<Passkey>> list();
  Future<Passkey> register();
  Future<AuthResponse> signIn();
  Future<void> delete(String passkeyId);
}

/// Real passkeys (WebAuthn): the private key lives in the device's credential
/// provider (Google Password Manager, fingerprint/face, screen lock, or a
/// security key). Supabase stores only the public key and issues the session.
///
/// Registration needs a signed-in, confirmed, non-anonymous user. Sign-in is
/// discoverable, so no email is needed — the platform picker chooses the
/// account from the passkey itself.
class PasskeyService implements PasskeyGateway {
  PasskeyService._();

  static final PasskeyService instance = PasskeyService._();

  final PasskeyAuthenticator _authenticator = PasskeyAuthenticator();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<bool> isSupported() async {
    // The customer app is native; the portal is a separate web deployment.
    if (kIsWeb) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final availability = await _authenticator.getAvailability().android();
          return availability.hasPasskeySupport;
        case TargetPlatform.iOS:
          final availability = await _authenticator.getAvailability().iOS();
          return availability.hasPasskeySupport;
        default:
          return false;
      }
    } catch (e) {
      // A missing/old Play Services build reports through the plugin channel;
      // treat that as "not available" rather than crashing the settings row.
      debugPrint('[passkey] availability check failed: $e');
      return false;
    }
  }

  @override
  Future<List<Passkey>> list() => _client.auth.passkey.list();

  @override
  Future<Passkey> register() => _client.auth.registerPasskey(_authenticator);

  @override
  Future<AuthResponse> signIn() =>
      _client.auth.signInWithPasskey(_authenticator);

  @override
  Future<void> delete(String passkeyId) =>
      _client.auth.passkey.delete(passkeyId: passkeyId);
}

/// True when the user simply dismissed the platform passkey sheet. Callers
/// should close quietly instead of showing an error toast.
bool isPasskeyCancellation(Object error) =>
    error is PasskeyAuthCancelledException;

/// Turns the plugin's platform exceptions and Supabase's error codes into
/// copy the customer can act on.
String passkeyErrorMessage(Object error) {
  if (error is PasskeyAuthCancelledException) {
    return 'Passkey setup was cancelled.';
  }
  if (error is NoCredentialsAvailableException) {
    return 'No CUFMAI passkey was found on this device. Sign in with your password, then add one in Account & Security.';
  }
  if (error is ExcludeCredentialsCanNotBeRegisteredException) {
    return 'This device already has a passkey for your account.';
  }
  if (error is MissingGoogleSignInException ||
      error is SyncAccountNotAvailableException) {
    return 'Sign in to a Google account on this device to use passkeys.';
  }
  if (error is DomainNotAssociatedException) {
    return 'Passkey setup for this app is not active yet. Please try again later.';
  }
  if (error is DeviceNotSupportedException ||
      error is PasskeyUnsupportedException) {
    return 'This device does not support passkeys.';
  }
  if (error is TimeoutException) {
    return 'The passkey request timed out. Please try again.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'passkey_disabled':
        return 'Passkeys are not enabled for CUFMAI yet. Please contact support.';
      case 'too_many_passkeys':
        return 'You have reached the passkey limit. Remove one before adding another.';
      case 'webauthn_credential_exists':
        return 'This device is already registered as a passkey.';
      case 'webauthn_credential_not_found':
        return 'That passkey is no longer registered. Try another one.';
      case 'webauthn_challenge_expired':
        return 'The passkey request expired. Please try again.';
      case 'webauthn_verification_failed':
        return 'We could not verify the passkey. Please try again.';
      case 'insufficient_aal':
        return 'Verify your two-factor authentication first, then manage passkeys.';
      case 'email_not_confirmed':
        return 'Confirm your email address before using passkeys.';
      case 'user_banned':
        return 'This account cannot use passkeys.';
      default:
        return error.message;
    }
  }
  return 'Could not complete the passkey request. Please try again.';
}
