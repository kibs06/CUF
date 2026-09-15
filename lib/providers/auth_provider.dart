import 'dart:convert';
import 'dart:io' show HttpClient, Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../models/seller_application_data.dart';
import '../services/account_manager.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/device_trust_service.dart';
import '../services/email_otp_service.dart';
import '../services/login_challenge_service.dart';
import '../services/supabase_service.dart';
import '../utils/auth_error_messages.dart';
import '../utils/dev_mode.dart';
import '../widgets/lockout_overlay.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService.instance;
  final SupabaseService _db = SupabaseService.instance;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _profile;
  bool _isLoading = false;
  String? _errorMessage;

  /// Set when a lockout triggers. The UI watches this to show the
  /// [LockoutOverlay]. After showing, call [clearPendingLockout].
  Map<String, dynamic>? _pendingLockout;
  Map<String, dynamic>? get pendingLockout => _pendingLockout;

  /// Non-null while a sign-up is waiting for its emailed confirmation code
  /// (ANQUI item 16, Part A). Holds `{'email'}`. AuthGate renders the
  /// verify-code screen for as long as this is set; there is no session yet.
  Map<String, dynamic>? _pendingSignupVerification;
  Map<String, dynamic>? get pendingSignupVerification =>
      _pendingSignupVerification;

  /// Non-null while a password login is parked behind the new-device email
  /// OTP step-up (Part B). Holds `{'email', 'deviceId', 'deviceLabel'}`.
  /// The AAL1 session is withdrawn while this is set — see [login].
  Map<String, dynamic>? _pendingDeviceChallenge;
  Map<String, dynamic>? get pendingDeviceChallenge => _pendingDeviceChallenge;

  /// Owns the trusted-device decision + the step-up round trip. Injectable
  /// so tests can drive [login] with fake gateways.
  final LoginChallengeService _challenge;

  /// Email OTP round trips (both purposes). The screen talks to the same
  /// gateway directly; this provider only needs it for the state machine.
  final EmailOtpGateway _otp = EmailOtpService.instance;

  /// Hooks set by the app root after construction.
  void Function(String userId)? onLoginHook;
  VoidCallback? onLogoutHook;

  Map<String, dynamic>? get currentUser => _currentUser;
  Map<String, dynamic>? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _currentUser != null;
  String get userRole => _profile?['role'] ?? AppConstants.roleCustomer;
  String get sellerStatus =>
      _profile?['seller_status'] ?? AppConstants.statusApproved;
  String get displayName => _profile?['full_name'] ?? 'User';
  String get displayEmail => _profile?['email'] ?? '';
  String get displayPhone => _profile?['phone'] ?? '';
  String? get avatarUrl => _profile?['avatar_url'];

  AuthProvider({LoginChallengeService? challengeService})
    : _challenge = challengeService ?? LoginChallengeService() {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = _db.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    // Point the device header at this account BEFORE the first read. The
    // step-up secret is per (user, device) — see DeviceTrustService — so a
    // restored session must present its own credential before it touches any
    // device-gated table, or it would silently read nothing.
    try {
      await DeviceTrustService.instance.refreshRequestHeader();
    } catch (e) {
      debugPrint('[AuthProvider] could not apply device header: $e');
    }

    try {
      final profile = await _db.getProfile(user.id);
      _currentUser = {'id': user.id, 'email': user.email};
      _profile = profile;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
    }

    _isLoading = false;
    notifyListeners();

    await _maybeStartRestoredSessionChallenge(user);
  }

  /// Repairs a session that predates the server-side device gate.
  ///
  /// Such an install has a perfectly valid session but no device secret, so
  /// every device-gated table (orders, cart, messages, addresses…) reads as
  /// EMPTY — RLS filters denied rows rather than raising, so the failure is
  /// silent. This asks the server whether the gate is actually shut, and only
  /// then does something:
  ///
  ///   • enforcement off (the shipped default) → nothing happens, no code is
  ///     ever mailed, and shipping this feature adds zero friction;
  ///   • enforcement on → if the session already proves possession (TOTP MFA
  ///     cleared at AAL2) one RPC mints the secret silently; otherwise the
  ///     user is asked for the emailed code, exactly once per install.
  Future<void> _maybeStartRestoredSessionChallenge(User user) async {
    try {
      final needs = await _challenge.needsStepUpOnRestoredSession(
        userId: user.id,
      );
      if (!needs) return;

      // Already stepped up in THIS session (AAL2 from TOTP, or an email OTP)?
      // Minting is then enough — no second challenge for the same proof.
      await ensureDeviceTrusted();
      if (await DeviceTrustService.instance.isGateOpen()) return;

      final email = user.email;
      if (email == null || email.trim().isEmpty) return;

      final deviceId = await DeviceTrustService.instance.currentDeviceId();
      final deviceLabel =
          await DeviceTrustService.instance.currentDeviceLabel();

      // Sending the code IS the challenge: on failure, leave the restored
      // session exactly as it was rather than parking the user on a screen
      // with nothing to type.
      await _challenge.sendChallengeCode(email);
      _pendingDeviceChallenge = {
        'email': email.trim().toLowerCase(),
        'deviceId': deviceId,
        'deviceLabel': deviceLabel,
        'reason': 'restored_session',
      };
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] restored-session step-up skipped: $e');
    }
  }

  /// Mints this install's device secret for the signed-in account, once the
  /// session has proved possession.
  ///
  /// Called after the TOTP challenge clears, because that is the only way an
  /// MFA user on a new device obtains one: `login()` deliberately does not
  /// raise the email challenge for them (an authenticator is the stronger
  /// factor), and without a minted secret the server gate would still deny
  /// them — the gate checks the device SECRET, not the AAL.
  ///
  /// Best-effort and idempotent: the RPC refuses a password-only session, and
  /// a device that already holds a secret is skipped.
  Future<void> ensureDeviceTrusted() async {
    final userId = _currentUser?['id'] as String?;
    if (userId == null || userId.isEmpty) return;
    try {
      if (await DeviceTrustService.instance.hasDeviceSecret(userId)) return;
      await _challenge.markDeviceTrusted(userId: userId);
    } catch (e) {
      debugPrint('[AuthProvider] could not trust this device: $e');
    }
  }

  // Clear errors
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Called by the UI after showing the lockout overlay.
  void clearPendingLockout() {
    _pendingLockout = null;
  }

  // ── Local lockout tracking (SharedPreferences) ──────────────
  // Works immediately without database migrations or RLS policies.
  // Keyed by email so different accounts lock independently.
  static const _maxFailedAttempts = 5;
  static const _lockoutMinutes = 30;
  static const _lockoutPrefix = 'lockout_';
  static const _failCountPrefix = 'fail_count_';

  /// Returns the SharedPreferences key for a given email.
  String _lockoutKey(String email) => '$_lockoutPrefix${email.trim().toLowerCase()}';
  String _failCountKey(String email) => '$_failCountPrefix${email.trim().toLowerCase()}';

  /// Check if [email] is currently locked out locally.
  Future<int> _getLocalFailCount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failCountKey(email)) ?? 0;
  }

  Future<DateTime?> _getLocalLockoutExpiry(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_lockoutKey(email));
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
  }

  Future<void> _recordLocalFailure(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = email.trim().toLowerCase();
    final count = (prefs.getInt(_failCountKey(key)) ?? 0) + 1;
    await prefs.setInt(_failCountKey(key), count);
    if (count >= _maxFailedAttempts) {
      final expiry = DateTime.now().toUtc().add(Duration(minutes: _lockoutMinutes));
      await prefs.setInt(_lockoutKey(key), expiry.millisecondsSinceEpoch);
    }
  }

  Future<void> _clearLocalLockout(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = email.trim().toLowerCase();
    await prefs.remove(_failCountKey(key));
    await prefs.remove(_lockoutKey(key));
  }

  // ── Device info collection ────────────────────────────────────
  /// Collects device model, OS version, and public IP address.
  /// Returns a map with 'userAgent' and 'ipAddress' keys.
  Future<Map<String, String>> _collectDeviceInfo() async {
    String deviceModel = 'Unknown';
    String osInfo = '';

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        deviceModel = '${android.manufacturer} ${android.model}';
        osInfo = 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        deviceModel = ios.name;
        osInfo = 'iOS ${ios.systemVersion}';
      } else {
        deviceModel = Platform.operatingSystem;
        osInfo = Platform.operatingSystemVersion;
      }
    } catch (_) {
      deviceModel = Platform.operatingSystem;
    }

    final userAgent = '$deviceModel ($osInfo)'.trim();

    // Fetch public IP (best-effort, timeout 3s)
    String ipAddress = '';
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('https://api.ipify.org?format=json'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      ipAddress = json['ip'] as String? ?? '';
      client.close(force: true);
    } catch (_) {
      // IP lookup is best-effort
    }

    return {'userAgent': userAgent, 'ipAddress': ipAddress};
  }

  // Login (UC002)
  Future<bool> login(String email, String password) async {
    // Reset all state before the attempt so stale data from a
    // previous session never leaks into the new login flow.
    _currentUser = null;
    _profile = null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // ── Pre-login lockout check (local) ────────────────────────
    // Skip lockout check entirely in dev mode.
    final trimmedEmail = email.trim().toLowerCase();
    if (!DevMode.instance.isEnabled) {
      final lockoutExpiry = await _getLocalLockoutExpiry(trimmedEmail);
      if (lockoutExpiry != null && DateTime.now().toUtc().isBefore(lockoutExpiry)) {
        final remaining = lockoutExpiry.difference(DateTime.now().toUtc());
        final mins = remaining.inMinutes < 1 ? 1 : remaining.inMinutes;
        _isLoading = false;
        _errorMessage = 'Account locked due to too many failed attempts. Try again in $mins minute${mins == 1 ? '' : 's'}.';
        // Show the lockout overlay with device details
        final deviceInfo = await _collectDeviceInfo();
        _pendingLockout = {
          'email': trimmedEmail,
          'remainingMinutes': mins,
          'device': deviceInfo['userAgent'] ?? '',
          'ipAddress': deviceInfo['ipAddress'] ?? '',
        };
        notifyListeners();
        return false;
      }
      // Lockout expired — clear it
      if (lockoutExpiry != null) {
        await _clearLocalLockout(trimmedEmail);
      }
    } else {
      // Dev mode: clear any existing lockout so login always works
      await _clearLocalLockout(trimmedEmail);
    }

    try {
      final res = await _auth.signIn(email: email, password: password);

      // ── New-device step-up (ANQUI item 16, Part B) ─────────────
      // The password is correct, so the failure counters are cleared below —
      // but a device we have never seen does not get to keep the token.
      // Checking HERE, before any of the login bookkeeping, is what makes
      // this a step-up rather than a warning after the fact.
      final userId = res['user']['id'] as String;
      final decision = await _challenge.evaluate(userId: userId);
      if (decision.requiresChallenge) {
        await _clearLocalLockout(trimmedEmail);
        try {
          await _auth.resetFailedCounter(userId);
        } catch (_) {
          // Best-effort, exactly as on the happy path.
        }
        _currentUser = null;
        _profile = null;

        // Sending the code IS the challenge, so failing to send it must not
        // complete the login. Surface the mapped error (rate limit, mailer
        // outage) and let the user retry.
        try {
          await _challenge.sendChallengeCode(trimmedEmail);
        } catch (e, st) {
          _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
          _pendingDeviceChallenge = null;
          notifyListeners();
          return false;
        } finally {
          // Withdraw the AAL1 session either way: an unverified device must
          // not hold a usable token while the code is outstanding.
          try {
            await _auth.signOut();
          } catch (_) {
            // A failed local sign-out still leaves the OTP gate in place.
          }
        }

        _pendingDeviceChallenge = {
          'email': trimmedEmail,
          'deviceId': decision.deviceId,
          'deviceLabel': decision.deviceLabel,
        };
        _errorMessage = null;
        notifyListeners();
        return false;
      }

      _currentUser = res['user'];
      _profile = res['profile'];
      onLoginHook?.call(_currentUser!['id'] as String);

      // Save session for multi-account switching
      try {
        await AccountManager.instance.saveCurrentSession(profile: _profile);
      } catch (_) {
        // Best-effort — don't block login if account saving fails
      }

      // ✅ Success — clear all failure tracking (local + remote)
      await _clearLocalLockout(trimmedEmail);
      if (_currentUser != null && _profile != null) {
        try {
          await _auth.resetFailedCounter(_currentUser!['id'] as String);
        } catch (_) {
          // Best-effort — local lockout already cleared
        }
      }

      return true;
    } catch (e, st) {
      // ── Never-confirmed account (ANQUI item 16 pre-rollout path) ──
      // Accounts created before "Confirm email" was switched on can have a
      // NULL email_confirmed_at. Supabase refuses them with
      // `email_not_confirmed`, which used to surface as "Confirm your email
      // first — check your inbox for the link we sent": a DEAD END for
      // someone who never received one. Send a fresh code instead and route
      // them to the same verify screen signup uses, so no existing user can
      // be locked out by the rollout. This is not a failed login attempt.
      if (e is AuthException && e.code == 'email_not_confirmed') {
        final started = await _startSignupVerification(trimmedEmail);
        if (!started) {
          _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
        }
        notifyListeners();
        return false;
      }

      // ❌ Failed login — record the failure locally (skip in dev mode)
      if (!DevMode.instance.isEnabled) {
        await _recordLocalFailure(trimmedEmail);
      }

      final failCount = await _getLocalFailCount(trimmedEmail);
      if (!DevMode.instance.isEnabled && failCount >= _maxFailedAttempts) {
        final expiry = await _getLocalLockoutExpiry(trimmedEmail);
        final mins = expiry != null
            ? (expiry.difference(DateTime.now().toUtc()).inMinutes).clamp(1, _lockoutMinutes)
            : _lockoutMinutes;
        _errorMessage = 'Account locked due to too many failed attempts. Try again in $mins minute${mins == 1 ? '' : 's'}.';
        // Collect device info so the admin can see the attacker's device
        // and the overlay can show it to the user.
        final deviceInfo = await _collectDeviceInfo();
        _pendingLockout = {
          'email': trimmedEmail,
          'remainingMinutes': mins,
          'device': deviceInfo['userAgent'] ?? '',
          'ipAddress': deviceInfo['ipAddress'] ?? '',
        };
        // ── Fire-and-forget: email + push notification + server tracking ──
        try {
          final profileData = await _db.getProfileByEmail(trimmedEmail);
          final userId = profileData?['id'] as String?;

          // 1) Email notification (includes device details)
          try {
            await Supabase.instance.client.functions.invoke(
              'send-lockout-email',
              body: {
                'email': trimmedEmail,
                'device': deviceInfo['userAgent'],
                'ip': deviceInfo['ipAddress'],
              },
            );
          } catch (_) {
            // Best-effort
          }

          // 2) Push notification to user
          if (userId != null) {
            try {
              await Supabase.instance.client.functions.invoke(
                'send-notification-push',
                body: {
                  'recipientUserId': userId,
                  'title': '🔒 Account Locked',
                  'body': 'Too many failed login attempts. Your account is locked for 30 minutes.',
                  'type': 'lockout',
                },
              );
            } catch (_) {
              // Best-effort
            }
          }

          // 3) Server-side tracking (with device info)
          if (userId != null) {
            try {
              await _auth.advanceFailedCounter(
                userId: userId,
                ipAddress: deviceInfo['ipAddress'] ?? '',
                userAgent: deviceInfo['userAgent'] ?? '',
              );
            } catch (_) {
              // Best-effort
            }
          }
        } catch (_) {
          // Profile lookup failed — all notifications are best-effort
        }
      } else {
        _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      }
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Register — customer (UC001, split from the legacy unified form)
  Future<bool> signUpCustomer({
    required String fullName,
    required String email,
    required String password,
    String? phone,
    DateTime? birthday,
    String? gender,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _auth.signUp(
        fullName: fullName,
        email: email,
        password: password,
        sellerStatus: 'none',
        phone: phone,
        birthday: birthday,
        gender: gender,
      );

      if (res['emailVerificationRequired'] == true) {
        // "Confirm email" is ON: signUp returned no session and the profiles
        // row is deferred until verifyOTP lands one. AuthGate swaps to the
        // verify-code screen; nothing else may navigate here.
        _pendingSignupVerification = {'email': email.trim().toLowerCase()};
        _currentUser = null;
        _profile = null;
        notifyListeners();
        return false;
      }

      // Auto login after sign up
      _currentUser = res['user'];
      _profile = res['profile'];
      onLoginHook?.call(_currentUser!['id'] as String);

      // The account was just created on THIS device — treat it as known so
      // the next sign-in from here is not challenged as a "new device".
      await _recordCurrentDeviceTrusted(_currentUser!['id'] as String);

      // Save session for multi-account switching
      try {
        await AccountManager.instance.saveCurrentSession(profile: _profile);
      } catch (_) {
        // Best-effort
      }

      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Register — seller (final step of the multi-step application flow).
  ///
  /// The documents are uploaded by the flow's `SellerApplicationController`
  /// BEFORE this is called; here we create the auth account (only at this
  /// point — abandoning earlier steps never orphans an account), persist
  /// the full Tier 1 application, and adopt the session so AuthGate routes
  /// the user to the PendingApprovalScreen.
  Future<bool> signUpSeller({
    required SellerApplicationData data,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ensured = await _auth.ensureUser(
        email: data.email,
        password: data.password,
        fullName: data.fullName,
      );
      if (ensured.emailVerificationRequired) {
        // Refuse rather than half-complete: writing the application now
        // would be a permission error (no session), and writing the profile
        // from signup metadata would create a plain CUSTOMER row instead of
        // a pending seller application. The caller is expected to verify
        // first — `SellerApplicationController.submit` does that for the
        // real flow, and the dev-mode submit for the dev one.
        throw const AuthException(
          'Please confirm your email address before submitting your '
          'application.',
        );
      }
      final res = await _auth.completeSellerApplication(
        user: ensured.user,
        data: data,
      );

      _currentUser = res['user'];
      _profile = res['profile'];
      onLoginHook?.call(_currentUser!['id'] as String);

      // Re-verified on this device a moment ago (signup verification or an
      // existing session), so don't treat it as new on the next sign-in.
      await _recordCurrentDeviceTrusted(_currentUser!['id'] as String);

      // Save session for multi-account switching
      try {
        await AccountManager.instance.saveCurrentSession(profile: _profile);
      } catch (_) {
        // Best-effort
      }

      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Email OTP: sign-up confirmation (ANQUI item 16, Part A) ──────

  /// Verifies the e-mailed signup code. This is the step that finally
  /// creates the `profiles` row (the table has no `on auth.users` trigger —
  /// its INSERT policy needs `auth.uid() = id`, so a session must exist
  /// first). On success the session is adopted and AuthGate routes onward.
  ///
  /// Throws on a wrong/expired code so the screen can show the mapped
  /// message; the pending state survives so the user can retry.
  Future<bool> verifySignupEmail(String code) async {
    final pending = _pendingSignupVerification;
    if (pending == null) return false;
    final email = (pending['email'] as String).trim();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _otp.verifySignupCode(email: email, token: code);
      final user = response.user ?? Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw const AuthException('That code did not start a session.');
      }

      final profile = await _auth.writeProfileFromMetadata(user);

      _pendingSignupVerification = null;
      _currentUser = {'id': user.id, 'email': user.email};
      _profile = profile;
      onLoginHook?.call(user.id);

      // The account now exists on this device — don't challenge it here next
      // time (this is the false-positive "new device" case to avoid). The
      // signup code we just verified makes this a stepped-up session, so the
      // server issues the device secret here.
      await _recordCurrentDeviceTrusted(user.id);

      try {
        await AccountManager.instance.saveCurrentSession(profile: _profile);
      } catch (_) {
        // Best-effort, as everywhere else.
      }

      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      // Rethrown so the OTP screen can render the mapped, code-specific
      // copy ("that code didn't match or has expired").
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resends the signup confirmation code. Rethrows so the button can show
  /// the rate-limit message instead of failing silently.
  Future<void> resendSignupEmail() async {
    final pending = _pendingSignupVerification;
    if (pending == null) return;
    await _otp.sendSignupCode((pending['email'] as String).trim());
  }

  /// Parks the app on the verify-e-mail screen for [email] and mails a fresh
  /// code. Returns false (leaving no pending state) when the code could not
  /// be sent, so the caller can surface the real error instead of a screen
  /// with nothing to enter.
  Future<bool> _startSignupVerification(String email) async {
    _pendingSignupVerification = {'email': email.trim().toLowerCase()};
    try {
      await _otp.sendSignupCode(email.trim());
      return true;
    } catch (e) {
      debugPrint('[AuthProvider] could not send signup code: $e');
      _pendingSignupVerification = null;
      return false;
    }
  }

  /// Verifies a signup code for a flow that does NOT consume the pending
  /// signup state — the seller application, which creates its account at
  /// final submit. Establishes the session and NOTHING else: the flow still
  /// writes its own profile through `completeSellerApplication`, so
  /// confirming the address can never grant seller access ahead of admin
  /// approval.
  Future<void> verifySignupCodeForSeller({
    required String email,
    required String code,
  }) async {
    final response = await _otp.verifySignupCode(email: email, token: code);
    if (response.user == null &&
        Supabase.instance.client.auth.currentUser == null) {
      throw const AuthException('That code did not start a session.');
    }
  }

  /// Abandons signup verification ("use a different account"). The auth user
  /// keeps existing in an unconfirmed state; signing up again with the same
  /// address simply re-sends the code.
  void cancelSignupVerification() {
    _pendingSignupVerification = null;
    _errorMessage = null;
    notifyListeners();
  }

  // ── Email OTP: new-device step-up (ANQUI item 16, Part B) ────────

  /// Completes the new-device challenge: verifies the code, records the
  /// device as trusted for this account, and adopts the session the
  /// verification establishes. Throws on a bad code (screen maps it).
  Future<bool> verifyDeviceChallenge(String code) async {
    final pending = _pendingDeviceChallenge;
    if (pending == null) return false;
    final email = (pending['email'] as String).trim();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _challenge.verifyChallengeCode(
        email: email,
        code: code,
      );

      // The step-up is cleared — remember this device so the next sign-in
      // from it is not challenged again (this must survive logout, which it
      // does: the row lives server-side, the id lives in secure storage).
      // This is also where the device SECRET is minted and attached to the
      // request header, which is what the server-side gate actually checks.
      await _challenge.markDeviceTrusted(
        userId: user.id,
        deviceId: pending['deviceId'] as String?,
        deviceLabel: pending['deviceLabel'] as String?,
      );

      _pendingDeviceChallenge = null;
      _currentUser = {'id': user.id, 'email': user.email};
      _profile = await _db.getProfile(user.id);
      onLoginHook?.call(user.id);

      try {
        await AccountManager.instance.saveCurrentSession(profile: _profile);
      } catch (_) {
        // Best-effort, as everywhere else.
      }

      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resends the new-device code. Rethrows so the button can surface a
  /// rate-limit or mailer error rather than appearing to do nothing.
  Future<void> resendDeviceChallenge() async {
    final pending = _pendingDeviceChallenge;
    if (pending == null) return;
    await _challenge.sendChallengeCode((pending['email'] as String).trim());
  }

  /// Abandons the challenge and returns to the sign-in screen. The password
  /// was already correct, so nothing is counted as a failed attempt.
  void cancelDeviceChallenge() {
    _pendingDeviceChallenge = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Best-effort: marks this install's device as trusted for [userId], and
  /// stores the secret the server mints. Called after a signup completes so a
  /// brand-new account does not immediately look like a stranger on the phone
  /// that created it.
  Future<void> _recordCurrentDeviceTrusted(String userId) async {
    try {
      await _challenge.markDeviceTrusted(userId: userId);
    } catch (_) {
      // Purely an optimisation — worst case the user clears one step-up.
    }
  }

  /// Persists the customer's foot-profile snapshot onto the profiles row.
  ///
  /// [source] is 'ar_scan' | 'manual' | 'skipped' (AppConstants
  /// footProfile*). [sizeEu] is the effective EU size as a number; for scans
  /// it mirrors the latest foot_measurements recommendation (full scan
  /// fidelity stays in foot_measurements — this is just the cheap snapshot
  /// other screens read). [widthLabel] is only set by the manual picker
  /// ('Narrow'/'Regular'/'Wide').
  ///
  /// Updates the local [_profile] so consumers watching this provider
  /// (e.g. the home reminder banner) hide immediately. Deliberately does
  /// NOT flip [_isLoading] — this is a background snapshot write (called
  /// from the onboarding screen and post-scan), so it must never flash
  /// global loading spinners on unrelated screens.
  Future<bool> saveFootProfile({
    double? sizeEu,
    String? widthLabel,
    required String source,
  }) async {
    final profileId = _profile?['id']?.toString();
    if (profileId == null) return false;

    try {
      final updated = await _db.updateProfileFootSnapshot(
        profileId,
        sizeEu: sizeEu,
        widthLabel: widthLabel,
        source: source,
      );
      _profile = updated;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      notifyListeners();
      return false;
    }
  }

  // Save profile edits (UC003)
  Future<bool> updateProfile({
    required String fullName,
    String? phone,
    String? newAvatarUrl,
    String? bio,
    String? gender,
    String? birthday,
  }) async {
    if (_profile == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await _db.updateProfile(
        _profile!['id'],
        fullName,
        phone: phone,
        avatarUrl: newAvatarUrl,
        bio: bio,
        gender: gender,
        birthday: birthday,
      );
      _profile = updated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      _isLoading = false;
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String email) async {
    _errorMessage = null;
    try {
      await _db.resetPassword(email);
      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      notifyListeners();
      return false;
    }
  }

  /// Report a lockout event as unauthorized ("This wasn't me").
  /// Sends the email + device info to the server for admin review.
  Future<bool> reportIntrusion(String email) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-lockout-email',
        body: {
          'email': email,
          'report': true,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Update the user's email address. Supabase sends a confirmation email
  /// to the new address — the email won't change until confirmed.
  Future<bool> updateEmail(String newEmail) async {
    _errorMessage = null;
    try {
      await _auth.updateEmail(newEmail);
      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
      notifyListeners();
      return false;
    }
  }

  // Logout (UC029)
  Future<void> logout() async {
    // Capture userId before clearing state
    final userId = _currentUser?['id'] as String?;

    // Clear all state BEFORE calling signOut to prevent stale data
    // from being visible during the sign-out / redirect flow.
    _currentUser = null;
    _profile = null;
    _errorMessage = null;
    _isLoading = false;
    onLogoutHook?.call();
    notifyListeners();

    // Remove this account from the multi-account store
    try {
      if (userId != null) {
        await AccountManager.instance.removeAccount(userId);
      }
    } catch (_) {
      // Best-effort
    }

    try {
      await _auth.signOut();
    } catch (_) {
      // Sign-out should never block logout — swallow errors.
    }

    // Clear biometric credentials so a different account can log in.
    try {
      await BiometricService.instance.clearCredentials();
    } catch (_) {
      // Best-effort — don't let biometric cleanup block logout.
    }
  }

  /// Refreshes the in-memory state after an account switch.
  /// Called by AccountSwitcherScreen after switching to a different stored
  /// account — re-fetches the profile for the now-active user.
  Future<void> refreshAfterSwitch() async {
    final user = _db.currentUser;
    if (user == null) {
      _currentUser = null;
      _profile = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final profile = await _db.getProfile(user.id);
      _currentUser = {'id': user.id, 'email': user.email};
      _profile = profile;
      onLoginHook?.call(user.id);
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
    }

    _isLoading = false;
    notifyListeners();
  }


}
