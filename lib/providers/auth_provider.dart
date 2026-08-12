import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/seller_application_data.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/supabase_service.dart';
import '../utils/auth_error_messages.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService.instance;
  final SupabaseService _db = SupabaseService.instance;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _profile;
  bool _isLoading = false;
  String? _errorMessage;

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

  // Login (UC002)
  Future<bool> login(String email, String password) async {
    // Reset all state before the attempt so stale data from a
    // previous session never leaks into the new login flow.
    _currentUser = null;
    _profile = null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _auth.signIn(email: email, password: password);
      _currentUser = res['user'];
      _profile = res['profile'];
      onLoginHook?.call(_currentUser!['id'] as String);
      return true;
    } catch (e, st) {
      _errorMessage = friendlyAuthErrorMessage(e, stackTrace: st);
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

  // Logout (UC029)
  Future<void> logout() async {
    // Clear all state BEFORE calling signOut to prevent stale data
    // from being visible during the sign-out / redirect flow.
    _currentUser = null;
    _profile = null;
    _errorMessage = null;
    _isLoading = false;
    onLogoutHook?.call();
    notifyListeners();

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


}
