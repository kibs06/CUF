import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row from `admin_notifications` — an event waiting on an admin.
///
/// Its own table, not the customer `notifications` feed and not the
/// store-scoped seller bell: an admin's work is about other people's rows,
/// so the feed carries a `reference_id` pointing at the subject (the
/// seller's profile, for a resubmission).
class AdminNotification {
  final String id;

  /// One of the values `admin_notifications.type` admits. Currently
  /// 'business_docs_resubmitted'.
  final String type;
  final String title;
  final String body;
  final String? referenceId;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  factory AdminNotification.fromMap(Map<String, dynamic> map) {
    final rawMeta = map['metadata'];
    return AdminNotification(
      id: map['id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      referenceId: map['reference_id']?.toString(),
      isRead: map['is_read'] == true,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
              DateTime.now(),
      metadata: rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : null,
    );
  }

  AdminNotification copyWith({bool? isRead}) => AdminNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        referenceId: referenceId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        metadata: metadata,
      );

  /// '2m ago' / '3h ago' / '5d ago' — the same reading as the seller bell.
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  /// A resubmission notice opens the Business Docs queue; anything else
  /// added later simply has no destination until it says so.
  bool get opensBusinessDocsQueue => type == 'business_docs_resubmitted';
}

/// Read/write surface for the admin's own feed.
///
/// Row visibility is the database's job — the RLS policy on
/// `admin_notifications` returns only `auth.uid()`'s rows and only while
/// that account is an admin — so these queries carry no user filter. There
/// is no INSERT path here: rows are written by the resubmission trigger.
class AdminNotificationService {
  /// Not private: a widget test substitutes a fake transport, and the provider
  /// takes the service through its constructor for exactly that.
  AdminNotificationService();

  static final AdminNotificationService instance = AdminNotificationService();

  SupabaseClient get _client => Supabase.instance.client;

  /// Newest first — the feed as the admin reads it.
  Future<List<AdminNotification>> fetch({int limit = 50}) async {
    final data = await _client
        .from('admin_notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((row) => AdminNotification.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// The dashboard bell's number.
  Future<int> unreadCount() async {
    final data = await _client
        .from('admin_notifications')
        .select('id')
        .eq('is_read', false);
    return (data as List).length;
  }

  Future<void> markAsRead(String id) async {
    await _client
        .from('admin_notifications')
        .update({'is_read': true})
        .eq('id', id);
  }

  Future<void> markAllAsRead() async {
    await _client
        .from('admin_notifications')
        .update({'is_read': true})
        .eq('is_read', false);
  }
}

/// Logs and forgets: a feed failure must never take down the screen that
/// shows it (the dashboard's bell load runs on every open).
void debugAdminNotifications(Object error) =>
    debugPrint('[AdminNotifications] $error');
