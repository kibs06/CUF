import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/account_manager.dart';

/// Screen for switching between multiple logged-in accounts on the device.
///
/// Shows all stored accounts with the active one highlighted, allows
/// switching instantly (no password required), adding a new account
/// (goes through full login flow), and removing accounts from the device.
class AccountSwitcherScreen extends StatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  State<AccountSwitcherScreen> createState() => _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends State<AccountSwitcherScreen> {
  final AccountManager _manager = AccountManager.instance;
  List<AccountEntry> _accounts = [];
  String? _activeId;
  bool _loading = true;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    final accounts = await _manager.getAccounts();
    final activeId = await _manager.getActiveAccountId();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _activeId = activeId;
      _loading = false;
    });
  }

  Future<void> _switchAccount(AccountEntry account) async {
    if (account.userId == _activeId || _switching) return;

    setState(() => _switching = true);

    try {
      final result = await _manager.switchToAccount(account.userId);

      if (!mounted) return;

      if (result == null) {
        // Token expired — account was removed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Session for ${account.email} has expired. Please sign in again.',
            ),
            backgroundColor: AppConstants.error,
          ),
        );
        await _loadAccounts();
        return;
      }

      // Refresh the AuthProvider with the new user
      final auth = context.read<AuthProvider>();
      await auth.refreshAfterSwitch();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${account.email}'),
          backgroundColor: AppConstants.success,
        ),
      );

      // Pop back to settings (which will refresh)
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to switch account: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _removeAccount(AccountEntry account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          'Remove Account?',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        content: Text(
          'Remove ${account.email} from this device? '
          'You can sign in again later.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: AppConstants.bodyStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final wasActive = account.userId == _activeId;
    await _manager.removeAccount(account.userId);

    if (wasActive) {
      // If we removed the active account, switch to the next one
      final remaining = await _manager.getAccounts();
      if (!mounted) return;
      if (remaining.isNotEmpty) {
        final auth = context.read<AuthProvider>();
        final result = await _manager.switchToAccount(remaining.first.userId);
        if (result != null) {
          await auth.refreshAfterSwitch();
        }
      } else {
        // No accounts left — sign out
        final auth = context.read<AuthProvider>();
        await auth.logout();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${account.email} removed from this device'),
      ),
    );
    await _loadAccounts();
  }

  void _addAccount() {
    // Pop back to settings, then navigate to login
    Navigator.of(context).pop('add_account');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Switch Account',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _accounts.isEmpty
                      ? _buildEmptyState()
                      : _buildAccountList(),
                ),
                // Add Account button at bottom
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_outlined, size: 20),
                      label: Text(
                        'Add Account',
                        style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppConstants.primary),
                        foregroundColor: AppConstants.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _addAccount,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No other accounts',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add another account to switch between them instantly.',
              style: AppConstants.bodyStyle(
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _accounts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final account = _accounts[index];
        final isActive = account.userId == _activeId;
        return _buildAccountCard(account, isActive: isActive);
      },
    );
  }

  Widget _buildAccountCard(
    AccountEntry account, {
    required bool isActive,
  }) {
    final initials = (account.fullName ?? account.email)
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Dismissible(
      key: Key(account.userId),
      direction: _accounts.length > 1
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) async {
        await _removeAccount(account);
        return false; // We handle removal ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppConstants.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.delete_outline,
          color: AppConstants.error,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isActive ? null : () => _switchAccount(account),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppConstants.primary
                    : AppConstants.borderGray,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      AppConstants.primary.withValues(alpha: 0.1),
                  backgroundImage: account.avatarUrl != null
                      ? NetworkImage(account.avatarUrl!)
                      : null,
                  child: account.avatarUrl == null
                      ? Text(
                          initials,
                          style: AppConstants.bodyStyle(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.fullName ?? 'User',
                        style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.email,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Active indicator or chevron
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppConstants.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Active',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primary,
                      ),
                    ),
                  )
                else if (_switching)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.swap_horiz,
                    color: AppConstants.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
