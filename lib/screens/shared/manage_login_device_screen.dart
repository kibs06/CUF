import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';

/// Manage Login Device screen — shows the current device and lets the user
/// review or log out of their CUFMAI account.
class ManageLoginDeviceScreen extends StatefulWidget {
  const ManageLoginDeviceScreen({super.key});

  @override
  State<ManageLoginDeviceScreen> createState() =>
      _ManageLoginDeviceScreenState();
}

class _ManageLoginDeviceScreenState extends State<ManageLoginDeviceScreen> {
  String _deviceName = 'This Device';
  String _deviceModel = '';
  String _osInfo = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        _deviceModel = '${android.manufacturer} ${android.model}';
        _osInfo = 'Android ${android.version.release}';
        _deviceName = 'Android Device';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        _deviceModel = ios.name;
        _osInfo = 'iOS ${ios.systemVersion}';
        _deviceName = 'iPhone';
      } else {
        _deviceModel = 'Unknown Device';
        _osInfo = Platform.operatingSystem;
        _deviceName = 'Desktop';
      }
    } catch (e) {
      _deviceModel = Platform.operatingSystem;
      _osInfo = '';
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'Manage Login Device',
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

            // ── Info banner ──────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppConstants.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.accent.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppConstants.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Review the devices that have logged into your CUFMAI account. Log out any device you no longer use.',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── This Device ──────────────────────────────────
            _sectionHeader('This Device'),
            _buildSection([
              _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppConstants.primary,
                          ),
                        ),
                      ),
                    )
                  : _deviceRow(
                      icon: Platform.isIOS
                          ? Icons.phone_iphone
                          : Icons.phone_android,
                      deviceName: _deviceName,
                      model: _deviceModel,
                      osInfo: _osInfo,
                      email: auth.displayEmail,
                      isCurrentDevice: true,
                    ),
            ]),
            const SizedBox(height: 16),

            // ── Other Devices ────────────────────────────────
            _sectionHeader('Other Devices'),
            _buildSection([
              // Since we don't have a server-side session list, show a
              // placeholder explaining that other sessions are managed
              // via Supabase and can be revoked by changing the password.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 20,
                          color: AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'To log out all other devices, change your password. This will end all other active sessions.',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.secondary.withValues(alpha: 0.6),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final email = auth.displayEmail;
                          final success = await auth.resetPassword(email);
                          if (!mounted) return;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? 'Password reset email sent to ${auth.displayEmail}'
                                    : auth.errorMessage ?? 'Unable to send reset email.',
                              ),
                              backgroundColor:
                                  success ? AppConstants.success : AppConstants.error,
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.lock_reset_outlined,
                          size: 18,
                        ),
                        label: Text(
                          'Change Password to Log Out All Devices',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppConstants.primary.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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

  // ── Section card ───────────────────────────────────────────────
  Widget _buildSection(List<Widget> children) {
    return Container(
      color: Colors.white,
      child: Column(children: children),
    );
  }

  // ── Device row ─────────────────────────────────────────────────
  Widget _deviceRow({
    required IconData icon,
    required String deviceName,
    required String model,
    required String osInfo,
    required String email,
    required bool isCurrentDevice,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Device icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppConstants.primary, size: 22),
          ),
          const SizedBox(width: 14),
          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      deviceName,
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isCurrentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppConstants.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Current',
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (model.isNotEmpty)
                  Text(
                    model,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                if (osInfo.isNotEmpty)
                  Text(
                    osInfo,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
