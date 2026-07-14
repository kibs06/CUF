import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/seller_notification_service.dart';

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

  // ── Public getters ─────────────────────────────────────────────

  List<SellerNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get storeId => _storeId;

  /// Display-friendly unread count (caps at "9+").
  String get unreadBadge => _unreadCount > 0
      ? (_unreadCount > 9 ? '9+' : '$_unreadCount')
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

    _realtimeSub = _client
        .from('seller_notifications')
        .stream(primaryKey: ['id'])
        .eq('store_id', _storeId!)
        .order('created_at', ascending: false)
        .limit(50)
        .listen((data) {
          _notifications = data
              .map((row) => SellerNotification.fromMap(Map<String, dynamic>.from(row)))
              .toList();
          _unreadCount = _notifications.where((n) => !n.isRead).length;
          notifyListeners();
        });
  }

  SupabaseClient get _client => Supabase.instance.client;
}
