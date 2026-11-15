import 'package:flutter/foundation.dart';

import '../services/admin_notification_service.dart';

/// Holds the signed-in admin's feed and unread count.
///
/// Kept deliberately small compared with the seller bell: no realtime
/// subscription and no soft delete. Admin events are rare (a seller
/// resubmitting after a rejection), the feed is refreshed on open, and the
/// database already scopes every row to the caller.
class AdminNotificationProvider extends ChangeNotifier {
  /// [service] defaults to the live singleton; widget tests pass a fake so
  /// every state below is exercised without a Supabase client.
  AdminNotificationProvider({AdminNotificationService? service})
      : _service = service ?? AdminNotificationService.instance;

  final AdminNotificationService _service;

  List<AdminNotification> _notifications = const [];
  int _unreadCount = 0;
  bool _isLoading = false;

  List<AdminNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get hasUnread => _unreadCount > 0;

  /// The bell only needs the number; the full list is loaded when the feed
  /// is opened.
  Future<void> loadUnread() async {
    try {
      _unreadCount = await _service.unreadCount();
      notifyListeners();
    } catch (e) {
      debugAdminNotifications('unread count failed: $e');
    }
  }

  Future<void> load({int limit = 50}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _notifications = await _service.fetch(limit: limit);
      _unreadCount = _notifications.where((n) => !n.isRead).length;
    } catch (e) {
      debugAdminNotifications('load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Optimistic: the row flips to read immediately and is rolled back if the
  /// UPDATE fails, so a flaky connection cannot silently mark work as seen.
  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1 || _notifications[index].isRead) return;

    final old = _notifications[index];
    final updated = List<AdminNotification>.from(_notifications);
    updated[index] = old.copyWith(isRead: true);
    _notifications = updated;
    _unreadCount = (_unreadCount - 1).clamp(0, 999);
    notifyListeners();

    try {
      await _service.markAsRead(id);
    } catch (e) {
      debugAdminNotifications('markAsRead failed: $e');
      final rolledBack = List<AdminNotification>.from(_notifications);
      rolledBack[index] = old;
      _notifications = rolledBack;
      _unreadCount++;
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    if (_unreadCount == 0) return;
    final oldList = _notifications;
    final oldCount = _unreadCount;

    _notifications =
        _notifications.map((n) => n.copyWith(isRead: true)).toList();
    _unreadCount = 0;
    notifyListeners();

    try {
      await _service.markAllAsRead();
    } catch (e) {
      debugAdminNotifications('markAllAsRead failed: $e');
      _notifications = oldList;
      _unreadCount = oldCount;
      notifyListeners();
    }
  }
}
