import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import 'admin_helpers.dart';

/// Admin Settings — port of admin-portal/src/pages/Settings.jsx.
///
/// Admin profile editing, password change, and a danger zone to sign out
/// of all sessions.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late final TextEditingController _nameCtrl;
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _signingOutAll = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    _nameCtrl = TextEditingController(text: profile?['full_name'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?['id'];
    if (userId == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Name cannot be empty.', isError: true);
      return;
    }
    setState(() => _savingProfile = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'full_name': name}).eq('id', userId);
      if (!mounted) return;
      _showSnack('Profile updated');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Update failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    final newPassword = _newPasswordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;
    if (newPassword.length < 6) {
      _showSnack('Password must be at least 6 characters', isError: true);
      return;
    }
    if (newPassword != confirm) {
      _showSnack('Passwords do not match', isError: true);
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: newPassword));
      if (!mounted) return;
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _showSnack('Password updated');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Password update failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _signOutAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text('Sign out of all sessions?', style: AppConstants.headlineStyle(fontSize: 18)),
        content: Text(
          'This signs you out of every device and session linked to this '
          'admin account.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.error,
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Sign out all',
              style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signingOutAll = true);
    try {
      // Invalidate every session server-side first, then clear local state.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {
      // Even if the server call fails, proceed with local sign-out.
    }
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppConstants.error : AppConstants.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final email = auth.displayEmail;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Settings', style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Admin profile
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppConstants.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_outline, size: 18, color: AppConstants.primary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Admin Profile',
                            style: AppConstants.headlineStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'FULL NAME',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameCtrl,
                        style: AppConstants.bodyStyle(fontSize: 14),
                        decoration: _fieldDecoration(),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'EMAIL',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceLight.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          email.isEmpty ? '—' : email,
                          style: AppConstants.bodyStyle(fontSize: 14, color: Colors.black45),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        onPressed: _savingProfile ? null : _saveProfile,
                        child: Text(
                          _savingProfile ? 'Saving…' : 'Save Profile',
                          style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Change password
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppConstants.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.lock_outline, size: 18, color: AppConstants.primary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Change Password',
                            style: AppConstants.headlineStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'NEW PASSWORD',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _newPasswordCtrl,
                        obscureText: true,
                        style: AppConstants.bodyStyle(fontSize: 14),
                        decoration: _fieldDecoration(),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'CONFIRM PASSWORD',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _confirmPasswordCtrl,
                        obscureText: true,
                        style: AppConstants.bodyStyle(fontSize: 14),
                        decoration: _fieldDecoration(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        onPressed: _savingPassword ? null : _changePassword,
                        child: Text(
                          _savingPassword ? 'Updating…' : 'Update Password',
                          style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Danger zone
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppConstants.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppConstants.error.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_outlined, size: 18, color: AppConstants.error),
                          const SizedBox(width: 8),
                          Text(
                            'Danger Zone',
                            style: AppConstants.headlineStyle(fontSize: 16, color: AppConstants.error),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign out of all devices and sessions linked to this admin account.',
                        style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.error),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.error,
                          side: const BorderSide(color: AppConstants.error),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: _signingOutAll ? null : _signOutAll,
                        child: Text(
                          _signingOutAll ? 'Signing out…' : 'Sign out of all sessions',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppConstants.surfaceLight.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppConstants.borderGray),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.6)),
      ),
    );
  }
}
