import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/seller_notification_service.dart';
import '../utils/notification_formatters.dart';

/// Holds seller notification state: list, unread count, and Realtime updates.
///
/// Used by the Dashboard bell icon badge and the Notification Center screen.
class SellerNotificationProvider extends ChangeNotifier {
  final SellerNotificationService _service = SellerNotificationService.instance;

  List<SellerNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _storeId;
  StreamSubscription? _realtimeSub;

  // ── Selection mode state ─────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // ── Public getters ─────────────────────────────────────────────

  List<SellerNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get storeId => _storeId;
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;

  /// Display-friendly unread count (caps at "99+").
  String get unreadBadge => _unreadCount > 0
      ? formatBadgeCount(_unreadCount)
      : '';

  bool get hasUnread => _unreadCount > 0;

  // ── Lifecycle ──────────────────────────────────────────────────

  /// Initialize with a store ID and start listening for real-time updates.
  void init(String storeId) {
    if (_storeId == storeId) return; // already initialized
    _storeId = storeId;
    loadUnreadCount();
    _subscribeToRealtime();
  }

  /// Clear state on logout or store change.
  void reset() {
    _storeId = null;
    _notifications = [];
    _unreadCount = 0;
    _realtimeSub?.cancel();
    _realtimeSub = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  // ── Load notifications ─────────────────────────────────────────

  Future<void> loadNotifications({int limit = 50}) async {
    if (_storeId == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      _notifications = await _service.getNotifications(_storeId!, limit: limit);
    } catch (e) {
      debugPrint('[SellerNotificationProvider] load failed: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Load unread count ──────────────────────────────────────────

  Future<void> loadUnreadCount() async {
    if (_storeId == null) return;

    try {
      _unreadCount = await _service.getUnreadCount(_storeId!);
      notifyListeners();
    } catch (e) {
      debugPrint('[SellerNotificationProvider] unread count failed: $e');
    }
  }

  // ── Mark as read (optimistic) ──────────────────────────────────

  Future<void> markAsRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final old = _notifications[index];
    if (old.isRead) return;

    // Optimistic update
    _notifications[index] = SellerNotification(
      id: old.id,
      storeId: old.storeId,
      type: old.type,
      title: old.title,
      body: old.body,
      referenceId: old.referenceId,
      isRead: true,
      createdAt: old.createdAt,
    );
    _unreadCount = (_unreadCount - 1).clamp(0, 999);
    notifyListeners();

    try {
      await _service.markAsRead(notificationId);
    } catch (e) {
      debugPrint('[SellerNotificationProvider] markAsRead failed: $e');
      // Rollback
      _notifications[index] = old;
      _unreadCount++;
      notifyListeners();
    }
  }

  /// Force-refresh unread count from the database.
  /// Called on tap (before navigating to Notification Center) as a safety net
  /// to guarantee the badge reflects the true current state.
  Future<void> refreshNotifications() async {
    if (_storeId == null || _isLoading) return;
    await loadUnreadCount();
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
      _unreadCount = (_unreadCount - 1).clamp(0, 999);
    }
    notifyListeners();

    try {
      await _service.deleteNotification(notificationId);
    } catch (e) {
      debugPrint('[SellerNotificationProvider] deleteNotification failed: $e');
      // Rollback
      _notifications.insert(index, old);
      if (wasUnread) _unreadCount++;
      notifyListeners();
    }
  }

  /// Restore a deleted notification (Undo snackbar path).
  void restoreNotification(SellerNotification notif, int index) {
    _notifications.insert(index, notif);
    if (!notif.isRead) _unreadCount++;
    notifyListeners();

    _service.restoreNotification(notif.id).catchError((e) {
      debugPrint('[SellerNotificationProvider] restoreNotification failed: $e');
    });
  }

  // ── Mark as unread ──────────────────────────────────────────

  Future<void> markAsUnread(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final old = _notifications[index];
    if (!old.isRead) return;

    _notifications[index] = SellerNotification(
      id: old.id,
      storeId: old.storeId,
      type: old.type,
      title: old.title,
      body: old.body,
      referenceId: old.referenceId,
      isRead: false,
      createdAt: old.createdAt,
    );
    _unreadCount++;
    notifyListeners();

    try {
      await _service.markAsUnread(notificationId);
    } catch (e) {
      debugPrint('[SellerNotificationProvider] markAsUnread failed: $e');
      _notifications[index] = old;
      _unreadCount = (_unreadCount - 1).clamp(0, 999);
      notifyListeners();
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    if (_storeId == null) return;

    // Optimistic update
    final oldNotifications = List<SellerNotification>.from(_notifications);
    final oldCount = _unreadCount;

    _notifications = _notifications
        .map((n) => n.isRead
            ? n
            : SellerNotification(
                id: n.id,
                storeId: n.storeId,
                type: n.type,
                title: n.title,
                body: n.body,
                referenceId: n.referenceId,
                isRead: true,
                createdAt: n.createdAt,
              ))
        .toList();
    _unreadCount = 0;
    notifyListeners();

    try {
      await _service.markAllAsRead(_storeId!);
    } catch (e) {
      debugPrint('[SellerNotificationProvider] markAllAsRead failed: $e');
      // Rollback
      _notifications = oldNotifications;
      _unreadCount = oldCount;
      notifyListeners();
    }
  }

  // ── Realtime subscription ──────────────────────────────────────

  void _subscribeToRealtime() {
    _realtimeSub?.cancel();
    if (_storeId == null) return;

    // NOTE: .order() and .limit() are NOT supported by Supabase Realtime
    // streams — sorting and capping are done client-side below.
    _realtimeSub = _client
        .from('seller_notifications')
        .stream(primaryKey: ['id'])
        .listen((data) {
          // Client-side filter: only this store, not soft-deleted
          // Sort newest-first and cap at 50
          _notifications = data
              .where((row) =>
                  row['store_id'] == _storeId &&
                  row['is_deleted'] != true)
              .map((row) => SellerNotification.fromMap(Map<String, dynamic>.from(row)))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (_notifications.length > 50) {
            _notifications = _notifications.sublist(0, 50);
          }
          _unreadCount = _notifications.where((n) => !n.isRead).length;
          notifyListeners();
        });
  }

  SupabaseClient get _client => Supabase.instance.client;

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

  Future<List<SellerNotification>> deleteSelected() async {
    if (_selectedIds.isEmpty || _storeId == null) return [];

    final idsToDelete = Set<String>.from(_selectedIds);
    final deletedNotifs = <SellerNotification>[];

    _notifications.removeWhere((n) {
      if (idsToDelete.contains(n.id)) {
        deletedNotifs.add(n);
        if (!n.isRead) {
          _unreadCount = (_unreadCount - 1).clamp(0, 999);
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
      debugPrint('[SellerNotificationProvider] deleteSelected failed: $e');
      for (final notif in deletedNotifs) {
        _notifications.add(notif);
        if (!notif.isRead) _unreadCount++;
      }
      _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _isSelectionMode = true;
      _selectedIds.addAll(idsToDelete);
      notifyListeners();
    }

    return deletedNotifs;
  }

  void undoDeleteSelected(List<SellerNotification> notifs) {
    for (final notif in notifs) {
      _notifications.insert(0, notif);
      if (!notif.isRead) _unreadCount++;
    }
    notifyListeners();

    _service
        .restoreNotifications(notifs.map((n) => n.id).toList())
        .catchError((e) {
      debugPrint('[SellerNotificationProvider] undoDeleteSelected failed: $e');
    });
  }

  // ── Bulk mark read/unread (selection mode) ───────────────────

  Future<void> markSelectedRead() async {
    if (_selectedIds.isEmpty || _storeId == null) return;

    final idsToMark = Set<String>.from(_selectedIds);

    for (var i = 0; i < _notifications.length; i++) {
      if (idsToMark.contains(_notifications[i].id) &&
          !_notifications[i].isRead) {
        _notifications[i] = SellerNotification(
          id: _notifications[i].id,
          storeId: _notifications[i].storeId,
          type: _notifications[i].type,
          title: _notifications[i].title,
          body: _notifications[i].body,
          referenceId: _notifications[i].referenceId,
          isRead: true,
          createdAt: _notifications[i].createdAt,
          metadata: _notifications[i].metadata,
        );
        _unreadCount = (_unreadCount - 1).clamp(0, 999);
      }
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await _service.markAsReadBulk(idsToMark.toList());
    } catch (e) {
      debugPrint('[SellerNotificationProvider] markSelectedRead failed: $e');
    }
  }

  Future<void> markSelectedUnread() async {
    if (_selectedIds.isEmpty || _storeId == null) return;

    final idsToMark = Set<String>.from(_selectedIds);

    for (var i = 0; i < _notifications.length; i++) {
      if (idsToMark.contains(_notifications[i].id) &&
          _notifications[i].isRead) {
        _notifications[i] = SellerNotification(
          id: _notifications[i].id,
          storeId: _notifications[i].storeId,
          type: _notifications[i].type,
          title: _notifications[i].title,
          body: _notifications[i].body,
          referenceId: _notifications[i].referenceId,
          isRead: false,
          createdAt: _notifications[i].createdAt,
          metadata: _notifications[i].metadata,
        );
        _unreadCount++;
      }
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await _service.markAsUnreadBulk(idsToMark.toList());
    } catch (e) {
      debugPrint('[SellerNotificationProvider] markSelectedUnread failed: $e');
    }
  }
}
