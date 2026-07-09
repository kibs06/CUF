import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import 'manage_inventory_screen.dart';
import 'custom_orders_screen.dart';
import 'reports_screen.dart';

class SellerMoreScreen extends StatelessWidget {
  const SellerMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'More',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _menuItem(
            icon: Icons.inventory_2_outlined,
            title: 'Manage Inventory',
            subtitle: 'Track stock levels',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManageInventoryScreen()),
            ),
          ),
          _menuItem(
            icon: Icons.design_services_outlined,
            title: 'Custom Orders',
            subtitle: 'Review customization requests',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomOrdersScreen()),
            ),
          ),
          _menuItem(
            icon: Icons.bar_chart_outlined,
            title: 'Reports & Export',
            subtitle: 'Sales reports and data export',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ReportsScreen())),
          ),
          _menuItem(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Store and account settings',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings coming soon')),
              );
            },
          ),
          const SizedBox(height: 24),
          const Divider(),
          _menuItem(
            icon: Icons.logout,
            title: 'Log Out',
            subtitle: 'Sign out of your account',
            iconColor: AppConstants.error,
            textColor: AppConstants.error,
            onTap: () async {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.error,
                      ),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await auth.logout();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color iconColor = AppConstants.primary,
    Color textColor = AppConstants.secondary,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppConstants.sellerShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: AppConstants.bodyStyle(
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.chevron_right,
          color: AppConstants.borderGray,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      ),
    );
  }
}
