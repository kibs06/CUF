import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleBottomNav extends StatelessWidget {
  final String role;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SoleBottomNav({
    super.key,
    required this.role,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final List<NavigationDestination> destinations = _getDestinations();

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: AppConstants.surfaceLight,
      indicatorColor: AppConstants.primary.withValues(alpha: 0.15),
      destinations: destinations,
    );
  }

  List<NavigationDestination> _getDestinations() {
    switch (role) {
      case AppConstants.roleSeller:
        return const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppConstants.primary),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: AppConstants.primary),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale, color: AppConstants.primary),
            label: 'POS',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: AppConstants.primary),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppConstants.primary),
            label: 'Profile',
          ),
        ];
      case AppConstants.roleAdmin:
        return const [
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings, color: AppConstants.primary),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt, color: AppConstants.primary),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.how_to_reg_outlined),
            selectedIcon: Icon(Icons.how_to_reg, color: AppConstants.primary),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart, color: AppConstants.primary),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppConstants.primary),
            label: 'Profile',
          ),
        ];
      case AppConstants.roleCustomer:
      default:
        return const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppConstants.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: AppConstants.primary),
            label: 'Store',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications, color: AppConstants.primary),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppConstants.primary),
            label: 'Profile',
          ),
        ];
    }
  }
}
