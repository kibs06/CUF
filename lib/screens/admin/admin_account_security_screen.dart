import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../models/account_security_overview.dart';
import '../../services/account_security_service.dart';
import 'admin_helpers.dart';

/// Admin view of ONE account's sign-in security: trusted devices and whether
/// each still holds the credential the device gate checks, the GoTrue event
/// timeline, and password lockouts.
///
/// This exists because the new-device step-up is otherwise invisible from the
/// admin portal — "I got a new phone and I can't get in" had no answer beyond
/// guesswork. The screen leads with the DERIVED diagnosis (see
/// [AccountSecurityOverview.findingsAt]) and then shows the raw evidence, so
/// an admin can either act on the headline or check it themselves.
///
/// What it deliberately does NOT claim is stated on the screen: a device that
/// was refused is not recorded, and a wrong code leaves no trace, so an empty
/// timeline is not proof that nobody tried.
class AdminAccountSecurityScreen extends StatefulWidget {
  final String userId;
  final String userName;

  /// Injected in tests; defaults to the live service. Same shape as
  /// [EmailOtpScreen.otpService].
  final AccountSecurityService? service;

  const AdminAccountSecurityScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.service,
  });

  @override
  State<AdminAccountSecurityScreen> createState() =>
      _AdminAccountSecurityScreenState();
}

class _AdminAccountSecurityScreenState
    extends State<AdminAccountSecurityScreen> {
  late final AccountSecurityService _service =
      widget.service ?? AccountSecurityService();

  AccountSecurityOverview? _overview;
  bool _isLoading = true;
  String? _error;

  /// Read once per load so every finding on the page is judged against the
  /// same instant (a lockout expiring mid-build would otherwise flip the
  /// headline between frames).
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final overview = await _service.fetchOverview(widget.userId);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _now = DateTime.now();
        _isLoading = false;
      });
    } on AccountSecurityException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[AdminAccountSecurity] load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the security report. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Account Security: ${widget.userName}',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isLoading ? null : _load,
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
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    final overview = _overview;
    if (overview == null) {
      return Center(
        child: Text('No security report available.', style: AppConstants.bodyStyle()),
      );
    }

    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosisBanner(overview),
            const SizedBox(height: 16),
            _buildAccountCard(overview),
            const SizedBox(height: 16),
            _buildEnforcementCard(overview),
            const SizedBox(height: 16),
            _buildDevicesCard(overview),
            const SizedBox(height: 16),
            _buildLockoutsCard(overview),
            const SizedBox(height: 16),
            _buildTimelineCard(overview),
            const SizedBox(height: 16),
            _buildCaveatsCard(overview),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppConstants.error.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: AppConstants.primary),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── the derived diagnosis: what the admin should do ────────────────

  Widget _buildDiagnosisBanner(AccountSecurityOverview overview) {
    final findings = overview.findingsAt(_now);
    // The green banner is the answer when nothing is blocking or likely
    // blocking; the remaining context findings still render underneath it.
    final healthy = overview.isHealthyAt(_now);

    return Column(
      children: [
        if (healthy) _buildHealthyBanner() else const SizedBox.shrink(),
        if (healthy && findings.isNotEmpty) const SizedBox(height: 10),
        for (final finding in findings) ...[
          _buildFindingCard(finding),
          if (finding != findings.last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildHealthyBanner() {
    return _card(
      color: AppConstants.success.withValues(alpha: 0.08),
      borderColor: AppConstants.success.withValues(alpha: 0.35),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, color: AppConstants.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nothing on record would block this account',
                    style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold,
                      color: AppConstants.success,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The address is confirmed, no lockout is in force and every '
                    'recorded device holds a working credential. If they still '
                    'cannot get in, the phone itself is the place to look.',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.8),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildFindingCard(SecurityFinding finding) {
    final color = _severityColor(finding.severity);
    return _card(
      color: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_severityIcon(finding.severity), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _badge(_severityLabel(finding.severity), color),
                    const SizedBox(width: 6),
                    _badge(finding.code, AppConstants.secondary.withValues(alpha: 0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  finding.headline,
                  style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  finding.detail,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.8),
                    height: 1.35,
                  ),
                ),
                if (finding.action != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_forward, size: 13, color: AppConstants.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          finding.action!,
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── the evidence ───────────────────────────────────────────────────

  Widget _buildAccountCard(AccountSecurityOverview overview) {
    final account = overview.account;
    final rows = <Widget>[
      _kv('User id', account.userId),
      _kv('Email', account.email ?? '—'),
      _kv('Role', account.role),
      if (account.sellerStatus != null) _kv('Seller status', account.sellerStatus!),
      _kv(
        'Email confirmed',
        account.emailConfirmed
            ? 'Yes — ${adminDateTime(account.emailConfirmedAt)}'
            : 'NOT CONFIRMED',
        valueColor: account.emailConfirmed ? null : AppConstants.error,
      ),
      _kv('Last sign-in', adminDateTime(account.lastSignInAt)),
      _kv('Last code sent', adminDateTime(account.recoverySentAt)),
      _kv('Account created', adminDateTime(account.createdAt)),
      _kv('Profile row', account.hasProfile ? 'Present' : 'MISSING',
          valueColor: account.hasProfile ? null : AppConstants.error),
    ];

    return _section(
      title: 'Account',
      subtitle: account.displayName,
      child: Column(children: rows),
    );
  }

  Widget _buildEnforcementCard(AccountSecurityOverview overview) {
    final enforcement = overview.enforcement;
    final on = enforcement.enabled;
    return _section(
      title: 'Device gate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on ? Icons.lock_outline : Icons.lock_open_outlined,
                size: 18,
                color: on ? AppConstants.success : AppConstants.statusPendingColor,
              ),
              const SizedBox(width: 8),
              Text(
                on ? 'Enforcement ON' : 'Enforcement OFF',
                style: AppConstants.bodyStyle(
                  fontWeight: FontWeight.bold,
                  color: on ? AppConstants.success : AppConstants.statusPendingColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            on
                ? 'Private tables require the device credential, so a device listed '
                      'below without one is being refused its data.'
                : 'Private tables are readable without a device credential right now, '
                      'so nothing below is blocking this account today.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
          if (enforcement.updatedAt != null) ...[
            const SizedBox(height: 8),
            _kv('Last changed', adminDateTime(enforcement.updatedAt)),
          ],
          if (enforcement.updatedBy != null)
            _kv('Changed by', adminShortId(enforcement.updatedBy)),
        ],
      ),
    );
  }

  Widget _buildDevicesCard(AccountSecurityOverview overview) {
    final devices = overview.devices;

    if (devices.isEmpty) {
      return _section(
        title: 'Trusted devices',
        child: Text(
          'No device has ever completed the step-up for this account. A phone '
          'that never finished the emailed-code challenge leaves no row here.',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.7),
            height: 1.35,
          ),
        ),
      );
    }

    return _section(
      title: 'Trusted devices',
      subtitle: '${devices.length} on record',
      child: Column(
        children: [
          for (var i = 0; i < devices.length; i++) ...[
            _buildDeviceRow(devices[i]),
            if (i < devices.length - 1) const Divider(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceRow(TrustedDevice device) {
    final hasSecret = device.hasSecret;
    final color = hasSecret ? AppConstants.success : AppConstants.statusPendingColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.phone_android, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device.displayLabel,
                style: AppConstants.bodyStyle(fontWeight: FontWeight.bold),
              ),
            ),
            _badge(
              hasSecret ? 'credential OK' : 'no credential',
              color,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          device.deviceId,
          style: AppConstants.monoStyle(
            fontSize: 10.5,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        _kv('Trusted', adminDateTime(device.trustedAt)),
        _kv('Last seen', adminDateTime(device.lastSeenAt)),
        _kv(
          'Credential minted',
          hasSecret ? adminDateTime(device.secretMintedAt) : 'never',
          valueColor: hasSecret ? null : AppConstants.statusPendingColor,
        ),
      ],
    );
  }

  Widget _buildLockoutsCard(AccountSecurityOverview overview) {
    final lockouts = overview.lockouts;
    return _section(
      title: 'Password lockouts',
      subtitle: lockouts.isEmpty ? null : '${lockouts.length} on record',
      child: lockouts.isEmpty
          ? Text(
              'No failed-password lockout has been recorded for this account.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            )
          : Column(
              children: [
                for (final lock in lockouts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _badge(
                              lock.status ?? 'unknown',
                              lock.isActiveAt(_now)
                                  ? AppConstants.error
                                  : AppConstants.secondary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            if (lock.attemptCount != null)
                              Text(
                                '${lock.attemptCount} attempts',
                                style: AppConstants.monoStyle(
                                  fontSize: 11,
                                  color: AppConstants.secondary.withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _kv('Failed at', adminDateTime(lock.failedAt)),
                        _kv(
                          'Locked until',
                          adminDateTime(lock.lockedUntil),
                          valueColor: lock.isActiveAt(_now) ? AppConstants.error : null,
                        ),
                        if (lock.userAgent != null) _kv('From', lock.userAgent!),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildTimelineCard(AccountSecurityOverview overview) {
    final events = overview.events;
    final codeEmails = overview.codeEmails.length;

    return _section(
      title: 'Sign-in & code timeline',
      subtitle: events.isEmpty ? null : '${events.length} events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            codeEmails == 0
                ? 'No code has been emailed to this account according to the auth '
                      'event log.'
                : '$codeEmails code(s) emailed, judging by when the auth server '
                      'accepted the send request.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
          if (events.isEmpty) const SizedBox(height: 0) else const SizedBox(height: 12),
          for (var i = 0; i < events.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: events[i].isCodeSent
                          ? AppConstants.primary
                          : AppConstants.borderGray,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        events[i].label,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${adminDateTime(events[i].at)}'
                        '${events[i].ipAddress != null ? ' · ${events[i].ipAddress}' : ''}',
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (i < events.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildCaveatsCard(AccountSecurityOverview overview) {
    if (overview.cannotAnswer.isEmpty) return const SizedBox.shrink();
    return _card(
      color: AppConstants.creamDeep.withValues(alpha: 0.5),
      borderColor: AppConstants.borderGray.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppConstants.secondary),
              const SizedBox(width: 8),
              Text(
                'What this report cannot tell you',
                style: AppConstants.bodyStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final caveat in overview.cannotAnswer)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      caveat,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.75),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── small building blocks ──────────────────────────────────────────

  Widget _section({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    required Color color,
    required Color borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _kv(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppConstants.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppConstants.monoStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _severityColor(SecuritySeverity severity) {
    switch (severity) {
      case SecuritySeverity.blocking:
        return AppConstants.error;
      case SecuritySeverity.warning:
        return AppConstants.statusPendingColor;
      case SecuritySeverity.info:
        return AppConstants.primary;
    }
  }

  IconData _severityIcon(SecuritySeverity severity) {
    switch (severity) {
      case SecuritySeverity.blocking:
        return Icons.error_outline;
      case SecuritySeverity.warning:
        return Icons.warning_amber_outlined;
      case SecuritySeverity.info:
        return Icons.info_outline;
    }
  }

  String _severityLabel(SecuritySeverity severity) {
    switch (severity) {
      case SecuritySeverity.blocking:
        return 'blocks sign-in';
      case SecuritySeverity.warning:
        return 'likely cause';
      case SecuritySeverity.info:
        return 'for context';
    }
  }
}
