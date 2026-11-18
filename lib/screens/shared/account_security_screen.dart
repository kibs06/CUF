import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../services/mfa_service.dart';
import '../../services/passkey_service.dart';
import '../../widgets/sole_switch.dart';
import '../auth/edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'manage_login_device_screen.dart';
import 'mfa_settings_screen.dart';
import 'passkey_settings_screen.dart';

/// Account & Security screen — Shopee-style settings layout with
/// Account and Security sections.
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool? _mfaEnabled; // null = still loading
  int? _passkeyCount; // null = still loading / unavailable

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    _loadMfaState();
    _loadPasskeyState();
  }

  Future<void> _loadBiometricState() async {
    final bio = BiometricService.instance;
    final available = await bio.isBiometricAvailable();
    final enabled = await bio.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  Future<void> _loadMfaState() async {
    try {
      final enabled = await MfaService.instance.isMfaEnabled();
      if (mounted) {
        setState(() => _mfaEnabled = enabled);
      }
    } catch (e) {
      // Leave unknown — the row still navigates and the settings
      // screen itself shows the real state.
      debugPrint('[account_security] mfa status failed: $e');
    }
  }

  Future<void> _openMfaSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MfaSettingsScreen()));
    // Refresh the row status when returning from the settings screen.
    _loadMfaState();
  }

  Future<void> _loadPasskeyState() async {
    try {
      final passkeys = await PasskeyService.instance.list();
      if (mounted) setState(() => _passkeyCount = passkeys.length);
    } catch (e) {
      // Passkeys can be unavailable before the project is configured, or
      // while the session needs a fresh MFA verification. Leave the row
      // tappable so its screen can explain the real error.
      debugPrint('[account_security] passkey status failed: $e');
      if (mounted) setState(() => _passkeyCount = null);
    }
  }

  Future<void> _openPasskeySettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PasskeySettingsScreen()));
    _loadPasskeyState();
  }

  String get _passkeySubtitle {
    if (_passkeyCount == null) {
      return 'Use fingerprint, face or screen lock instead of a password';
    }
    if (_passkeyCount == 0) {
      return 'Set up a passkey for passwordless sign-in';
    }
    return '$_passkeyCount passkey${_passkeyCount == 1 ? '' : 's'} registered';
  }

  String get _passkeyActionLabel {
    return _passkeyCount == null || _passkeyCount == 0 ? 'Set Up' : 'Manage';
  }

  Future<void> _toggleBiometric(bool value) async {
    final bio = BiometricService.instance;
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (value) {
      // Enable — save current credentials for biometric re-auth
      final email = auth.displayEmail;
      if (email.isNotEmpty) {
        // We can't get the password here; biometric enrollment happens at
        // login time. Just flip the flag so next login offers enrollment.
        await bio.saveCredentials(email, '');
      }
    } else {
      await bio.clearCredentials();
    }

    if (mounted) {
      setState(() => _biometricEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Biometric authentication enabled'
                : 'Biometric authentication disabled',
          ),
          backgroundColor: AppConstants.success,
        ),
      );
    }
  }

  /// Set a new password right here, on the live session — no reset e-mail.
  ///
  /// The e-mail link is still the signed-OUT path (login screen's "Forgot
  /// password?"), because proving an account without a session needs a
  /// delivered link or OTP. This row is the signed-in one, where possession of
  /// the session is already the proof.
  Future<void> _openChangePassword() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(
          email: auth.displayEmail,
          onSubmit: (newPassword) => auth.changePassword(newPassword),
        ),
      ),
    );
  }

  /// Show a dialog to change the user's email address.
  Future<void> _showChangeEmailDialog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final controller = TextEditingController(text: auth.displayEmail);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Change Email',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A verification link will be sent to your new email address. The change will take effect once you confirm.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'New email address',
                  hintText: 'you@example.com',
                  labelStyle: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: AppConstants.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppConstants.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppConstants.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppConstants.primary),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter an email address';
                  }
                  final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                  if (!emailRegex.hasMatch(val.trim())) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(
              'Send Verification',
              style: AppConstants.bodyStyle(
                color: AppConstants.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final newEmail = controller.text.trim();
      final success = await auth.updateEmail(newEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Verification email sent to $newEmail'
                : auth.errorMessage ?? 'Failed to update email.',
          ),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  /// Mask a phone number for display: show last 2 digits.
  String _maskPhone(String phone) {
    if (phone.length <= 2) return phone;
    final masked = '*' * (phone.length - 2) + phone.substring(phone.length - 2);
    return masked;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Account & Security',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // ── Account Section ────────────────────────────────
            _sectionHeader('Account'),
            _buildSection([
              // My Profile
              _settingsRow(
                title: 'My Profile',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  );
                },
              ),

              // Username
              _infoRow(
                title: 'Username',
                value: auth.displayName.isNotEmpty
                    ? auth.displayName
                    : 'Not set',
              ),

              // Phone
              _settingsRow(
                title: 'Phone',
                value: auth.displayPhone.isNotEmpty
                    ? _maskPhone(auth.displayPhone)
                    : 'Not set',
                onTap: () {
                  // Navigate to profile edit for phone update
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  );
                },
              ),

              // Email
              auth.displayEmail.isNotEmpty
                  ? _settingsRow(
                      title: 'Email',
                      value: auth.displayEmail,
                      onTap: _showChangeEmailDialog,
                    )
                  : _settingsRow(
                      title: 'Email',
                      actionLabel: 'Set Now',
                      onTap: _showChangeEmailDialog,
                    ),

              // Social Media Accounts
              _settingsRow(
                title: 'Social Media Accounts',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon'),
                      backgroundColor: AppConstants.primary,
                    ),
                  );
                },
              ),

              // Change Password — in-app, on the existing session
              _settingsRow(
                title: 'Change Password',
                subtitle: 'Set a new one here — no email needed',
                onTap: _openChangePassword,
              ),

              // Passkeys
              _settingsRow(
                title: 'Passkeys',
                subtitle: _passkeySubtitle,
                actionLabel: _passkeyActionLabel,
                onTap: _openPasskeySettings,
              ),

              // Fingerprint Authentication
              if (_biometricAvailable)
                _toggleRow(
                  title: 'Fingerprint Authentication',
                  subtitle:
                      'Your fingerprint data is on your device and CUFMAI does not store it',
                  value: _biometricEnabled,
                  onChanged: _toggleBiometric,
                ),
            ]),
            const SizedBox(height: 16),

            // ── Security Section ──────────────────────────────
            _sectionHeader('Security'),
            _buildSection([
              _settingsRow(
                title: 'Check Account Activity',
                subtitle:
                    'Check your login and account changes in the last 30 days',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon'),
                      backgroundColor: AppConstants.primary,
                    ),
                  );
                },
              ),
              _settingsRow(
                title: 'Manage Login Device',
                subtitle:
                    'Review the devices that you have logged in CUFMAI account',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ManageLoginDeviceScreen(),
                    ),
                  );
                },
              ),
              _settingsRow(
                title: 'Two-Factor Authentication (2FA)',
                subtitle:
                    'Add a code from your authenticator app when signing in',
                value: _mfaEnabled == null
                    ? null
                    : (_mfaEnabled! ? 'On' : 'Off'),
                onTap: _openMfaSettings,
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Section header ─────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      color: AppConstants.sellerCardBg,
      child: Text(
        title,
        style: AppConstants.bodyStyle(
          fontSize: 13,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  // ── Section card ───────────────────────────────────────────────
  Widget _buildSection(List<Widget> children) {
    return Container(
      color: AppConstants.surfaceLight,
      child: Column(children: children),
    );
  }

  // ── Info row (read-only, no chevron) ───────────────────────────
  Widget _infoRow({required String title, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppConstants.bodyStyle(fontSize: 15)),
          ),
          Text(
            value,
            style: AppConstants.bodyStyle(
              fontSize: 14,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ── Settings row with optional trailing value ───────────────────
  Widget _settingsRow({
    required String title,
    required VoidCallback onTap,
    String? value,
    String? actionLabel,
    String? subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppConstants.bodyStyle(fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actionLabel != null)
                Text(
                  actionLabel,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.accent,
                  ),
                )
              else if (value != null)
                Text(
                  value,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: AppConstants.borderGray,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Toggle row (Fingerprint Authentication) ────────────────────
  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppConstants.bodyStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SoleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
