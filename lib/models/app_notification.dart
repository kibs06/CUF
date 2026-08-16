import 'dart:convert';

import 'notification_category.dart';

/// A single message preview within a batched message notification.
class MessagePreview {
  final String sender;
  final String text;
  final DateTime timestamp;

  const MessagePreview({
    required this.sender,
    required this.text,
    required this.timestamp,
  });

  factory MessagePreview.fromMap(Map<String, dynamic> map) {
    return MessagePreview(
      sender: map['sender']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Data model for a single notification row from the `notifications` table.
class AppNotification {
  final String id;
  final String? orderId;
  final NotificationCategory category;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const AppNotification({
    required this.id,
    this.orderId,
    required this.category,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  // ── Convenience getters for message notifications ──────────────

  /// The conversation ID (only present for message notifications).
  String? get conversationId => metadata?['conversation_id']?.toString();

  /// The store/sender name (only present for message notifications).
  String? get storeName => metadata?['store_name']?.toString();

  /// The sender's user ID (only present for message notifications).
  String? get senderId => metadata?['sender_id']?.toString();

  /// Whether this is a message notification.
  bool get isMessageNotification => category == NotificationCategory.message;

  /// The report ID (only present for support/report notifications).
  String? get reportId => metadata?['report_id']?.toString();

  /// Whether this is a support/report notification.
  bool get isSupportNotification => category == NotificationCategory.support;

  /// The order type ('catalog', 'custom', or null).
  String? get orderType => metadata?['order_type']?.toString();

  // ── Batched message getters ─────────────────────────────────────

  /// Number of messages folded into this unread batch.
  /// Returns 0 if metadata.previews is absent (legacy row).
  int get messageCount =>
      (metadata?['message_count'] as num?)?.toInt() ?? 0;

  /// Typed list of message previews (newest first, max 3).
  /// Empty for legacy rows that predate batching.
  List<MessagePreview> get previews {
    final raw = metadata?['previews'];
    if (raw is! List) return const [];
    return raw
        .map((e) => MessagePreview.fromMap(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Whether this card represents a batch (>1 message folded in).
  bool get isBatched => messageCount > 1;

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    // Parse metadata — may come as JSON string or Map
    Map<String, dynamic>? meta;
    final rawMeta = map['metadata'];
    if (rawMeta is Map<String, dynamic>) {
      meta = rawMeta;
    } else if (rawMeta is String && rawMeta.isNotEmpty) {
      try {
        meta = jsonDecode(rawMeta) as Map<String, dynamic>;
      } catch (_) {}
    }

    return AppNotification(
      id: map['id']?.toString() ?? '',
      orderId: map['order_id']?.toString(),
      category: _parseCategory(map['category']?.toString() ?? ''),
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      metadata: meta,
    );
  }

  /// Friendly relative timestamp (e.g. "2h ago", "3d ago").
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  static NotificationCategory _parseCategory(String value) {
    switch (value) {
      case 'unpaid':
        return NotificationCategory.unpaid;
      case 'processing':
        return NotificationCategory.processing;
      case 'shipped':
        return NotificationCategory.shipped;
      case 'review':
        return NotificationCategory.review;
      case 'returns':
        return NotificationCategory.returns;
      case 'message':
        return NotificationCategory.message;
      case 'support':
        return NotificationCategory.support;
      case 'approval':
        return NotificationCategory.approval;
      default:
        return NotificationCategory.unpaid;
    }
  }
}
