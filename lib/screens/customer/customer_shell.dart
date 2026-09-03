import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../models/update_info.dart';
import '../../providers/notification_provider.dart';
import '../../providers/update_provider.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/sole_bottom_nav.dart';
import '../../widgets/update_overlay.dart';
import 'customer_home_screen.dart';
import '../store/store_screen.dart';
import '../notifications_screen.dart';
import '../shared/profile_screen.dart';
import '../shared/settings_screen.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  final List<Widget> _screens = [
    const CustomerHomeScreen(hideAppBar: true),
    const StoreScreen(hideAppBar: true),
    const NotificationsScreen(hideAppBar: true),
    const ProfileScreen(hideAppBar: true),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showUpdateOverlay(UpdateInfo update) {
    final provider = context.read<UpdateProvider>();
    provider.markUpdateOverlayShown();
    UpdateOverlay.show(context, update: update);
  }

  @override
  Widget build(BuildContext context) {
    // Listen for late-arriving update checks (e.g. slow network).
    // When the provider finishes checking and finds an update, show
    // the overlay once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<UpdateProvider>();
      if (provider.shouldShowUpdateOverlay) {
        _showUpdateOverlay(provider.latestUpdate!);
      }
    });

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: _buildAppBar(),
      body: _screens.isEmpty
          ? const Center(child: Text('Unable to load screen'))
          : PageView(
              controller: _pageController,
              physics: const PageScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              children: _screens,
            ),
      bottomNavigationBar: Consumer<NotificationProvider>(
        builder: (context, notifProvider, _) {
          return SoleBottomNav(
            role: AppConstants.roleCustomer,
            currentIndex: _currentIndex,
            onTap: (index) {
              _pageController.jumpToPage(index);
            },
            notificationUnreadCount: notifProvider.totalUnread,
          );
        },
      ),
    );
  }

  // ─── SHARED APP BAR ─────────────────────────────────────────────
  PreferredSizeWidget? _buildAppBar() {
    switch (_currentIndex) {
      case 0: // Home — no AppBar (full-bleed hero design)
        return null;
      case 1: // Store
        return AppBar(
          title: Text(
            'Stores',
            style: AppConstants.headlineStyle(fontSize: 22),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: const [CartIconButton()],
        );
      case 2: // Notifications
        return AppBar(
          title: Text(
            'Notifications',
            style: AppConstants.headlineStyle(fontSize: 20),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            if (context.watch<NotificationProvider>().totalUnread > 0)
              TextButton(
                onPressed: () =>
                    context.read<NotificationProvider>().markAllAsRead(),
                child: Text(
                  'Mark all read',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.primary,
                  ),
                ),
              ),
          ],
        );
      case 3: // Profile
        return AppBar(
          title: Text(
            'My Profile',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          backgroundColor: AppConstants.surfaceLight,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              tooltip: 'Settings',
              icon: const Icon(
                Icons.settings_outlined,
                color: AppConstants.secondary,
              ),
            ),
          ],
        );
      default:
        return null;
    }
  }
}
