import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    // Retry up to 5 times — trigger may need a moment to fire
    for (int attempt = 1; attempt <= 5; attempt++) {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) return data;

      // Wait before retrying
      await Future.delayed(Duration(seconds: attempt));
    }

    // If still null after retries, create the profile manually
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // ✅ Email included
      await Supabase.instance.client.from('profiles').upsert({
        'id': userId,
        'full_name': user.userMetadata?['full_name'] ?? '',
        'email': user.email ?? '',
        'role': 'customer',
        'seller_status': 'none',
      });

      return await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
    }

    throw Exception('Could not create or find profile for user $userId');
  }

  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    // Force sign-out any existing session — critical when switching accounts.
    // Without this, a lingering session can block the new sign-in silently.
    final existing = _client.auth.currentSession;
    if (existing != null) {
      await _client.auth.signOut();
    }

    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) throw Exception('Login failed. Please try again.');

    final profile = await getProfile(user.id);

    return {
      'user': {'id': user.id, 'email': user.email ?? email.trim()},
      'profile': profile,
    };
  }

  Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String email,
    required String password,
    String sellerStatus = 'none',
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
    final user = response.user;
    if (user == null) throw Exception('Sign up failed. Please try again.');

    final profileData = {
      'id': user.id,
      'full_name': fullName.trim(),
      'email': email.trim(),
      'role': AppConstants.roleCustomer,
      'seller_status': sellerStatus,
      'avatar_url': null,
      'phone': null,
    };

    await _client.from('profiles').upsert(profileData);
    final profile = await getProfile(user.id);

    return {
      'user': {'id': user.id, 'email': user.email ?? email.trim()},
      'profile': profile,
    };
  }

  Future<List<Map<String, dynamic>>> fetchPendingSellerApplications() async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('seller_status', AppConstants.statusPending)
        .order('created_at', ascending: false);
    return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> approveSeller(String userId) async {
    await _client
        .from('profiles')
        .update({
          'role': AppConstants.roleSeller,
          'seller_status': AppConstants.statusApproved,
        })
        .eq('id', userId);
  }

  Future<void> rejectSeller(String userId) async {
    await _client
        .from('profiles')
        .update({'seller_status': AppConstants.statusRejected})
        .eq('id', userId);
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}