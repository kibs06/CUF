import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../utils/auth_error_messages.dart';
import '../../widgets/app_error_toast.dart';
import '../../widgets/auth/dark_auth_text_field.dart';
import '../../widgets/auth/dev_mode_badge.dart';
import '../../widgets/auth/dev_mode_swipe_detector.dart';
import '../../widgets/auth/full_bleed_video_background.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';
import '../../widgets/lockout_overlay.dart';
import 'customer_register_screen.dart';
import 'seller_application_flow.dart';

/// The two in-place modes of the merged front-door screen.
enum AuthEntryMode {
  /// \"Create your account\" — role choice (Shop as customer / Apply to sell).
  create,

  /// \"Welcome back\" — the email/password sign-in form.
  signin,
}

/// The merged front door: **one screen, two in-place modes** (`create` and
/// `signin`) sharing a single full-bleed video background.
///
/// Switching modes is a **state change within this widget** — it is never a
/// route push, so the video never restarts or cuts. Header and content block
/// slide in **opposite horizontal directions** on every switch, and the
/// direction reverses depending on which way you're going (create → signin:
/// header slides left / content slides right; signin → create: mirrored).
/// Both blocks are driven by one shared `AnimationController` through the
/// `_SlideSwap` widget — the content block's offset is the header's with the
/// sign flipped, not two independently-tuned animations. When the platform
/// reports reduced motion (`MediaQuery.disableAnimations`), the switch snaps
/// instantly instead of sliding.
///
/// Routing contract (from `docs/AI/SIGN_IN_ARCHITECTURE.md`, still applies):
/// **no self-navigation on successful login.** `_submit` calls
/// `AuthProvider.login` exactly like the legacy `LoginScreen` did and then
/// does nothing else — `AuthGate`'s `StreamBuilder` detects the new session
/// and swaps the root widget. The create-mode buttons DO push routes
/// (`CustomerRegisterScreen` / `SellerApplicationFlow`) exactly as the old
/// role-choice screen did; those flows own their own post-signup navigation.
///
/// Layout: header block pinned top, content block pinned bottom (bottom-anchored
/// inside a scroll view so short devices / large accessibility text scroll
/// instead of clipping), empty middle where the video is unobstructed. The
/// screen is light-theme-only like the rest of auth (the app defines no dark
/// theme) — the video + scrims are inherently dark by design.
class AccountEntryScreen extends StatefulWidget {
  const AccountEntryScreen({super.key});

  @override
  State<AccountEntryScreen> createState() => _AccountEntryScreenState();
}

class _AccountEntryScreenState extends State<AccountEntryScreen>
    with TickerProviderStateMixin {
  static const _transitionDuration = Duration(milliseconds: 280);

  // Sign-in form state (controllers live in State, so typed values survive
  // mode toggles even though the fields themselves are rebuilt each time).
  final _signinFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Biometric state.
  final BiometricService _bioService = BiometricService.instance;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricLoading = false;

  // Mode-switch state.
  AuthEntryMode _mode = AuthEntryMode.create;

  /// The mode being replaced — non-null only while a transition is running.
  AuthEntryMode? _previousMode;

  /// Content block controller.
  late final AnimationController _modeController;

  /// Header title block controller — independent of the content block so
  /// its timing can be tuned separately; both are started together in
  /// [_switchMode] so they stay in sync.
  late final AnimationController _headerController;
  bool _reducedMotion = false;

  /// Direction of the current transition. create → signin is \"forward\"
  /// (header slides left, content slides right); signin → create is the
  /// mirror. Only meaningful while `_previousMode != null`.
  bool get _isForward => _mode == AuthEntryMode.signin;

  @override
  void initState() {
    super.initState();
    _modeController = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    )..addStatusListener(_onTransitionStatus);
    _headerController = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    )..addStatusListener(_onTransitionStatus);
    _checkBiometricState();
    _checkLockoutOverlay();
  }

  /// If the user tapped a lockout push notification, show the overlay
  /// on first load.
  Future<void> _checkLockoutOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldShow = prefs.getBool('show_lockout_overlay') ?? false;
    if (shouldShow) {
      await prefs.remove('show_lockout_overlay');
      if (!mounted) return;
      // Wait for the first frame so the overlay renders on top
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        LockoutOverlay.show(
          context,
          email: '',
          remainingMinutes: 30,
        );
      });
    }
  }

  @override
  void dispose() {
    _modeController.dispose();
    _headerController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onTransitionStatus(AnimationStatus status) {
    // Transition finished — drop the outgoing copy so only the current mode
    // stays mounted (and its form GlobalKey stays unique).
    if (status == AnimationStatus.completed && _previousMode != null) {
      setState(() => _previousMode = null);
    }
  }

  void _switchMode(AuthEntryMode next) {
    if (_mode == next) return;
    _reducedMotion = MediaQuery.of(context).disableAnimations;
    if (_reducedMotion) {
      // Respect reduced motion: swap instantly, no slide/fade.
      setState(() {
        _previousMode = null;
        _mode = next;
      });
      return;
    }
    setState(() {
      _previousMode = _mode;
      _mode = next;
    });
    // Both blocks animate together — each has its own controller so the
    // header's timing can be tuned independently of the content, but they
    // always start on the same frame.
    _modeController.forward(from: 0);
    _headerController.forward(from: 0);
  }

  // ─── Navigation (create mode) ─────────────────────────────────────────
  void _openCustomer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerRegisterScreen()),
    );
  }

  void _openSeller() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SellerApplicationFlow()),
    );
  }

  // ─── Sign-in logic (carried over from the legacy LoginScreen) ─────────
  Future<void> _checkBiometricState() async {
    final available = await _bioService.isBiometricAvailable();
    final enabled = await _bioService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  Future<void> _submit() async {
    if (!mounted) return;
    if (!_signinFormKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final success = await auth.login(email, password);

      if (success && mounted) {
        // Offer biometric enrollment after successful login. No navigation
        // here — AuthGate reacts to the auth state change and swaps the root.
        _offerBiometricEnrollment(email, password);
      } else if (!success && mounted) {
        // Check if a lockout overlay should be shown
        final lockout = auth.pendingLockout;
        if (lockout != null && mounted) {
          auth.clearPendingLockout();
          final lockoutEmail = lockout['email'] as String;
          LockoutOverlay.show(
            context,
            email: lockoutEmail,
            remainingMinutes: lockout['remainingMinutes'] as int,
            device: lockout['device'] as String?,
            ipAddress: lockout['ipAddress'] as String?,
            onResetPassword: (email) async {
              final success = await auth.resetPassword(email);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Check your email for a reset link.'),
                    backgroundColor: AppConstants.success,
                  ),
                );
              }
              return success;
            },
            onReportIntrusion: (email) async {
              return await auth.reportIntrusion(email);
            },
          );
        } else {
          _showError(auth.errorMessage ?? 'Authentication failed.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError(friendlyAuthErrorMessage(e));
    }
  }

  /// Sends a password-reset email via Supabase for the address in the
  /// email field. Shows a confirmation SnackBar or an error toast.
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email address first.');
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.resetPassword(email);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Password reset link sent to $email'
              : auth.errorMessage ?? 'Unable to send reset email.',
        ),
        backgroundColor: success ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  void _showError(String message) {
    // Root-overlay toast — floats above the video/content and the keyboard.
    AppErrorToast.show(context, message: message);
  }

  /// Offer biometric enrollment after a successful email/password login.
  Future<void> _offerBiometricEnrollment(String email, String password) async {
    // Don't ask if already enabled, not available, or previously declined.
    if (_biometricEnabled) return;
    if (!_biometricAvailable) return;
    final declined = await _bioService.hasDeclinedBiometric();
    if (declined) return;
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
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
                color: AppConstants.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.fingerprint,
                color: AppConstants.accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Enable Biometric Login?',
              style: AppConstants.headlineStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Use fingerprint or face recognition to sign in faster next time.',
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
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _bioService.saveCredentials(email, password);
                  if (mounted) {
                    setState(() => _biometricEnabled = true);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: Text(
                  'Enable',
                  style: AppConstants.headlineStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.surfaceLight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _bioService.declineBiometric();
              },
              child: Text(
                'No Thanks',
                style: AppConstants.bodyStyle(
                  fontWeight: FontWeight.w600,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Authenticate using saved biometric credentials.
  Future<void> _loginWithBiometrics() async {
    setState(() => _biometricLoading = true);
    try {
      final authenticated = await _bioService.authenticate();
      if (!authenticated) {
        if (mounted) {
          _showError('Biometric authentication cancelled.');
        }
        return;
      }

      final creds = await _bioService.getSavedCredentials();
      if (creds == null) {
        if (mounted) {
          _showError('No saved credentials found. Please sign in manually.');
        }
        return;
      }

      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final success = await auth.login(creds['email']!, creds['password']!);
      if (!success && mounted) {
        _showError(auth.errorMessage ?? 'Authentication failed.');
      }
    } catch (e) {
      if (mounted) {
        _showError('Biometric login failed. Please sign in manually.');
      }
    } finally {
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceDark,
      // ⚠️ DEV MODE — REMOVE BEFORE RELEASE: the swipe detector that unlocks
      // the UI-only skip mode (see docs/AI/DEV_MODE_ARCHITECTURE.md).
      body: DevModeSwipeDetector(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const VideoHeroBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AuthSpacing.s24,
                    AuthSpacing.s8,
                    AuthSpacing.s24,
                    0,
                  ),
                  child: _buildHeader(),
                ),
                // Middle (video) + bottom-anchored content block. When the
                // content fits it is pinned to the bottom; when it overflows
                // (short device, large text, keyboard up) the scroll view
                // takes over — nothing ever clips.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AuthSpacing.s24,
                          AuthSpacing.s12,
                          AuthSpacing.s24,
                          AuthSpacing.s16,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight -
                                AuthSpacing.s12 -
                                AuthSpacing.s16,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [_buildContent(auth)],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  /// Pinned top block: static CUFMAI eyebrow + the animated title/subtitle
  /// swap. Header slides OPPOSITE the content block on every mode switch.
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CUFMAI',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
                color: AppConstants.surfaceLight,
              ),
            ),
            const Spacer(),
            // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
            const DevModeBadge(),
          ],
        ),
        const SizedBox(height: AuthSpacing.s8),
        // Header block runs on its own controller (started in sync with the
        // content controller in _switchMode) so the title swap can be tuned
        // independently — the two blocks never fight each other's timing.
        _SlideSwap(
          animation: _headerController,
          exitTo: _isForward ? -1.0 : 1.0,
          alignment: Alignment.topCenter,
          incoming: _titleBlockFor(_mode),
          outgoing:
              _previousMode == null ? null : _titleBlockFor(_previousMode!),
        ),
      ],
    );
  }

  Widget _titleBlockFor(AuthEntryMode mode) {
    final signin = mode == AuthEntryMode.signin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          signin ? 'Welcome back' : 'Create your account',
          style: AppConstants.headlineStyle(
            fontSize: 28,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AuthSpacing.s8),
        // Subtitle in a fixed two-line slot: the two subtitles differ in
        // line count, and a changing header height made the swap animate in
        // two phases (slide, then a resize) — the "stops then proceeds"
        // feel. A constant height means the title block never resizes, so
        // the slide is purely horizontal with no vertical drift.
        SizedBox(
          height: 2 * 14 * 1.45 * MediaQuery.textScalerOf(context).scale(1),
          child: Text(
            signin
                ? 'Sign in to your CUFMAI account.'
                : 'Join the home of Carcar footwear craftsmanship.',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  /// The mode content block, wrapped in the swap that slides it opposite the
  /// header.
  Widget _buildContent(AuthProvider auth) {
    return _SlideSwap(
      animation: _modeController,
      // Content offset is the header's with the sign flipped.
      exitTo: _isForward ? 1.0 : -1.0,
      // Bottom-anchor the two content blocks: they have very different
      // heights (the sign-in form is much taller than the create panel), so
      // a top-aligned Stack would make the buttons jump up/down as the
      // stack height snaps to the taller child and back. Bottom alignment
      // keeps the buttons and links pinned to the same spot — only the
      // empty video space above grows/shrinks.
      alignment: Alignment.bottomCenter,
      incoming: _contentFor(_mode, auth),
      outgoing:
          _previousMode == null ? null : _contentFor(_previousMode!, auth),
    );
  }

  Widget _contentFor(AuthEntryMode mode, AuthProvider auth) {
    if (mode == AuthEntryMode.create) {
      return _buildCreateContent();
    }
    return _buildSigninContent(auth);
  }

  /// Default mode: the primary customer CTA, the secondary seller link, and
  /// the sign-in mode-switch footer.
  Widget _buildCreateContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PressScale(
          child: SolePrimaryAuthButton(
            label: 'Shop as customer?',
            borderRadius: 14,
            boxShadow: _heroButtonShadow,
            onPressed: _openCustomer,
          ),
        ),
        const SizedBox(height: AuthSpacing.s16),
        _CenteredLinkRow(
          prefix: 'A shoemaker or artisan? ',
          link: 'Apply to sell',
          fontSize: 14,
          underlineLink: true,
          semanticsLabel: 'A shoemaker or artisan? Apply to sell on SoleVision',
          onTap: _openSeller,
        ),
        const SizedBox(height: AuthSpacing.s16),
        _hairline(),
        const SizedBox(height: AuthSpacing.s16),
        // Switch to sign-in mode — in-place state change, NOT navigation.
        _CenteredLinkRow(
          prefix: 'Already have an account? ',
          link: 'Sign in',
          underlineLink: false,
          semanticsLabel: 'Already have an account? Sign in',
          onTap: () => _switchMode(AuthEntryMode.signin),
        ),
      ],
    );
  }

  /// Sign-in mode: the dark-styled form, forgot-password stub, Log In CTA,
  /// biometric option (kept from the legacy LoginScreen — never silently
  /// dropped), and the create-account mode-switch footer.
  Widget _buildSigninContent(AuthProvider auth) {
    return Form(
      key: _signinFormKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DarkAuthTextField(
              labelText: 'Email Address',
              hintText: 'e.g. maria@gmail.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.email_outlined,
              autofillHints: const [AutofillHints.email],
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Please enter your email';
                }
                return null;
              },
            ),
            const SizedBox(height: AuthSpacing.s16),
            DarkAuthTextField(
              labelText: 'Password',
              hintText: '••••••••',
              controller: _passwordController,
              obscureText: _obscurePassword,
              prefixIcon: Icons.lock_outline,
              autofillHints: const [AutofillHints.password],
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppConstants.surfaceLight.withValues(alpha: 0.85),
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (val) {
                if (val == null || val.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: AuthSpacing.s12),
            // Forgot password — sends a real Supabase reset link to the
            // email typed in the field above. If the field is empty the
            // user is prompted to fill it first.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot password?',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.surfaceLight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AuthSpacing.s16),
            _PressScale(
              child: SolePrimaryAuthButton(
                label: 'Log In',
                isLoading: auth.isLoading,
                onPressed: auth.isLoading ? null : _submit,
                borderRadius: 14,
                boxShadow: _heroButtonShadow,
              ),
            ),
            // Biometric login — doubly gated (device support AND prior
            // enrollment), so most fresh installs never see this section.
            if (_biometricAvailable && _biometricEnabled) ...[
              const SizedBox(height: AuthSpacing.s16),
              _buildBiometricButton(),
            ],
            const SizedBox(height: AuthSpacing.s16),
            _hairline(),
            const SizedBox(height: AuthSpacing.s16),
            // Switch back to create mode — in-place state change.
            _CenteredLinkRow(
              prefix: 'New here? ',
              link: 'Create an account',
              underlineLink: false,
              semanticsLabel: 'New here? Create an account',
              onTap: () => _switchMode(AuthEntryMode.create),
            ),
          ],
        ),
      ),
    );
  }

  /// Biometric login section — an OR divider + a white pill button, restyled
  /// for the dark video background (light dividers, black-based shadow).
  Widget _buildBiometricButton() {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 24),
            Expanded(
              child: Divider(color: Colors.white.withValues(alpha: 0.22)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Text(
                'OR',
                style: AppConstants.monoStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
            Expanded(
              child: Divider(color: Colors.white.withValues(alpha: 0.22)),
            ),
            const SizedBox(width: 24),
          ],
        ),
        const SizedBox(height: AuthSpacing.s12),
        Center(
          child: GestureDetector(
            onTap: _biometricLoading ? null : _loginWithBiometrics,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppConstants.buttonRadius,
                border: Border.all(
                  color: AppConstants.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_biometricLoading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppConstants.primary,
                      ),
                    )
                  else
                    const Icon(
                      Icons.fingerprint,
                      color: AppConstants.primary,
                      size: 24,
                    ),
                  const SizedBox(width: 10),
                  Text(
                    'Sign in with Biometrics',
                    style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hairline() {
    return Container(height: 1, color: Colors.white.withValues(alpha: 0.22));
  }

  /// Drop shadow shared by the two hero CTAs — real legibility for the label
  /// over moving footage, not just decoration.
  static final List<BoxShadow> _heroButtonShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.30),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}

/// The opposite-direction slide swap.
///
/// Shared curve for both directions of the swap — symmetric so the outgoing
/// and incoming children mirror each other exactly at every frame (a
/// mismatched easeIn/easeOut made one child visually lag the other).
const Curve _swapCurve = Curves.easeInOutCubic;

/// One shared animation drives both blocks; [exitTo] is the horizontal
/// direction (as a unit vector sign) the OUTGOING child slides toward, and
/// the incoming child enters from the opposite side (`-exitTo`). The content
/// block's [exitTo] is simply the header's negated — the two blocks always
/// move in opposite directions in the same transition.
///
/// While idle (`outgoing == null`) the incoming child renders bare — no
/// animation wrappers, so the initial frame is fully visible.
class _SlideSwap extends StatelessWidget {
  final Animation<double> animation;

  /// +1 or -1: the direction the outgoing child slides out to.
  final double exitTo;

  /// How the two children (which may have different heights) are anchored
  /// inside the Stack. Bottom-anchored for the mode content block (buttons
  /// stay pinned while the panel height changes), top-anchored for the
  /// header title block.
  final Alignment alignment;
  final Widget incoming;
  final Widget? outgoing;

  const _SlideSwap({
    required this.animation,
    required this.exitTo,
    required this.incoming,
    this.alignment = Alignment.topCenter,
    this.outgoing,
  });

  @override
  Widget build(BuildContext context) {
    final outgoing = this.outgoing;
    if (outgoing == null) return incoming;

    return Stack(
      alignment: alignment,
      children: [
        // Outgoing: settle → slide away in the exit direction, fading out.
        SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: Offset(exitTo, 0),
          ).animate(
            // One shared curve for both directions so the two children
            // mirror each other exactly — a mismatched easeIn/easeOut made
            // one child lag the other mid-transition.
            CurvedAnimation(parent: animation, curve: _swapCurve),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(animation),
            child: ExcludeSemantics(excluding: true, child: outgoing),
          ),
        ),
        // Incoming: slide in from the opposite side, fading in.
        SlideTransition(
          position: Tween<Offset>(
            begin: Offset(-exitTo, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: _swapCurve),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(animation),
            child: incoming,
          ),
        ),
      ],
    );
  }
}

/// A centered link-style row (no border, no fill) with a ≥44px tap target,
/// `Semantics` button label, hover tint on desktop, and the auth module's
/// press language (0.99 scale + light haptic). Used for the seller link, the
/// sign-in switch, and the create-account switch.
class _CenteredLinkRow extends StatefulWidget {
  final String prefix;
  final String link;

  /// Text size for the row (the seller link is one step larger than the
  /// mode-switch footers so it keeps a hint of primary-action weight).
  final double fontSize;
  final bool underlineLink;
  final VoidCallback onTap;
  final String semanticsLabel;

  const _CenteredLinkRow({
    required this.prefix,
    required this.link,
    this.fontSize = 13,
    required this.underlineLink,
    required this.onTap,
    required this.semanticsLabel,
  });

  @override
  State<_CenteredLinkRow> createState() => _CenteredLinkRowState();
}

class _CenteredLinkRowState extends State<_CenteredLinkRow> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {
              HapticFeedback.lightImpact();
              setState(() => _pressed = true);
            },
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: AuthSpacing.s8,
                vertical: AuthSpacing.s8,
              ),
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
              child: Text.rich(
                TextSpan(
                  style: AppConstants.bodyStyle(
                    fontSize: widget.fontSize,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  children: [
                    TextSpan(text: widget.prefix),
                    TextSpan(
                      text: widget.link,
                      style: AppConstants.bodyStyle(
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.surfaceLight,
                      ).copyWith(
                        decoration: widget.underlineLink
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationColor: widget.underlineLink
                            ? AppConstants.surfaceLight.withValues(alpha: 0.8)
                            : null,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle press feedback consistent with the auth module's motion language
/// (scale + light haptic on press). Uses raw pointer events (not a tap
/// recognizer) so it never competes with the wrapped button's own `onPressed`
/// in the gesture arena — the scale is purely cosmetic feedback.
class _PressScale extends StatefulWidget {
  final Widget child;

  const _PressScale({required this.child});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
