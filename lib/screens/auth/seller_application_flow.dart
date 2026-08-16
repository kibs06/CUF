import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../models/seller_application_data.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_application_controller.dart';
import '../../screens/shared/terms_privacy_screen.dart';
import '../../services/auth_service.dart';
import '../../services/seller_application_draft_store.dart';
import '../../utils/customer_profile_fields.dart';
import '../../utils/dev_mode.dart';
import '../../screens/seller/store_location_picker_screen.dart';
import '../../widgets/seller/tag_selector.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/document_upload_tile.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';
import '../../widgets/auth/step_progress_indicator.dart';
import '../../widgets/auth/terms_policy_tile.dart';

/// Multi-step seller application (the spec's "SellerApplicationFlow"):
///
///   Step 1 — Account      full name, email, phone, birthday, gender, password, terms
///   Step 2 — Identity     government ID photo + liveness selfie
///   Step 3 — Community    CUFMAI/barangay proof + store location (map)
///   Step 4 — Business     DTI certificate + BIR COR + mayor's/barangay permit (required)
///   Step 5 — Storefront   store name, description, tags, store photos
///
/// The Supabase Auth user is created ONLY on final submit (see
/// SellerApplicationController). All form + upload state lives in the
/// controller, so navigating back/forward (or leaving and re-entering the
/// flow) never loses entered data.
///
/// Two behaviors worth knowing:
/// - **Back goes to the previous step.** The top-bar back button AND the
///   system back gesture move back one step (step 4 → 3 → …) instead of
///   popping the whole flow to the landing screen; only step 1 exits the
///   flow. During submission back is ignored; on the submission/error view
///   back dismisses it and returns to the form.
/// - **30-minute draft resume.** For the fresh "Apply to sell" entry (no
///   `prefillProfile`), the form is autosaved to disk (debounced) so an
///   accidentally-closed app restores the filled fields, the current step,
///   and any still-existing picked images when reopened within 30 minutes
///   (see SellerApplicationDraftStore). The draft is cleared on successful
///   submission; re-apply (`prefillProfile`) never persists or restores.
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
  // Step 3 personal-detail fields (owned here so draft restore + re-apply
  // prefill can seed them like every other text field).
  final _birthdayController = TextEditingController();
  final _genderSelfDescribeController = TextEditingController();
  final _locationController = TextEditingController();
  String? _gender;

  // One form key per step — AnimatedSwitcher briefly keeps the outgoing
  // step mounted, so sharing a key between steps would crash with
  // "Duplicate GlobalKey".
  final _accountFormKey = GlobalKey<FormState>();
  final _storefrontFormKey = GlobalKey<FormState>();
  bool _checkingEmail = false;

  // Debounced draft autosave — SharedPreferences is written at most every
  // 300ms of typing, and never for the re-apply flow (prefillProfile).
  Timer? _saveTimer;

  bool get _persistDraft => widget.prefillProfile == null;

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
    _seedPersonalDetails();
    // The step widgets read controller state directly in their build
    // methods (step index, termsAccepted, document statuses…), so the flow
    // must re-run its own build whenever the controller changes — otherwise
    // a value like termsAccepted is stored but never repainted (e.g. the
    // terms checkbox staying unchecked after the read-and-agree flow).
    _controller.addListener(_onControllerChanged);
    _restoreDraft();
  }

  /// Restores a persisted draft (app was closed mid-application and
  /// reopened within the 30-minute window). Loads asynchronously; the step
  /// widgets render the (empty) current step first, then repaint once the
  /// draft lands — fast enough on-device that no loading gate is needed.
  Future<void> _restoreDraft() async {
    if (!_persistDraft) return;
    final draft = await SellerApplicationDraftStore.instance.load();
    if (!mounted || draft == null) return;
    _controller.restoreDraft(draft);
    // Sync the TextEditingControllers so the restored text is editable.
    _nameController.text = _controller.fullName;
    _emailController.text = _controller.email;
    _phoneController.text = _controller.phone;
    _passwordController.text = _controller.password;
    _confirmController.text = _controller.password;
    _memberIdController.text = _controller.cufmaiMemberId;
    _storeNameController.text = _controller.storeName;
    _storeDescController.text = _controller.storeDescription;
    _seedPersonalDetails();
    setState(() {});
  }

  /// Seeds the Step 1 personal-detail fields from controller state — used
  /// on init (re-apply prefill already lives in the controller) and after
  /// a draft restore. A saved free-text gender maps back to the
  /// 'Self-describe' chip with the text restored.
  void _seedPersonalDetails() {
    final ctrl = _controller;
    _birthdayController.text =
        ctrl.birthday == null ? '' : _formatBirthday(ctrl.birthday!);
    final gender = ctrl.gender;
    if (gender != null && gender.isNotEmpty) {
      if (AppConstants.customerGenderOptions.contains(gender)) {
        _gender = gender;
      } else {
        _gender = 'Self-describe';
        _genderSelfDescribeController.text = gender;
      }
    }
    _locationController.text = ctrl.storeLocation;
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!_persistDraft) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final ctrl = _controller;
    await SellerApplicationDraftStore.instance.save(
      SellerApplicationDraft(
        step: ctrl.step,
        fullName: ctrl.fullName,
        email: ctrl.email,
        phone: ctrl.phone,
        password: ctrl.password,
        termsAccepted: ctrl.termsAccepted,
        isCufmaiMember: ctrl.isCufmaiMember,
        cufmaiMemberId: ctrl.cufmaiMemberId,
        idType: ctrl.idType,
        birthday: ctrl.birthday,
        gender: ctrl.gender,
        storeLocation: ctrl.storeLocation,
        storeTags: ctrl.storeTags,
        storeName: ctrl.storeName,
        storeDescription: ctrl.storeDescription,
        idDocumentPath: ctrl.idDocument.localPath,
        selfiePath: ctrl.selfie.localPath,
        barangayProofPath: ctrl.barangayProof.localPath,
        storeFrontPath: ctrl.storeFront.localPath,
        dtiPath: ctrl.dti.localPath,
        birPath: ctrl.bir.localPath,
        permitPath: ctrl.permit.localPath,
        productPhotoPaths:
            ctrl.productPhotos.map((doc) => doc.localPath).toList(),
        savedAt: DateTime.now(),
      ),
    );
  }

  /// Shared back handler for the top-bar button and the system back
  /// gesture: move back one step, dismiss the submission view, or (only on
  /// step 1) leave the flow.
  void _handleBack() {
    final ctrl = _controller;
    if (ctrl.isSubmitting) return;
    if (ctrl.showSubmission) {
      ctrl.dismissSubmission();
      return;
    }
    if (ctrl.step > 0) {
      ctrl.backStep();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
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
    _birthdayController.dispose();
    _genderSelfDescribeController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ── Step 1 actions ────────────────────────────────────────────
  Future<void> _continueFromAccount() async {
    if (_checkingEmail) return;

    // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
    // UI-only skip: bypass validation, terms + duplicate-email check.
    if (DevMode.instance.isEnabled) {
      _controller.nextStep();
      return;
    }

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
    // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
    // REAL-ACCOUNT dev submit: creates an actual Supabase account with a
    // normal PENDING application (role stays customer, seller_status =
    // pending), so the dev lands on PendingApprovalScreen and the FULL
    // admin loop runs: admin approves in the console → in-app notification
    // + Gmail via the send-approval-email edge function. No documents are
    // uploaded (paths are null — the admin review shows them as missing,
    // which is fine for testing). The chosen credentials are reused when
    // the email already exists (ensureUser signs back in), so repeated dev
    // runs land on the same pending account.
    if (DevMode.instance.isEnabled) {
      final auth = context.read<AuthProvider>();
      final email = _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim()
          : 'dev.seller@test.com';
      final password = _passwordController.text.isNotEmpty
          ? _passwordController.text
          : 'devpass123';
      final fullName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'Dev Seller';
      final ok = await auth.signUpSeller(
        data: SellerApplicationData(
          fullName: fullName,
          email: email,
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : '09171234567',
          password: password,
          idType: _controller.idType,
          idDocumentPath: null,
          selfiePath: null,
          cufmaiMemberId: _controller.cufmaiMemberId.trim().isNotEmpty
              ? _controller.cufmaiMemberId.trim()
              : null,
          barangayProofPath: null,
          birthday: _controller.birthday ?? DateTime(2000, 1, 1),
          gender: resolveGenderValue(
            _gender,
            _genderSelfDescribeController.text,
          ),
          storeLocation: _controller.storeLocation.trim().isNotEmpty
              ? _controller.storeLocation.trim()
              : 'Carcar City, Cebu',
          storeLat: _controller.storeLat,
          storeLng: _controller.storeLng,
          dtiCertPath: null,
          birCorPath: null,
          permitPath: null,
          storeName: _controller.storeName.trim().isNotEmpty
              ? _controller.storeName.trim()
              : 'Dev Store',
          storeDescription: _controller.storeDescription.trim(),
          storeTags: _controller.storeTags.isNotEmpty
              ? List.of(_controller.storeTags)
              : const ['local'],
          storeFrontPath: null,
          productPhotoPaths: const [],
        ),
      );
      if (!mounted) return;

      // Capture messenger + navigator before popping — the flow's context
      // is disposed by popUntil (flow + entry screen both unwind), so
      // reading it afterwards is unsafe. AuthGate routes to the real
      // PendingApprovalScreen (session adopted, seller_status = pending).
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Dev seller application submitted — awaiting admin approval (DEV MODE)'
                : 'Dev seller application failed: '
                    '${auth.errorMessage ?? 'unknown error'}',
          ),
          backgroundColor: ok ? AppConstants.success : AppConstants.error,
        ),
      );
      return;
    }

    if (!_storefrontFormKey.currentState!.validate()) return;
    // Resolve the Step 1 gender (chip → free text when 'Self-describe')
    // into the controller so the submission carries the final value.
    _controller.gender =
        resolveGenderValue(_gender, _genderSelfDescribeController.text);
    // At least one store tag is required (application v2).
    if (_controller.storeTags.isEmpty) {
      _showError('Please choose at least one store tag.');
      return;
    }
    // Store photos are required — admins verify the applicant really runs
    // a store, and the store-front photo doubles as the store banner.
    if (_controller.storeFront.status == DocumentUploadStatus.empty) {
      _showError('Please add a photo of your store front.');
      return;
    }
    final missingProducts = _controller.productPhotos
        .where((doc) => doc.status == DocumentUploadStatus.empty)
        .length;
    if (missingProducts > 0) {
      _showError(
        missingProducts == 1
            ? 'Please add 1 more product photo (5 required).'
            : 'Please add $missingProducts more product photos (5 required).',
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await _controller.submit(
      signUpSeller: (data) => auth.signUpSeller(data: data),
    );
    if (!mounted) return;
    if (ok) {
      // The application is in — drop the persisted draft so reopening the
      // flow never resurrects a submitted form.
      _saveTimer?.cancel();
      SellerApplicationDraftStore.instance.clear();
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
    // Replace any visible snackbar — rapid validation taps on the same
    // step should update the message, not queue stale ones behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
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
        // Back moves between steps (or dismisses the submission view), so
        // the route may only pop from step 1 while idle.
        canPop: !submitting && !ctrl.showSubmission && ctrl.step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack();
        },
        child: SignupScaffold(
          eyebrow: 'SELLER APPLICATION',
          title: _titleFor(ctrl.step),
          subtitle: _subtitleFor(ctrl.step),
          onBack: _handleBack,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepProgressIndicator(
                currentStep: ctrl.step,
                totalSteps: SellerApplicationController.stepCount,
                labels: const ['Account', 'Identity', 'Community', 'Business', 'Storefront'],
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
      case 3:
        return 'Verify your business';
      default:
        return 'Set up your storefront';
    }
  }

  // The "Step X of 4 · Step name" caption below the segmented progress bar
  // already states the position, so the subtitle keeps only the guidance.
  String _subtitleFor(int step) {
    switch (step) {
      case 0:
        return 'Your login details for SoleVision.';
      case 1:
        return 'A government ID and a selfie help admins confirm it’s really you.';
      case 2:
        return 'CUFMAI membership (or barangay proof), your personal details, and your store’s location.';
      case 3:
        return 'DTI certificate, BIR COR, and mayor’s/barangay permit — these confirm you run a registered business.';
      default:
        return 'Your store name, tags, and photos — how customers will find you.';
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
          birthdayController: _birthdayController,
          gender: _gender,
          onGenderChanged: (g) => setState(() => _gender = g),
          selfDescribeController: _genderSelfDescribeController,
          onPickBirthday: _pickBirthday,
        );
      case 1:
        return _IdentityStep(ctrl: ctrl, onPick: _pickDocument);
      case 2:
        return _CommunityStep(
          ctrl: ctrl,
          memberId: _memberIdController,
          onPick: _pickDocument,
          locationController: _locationController,
          onPickLocation: _pickStoreLocation,
        );
      case 3:
        return _BusinessStep(ctrl: ctrl, onPick: _pickDocument);
      default:
        return _StorefrontStep(
          formKey: _storefrontFormKey,
          ctrl: ctrl,
          storeName: _storeNameController,
          storeDescription: _storeDescController,
          onPick: _pickDocument,
          onSubmit: _submit,
        );
    }
  }

  // ── Step 3 actions ────────────────────────────────────────────
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _controller.birthday ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your birthday',
    );
    if (picked == null || !mounted) return;
    _controller.birthday = picked;
    _birthdayController.text = _formatBirthday(picked);
  }

  /// Store location: pushes the lightweight map picker (same MapTiler +
  /// Geolocator infrastructure as the customer's address screen, but no
  /// delivery-address form) and captures the confirmed address line +
  /// coordinates into the controller.
  Future<void> _pickStoreLocation() async {
    final picked = await Navigator.of(context).push<StoreLocationResult>(
      MaterialPageRoute(builder: (_) => const StoreLocationPickerScreen()),
    );
    if (picked == null || !mounted) return;
    _controller.storeLocation = picked.address;
    _controller.storeLat = picked.latitude;
    _controller.storeLng = picked.longitude;
    _locationController.text = picked.address;
  }

  String _formatBirthday(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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

  // Personal details (application v2 — birthday required, gender optional)
  final TextEditingController birthdayController;
  final String? gender;
  final ValueChanged<String?> onGenderChanged;
  final TextEditingController selfDescribeController;
  final VoidCallback onPickBirthday;

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
    required this.birthdayController,
    required this.gender,
    required this.onGenderChanged,
    required this.selfDescribeController,
    required this.onPickBirthday,
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
          const SizedBox(height: AuthSpacing.s16),

          // ── Personal details ────────────────────────────────────
          AuthTextField(
            label: 'Birthday *',
            hint: 'Tap to select your date of birth',
            controller: birthdayController,
            readOnly: true,
            onTap: onPickBirthday,
            prefixIcon: Icons.cake_outlined,
            validator: (_) => validateBirthday(ctrl.birthday),
          ),
          const SizedBox(height: AuthSpacing.s16),
          Text(
            'Gender (optional)',
            style: AppConstants.bodyStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: AuthSpacing.s8),
          Wrap(
            spacing: AuthSpacing.s8,
            runSpacing: AuthSpacing.s8,
            children: AppConstants.customerGenderOptions.map((option) {
              final selected = gender == option;
              return ChoiceChip(
                label: Text(
                  option,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? AppConstants.surfaceLight
                        : AppConstants.secondary,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                onSelected: (sel) => onGenderChanged(sel ? option : null),
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
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: gender == 'Self-describe'
                ? Padding(
                    padding: const EdgeInsets.only(top: AuthSpacing.s12),
                    child: AuthTextField(
                      label: 'How would you describe yourself?',
                      hint: 'e.g. Agender, Pangender, genderfluid…',
                      controller: selfDescribeController,
                      prefixIcon: Icons.edit_outlined,
                      validator: (_) => validateGenderSelfDescribe(
                        gender,
                        selfDescribeController.text,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: AuthSpacing.s16),
          if (!ctrl.isReapply) ...[
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
          _buildIdTypePicker(context, ctrl),
          // The ID photo upload only appears AFTER the seller commits to a
          // government ID type — picking the type "unlocks" the photo step
          // (AnimatedSwitcher so the reveal feels like a deliberate step).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: ctrl.idType == null
                ? Padding(
                    key: const ValueKey('id-photo-locked'),
                    padding: const EdgeInsets.only(top: AuthSpacing.s8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: AppConstants.secondary.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'The ID photo step appears once you choose your ID type above.',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(
                                alpha: 0.55,
                              ),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    key: const ValueKey('id-photo-upload'),
                    padding: const EdgeInsets.only(top: AuthSpacing.s12),
                    child: DocumentUploadTile(
                      title: 'Government ID photo',
                      description:
                          'A clear photo of the ID type you selected above — your full name and photo must be readable.',
                      status: ctrl.idDocument.status,
                      imagePath: ctrl.idDocument.localPath,
                      errorMessage: ctrl.idDocument.errorMessage,
                      onPick: () => widget.onPick(ctrl.idDocument),
                      onRemove: () => ctrl.removeDocument(ctrl.idDocument),
                      onRetry: () => _retrySubmit(context, ctrl),
                    ),
                  ),
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
              // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
              if (DevMode.instance.isEnabled) {
                ctrl.nextStep();
                return;
              }
              if (ctrl.idType == null) {
                _showSnack(context, 'Please select your government ID type.');
                return;
              }
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

  /// The "what type of government ID is this?" picker — a tappable card
  /// styled like the upload tiles that opens a bottom sheet listing the
  /// valid Philippine government IDs (AppConstants.govIdTypes).
  Widget _buildIdTypePicker(BuildContext context, SellerApplicationController ctrl) {
    final selected = ctrl.idType;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AuthSpacing.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (selected == null
                  ? AppConstants.borderGray
                  : AppConstants.success)
              .withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: AppConstants.warmShadow,
      ),
      child: InkWell(
        onTap: () => _pickIdType(context, ctrl),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AuthSpacing.s4),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: AppConstants.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AuthSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Government ID type',
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AuthSpacing.s4),
                    Text(
                      selected == null
                          ? 'Tap to choose — valid PH government IDs only'
                          : AppConstants.govIdTypeLabel(selected),
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.55),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AuthSpacing.s8),
              Icon(
                selected == null
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.check_circle_rounded,
                color: selected == null
                    ? AppConstants.secondary.withValues(alpha: 0.4)
                    : AppConstants.success,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickIdType(
    BuildContext context,
    SellerApplicationController ctrl,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  'Choose your government ID type',
                  style: AppConstants.headlineStyle(fontSize: 18),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: AppConstants.govIdTypes.length,
                  itemBuilder: (context, index) {
                    final type = AppConstants.govIdTypes[index];
                    final isSelected = ctrl.idType == type.value;
                    return ListTile(
                      title: Text(
                        type.label,
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: AppConstants.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(type.value),
                    );
                  },
                ),
              ),
              const SizedBox(height: AuthSpacing.s8),
            ],
          ),
        ),
      ),
    );
    if (selected != null) ctrl.idType = selected;
  }

  void _showSnack(BuildContext context, String message) {
    // Replace any visible snackbar — rapid validation taps on the same
    // step should update the message, not queue stale ones behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
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

  // Store location (application v2 — map-picked, required)
  final TextEditingController locationController;
  final VoidCallback onPickLocation;

  const _CommunityStep({
    required this.ctrl,
    required this.memberId,
    required this.onPick,
    required this.locationController,
    required this.onPickLocation,
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

          // ── Store location (map picker) ─────────────────────────
          _buildSectionLabel(
            context,
            'Store location *',
            Icons.location_on_outlined,
          ),
          const SizedBox(height: AuthSpacing.s8),
          AuthTextField(
            label: 'Where is your store?',
            hint: 'Tap to pin your store on the map',
            controller: widget.locationController,
            readOnly: true,
            onTap: widget.onPickLocation,
            prefixIcon: Icons.map_outlined,
          ),
          const SizedBox(height: AuthSpacing.s8),
          Text(
            'Pick your store address on the map — this becomes your store’s location on your public page.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AuthSpacing.s24),

          SolePrimaryAuthButton(
            label: 'Continue',
            onPressed: () {
              // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
              if (DevMode.instance.isEnabled) {
                ctrl.nextStep();
                return;
              }
              if (ctrl.storeLocation.trim().isEmpty) {
                _showSnack(
                  context,
                  'Please set your store location on the map to continue.',
                );
                return;
              }
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

  Widget _buildSectionLabel(
    BuildContext context,
    String text,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppConstants.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppConstants.headlineStyle(fontSize: 16),
        ),
      ],
    );
  }

  void _showSnack(BuildContext context, String message) {
    // Replace any visible snackbar — rapid validation taps on the same
    // step should update the message, not queue stale ones behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppConstants.error),
      );
  }
}

// ══════════════════════════════════════════════════════════════════
// STEP 4 — BUSINESS VERIFICATION
// ══════════════════════════════════════════════════════════════════
class _BusinessStep extends StatefulWidget {
  final SellerApplicationController ctrl;
  final void Function(SellerDocState doc) onPick;

  const _BusinessStep({
    required this.ctrl,
    required this.onPick,
  });

  @override
  State<_BusinessStep> createState() => _BusinessStepState();
}

class _BusinessStepState extends State<_BusinessStep> {
  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBanner(
          icon: Icons.verified_outlined,
          text:
              'These documents confirm you run a registered business. All three are required — they help admins verify your store before approving your application.',
        ),
        const SizedBox(height: AuthSpacing.s16),
        _DocTileLabel('DTI certificate'),
        DocumentUploadTile(
          title: 'DTI Business Registration',
          description:
              'Certificate of Business Name Registration issued by the DTI.',
          status: ctrl.dti.status,
          imagePath: ctrl.dti.localPath,
          errorMessage: ctrl.dti.errorMessage,
          onPick: () => widget.onPick(ctrl.dti),
          onRemove: () => ctrl.removeDocument(ctrl.dti),
          onRetry: () => _retrySubmit(context, ctrl),
        ),
        const SizedBox(height: AuthSpacing.s16),
        _DocTileLabel('BIR Certificate of Registration'),
        DocumentUploadTile(
          title: 'BIR COR',
          description:
              'Certificate of Registration issued by the BIR for your business.',
          status: ctrl.bir.status,
          imagePath: ctrl.bir.localPath,
          errorMessage: ctrl.bir.errorMessage,
          onPick: () => widget.onPick(ctrl.bir),
          onRemove: () => ctrl.removeDocument(ctrl.bir),
          onRetry: () => _retrySubmit(context, ctrl),
        ),
        const SizedBox(height: AuthSpacing.s16),
        _DocTileLabel('Mayor’s / barangay permit'),
        DocumentUploadTile(
          title: 'Business permit',
          description:
              'Mayor’s permit or barangay business permit for your location.',
          status: ctrl.permit.status,
          imagePath: ctrl.permit.localPath,
          errorMessage: ctrl.permit.errorMessage,
          onPick: () => widget.onPick(ctrl.permit),
          onRemove: () => ctrl.removeDocument(ctrl.permit),
          onRetry: () => _retrySubmit(context, ctrl),
        ),
        const SizedBox(height: AuthSpacing.s24),
        SolePrimaryAuthButton(
          label: 'Continue',
          onPressed: () {
            // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
            if (DevMode.instance.isEnabled) {
              ctrl.nextStep();
              return;
            }
            if (ctrl.dti.status == DocumentUploadStatus.empty) {
              _showSnack(
                context,
                'Please add your DTI certificate to continue.',
              );
              return;
            }
            if (ctrl.bir.status == DocumentUploadStatus.empty) {
              _showSnack(context, 'Please add your BIR COR to continue.');
              return;
            }
            if (ctrl.permit.status == DocumentUploadStatus.empty) {
              _showSnack(
                context,
                'Please add your business permit to continue.',
              );
              return;
            }
            ctrl.nextStep();
          },
        ),
      ],
    );
  }

  void _showSnack(BuildContext context, String message) {
    // Replace any visible snackbar — rapid validation taps on the same
    // step should update the message, not queue stale ones behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppConstants.error),
      );
  }
}

// ══════════════════════════════════════════════════════════════════
// STEP 5 — STOREFRONT
// ══════════════════════════════════════════════════════════════════
class _StorefrontStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final SellerApplicationController ctrl;
  final TextEditingController storeName;
  final TextEditingController storeDescription;
  final void Function(SellerDocState doc) onPick;
  final VoidCallback onSubmit;

  const _StorefrontStep({
    required this.formKey,
    required this.ctrl,
    required this.storeName,
    required this.storeDescription,
    required this.onPick,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
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
            // Optional — sellers can add their story after approval from
            // their store's edit screen; don't gate submission on it.
            label: 'Store Description (optional)',
            hint: 'Tell customers about your craft — you can add this later.',
            controller: storeDescription,
            maxLines: 4,
            onChanged: (v) => ctrl.storeDescription = v,
          ),
          const SizedBox(height: AuthSpacing.s24),

          // ── Store tags (same vocabulary as product tags) ────────
          Row(
            children: [
              Icon(Icons.sell_outlined,
                  size: 16, color: AppConstants.primary),
              const SizedBox(width: 6),
              Text(
                'Store tags (optional)',
                style: AppConstants.headlineStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: AuthSpacing.s8),
          Text(
            'Choose at least one tag that describes your store — handmade, family-owned, Carcar-made…',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AuthSpacing.s12),
          TagSelector(
            groups: storeTagGroups,
            initialTags: ctrl.storeTags,
            onChanged: (tags) => ctrl.storeTags = tags,
          ),
          const SizedBox(height: AuthSpacing.s24),
          _DocTileLabel('Store photos'),
          DocumentUploadTile(
            title: 'Store front photo',
            description:
                'A photo of the front of your store — this becomes your store banner.',
            status: ctrl.storeFront.status,
            imagePath: ctrl.storeFront.localPath,
            errorMessage: ctrl.storeFront.errorMessage,
            onPick: () => onPick(ctrl.storeFront),
            onRemove: () => ctrl.removeDocument(ctrl.storeFront),
            onRetry: () => _retrySubmit(context, ctrl),
          ),
          const SizedBox(height: AuthSpacing.s24),
          _DocTileLabel('Product photos'),
          Text(
            'All 5 photos are required — they help admins confirm your store has real stock.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AuthSpacing.s12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  _ProductPhotoSlot(
                    key: ValueKey('product-slot-${i + 1}'),
                    index: i + 1,
                    doc: ctrl.productPhotos[i],
                    onPick: () => onPick(ctrl.productPhotos[i]),
                    onRemove: () => ctrl.removeDocument(ctrl.productPhotos[i]),
                  ),
                  if (i < 4) const SizedBox(width: AuthSpacing.s12),
                ],
              ],
            ),
          ),
          const SizedBox(height: AuthSpacing.s8),
          Text(
            'Swipe to see all 5 — tap a slot to add or replace a photo.',
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

/// One compact square slot in the product-photos carousel. Empty slots
/// show a "+ / number" affordance; filled slots show the picked image
/// with a number chip and a small remove (X) button.
class _ProductPhotoSlot extends StatelessWidget {
  final int index;
  final SellerDocState doc;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ProductPhotoSlot({
    super.key,
    required this.index,
    required this.doc,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final path = doc.localPath;

    return SizedBox(
      width: 96,
      height: 96,
      child: path == null
          ? _buildEmpty(context)
          : _buildFilled(context, path),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.6),
            width: 1,
          ),
          boxShadow: AppConstants.warmShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_a_photo_outlined,
              color: AppConstants.primary,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              '$index',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppConstants.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilled(BuildContext context, String path) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: AppConstants.primary.withValues(alpha: 0.08),
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppConstants.primary,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$index',
              style: AppConstants.bodyStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
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
                label: 'Upload store front photo',
                done: ctrl.storeFront.status ==
                    DocumentUploadStatus.uploaded,
                active: ctrl.storeFront.status ==
                    DocumentUploadStatus.uploading,
                error: ctrl.storeFront.status ==
                    DocumentUploadStatus.error,
              ),
              _CheckRow(
                label: 'Upload product photos (5)',
                done: ctrl.productPhotos.every(
                  (doc) => doc.status == DocumentUploadStatus.uploaded,
                ),
                active: ctrl.productPhotos.any(
                  (doc) => doc.status == DocumentUploadStatus.uploading,
                ),
                error: ctrl.productPhotos.any(
                  (doc) => doc.status == DocumentUploadStatus.error,
                ),
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


