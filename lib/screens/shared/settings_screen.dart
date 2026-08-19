import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/sole_card.dart';
import '../customer/foot_instructions_screen.dart';
import 'terms_privacy_screen.dart';
import 'about_cufmai_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Settings items card
            SoleCard(
              color: Colors.white,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
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
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  _settingsRow(
                    context: context,
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    onTap: () => _sendReset(context, auth),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
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
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
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
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Logout button
            OutlinedButton.icon(
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
          ],
        ),
      ),
    );
  }

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
      child: ListTile(
        dense: subtitle == null,
        leading: Icon(icon, color: AppConstants.primary, size: 22),
        title: Text(title, style: AppConstants.bodyStyle(fontSize: 14)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
        trailing: trailing ??
            const Icon(Icons.chevron_right, color: AppConstants.borderGray),
        onTap: onTap,
      ),
    );
  }

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
