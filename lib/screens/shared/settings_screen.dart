import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/customer_profile_fields.dart';
import '../auth/account_entry_screen.dart';
import '../customer/address_book_screen.dart';
import '../customer/size_your_foot_screen.dart';
import 'account_security_screen.dart';
import 'account_switcher_screen.dart';
import 'help_menu_screen.dart';
import 'terms_privacy_screen.dart';
import 'whats_new_screen.dart';
import 'about_cufmai_screen.dart';

/// One row in the appearance sheet.
class _AppearanceOption {
  const _AppearanceOption({
    required this.mode,
    required this.icon,
    required this.title,
    required this.description,
  });

  final ThemeMode mode;
  final IconData icon;
  final String title;
  final String description;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final updateProvider = context.watch<UpdateProvider>();
    final installedVersion = updateProvider.installedVersion;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // ── Account Section ──────────────────────────────────
            _sectionHeader('Account'),
            _buildSection([
              _settingsRow(
                context: context,
                icon: Icons.security_outlined,
                title: 'Account & Security',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AccountSecurityScreen(),
                    ),
                  );
                },
              ),
              // Customer-only: a seller has no foot profile and no delivery
              // address book, so both rows would only drop them into empty
              // customer screens. Gated on `roleCustomer` rather than "not a
              // seller", so an admin does not inherit them either — the same
              // convention the profile screen's rows use.
              //
              // This screen is reachable from the seller profile's settings
              // icon (it is the only way a seller picks Light/Dark), which is
              // why the gate lives here rather than on the entry point.
              if (auth.userRole == AppConstants.roleCustomer) ...[
                // ONE entry for the foot size. The AR scan (Foot Size 2.0) and
                // manual entry are swipable panels inside, so the two paths
                // cannot drift apart in the menu. The subtitle names the current
                // value and where it came from, so the customer can see what the
                // app believes before changing it.
                _settingsRow(
                  context: context,
                  icon: Icons.straighten_outlined,
                  title: 'Size Your Foot',
                  subtitle: footProfileSummary(auth.profile),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SizeYourFootScreen(),
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
              ],
              _settingsRow(
                context: context,
                icon: Icons.swap_horiz,
                title: 'Switch Account',
                onTap: () => _openSwitchAccount(context),
              ),
            ]),
            const SizedBox(height: 16),

            // ── Appearance Section ───────────────────────────────
            _sectionHeader('Appearance'),
            _buildSection([
              _settingsRow(
                context: context,
                icon: Icons.brightness_6_outlined,
                title: 'Theme',
                subtitle: _appearanceSubtitle(context),
                onTap: () => _showAppearanceSheet(context),
              ),
            ]),
            const SizedBox(height: 16),

            // ── Legal Section ────────────────────────────────────
            _sectionHeader('Legal'),
            _buildSection([
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
                icon: Icons.new_releases_outlined,
                title: "What's New",
                subtitle: installedVersion != null ? 'v$installedVersion' : null,
                showDotBadge: updateProvider.hasUnviewedUpdate,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsNewScreen(),
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
                icon: Icons.delete_outline,
                title: 'Request Account Deletion',
                onTap: () => _confirmAccountDeletion(context, auth),
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

  // ── Appearance ───────────────────────────────────────────────
  /// The chosen mode, plus what it resolves to right now. "System · Dark" is
  /// deliberately explicit: it tells the user the app is following the device
  /// *and* what that currently means, which a bare "System" does not.
  String _appearanceSubtitle(BuildContext context) {
    final mode = context.watch<ThemeProvider>().mode;
    if (mode == ThemeMode.system) {
      final isDark = MediaQuery.platformBrightnessOf(context) ==
          Brightness.dark;
      return 'System · ${isDark ? 'Dark' : 'Light'} (device)';
    }
    return ThemeProvider.label(mode);
  }

  /// System / Light / Dark picker. A sheet rather than an inline switch: the
  /// three-way choice is the whole point (an on/off switch would silently
  /// stop following the device), and it matches the home screen's sort sheet.
  Future<void> _showAppearanceSheet(BuildContext context) async {
    final provider = context.read<ThemeProvider>();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppConstants.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Appearance',
                style: AppConstants.bodyStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Dark mode can follow your device or be pinned.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final option in _appearanceOptions)
              _appearanceOption(
                sheetContext,
                option,
                selected: provider.mode == option.mode,
                onTap: () {
                  provider.setMode(option.mode);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static const List<_AppearanceOption> _appearanceOptions = [
    _AppearanceOption(
      mode: ThemeMode.system,
      icon: Icons.brightness_auto_outlined,
      title: 'System',
      description: 'Match your device setting',
    ),
    _AppearanceOption(
      mode: ThemeMode.light,
      icon: Icons.light_mode_outlined,
      title: 'Light',
      description: 'Always the light theme',
    ),
    _AppearanceOption(
      mode: ThemeMode.dark,
      icon: Icons.dark_mode_outlined,
      title: 'Dark',
      description: 'Always the dark theme',
    ),
  ];

  Widget _appearanceOption(
    BuildContext context,
    _AppearanceOption option, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(option.icon, size: 22, color: AppConstants.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check, color: AppConstants.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section header with background ───────────────────────────
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

  // ── Section card (flat, no rounded corners) ──────────────────
  Widget _buildSection(List<Widget> children) {
    return Container(
      color: AppConstants.surfaceLight,
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
    bool showDotBadge = false,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppConstants.bodyStyle(fontSize: 15),
                          ),
                        ),
                        // Unviewed-update indicator dot (e.g. a newer What's
                        // New entry).
                        if (showDotBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppConstants.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
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
                  Icon(Icons.chevron_right, color: AppConstants.borderGray, size: 20),
            ],
          ),
        ),
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
      // Pop all routes back to root so AuthGate can show the login screen.
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  // ── Account deletion confirm ──────────────────────────────────
  Future<void> _confirmAccountDeletion(BuildContext context, AuthProvider auth) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Account Deletion'),
        content: const Text(
          'Are you sure you want to request account deletion?\n\n'
          'This will permanently remove all your data including:\n'
          '• Profile information\n'
          '• Orders and purchase history\n'
          '• Saved addresses\n'
          '• Foot sizing data\n\n'
          'This action cannot be undone.\n'
          'Please contact support if you need assistance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Request Deletion',
              style: TextStyle(color: AppConstants.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final result = await SupabaseService.instance.requestAccountDeletion();
        if (!context.mounted) return;
        Navigator.of(context).pop(); // dismiss loading

        final success = result['success'] == true;
        final message = result['message'] as String? ?? 'Something went wrong';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? null : AppConstants.error,
            duration: const Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  // ── Switch Account ───────────────────────────────────────────
  Future<void> _openSwitchAccount(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AccountSwitcherScreen(),
      ),
    );

    // If 'add_account' was returned, navigate to login
    if (result == 'add_account' && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AccountEntryScreen(),
        ),
      );
    }
  }
}
