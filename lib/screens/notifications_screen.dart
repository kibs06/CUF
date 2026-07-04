import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../models/app_notification.dart';
import '../models/notification_category.dart';
import '../providers/notification_provider.dart';
import '../widgets/sole_card.dart';
import 'customer/tracking_screen.dart';

/// Notifications feed screen — the primary entry point via the bottom nav
/// "Notifications" tab. Also reachable from the profile screen's icon row.
///
/// Tabs filter by order source: All / Catalog / Custom.
/// Tapping a card marks it read and navigates to the order tracking screen.
/// Can be opened with an optional [initialCategory] filter (e.g. from the
/// profile screen's icon row) — this pre-selects a category within the
/// current tab.
class NotificationsScreen extends StatefulWidget {
  /// If non-null, the feed highlights notifications matching this category.
  final NotificationCategory? initialCategory;

  const NotificationsScreen({super.key, this.initialCategory});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 0 = All, 1 = Catalog, 2 = Custom
  static const _tabOrderTypes = <String?>[null, 'catalog', 'custom'];

  /// Active category filter (from profile screen icon tap). null = no filter.
  NotificationCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.initialCategory;

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentTab();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadCurrentTab();
  }

  void _loadCurrentTab() {
    final orderType = _tabOrderTypes[_tabController.index];
    context.read<NotificationProvider>().loadNotifications(
          categoryFilter: _categoryFilter,
          orderTypeFilter: orderType,
        );
  }

  /// Clear the category filter (e.g. when the user manually switches tabs).
  void _clearCategoryFilter() {
    if (_categoryFilter != null) {
      setState(() => _categoryFilter = null);
      _loadCurrentTab();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          if (provider.totalUnread > 0)
            TextButton(
              onPressed: () => provider.markAllAsRead(),
              child: Text(
                'Mark all read',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.primary,
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppConstants.primary,
          labelColor: AppConstants.primary,
          unselectedLabelColor: AppConstants.secondary.withValues(alpha: 0.5),
          labelStyle: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          onTap: (_) => _clearCategoryFilter(),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Catalog'),
            Tab(text: 'Custom'),
          ],
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primary,
                  ),
                )
              : provider.notifications.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: AppConstants.primary,
                      onRefresh: () async => _loadCurrentTab(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: provider.notifications.length,
                        itemBuilder: (context, index) {
                          final notif = provider.notifications[index];

                          // If a category filter is active, only show matching
                          if (_categoryFilter != null &&
                              notif.category != _categoryFilter) {
                            return const SizedBox.shrink();
                          }

                          return _NotificationCard(
                            notification: notif,
                            onTap: () => _handleTap(provider, notif),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }

  Future<void> _handleTap(
    NotificationProvider provider,
    AppNotification notif,
  ) async {
    // Mark as read
    if (!notif.isRead) {
      provider.markAsRead(notif.id);
    }

    // Fetch full order data before navigating to tracking
    if (notif.orderId != null) {
      try {
        final data = await Supabase.instance.client
            .from('orders')
            .select('*, order_items(*, products(name))')
            .eq('id', int.parse(notif.orderId!))
            .single();
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(order: data),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load order details: $e')),
          );
        }
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 48,
            color: AppConstants.borderGray,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: AppConstants.bodyStyle(
              fontSize: 16,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Order updates will appear here',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Notification Card
// ══════════════════════════════════════════════════════════════════

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: SoleCard(
          color: notification.isRead
              ? Colors.white
              : AppConstants.primary.withValues(alpha: 0.04),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Leading icon in tinted circle ──────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _categoryColor(notification.category)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _categoryIcon(notification.category),
                  size: 20,
                  color: _categoryColor(notification.category),
                ),
              ),
              const SizedBox(width: 12),

              // ── Title + message + timestamp ────────────────────
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
                              fontWeight: FontWeight.bold,
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
                              color: AppConstants.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
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

  IconData _categoryIcon(NotificationCategory cat) {
    switch (cat) {
      case NotificationCategory.unpaid:
        return Icons.credit_card_outlined;
      case NotificationCategory.processing:
        return Icons.inventory_2_outlined;
      case NotificationCategory.shipped:
        return Icons.local_shipping_outlined;
      case NotificationCategory.review:
        return Icons.chat_bubble_outline;
      case NotificationCategory.returns:
        return Icons.assignment_return_outlined;
    }
  }

  Color _categoryColor(NotificationCategory cat) {
    switch (cat) {
      case NotificationCategory.unpaid:
        return const Color(0xFFF59E0B); // amber
      case NotificationCategory.processing:
        return const Color(0xFF3B82F6); // blue
      case NotificationCategory.shipped:
        return AppConstants.primary; // brand
      case NotificationCategory.review:
        return const Color(0xFF6B8F47); // green
      case NotificationCategory.returns:
        return AppConstants.error; // red
    }
  }
}
