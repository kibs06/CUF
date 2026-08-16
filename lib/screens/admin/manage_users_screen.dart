import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../widgets/sole_card.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadProfiles();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _deactivateUser(String userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text('Reset Role?', style: AppConstants.headlineStyle(fontSize: 18)),
        content: Text('Are you sure you want to reset "$name" to a standard Customer role?', style: AppConstants.bodyStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Reset', style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await Provider.of<OrderProvider>(context, listen: false).deactivateUser(userId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role reset successfully.'), backgroundColor: AppConstants.success),
        );
      }
    }
  }

  /// Permanently deletes a user's account (profile + auth + owned stores).
  /// Only offered for suspended accounts, and only after an explicit
  /// confirmation — the action cannot be undone.
  Future<void> _deleteUserPermanently(String userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          'Delete account permanently?',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        content: Text(
          'This permanently deletes "$name" — their account, store, and '
          'data. This cannot be undone.\n\n'
          'Customer orders placed at their store will be kept but detached '
          'from the store.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete forever', style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Second step: type DELETE to confirm, so a mis-tap on the popup can't
    // destroy an account. (The popup menu is one tap away from this dialog.)
    final deleteController = TextEditingController();
    final typedCorrectly = ValueNotifier<bool>(false);
    final doubleCheck = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text('Are you absolutely sure?', style: AppConstants.headlineStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes the account and cannot be undone. '
                'Type DELETE to confirm.',
                style: AppConstants.bodyStyle(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deleteController,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: AppConstants.bodyStyle(fontSize: 13, color: Colors.black38),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (val) {
                  typedCorrectly.value = val.trim().toUpperCase() == 'DELETE';
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary)),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: typedCorrectly,
              builder: (context, canDelete, _) => FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.error,
                  disabledBackgroundColor: AppConstants.error.withValues(alpha: 0.35),
                ),
                onPressed: canDelete
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text('Delete forever', style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );

    deleteController.dispose();
    if (doubleCheck != true || !mounted) return;

    final success = await Provider.of<OrderProvider>(context, listen: false)
        .deleteUserPermanently(userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Account deleted permanently.' : 'Delete failed. Try again.',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: success ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  void _changeRole(String userId, String currentRole) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text('Modify Account Role', style: AppConstants.headlineStyle(fontSize: 18)),
          children: [
            _roleOption(userId, 'Customer', AppConstants.roleCustomer, currentRole),
            _roleOption(userId, 'Seller', AppConstants.roleSeller, currentRole),
            _roleOption(userId, 'Admin', AppConstants.roleAdmin, currentRole),
          ],
        );
      },
    );
  }

  Widget _roleOption(String userId, String label, String roleValue, String currentRole) {
    final isSelected = currentRole == roleValue;
    return SimpleDialogOption(
      onPressed: () async {
        Navigator.of(context).pop();
        if (isSelected) return;
        final orderProvider = Provider.of<OrderProvider>(context, listen: false);
        await orderProvider.deactivateUser(userId); // deactivates to customer
        if (!mounted) return;
        if (roleValue != AppConstants.roleCustomer) {
          // If advancing to seller or admin
          if (roleValue == AppConstants.roleSeller) {
            await orderProvider.approveSeller(userId);
          } else {
            // mock custom role assignment (local cache only)
            orderProvider.setProfileRole(userId, AppConstants.roleAdmin);
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role updated to $label!'), backgroundColor: AppConstants.success),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppConstants.bodyStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          if (isSelected) const Icon(Icons.check, color: AppConstants.primary, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    
    // Filter profiles based on keyword
    final filteredProfiles = orderProvider.profiles.where((p) {
      final name = (p['full_name'] as String).toLowerCase();
      final email = (p['email'] as String).toLowerCase();
      final keyword = _searchKeyword.toLowerCase();
      return name.contains(keyword) || email.contains(keyword);
    }).toList();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Users Directory',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Column(
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchKeyword = val),
                  style: AppConstants.bodyStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search user accounts by name or email...',
                    hintStyle: AppConstants.bodyStyle(fontSize: 13, color: Colors.black38),
                    prefixIcon: const Icon(Icons.search, color: AppConstants.primary),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
              
              // Profiles list
              Expanded(
                child: orderProvider.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
                    : filteredProfiles.isEmpty
                        ? Center(child: Text('No users match search terms.', style: AppConstants.bodyStyle(color: Colors.black45)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredProfiles.length,
                            itemBuilder: (context, index) {
                              final profile = filteredProfiles[index];
                              final name = profile['full_name'];
                              final email = profile['email'];
                              final String role = profile['role'];
                              final String sellerStatus =
                                  profile['seller_status']?.toString() ?? 'none';
                              final userId = profile['id'];

                              // A pending seller applicant keeps role=customer
                              // until admin approval (that's what locks them
                              // out of the seller shell), so badge them as
                              // PENDING SELLER instead of a plain customer.
                              final bool isPendingSeller =
                                  role == AppConstants.roleCustomer &&
                                  sellerStatus == AppConstants.statusPending;
                              final String badgeLabel = isPendingSeller
                                  ? 'PENDING SELLER'
                                  : role.toUpperCase();

                              Color roleBgColor;
                              Color roleTextColor;
                              if (role == AppConstants.roleAdmin) {
                                roleBgColor = AppConstants.error.withValues(alpha: 0.15);
                                roleTextColor = AppConstants.error;
                              } else if (isPendingSeller) {
                                roleBgColor = Colors.orange.withValues(alpha: 0.14);
                                roleTextColor = const Color(0xFFB45309);
                              } else if (role == AppConstants.roleSeller) {
                                roleBgColor = Colors.amber.withValues(alpha: 0.15);
                                roleTextColor = const Color(0xFFC47D00);
                              } else {
                                roleBgColor = Colors.grey.withValues(alpha: 0.15);
                                roleTextColor = Colors.grey;
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: SoleCard(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: AppConstants.primary.withValues(alpha: 0.1),
                                        backgroundImage: profile['avatar_url'] != null
                                            ? NetworkImage(profile['avatar_url'])
                                            : null,
                                        child: profile['avatar_url'] == null
                                            ? const Icon(Icons.person, color: AppConstants.primary, size: 20)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name, style: AppConstants.bodyStyle(fontWeight: FontWeight.bold)),
                                            Text(email, style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Role Chip
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: roleBgColor,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          badgeLabel,
                                          style: AppConstants.monoStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: roleTextColor,
                                          ),
                                        ),
                                      ),
                                      // Context actions
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 18, color: AppConstants.primary),
                                        onSelected: (val) {
                                          if (val == 'role') {
                                            _changeRole(userId, role);
                                          } else if (val == 'reset') {
                                            _deactivateUser(userId, name);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'role',
                                            child: Text('Edit Role', style: AppConstants.bodyStyle(fontSize: 13)),
                                          ),
                                          PopupMenuItem(
                                            value: 'reset',
                                            child: Text('Reset to Customer', style: AppConstants.bodyStyle(fontSize: 13, color: AppConstants.error)),
                                          ),
                                        ],
                                      ),
                                      // Permanent delete — a dedicated button
                                      // at the far right, isolated from the
                                      // other actions. Only shown for
                                      // suspended accounts (the enforcement
                                      // gate in auth_gate.dart already keeps
                                      // them out of the app), and always
                                      // guarded by the two-step confirmation.
                                      const SizedBox(width: 6),
                                      if (profile['suspended'] == true)
                                        Tooltip(
                                          message: 'Delete permanently',
                                          child: InkWell(
                                            onTap: () =>
                                                _deleteUserPermanently(userId, name),
                                            borderRadius: BorderRadius.circular(10),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: AppConstants.error.withValues(alpha: 0.10),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.delete_forever_outlined,
                                                size: 20,
                                                color: AppConstants.error,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
