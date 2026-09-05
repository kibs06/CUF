import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of [MfaService.enroll]: everything the enrollment UI needs to
/// walk the user through "scan → confirm".
class MfaEnrollment {
  /// ID of the newly created (unverified) factor. Needed to verify the
  /// first code and to clean up if the user abandons enrollment.
  final String factorId;

  /// Raw SVG string of the QR code encoding the authenticator URI
  /// (render with flutter_svg's SvgPicture.string).
  final String qrCodeSvg;

  /// The TOTP secret, shown so users who can't scan can type it into
  /// their authenticator app manually.
  final String secret;

  const MfaEnrollment({
    required this.factorId,
    required this.qrCodeSvg,
    required this.secret,
  });
}

/// A single enrolled MFA factor (project only uses TOTP today).
class MfaFactorInfo {
  final String id;
  final String? friendlyName;
  final FactorStatus status;

  const MfaFactorInfo({
    required this.id,
    this.friendlyName,
    required this.status,
  });

  bool get verified => status == FactorStatus.verified;
}

/// Interface over the MFA operations the UI needs — lets widget tests
/// inject a fake instead of touching the real Supabase API.
abstract class MfaGateway {
  Future<bool> isMfaEnabled();
  Future<MfaEnrollment> enroll({String? friendlyName});
  Future<void> verifyEnrollment({
    required String factorId,
    required String code,
  });
  Future<void> cancelEnrollment(String factorId);
  Future<void> unenroll(String factorId);
  Future<MfaFactorInfo?> verifiedFactor();
  Future<void> verifyChallenge({
    required String factorId,
    required String code,
  });
}

/// Thin wrapper over Supabase Auth's TOTP MFA API
/// (`supabase.auth.mfa.*`, gotrue 2.26). MFA is per-user at the auth
/// server, so the same service covers customers, sellers, and admins.
///
/// Throwing methods rethrow the underlying [AuthException] — callers
/// map error codes (429 rate limit, etc.) to friendly messages via
/// `utils/auth_error_messages.dart` conventions in the UI layer.
class MfaService implements MfaGateway {
  MfaService._();
  static final MfaService instance = MfaService._();

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _client.auth;

  // ── Public status API ─────────────────────────────────────────

  /// True when the signed-in user has at least one VERIFIED TOTP factor.
  /// Unverified (abandoned) enrollments don't count.
  @override
  Future<bool> isMfaEnabled() async {
    final factors = await listFactors();
    return factors.any((f) => f.verified);
  }

  // ── Enrollment (Settings screen) ──────────────────────────────

  /// Starts TOTP enrollment: creates an unverified factor and returns
  /// the QR (SVG) + manual secret. The caller must follow up with
  /// [verifyEnrollment] to activate it, or [cancelEnrollment] to clean up.
  @override
  Future<MfaEnrollment> enroll({String? friendlyName}) async {
    final res = await _auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'SoleVision',
      friendlyName: friendlyName ?? 'Authenticator app',
    );
    final totp = res.totp;
    if (totp == null) {
      throw const AuthException('Server did not return TOTP enrollment data.');
    }
    return MfaEnrollment(
      factorId: res.id,
      qrCodeSvg: totp.qrCode,
      secret: totp.secret,
    );
  }

  /// Verifies the first 6-digit code to activate a pending enrollment.
  /// On success the factor becomes `verified` and MFA is active.
  @override
  Future<void> verifyEnrollment({
    required String factorId,
    required String code,
  }) async {
    await _auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  /// Deletes an unverified (abandoned) enrollment.
  @override
  Future<void> cancelEnrollment(String factorId) async {
    await _auth.mfa.unenroll(factorId);
  }

  /// Disables MFA by deleting a verified factor.
  @override
  Future<void> unenroll(String factorId) async {
    await _auth.mfa.unenroll(factorId);
  }

  // ── Login-time verification ───────────────────────────────────

  /// The verified TOTP factor to challenge at login, or null when the
  /// user has no MFA enrolled.
  @override
  Future<MfaFactorInfo?> verifiedFactor() async {
    final factors = await listFactors();
    for (final f in factors) {
      if (f.verified) return f;
    }
    return null;
  }

  /// Verifies a 6-digit code against a fresh challenge for [factorId].
  /// On success Supabase upgrades the session to AAL2 and the auth
  /// stream emits `mfaChallengeVerified`.
  @override
  Future<void> verifyChallenge({
    required String factorId,
    required String code,
  }) async {
    await _auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  // ── Internals ─────────────────────────────────────────────────

  Future<List<MfaFactorInfo>> listFactors() async {
    final res = await _auth.mfa.listFactors();
    return res.all
        .map(
          (f) => MfaFactorInfo(
            id: f.id,
            friendlyName: f.friendlyName,
            status: f.status,
          ),
        )
        .toList();
  }

  // ── Pure helpers (no I/O — unit-testable) ─────────────────────

  /// Decodes the payload of a Supabase access token (JWT). Returns null
  /// for malformed tokens — callers must treat null as AAL1 (fail closed
  /// toward the challenge check, never silently granting AAL2).
  static Map<String, dynamic>? jwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Parses Supabase's `aal` (Authenticator Assurance Level) claim.
  /// `aal1` = password verified, MFA not completed · `aal2` = MFA
  /// completed. Anything unrecognized (or missing) is treated as AAL1.
  static String aalFromJwtPayload(Map<String, dynamic>? payload) {
    final aal = payload?['aal'];
    return aal is String && aal.toLowerCase() == 'aal2' ? 'aal2' : 'aal1';
  }

  /// Whether a session with [aal] still needs an MFA verification step.
  static bool mfaRequiredForAal(String aal) => aal != 'aal2';
}
