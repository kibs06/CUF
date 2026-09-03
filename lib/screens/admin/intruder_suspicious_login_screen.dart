import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/auth_service.dart';

/// Screen showing suspicious/intruder login attempts for admin review.
/// Fetches real data from the failed_logins table joined with profiles.
class AdminIntruderSuspiciousLoginScreen extends StatefulWidget {
  const AdminIntruderSuspiciousLoginScreen({super.key});

  @override
  State<AdminIntruderSuspiciousLoginScreen> createState() =>
      _AdminIntruderSuspiciousLoginScreenState();
}

class _AdminIntruderSuspiciousLoginScreenState
    extends State<AdminIntruderSuspiciousLoginScreen> {
  final AuthService _auth = AuthService.instance;
  List<Map<String, dynamic>> _failedLogins = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _auth.fetchAllFailedLogins();
      if (mounted) {
        setState(() {
          _failedLogins = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearAllLockouts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Lockouts'),
        content: const Text(
          'This will reset all failed login counters and unlock all accounts. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _auth.clearAllLockouts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All lockouts cleared.'),
          backgroundColor: AppConstants.success,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear lockouts: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  int get _lockedCount =>
      _failedLogins.where((r) => r['status'] == 'locked').length;

  int get _activeCount =>
      _failedLogins.where((r) => r['status'] == 'active').length;

  @override
  Widget build(BuildContext context) {
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
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppConstants.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 24),
            _buildFailedLoginsList(),
            const SizedBox(height: 24),
            if (_failedLogins.isNotEmpty) _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security Overview',
            style: AppConstants.headlineStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatChip(
                label: 'Tracked',
                value: '${_failedLogins.length}',
                color: AppConstants.primary,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: 'Locked',
                value: '$_lockedCount',
                color: AppConstants.error,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: 'Active',
                value: '$_activeCount',
                color: AppConstants.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Accounts with 5+ failed attempts are locked for 30 minutes.',
            style: TextStyle(color: AppConstants.secondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedLoginsList() {
    if (_failedLogins.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppConstants.cardRadius,
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 48,
              color: AppConstants.secondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No failed login attempts recorded yet.',
              style: TextStyle(color: AppConstants.secondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Flagged Accounts (${_failedLogins.length})',
          style: AppConstants.headlineStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
        ..._failedLogins.map((row) => _buildLoginAttemptCard(row)),
      ],
    );
  }

  Widget _buildLoginAttemptCard(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    final email = profile?['email'] as String? ?? 'Unknown';
    final name = profile?['full_name'] as String? ?? 'Unknown';
    final status = row['status'] as String? ?? 'active';
    final attemptCount = (row['attempt_count'] ?? 0) as int;
    final lockedUntil = row['locked_until'] as String?;
    final failedAt = row['failed_at'] as String?;
    final ipAddress = row['ip_address'] as String?;

    final isLocked = status == 'locked';
    DateTime? lockedUntilDt;
    if (lockedUntil != null) {
      lockedUntilDt = DateTime.parse(lockedUntil).toUtc();
    }

    final statusColor = isLocked ? AppConstants.error : AppConstants.success;
    final statusText = isLocked ? 'LOCKED' : 'ACTIVE';
    final statusIcon = isLocked ? Icons.lock : Icons.lock_open;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border: Border.all(
          color: isLocked
              ? AppConstants.error.withValues(alpha: 0.5)
              : AppConstants.borderGray.withValues(alpha: 0.3),
          width: isLocked ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLocked ? AppConstants.error : Colors.black).withValues(
              alpha: isLocked ? 0.08 : 0.04,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      email,
                      style: TextStyle(
                        color: AppConstants.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: AppConstants.borderGray.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Row(
            children: [
              _DetailChip(
                icon: Icons.warning_amber_rounded,
                label: '$attemptCount attempt${attemptCount == 1 ? '' : 's'}',
                color: attemptCount >= 5 ? AppConstants.error : Colors.orange,
              ),
              const SizedBox(width: 12),
              if (ipAddress != null && ipAddress.isNotEmpty)
                _DetailChip(
                  icon: Icons.language,
                  label: ipAddress,
                  color: AppConstants.secondary,
                ),
            ],
          ),
          if (isLocked && lockedUntilDt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timer_off, size: 14, color: AppConstants.error),
                const SizedBox(width: 4),
                Text(
                  'Locked until ${lockedUntilDt.toLocal()}',
                  style: TextStyle(color: AppConstants.error, fontSize: 12),
                ),
              ],
            ),
          ],
          if (failedAt != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: AppConstants.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Last attempt: ${DateTime.parse(failedAt).toLocal()}',
                  style: TextStyle(color: AppConstants.secondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _clearAllLockouts,
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

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
