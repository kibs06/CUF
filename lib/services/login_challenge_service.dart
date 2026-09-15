import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_trust_service.dart';
import 'email_otp_service.dart';
import 'mfa_service.dart';

/// The outcome of evaluating a freshly password-authenticated login against
/// the account's trusted-device list.
@immutable
class LoginChallengeDecision {
  /// True when the caller must NOT proceed: the session has to be withdrawn
  /// and an email OTP completed first.
  final bool requiresChallenge;

  /// The device this install claims to be — null when it could not be
  /// established (in which case [requiresChallenge] is false: fail open).
  final String? deviceId;

  /// Best-effort label for the challenge screen ("the code is for the phone
  /// you're signing in on").
  final String? deviceLabel;

  /// Why no challenge was raised — diagnostics only, never shown to a user.
  final String? skipReason;

  const LoginChallengeDecision._({
    required this.requiresChallenge,
    this.deviceId,
    this.deviceLabel,
    this.skipReason,
  });

  static LoginChallengeDecision proceed({String? reason}) =>
      LoginChallengeDecision._(requiresChallenge: false, skipReason: reason);

  static LoginChallengeDecision challenge({
    required String deviceId,
    String? deviceLabel,
  }) => LoginChallengeDecision._(
    requiresChallenge: true,
    deviceId: deviceId,
    deviceLabel: deviceLabel,
  );
}

/// Decides whether a password login needs the new-device email OTP step-up,
/// and owns the trusted-device state machine around it (ANQUI item 16,
/// Part B). `AuthProvider.login` delegates here so the decision is testable
/// with fake gateways instead of the Supabase singletons.
///
/// The decision itself is one line of [DeviceTrustPolicy]; everything else
/// is failure handling, and the governing rule is:
///
///   **Never lock a legitimate user out because of our own plumbing.**
///
/// So every *evaluation* failure (secure storage unavailable, `trusted_devices`
/// unreadable, device id missing) fails OPEN — the login proceeds exactly as
/// it did before this feature existed. Only a definite "this device is not
/// trusted and the account has no TOTP factor" raises the challenge, and once
/// raised, a failure to *send* the code fails CLOSED (the login does not
/// complete) because that is the point of the feature.
class LoginChallengeService {
  LoginChallengeService({
    DeviceTrustGateway? deviceTrust,
    MfaGateway? mfa,
    EmailOtpGateway? otp,
  }) : _deviceTrust = deviceTrust ?? DeviceTrustService.instance,
       _mfa = mfa ?? MfaService.instance,
       _otp = otp ?? EmailOtpService.instance;

  final DeviceTrustGateway _deviceTrust;
  final MfaGateway _mfa;
  final EmailOtpGateway _otp;

  /// Called after the password check passed but before the login is allowed
  /// to complete. Reads (and, when the device is already known, refreshes)
  /// the trusted-device row. `userId` must be the just-authenticated user.
  Future<LoginChallengeDecision> evaluate({required String userId}) async {
    final deviceId = await _deviceTrust.currentDeviceId();
    if (deviceId == null) {
      // Secure storage is unusable on this install — we cannot tell whether
      // this is a new device, so we must not challenge (every login would
      // be challenged forever).
      return LoginChallengeDecision.proceed(reason: 'device_id_unavailable');
    }

    final label = await _deviceTrust.currentDeviceLabel();

    // "Known" now means we still hold the SECRET the server checks
    // (public.device_is_trusted()), not merely that a trusted_devices row
    // exists. A row without a local secret leaves the gate shut, so it must
    // not be treated as a cleared device — that is exactly the state an
    // existing install is in right after this feature ships.
    var deviceKnown = await _deviceTrust.hasDeviceSecret(userId);
    if (deviceKnown) {
      try {
        // Confirm the server still lists this device: a row deleted from the
        // security screen must re-challenge, even though we still hold the
        // (now useless) secret.
        deviceKnown = await _deviceTrust.isTrusted(
          userId: userId,
          deviceId: deviceId,
        );
      } catch (e) {
        // A transient read failure is not evidence of a revoked device, and
        // we DO hold the credential the gate looks for — keep the optimistic
        // answer rather than mailing a code that would be pure friction.
        debugPrint('[DeviceTrust] trusted_devices read failed: $e');
      }
    }

    var mfaEnabled = false;
    if (!deviceKnown) {
      try {
        mfaEnabled = await _mfa.isMfaEnabled();
      } catch (e) {
        // Unknown factor state → assume NO MFA so the extra challenge is
        // still applied. Erring toward the challenge can only add friction
        // the user can clear; erring away from it would silently disable
        // the feature on exactly the accounts that need it.
        debugPrint('[DeviceTrust] MFA state unavailable: $e');
        mfaEnabled = false;
      }
    }

    if (!DeviceTrustPolicy.requiresEmailOtpChallenge(
      deviceKnown: deviceKnown,
      mfaEnabled: mfaEnabled,
    )) {
      // Known device (bump last_seen) or an MFA account clearing the step-up
      // with its authenticator. Either way record/refresh the row so the
      // device is not re-evaluated on the next login. Best-effort: a failed
      // write only means the row is refreshed next time.
      //
      // For the MFA branch this mint is expected to FAIL at this point: the
      // session is still AAL1 (the TOTP challenge has not run yet), and the
      // server only accepts a stepped-up session. AuthProvider mints again
      // once the session reaches AAL2 — see ensureDeviceTrusted().
      await _recordDevice(deviceId, label);
      return LoginChallengeDecision.proceed(
        reason: deviceKnown ? 'known_device' : 'mfa_satisfies_step_up',
      );
    }

    return LoginChallengeDecision.challenge(deviceId: deviceId, deviceLabel: label);
  }

  /// Emails a sign-in code for [email]. Throws on failure — the caller must
  /// NOT complete the login when this fails.
  Future<void> sendChallengeCode(String email) => _otp.sendLoginCode(email);

  /// Verifies the code the user typed. Returns the now-authenticated user;
  /// the caller adopts the session it establishes.
  Future<User> verifyChallengeCode({
    required String email,
    required String code,
  }) async {
    final response = await _otp.verifyLoginCode(email: email, token: code);
    // A verification that returns no user has not signed anyone in. Reading
    // the client's `currentUser` as a fallback would mask that (and would
    // make this service depend on the global client) — fail instead.
    final user = response.user;
    if (user == null) {
      throw const AuthException('That code did not start a session.');
    }
    return user;
  }

  /// Returns true when a session restored from storage should be asked for a
  /// code before it is trusted with gated data.
  ///
  /// This is the repair path for installs that predate the server-side gate:
  /// they hold a valid session but no device secret. It asks the SERVER
  /// whether the gate is actually shut (`device_gate_open()`), so while
  /// enforcement is switched off this is false and the app adds no friction —
  /// and the moment enforcement is switched on, the next launch of an
  /// affected install repairs itself instead of showing empty screens.
  Future<bool> needsStepUpOnRestoredSession({required String userId}) async {
    if (await _deviceTrust.hasDeviceSecret(userId)) return false;
    try {
      return !await _deviceTrust.isGateOpen();
    } catch (e) {
      // A probe we cannot read must not force a code on a legitimate user.
      debugPrint('[DeviceTrust] gate probe failed: $e');
      return false;
    }
  }

  /// Marks the current install's device trusted for [userId] and stores the
  /// minted secret so every later request satisfies the server gate. Called
  /// after the challenge, after a sign-up verification, and after an MFA
  /// session reaches AAL2. Returns the minted secret, or null if the server
  /// sent none / refused (a password-only session is refused by design).
  Future<String?> markDeviceTrusted({
    required String userId,
    String? deviceId,
    String? deviceLabel,
  }) async {
    final id = deviceId ?? await _deviceTrust.currentDeviceId();
    if (id == null) return null;
    final label = deviceLabel ?? await _deviceTrust.currentDeviceLabel();
    return _recordDevice(id, label);
  }

  Future<List<TrustedDevice>> listDevices() => _deviceTrust.listTrusted();

  Future<void> revokeDevice(String deviceId) => _deviceTrust.revoke(deviceId);

  /// Best-effort row write — never throws. Callers treat failure as "the
  /// device will be re-evaluated next login", not as an error state.
  /// Returns the minted secret when the server issued one.
  Future<String?> _recordDevice(String deviceId, String? label) async {
    try {
      return await _deviceTrust.trust(deviceId: deviceId, deviceLabel: label);
    } catch (e) {
      debugPrint('[DeviceTrust] Could not record trusted device: $e');
      return null;
    }
  }
}
