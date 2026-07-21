# Notification Swipe Gestures — Reference Implementation

> **Source:** `lib/screens/notifications_screen.dart` and `lib/screens/seller/seller_notification_center_screen.dart`
> **Package:** `flutter_slidable: ^3.1.0`
> **Date:** July 19, 2026

---

## ListView Wrapper (in both screens)

```dart
SlidableAutoCloseBehavior(
  child: ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
    itemCount: provider.notifications.length,
    itemBuilder: (context, index) {
      final notif = provider.notifications[index];
      return _NotificationCard(
        notification: notif,
        onTap: () => _handleTap(provider, notif),
        onDelete: () => _deleteWithUndo(provider, notif),
        onToggleRead: () {
          if (notif.isRead) {
            provider.markAsUnread(notif.id);
          } else {
            provider.markAsRead(notif.id);
          }
        },
      );
    },
  ),
),
```

---

## Card Widget with Slidable

```dart
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleRead;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDelete,
    required this.onToggleRead,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey(notification.id),
        // End-to-start (swipe left): Mark Read/Unread + Delete
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
                HapticFeedback.lightImpact();
                onDelete();
              },
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
          ],
        ),
        // Start-to-end (swipe right): Delete with confirm-dismiss
        startActionPane: ActionPane(
          motion: const BehindMotion(),
          dismissible: DismissiblePane(
            onDismissed: () {
              HapticFeedback.lightImpact();
              onDelete();
            },
          ),
          children: [],
        ),
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
                // Leading icon
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
                // Title + message + timestamp
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
      ),
    );
  }
}
```

---

## Delete with Undo Handler

```dart
void _deleteWithUndo(
  NotificationProvider provider,
  AppNotification notif,
) {
  final removed = notif;

  provider.deleteNotification(notif.id);

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Notification deleted'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        textColor: AppConstants.primary,
        onPressed: () {
          if (!mounted) return;
          provider.restoreNotification(removed);
        },
      ),
    ),
  );
}
```

---

## Provider Methods (optimistic with rollback)

```dart
// Delete
Future<void> deleteNotification(String notificationId) async {
  final index = _notifications.indexWhere((n) => n.id == notificationId);
  if (index == -1) return;
  final removed = _notifications.removeAt(index);
  if (!removed.isRead) {
    _unreadCounts[removed.category] =
        (_unreadCounts[removed.category] ?? 1) - 1;
  }
  notifyListeners();
  try {
    await _service.deleteNotification(notificationId);
  } catch (e) {
    _notifications.insert(index, removed);
    if (!removed.isRead) {
      _unreadCounts[removed.category] =
          (_unreadCounts[removed.category] ?? 0) + 1;
    }
    notifyListeners();
  }
}

// Restore (Undo)
Future<void> restoreNotification(AppNotification notification) async {
  int insertIndex = 0;
  for (int i = 0; i < _notifications.length; i++) {
    if (_notifications[i].createdAt.isBefore(notification.createdAt)) {
      insertIndex = i;
      break;
    }
    insertIndex = i + 1;
  }
  _notifications.insert(insertIndex, notification);
  if (!notification.isRead) {
    _unreadCounts[notification.category] =
        (_unreadCounts[notification.category] ?? 0) + 1;
  }
  notifyListeners();
  try {
    await _service.restoreNotification(notification.id);
  } catch (e) {
    _notifications.removeWhere((n) => n.id == notification.id);
    if (!notification.isRead) {
      _unreadCounts[notification.category] =
          (_unreadCounts[notification.category] ?? 1) - 1;
    }
    notifyListeners();
  }
}

// Mark as unread
Future<void> markAsUnread(String notificationId) async {
  final index = _notifications.indexWhere((n) => n.id == notificationId);
  if (index == -1) return;
  final old = _notifications[index];
  if (!old.isRead) return;
  _notifications[index] = AppNotification(
    id: old.id, orderId: old.orderId, category: old.category,
    title: old.title, message: old.message,
    isRead: false, createdAt: old.createdAt,
  );
  _unreadCounts[old.category] = (_unreadCounts[old.category] ?? 0) + 1;
  notifyListeners();
  try {
    await _service.markAsUnread(notificationId);
  } catch (e) {
    _notifications[index] = old;
    _unreadCounts[old.category] = (_unreadCounts[old.category] ?? 1) - 1;
    notifyListeners();
  }
}
```

---

## Key Requirements

1. **`key: ValueKey(notification.id)`** — Required on `Slidable` when used in lists with `DismissiblePane`
2. **`SlidableAutoCloseBehavior`** — Wraps the `ListView` to close open panes when another is opened
3. **`extentRatio: 0.5`** — Gives enough room for 2 action buttons (~72px each)
4. **Haptics** — `selectionClick()` on pane open, `lightImpact()` on delete threshold
5. **`mounted` check** — In undo callback before `restoreNotification`
