import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_text_field.dart';
import '../../widgets/sole_primary_button.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Biometric state
  final BiometricService _bioService = BiometricService.instance;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricLoading = false;

  // Decorative shoe sole SVG
  static const String _soleIllustrationSvg = '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M50,12 C62,12 68,26 64,40 C60,54 66,74 62,84 C58,89 42,89 38,84 C34,74 40,54 36,40 C32,26 38,12 50,12 Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="4 4"/>
</svg>
''';

  @override
  void initState() {
    super.initState();
    _checkBiometricState();
  }

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final success = await auth.login(email, password);

      if (success && mounted) {
        // Offer biometric enrollment after successful login
        _offerBiometricEnrollment(email, password);
      } else if (!success && mounted) {
        _showError(auth.errorMessage ?? 'Authentication failed.');
      }
    } catch (e) {
      if (!mounted) return;
      _showError(
        kDebugMode
            ? 'Debug: ${e.toString()}'
            : 'Something went wrong. Please try again.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.error),
    );
  }

  /// Offer biometric enrollment after a successful email/password login.
  Future<void> _offerBiometricEnrollment(String email, String password) async {
    // Don't ask if already enabled, not available, or previously declined
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          // Background noise texture
          AppConstants.noiseOverlay(opacity: 0.04),

          // Scrollable login content
          SingleChildScrollView(
            child: AutofillGroup(
              child: Column(
                children: [
                  // Top 40% Hero: Warm Gradient with shoe sole illustration
                  Container(
                    width: double.infinity,
                    height: size.height * 0.38,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppConstants.primary, AppConstants.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Decorative SVG sole
                        Positioned(
                          right: -20,
                          top: 40,
                          width: 200,
                          height: 200,
                          child: Opacity(
                            opacity: 0.12,
                            child: SvgPicture.string(
                              _soleIllustrationSvg,
                              colorFilter: const ColorFilter.mode(
                                AppConstants.surfaceLight,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        // Wordmark / Header text
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 24.0,
                            bottom: 40.0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CUFMAI',
                                style: AppConstants.headlineStyle(
                                  fontSize: 36,
                                  color: AppConstants.surfaceLight,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Carcar United Footwear Manufacturers Association, Inc.',
                                style: AppConstants.bodyStyle(
                                  fontSize: 13,
                                  color: AppConstants.surfaceLight.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Login card (white, lifted with shadow)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: SoleCard(
                      color: Colors.white,
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sign In',
                              style: AppConstants.headlineStyle(fontSize: 22),
                            ),
                            const SizedBox(height: 18),

                            // Email
                            SoleTextField(
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
                            const SizedBox(height: 16),

                            // Password
                            SoleTextField(
                              labelText: 'Password',
                              hintText: '••••••••',
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              prefixIcon: Icons.lock_outline,
                              autofillHints: const [AutofillHints.password],
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: AppConstants.primary,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              validator: (val) {
                                if (val == null || val.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 12),

                            // Forgot Password
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Password reset link sent (simulated).',
                                      ),
                                      backgroundColor: AppConstants.success,
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Forgot password?',
                                  style: AppConstants.bodyStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primary,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Log In Button
                            SolePrimaryButton(
                              label: 'Log In',
                              isLoading: auth.isLoading,
                              onPressed: auth.isLoading ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ─── Biometric Login Button ──────────────────────
                  if (_biometricAvailable && _biometricEnabled) ...[
                    const SizedBox(height: 16),
                    _buildBiometricButton(),
                  ],

                  const SizedBox(height: 16),

                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: AppConstants.bodyStyle(
                          color:
                              AppConstants.secondary.withValues(alpha: 0.7),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Register',
                          style: AppConstants.bodyStyle(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Biometric login button — shown only when biometrics are available
  /// and the user has previously enrolled their credentials.
  Widget _buildBiometricButton() {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 24),
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Text(
                'OR',
                style: AppConstants.monoStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.4),
                ),
              ),
            ),
            const Expanded(child: Divider()),
            const SizedBox(width: 24),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _biometricLoading ? null : _loginWithBiometrics,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppConstants.buttonRadius,
              border: Border.all(
                color: AppConstants.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: AppConstants.warmShadow,
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
      ],
    );
  }
}
