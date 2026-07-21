import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/sole_bottom_nav.dart';
import 'customer_home_screen.dart';
import '../store/store_screen.dart';
import '../notifications_screen.dart';
import '../shared/profile_screen.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const CustomerHomeScreen(),
    const StoreScreen(),
    const NotificationsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: _screens.isEmpty
          ? const Center(child: Text('Unable to load screen'))
          : IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Consumer<NotificationProvider>(
        builder: (context, notifProvider, _) {
          return SoleBottomNav(
            role: AppConstants.roleCustomer,
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            notificationUnreadCount: notifProvider.totalUnread,
          );
        },
      ),
    );
  }
}
