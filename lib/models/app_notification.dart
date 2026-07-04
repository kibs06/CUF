import 'notification_category.dart';

/// Data model for a single notification row from the `notifications` table.
class AppNotification {
  final String id;
  final String? orderId;
  final NotificationCategory category;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    this.orderId,
    required this.category,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id']?.toString() ?? '',
      orderId: map['order_id']?.toString(),
      category: _parseCategory(map['category']?.toString() ?? ''),
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
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
      default:
        return NotificationCategory.unpaid;
    }
  }
}
