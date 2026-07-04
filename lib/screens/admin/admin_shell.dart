import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../widgets/sole_bottom_nav.dart';
import 'admin_dashboard_screen.dart';
import 'manage_users_screen.dart';
import 'seller_approval_screen.dart';
import 'monitor_products_screen.dart';
import '../shared/profile_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const AdminDashboardScreen(),
    const ManageUsersScreen(),
    const SellerApprovalScreen(),
    const MonitorProductsScreen(),
    const ProfileScreen(), // Share unified ProfileScreen for tester role changer
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: _screens.isEmpty
          ? const Center(child: Text('Unable to load screen'))
          : IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: SoleBottomNav(
        role: AppConstants.roleAdmin,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
