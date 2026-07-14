import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single seller notification record.
class SellerNotification {
  final String id;
  final String storeId;
  final String type; // 'new_order' | 'stale_order' | 'low_stock' | 'custom_order_request' | 'new_message'
  final String title;
  final String body;
  final String? referenceId;
  final bool isRead;
  final DateTime createdAt;

  const SellerNotification({
    required this.id,
    required this.storeId,
    required this.type,
    required this.title,
    required this.body,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
  });

  factory SellerNotification.fromMap(Map<String, dynamic> map) {
    return SellerNotification(
      id: map['id']?.toString() ?? '',
      storeId: map['store_id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      referenceId: map['reference_id']?.toString(),
      isRead: map['is_read'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Relative time string like "5 min ago", "3d ago".
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

/// Service for seller-scoped notifications (new orders, stale orders, low stock, custom requests).
///
/// Follows the same singleton pattern as other services in the app.
class SellerNotificationService {
  SellerNotificationService._();
  static final SellerNotificationService instance = SellerNotificationService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── READ ───────────────────────────────────────────────────────

  /// Fetch recent notifications for a store, newest first.
  Future<List<SellerNotification>> getNotifications(
    String storeId, {
    int limit = 50,
  }) async {
    final data = await _client
        .from('seller_notifications')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List)
        .map((row) => SellerNotification.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Count unread notifications for badge display.
  Future<int> getUnreadCount(String storeId) async {
    final data = await _client
        .from('seller_notifications')
        .select('id')
        .eq('store_id', storeId)
        .eq('is_read', false);

    return (data as List).length;
  }

  // ─── UPDATE ─────────────────────────────────────────────────────

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('seller_notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Mark all notifications for a store as read.
  Future<void> markAllAsRead(String storeId) async {
    await _client
        .from('seller_notifications')
        .update({'is_read': true})
        .eq('store_id', storeId)
        .eq('is_read', false);
  }

  // ─── CREATE (internal helpers) ──────────────────────────────────

  /// Insert a new notification record.
  Future<void> _create({
    required String storeId,
    required String type,
    required String title,
    required String body,
    String? referenceId,
  }) async {
    try {
      await _client.from('seller_notifications').insert({
        'store_id': storeId,
        'type': type,
        'title': title,
        'body': body,
        'reference_id': referenceId,
      });
    } catch (e) {
      debugPrint('[SellerNotification] Create failed: $e');
    }
  }

  /// Create a "new order" notification.
  Future<void> createNewOrder({
    required String storeId,
    required String orderId,
    required double totalAmount,
  }) async {
    final shortId = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
    await _create(
      storeId: storeId,
      type: 'new_order',
      title: 'New order #$shortId',
      body: '₱${totalAmount.toStringAsFixed(0)} — tap to view',
      referenceId: orderId,
    );
  }

  /// Create a "stale order" notification (deduplicated per order).
  Future<void> createStaleOrder({
    required String storeId,
    required String orderId,
    required int hoursPending,
  }) async {
    // Check if an unread stale_order notification already exists for this order
    final existing = await _client
        .from('seller_notifications')
        .select('id')
        .eq('store_id', storeId)
        .eq('type', 'stale_order')
        .eq('reference_id', orderId)
        .eq('is_read', false)
        .limit(1);

    if ((existing as List).isNotEmpty) return; // already notified

    final shortId = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
    await _create(
      storeId: storeId,
      type: 'stale_order',
      title: 'Order #$shortId needs attention',
      body: 'Pending for $hoursPending hrs — tap to review',
      referenceId: orderId,
    );
  }

  /// Create a "low stock" notification (deduplicated per product+size).
  Future<void> createLowStock({
    required String storeId,
    required String productId,
    required String productName,
    required String size,
    required int currentStock,
  }) async {
    // Check if an unread low_stock notification already exists for this product+size
    final existing = await _client
        .from('seller_notifications')
        .select('id')
        .eq('store_id', storeId)
        .eq('type', 'low_stock')
        .eq('reference_id', productId)
        .eq('is_read', false)
        .limit(1);

    if ((existing as List).isNotEmpty) return; // already notified

    final stockMsg = currentStock == 0
        ? 'out of stock'
        : '$currentStock left';
    await _create(
      storeId: storeId,
      type: 'low_stock',
      title: '$productName (Size $size) — $stockMsg',
      body: currentStock == 0 ? 'Restock needed' : 'Low on stock — tap to manage',
      referenceId: productId,
    );
  }

  /// Create a "new message" notification.
  Future<void> createNewMessage({
    required String storeId,
    required String conversationId,
    required String senderName,
    required String body,
  }) async {
    // Check if an unread new_message notification already exists for this conversation
    final existing = await _client
        .from('seller_notifications')
        .select('id')
        .eq('store_id', storeId)
        .eq('type', 'new_message')
        .eq('reference_id', conversationId)
        .eq('is_read', false)
        .limit(1);

    if ((existing as List).isNotEmpty) return; // already notified

    final preview = body.length > 80 ? '${body.substring(0, 80)}...' : body;
    await _create(
      storeId: storeId,
      type: 'new_message',
      title: 'New message from $senderName',
      body: preview,
      referenceId: conversationId,
    );
  }

  /// Create a "custom order request" notification.
  Future<void> createCustomOrderRequest({
    required String storeId,
    required String requestId,
    required String customerName,
  }) async {
    await _create(
      storeId: storeId,
      type: 'custom_order_request',
      title: 'New custom order request',
      body: 'From $customerName — tap to review',
      referenceId: requestId,
    );
  }

}
