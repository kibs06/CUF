import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/notification_category.dart';
import '../services/notification_service.dart';

/// Holds the current notification list + unread counts in memory.
///
/// Exposed to both the notifications feed screen and the profile screen's
/// icon row. Unread counts are loaded on auth change so badges appear
/// as soon as the user's profile loads.
class NotificationProvider extends ChangeNotifier {
  final NotificationService _service = NotificationService.instance;

  List<AppNotification> _notifications = [];
  Map<NotificationCategory, int> _unreadCounts = {
    for (final cat in NotificationCategory.values) cat: 0,
  };
  bool _isLoading = false;
  String? _userId;

  // ── Public getters ─────────────────────────────────────────────

  List<AppNotification> get notifications => _notifications;
  Map<NotificationCategory, int> get unreadCounts => Map.unmodifiable(_unreadCounts);
  bool get isLoading => _isLoading;

  /// Total unread count across all categories.
  int get totalUnread =>
      _unreadCounts.values.fold(0, (sum, count) => sum + count);

  // ── Lifecycle ──────────────────────────────────────────────────

  NotificationProvider() {
    // Listen for auth changes to load/clear notifications
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (session != null) {
        _userId = session.user.id;
        loadUnreadCounts();
      } else {
        _userId = null;
        _notifications = [];
        _unreadCounts = {
          for (final cat in NotificationCategory.values) cat: 0,
        };
        notifyListeners();
      }
    });

    // Hydrate immediately if already logged in
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      _userId = currentUserId;
      loadUnreadCounts();
    }
  }

  // ── Load notifications ─────────────────────────────────────────

  Future<void> loadNotifications({
    NotificationCategory? categoryFilter,
    String? orderTypeFilter, // 'catalog', 'custom', or null for all
  }) async {
    if (_userId == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      _notifications = await _service.fetchNotifications(
        userId: _userId!,
        categoryFilter: categoryFilter,
        orderTypeFilter: orderTypeFilter,
      );
    } catch (e) {
      debugPrint('NotificationProvider: load failed: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Load unread counts ─────────────────────────────────────────

  Future<void> loadUnreadCounts() async {
    if (_userId == null) return;

    try {
      _unreadCounts = await _service.fetchUnreadCounts(_userId!);
      notifyListeners();
    } catch (e) {
      debugPrint('NotificationProvider: unread counts failed: $e');
    }
  }

  // ── Mark as read (optimistic) ──────────────────────────────────

  Future<void> markAsRead(String notificationId) async {
    // Optimistic: flip locally
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final old = _notifications[index];
    if (old.isRead) return; // already read

    // Create updated notification
    _notifications[index] = AppNotification(
      id: old.id,
      orderId: old.orderId,
      category: old.category,
      title: old.title,
      message: old.message,
      isRead: true,
      createdAt: old.createdAt,
    );

    // Decrement unread count
    _unreadCounts[old.category] =
        (_unreadCounts[old.category] ?? 1) - 1;
    notifyListeners();

    // Background server write
    try {
      await _service.markAsRead(notificationId);
    } catch (e) {
      debugPrint('NotificationProvider: markAsRead failed: $e');
      // Rollback
      _notifications[index] = old;
      _unreadCounts[old.category] =
          (_unreadCounts[old.category] ?? 0) + 1;
      notifyListeners();
    }
  }

  /// Mark all notifications as read (used by "Mark all read" button).
  Future<void> markAllAsRead() async {
    if (_userId == null) return;

    // Optimistic: mark all local notifications as read
    final oldNotifications = List<AppNotification>.from(_notifications);
    final oldCounts = Map<NotificationCategory, int>.from(_unreadCounts);

    _notifications = _notifications
        .map((n) => n.isRead
            ? n
            : AppNotification(
                id: n.id,
                orderId: n.orderId,
                category: n.category,
                title: n.title,
                message: n.message,
                isRead: true,
                createdAt: n.createdAt,
              ))
        .toList();
    _unreadCounts = {
      for (final cat in NotificationCategory.values) cat: 0,
    };
    notifyListeners();

    try {
      await _service.markAllAsRead(userId: _userId!);
    } catch (e) {
      debugPrint('NotificationProvider: markAllAsRead failed: $e');
      // Rollback
      _notifications = oldNotifications;
      _unreadCounts = oldCounts;
      notifyListeners();
    }
  }
}
