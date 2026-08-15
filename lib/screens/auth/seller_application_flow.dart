import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_application_controller.dart';
import '../../screens/shared/terms_privacy_screen.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/document_upload_tile.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';
import '../../widgets/auth/step_progress_indicator.dart';
import '../../widgets/auth/terms_policy_tile.dart';

/// Multi-step seller application (the spec's "SellerApplicationFlow"):
///
///   Step 1 — Account      full name, email, phone, password, terms
///   Step 2 — Identity     government ID photo + liveness selfie
///   Step 3 — Community    CUFMAI member ID (members) OR barangay proof
///   Step 4 — Storefront   store name/description + payout details
///
/// The Supabase Auth user is created ONLY on final submit (see
/// SellerApplicationController). All form + upload state lives in the
/// controller, so navigating back/forward (or leaving and re-entering the
/// flow) never loses entered data.
class SellerApplicationFlow extends StatefulWidget {
  final Map<String, dynamic>? prefillProfile;

  const SellerApplicationFlow({super.key, this.prefillProfile});

  @override
  State<SellerApplicationFlow> createState() => _SellerApplicationFlowState();
}

class _SellerApplicationFlowState extends State<SellerApplicationFlow> {
  late final SellerApplicationController _controller;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _memberIdController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _storeDescController = TextEditingController();
  final _payoutDetailsController = TextEditingController();

  // One form key per step — AnimatedSwitcher briefly keeps the outgoing
  // step mounted, so sharing a key between steps would crash with
  // "Duplicate GlobalKey".
  final _accountFormKey = GlobalKey<FormState>();
  final _storefrontFormKey = GlobalKey<FormState>();
  bool _checkingEmail = false;

  @override
  void initState() {
    super.initState();
    _controller = SellerApplicationController(
      prefillProfile: widget.prefillProfile,
    );
    _nameController.text = _controller.fullName;
    _emailController.text = _controller.email;
    _phoneController.text = _controller.phone;
    _memberIdController.text = _controller.cufmaiMemberId;
    _storeNameController.text = _controller.storeName;
    _payoutDetailsController.text = _controller.payoutDetails;
    // The step widgets read controller state directly in their build
    // methods (step index, termsAccepted, document statuses…), so the flow
    // must re-run its own build whenever the controller changes — otherwise
    // a value like termsAccepted is stored but never repainted (e.g. the
    // terms checkbox staying unchecked after the read-and-agree flow).
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _memberIdController.dispose();
    _storeNameController.dispose();
    _storeDescController.dispose();
    _payoutDetailsController.dispose();
    super.dispose();
  }

  // ── Step 1 actions ────────────────────────────────────────────
  Future<void> _continueFromAccount() async {
    if (_checkingEmail) return;
    if (!_accountFormKey.currentState!.validate()) return;
    if (!_controller.termsAccepted) {
      _showError('Please accept the Terms & Privacy Policy to continue.');
      return;
    }

    setState(() => _checkingEmail = true);
    try {
      // Duplicate-email check at Step 1 — before any document work.
      // Skipped when re-applying with the same (signed-in) email.
      final ownEmail = (context.read<AuthProvider>().currentUser?['email'] ?? '')
          .toLowerCase();
      final exists = await AuthService.instance
          .emailExists(_controller.email);
      if (!mounted) return;
      if (exists && _controller.email.toLowerCase() != ownEmail) {
        _controller.emailExistsError =
            'This email is already registered. Try signing in instead.';
        _accountFormKey.currentState!.validate();
        return;
      }
      _controller.nextStep();
    } finally {
      if (mounted) setState(() => _checkingEmail = false);
    }
  }

  Future<void> _pickDocument(SellerDocState doc) async {
    final source = await showVerificationImageSourceSheet(context);
    if (source == null) return;
    await _controller.pickDocument(doc, source);
  }

  Future<void> _submit() async {
    if (!_storefrontFormKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await _controller.submit(
      signUpSeller: (data) => auth.signUpSeller(data: data),
    );
    if (!mounted) return;
    if (ok) {
      // Capture the messenger before popping — the flow's context is
      // disposed by popUntil (flow + role-choice both unwind), so reading
      // it afterwards is unsafe.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Application submitted! An admin will review it.'),
          backgroundColor: AppConstants.success,
        ),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.error),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final submitting = ctrl.isSubmitting;

    return ChangeNotifierProvider.value(
      value: ctrl,
      child: PopScope(
        canPop: !submitting,
        child: SignupScaffold(
          eyebrow: 'SELLER APPLICATION',
          title: _titleFor(ctrl.step),
          subtitle: _subtitleFor(ctrl.step),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepProgressIndicator(
                currentStep: ctrl.step,
                totalSteps: SellerApplicationController.stepCount,
                labels: const ['Account', 'Identity', 'Community', 'Storefront'],
              ),
              const SizedBox(height: AuthSpacing.s24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: submitting || ctrl.showSubmission
                    ? _SubmissionView(key: const ValueKey('submission'))
                    : KeyedSubtree(
                        key: ValueKey('step-${ctrl.step}'),
                        child: _buildStep(ctrl),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(int step) {
    switch (step) {
      case 0:
        return 'Create your seller account';
      case 1:
        return 'Verify your identity';
      case 2:
        return 'Prove your community link';
      default:
        return 'Set up your storefront';
    }
  }

  String _subtitleFor(int step) {
    switch (step) {
      case 0:
        return 'Step 1 of 4 — your login details for SoleVision.';
      case 1:
        return 'Step 2 of 4 — a government ID and a selfie help admins confirm it’s really you.';
      case 2:
        return 'Step 3 of 4 — CUFMAI membership, or a barangay proof if you’re not a member.';
      default:
        return 'Step 4 of 4 — how customers will find you, and where your earnings go.';
    }
  }

  Widget _buildStep(SellerApplicationController ctrl) {
    switch (ctrl.step) {
      case 0:
        return _AccountStep(
          formKey: _accountFormKey,
          ctrl: ctrl,
          name: _nameController,
          email: _emailController,
          phone: _phoneController,
          password: _passwordController,
          confirm: _confirmController,
          checkingEmail: _checkingEmail,
          onContinue: _continueFromAccount,
        );
      case 1:
        return _IdentityStep(ctrl: ctrl, onPick: _pickDocument);
      case 2:
        return _CommunityStep(
          ctrl: ctrl,
          memberId: _memberIdController,
          onPick: _pickDocument,
        );
      default:
        return _StorefrontStep(
          formKey: _storefrontFormKey,
          ctrl: ctrl,
          storeName: _storeNameController,
          storeDescription: _storeDescController,
          payoutDetails: _payoutDetailsController,
          onSubmit: _submit,
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// STEP 1 — ACCOUNT
// ══════════════════════════════════════════════════════════════════
class _AccountStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final SellerApplicationController ctrl;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool checkingEmail;
  final VoidCallback onContinue;

  const _AccountStep({
    required this.formKey,
    required this.ctrl,
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.confirm,
    required this.checkingEmail,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ctrl.isReapply) ...[
            _InfoBanner(
              icon: Icons.refresh_rounded,
              text:
                  'You’re re-applying with your existing SoleVision account — no new password needed.',
            ),
            const SizedBox(height: AuthSpacing.s16),
          ],
          AuthTextField(
            label: 'Full Name',
            hint: 'e.g. Josefa Reyes',
            controller: name,
            prefixIcon: Icons.person_outline,
            autofillHints: const [AutofillHints.name],
            onChanged: (v) => ctrl.fullName = v,
            validator: (val) => (val == null || val.trim().isEmpty)
                ? 'Please enter your full name'
                : null,
          ),
          const SizedBox(height: AuthSpacing.s16),
          AuthTextField(
            label: 'Email Address',
            hint: 'e.g. josefa@gmail.com',
            controller: email,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
            autofillHints: const [AutofillHints.email],
            onChanged: (v) {
              ctrl.email = v;
              if (ctrl.emailExistsError != null) {
                ctrl.emailExistsError = null;
              }
            },
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!val.contains('@') || !val.contains('.')) {
                return 'Please enter a valid email';
              }
              if (ctrl.emailExistsError != null) return ctrl.emailExistsError;
              return null;
            },
          ),
          const SizedBox(height: AuthSpacing.s16),
          AuthTextField(
            label: 'Phone Number',
            hint: 'e.g. 09XX-XXX-XXXX',
            controller: phone,
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (v) => ctrl.phone = v,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your phone number';
              }
              if (val.trim().length < 10) {
                return 'Please enter a valid phone number';
              }
              return null;
            },
          ),
          if (!ctrl.isReapply) ...[
            const SizedBox(height: AuthSpacing.s16),
            AuthTextField(
              label: 'Password',
              hint: 'At least 6 characters',
              controller: password,
              obscureText: true,
              passwordField: true,
              prefixIcon: Icons.lock_outline,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (v) => ctrl.password = v,
              validator: (val) => (val == null || val.length < 6)
                  ? 'Password must be at least 6 characters'
                  : null,
            ),
            const SizedBox(height: AuthSpacing.s8),
            PasswordStrengthMeter(password: password.text),
            AuthTextField(
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              controller: confirm,
              obscureText: true,
              passwordField: true,
              prefixIcon: Icons.lock_clock_outlined,
              validator: (val) =>
                  (val != password.text) ? 'Passwords do not match' : null,
            ),
          ],
          const SizedBox(height: AuthSpacing.s16),
          TermsPolicyTile(
            value: ctrl.termsAccepted,
            onChanged: (v) => ctrl.termsAccepted = v,
            policy: CUFMAITermsPolicy.seller,
          ),
          const SizedBox(height: AuthSpacing.s24),
          SolePrimaryAuthButton(
            label: 'Continue',
            isLoading: checkingEmail,
            onPressed: checkingEmail ? null : onContinue,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// STEP 2 — IDENTITY
// ══════════════════════════════════════════════════════════════════
class _IdentityStep extends StatefulWidget {
  final SellerApplicationController ctrl;
  final void Function(SellerDocState doc) onPick;

  const _IdentityStep({required this.ctrl, required this.onPick});

  @override
  State<_IdentityStep> createState() => _IdentityStepState();
}

class _IdentityStepState extends State<_IdentityStep> {
  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final idReady = ctrl.idDocument.status != DocumentUploadStatus.empty;
    final selfieReady = ctrl.selfie.status != DocumentUploadStatus.empty;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DocTileLabel('Government-issued ID'),
          DocumentUploadTile(
            title: 'Government ID photo',
            description:
                'Any valid ID with your full name and photo (UMID, passport, driver’s license, PRC).',
            status: ctrl.idDocument.status,
            imagePath: ctrl.idDocument.localPath,
            errorMessage: ctrl.idDocument.errorMessage,
            onPick: () => widget.onPick(ctrl.idDocument),
            onRemove: () => ctrl.removeDocument(ctrl.idDocument),
            onRetry: () => _retrySubmit(context, ctrl),
          ),
          const SizedBox(height: AuthSpacing.s16),
          _DocTileLabel('Liveness selfie'),
          DocumentUploadTile(
            title: 'Selfie',
            description:
                'A clear photo of your face in good light — no sunglasses or masks.',
            status: ctrl.selfie.status,
            imagePath: ctrl.selfie.localPath,
            errorMessage: ctrl.selfie.errorMessage,
            onPick: () => widget.onPick(ctrl.selfie),
            onRemove: () => ctrl.removeDocument(ctrl.selfie),
            onRetry: () => _retrySubmit(context, ctrl),
          ),
          const SizedBox(height: AuthSpacing.s16),
          _InfoBanner(
            icon: Icons.lock_outline_rounded,
            text:
                'Your photos are stored privately and only viewed by SoleVision admins during review.',
          ),
          const SizedBox(height: AuthSpacing.s24),
          SolePrimaryAuthButton(
            label: 'Continue',
            onPressed: () {
              if (!idReady) {
                _showSnack(context, 'Please add your government ID photo.');
                return;
              }
              if (!selfieReady) {
                _showSnack(context, 'Please add your selfie.');
                return;
              }
              ctrl.nextStep();
            },
          ),
        ],
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.error),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// STEP 3 — COMMUNITY
// ══════════════════════════════════════════════════════════════════
class _CommunityStep extends StatefulWidget {
  final SellerApplicationController ctrl;
  final TextEditingController memberId;
  final void Function(SellerDocState doc) onPick;

  const _CommunityStep({
    required this.ctrl,
    required this.memberId,
    required this.onPick,
  });

  @override
  State<_CommunityStep> createState() => _CommunityStepState();
}

class _CommunityStepState extends State<_CommunityStep> {
  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoBanner(
            icon: Icons.people_outline_rounded,
            text:
                'Why do we ask? SoleVision is a marketplace for Carcar City’s shoe artisans. Proving your CUFMAI membership — or that you live and work in the area — keeps the marketplace authentic.',
          ),
          const SizedBox(height: AuthSpacing.s16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('CUFMAI member'),
                icon: Icon(Icons.badge_outlined, size: 18),
              ),
              ButtonSegment(
                value: false,
                label: Text('Not a member'),
                icon: Icon(Icons.home_outlined, size: 18),
              ),
            ],
            selected: {ctrl.isCufmaiMember},
            onSelectionChanged: (selection) {
              ctrl.isCufmaiMember = selection.first;
              if (selection.first) ctrl.removeDocument(ctrl.barangayProof);
            },
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppConstants.primary.withValues(alpha: 0.12),
              selectedForegroundColor: AppConstants.primary,
              side: BorderSide(
                color: AppConstants.borderGray.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: AuthSpacing.s16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: ctrl.isCufmaiMember
                ? Column(
                    key: const ValueKey('member'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthTextField(
                        label: 'CUFMAI Member ID (optional)',
                        hint: 'e.g. CUF-2021-0184',
                        controller: widget.memberId,
                        prefixIcon: Icons.badge_outlined,
                        onChanged: (v) => ctrl.cufmaiMemberId = v,
                      ),
                      const SizedBox(height: AuthSpacing.s12),
                      Text(
                        'Adding your member ID speeds up approval. If you don’t have it handy, you can still apply.',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                          height: 1.4,
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('non-member'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DocTileLabel('Proof of residency (barangay)'),
                      DocumentUploadTile(
                        title: 'Barangay certificate / proof',
                        description:
                            'Barangay certificate of residency, cedula, or any recent proof you live in Carcar City.',
                        status: ctrl.barangayProof.status,
                        imagePath: ctrl.barangayProof.localPath,
                        errorMessage: ctrl.barangayProof.errorMessage,
                        onPick: () => widget.onPick(ctrl.barangayProof),
                        onRemove: () => ctrl.removeDocument(ctrl.barangayProof),
                        onRetry: () => _retrySubmit(context, ctrl),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AuthSpacing.s24),
          SolePrimaryAuthButton(
            label: 'Continue',
            onPressed: () {
              if (!ctrl.isCufmaiMember &&
                  ctrl.barangayProof.status == DocumentUploadStatus.empty) {
                _showSnack(context, 'Please add your barangay proof to continue.');
                return;
              }
              ctrl.nextStep();
            },
          ),
        ],
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.error),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// STEP 4 — STOREFRONT
// ══════════════════════════════════════════════════════════════════
class _StorefrontStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final SellerApplicationController ctrl;
  final TextEditingController storeName;
  final TextEditingController storeDescription;
  final TextEditingController payoutDetails;
  final VoidCallback onSubmit;

  const _StorefrontStep({
    required this.formKey,
    required this.ctrl,
    required this.storeName,
    required this.storeDescription,
    required this.payoutDetails,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isGcash = ctrl.payoutMethod == AppConstants.payoutGcash;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            label: 'Store Name',
            hint: 'e.g. Reyes Handcrafted Leather',
            controller: storeName,
            prefixIcon: Icons.storefront_outlined,
            onChanged: (v) => ctrl.storeName = v,
            validator: (val) => (val == null || val.trim().isEmpty)
                ? 'Please enter your store name'
                : null,
          ),
          const SizedBox(height: AuthSpacing.s16),
          AuthTextField(
            label: 'Store Description',
            hint: 'Tell customers about your craft — materials, styles, story.',
            controller: storeDescription,
            maxLines: 4,
            onChanged: (v) => ctrl.storeDescription = v,
            validator: (val) {
              if (val == null || val.trim().length < 20) {
                return 'Please write at least a short paragraph (20+ characters)';
              }
              return null;
            },
          ),
          const SizedBox(height: AuthSpacing.s24),
          Text(
            'PAYOUT METHOD',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AuthSpacing.s8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'gcash',
                label: Text('GCash'),
                icon: Icon(Icons.smartphone_outlined, size: 18),
              ),
              ButtonSegment(
                value: 'bank',
                label: Text('Bank account'),
                icon: Icon(Icons.account_balance_outlined, size: 18),
              ),
            ],
            selected: {ctrl.payoutMethod},
            onSelectionChanged: (selection) {
              ctrl.payoutMethod = selection.first;
              ctrl.payoutDetails = '';
              payoutDetails.clear();
            },
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppConstants.primary.withValues(alpha: 0.12),
              selectedForegroundColor: AppConstants.primary,
              side: BorderSide(
                color: AppConstants.borderGray.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: AuthSpacing.s16),
          AuthTextField(
            label: isGcash ? 'GCash Number' : 'Bank Details',
            hint: isGcash
                ? 'e.g. 0917 123 4567'
                : 'Bank name + account name + account number',
            controller: payoutDetails,
            prefixIcon: isGcash
                ? Icons.phone_android_outlined
                : Icons.account_balance_outlined,
            onChanged: (v) => ctrl.payoutDetails = v,
            validator: (val) => (val == null || val.trim().isEmpty)
                ? 'Please enter your payout details'
                : null,
          ),
          const SizedBox(height: AuthSpacing.s12),
          Text(
            'Your earnings from SoleVision sales are sent here. You can update this later.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: AuthSpacing.s24),
          SolePrimaryAuthButton(
            label: 'Submit application',
            isLoading: ctrl.isSubmitting,
            onPressed: ctrl.isSubmitting ? null : onSubmit,
          ),
          const SizedBox(height: AuthSpacing.s8),
          // Footnote with an inline tappable link to the Terms & Privacy
          // Policy — WidgetSpan + GestureDetector keeps it leak-free inside
          // this stateless step (no recognizer lifecycle to manage).
          Center(
            child: Text.rich(
              TextSpan(
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.45),
                  height: 1.4,
                ),
                children: [
                  const TextSpan(
                    text: 'By submitting, you agree to be reviewed by a '
                        'SoleVision admin before selling, and to our ',
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TermsPrivacyScreen(
                              policy: CUFMAITermsPolicy.seller,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Terms & Privacy Policy',
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primary,
                        ).copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: AppConstants.primary,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SUBMISSION VIEW — animated checklist with a designed error + retry
// ══════════════════════════════════════════════════════════════════
class _SubmissionView extends StatelessWidget {
  const _SubmissionView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SellerApplicationController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AuthSpacing.s20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppConstants.premiumCardRadius,
            boxShadow: AppConstants.premiumCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Submitting your application',
                style: AppConstants.headlineStyle(fontSize: 18),
              ),
              const SizedBox(height: AuthSpacing.s4),
              Text(
                'This usually takes a few seconds. Please keep the app open.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AuthSpacing.s16),
              _CheckRow(
                label: 'Create your account',
                done: ctrl.accountCreated,
                active: ctrl.isSubmitting && !ctrl.accountCreated,
              ),
              _CheckRow(
                label: 'Upload government ID',
                done: ctrl.idDocument.status == DocumentUploadStatus.uploaded,
                active: ctrl.idDocument.status ==
                    DocumentUploadStatus.uploading,
                error: ctrl.idDocument.status == DocumentUploadStatus.error,
              ),
              _CheckRow(
                label: 'Upload selfie',
                done: ctrl.selfie.status == DocumentUploadStatus.uploaded,
                active:
                    ctrl.selfie.status == DocumentUploadStatus.uploading,
                error: ctrl.selfie.status == DocumentUploadStatus.error,
              ),
              if (!ctrl.isCufmaiMember)
                _CheckRow(
                  label: 'Upload barangay proof',
                  done: ctrl.barangayProof.status ==
                      DocumentUploadStatus.uploaded,
                  active: ctrl.barangayProof.status ==
                      DocumentUploadStatus.uploading,
                  error: ctrl.barangayProof.status ==
                      DocumentUploadStatus.error,
                ),
              _CheckRow(
                label: 'Save your application',
                done: ctrl.applicationSaved,
                active: ctrl.isSubmitting &&
                    !ctrl.applicationSaved &&
                    ctrl.accountCreated &&
                    ctrl.completedUploadCount == ctrl.requiredUploadCount,
              ),
            ],
          ),
        ),
        if (ctrl.submitError != null) ...[
          const SizedBox(height: AuthSpacing.s16),
          Container(
            padding: const EdgeInsets.all(AuthSpacing.s16),
            decoration: BoxDecoration(
              color: AppConstants.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppConstants.error.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppConstants.error,
                      size: 20,
                    ),
                    const SizedBox(width: AuthSpacing.s8),
                    Expanded(
                      child: Text(
                        ctrl.submitError!,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AuthSpacing.s12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () {
                      final auth = context.read<AuthProvider>();
                      ctrl.submit(
                        signUpSeller: (data) =>
                            auth.signUpSeller(data: data),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AuthSpacing.s4),
                Center(
                  child: TextButton(
                    onPressed: () {
                      ctrl.dismissSubmission();
                      ctrl.jumpToStep(0);
                    },
                    child: Text(
                      'Back to my application',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Retries the full submission from a document-error state inside a step.
/// The submit sequence is idempotent — already-uploaded documents are
/// skipped and only the failed one is re-attempted.
void _retrySubmit(BuildContext context, SellerApplicationController ctrl) {
  final auth = context.read<AuthProvider>();
  ctrl.submit(signUpSeller: (data) => auth.signUpSeller(data: data));
}

// ══════════════════════════════════════════════════════════════════
// Small shared bits
// ══════════════════════════════════════════════════════════════════
class _CheckRow extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  final bool error;

  const _CheckRow({
    required this.label,
    required this.done,
    this.active = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget trailing;
    if (done) {
      trailing = const Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: AppConstants.success,
      );
    } else if (error) {
      trailing = const Icon(
        Icons.cancel_rounded,
        size: 20,
        color: AppConstants.error,
      );
    } else if (active) {
      trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppConstants.primary,
        ),
      );
    } else {
      trailing = const Icon(
        Icons.radio_button_unchecked_rounded,
        size: 20,
        color: AppConstants.borderGray,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: trailing,
          ),
          const SizedBox(width: AuthSpacing.s12),
          Expanded(
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: done ? FontWeight.w600 : FontWeight.normal,
                color: done
                    ? AppConstants.success
                    : (error ? AppConstants.error : AppConstants.secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTileLabel extends StatelessWidget {
  final String text;

  const _DocTileLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AuthSpacing.s8),
      child: Text(
        text.toUpperCase(),
        style: AppConstants.bodyStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppConstants.secondary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AuthSpacing.s12),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppConstants.primary),
          const SizedBox(width: AuthSpacing.s8),
          Expanded(
            child: Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


