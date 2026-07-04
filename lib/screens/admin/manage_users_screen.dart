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
        final success = await Provider.of<OrderProvider>(context, listen: false).deactivateUser(userId); // deactivates to customer
        if (roleValue != AppConstants.roleCustomer) {
          // If advancing to seller or admin
          if (roleValue == AppConstants.roleSeller) {
            await Provider.of<OrderProvider>(context, listen: false).approveSeller(userId);
          } else {
            // mock custom role assignment
            final op = Provider.of<OrderProvider>(context, listen: false);
            final index = op.profiles.indexWhere((p) => p['id'] == userId);
            if (index != -1) {
              op.profiles[index]['role'] = AppConstants.roleAdmin;
              op.notifyListeners();
            }
          }
        }
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
                              final userId = profile['id'];

                              Color roleBgColor;
                              Color roleTextColor;
                              if (role == AppConstants.roleAdmin) {
                                roleBgColor = AppConstants.error.withOpacity(0.15);
                                roleTextColor = AppConstants.error;
                              } else if (role == AppConstants.roleSeller) {
                                roleBgColor = Colors.amber.withOpacity(0.15);
                                roleTextColor = const Color(0xFFC47D00);
                              } else {
                                roleBgColor = Colors.grey.withOpacity(0.15);
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
                                        backgroundColor: AppConstants.primary.withOpacity(0.1),
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
                                          role.toUpperCase(),
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
