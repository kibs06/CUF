import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/update_info.dart';
import '../../providers/auth_provider.dart';
import '../../providers/message_provider.dart';
import '../../providers/seller_notification_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/sole_bottom_nav.dart';
import '../../widgets/update_overlay.dart';
import '../../widgets/chat/chat_view.dart';
import 'seller_dashboard_screen.dart';
import 'pos_screen.dart';
import 'manage_products_screen.dart';
import 'manage_orders_screen.dart';
import 'order_detail_screen.dart';
import 'custom_orders_screen.dart';
import 'seller_inbox_screen.dart';
import 'seller_notification_center_screen.dart';
import 'pos_history_screen.dart';
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
  late final PageController _pageController;

  final List<Widget> _screens = [
    const SellerDashboardScreen(hideAppBar: true),
    const POSScreen(hideAppBar: true),
    const ManageProductsScreen(hideAppBar: true),
    const ManageOrdersScreen(hideAppBar: true),
    const ProfileScreen(hideAppBar: true),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Wire up push notification deep-link for sellers
    PushNotificationService.instance.onNavigateToChat =
        (conversationId, storeName) {
          if (!mounted) return;
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

    PushNotificationService
        .instance
        .onNavigateToScreen = (screen, referenceId) {
      if (!mounted) return;
      switch (screen) {
        case 'seller_order_detail':
          if (referenceId != null) {
            Supabase.instance.client
                .from('orders')
                .select(
                  '*, profiles!orders_customer_id_fkey(full_name, email), order_items(*, products(name))',
                )
                .eq('id', referenceId)
                .single()
                .then((data) {
                  if (mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(order: data),
                      ),
                    );
                  }
                })
                .catchError((e) {
                  debugPrint('[Push] Failed to fetch order for deep-link: $e');
                });
          }
          break;
        case 'seller_product_detail':
          setState(() => _currentIndex = 2); // Products tab
          break;
        case 'seller_custom_order':
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CustomOrdersScreen()));
          break;
      }
    };
  }

  void _showUpdateOverlay(UpdateInfo update) {
    final provider = context.read<UpdateProvider>();
    provider.markUpdateOverlayShown();
    UpdateOverlay.show(context, update: update);
  }

  @override
  Widget build(BuildContext context) {
    // Show update overlay once if a newer version is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<UpdateProvider>();
      if (provider.shouldShowUpdateOverlay) {
        _showUpdateOverlay(provider.latestUpdate!);
      }
    });

    return Scaffold(
      backgroundColor: SellerTheme.creamBg,
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: SellerTheme.cardBorder)),
        ),
        // Same sliding-pill nav as the customer/admin shells, tinted with
        // the seller palette (no tap ripple/highlight by default).
        child: SoleBottomNav(
          role: AppConstants.roleSeller,
          currentIndex: _currentIndex,
          onTap: (index) {
            _pageController.jumpToPage(index);
          },
          backgroundColor: SellerTheme.card,
          activeColor: SellerTheme.rustDeep,
          inactiveColor: SellerTheme.textMuted,
          // Keep the seller's signature amber indicator, now sliding.
          pillColor: SellerTheme.amberBg,
          barHeight: 65,
        ),
      ),
    );
  }

  // ─── SHARED APP BAR ─────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final auth = context.watch<AuthProvider>();
    final hour = DateTime.now().hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    final firstName = auth.displayName.split(' ').first;

    switch (_currentIndex) {
      case 0: // Dashboard
        return AppBar(
          backgroundColor: AppConstants.secondary,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CUFMAI',
                style: AppConstants.bodyStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$greeting, $firstName',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: Colors.white.withAlpha(180),
                ),
              ),
            ],
          ),
          actions: [
            _buildMessageIcon(),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildNotificationBell(),
            ),
          ],
        );
      case 1: // POS
        return AppBar(
          backgroundColor: AppConstants.secondary,
          elevation: 0,
          automaticallyImplyLeading: false,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            'POS',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'History',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PosHistoryScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.history, color: Colors.white),
            ),
          ],
        );
      case 2: // Products
        return AppBar(
          backgroundColor: AppConstants.secondary,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Products',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      case 3: // Orders
        return AppBar(
          backgroundColor: AppConstants.secondary,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Orders',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      case 4: // Profile
        return AppBar(
          backgroundColor: AppConstants.surfaceLight,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'My Profile',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          actions: [
            IconButton(
              onPressed: null,
              tooltip: 'Settings',
              icon: const Icon(
                Icons.settings_outlined,
                color: AppConstants.secondary,
              ),
            ),
          ],
        );
      default:
        return AppBar(
          backgroundColor: AppConstants.secondary,
          elevation: 0,
          automaticallyImplyLeading: false,
        );
    }
  }

  // ─── Message Icon with Badge ──────────────────────────────────
  Widget _buildMessageIcon() {
    final msgProvider = context.watch<MessageProvider>();
    final badge = msgProvider.unreadBadge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
          onPressed: () async {
            await msgProvider.refreshInbox();
            if (!mounted || !context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SellerInboxScreen(),
              ),
            );
          },
        ),
        if (badge.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppConstants.statusConfirmedColor,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // ─── Notification Bell with Badge ──────────────────────────────
  Widget _buildNotificationBell() {
    final notifProvider = context.watch<SellerNotificationProvider>();
    final badge = notifProvider.unreadBadge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () async {
            await notifProvider.refreshNotifications();
            if (!mounted || !context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SellerNotificationCenterScreen(),
              ),
            );
          },
        ),
        if (badge.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppConstants.statusConfirmedColor,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
