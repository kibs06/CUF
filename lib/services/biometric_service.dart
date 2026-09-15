import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for biometric authentication and secure credential storage.
///
/// Wraps [LocalAuthentication] for fingerprint/face prompts and
/// [FlutterSecureStorage] for persisting login credentials on device.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Storage keys
  static const _keyEmail = 'bio_email';
  static const _keyPassword = 'bio_password';
  static const _keyEnabled = 'bio_enabled';
  static const _keyDeclined = 'bio_declined';

  /// Check if the device supports biometric authentication.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Trigger the biometric authentication prompt.
  /// Returns `true` if authentication succeeded.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Verify your identity to sign in to CUFMAI',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Persist user credentials securely for biometric re-auth.
  Future<void> saveCredentials(String email, String password) async {
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  /// Retrieve saved credentials. Returns `null` if biometric login is
  /// not enabled or credentials are missing.
  Future<Map<String, String>?> getSavedCredentials() async {
    final enabled = await _storage.read(key: _keyEnabled);
    if (enabled != 'true') return null;
    final email = await _storage.read(key: _keyEmail);
    final password = await _storage.read(key: _keyPassword);
    if (email == null || password == null) return null;
    return {'email': email, 'password': password};
  }

  /// Quick check — is biometric login enabled?
  Future<bool> isBiometricEnabled() async {
    final enabled = await _storage.read(key: _keyEnabled);
    return enabled == 'true';
  }

  /// Check whether user has declined biometric enrollment.
  Future<bool> hasDeclinedBiometric() async {
    final declined = await _storage.read(key: _keyDeclined);
    return declined == 'true';
  }

  /// Mark that the user declined biometric enrollment (don't ask again).
  Future<void> declineBiometric() async {
    await _storage.write(key: _keyDeclined, value: 'true');
  }

  /// Clear all stored credentials and biometric preference.
  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyEnabled);
    // Keep _keyDeclined so we don't re-ask after logout
  }

  /// Full wipe of BIOMETRIC state — everything this service owns, including
  /// the declined flag.
  ///
  /// Deliberately NOT `deleteAll()`. The secure store is shared with
  /// [DeviceTrustService] (the per-install device id and the per-account
  /// step-up secrets) and [AccountManager], so a blanket wipe would destroy
  /// this device's identity: the phone would look brand new on the next login
  /// — re-triggering the OTP step-up — and, with server-side device
  /// enforcement on, its credential would be gone. Only this service's own
  /// keys are cleared. Guarded by
  /// test/services/device_trust_persistence_test.dart.
  Future<void> clearAll() async {
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyEnabled);
    await _storage.delete(key: _keyDeclined);
  }
}
