import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService.instance;
  final SupabaseService _db = SupabaseService.instance;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _profile;
  bool _isLoading = false;
  String? _errorMessage;

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
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
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
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Register (UC001)
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    required bool applyAsSeller,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _auth.signUp(
        fullName: fullName,
        email: email,
        password: password,
        sellerStatus: applyAsSeller ? AppConstants.statusPending : 'none',
      );

      // Auto login after sign up
      _currentUser = res['user'];
      _profile = res['profile'];
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
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
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String email) async {
    _errorMessage = null;
    try {
      await _db.resetPassword(email);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
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
