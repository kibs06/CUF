import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../models/seller_application_data.dart';
import '../utils/customer_profile_fields.dart' as customer_profile_fields;

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    // Retry up to 5 times — the auth trigger may need a moment to fire
    // the profile row after signup. The sleeps are a SHORT backoff, not a
    // long hang: the previous 1+2+3+4+5s pattern (15s total) exceeded
    // AuthGate's 12s profile timeout, so a missing row always surfaced as
    // a TimeoutException and the fallback below never ran.
    for (int attempt = 1; attempt <= 5; attempt++) {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) return data;

      // Wait before retrying
      await Future.delayed(Duration(milliseconds: 300 * attempt));
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

  /// Lightweight duplicate-email check surfaced at Step 1 of the flows,
  /// BEFORE the user invests time uploading documents. Queries the public
  /// profiles table (world-readable SELECT); the authoritative check still
  /// happens at auth.signUp on final submit.
  Future<bool> emailExists(String email) async {
    final data = await _client
        .from('profiles')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    return data != null;
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
    String? phone,
    DateTime? birthday,
    String? gender,
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
      'phone': phone,
      // Birthday/gender are collected at signup (see customer_register_screen).
      // formatBirthdayForDb keeps the DATE column from shifting across
      // midnight via UTC serialization.
      'birthday': customer_profile_fields.formatBirthdayForDb(birthday),
      'gender': gender,
    };

    await _client.from('profiles').upsert(profileData);
    final profile = await getProfile(user.id);

    return {
      'user': {'id': user.id, 'email': user.email ?? email.trim()},
      'profile': profile,
    };
  }

  /// Ensures an authenticated Supabase user exists for [email].
  ///
  /// Used by the seller application flow, which deliberately creates the
  /// auth user only at the FINAL submit step (so abandoning the flow never
  /// leaves an orphaned account). Handles three cases:
  ///
  /// 1. Already signed in with this email (re-apply) → returns the current
  ///    user, no network call.
  /// 2. Signed in with a DIFFERENT account → signs out first (mirrors
  ///    [signIn]) so the new signup runs in a clean session.
  /// 3. Not signed in → auth.signUp. If Supabase reports the account
  ///    already exists but returns no session (e.g. an abandoned legacy
  ///    application), signs in with the supplied password instead so the
  ///    retryable submit can complete the profile.
  Future<User> ensureUser({
    required String email,
    String? password,
    String? fullName,
  }) async {
    final trimmedEmail = email.trim();
    final current = _client.auth.currentUser;
    if (current != null) {
      if ((current.email ?? '').toLowerCase() == trimmedEmail.toLowerCase()) {
        return current;
      }
      await _client.auth.signOut();
    }

    // No session (re-apply case): creating an account requires a password.
    if (password == null || fullName == null) {
      throw Exception('Please sign in again to re-apply as a seller.');
    }

    final response = await _client.auth.signUp(
      email: trimmedEmail,
      password: password,
      data: {'full_name': fullName.trim()},
    );
    var user = response.user;
    if (user == null) throw Exception('Sign up failed. Please try again.');

    if (response.session == null) {
      // Account exists but no session — likely an abandoned legacy
      // application. Complete it by signing in with the submitted password.
      final signIn = await _client.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
      user = signIn.user ?? user;
    }
    return user;
  }

  /// Writes the full Tier 1 seller application onto the user's profile and
  /// marks it `pending` for admin review. The `role` stays `customer` —
  /// the flip to `seller` happens ONLY on admin approval (unchanged from
  /// the legacy flow).
  Future<Map<String, dynamic>> completeSellerApplication({
    required User user,
    required SellerApplicationData data,
  }) async {
    final profileData = <String, dynamic>{
      'id': user.id,
      'full_name': data.fullName.trim(),
      'email': data.email.trim(),
      'role': AppConstants.roleCustomer,
      'seller_status': AppConstants.statusPending,
      'phone': data.phone.trim().isEmpty ? null : data.phone.trim(),
      'id_type': data.idType,
      'id_document_url': data.idDocumentPath,
      'selfie_url': data.selfiePath,
      'cufmai_member_id':
          data.cufmaiMemberId != null && data.cufmaiMemberId!.trim().isNotEmpty
              ? data.cufmaiMemberId!.trim()
              : null,
      'barangay_proof_url': data.barangayProofPath,
      'store_front_url': data.storeFrontPath,
      'product_photo_urls': data.productPhotoPaths.isEmpty
          ? null
          : data.productPhotoPaths,
      'store_name': data.storeName.trim(),
      'store_description': data.storeDescription.trim(),
      // Application v2 (Step 3 personal details + location, Step 5 tags)
      'birthday': customer_profile_fields.formatBirthdayForDb(data.birthday),
      'gender': data.gender,
      'store_location': data.storeLocation,
      'store_lat': data.storeLat,
      'store_lng': data.storeLng,
      'store_tags': data.storeTags.isEmpty ? null : data.storeTags,
      // Re-applying clears any previous rejection reason — the old verdict
      // no longer applies to the new application.
      'rejection_reason': null,
    };

    await _client.from('profiles').upsert(profileData);

    // Step 4 business docs — DTI cert, BIR COR, mayor's/barangay permit
    // are REQUIRED in the application v2 flow, so write them to
    // seller_business_docs (one row per profile, owner-insert RLS lets the
    // applicant create it) and flag the submission as pending review.
    // Idempotent on retry: upsert on profile_id keeps a single row.
    if (data.dtiCertPath != null ||
        data.birCorPath != null ||
        data.permitPath != null) {
      await _client.from('seller_business_docs').upsert(
        {
          'profile_id': user.id,
          'dti_cert_url': data.dtiCertPath,
          'bir_cor_url': data.birCorPath,
          'permit_url': data.permitPath,
          'verification_status': AppConstants.bizStatusPending,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
          'verified_at': null,
        },
        onConflict: 'profile_id',
      );
    }

    final profile = await getProfile(user.id) ?? profileData;

    return {
      'user': {'id': user.id, 'email': user.email ?? data.email.trim()},
      'profile': profile,
    };
  }

  Future<List<Map<String, dynamic>>> fetchPendingSellerApplications() async {
    final data = await _client
        .from('profiles')
        // Include the applicant's required business-docs row (DTI/BIR/
        // permit) via the FK so the review screen can verify all of them.
        .select(
          '*, seller_business_docs(id, dti_cert_url, bir_cor_url, permit_url, verification_status)',
        )
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

  // ── Tier 2 — optional business verification (decoupled from approval) ──

  /// Fetches the current user's Tier 2 business-docs row (or null).
  Future<Map<String, dynamic>?> fetchBusinessVerification(
    String profileId,
  ) async {
    final data = await _client
        .from('seller_business_docs')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Submits (or re-submits) Tier 2 business documents for verification.
  ///
  /// Upserts the single row per profile, keeps any previously uploaded
  /// document paths the seller did not replace, and flips the status back
  /// to `pending`. Purely additive to the approval state machine — a
  /// seller with `none`/`pending` here can still sell normally.
  Future<Map<String, dynamic>> submitBusinessVerification({
    required String profileId,
    String? dtiCertPath,
    String? birCorPath,
    String? permitPath,
  }) async {
    final existing =
        await fetchBusinessVerification(profileId) ?? <String, dynamic>{};

    final row = {
      'profile_id': profileId,
      'dti_cert_url': dtiCertPath ?? existing['dti_cert_url'],
      'bir_cor_url': birCorPath ?? existing['bir_cor_url'],
      'permit_url': permitPath ?? existing['permit_url'],
      'verification_status': AppConstants.bizStatusPending,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'verified_at': null,
    };

    final inserted = await _client
        .from('seller_business_docs')
        .upsert(row, onConflict: 'profile_id')
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  /// Admin: every Tier 2 submission (any status), newest first.
  Future<List<Map<String, dynamic>>> fetchAllBusinessVerifications() async {
    final data = await _client
        .from('seller_business_docs')
        .select(
          '*, profiles(id, full_name, email, store_name)',
        )
        .order('created_at', ascending: false);
    return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Admin: set a Tier 2 verdict via the SECURITY DEFINER RPC
  /// (`set_business_verification_status`), which re-checks is_admin()
  /// server-side. 'verified' stamps verified_at; 'rejected' leaves it null.
  Future<void> setBusinessVerificationStatus(
    String docId, {
    required bool verified,
  }) async {
    await _client.rpc(
      'set_business_verification_status',
      params: {
        'p_doc_id': docId,
        'p_status': verified
            ? AppConstants.bizStatusVerified
            : AppConstants.bizStatusRejected,
      },
    );
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
