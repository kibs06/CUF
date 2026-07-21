import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../models/app_notification.dart';
import '../models/notification_category.dart';
import '../providers/notification_provider.dart';
import '../widgets/sole_card.dart';
import '../widgets/chat/chat_view.dart';
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

  /// IDs of notifications currently visible (respecting tab + category filter).
  List<String> _visibleIds(NotificationProvider provider) {
    final orderType = _tabOrderTypes[_tabController.index];
    return provider.notifications
        .where((n) {
          if (_categoryFilter != null && n.category != _categoryFilter) return false;
          if (orderType != null && n.orderType != orderType) return false;
          return true;
        })
        .map((n) => n.id)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: provider.isSelectionMode
          ? _buildSelectionAppBar(provider)
          : _buildNormalAppBar(provider),
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
                      child: SlidableAutoCloseBehavior(
                        closeWhenOpened: true,
                        closeWhenTapped: true,
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

                            return _NotificationSlidable(
                              notification: notif,
                              index: index,
                              isSelectionMode: provider.isSelectionMode,
                              isSelected: provider.selectedIds.contains(notif.id),
                              onTap: provider.isSelectionMode
                                  ? () => provider.toggleSelection(notif.id)
                                  : () => _handleTap(provider, notif),
                              onLongPress: provider.isSelectionMode
                                  ? null
                                  : () {
                                      provider.enterSelectionMode();
                                      provider.toggleSelection(notif.id);
                                    },
                              onDelete: () => _handleDelete(provider, notif, index),
                              onToggleRead: () {
                                if (notif.isRead) {
                                  provider.markAsUnread(notif.id);
                                } else {
                                  provider.markAsRead(notif.id);
                                }
                              },
                              onView: () => _handleTap(provider, notif),
                            );
                          },
                        ),
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

    // ── Message notification: deep-link to ChatView ──────────────
    if (notif.isMessageNotification && notif.conversationId != null) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatView(
              conversationId: notif.conversationId!,
              viewerRole: 'customer',
              otherPartyName: notif.storeName ?? 'Store',
            ),
          ),
        );
      }
      return;
    }

    // ── Order notification: fetch full order data → tracking ──────
    if (notif.orderId != null) {
      try {
        final orderIdStr = notif.orderId!;
        // orders.id is BIGINT — try parsing as int, but fall back to
        // string equality if it's a UUID or non-numeric value.
        final data = await Supabase.instance.client
            .from('orders')
            .select('*, order_items(*, products(name, product_images(image_url, display_order)))')
            .eq('id', int.tryParse(orderIdStr) ?? orderIdStr)
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

  void _handleDelete(
    NotificationProvider provider,
    AppNotification notif,
    int index,
  ) async {
    // Optimistic remove
    provider.deleteNotification(notif.id);

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Notification deleted'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppConstants.primary,
          onPressed: () {
            provider.restoreNotification(notif, index);
          },
        ),
      ),
    );
  }

  // ── App Bars ─────────────────────────────────────────────────

  PreferredSizeWidget _buildNormalAppBar(NotificationProvider provider) {
    return AppBar(
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
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(NotificationProvider provider) {
    final visible = _visibleIds(provider);
    final allVisibleSelected = visible.isNotEmpty &&
        visible.every((id) => provider.selectedIds.contains(id));

    return AppBar(
      backgroundColor: AppConstants.primary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () => provider.exitSelectionMode(),
      ),
      title: Text(
        '${provider.selectedCount} selected',
        style: AppConstants.bodyStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      actions: [
        // Select all
        IconButton(
          icon: Icon(
            allVisibleSelected
                ? Icons.deselect_outlined
                : Icons.select_all_outlined,
            color: Colors.white,
          ),
          tooltip: allVisibleSelected ? 'Deselect all' : 'Select all',
          onPressed: () {
            if (allVisibleSelected) {
              provider.clearSelection();
            } else {
              provider.selectAll(visible);
            }
          },
        ),
        // Mark as read
        IconButton(
          icon: const Icon(Icons.mark_email_read_outlined, color: Colors.white),
          tooltip: 'Mark as read',
          onPressed: provider.selectedCount > 0
              ? () async {
                  await provider.markSelectedRead();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marked as read')),
                    );
                  }
                }
              : null,
        ),
        // Delete
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white),
          tooltip: 'Delete',
          onPressed: provider.selectedCount > 0
              ? () => _confirmBulkDelete(provider)
              : null,
        ),
      ],
    );
  }

  Future<void> _confirmBulkDelete(NotificationProvider provider) async {
    final count = provider.selectedCount;
    if (count <= 1) {
      final deleted = await provider.deleteSelected();
      if (mounted && deleted.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count notification deleted'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              textColor: AppConstants.primary,
              onPressed: () => provider.undoDeleteSelected(deleted),
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $count notifications?'),
        content: const Text('This action can be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await provider.deleteSelected();
      if (mounted && deleted.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count notifications deleted'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              textColor: AppConstants.primary,
              onPressed: () => provider.undoDeleteSelected(deleted),
            ),
          ),
        );
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

class _NotificationSlidable extends StatelessWidget {
  final AppNotification notification;
  final int index;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onToggleRead;
  final VoidCallback onView;

  const _NotificationSlidable({
    required this.notification,
    required this.index,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onTap,
    this.onLongPress,
    required this.onDelete,
    required this.onToggleRead,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    // In selection mode, disable slidable and just show the card with checkbox
    if (isSelectionMode) {
      return _NotificationCardContent(
        notification: notification,
        onTap: onTap,
        isSelectionMode: true,
        isSelected: isSelected,
      );
    }

    return Slidable(
      key: ValueKey(notification.id),
      // Swipe right → Delete (startActionPane)
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        dismissible: DismissiblePane(
          onDismissed: () {
            HapticFeedback.lightImpact();
            onDelete();
          },
        ),
        children: [
          SlidableAction(
            onPressed: (_) {
              HapticFeedback.lightImpact();
              onDelete();
            },
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      // Swipe left → Mark Read + View (endActionPane)
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) {
              HapticFeedback.selectionClick();
              onToggleRead();
            },
            backgroundColor: AppConstants.primary,
            foregroundColor: Colors.white,
            icon: notification.isRead
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
            label: notification.isRead ? 'Unread' : 'Read',
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
          ),
          SlidableAction(
            onPressed: (_) {
              HapticFeedback.selectionClick();
              onView();
            },
            backgroundColor: AppConstants.secondary,
            foregroundColor: Colors.white,
            icon: notification.isMessageNotification
                ? Icons.chat_bubble_outline
                : Icons.local_shipping_outlined,
            label: notification.isMessageNotification ? 'Chat' : 'View',
          ),
        ],
      ),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: _NotificationCardContent(
          notification: notification,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _NotificationCardContent extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final bool isSelectionMode;
  final bool isSelected;

  const _NotificationCardContent({
    required this.notification,
    required this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
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
              // ── Selection checkbox or Leading icon ─────────────
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? AppConstants.primary
                        : AppConstants.secondary.withValues(alpha: 0.3),
                    size: 24,
                  ),
                )
              else
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
                    // ── Batched message previews or single message ──
                    if (notification.isBatched && notification.previews.isNotEmpty)
                      _buildBatchedPreviews()
                    else
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
      case NotificationCategory.message:
        return Icons.chat_bubble_outline;
    }
  }

  /// Build the batched message preview stack for message notifications
  /// that have multiple messages folded in (message_count > 1).
  Widget _buildBatchedPreviews() {
    final previews = notification.previews;
    final count = notification.messageCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Count badge
        Text(
          '$count new messages',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppConstants.secondary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        // Preview snippets (newest first, max 3)
        for (var i = 0; i < previews.length && i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${previews[i].sender}: ${previews[i].text}',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
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
      case NotificationCategory.message:
        return const Color(0xFF4ECDC4); // celadon teal
    }
  }
}
