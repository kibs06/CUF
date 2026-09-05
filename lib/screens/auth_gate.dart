import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/follow_provider.dart';
import '../services/auth_service.dart';
import '../services/mfa_service.dart';
import '../widgets/error_retry_widget.dart';
import 'shared/mfa_verify_screen.dart';
import 'admin/admin_shell.dart';
import 'auth/account_entry_screen.dart';
import 'auth/onboarding_screen.dart';
import 'auth/pending_approval_screen.dart';
import 'auth/seller_approved_celebration_screen.dart';
import 'customer/customer_shell.dart';
import 'seller/seller_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService.instance;
  Future<Map<String, dynamic>?>? _profileFuture;
  String? _profileUserId;

  /// User ids that already saw the approval celebration — so the welcome
  /// screen shows exactly once per account (persisted in prefs).
  final Set<String> _celebratedUserIds = {};

  /// Whether we've set up the auth hooks (login/logout) already.
  bool _hooksWired = false;

  /// Maximum time to wait for a profile fetch before showing a retry screen.
  static const _profileTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _loadCelebratedUsers();
  }

  /// Loads the persisted set of user ids that already saw the approval
  /// celebration (prefs key `seller_celebration_seen_v1`).
  Future<void> _loadCelebratedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('seller_celebration_seen_v1') ?? [];
    if (!mounted) return;
    setState(() => _celebratedUserIds.addAll(ids));
  }

  /// Marks [userId] as having seen the celebration and persists it, so the
  /// welcome screen never shows again for that account.
  Future<void> _markCelebrated(String userId) async {
    if (_celebratedUserIds.contains(userId)) return;
    setState(() => _celebratedUserIds.add(userId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'seller_celebration_seen_v1',
      _celebratedUserIds.toList(),
    );
  }

  /// Wire up auth hooks so FollowProvider loads on login and resets on logout.
  void _wireAuthHooks() {
    if (_hooksWired) return;
    _hooksWired = true;
    final auth = context.read<AuthProvider>();
    final follow = context.read<FollowProvider>();
    auth.onLoginHook = (userId) => follow.loadForUser(userId);
    auth.onLogoutHook = () => follow.reset();

    // Also load for an existing session (app restart) — the hook only
    // fires on explicit login/signup, not on a persisted session.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null && !follow.isLoaded) {
      follow.loadForUser(userId);
    }
  }

  Future<Map<String, dynamic>?> _profileFor(User user) {
    if (_profileFuture == null || _profileUserId != user.id) {
      _profileUserId = user.id;
      _profileFuture = _authService
          .getProfile(user.id)
          .timeout(_profileTimeout);
    }
    return _profileFuture!;
  }

  /// Force-reset profile cache — called when the auth stream emits
  /// a new signedIn event for a different user so we never serve
  /// the previous user's stale profile.
  void _resetProfileCache() {
    _profileFuture = null;
    _profileUserId = null;
  }

  void _retryProfile(User user) {
    setState(() {
      _profileUserId = user.id;
      _profileFuture = _authService.getProfile(user.id).timeout(_profileTimeout);
    });
  }

  /// Quick connectivity check — returns true if the device can reach the internet.
  Future<bool> _hasConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure hooks are wired once per widget lifecycle.
    _wireAuthHooks();

    return StreamBuilder<AuthState>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // While stream is connecting, check for an existing session immediately
        if (snapshot.connectionState == ConnectionState.waiting) {
          final existingSession =
              Supabase.instance.client.auth.currentSession;
          if (existingSession != null) {
            // Already logged in — load profile and route directly
            return FutureBuilder<Map<String, dynamic>?>(
              future: _profileFor(existingSession.user),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const _LoadingScreen();
                }
                if (profileSnapshot.hasError ||
                    profileSnapshot.data == null) {
                  return _ProfileErrorView(
                    error: profileSnapshot.error,
                    onRetry: () => _retryProfile(existingSession.user),
                    checkConnection: _hasConnection,
                    onSignOut: () =>
                        context.read<AuthProvider>().logout(),
                  );
                }
                return _routeByRole(profileSnapshot.data!);
              },
            );
          }
          // No session — show loading briefly
          return const _LoadingScreen();
        }

        final session = snapshot.data?.session;
        final user = session?.user;

        if (user == null) {
          // Reset cached profile so the next sign-in always fetches
          // the new user's profile from scratch.
          _resetProfileCache();

          // First time ever opening app → show onboarding
          // Returning logged-out user → show login
          return const _FirstTimeOrLoginRouter();
        }

        // Ensure FollowProvider is loaded for this session.
        // The hook covers explicit login; this covers persisted sessions.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final follow = context.read<FollowProvider>();
          if (!follow.isLoaded) {
            follow.loadForUser(user.id);
          }
        });

        return FutureBuilder<Map<String, dynamic>?>(
          future: _profileFor(user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            if (profileSnapshot.hasError || profileSnapshot.data == null) {
              return _ProfileErrorView(
                error: profileSnapshot.error,
                onRetry: () => _retryProfile(user),
                checkConnection: _hasConnection,
                onSignOut: () => context.read<AuthProvider>().logout(),
              );
            }

            return _routeByRole(profileSnapshot.data!);
          },
        );
      },
    );
  }

  /// Routes to the correct shell based on the user's profile role.
  /// Wrapped in AnimatedSwitcher for a smooth fade transition.
  Widget _routeByRole(Map<String, dynamic> profile) {
    // Hard ban gate: a suspended account never reaches any shell. RLS
    // blocks their writes server-side; here we block the UI entirely and
    // clear the session so they land on the login screen.
    if (profile['suspended'] == true) {
      return _SuspendedAccountScreen(
        reason: profile['suspended_reason']?.toString(),
        onSignOut: () => context.read<AuthProvider>().logout(),
      );
    }

    final role = profile['role']?.toString() ?? AppConstants.roleCustomer;
    final sellerStatus = profile['seller_status']?.toString() ?? 'none';

    Widget target;
    if (role == AppConstants.roleAdmin) {
      target = const AdminShell();
    } else if (role == AppConstants.roleSeller &&
        sellerStatus == AppConstants.statusApproved) {
      // One-time welcome: the first launch after approval shows the
      // celebration screen instead of going straight into the dashboard.
      // "Go to dashboard" marks the user seen and routes to SellerShell.
      final userId = profile['id']?.toString() ?? '';
      if (userId.isNotEmpty && !_celebratedUserIds.contains(userId)) {
        target = SellerApprovedCelebrationScreen(
          userName: profile['full_name']?.toString() ?? '',
          onGoToDashboard: () => _markCelebrated(userId),
        );
      } else {
        target = const SellerShell();
      }
    } else if (sellerStatus == AppConstants.statusPending) {
      target = const PendingApprovalScreen();
    } else {
      target = const CustomerShell();
    }

    // Every shell (customer, seller, admin) sits behind the same MFA
    // step-up gate: if the session is still AAL1 and the user has a
    // verified TOTP factor, the code screen shows before the shell.
    // MFA is per-user at Supabase Auth, so one gate covers all roles.
    // The gate is keyed by shell type so role switches still animate.
    // Smooth fade-in transition (Change 6c)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _MfaGate(
        key: ValueKey(target.runtimeType),
        child: target,
      ),
    );
  }
}

/// MFA step-up gate: shows [MfaVerifyScreen] when the session is still
/// AAL1 (password verified, MFA not yet completed) and the user has an
/// enrolled, verified TOTP factor. On success Supabase upgrades the
/// session to AAL2 and emits `mfaChallengeVerified`; AuthGate's stream
/// rebuilds and [didUpdateWidget] re-evaluates, unmounting this gate.
///
/// Fails open (no extra network waits): the factor list is read from
/// the session user's embedded `factors` claim, so a user with no MFA
/// never blocks on a round-trip here. Worst case is the challenge
/// appearing on the user's NEXT sign-in.
class _MfaGate extends StatefulWidget {
  final Widget child;

  const _MfaGate({super.key, required this.child});

  @override
  State<_MfaGate> createState() => _MfaGateState();
}

class _MfaGateState extends State<_MfaGate> {
  // null = checking (synchronous in practice), true = shell may show,
  // false = challenge required.
  bool? _open;
  String? _factorId;
  String? _lastAal;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(covariant _MfaGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fires after a verify success (auth stream → AuthGate rebuild →
    // new shell child): the AAL changed to aal2, so reopen.
    final aal = _currentAal();
    if (aal != _lastAal) _evaluate();
  }

  String _currentAal() => MfaService.aalFromJwtPayload(
        MfaService.jwtPayload(
          Supabase.instance.client.auth.currentSession?.accessToken ?? '',
        ),
      );

  void _evaluate() {
    _lastAal = _currentAal();
    final aal = _lastAal!;
    if (!MfaService.mfaRequiredForAal(aal)) {
      setState(() {
        _open = true;
        _factorId = null;
      });
      return;
    }

    final factors = Supabase.instance.client.auth.currentUser?.factors ?? const [];
    final verifiedTotp = factors.where(
      (f) => f.factorType == FactorType.totp && f.status == FactorStatus.verified,
    );
    final factor = verifiedTotp.isEmpty ? null : verifiedTotp.first;
    setState(() {
      _open = factor == null;
      _factorId = factor?.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_open == null) return const _LoadingScreen();
    if (_open == true) return widget.child;
    return MfaVerifyScreen(
      factorId: _factorId ?? '',
      onVerified: _evaluate,
    );
  }
}

// ─── First Time / Login Router ──────────────────────────────────────
/// Checks SharedPreferences to decide between OnboardingScreen and
/// AccountEntryScreen (the merged create-account / sign-in front door).
class _FirstTimeOrLoginRouter extends StatefulWidget {
  const _FirstTimeOrLoginRouter();

  @override
  State<_FirstTimeOrLoginRouter> createState() =>
      _FirstTimeOrLoginRouterState();
}

class _FirstTimeOrLoginRouterState extends State<_FirstTimeOrLoginRouter> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) return const _LoadingScreen();

    // Return directly — do NOT use Navigator.pushReplacement.
    // AuthGate's StreamBuilder controls all navigation after login.
    // When the stream emits signedIn, AuthGate rebuilds and replaces
    // this widget with the correct shell automatically.
    if (!_hasSeenOnboarding!) return const OnboardingScreen();
    return const AccountEntryScreen();
  }
}

// ─── Pending Approval Screen ──────────────────────────────────────
// Moved to lib/screens/auth/pending_approval_screen.dart (redesigned for
// the tiered-verification signup: shows submitted Tier 1 items + explains
// optional Tier 2). Imported at the top of this file.

// ─── Suspended Account Screen ────────────────────────────────────
/// Shown when the signed-in profile has `suspended = true`. Explains the
/// ban and offers sign-out; the session is only cleared when the user
/// taps the button (keeps them on this screen rather than silently
/// flipping to login).
class _SuspendedAccountScreen extends StatelessWidget {
  final String? reason;
  final VoidCallback onSignOut;

  const _SuspendedAccountScreen({required this.reason, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppConstants.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.block_rounded,
                        size: 36,
                        color: AppConstants.error,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Account Suspended',
                      style: AppConstants.headlineStyle(fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your account has been suspended. Please contact support if you believe this is a mistake.',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (reason != null && reason!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppConstants.cardRadius,
                          border: Border.all(
                            color: AppConstants.borderGray.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          reason!,
                          style: AppConstants.bodyStyle(fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: onSignOut,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Sign out'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppConstants.buttonRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Profile Error View ──────────────────────────────────────────
/// Checks connectivity and shows either a timeout message or a
/// "No internet" screen with retry.
class _ProfileErrorView extends StatefulWidget {
  final Object? error;
  final VoidCallback onRetry;
  final Future<bool> Function() checkConnection;

  /// Clears the current session. Offered on the error screen because a
  /// stale session (e.g. the account was deleted by an admin) can make the
  /// profile fetch fail forever — "Try Again" would loop without end.
  final VoidCallback onSignOut;

  const _ProfileErrorView({
    required this.error,
    required this.onRetry,
    required this.checkConnection,
    required this.onSignOut,
  });

  @override
  State<_ProfileErrorView> createState() => _ProfileErrorViewState();
}

class _ProfileErrorViewState extends State<_ProfileErrorView> {
  bool _isChecking = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final online = await widget.checkConnection();
    if (mounted) {
      setState(() {
        _isOnline = online;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const _LoadingScreen();
    }

    if (!_isOnline) {
      return Scaffold(
        backgroundColor: AppConstants.surfaceLight,
        body: Stack(
          children: [
            AppConstants.noiseOverlay(opacity: 0.03),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppConstants.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.wifi_off_rounded,
                        size: 32,
                        color: AppConstants.error,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No Internet Connection',
                      style: AppConstants.headlineStyle(fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please check your network settings and try again.',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () {
                          setState(() => _isChecking = true);
                          _check().then((_) {
                            if (_isOnline) widget.onRetry();
                          });
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppConstants.buttonRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Online but profile fetch failed — show a friendly message with
    // retry. NEVER surface raw exception strings (PostgrestException etc.)
    // to the customer — they're developer noise, not user guidance.
    final error = widget.error;
    // Keep the raw exception in the log so server-side issues (e.g.
    // PostgrestException code 42P17) stay diagnosable in production.
    debugPrint('[auth_gate] profile load failed: $error');
    final message = switch (error) {
      TimeoutException() =>
        'Taking longer than expected. Please check your connection and try again.',
      PostgrestException() =>
        'We could not load your account right now. Please try again in a moment.',
      _ => 'Unable to load your profile. Please try again.',
    };
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorRetryWidget(
                  message: message,
                  onRetry: widget.onRetry,
                ),
                const SizedBox(height: 16),
                // Escape hatch: a session whose account was deleted will
                // never load a profile, so Retry alone is a dead end.
                TextButton.icon(
                  onPressed: widget.onSignOut,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppConstants.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Loading Screen ───────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your experience…',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
