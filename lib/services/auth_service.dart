import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../models/seller_application_data.dart';
import '../utils/customer_profile_fields.dart' as customer_profile_fields;
import 'deep_link_service.dart';

/// Result of [AuthService.ensureUser] — the authenticated user plus whether
/// the e-mail still has to be confirmed before anything can be written for
/// them. When [emailVerificationRequired] is true there is deliberately NO
/// session yet (see `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md`).
class EnsureUserResult {
  final User user;
  final bool emailVerificationRequired;

  const EnsureUserResult({
    required this.user,
    required this.emailVerificationRequired,
  });
}

/// Thrown by [AuthService.signInWithGoogle] when `requireExistingAccount` is
/// set and the Google account's email has no row in `profiles` yet.
///
/// A typed signal (not a message string) so the UI can ROUTE — switch to the
/// create-account panel — instead of showing an error toast. It is
/// intercepted in `AuthProvider.signInWithSocial` before the error mapper,
/// so it never reaches `friendlyAuthErrorMessage` or the generic fallback.
class UnregisteredSocialAccountException implements Exception {
  final String email;

  const UnregisteredSocialAccountException(this.email);

  @override
  String toString() => 'UnregisteredSocialAccountException($email)';
}

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

  // ── Social sign-in (Google + Facebook) ─────────────────────────────
  //
  // Both go through the NATIVE provider SDKs, then prove the result to
  // Supabase with signInWithIdToken — no passwords, no email OTP. A social
  // identity only ever yields the default `customer` profile row (see
  // writeProfileFromMetadata): sellers still complete the application flow,
  // and admins are never provisioned by this path (the portal gate blocks
  // non-admins; the app has no admin role at all).
  //
  // Both methods REQUIRE the Phase-0 console setup
  // (docs/SOCIAL_SIGNIN_SETUP.md): enabling the provider in Supabase plus
  // the Google OAuth client / Meta app. Until then the Supabase call throws
  // and [_socialNotEnabled] turns it into setup copy instead of a dead end.

  /// Shared tail for both social methods: profile row + return shape.
  ///
  /// `emailMissing` is true when the provider gave no email address
  /// (common on Facebook) — the caller prompts for one so the profile row
  /// is never stuck with an empty email.
  Future<Map<String, dynamic>> _profileForSocialUser(User user) async {
    final profile = await getProfile(user.id) ??
        await writeProfileFromMetadata(user);
    final email = user.email ?? '';
    return {
      'user': {'id': user.id, 'email': email},
      'profile': profile,
      'emailMissing': email.isEmpty,
    };
  }

  /// Signs in with the native Google account picker.
  ///
  /// [serverClientId] is the Google Web OAuth client ID (used as the
  /// audience for the ID token). Pass it explicitly when the app has no
  /// `google-services` config carrying a Web client entry; otherwise the
  /// native SDK resolves it from the platform configuration.
  ///
  /// When [requireExistingAccount] is true (the Sign in screen), a Google
  /// account whose email has no `profiles` row throws
  /// [UnregisteredSocialAccountException] BEFORE any Supabase call — so no
  /// auth user is created and the UI can route to account creation instead
  /// of silently provisioning a customer.
  Future<Map<String, dynamic>> signInWithGoogle({
    String? serverClientId,
    bool requireExistingAccount = false,
  }) async {
    // `google-services.json` carries no `oauth_client` entry on this
    // project, and iOS has no GoogleService-Info.plist — so the explicit
    // Web client ID is required. Empty means Phase-0 console setup has not
    // landed: keep the dormant setup copy instead of failing inside the SDK.
    final effectiveServerClientId =
        (serverClientId ?? AppConstants.googleServerClientId).trim();
    if (effectiveServerClientId.isEmpty) {
      throw Exception(
        'Google sign-in is not switched on yet. Use your email and '
        'password for now.',
      );
    }
    final existing = _client.auth.currentSession;
    if (existing != null) {
      await _client.auth.signOut();
    }

    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(serverClientId: effectiveServerClientId);
    final account = await googleSignIn.authenticate();
    // Sign-in mode only: an unknown Gmail must NOT auto-provision a
    // customer — bounce to the create-account panel instead. Checked here,
    // before signInWithIdToken, so the attempt leaves no auth user behind.
    // A failed lookup fails OPEN (normal flow): the Supabase call below
    // surfaces a real outage as its own error rather than this blocking it.
    if (requireExistingAccount) {
      // CONTRACT: `emailExists` reads the world-readable `profiles` table
      // with no session (any existing session was signed out above), so this
      // check only answers correctly while that SELECT stays public. If RLS
      // ever closes it, the lookup throws and we fail OPEN below — an
      // unknown Gmail would auto-provision again, the exact behavior this
      // flag exists to prevent. The debugPrint keeps that degradation
      // visible in device logs instead of silent.
      final googleEmail = account.email.trim();
      if (googleEmail.isNotEmpty) {
        bool known = true;
        try {
          known = await emailExists(googleEmail);
        } catch (e) {
          debugPrint('[AuthError] requireExistingAccount lookup failed ($e) '
              '— proceeding with normal sign-in.');
          known = true;
        }
        if (!known) throw UnregisteredSocialAccountException(googleEmail);
      }
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception(
        'Google sign-in did not return an ID token. Please try again.',
      );
    }
    // The auth token lives behind a separate authorization grant in
    // google_sign_in 7.x — best-effort here, the ID token is what
    // Supabase verifies.
    String? accessToken;
    try {
      final authorization =
          await account.authorizationClient.authorizationForScopes(const []);
      accessToken = authorization?.accessToken;
    } catch (_) {
      // Optional grant — not worth failing the sign-in over.
    }

    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      final user = response.user;
      if (user == null) throw Exception('Google sign-in failed.');
      return await _profileForSocialUser(user);
    } on AuthException catch (e) {
      _throwIfSocialNotEnabled(e, 'Google');
      rethrow;
    }
  }

  /// Signs in with the native Facebook Login SDK.
  ///
  //  iOS uses Limited Login; Android requests the `openid` scope via a
  //  web-only flow so the SDK returns an OIDC ID token — Supabase's
  //  signInWithIdToken verifies THAT token, not the classic access token,
  //  so passing the access token as `idToken` is NOT equivalent.
  Future<Map<String, dynamic>> signInWithFacebook() async {
    final existing = _client.auth.currentSession;
    if (existing != null) {
      await _client.auth.signOut();
    }

    final LoginResult result;
    if (Platform.isIOS) {
      result = await FacebookAuth.instance.login(
        permissions: const ['public_profile', 'email'],
        loginTracking: LoginTracking.limited,
      );
    } else {
      result = await FacebookAuth.instance.login(
        permissions: const ['public_profile', 'email', 'openid'],
        loginBehavior: LoginBehavior.webOnly,
      );
    }
    if (result.status != LoginStatus.success) {
      throw Exception(
        result.message ?? 'Facebook sign-in was cancelled.',
      );
    }
    final token = result.accessToken;
    String? idToken;
    if (token is LimitedToken) {
      idToken = token.tokenString;
    } else if (token is ClassicToken) {
      idToken = token.authenticationToken;
    }
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Facebook did not return a sign-in token. Please try again.',
      );
    }

    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.facebook,
        idToken: idToken,
      );
      final user = response.user;
      if (user == null) throw Exception('Facebook sign-in failed.');
      return await _profileForSocialUser(user);
    } on AuthException catch (e) {
      _throwIfSocialNotEnabled(e, 'Facebook');
      rethrow;
    }
  }

  /// Replaces GoTrue's raw "provider not enabled" failure with the setup
  /// copy. Message-sniffed deliberately: this is a CONSOLE state error, not
  //  a credential rejection, and GoTrue gives it no stable per-provider code
  /// — the alternative is the generic "Something went wrong" dead end.
  void _throwIfSocialNotEnabled(AuthException e, String provider) {
    final haystack = '${e.code} ${e.message}'.toLowerCase();
    if (haystack.contains('not enabled') ||
        haystack.contains('unsupported provider')) {
      throw Exception(
        '$provider sign-in is not switched on yet. Use your email and '
        'password for now.',
      );
    }
  }

  /// Creates the Supabase auth user for a CUSTOMER signup.
  ///
  /// ⚠️ Ordering contract: `public.profiles` has no `on auth.users` trigger —
  /// its INSERT policy is `auth.uid() = id`, so a session must already exist
  /// to write the row. With "Confirm email" ON, `signUp` returns **no
  /// session**, so the profile write is DEFERRED to [writeProfileFromMetadata],
  /// which the verify-email screen calls once `verifyOTP` has established one.
  ///
  /// The fields the profile needs are therefore also stashed in the user's
  /// metadata (server-side, so closing the app mid-verification — or the same
  /// code being typed on another device — does not lose them).
  ///
  /// Returns `{'user', 'profile', 'emailVerificationRequired'}`. `profile` is
  /// null when verification is still pending.
  Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String email,
    required String password,
    String sellerStatus = 'none',
    String? phone,
    DateTime? birthday,
    String? gender,
  }) async {
    // Birthday/gender are collected at signup (see customer_register_screen).
    // formatBirthdayForDb keeps the DATE column from shifting across
    // midnight via UTC serialization.
    final birthdayValue = customer_profile_fields.formatBirthdayForDb(birthday);

    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        // Mirrors the profiles columns so the row can be written later from
        // metadata alone, after email confirmation.
        //
        // The explicit `role` is ALSO what tells a link-confirmed signup
        // whether it may write that row at all: the seller flow's signup
        // (`ensureUser`) carries only a name and must not produce a plain
        // customer row. See `AuthProvider.completeSignupFromEmailLink`.
        'role': AppConstants.roleCustomer,
        'seller_status': sellerStatus,
        'phone': phone,
        'birthday': birthdayValue,
        'gender': gender,
      },
      // The confirmation e-mail's button comes back to the APP, not to the
      // site URL (which the app cannot use at all). See
      // `DeepLinkService.authConfirmRedirect` for the three places that must
      // agree on this value.
      emailRedirectTo: DeepLinkService.authConfirmRedirect,
    );
    final user = response.user;
    if (user == null) throw Exception('Sign up failed. Please try again.');

    if (response.session == null) {
      // "Confirm email" is ON. No session ⇒ no profile write yet: RLS would
      // reject it. The verify-email screen finishes the job.
      return {
        'user': {'id': user.id, 'email': user.email ?? email.trim()},
        'profile': null,
        'emailVerificationRequired': true,
      };
    }

    final profile = await writeProfileFromMetadata(user);

    return {
      'user': {'id': user.id, 'email': user.email ?? email.trim()},
      'profile': profile,
      'emailVerificationRequired': false,
    };
  }

  /// Upserts the `profiles` row for [user] from the metadata captured at
  /// sign-up. Idempotent, so it is safe on both paths: immediately after
  /// `signUp` when confirmation is OFF, or after `verifyOTP` when it is ON.
  ///
  /// ⚠️ It also runs for accounts that predate e-mail confirmation (a
  /// never-confirmed legacy account that just verified, see
  /// `AuthProvider.login`). For those the row ALREADY EXISTS, so the method
  /// must not clobber it: `role` and `seller_status` are only ever written
  /// when there is no row yet (otherwise a legacy approved SELLER, whose
  /// metadata has no `role`, would be silently demoted to `customer`), and
  /// only non-null metadata values overwrite existing columns.
  Future<Map<String, dynamic>> writeProfileFromMetadata(User user) async {
    final meta = user.userMetadata ?? const <String, dynamic>{};

    final existing = await _client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

    final profileData = <String, dynamic>{
      'id': user.id,
      'full_name': (meta['full_name'] ?? '').toString(),
      'email': user.email ?? (meta['email'] ?? '').toString(),
    };

    if (existing == null) {
      // First write for this account — it also needs its role/status.
      profileData['role'] =
          (meta['role'] ?? AppConstants.roleCustomer).toString();
      profileData['seller_status'] = (meta['seller_status'] ?? 'none').toString();
    }

    // Identity fields are only applied when the metadata actually carries
    // them, so a legacy row's phone/birthday/gender survive too.
    for (final key in const ['phone', 'birthday', 'gender']) {
      if (meta[key] != null) profileData[key] = meta[key];
    }

    await _client.from('profiles').upsert(profileData);
    return await getProfile(user.id) ?? profileData;
  }

  /// Ensures an authenticated Supabase user exists for [email].
  ///
  /// Used by the seller application flow, which deliberately creates the
  /// auth user only at the FINAL submit step (so abandoning the flow never
  /// leaves an orphaned account). Handles four cases:
  ///
  /// 1. Already signed in with this email (re-apply) → returns the current
  ///    user, no network call.
  /// 2. Signed in with a DIFFERENT account → signs out first (mirrors
  ///    [signIn]) so the new signup runs in a clean session.
  /// 3. Not signed in → auth.signUp. If Supabase reports the account
  ///    already exists but returns no session (e.g. an abandoned legacy
  ///    application), signs in with the supplied password instead so the
  ///    retryable submit can complete the profile.
  /// 4. **"Confirm email" is ON** → `signUp` returns no session and the
  ///    sign-in fallback above fails with `email_not_confirmed`. That is
  ///    reported as [EnsureUserResult.emailVerificationRequired] rather than
  ///    thrown, so the flow can verify FIRST and only then upload into the
  ///    private bucket / write the profile — both of which need a session
  ///    (`seller-verification-docs` RLS keys off `auth.uid()`).
  Future<EnsureUserResult> ensureUser({
    required String email,
    String? password,
    String? fullName,
  }) async {
    final trimmedEmail = email.trim();
    final current = _client.auth.currentUser;
    if (current != null) {
      if ((current.email ?? '').toLowerCase() == trimmedEmail.toLowerCase()) {
        return EnsureUserResult(
          user: current,
          emailVerificationRequired: false,
        );
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
    final user = response.user;
    if (user == null) throw Exception('Sign up failed. Please try again.');

    if (response.session != null) {
      return EnsureUserResult(user: user, emailVerificationRequired: false);
    }

    // No session. Either the account already exists (an abandoned
    // application) or email confirmation is required. Diffing on the
    // server's own answer is more reliable than guessing from config.
    try {
      final signIn = await _client.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
      return EnsureUserResult(
        user: signIn.user ?? user,
        emailVerificationRequired: false,
      );
    } on AuthException catch (e) {
      if (e.code == 'email_not_confirmed') {
        return EnsureUserResult(user: user, emailVerificationRequired: true);
      }
      // Wrong password / anything else: surface it unchanged so the flow's
      // existing error mapper keeps producing the right copy.
      rethrow;
    }
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

  /// Send the password-reset e-mail (the sign-in screen's "Forgot password?"
  /// and the lockout overlay's "Reset password").
  ///
  /// `redirectTo` is what makes the mailed link usable, and it points at the
  /// APP: GoTrue's button is an `https://…/auth/v1/verify` link that 302s to
  /// the redirect it was given, so the customer lands in CUFMAI with a
  /// short-lived recovery session (`#access_token=…&type=recovery`) instead of
  /// on a web page. With no redirect at all GoTrue resolves the link to the
  /// project's **Site URL** — a dashboard value the app cannot see — and while
  /// that was the shipped `localhost:3000` default, tapping the link opened a
  /// dead page (`ERR_CONNECTION_REFUSED`) even after the mailer was repaired.
  ///
  /// ⚠️ GoTrue only honours a redirect it has been told about, so this value
  /// must be in the live project's allow list — written, together with the
  /// site URL, by `tool/apply_live_auth_mail.dart`. See
  /// `DeepLinkService.authRecoveryRedirect` for the three places that agree.
  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: DeepLinkService.authRecoveryRedirect,
    );
  }


  // ── Failed-login tracking ──────────────────────────────────────
  static const _maxFailedAttempts = 5;
  static const _lockoutMinutes = 30;

  /// Record a failed login attempt for [userId] from [ipAddress] with
  /// [userAgent]. Returns the updated failed_login row.
  Future<Map<String, dynamic>> recordFailedLogin(
    String userId, {
    String? ipAddress,
    String? userAgent,
  }) async {
    final client = _client;
    final now = DateTime.now().toUtc();

    // Upsert: one row per user, update attempts and lock status
    final data = await client
        .from('failed_logins')
        .upsert({
          'user_id': userId,
          'ip_address': ipAddress,
          'user_agent': userAgent,
          'status': 'active',
          'failed_at': now.toIso8601String(),
          'locked_until': now.add(Duration(minutes: _lockoutMinutes)).toIso8601String(),
        },
        onConflict: 'user_id')
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  /// Check if [userId] is currently locked out. Returns lockout info or null.
  Future<Map<String, dynamic>?> checkLockout(String userId) async {
    final client = _client;
    final now = DateTime.now().toUtc();

    final data = await client
        .from('failed_logins')
        .select('*, profiles(role)')
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return null;

    final status = data['status'] as String;
    final lockedUntil = data['locked_until'] != null
        ? DateTime.parse(data['locked_until'] as String).toUtc()
        : null;

    // If locked and the lockout has expired, unlock the account
    if (status == 'locked' && lockedUntil != null && now.isAfter(lockedUntil)) {
      // Unlock the account
      await client
          .from('failed_logins')
          .update({
            'status': 'active',
            'locked_until': null,
          })
          .eq('user_id', userId);
      return {
        'wasLocked': true,
        'justUnlocked': true,
        'remainingMinutes': 0,
        'role': (data['profiles'] as Map<String, dynamic>?)?['role'],
      };
    }

    if (status == 'locked' && lockedUntil != null) {
      final remaining = lockedDifference(lockedUntil, now);
      return {
        'wasLocked': true,
        'justUnlocked': false,
        'remainingMinutes': remaining,
        'role': (data['profiles'] as Map<String, dynamic>?)?['role'],
      };
    }

    // Active account — no lockout
    return {
      'wasLocked': false,
      'remainingMinutes': 0,
      'role': (data['profiles'] as Map<String, dynamic>?)?['role'],
    };
  }

  /// Advance the failed-attempt counter. On the 5th consecutive failure,
  /// lock the account for [_lockoutMinutes] minutes.
  ///
  /// [location], [latitude] and [longitude] are the city-level place the
  /// attempt's address resolves to (see `IpGeolocationService`), stored for the
  /// admin's intruder view. They are evidence ABOUT the lockout, never an input
  /// to it: every one of them is optional and the lockout decision does not
  /// read them.
  Future<Map<String, dynamic>> advanceFailedCounter({
    required String userId,
    required String ipAddress,
    required String userAgent,
    String? location,
    double? latitude,
    double? longitude,
  }) async {
    final client = _client;
    final now = DateTime.now().toUtc();

    // First, check if there's an existing row. `id` comes along because the
    // write below is an UPDATE of this row when it exists (see
    // [_writeFailedLoginRow] for why it is not an upsert), and the newest row
    // wins if a database somehow holds more than one for this account —
    // `.maybeSingle()` would throw on that rather than pick.
    final existing = await client
        .from('failed_logins')
        .select('id, attempt_count, locked_until, status')
        .eq('user_id', userId)
        .order('failed_at', ascending: false)
        .limit(1)
        .maybeSingle();

    int attemptCount = 1;
    String newStatus = 'active';
    DateTime? newLockedUntil;

    if (existing != null) {
      final existingCount = (existing['attempt_count'] ?? 0) as int;
      final existingLocked = existing['locked_until'] as String?;
      final existingStatus = existing['status'] as String;

      // If currently locked and lockout expired, reset counter
      if (existingStatus == 'locked' &&
          existingLocked != null &&
          now.isAfter(DateTime.parse(existingLocked).toUtc())) {
        attemptCount = 1;
        newStatus = 'active';
        newLockedUntil = null;
      } else if (existingStatus == 'locked' && existingLocked != null) {
        // Still locked — increment but keep locked
        attemptCount = existingCount + 1;
        newStatus = 'locked';
        newLockedUntil = DateTime.parse(existingLocked).toUtc().add(
            Duration(minutes: _lockoutMinutes));
      } else {
        // Active, increment
        attemptCount = existingCount + 1;
        newStatus = 'active';
        newLockedUntil = null;
      }
    } else {
      attemptCount = 1;
      newStatus = 'active';
      newLockedUntil = null;
    }

    // If we just hit the 5th attempt, lock the account
    if (attemptCount >= _maxFailedAttempts) {
      newStatus = 'locked';
      newLockedUntil = now.add(Duration(minutes: _lockoutMinutes));
    }

    final row = <String, dynamic>{
      'user_id': userId,
      'attempt_count': attemptCount,
      'status': newStatus,
      'locked_until': newLockedUntil?.toIso8601String(),
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'failed_at': now.toIso8601String(),
    };

    final hasLocation =
        (location != null && location.trim().isNotEmpty) ||
        latitude != null ||
        longitude != null;
    if (hasLocation) {
      row['location'] = location;
      row['latitude'] = latitude;
      row['longitude'] = longitude;
    }

    final existingId = existing?['id'] as String?;

    try {
      return await _writeFailedLoginRow(
        client: client,
        values: row,
        existingId: existingId,
      );
    } on PostgrestException catch (e) {
      // The three location columns arrive in
      // `20261012120000_add_location_to_failed_logins.sql`. Until that is
      // applied the server refuses the WHOLE row — which would silently stop
      // the device/IP forensics that already work, the exact opposite of what
      // this change is for. So the geo fields are dropped and the write
      // retried: the lockout keeps the evidence it has always had and simply
      // has no location. Measured answer (local PostgREST, 2026-10-12):
      // `PGRST204 — Could not find the 'latitude' column of 'failed_logins'
      // in the schema cache`, naming whichever of the three the server meets
      // first — which is why `isUnknownLocationColumn` matches all three.
      if (!hasLocation || !isUnknownLocationColumn(e)) rethrow;
      debugPrint(
        '[AuthService] failed_logins has no location column yet — recording '
        'the device and IP only. Apply '
        '20261012120000_add_location_to_failed_logins.sql to store the '
        'attacker location too.',
      );
      row.remove('location');
      row.remove('latitude');
      row.remove('longitude');
      return _writeFailedLoginRow(
        client: client,
        values: row,
        existingId: existingId,
      );
    }
  }

  /// Writes one lockout row — an UPDATE of the account's existing row when
  /// [existingId] is known, an INSERT when it is not.
  ///
  /// ⚠️ **This deliberately replaces `upsert(..., onConflict: 'user_id')`, and
  /// the reason is measured rather than stylistic.** The only unique index on
  /// `user_id` is **partial** — `uq_user_active_failed … WHERE status IN
  /// ('active','locked')` — and Postgres refuses an `ON CONFLICT (user_id)`
  /// that does not repeat that predicate, answering `42P10` ("there is no
  /// unique or exclusion constraint matching the ON CONFLICT specification").
  /// PostgREST does not emit the predicate, so **every** lockout write failed;
  /// and because the caller treats this write as best-effort, the failure was
  /// silent — the device, the IP and the location were never recorded, and the
  /// admin's intruder view stayed empty. Measured against a local PostgREST on
  /// 2026-10-12, both with and without this change's own columns.
  ///
  /// The alternative fix is a schema change: an unconditional unique index on
  /// `user_id`, which is what the table's own header describes ("Single row per
  /// user (upsert on each attempt)"). That is the cleaner end state and is
  /// noted in `supabase/MIGRATIONS_LIVE_STATUS.md`; it is not done here because
  /// it must first be checked against the rows the hosted project actually
  /// holds, and this path needs no such assumption.
  Future<Map<String, dynamic>> _writeFailedLoginRow({
    required SupabaseClient client,
    required Map<String, dynamic> values,
    required String? existingId,
  }) async {
    final builder = existingId == null
        ? client.from('failed_logins').insert(values)
        : client.from('failed_logins').update(values).eq('id', existingId);
    final data = await builder.select().single();
    return Map<String, dynamic>.from(data);
  }

  /// True when [e] is the server saying the location columns do not exist yet
  /// (this migration has not been applied).
  ///
  /// Narrow on purpose: only an unknown-column answer that NAMES one of the
  /// three columns is treated as "the migration is missing". Anything else —
  /// RLS, a network fault, a constraint — is rethrown and handled as the real
  /// failure it is. Public so the rule can be pinned by a test: too narrow and
  /// a lockout loses the device/IP evidence it has always had, too broad and
  /// a real failure is retried into a confusing second error.
  ///
  /// **All three names are checked, and that is measured rather than tidy.**
  /// PostgREST reports the FIRST unknown key it meets, so with the columns
  /// absent the real answer for a payload carrying `location`, `latitude` and
  /// `longitude` is:
  ///
  ///   `PGRST204 — Could not find the 'latitude' column of 'failed_logins' in
  ///   the schema cache`
  ///
  /// — a message that does not contain the string `location` at all. Matching
  /// on `location` alone (which is what this did until the live answer was
  /// measured against a local stack on 2026-10-12) would have let the write
  /// fail, and with it the device and IP the lockout has always recorded.
  @visibleForTesting
  static bool isUnknownLocationColumn(PostgrestException e) {
    final message = e.message.toLowerCase();
    final namesAGeoColumn = _locationColumns.any(message.contains);
    if (!namesAGeoColumn) return false;
    // PGRST204: unknown column in the payload. 42703: undefined_column.
    return e.code == 'PGRST204' ||
        e.code == '42703' ||
        message.contains('schema cache') ||
        message.contains('does not exist');
  }

  /// The columns added by
  /// `20261012120000_add_location_to_failed_logins.sql`. Not columns of any
  /// other table this row touches, so naming one is unambiguous.
  static const _locationColumns = ['location', 'latitude', 'longitude'];

  /// Reset the failed-attempt counter on successful login.
  Future<void> resetFailedCounter(String userId) async {
    await _client
        .from('failed_logins')
        .update({
          'attempt_count': 0,
          'status': 'active',
          'locked_until': null,
        })
        .eq('user_id', userId);
  }

  /// Admin: fetch all failed-login rows with the user's email/name.
  Future<List<Map<String, dynamic>>> fetchAllFailedLogins() async {
    final data = await _client
        .from('failed_logins')
        .select('*, profiles(id, full_name, email, role)')
        .order('failed_at', ascending: false);
    return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Admin: clear all lockouts (reset all rows to active).
  Future<void> clearAllLockouts() async {
    await _client
        .from('failed_logins')
        .update({
          'status': 'active',
          'attempt_count': 0,
          'locked_until': null,
        })
        .neq('status', 'active');
  }

  /// Set a new password for the CURRENT session — the last step of the
  /// recovery flow (`AuthProvider.applyRecoveredPassword`), and the same call
  /// any change-password screen makes.
  ///
  /// Throws when GoTrue refuses the password: the project enforces
  /// `password_min_length` (live value 6), and answers `weak_password` — or
  /// `same_password` when the new one matches the old. Both are mapped in
  /// `friendlyAuthErrorMessage`. The session is AAL1-with-recovery-token at
  /// this point, and the live project does not require re-authentication for a
  /// password update (`security_update_password_require_reauthentication` =
  /// false); if that is ever turned on, THIS call starts failing with
  /// `reauthentication_needed` instead of silently doing nothing.
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Send account lockout notification email to the account owner.
  /// Uses the existing email-sending function (Supabase resetPasswordForEmail)
  /// which sends a password reset link. The reset form will check for
  /// pending lockout/intruder state and present the two confirmation options.
  /// On successful reset or confirmation, the lockout is lifted.
  Future<void> sendLockoutNotificationEmail(String email) async {
    // Reuse the existing email-sending function, with the same `redirectTo`
    // as [resetPassword]: one reset destination, so a lockout mail can never
    // send the customer somewhere the new-password form is not.
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: DeepLinkService.authRecoveryRedirect,
    );
    debugPrint(
        '[Auth] Lockout notification email sent to: $email (Supabase reset password)');
  }

  /// Calculate remaining minutes until lockout expires
  int lockedDifference(DateTime lockedUntil, DateTime now) {
    final difference = lockedDifferenceInSeconds(lockedUntil, now);
    return (difference / 60).ceil().clamp(0, _lockoutMinutes);
  }

  int lockedDifferenceInSeconds(DateTime lockedUntil, DateTime now) {
    final difference = lockedUntil.difference(now).inSeconds;
    return difference.clamp(0, _lockoutMinutes * 60);
  }


  /// Update the user's email address.
  ///
  /// Supabase sends a confirmation link to the new email. The email won't
  /// actually change until the user clicks that link. Throws if the user
  /// is not signed in or the new email is already taken.
  Future<void> updateEmail(String newEmail) async {
    await _client.auth.updateUser(UserAttributes(email: newEmail.trim()));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
