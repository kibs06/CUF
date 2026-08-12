import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/sole_bottom_nav.dart';
import '../../widgets/chat/chat_view.dart';
import 'seller_dashboard_screen.dart';
import 'pos_screen.dart';
import 'manage_products_screen.dart';
import 'manage_orders_screen.dart';
import 'order_detail_screen.dart';
import 'custom_orders_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SellerTheme.creamBg,
      body: _screens.isEmpty
          ? const Center(child: Text('Unable to load screen'))
          : IndexedStack(index: _currentIndex, children: _screens),
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
            setState(() => _currentIndex = index);
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
}
