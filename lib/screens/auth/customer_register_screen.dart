import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/auth_error_messages.dart';
import '../../utils/customer_profile_fields.dart';
import '../../utils/dev_mode.dart';
import '../../widgets/app_error_toast.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../screens/shared/terms_privacy_screen.dart';
import '../../widgets/auth/terms_policy_tile.dart';
import '../../widgets/sole_primary_button.dart';
import 'foot_profile_onboarding_screen.dart';

/// Customer registration — name, email, phone (optional), a required
/// birthday (13+, with a short why-we-ask line), an optional gender select
/// (with a self-describe free-text escape hatch), password, confirm and
/// terms. Inline validation icons, a live password-strength meter and a
/// duplicate-email check are surfaced at this step.
///
/// On success the account is created (independent of anything that happens
/// next) and the user is handed off to [FootProfileOnboardingScreen] — a
/// separate, always-skippable step that introduces the AR foot scan.
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
  final _birthdayController = TextEditingController();
  final _selfDescribeController = TextEditingController();

  DateTime? _birthday;
  String? _gender;
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
    _birthdayController.dispose();
    _selfDescribeController.dispose();
    super.dispose();
  }

  /// Opens the date picker for the required birthday field and stamps the
  /// formatted value into the read-only field.
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Sensible default initial date: a 25-year-old today.
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your birthday',
      // The business rule (13+) is enforced by [validateBirthday] on
      // submit; the picker itself stays permissive so the error message
      // (not a hard block) explains the policy.
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthday = picked;
      _birthdayController.text = _formatBirthday(picked);
    });
  }

  String _formatBirthday(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
    // UI-only skip: bypass validation/terms and jump straight to the next
    // screen in the flow WITHOUT creating an account (nothing hits Supabase).
    if (DevMode.instance.isEnabled) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FootProfileOnboardingScreen()),
      );
      return;
    }

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
          // Same wording the auth-error mapper uses for user_already_exists,
          // so the inline field check and the submit-failure toast agree.
          _emailExistsError = authErrorEmailExists;
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
        birthday: _birthday,
        gender: resolveGenderValue(_gender, _selfDescribeController.text),
      );

      if (!mounted) return;
      if (success) {
        // Hand the user to the foot-profile onboarding step. It replaces
        // THIS route (the account already exists — the step is optional
        // and never blocks access), and when it finishes it pops to the
        // root, where AuthGate has already swapped the shell to
        // CustomerShell.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const FootProfileOnboardingScreen(),
          ),
        );
      } else {
        setState(() => _isSubmitting = false);
        _showMessage(auth.errorMessage ?? 'Registration failed.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage(friendlyAuthErrorMessage(e));
    }
  }

  void _showMessage(String message) {
    AppErrorToast.show(context, message: message);
  }

  /// Required birthday field (read-only text field + date picker) with a
  /// short why-we-ask line — the copy meaningfully affects completion rate
  /// for a field many users are wary of providing.
  Widget _buildBirthdayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTextField(
          label: 'Birthday',
          hint: 'Tap to select your date of birth',
          controller: _birthdayController,
          readOnly: true,
          onTap: _pickBirthday,
          prefixIcon: Icons.cake_outlined,
          validator: (_) => validateBirthday(_birthday),
        ),
        const SizedBox(height: AuthSpacing.s8),
        Row(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 13,
              color: AppConstants.accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'We\u2019ll surprise you with a birthday treat. \u2014 we only use this to make sure you\u2019re old enough to shop with us.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Optional gender select: four chips, the last ('Self-describe')
  /// revealing a free-text field. No selection is required to submit.
  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Gender',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(optional)',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: AuthSpacing.s8),
        Wrap(
          spacing: AuthSpacing.s8,
          runSpacing: AuthSpacing.s8,
          children: AppConstants.customerGenderOptions.map((option) {
            final selected = _gender == option;
            return ChoiceChip(
              label: Text(
                option,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? AppConstants.surfaceLight
                      : AppConstants.secondary,
                ),
              ),
              selected: selected,
              showCheckmark: false,
              onSelected: (sel) => setState(() => _gender = sel ? option : null),
              selectedColor: AppConstants.primary,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected
                    ? Colors.transparent
                    : AppConstants.borderGray.withValues(alpha: 0.5),
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
        // Self-describe free text — validated only when that option is
        // active (validateGenderSelfDescribe), so it never blocks the
        // other three choices.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _gender == 'Self-describe'
              ? Padding(
                  padding: const EdgeInsets.only(top: AuthSpacing.s12),
                  child: AuthTextField(
                    label: 'How would you describe yourself?',
                    hint: 'e.g. Agender, Pangender, genderfluid\u2026',
                    controller: _selfDescribeController,
                    prefixIcon: Icons.edit_outlined,
                    validator: (_) => validateGenderSelfDescribe(
                      _gender,
                      _selfDescribeController.text,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
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
            _buildBirthdayField(),
            const SizedBox(height: AuthSpacing.s16),
            _buildGenderSelector(),
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
            TermsPolicyTile(
              value: _termsAccepted,
              onChanged: (v) => setState(() => _termsAccepted = v),
              policy: CUFMAITermsPolicy.customer,
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
