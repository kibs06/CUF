import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// One row of `public.trusted_devices` — a device that has already cleared
/// the new-device email OTP step-up for this account.
class TrustedDevice {
  final String deviceId;
  final String? deviceLabel;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final DateTime? trustedAt;

  const TrustedDevice({
    required this.deviceId,
    this.deviceLabel,
    this.firstSeenAt,
    this.lastSeenAt,
    this.trustedAt,
  });

  /// Human label for the device list; falls back to a short id so a row is
  /// never blank when the platform reported no model.
  String get displayLabel {
    final label = deviceLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return deviceId.length > 8 ? 'Device ${deviceId.substring(0, 8)}' : deviceId;
  }

  static DateTime? _time(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  factory TrustedDevice.fromRow(Map<String, dynamic> row) {
    return TrustedDevice(
      deviceId: row['device_id']?.toString() ?? '',
      deviceLabel: row['device_label']?.toString(),
      firstSeenAt: _time(row['first_seen_at']),
      lastSeenAt: _time(row['last_seen_at']),
      trustedAt: _time(row['trusted_at']),
    );
  }
}

/// The step-6 decision (does a password login from an untrusted device still
/// need the email challenge when TOTP MFA is enrolled?) expressed as a pure
/// function, so the rule is testable and lives in exactly one place.
///
/// **Decision: TOTP MFA satisfies the step-up, so the email challenge is
/// SKIPPED for MFA users.** An authenticator app is a stronger possession
/// factor than an emailed code — and banking two challenges on the same
/// login is friction with no added assurance.
///
/// NOTE (server side): the same rule is expressed in SQL by
/// `public.session_proves_possession()`, which accepts `amr` otp/magiclink
/// OR `aal2`. An MFA user therefore satisfies the server gate too, but only
/// once the session really is AAL2 — which is why `AuthProvider` mints the
/// device secret after the TOTP challenge clears (see
/// `ensureDeviceTrusted()`). Without that step an MFA user on a new device
/// would hold a `trusted_devices` row but no secret, and be locked out of
/// every gated table.
class DeviceTrustPolicy {
  DeviceTrustPolicy._();

  static bool requiresEmailOtpChallenge({
    required bool deviceKnown,
    required bool mfaEnabled,
  }) {
    if (deviceKnown) return false;
    if (mfaEnabled) return false;
    return true;
  }
}

/// Interface over device identity + the `trusted_devices` table — lets
/// provider/service tests inject a fake instead of touching secure storage,
/// platform channels and the network.
abstract class DeviceTrustGateway {
  /// This install's stable device id, or **null when it cannot be
  /// established** (secure-storage failure). Null must fail OPEN — the
  /// caller proceeds without a challenge rather than locking the user out.
  Future<String?> currentDeviceId();

  /// Best-effort human-readable device label ("Samsung SM-A155F · Android 14").
  Future<String?> currentDeviceLabel();

  /// Whether this install still holds the step-up secret for [userId].
  ///
  /// This is the credential the SERVER checks (see
  /// `public.device_is_trusted()`), so holding it is what makes a device
  /// "known" from the client's point of view — the `trusted_devices` row
  /// alone is not enough.
  Future<bool> hasDeviceSecret(String userId);

  /// `"<device_id>:<secret>"` for [userId], or null when either half is
  /// missing. This is exactly the value sent as the `x-cufmai-device` header.
  Future<String?> currentDeviceToken(String userId);

  Future<bool> isTrusted({required String userId, required String deviceId});

  /// True when the server would currently let this session use the
  /// device-gated tables. False means enforcement is on and this install has
  /// not cleared the step-up — the one case where the app must ask for a code
  /// on top of an already-restored session.
  Future<bool> isGateOpen();

  /// Records the device as trusted for the signed-in user and mints a fresh
  /// secret, which is persisted here and attached to later requests.
  /// Returns the minted secret (or null if the server sent none).
  ///
  /// Throws `PostgrestException` (42501) when the session has not proved
  /// possession — the server refuses to trust a device on a password-only
  /// session, which is what stops a hand-crafted client skipping the step-up.
  Future<String?> trust({required String deviceId, String? deviceLabel});

  Future<List<TrustedDevice>> listTrusted();

  /// Revokes one of the user's devices — its next login is challenged again,
  /// and its server-side secret is destroyed with it.
  Future<void> revoke(String deviceId);
}

/// Device identity for the current install.
///
/// The id is a random UUID v4 generated once and kept in
/// [FlutterSecureStorage] under [_deviceIdKey]. Two properties matter:
///
///  • It is **per install**, not per session or per account — logging out
///    must not change it (that is what keeps "log out / log back in on the
///    same phone" from looking like a new device), and two accounts on one
///    phone share it, which is why `trusted_devices` is keyed by
///    `(user_id, device_id)`.
///  • It is **not a secret**. The id only names the device; the separate
///    secret below is what actually satisfies the server's gate.
///
/// ## The step-up secret
///
/// `public.trust_device()` returns a 32-byte random secret, stored here under
/// a key scoped to the account ([_secretKeyPrefix] + user id) and sent as
/// `x-cufmai-device: <device_id>:<secret>` on every request. The server keeps
/// only its SHA-256 and compares it in `public.device_is_trusted()`.
///
/// It is scoped per ACCOUNT, not per install, because the server's row is
/// keyed by `(user_id, device_id)`: two accounts signing in on one phone each
/// have their own secret, and sending the wrong one simply closes the gate.
class DeviceTrustService implements DeviceTrustGateway {
  DeviceTrustService._();
  static final DeviceTrustService instance = DeviceTrustService._();

  /// A fresh instance with no cached state, sharing the same secure storage.
  ///
  /// The production [instance] is a process-wide singleton that caches the
  /// device id, the per-account secrets and the applied header in memory —
  /// that is what makes it cheap to consult on every auth-state change, and
  /// what makes it useless in a test that needs to simulate the NEXT app
  /// launch. A new instance re-reads storage, so it stands in for a restart:
  /// create one, and you are testing what the user gets after the process
  /// died. See test/services/device_trust_persistence_test.dart.
  @visibleForTesting
  factory DeviceTrustService.fresh() => DeviceTrustService._();

  /// Bumping this key's suffix retires every previously stored device id
  /// (i.e. re-challenges every device once).
  static const _deviceIdKey = 'cufmai_device_id_v1';

  /// Per-account: the suffix is the user id. See the class doc.
  static const _secretKeyPrefix = 'cufmai_device_secret_v1_';

  /// The request header PostgREST exposes to SQL as
  /// `request.headers->>'x-cufmai-device'` — the value
  /// `public.device_is_trusted()` reads.
  static const deviceHeaderName = 'x-cufmai-device';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _cachedDeviceId;

  /// The token currently attached to outgoing requests, so a no-op refresh
  /// (every token refresh fires the auth listener) costs nothing.
  String? _appliedToken;

  StreamSubscription<AuthState>? _authSub;

  // ── Device id ─────────────────────────────────────────────────────
  @override
  Future<String?> currentDeviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final existing = await _storage.read(key: _deviceIdKey);
      if (existing != null && existing.trim().length >= 8) {
        _cachedDeviceId = existing.trim();
        return _cachedDeviceId;
      }

      final generated = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: generated);
      _cachedDeviceId = generated;
      // A brand-new id RETIRES every secret we hold. The server keys its rows
      // by `(user_id, device_id)`, so a secret minted for the previous id can
      // never match again — and leaving it in storage would make
      // `hasDeviceSecret()` lie, which is the one signal that decides whether
      // the app skips the step-up. Dropping them is what makes "bump
      // [_deviceIdKey] to re-challenge every device" actually re-challenge
      // instead of silently denying every gated table.
      await _retireDeviceSecrets();
      return generated;
    } on PlatformException catch (e) {
      // Unexpected keychain/keystore failure — fail open, never block login.
      debugPrint('[DeviceTrust] Could not read/write device id: $e');
      return null;
    } catch (e) {
      debugPrint('[DeviceTrust] Could not establish device id: $e');
      return null;
    }
  }

  /// Reuses the same `device_info_plus` fields the lockout/intruder
  /// notification already sends, so the label the user sees in the device
  /// list matches the one an admin sees in the lockout row.
  @override
  Future<String?> currentDeviceLabel() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return '${android.manufacturer} ${android.model} · Android '
            '${android.version.release}';
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return '${ios.name} · iOS ${ios.systemVersion}';
      }
      return '${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}';
    } catch (e) {
      debugPrint('[DeviceTrust] Could not read device label: $e');
      return null;
    }
  }

  // ── The step-up secret ────────────────────────────────────────────
  String _secretKey(String userId) => '$_secretKeyPrefix$userId';

  /// Reads the stored secret for [userId]. Cached in memory for the life of
  /// the process — this is read on every auth-state change.
  final Map<String, String> _secretCache = {};

  Future<String?> deviceSecret(String userId) async {
    if (userId.isEmpty) return null;
    final cached = _secretCache[userId];
    if (cached != null) return cached;

    try {
      final stored = await _storage.read(key: _secretKey(userId));
      if (stored != null && stored.trim().length >= 32) {
        _secretCache[userId] = stored.trim();
        return _secretCache[userId];
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('[DeviceTrust] Could not read device secret: $e');
      return null;
    } catch (e) {
      debugPrint('[DeviceTrust] Could not read device secret: $e');
      return null;
    }
  }

  Future<void> storeDeviceSecret(String userId, String secret) async {
    if (userId.isEmpty || secret.length < 32) return;
    _secretCache[userId] = secret;
    try {
      await _storage.write(key: _secretKey(userId), value: secret);
    } catch (e) {
      // The in-memory value still satisfies this session; worst case the
      // user clears one more step-up after a restart.
      debugPrint('[DeviceTrust] Could not persist device secret: $e');
    }
  }

  /// Drops EVERY account's secret for this install, because the device id has
  /// changed and none of them can match a server row any more.
  ///
  /// Reads the whole store rather than walking [_secretCache], which is empty
  /// in a fresh process — the secrets being retired are exactly the ones this
  /// process has never looked at.
  Future<void> _retireDeviceSecrets() async {
    _secretCache.clear();
    _appliedToken = null;
    try {
      final all = await _storage.readAll();
      // Materialise the list BEFORE deleting. Some platform implementations
      // hand back a live view of the underlying store, and mutating a map
      // while iterating its keys skips entries — which would silently retire
      // one account's secret and leave the rest behind. (Found by
      // test/services/device_trust_persistence_test.dart, which retires two
      // accounts at once for exactly this reason: one account passes either
      // way, which is how the bug hid.)
      final stale = all.keys
          .where((key) => key.startsWith(_secretKeyPrefix))
          .toList();
      for (final key in stale) {
        await _storage.delete(key: key);
      }
    } catch (e) {
      // Best-effort, like every other storage write here: a secret we cannot
      // delete only costs one more step-up, whereas throwing here would break
      // device-id establishment entirely.
      debugPrint('[DeviceTrust] Could not retire stale device secrets: $e');
    }
  }

  /// Drops the credential for [userId] — used when the user revokes this very
  /// device, so the next login from it is challenged again.
  Future<void> clearDeviceSecret(String userId) async {
    _secretCache.remove(userId);
    try {
      await _storage.delete(key: _secretKey(userId));
    } catch (e) {
      debugPrint('[DeviceTrust] Could not clear device secret: $e');
    }
  }

  @override
  Future<bool> hasDeviceSecret(String userId) async =>
      (await deviceSecret(userId)) != null;

  /// The wire format of the credential: `"<device_id>:<secret>"`.
  ///
  /// Extracted so the contract with the server
  /// (`public.device_is_trusted()` splits on the first `:`) is testable
  /// without secure storage or a network. See
  /// test/services/device_gate_contract_test.dart.
  static String formatToken(String deviceId, String secret) =>
      '$deviceId:$secret';

  @override
  Future<String?> currentDeviceToken(String userId) async {
    final id = await currentDeviceId();
    final secret = await deviceSecret(userId);
    if (id == null || id.isEmpty || secret == null || secret.isEmpty) {
      return null;
    }
    return formatToken(id, secret);
  }

  // ── Header plumbing ───────────────────────────────────────────────
  /// Attaches (or removes) the device header on the shared Supabase client.
  ///
  /// `SupabaseClient.headers` is a settable map that the SDK re-propagates to
  /// the REST, functions, storage, auth and realtime clients, so this is the
  /// one seam that covers every request the app makes.
  void _applyToken(String? token) {
    if (token == _appliedToken) return;
    try {
      final client = Supabase.instance.client;
      final headers = Map<String, String>.from(client.headers);
      if (token == null || token.isEmpty) {
        headers.remove(deviceHeaderName);
      } else {
        headers[deviceHeaderName] = token;
      }
      client.headers = headers;
      _appliedToken = token;
    } catch (e) {
      // Called before Supabase.initialize in tests / early startup.
      debugPrint('[DeviceTrust] Could not set device header: $e');
    }
  }

  /// Points the device header at the currently signed-in account. Safe (and
  /// cheap) to call at any time.
  Future<void> refreshRequestHeader() async {
    final userId = _safeCurrentUserId();
    if (userId == null) {
      _applyToken(null);
      return;
    }
    _applyToken(await currentDeviceToken(userId));
  }

  /// Re-applies the header whenever the session changes — sign-in, account
  /// switch, sign-out, token refresh.
  ///
  /// This is deliberate belt-and-braces: the secret is per account, so a
  /// session change that bypassed the login flow (account switching) would
  /// otherwise leave the previous account's credential attached and silently
  /// close the gate for the new one.
  void startSyncWithAuthState() {
    if (_authSub != null) return;
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        unawaited(refreshRequestHeader());
      });
    } catch (e) {
      debugPrint('[DeviceTrust] Could not watch auth state: $e');
    }
  }

  String? _safeCurrentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  // ── trusted_devices table ─────────────────────────────────────────
  @override
  Future<bool> isTrusted({
    required String userId,
    required String deviceId,
  }) async {
    // RLS already limits this table to the caller's own rows; the explicit
    // user filter keeps the intent readable and makes the query index-backed.
    final row = await Supabase.instance.client
        .from('trusted_devices')
        .select('device_id')
        .eq('user_id', userId)
        .eq('device_id', deviceId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<bool> isGateOpen() async {
    final result = await Supabase.instance.client.rpc('device_gate_open');
    // Fail open on an unexpected shape: a probe that we cannot read must not
    // be the thing that forces a code on a legitimate user.
    if (result is bool) return result;
    return true;
  }

  @override
  Future<String?> trust({
    required String deviceId,
    String? deviceLabel,
  }) async {
    // The RPC takes the user from auth.uid() — there is deliberately no
    // INSERT/UPDATE policy on the table, so this is the only write path and
    // a client can never trust a device for another account. It refuses
    // (42501) unless the session already proved possession.
    final result = await Supabase.instance.client.rpc(
      'trust_device',
      params: {'p_device_id': deviceId, 'p_device_label': deviceLabel},
    );

    // A set-returning function comes back as a list of rows; be tolerant of
    // both shapes so a PostgREST behaviour change cannot silently drop the
    // secret on the floor.
    final rows = result is List ? result : [result];
    final userId = _safeCurrentUserId();
    for (final row in rows) {
      if (row is! Map) continue;
      final secret = row['device_secret']?.toString();
      if (secret != null && secret.length >= 32 && userId != null) {
        await storeDeviceSecret(userId, secret);
        _applyToken(await currentDeviceToken(userId));
        return secret;
      }
    }
    return null;
  }

  @override
  Future<List<TrustedDevice>> listTrusted() async {
    final rows = await Supabase.instance.client
        .from('trusted_devices')
        .select()
        .order('last_seen_at', ascending: false);
    return (rows as List)
        .map((row) => TrustedDevice.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<void> revoke(String deviceId) async {
    await Supabase.instance.client
        .from('trusted_devices')
        .delete()
        .eq('device_id', deviceId);

    // Revoking THIS install must also drop the local credential — otherwise
    // the phone would keep presenting a secret whose server row (and hash) is
    // gone, and be denied on every gated table instead of being re-challenged.
    final mine = await currentDeviceId();
    final userId = _safeCurrentUserId();
    if (mine != null && mine == deviceId && userId != null) {
      await clearDeviceSecret(userId);
      _applyToken(null);
    }
  }
}
