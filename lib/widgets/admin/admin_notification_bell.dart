import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/admin_notification_provider.dart';
import '../../screens/admin/admin_notification_center_screen.dart';

/// The admin app bar's bell: the unread count of the admin's own feed.
///
/// A widget of its own rather than a slab inside `AdminDashboardScreen`, so
/// the badge can be exercised against `AdminNotificationProvider` on its own
/// — the dashboard also loads orders, products and profiles on first frame,
/// which no widget test should have to stand up for a badge.
///
/// It watches the provider, so reading a notice in the feed updates the
/// number on return without re-querying; [onFeedClosed] exists for the
/// dashboard's OWN state (its queue count), which is not the feed.
class AdminNotificationBell extends StatelessWidget {
  final VoidCallback? onFeedClosed;

  const AdminNotificationBell({super.key, this.onFeedClosed});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AdminNotificationProvider>().unreadCount;

    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () async {
        // Resolved before the push: `build`'s context is a parameter, and the
        // provider may change while the feed is open.
        final provider = context.read<AdminNotificationProvider>();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AdminNotificationCenterScreen(),
          ),
        );
        if (!context.mounted) return;
        provider.loadUnread();
        onFeedClosed?.call();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (unread > 0)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                key: const Key('admin-notification-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppConstants.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
