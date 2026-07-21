import 'dart:async';

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
  StreamSubscription? _realtimeSub;

  // ── Selection mode state ─────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // ── Public getters ─────────────────────────────────────────────

  List<AppNotification> get notifications => _notifications;
  Map<NotificationCategory, int> get unreadCounts => Map.unmodifiable(_unreadCounts);
  bool get isLoading => _isLoading;
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;

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
      _subscribeToRealtime();
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

  // ── Delete notification (optimistic with undo) ────────────────

  Future<void> deleteNotification(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final old = _notifications[index];
    final wasUnread = !old.isRead;

    // Optimistic: remove from list
    _notifications.removeAt(index);
    if (wasUnread) {
      _unreadCounts[old.category] =
          (_unreadCounts[old.category] ?? 1) - 1;
    }
    notifyListeners();

    try {
      await _service.deleteNotification(notificationId);
    } catch (e) {
      debugPrint('NotificationProvider: deleteNotification failed: $e');
      // Rollback
      _notifications.insert(index, old);
      if (wasUnread) {
        _unreadCounts[old.category] =
            (_unreadCounts[old.category] ?? 0) + 1;
      }
      notifyListeners();
    }
  }

  /// Restore a deleted notification (Undo snackbar path).
  void restoreNotification(AppNotification notif, int index) {
    _notifications.insert(index, notif);
    if (!notif.isRead) {
      _unreadCounts[notif.category] =
          (_unreadCounts[notif.category] ?? 0) + 1;
    }
    notifyListeners();

    // Background: persist restore to DB
    _service.restoreNotification(notif.id).catchError((e) {
      debugPrint('NotificationProvider: restoreNotification failed: $e');
    });
  }

  // ── Mark as unread ──────────────────────────────────────────

  Future<void> markAsUnread(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final old = _notifications[index];
    if (!old.isRead) return; // already unread

    _notifications[index] = AppNotification(
      id: old.id,
      orderId: old.orderId,
      category: old.category,
      title: old.title,
      message: old.message,
      isRead: false,
      createdAt: old.createdAt,
    );
    _unreadCounts[old.category] =
        (_unreadCounts[old.category] ?? 0) + 1;
    notifyListeners();

    try {
      await _service.markAsUnread(notificationId);
    } catch (e) {
      debugPrint('NotificationProvider: markAsUnread failed: $e');
      _notifications[index] = old;
      _unreadCounts[old.category] =
          (_unreadCounts[old.category] ?? 1) - 1;
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

  // ── Selection mode ──────────────────────────────────────────

  void enterSelectionMode() {
    _isSelectionMode = true;
    _selectedIds.clear();
    notifyListeners();
  }

  void exitSelectionMode() {
    _isSelectionMode = false;
    _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  /// Select all currently visible notification IDs.
  void selectAll(List<String> visibleIds) {
    _selectedIds.addAll(visibleIds);
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  // ── Bulk delete (selection mode) ─────────────────────────────

  /// Delete selected notifications. Returns the deleted list for undo.
  Future<List<AppNotification>> deleteSelected() async {
    if (_selectedIds.isEmpty || _userId == null) return [];

    final idsToDelete = Set<String>.from(_selectedIds);
    final deletedNotifs = <AppNotification>[];

    // Optimistic: remove from list and track for undo
    _notifications.removeWhere((n) {
      if (idsToDelete.contains(n.id)) {
        deletedNotifs.add(n);
        if (!n.isRead) {
          _unreadCounts[n.category] =
              (_unreadCounts[n.category] ?? 1) - 1;
        }
        return true;
      }
      return false;
    });
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await _service.deleteNotifications(idsToDelete.toList());
    } catch (e) {
      debugPrint('NotificationProvider: deleteSelected failed: $e');
      // Rollback: re-insert deleted items
      for (final notif in deletedNotifs) {
        _notifications.add(notif);
        if (!notif.isRead) {
          _unreadCounts[notif.category] =
              (_unreadCounts[notif.category] ?? 0) + 1;
        }
      }
      _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _isSelectionMode = true;
      _selectedIds.addAll(idsToDelete);
      notifyListeners();
    }

    return deletedNotifs;
  }

  /// Undo bulk delete: restore previously deleted notifications.
  void undoDeleteSelected(List<AppNotification> notifs) {
    for (final notif in notifs) {
      _notifications.insert(0, notif);
      if (!notif.isRead) {
        _unreadCounts[notif.category] =
            (_unreadCounts[notif.category] ?? 0) + 1;
      }
    }
    notifyListeners();

    // Background: restore in DB
    _service
        .restoreNotifications(notifs.map((n) => n.id).toList())
        .catchError((e) {
      debugPrint('NotificationProvider: undoDeleteSelected failed: $e');
    });
  }

  // ── Bulk mark read/unread (selection mode) ───────────────────

  Future<void> markSelectedRead() async {
    if (_selectedIds.isEmpty || _userId == null) return;

    final idsToMark = Set<String>.from(_selectedIds);

    // Optimistic
    for (var i = 0; i < _notifications.length; i++) {
      if (idsToMark.contains(_notifications[i].id) &&
          !_notifications[i].isRead) {
        _notifications[i] = AppNotification(
          id: _notifications[i].id,
          orderId: _notifications[i].orderId,
          category: _notifications[i].category,
          title: _notifications[i].title,
          message: _notifications[i].message,
          isRead: true,
          createdAt: _notifications[i].createdAt,
          metadata: _notifications[i].metadata,
        );
        _unreadCounts[_notifications[i].category] =
            (_unreadCounts[_notifications[i].category] ?? 1) - 1;
      }
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await _service.markAsReadBulk(idsToMark.toList());
    } catch (e) {
      debugPrint('NotificationProvider: markSelectedRead failed: $e');
    }
  }

  Future<void> markSelectedUnread() async {
    if (_selectedIds.isEmpty || _userId == null) return;

    final idsToMark = Set<String>.from(_selectedIds);

    // Optimistic
    for (var i = 0; i < _notifications.length; i++) {
      if (idsToMark.contains(_notifications[i].id) &&
          _notifications[i].isRead) {
        _notifications[i] = AppNotification(
          id: _notifications[i].id,
          orderId: _notifications[i].orderId,
          category: _notifications[i].category,
          title: _notifications[i].title,
          message: _notifications[i].message,
          isRead: false,
          createdAt: _notifications[i].createdAt,
          metadata: _notifications[i].metadata,
        );
        _unreadCounts[_notifications[i].category] =
            (_unreadCounts[_notifications[i].category] ?? 0) + 1;
      }
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await _service.markAsUnreadBulk(idsToMark.toList());
    } catch (e) {
      debugPrint('NotificationProvider: markSelectedUnread failed: $e');
    }
  }

  // ── Realtime subscription ──────────────────────────────────────

  void _subscribeToRealtime() {
    _realtimeSub?.cancel();
    if (_userId == null) return;

    _realtimeSub = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', _userId!)
        .order('created_at', ascending: false)
        .limit(100)
        .listen(
      (data) {
        // Client-side filter: not soft-deleted
        _notifications = data
            .where((row) => row['is_deleted'] != true)
            .take(50)
            .map((row) =>
                AppNotification.fromMap(Map<String, dynamic>.from(row)))
            .toList();
        _recomputeUnreadCounts();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('NotificationProvider: realtime error: $e');
      },
    );
  }

  /// Recompute unread counts from the current notification list.
  void _recomputeUnreadCounts() {
    final counts = <NotificationCategory, int>{
      for (final cat in NotificationCategory.values) cat: 0,
    };
    for (final n in _notifications) {
      if (!n.isRead) {
        counts[n.category] = (counts[n.category] ?? 0) + 1;
      }
    }
    _unreadCounts = counts;
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }
}
