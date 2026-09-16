import 'package:app/services/device_trust_service.dart';
import 'package:app/services/email_otp_service.dart';
import 'package:app/services/login_challenge_service.dart';
import 'package:app/services/mfa_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fakes for the three collaborators. Nothing here touches secure storage,
/// platform channels or the network, so the whole decision matrix — including
/// every failure branch — is exercised deterministically.
class FakeDeviceTrust implements DeviceTrustGateway {
  String? deviceId = 'device-1111-2222-3333';
  String? label = 'samsung SM-A155F · Android 14';

  /// Set the answer for the "is this device already trusted?" lookup.
  bool known = false;

  /// Does this install still hold the step-up secret for the account? This
  /// is the credential the SERVER checks, so it — not the row above — is what
  /// decides whether a device counts as known.
  bool secret = true;

  /// Answer to the "would the gate let this session through?" probe.
  bool gateOpen = true;

  /// How many times the gate was probed — the probe costs a round trip, so
  /// the paths that must not pay for it are pinned.
  int gateProbes = 0;

  /// The secret the server hands back from trust().
  final String mintedSecret = List.filled(64, 'a').join();

  Object? gateError;

  Object? idError;
  Object? lookupError;
  Object? trustError;
  Object? listError;
  Object? revokeError;

  final List<Map<String, String?>> trustCalls = [];
  final List<String> revoked = [];
  List<TrustedDevice> rows = const [];

  @override
  Future<String?> currentDeviceId() async {
    if (idError != null) throw idError!;
    return deviceId;
  }

  @override
  Future<String?> currentDeviceLabel() async => label;

  @override
  Future<bool> isTrusted({required String userId, required String deviceId}) async {
    if (lookupError != null) throw lookupError!;
    return known;
  }

  @override
  Future<bool> hasDeviceSecret(String userId) async => secret;

  @override
  Future<String?> currentDeviceToken(String userId) async =>
      secret ? '$deviceId:$mintedSecret' : null;

  @override
  Future<bool> isGateOpen() async {
    gateProbes++;
    if (gateError != null) throw gateError!;
    return gateOpen;
  }

  @override
  Future<String?> trust({required String deviceId, String? deviceLabel}) async {
    trustCalls.add({'deviceId': deviceId, 'label': deviceLabel});
    if (trustError != null) throw trustError!;
    return mintedSecret;
  }

  @override
  Future<List<TrustedDevice>> listTrusted() async {
    if (listError != null) throw listError!;
    return rows;
  }

  @override
  Future<void> revoke(String deviceId) async {
    if (revokeError != null) throw revokeError!;
    revoked.add(deviceId);
  }
}

class FakeMfa implements MfaGateway {
  bool enabled = false;
  Object? statusError;

  @override
  Future<bool> isMfaEnabled() async {
    if (statusError != null) throw statusError!;
    return enabled;
  }

  @override
  Future<MfaEnrollment> enroll({String? friendlyName}) async =>
      throw UnimplementedError();

  @override
  Future<void> verifyEnrollment({
    required String factorId,
    required String code,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelEnrollment(String factorId) async {}

  @override
  Future<void> unenroll(String factorId) async {}

  @override
  Future<MfaFactorInfo?> verifiedFactor() async => null;

  @override
  Future<void> verifyChallenge({
    required String factorId,
    required String code,
  }) async => throw UnimplementedError();
}

class FakeOtp implements EmailOtpGateway {
  final List<String> sentLoginCodes = [];
  final List<String> sentSignupCodes = [];
  Object? sendError;
  Object? verifyError;

  /// When null, verify throws (simulating Supabase returning no user).
  User? verifiedUser = User.fromJson({
    'id': 'user-1',
    'email': 'maria@gmail.com',
    'aud': 'authenticated',
    'created_at': '2026-01-01T00:00:00.000Z',
  });

  @override
  Future<void> sendLoginCode(String email) async {
    sentLoginCodes.add(email);
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> sendSignupCode(String email) async {
    sentSignupCodes.add(email);
    if (sendError != null) throw sendError!;
  }

  @override
  Future<AuthResponse> verifyLoginCode({
    required String email,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
    return AuthResponse(user: verifiedUser);
  }

  @override
  Future<AuthResponse> verifySignupCode({
    required String email,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
    return AuthResponse(user: verifiedUser);
  }
}

void main() {
  late FakeDeviceTrust trust;
  late FakeMfa mfa;
  late FakeOtp otp;
  late LoginChallengeService service;

  setUp(() {
    trust = FakeDeviceTrust();
    mfa = FakeMfa();
    otp = FakeOtp();
    service = LoginChallengeService(
      deviceTrust: trust,
      mfa: mfa,
      otp: otp,
    );
  });

  group('evaluate — the decision', () {
    test('a known device proceeds and refreshes last_seen_at', () async {
      trust.known = true;

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isFalse);
      expect(decision.skipReason, 'known_device');
      expect(trust.trustCalls, [
        {'deviceId': 'device-1111-2222-3333', 'label': trust.label},
      ]);
    });

    test('an unknown device without MFA raises the challenge', () async {
      trust.known = false;
      mfa.enabled = false;
      trust.gateOpen = false; // enforcement is ON for this case

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isTrue);
      expect(decision.deviceId, 'device-1111-2222-3333');
      expect(decision.deviceLabel, trust.label);
      // Nothing is trusted until the code clears.
      expect(trust.trustCalls, isEmpty);
    });

    // ── the gate probe (enforcement OFF) ──────────────────────────
    test('no code while the server gate is OPEN (enforcement off)', () async {
      trust.known = false;
      trust.secret = false; // nothing on this device backs the session
      mfa.enabled = false;
      trust.gateOpen = true; // …but nothing is denied without a secret either

      final decision = await service.evaluate(userId: 'user-1');

      // The step-up would buy nothing here, so it must not cost the user
      // their account when the code cannot be mailed.
      expect(decision.requiresChallenge, isFalse);
      expect(decision.skipReason, 'enforcement_off');
      // `trust_device()` refuses a password-only session, so no write is
      // attempted — the challenge mints the credential once the gate is on.
      expect(trust.trustCalls, isEmpty);
      expect(trust.gateProbes, 1);
    });

    test('an unreadable gate probe fails OPEN (never mails on a guess)',
        () async {
      trust.known = false;
      trust.secret = false;
      mfa.enabled = false;
      trust.gateError = Exception('offline');

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isFalse);
      expect(decision.skipReason, 'enforcement_off');
    });

    test('the gate is never probed when the device is already known',
        () async {
      trust.known = true;
      trust.secret = true;

      await service.evaluate(userId: 'user-1');

      expect(trust.gateProbes, 0);
    });

    test('the gate is never probed for an MFA account either', () async {
      trust.known = false;
      trust.secret = false;
      mfa.enabled = true;

      await service.evaluate(userId: 'user-1');

      expect(trust.gateProbes, 0);
    });

    test('an unknown device on an MFA account skips the email challenge',
        () async {
      trust.known = false;
      mfa.enabled = true;

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isFalse);
      expect(decision.skipReason, 'mfa_satisfies_step_up');
      // …and the device is recorded, so removing MFA later does not suddenly
      // start challenging this phone.
      expect(trust.trustCalls, hasLength(1));
    });

    test('the MFA check is skipped entirely for a known device', () async {
      trust.known = true;
      mfa.statusError = StateError('should not be called');

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isFalse);
    });

    // ── the secret IS the credential (server-side gate) ────────────
    test('a trusted_devices row alone is not enough — no secret, no trust',
        () async {
      trust.known = true; // the server still lists this device…
      trust.secret = false; // …but this install holds no credential
      trust.gateOpen = false; // enforcement is ON

      final decision = await service.evaluate(userId: 'user-1');

      // This is the state every existing install is in right after the
      // server-side gate ships, and the reason the row cannot be the test.
      expect(decision.requiresChallenge, isTrue);
      expect(trust.trustCalls, isEmpty);
    });

    test('holding a secret for a revoked device still challenges', () async {
      trust.known = false; // removed from the security screen
      trust.secret = true; // stale credential still in secure storage
      trust.gateOpen = false; // enforcement is ON

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isTrue);
    });
  });

  group('needsStepUpOnRestoredSession — the rollout repair path', () {
    test('holding a secret needs no step-up', () async {
      trust.gateOpen = false; // even when the gate would otherwise be shut
      expect(
        await service.needsStepUpOnRestoredSession(userId: 'user-1'),
        isFalse,
      );
    });

    test('no secret while enforcement is OFF adds no friction', () async {
      trust.secret = false;
      trust.gateOpen = true;
      expect(
        await service.needsStepUpOnRestoredSession(userId: 'user-1'),
        isFalse,
      );
    });

    test('no secret with the gate SHUT asks for a code', () async {
      trust.secret = false;
      trust.gateOpen = false;
      expect(
        await service.needsStepUpOnRestoredSession(userId: 'user-1'),
        isTrue,
      );
    });

    test('an unreadable probe fails OPEN (never mails on a guess)', () async {
      trust.secret = false;
      trust.gateError = Exception('offline');
      expect(
        await service.needsStepUpOnRestoredSession(userId: 'user-1'),
        isFalse,
      );
    });

    test('the probe is skipped entirely when a secret is held', () async {
      trust.secret = true;
      await service.needsStepUpOnRestoredSession(userId: 'user-1');
      expect(trust.gateProbes, 0);
    });
  });

  group('evaluate — failure handling', () {
    test('a missing device id fails OPEN (never challenges)', () async {
      trust.deviceId = null;

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isFalse);
      expect(decision.skipReason, 'device_id_unavailable');
      expect(trust.trustCalls, isEmpty);
    });

    test('an unreadable trusted_devices table does not force a challenge '
        'while we still hold the secret', () async {
      trust.lookupError = Exception('network down');

      final decision = await service.evaluate(userId: 'user-1');

      // A transient roster read is not evidence of a revoked device, and we
      // hold the credential the server gate actually checks.
      expect(decision.requiresChallenge, isFalse);
      expect(decision.skipReason, 'known_device');
    });

    test('a failed roster read WITH no local secret challenges — when the gate '
        'is shut', () async {
      trust.secret = false;
      trust.lookupError = Exception('network down');
      trust.gateOpen = false;

      final decision = await service.evaluate(userId: 'user-1');

      // Nothing proves this install is cleared, so the safe answer is the
      // challenge — proceeding would just hit a shut server gate.
      expect(decision.requiresChallenge, isTrue);
    });

    test('an unreadable MFA state fails TOWARD the challenge once the gate is '
        'actually shut', () async {
      // Unknown factor state is not evidence of a second factor, so the
      // extra challenge is applied (friction the user can clear) rather
      // than silently skipped (a hole that cannot be seen). The gate probe
      // still gets the final say: enforcement OFF means no code either way.
      trust.known = false;
      trust.gateOpen = false;
      mfa.statusError = Exception('factors unavailable');

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isTrue);
    });

    test('a failed trust write on a known device still proceeds', () async {
      trust.known = true;
      trust.trustError = Exception('rpc failed');

      final decision = await service.evaluate(userId: 'user-1');

      expect(decision.requiresChallenge, isFalse);
    });
  });

  group('the challenge round trip', () {
    test('sendChallengeCode delegates to the login OTP sender', () async {
      await service.sendChallengeCode('maria@gmail.com');
      expect(otp.sentLoginCodes, ['maria@gmail.com']);
    });

    test('a send failure PROPAGATES so login can refuse to complete',
        () async {
      otp.sendError = AuthException('rate limited', code: 'over_email_send_rate_limit');
      await expectLater(
        service.sendChallengeCode('maria@gmail.com'),
        throwsA(isA<AuthException>()),
      );
    });

    test('verifyChallengeCode returns the signed-in user', () async {
      final user = await service.verifyChallengeCode(
        email: 'maria@gmail.com',
        code: '123456',
      );
      expect(user.id, 'user-1');
    });

    test('verifyChallengeCode throws when no user came back', () async {
      otp.verifiedUser = null;
      await expectLater(
        service.verifyChallengeCode(email: 'maria@gmail.com', code: '123456'),
        throwsA(isA<AuthException>()),
      );
    });

    test('verifyChallengeCode propagates a bad code', () async {
      otp.verifyError = AuthException('expired', code: 'otp_expired');
      await expectLater(
        service.verifyChallengeCode(email: 'maria@gmail.com', code: '000000'),
        throwsA(isA<AuthException>()),
      );
    });

    test('markDeviceTrusted uses the current device id and label by default',
        () async {
      await service.markDeviceTrusted(userId: 'user-1');
      expect(trust.trustCalls, [
        {'deviceId': 'device-1111-2222-3333', 'label': trust.label},
      ]);
    });

    test('markDeviceTrusted returns the minted secret to persist', () async {
      // The secret is what satisfies the server gate, so the caller must get
      // it back — this is the value DeviceTrustService stores and sends.
      final secret = await service.markDeviceTrusted(userId: 'user-1');
      expect(secret, trust.mintedSecret);
    });

    test('markDeviceTrusted prefers an explicit device id', () async {
      await service.markDeviceTrusted(
        userId: 'user-1',
        deviceId: 'device-9999',
        deviceLabel: 'Pixel',
      );
      expect(trust.trustCalls, [
        {'deviceId': 'device-9999', 'label': 'Pixel'},
      ]);
    });

    test('markDeviceTrusted is a no-op when there is no device id', () async {
      trust.deviceId = null;
      await service.markDeviceTrusted(userId: 'user-1');
      expect(trust.trustCalls, isEmpty);
    });

    test('a refused mint (password-only session) returns null, never throws',
        () async {
      // The server refuses to trust a device on a password-only session
      // (42501). MFA users hit exactly this at login, before their TOTP
      // challenge clears — it must not surface as an error.
      trust.trustError = Exception('42501');
      expect(await service.markDeviceTrusted(userId: 'user-1'), isNull);
    });
  });

  group('device management', () {
    test('listDevices delegates', () async {
      trust.rows = const [
        TrustedDevice(deviceId: 'd1', deviceLabel: 'Phone'),
      ];
      final devices = await service.listDevices();
      expect(devices.single.deviceId, 'd1');
    });

    test('revokeDevice delegates', () async {
      await service.revokeDevice('d1');
      expect(trust.revoked, ['d1']);
    });

    test('revokeDevice propagates failure so the UI can say so', () async {
      trust.revokeError = Exception('denied');
      await expectLater(service.revokeDevice('d1'), throwsA(isA<Exception>()));
    });
  });
}
