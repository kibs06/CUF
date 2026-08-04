import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_text_field.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/sole_switch.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _applyAsSeller = false;
  final bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      final auth = Provider.of<AuthProvider>(context, listen: false);
      try {
        final success = await auth.signUp(
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          applyAsSeller: _applyAsSeller,
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _applyAsSeller
                    ? 'Account created! Application sent to Admins.'
                    : 'Welcome to CUFMAI!',
              ),
              backgroundColor: AppConstants.success,
            ),
          );
          Navigator.of(context).pop();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(auth.errorMessage ?? 'Registration failed.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppConstants.error,
          ),
        );
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.04),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 12.0,
              ),
              child: Column(
                children: [
                  Text(
                    'Create Account',
                    style: AppConstants.headlineStyle(fontSize: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join the home of Carcar footwear craftsmanship',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Register Card
                  SoleCard(
                    color: Colors.white,
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Full Name
                          SoleTextField(
                            labelText: 'Full Name',
                            hintText: 'e.g. Maria Cobarrubias',
                            controller: _nameController,
                            prefixIcon: Icons.person_outline,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your full name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Email
                          SoleTextField(
                            labelText: 'Email Address',
                            hintText: 'e.g. maria@gmail.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icons.email_outlined,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!val.contains('@')) {
                                return 'Please enter a valid email';
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
                            validator: (val) {
                              if (val == null || val.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Confirm Password
                          SoleTextField(
                            labelText: 'Confirm Password',
                            hintText: '••••••••',
                            controller: _confirmPasswordController,
                            obscureText: _obscurePassword,
                            prefixIcon: Icons.lock_clock_outlined,
                            validator: (val) {
                              if (val != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Styled toggle tile "Apply as a seller"
                          Container(
                            decoration: BoxDecoration(
                              color: AppConstants.surfaceLight.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppConstants.primary.withValues(
                                  alpha: 0.12,
                                ),
                                width: 1,
                              ),
                            ),
                            child: SwitchListTile(
                              activeThumbColor: SoleSwitch.onColor,
                              title: Row(
                                children: [
                                  const Icon(
                                    Icons
                                        .sell_outlined, // Leather tag/sell icon
                                    color: AppConstants.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Apply as a seller',
                                    style: AppConstants.bodyStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              value: _applyAsSeller,
                              onChanged: (bool value) {
                                setState(() {
                                  _applyAsSeller = value;
                                });
                              },
                            ),
                          ),

                          if (_applyAsSeller) ...[
                            const SizedBox(height: 12),
                            // Amber info chip
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.amber.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Color(0xFFC47D00),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your application will be reviewed by an admin before approval.',
                                      style: AppConstants.bodyStyle(
                                        fontSize: 12,
                                        color: const Color(0xFFC47D00),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Register Button
                          SolePrimaryButton(
                            label: 'Register',
                            isLoading: _isSubmitting || auth.isLoading,
                            onPressed: _isSubmitting ? null : _submit,
                          ),
                        ],
                      ),
                    ),
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
}
