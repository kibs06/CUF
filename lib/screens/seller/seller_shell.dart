import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/chat/chat_view.dart';
import 'seller_dashboard_screen.dart';
import 'pos_screen.dart';
import 'manage_products_screen.dart';
import 'manage_orders_screen.dart';
import '../shared/profile_screen.dart';

/// Seller shell with 5-tab bottom navigation:
/// Dashboard, POS, Products, Orders, More
class SellerShell extends StatefulWidget {
  const SellerShell({super.key});

  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const SellerDashboardScreen(),
    const POSScreen(),
    const ManageProductsScreen(),
    const ManageOrdersScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Wire up push notification deep-link for sellers
    PushNotificationService.instance.onNavigateToChat = (conversationId, storeName) {
      if (!mounted) return;
      // Switch to inbox tab (index 4 is Profile, but we navigate directly)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            conversationId: conversationId,
            viewerRole: 'seller',
            otherPartyName: storeName,
          ),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: _screens.isEmpty
          ? const Center(child: Text('Unable to load screen'))
          : IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppConstants.sellerCardBg,
          indicatorColor: AppConstants.primary.withAlpha(30),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppConstants.primary);
            }
            return IconThemeData(color: Colors.grey.shade500);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppConstants.primary,
              );
            }
            return AppConstants.bodyStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          height: 65,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale),
              label: 'POS',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
