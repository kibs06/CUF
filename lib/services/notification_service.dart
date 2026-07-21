import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/notification_category.dart';

/// Singleton service handling all notification-related Supabase operations.
///
/// Follows the same pattern as [CartService] / [ProductService].
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── READ ───────────────────────────────────────────────────────

  /// Fetch notifications for a user, optionally filtered by category and/or order type.
  Future<List<AppNotification>> fetchNotifications({
    required String userId,
    NotificationCategory? categoryFilter,
    String? orderTypeFilter, // 'catalog', 'custom', or null for all
  }) async {
    var query = _client
        .from('notifications')
        .select()
        .eq('user_id', userId);

    if (categoryFilter != null) {
      query = query.eq('category', categoryFilter.name);
    }

    if (orderTypeFilter != null) {
      query = query.eq('order_type', orderTypeFilter);
    }

    final data = await query
        .eq('is_deleted', false)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => AppNotification.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Get unread counts grouped by category.
  ///
  /// Returns a map like `{unpaid: 3, processing: 1, shipped: 0, ...}`.
  Future<Map<NotificationCategory, int>> fetchUnreadCounts(
    String userId,
  ) async {
    final data = await _client
        .from('notifications')
        .select('category')
        .eq('user_id', userId)
        .eq('is_read', false)
        .eq('is_deleted', false);

    final counts = <NotificationCategory, int>{
      for (final cat in NotificationCategory.values) cat: 0,
    };

    for (final row in data as List) {
      final catName = row['category']?.toString() ?? '';
      final cat = NotificationCategory.values
          .where((c) => c.name == catName)
          .firstOrNull;
      if (cat != null) {
        counts[cat] = (counts[cat] ?? 0) + 1;
      }
    }

    return counts;
  }

  // ─── UPDATE ─────────────────────────────────────────────────────

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  /// Mark all notifications for a user as read, optionally scoped to one category.
  Future<void> markAllAsRead({
    required String userId,
    NotificationCategory? categoryFilter,
  }) async {
    var query = _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false)
        .eq('is_deleted', false);

    if (categoryFilter != null) {
      query = query.eq('category', categoryFilter.name);
    }

    await query;
  }

  // ─── SOFT DELETE ───────────────────────────────────────────────

  /// Soft-delete a notification (hide from feed, allow undo).
  Future<void> deleteNotification(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_deleted': true})
        .eq('id', notificationId);
  }

  /// Restore a soft-deleted notification (used by Undo snackbar).
  Future<void> restoreNotification(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_deleted': false})
        .eq('id', notificationId);
  }

  /// Mark a notification as unread.
  Future<void> markAsUnread(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': false})
        .eq('id', notificationId);
  }

  // ─── BULK OPERATIONS (Selection Mode) ──────────────────────────

  /// Soft-delete multiple notifications at once (selection mode).
  Future<void> deleteNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('notifications')
        .update({'is_deleted': true})
        .inFilter('id', ids);
  }

  /// Restore multiple soft-deleted notifications (undo from selection mode).
  Future<void> restoreNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('notifications')
        .update({'is_deleted': false})
        .inFilter('id', ids);
  }

  /// Mark multiple notifications as read (bulk selection mode).
  Future<void> markAsReadBulk(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .inFilter('id', ids);
  }

  /// Mark multiple notifications as unread (bulk selection mode).
  Future<void> markAsUnreadBulk(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('notifications')
        .update({'is_read': false})
        .inFilter('id', ids);
  }
}
