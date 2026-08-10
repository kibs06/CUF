import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../providers/seller_notification_provider.dart';
import '../../services/seller_notification_service.dart';
import 'manage_orders_screen.dart';
import 'custom_orders_screen.dart';
import 'manage_products_screen.dart';
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
      appBar: provider.isSelectionMode
          ? _buildSelectionAppBar(provider)
          : _buildNormalAppBar(provider),
      body: provider.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            )
          : provider.notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppConstants.primary,
                  onRefresh: () => provider.loadNotifications(),
                  child: SlidableAutoCloseBehavior(
                    closeWhenOpened: true,
                    closeWhenTapped: true,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: provider.notifications.length,
                      itemBuilder: (context, index) {
                        final notif = provider.notifications[index];
                        return _NotificationSlidable(
                          notification: notif,
                          index: index,
                          isSelectionMode: provider.isSelectionMode,
                          isSelected:
                              provider.selectedIds.contains(notif.id),
                          onTap: provider.isSelectionMode
                              ? () => provider.toggleSelection(notif.id)
                              : () => _handleTap(provider, notif),
                          onLongPress: provider.isSelectionMode
                              ? null
                              : () {
                                  provider.enterSelectionMode();
                                  provider.toggleSelection(notif.id);
                                },
                          onDelete: () =>
                              _handleDelete(provider, notif, index),
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
    );
  }

  // ── App Bars ─────────────────────────────────────────────────

  PreferredSizeWidget _buildNormalAppBar(
      SellerNotificationProvider provider) {
    return AppBar(
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
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
      SellerNotificationProvider provider) {
    final allSelected = provider.notifications.isNotEmpty &&
        provider.notifications
            .every((n) => provider.selectedIds.contains(n.id));

    return AppBar(
      backgroundColor: AppConstants.secondary,
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
        // Select all / Deselect all
        IconButton(
          icon: Icon(
            allSelected
                ? Icons.deselect_outlined
                : Icons.select_all_outlined,
            color: Colors.white,
          ),
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed: () {
            if (allSelected) {
              provider.clearSelection();
            } else {
              provider.selectAll(
                provider.notifications.map((n) => n.id).toList(),
              );
            }
          },
        ),
        // Mark as read
        IconButton(
          icon:
              const Icon(Icons.mark_email_read_outlined, color: Colors.white),
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

  Future<void> _confirmBulkDelete(
      SellerNotificationProvider provider) async {
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $count notifications?'),
        content: const Text('This action can be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppConstants.error),
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
          MaterialPageRoute(
            builder: (_) =>
                const ManageProductsScreen(initialFilter: 'Low Stock'),
          ),
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
    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select(
              '*, profiles!orders_customer_id_fkey(full_name, email), order_items(*, products(name))')
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
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ManageOrdersScreen()),
        );
      }
    }
  }

  void _handleDelete(
    SellerNotificationProvider provider,
    SellerNotification notif,
    int index,
  ) async {
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

class _NotificationSlidable extends StatelessWidget {
  final SellerNotification notification;
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
    // In selection mode, disable slidable
    if (isSelectionMode) {
      return _NotificationRowContent(
        notification: notification,
        onTap: onTap,
        isSelectionMode: true,
        isSelected: isSelected,
      );
    }

    return Slidable(
      key: ValueKey(notification.id),
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
            icon: Icons.open_in_new,
            label: 'View',
          ),
        ],
      ),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: _NotificationRowContent(
          notification: notification,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _NotificationRowContent extends StatelessWidget {
  final SellerNotification notification;
  final VoidCallback onTap;
  final bool isSelectionMode;
  final bool isSelected;

  const _NotificationRowContent({
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
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: notification.isRead
                ? AppConstants.sellerCardBg
                : AppConstants.statusConfirmedColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SellerTheme.cardBorder),
            boxShadow: AppConstants.sellerShadow,
          ),
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
                        ? AppConstants.statusConfirmedColor
                        : AppConstants.secondary.withValues(alpha: 0.3),
                    size: 24,
                  ),
                )
              else
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
                    // ── Batched message previews or single body ──
                    if (notification.isBatched &&
                        notification.previews.isNotEmpty)
                      _buildBatchedPreviews()
                    else
                      Text(
                        notification.body,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary
                              .withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      notification.relativeTime,
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary
                            .withValues(alpha: 0.4),
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

  /// Build the batched message preview stack for message notifications
  /// that have multiple messages folded in (message_count > 1).
  Widget _buildBatchedPreviews() {
    final previews = notification.previews;
    final count = notification.messageCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count new messages',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppConstants.secondary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
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
        return AppConstants.statusConfirmedColor;
      case 'stale_order':
        return AppConstants.statusPendingColor;
      case 'low_stock':
        return AppConstants.lowStockColor;
      case 'custom_order_request':
        return AppConstants.statusReadyColor;
      case 'new_message':
        return AppConstants.statusConfirmedColor;
      default:
        return AppConstants.primary;
    }
  }
}
