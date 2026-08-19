import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/update_provider.dart';
import '../customer/address_book_screen.dart';
import '../customer/foot_instructions_screen.dart';
import 'help_menu_screen.dart';
import 'terms_privacy_screen.dart';
import 'whats_new_screen.dart';
import 'about_cufmai_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final updateProvider = context.watch<UpdateProvider>();
    final installedVersion = updateProvider.installedVersion;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'Settings',
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

            // ── Account Section ──────────────────────────────────
            _sectionHeader('Account'),
            _buildSection([
              _settingsRow(
                context: context,
                icon: Icons.straighten_outlined,
                title: 'Get Your Foot Size',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FootInstructionsScreen(),
                    ),
                  );
                },
              ),
              _settingsRow(
                context: context,
                icon: Icons.location_on_outlined,
                title: 'My Addresses',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AddressBookScreen(),
                    ),
                  );
                },
              ),
              _settingsRow(
                context: context,
                icon: Icons.lock_outline,
                title: 'Change Password',
                onTap: () => _sendReset(context, auth),
              ),
            ]),
            const SizedBox(height: 16),

            // ── Legal Section ────────────────────────────────────
            _sectionHeader('Legal'),
            _buildSection([
              _settingsRow(
                context: context,
                icon: Icons.description_outlined,
                title: 'Terms & Privacy',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TermsPrivacyScreen(
                        policy: auth.userRole == AppConstants.roleSeller
                            ? CUFMAITermsPolicy.seller
                            : (auth.userRole == AppConstants.roleAdmin
                                ? CUFMAITermsPolicy.all
                                : CUFMAITermsPolicy.customer),
                      ),
                    ),
                  );
                },
              ),
              _settingsRow(
                context: context,
                icon: Icons.info_outline,
                title: 'About CUFMAI',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AboutCufmaiScreen(),
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 16),

            // ── Support Section ──────────────────────────────────
            _sectionHeader('Support'),
            _buildSection([
              _settingsRow(
                context: context,
                icon: Icons.headset_mic_outlined,
                title: 'Help & Support',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HelpMenuScreen(),
                    ),
                  );
                },
              ),
              _settingsRow(
                context: context,
                icon: Icons.new_releases_outlined,
                title: "What's New",
                subtitle: installedVersion != null ? 'v$installedVersion' : null,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsNewScreen(),
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 32),

            // ── Logout Button ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout, color: AppConstants.error),
                label: Text(
                  'Log Out',
                  style: AppConstants.bodyStyle(color: AppConstants.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppConstants.error.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _confirmLogout(context, auth),
              ),
            ),
            const SizedBox(height: 16),
            // Version info
            Center(
              child: Text(
                installedVersion != null ? 'CUFMAI v$installedVersion' : '',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Section header with background ───────────────────────────
  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      color: const Color(0xFFF0F0F0),
      child: Text(
        title,
        style: AppConstants.bodyStyle(
          fontSize: 13,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  // ── Section card (flat, no rounded corners) ──────────────────
  Widget _buildSection(List<Widget> children) {
    return Container(
      color: Colors.white,
      child: Column(children: children),
    );
  }

  // ── Settings row ─────────────────────────────────────────────
  Widget _settingsRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppConstants.primary, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppConstants.bodyStyle(fontSize: 15),
                    ),
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
              trailing ??
                  const Icon(Icons.chevron_right, color: AppConstants.borderGray, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Password reset ───────────────────────────────────────────
  Future<void> _sendReset(BuildContext context, AuthProvider auth) async {
    final success = await auth.resetPassword(auth.displayEmail);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Password reset email sent to ${auth.displayEmail}'
              : auth.errorMessage ?? 'Unable to send reset email.',
        ),
        backgroundColor: success ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  // ── Logout confirm ───────────────────────────────────────────
  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: AppConstants.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await auth.logout();
    }
  }
}
