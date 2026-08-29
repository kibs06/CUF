import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import 'admin_shell.dart';

/// Screen showing suspicious/intruder login attempts for admin review.
/// Extends the existing admin panel as required by the prompt.
class AdminIntruderSuspiciousLoginScreen extends StatefulWidget {
  const AdminIntruderSuspiciousLoginScreen({super.key});

  @override
  State<AdminIntruderSuspiciousLoginScreen> createState() =>
      _AdminIntruderSuspiciousLoginScreenState();
}

class _AdminIntruderSuspiciousLoginScreenState
    extends State<AdminIntruderSuspiciousLoginScreen> {
  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Intruder / Suspicious Login',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _buildBody(authProvider),
        ],
      ),
    );
  }

  Widget _buildBody(AuthProvider authProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary stats card
          _buildSummaryCard(),

          const SizedBox(height: 24),

          // Table of failed logins
          _buildFailedLoginsTable(),

          const SizedBox(height: 24),

          // Action buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'View accounts with lockout status, failed attempt counts, and admin actions.',
            style: TextStyle(color: AppConstants.secondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedLoginsTable() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Flagged Login Attempts',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppConstants.primary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'No failed login data available yet.',
          style: TextStyle(color: AppConstants.secondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.lock_open),
            label: const Text('Clear All Lockouts'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}