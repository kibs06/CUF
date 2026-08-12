import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/sole_primary_button.dart';

/// Slimmed-down customer registration — a strict subset of the legacy
/// single form (name, email, optional phone, password, confirm, terms),
/// with inline validation icons, a live password-strength meter and a
/// duplicate-email check surfaced at this step instead of after uploads.
class CustomerRegisterScreen extends StatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _termsAccepted = false;
  bool _isSubmitting = false;
  String? _emailExistsError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      _showMessage('Please accept the Terms & Privacy Policy to continue.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _emailExistsError = null;
    });

    final auth = context.read<AuthProvider>();
    try {
      // Duplicate email check FIRST — surface it inline before the account
      // is created (same behavior as before, but clearer placement).
      final exists =
          await AuthService.instance.emailExists(_emailController.text.trim());
      if (!mounted) return;
      if (exists) {
        setState(() {
          _isSubmitting = false;
          _emailExistsError = 'This email is already registered. Try signing in.';
        });
        // Re-validate so the email field shows the inline error immediately.
        _formKey.currentState?.validate();
        return;
      }

      final success = await auth.signUpCustomer(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );

      if (!mounted) return;
      if (success) {
        // AuthGate swaps the root for CustomerShell — just unwind the
        // pushed route so the new shell is what's visible. Capture the
        // messenger BEFORE popping: the screen's context is disposed by
        // popUntil, so reading it afterwards is unsafe.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Welcome to CUFMAI!'),
            backgroundColor: AppConstants.success,
          ),
        );
      } else {
        setState(() => _isSubmitting = false);
        _showMessage(auth.errorMessage ?? 'Registration failed.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return SignupScaffold(
      eyebrow: 'CUSTOMER',
      title: 'Create account',
      subtitle:
          'Join SoleVision to discover handcrafted footwear from Carcar’s artisans.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthTextField(
              label: 'Full Name',
              hint: 'e.g. Maria Cobarrubias',
              controller: _nameController,
              prefixIcon: Icons.person_outline,
              autofillHints: const [AutofillHints.name],
              validator: (val) => (val == null || val.trim().isEmpty)
                  ? 'Please enter your full name'
                  : null,
            ),
            const SizedBox(height: AuthSpacing.s16),
            AuthTextField(
              label: 'Email Address',
              hint: 'e.g. maria@gmail.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.email_outlined,
              autofillHints: const [AutofillHints.email],
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!val.contains('@') || !val.contains('.')) {
                  return 'Please enter a valid email';
                }
                if (_emailExistsError != null) return _emailExistsError;
                return null;
              },
            ),
            const SizedBox(height: AuthSpacing.s16),
            AuthTextField(
              label: 'Phone Number (optional)',
              hint: 'e.g. 09XX-XXX-XXXX',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const SizedBox(height: AuthSpacing.s16),
            AuthTextField(
              label: 'Password',
              hint: 'At least 6 characters',
              controller: _passwordController,
              obscureText: true,
              passwordField: true,
              prefixIcon: Icons.lock_outline,
              autofillHints: const [AutofillHints.newPassword],
              validator: (val) => (val == null || val.length < 6)
                  ? 'Password must be at least 6 characters'
                  : null,
            ),
            const SizedBox(height: AuthSpacing.s8),
            PasswordStrengthMeter(password: _passwordController.text),
            AuthTextField(
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              controller: _confirmController,
              obscureText: true,
              passwordField: true,
              prefixIcon: Icons.lock_clock_outlined,
              validator: (val) =>
                  (val != _passwordController.text) ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: AuthSpacing.s16),
            _TermsTile(
              value: _termsAccepted,
              onChanged: (v) => setState(() => _termsAccepted = v),
            ),
            const SizedBox(height: AuthSpacing.s24),
            SolePrimaryButton(
              label: 'Create account',
              isLoading: _isSubmitting || auth.isLoading,
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox row for the Terms & Privacy consent — used by both customer
/// and seller registration.
class _TermsTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TermsTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AuthSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? AppConstants.primary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value
                      ? AppConstants.primary
                      : AppConstants.borderGray,
                  width: 1.5,
                ),
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: AuthSpacing.s12),
            Expanded(
              child: Text(
                'I agree to the Terms & Privacy Policy of SoleVision.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
