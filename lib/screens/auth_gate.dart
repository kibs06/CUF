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
import '../widgets/error_retry_widget.dart';
import 'admin/admin_shell.dart';
import 'auth/login_screen.dart';
import 'auth/onboarding_screen.dart';
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

  /// Whether the user was previously authenticated in this session.
  /// Used to detect session expiry mid-use.
  bool _wasAuthenticated = false;

  /// Whether we've set up the auth hooks (login/logout) already.
  bool _hooksWired = false;

  /// Maximum time to wait for a profile fetch before showing a retry screen.
  static const _profileTimeout = Duration(seconds: 12);

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

  /// Show a non-dismissible bottom sheet when the session expires mid-use.
  void _showSessionExpiredSheet() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppConstants.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                color: AppConstants.error,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Session Expired',
              style: AppConstants.headlineStyle(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Your session has expired. Please sign in again.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: Text(
                  'Sign In',
                  style: AppConstants.headlineStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.surfaceLight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
            _wasAuthenticated = true;
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

          // Detect session expiry mid-use
          if (_wasAuthenticated) {
            _wasAuthenticated = false;

            // Schedule showing the session expired sheet after build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showSessionExpiredSheet();
            });
          }

          // First time ever opening app → show onboarding
          // Returning logged-out user → show login
          return const _FirstTimeOrLoginRouter();
        }

        _wasAuthenticated = true;

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
    final role = profile['role']?.toString() ?? AppConstants.roleCustomer;
    final sellerStatus = profile['seller_status']?.toString() ?? 'none';

    Widget target;
    if (role == AppConstants.roleAdmin) {
      target = const AdminShell();
    } else if (role == AppConstants.roleSeller &&
        sellerStatus == AppConstants.statusApproved) {
      target = const SellerShell();
    } else if (sellerStatus == AppConstants.statusPending) {
      target = const PendingApprovalScreen();
    } else {
      target = const CustomerShell();
    }

    // Smooth fade-in transition (Change 6c)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(target.runtimeType),
        child: target,
      ),
    );
  }
}

// ─── First Time / Login Router ──────────────────────────────────────
/// Checks SharedPreferences to decide between OnboardingScreen and LoginScreen.
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
    return const LoginScreen();
  }
}

// ─── Pending Approval Screen ──────────────────────────────────────
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppConstants.statusPendingColor.withValues(
                          alpha: 0.16,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: AppConstants.statusPendingColor,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Seller Application Pending',
                      textAlign: TextAlign.center,
                      style: AppConstants.headlineStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your account was created. An admin needs to approve your seller access before you can open the seller dashboard.',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        color: AppConstants.secondary.withValues(alpha: 0.68),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.read<AuthProvider>().logout(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log Out'),
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

  const _ProfileErrorView({
    required this.error,
    required this.onRetry,
    required this.checkConnection,
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
        child: ErrorRetryWidget(
          message: message,
          onRetry: widget.onRetry,
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
