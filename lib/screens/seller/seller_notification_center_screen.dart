import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/seller_notification_provider.dart';
import '../../services/seller_notification_service.dart';
import 'manage_orders_screen.dart';
import 'custom_orders_screen.dart';
import 'manage_inventory_screen.dart';
import 'order_detail_screen.dart';
import 'seller_inbox_screen.dart';

/// Seller Notification Center — pushed from the Dashboard bell icon.
///
/// Shows all seller notifications (new orders, stale orders, low stock,
/// custom requests) with tap-to-navigate and mark-as-read.
class SellerNotificationCenterScreen extends StatefulWidget {
  const SellerNotificationCenterScreen({super.key});

  @override
  State<SellerNotificationCenterScreen> createState() =>
      _SellerNotificationCenterScreenState();
}

class _SellerNotificationCenterScreenState
    extends State<SellerNotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SellerNotificationProvider>().loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SellerNotificationProvider>();

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Notifications',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (provider.hasUnread)
            TextButton(
              onPressed: () => provider.markAllAsRead(),
              child: Text(
                'Mark all read',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
        ],
      ),
      body: provider.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            )
          : provider.notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppConstants.primary,
                  onRefresh: () => provider.loadNotifications(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: provider.notifications.length,
                    itemBuilder: (context, index) {
                      final notif = provider.notifications[index];
                      return _NotificationRow(
                        notification: notif,
                        onTap: () => _handleTap(provider, notif),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _handleTap(
    SellerNotificationProvider provider,
    SellerNotification notif,
  ) async {
    // Mark as read
    if (!notif.isRead) {
      provider.markAsRead(notif.id);
    }

    if (!mounted) return;

    // Navigate based on type and reference_id
    switch (notif.type) {
      case 'new_order':
      case 'stale_order':
        if (notif.referenceId != null) {
          _navigateToOrderDetail(notif.referenceId!);
        }
        break;
      case 'low_stock':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ManageInventoryScreen()),
        );
        break;
      case 'custom_order_request':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomOrdersScreen()),
        );
        break;
      case 'new_message':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SellerInboxScreen()),
        );
        break;
    }
  }

  void _navigateToOrderDetail(String orderId) async {
    // Fetch the order and navigate to detail screen
    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select('*, profiles!orders_customer_id_fkey(full_name, email), order_items(*, products(name))')
          .eq('id', orderId)
          .single();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(order: data),
          ),
        );
      }
    } catch (e) {
      // Fallback: navigate to orders list if order not found
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ManageOrdersScreen()),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none,
                size: 34,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No notifications yet',
              style: AppConstants.bodyStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'New orders, stock alerts, and custom requests\nwill appear here.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Notification Row
// ══════════════════════════════════════════════════════════════════

class _NotificationRow extends StatelessWidget {
  final SellerNotification notification;
  final VoidCallback onTap;

  const _NotificationRow({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: notification.isRead
                ? AppConstants.sellerCardBg
                : AppConstants.statusConfirmedColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppConstants.sellerShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Leading icon in tinted circle ──────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _typeIcon,
                  size: 20,
                  color: _typeColor,
                ),
              ),
              const SizedBox(width: 12),

              // ── Title + body + timestamp ───────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: notification.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                              color: AppConstants.statusConfirmedColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.relativeTime,
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _typeIcon {
    switch (notification.type) {
      case 'new_order':
        return Icons.receipt_long_outlined;
      case 'stale_order':
        return Icons.schedule_outlined;
      case 'low_stock':
        return Icons.warning_amber_outlined;
      case 'custom_order_request':
        return Icons.design_services_outlined;
      case 'new_message':
        return Icons.chat_bubble_outline;
      default:
        return Icons.notifications_none;
    }
  }

  Color get _typeColor {
    switch (notification.type) {
      case 'new_order':
        return AppConstants.statusConfirmedColor; // blue
      case 'stale_order':
        return AppConstants.statusPendingColor; // amber
      case 'low_stock':
        return AppConstants.lowStockColor; // red
      case 'custom_order_request':
        return AppConstants.statusReadyColor; // brand
      case 'new_message':
        return AppConstants.statusConfirmedColor; // blue
      default:
        return AppConstants.primary;
    }
  }
}
