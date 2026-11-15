import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/admin_notification_provider.dart';
import '../../services/admin_notification_service.dart';
import 'seller_business_docs_review_screen.dart';

/// The admin's feed.
///
/// Until now the only signal that a seller had resubmitted business
/// documents was a count on the dashboard: it said something was waiting but
/// not who, when, or how many attempts — and it vanished the moment the
/// queue changed. This screen lists each event, marks it read, and opens the
/// queue the notice is about.
class AdminNotificationCenterScreen extends StatefulWidget {
  const AdminNotificationCenterScreen({super.key});

  @override
  State<AdminNotificationCenterScreen> createState() =>
      _AdminNotificationCenterScreenState();
}

class _AdminNotificationCenterScreenState
    extends State<AdminNotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminNotificationProvider>().load();
    });
  }

  Future<void> _open(AdminNotification notif) async {
    final provider = context.read<AdminNotificationProvider>();
    await provider.markAsRead(notif.id);
    if (!mounted || !notif.opensBusinessDocsQueue) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SellerBusinessDocsReviewScreen(),
      ),
    );
    if (!mounted) return;
    // Returning from the queue is the one moment a verdict may have landed;
    // refresh so the list reflects anything that arrived meanwhile.
    await provider.load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminNotificationProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.chrome,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          if (provider.hasUnread)
            TextButton(
              key: const Key('admin-notifications-mark-all'),
              onPressed: provider.markAllAsRead,
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
      body: provider.isLoading && provider.notifications.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => provider.load(),
              child: provider.notifications.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none,
                                size: 48,
                                color: AppConstants.borderGray,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nothing needs you right now.',
                                style: AppConstants.bodyStyle(
                                  color: AppConstants.secondary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final notif = provider.notifications[index];
                        return _AdminNoticeCard(
                          notification: notif,
                          onTap: () => _open(notif),
                        );
                      },
                    ),
            ),
    );
  }
}

class _AdminNoticeCard extends StatelessWidget {
  final AdminNotification notification;
  final VoidCallback onTap;

  const _AdminNoticeCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final accent = notification.opensBusinessDocsQueue
        ? const Color(0xFFC47D00)
        : AppConstants.primary;

    return Material(
      color: AppConstants.surfaceLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('admin-notice-${notification.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread
                  ? accent.withValues(alpha: 0.45)
                  : AppConstants.borderGray.withValues(alpha: 0.5),
              width: unread ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  notification.opensBusinessDocsQueue
                      ? Icons.fact_check_outlined
                      : Icons.notifications_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
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
                              fontWeight:
                                  unread ? FontWeight.bold : FontWeight.w600,
                              color: AppConstants.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          notification.relativeTime,
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            color: AppConstants.secondary
                                .withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppConstants.secondary
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  key: ValueKey('admin-notice-unread-dot-${notification.id}'),
                  margin: const EdgeInsets.only(top: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
