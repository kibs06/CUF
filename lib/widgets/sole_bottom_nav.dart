import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleBottomNav extends StatelessWidget {
  final String role;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Number of unread notifications for the bell icon badge.
  /// When 0, no badge is shown. Values > 9 display as "9+".
  final int notificationUnreadCount;

  const SoleBottomNav({
    super.key,
    required this.role,
    required this.currentIndex,
    required this.onTap,
    this.notificationUnreadCount = 0,
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
        return [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppConstants.primary),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: AppConstants.primary),
            label: 'Store',
          ),
          NavigationDestination(
            icon: _NotificationBadgeIcon(
              icon: Icons.notifications_outlined,
              unreadCount: notificationUnreadCount,
            ),
            selectedIcon: _NotificationBadgeIcon(
              icon: Icons.notifications,
              unreadCount: notificationUnreadCount,
              selected: true,
            ),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppConstants.primary),
            label: 'Profile',
          ),
        ];
    }
  }
}

/// Wraps a notification icon with an optional unread-count badge.
///
/// The badge sits at the top-right of the icon and:
/// - Is hidden when [unreadCount] is 0.
/// - Shows the raw number up to 9, then "9+" for higher counts.
/// - Uses a red background consistent with the app's unread-dot color.
class _NotificationBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int unreadCount;
  final bool selected;

  const _NotificationBadgeIcon({
    required this.icon,
    required this.unreadCount,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasBadge = unreadCount > 0;
    final badgeText = unreadCount > 9 ? '9+' : '$unreadCount';

    return Semantics(
      label: hasBadge
          ? 'Notifications, $unreadCount unread'
          : 'Notifications',
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            icon,
            color: selected ? AppConstants.primary : null,
          ),
          if (hasBadge)
            Positioned(
              top: -2,
              right: -6,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppConstants.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
