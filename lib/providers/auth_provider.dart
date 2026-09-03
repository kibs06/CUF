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

  AuthProvider() {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = _db.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final profile = await _db.getProfile(user.id);
      _currentUser = {'id': user.id, 'email': user.email};
      _profile = profile;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
    }

    _isLoading = false;
    notifyListeners();
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

      // Auto login after sign up
      _currentUser = res['user'];
      _profile = res['profile'];
      onLoginHook?.call(_currentUser!['id'] as String);

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
      final user = await _auth.ensureUser(
        email: data.email,
        password: data.password,
        fullName: data.fullName,
      );
      final res = await _auth.completeSellerApplication(user: user, data: data);

      _currentUser = res['user'];
      _profile = res['profile'];
      onLoginHook?.call(_currentUser!['id'] as String);

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
