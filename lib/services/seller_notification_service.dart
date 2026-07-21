import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart'; // for MessagePreview

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
  final Map<String, dynamic>? metadata;

  const SellerNotification({
    required this.id,
    required this.storeId,
    required this.type,
    required this.title,
    required this.body,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  factory SellerNotification.fromMap(Map<String, dynamic> map) {
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

    return SellerNotification(
      id: map['id']?.toString() ?? '',
      storeId: map['store_id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      referenceId: map['reference_id']?.toString(),
      isRead: map['is_read'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      metadata: meta,
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

  // ── Batched message getters ─────────────────────────────────────

  /// Number of messages folded into this unread batch.
  int get messageCount =>
      (metadata?['message_count'] as num?)?.toInt() ?? 0;

  /// Typed list of message previews (newest first, max 3).
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
        .eq('is_deleted', false)
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
        .eq('is_read', false)
        .eq('is_deleted', false);

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
        .eq('is_read', false)
        .eq('is_deleted', false);
  }

  // ─── SOFT DELETE ───────────────────────────────────────────────

  /// Soft-delete a notification (hide from feed, allow undo).
  Future<void> deleteNotification(String notificationId) async {
    await _client
        .from('seller_notifications')
        .update({'is_deleted': true})
        .eq('id', notificationId);
  }

  /// Restore a soft-deleted notification (used by Undo snackbar).
  Future<void> restoreNotification(String notificationId) async {
    await _client
        .from('seller_notifications')
        .update({'is_deleted': false})
        .eq('id', notificationId);
  }

  /// Mark a notification as unread.
  Future<void> markAsUnread(String notificationId) async {
    await _client
        .from('seller_notifications')
        .update({'is_read': false})
        .eq('id', notificationId);
  }

  // ─── BULK OPERATIONS (Selection Mode) ──────────────────────────

  /// Soft-delete multiple notifications at once (selection mode).
  Future<void> deleteNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('seller_notifications')
        .update({'is_deleted': true})
        .inFilter('id', ids);
  }

  /// Restore multiple soft-deleted notifications (undo from selection mode).
  Future<void> restoreNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('seller_notifications')
        .update({'is_deleted': false})
        .inFilter('id', ids);
  }

  /// Mark multiple notifications as read (bulk selection mode).
  Future<void> markAsReadBulk(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('seller_notifications')
        .update({'is_read': true})
        .inFilter('id', ids);
  }

  /// Mark multiple notifications as unread (bulk selection mode).
  Future<void> markAsUnreadBulk(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('seller_notifications')
        .update({'is_read': false})
        .inFilter('id', ids);
  }

  // ─── CREATE (internal helpers) ──────────────────────────────────

  /// Insert a new notification record.
  Future<void> _create({
    required String storeId,
    required String type,
    required String title,
    required String body,
    String? referenceId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _client.from('seller_notifications').insert({
        'store_id': storeId,
        'type': type,
        'title': title,
        'body': body,
        'reference_id': referenceId,
        if (metadata != null) 'metadata': metadata,
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
    final title = 'New order #$shortId';
    final body = '₱${totalAmount.toStringAsFixed(0)} — tap to view';
    await _create(
      storeId: storeId,
      type: 'new_order',
      title: title,
      body: body,
      referenceId: orderId,
    );
    // Push to seller's device
    _triggerPush(
      storeId: storeId,
      type: 'new_order',
      title: title,
      body: body,
      referenceId: orderId,
      screen: 'seller_order_detail',
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
    final title = 'Order #$shortId needs attention';
    final body = 'Pending for $hoursPending hrs — tap to review';
    await _create(
      storeId: storeId,
      type: 'stale_order',
      title: title,
      body: body,
      referenceId: orderId,
    );
    // Push to seller's device (inside dedup guard — only fires when a new DB row is created)
    _triggerPush(
      storeId: storeId,
      type: 'stale_order',
      title: title,
      body: body,
      referenceId: orderId,
      screen: 'seller_order_detail',
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
    final title = '$productName (Size $size) — $stockMsg';
    final body = currentStock == 0 ? 'Restock needed' : 'Low on stock — tap to manage';
    await _create(
      storeId: storeId,
      type: 'low_stock',
      title: title,
      body: body,
      referenceId: productId,
    );
    // Push to seller's device (inside dedup guard — only fires when a new DB row is created)
    _triggerPush(
      storeId: storeId,
      type: 'low_stock',
      title: title,
      body: body,
      referenceId: productId,
      screen: 'seller_product_detail',
    );
  }

  /// Create or update a "new message" notification (upsert with batching).
  ///
  /// When an unread `new_message` notification already exists for this
  /// conversation, append the new message to `metadata.previews` (cap 3),
  /// increment `metadata.message_count`, and refresh title/body/created_at.
  /// Otherwise insert a fresh row with initial preview metadata.
  Future<void> createNewMessage({
    required String storeId,
    required String conversationId,
    required String senderName,
    required String body,
  }) async {
    final previewText = body.length > 80 ? '${body.substring(0, 80)}...' : body;
    final now = DateTime.now().toIso8601String();

    // Build the new preview entry
    final newPreview = {
      'sender': senderName,
      'text': previewText,
      'timestamp': now,
    };

    // Check for existing unread new_message notification for this conversation
    final existing = await _client
        .from('seller_notifications')
        .select('id, metadata')
        .eq('store_id', storeId)
        .eq('type', 'new_message')
        .eq('reference_id', conversationId)
        .eq('is_read', false)
        .eq('is_deleted', false)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      // ── UPDATE: append preview, increment count ─────────────
      final oldMeta = existing['metadata'] is Map
          ? Map<String, dynamic>.from(existing['metadata'] as Map)
          : <String, dynamic>{};

      List<dynamic> previews = (oldMeta['previews'] is List)
          ? List<dynamic>.from(oldMeta['previews'] as List)
          : [];

      // Prepend new preview, cap at 3
      previews = [newPreview, ...previews];
      if (previews.length > 3) {
        previews = previews.sublist(0, 3);
      }

      final oldCount = (oldMeta['message_count'] as num?)?.toInt() ?? 1;

      await _client
          .from('seller_notifications')
          .update({
            'title': 'New message from $senderName',
            'body': previewText,
            'created_at': now,
            'is_deleted': false,
            'metadata': {
              ...oldMeta,
              'previews': previews,
              'message_count': oldCount + 1,
            },
          })
          .eq('id', existing['id']);
    } else {
      // ── INSERT: fresh row with initial preview metadata ──────
      await _create(
        storeId: storeId,
        type: 'new_message',
        title: 'New message from $senderName',
        body: previewText,
        referenceId: conversationId,
        metadata: {
          'previews': [newPreview],
          'message_count': 1,
        },
      );
    }
  }

  /// Create a "custom order request" notification.
  Future<void> createCustomOrderRequest({
    required String storeId,
    required String requestId,
    required String customerName,
  }) async {
    final title = 'New custom order request';
    final body = 'From $customerName — tap to review';
    await _create(
      storeId: storeId,
      type: 'custom_order_request',
      title: title,
      body: body,
      referenceId: requestId,
    );
    // Push to seller's device
    _triggerPush(
      storeId: storeId,
      type: 'custom_order_request',
      title: title,
      body: body,
      referenceId: requestId,
      screen: 'seller_custom_order',
    );
  }

  // ─── PUSH NOTIFICATION HELPERS ────────────────────────────────

  /// Look up the store owner's user ID and send a push notification.
  /// Fire-and-forget — failures are caught and logged, never propagated.
  void _triggerPush({
    required String storeId,
    required String type,
    required String title,
    required String body,
    String? referenceId,
    String? screen,
  }) {
    try {
      _client
          .from('stores')
          .select('owner_id')
          .eq('id', storeId)
          .maybeSingle()
          .then((store) async {
        final ownerId = store?['owner_id']?.toString();
        if (ownerId == null) return;

        await _client.functions.invoke('send-notification-push', body: {
          'recipientUserId': ownerId,
          'title': title,
          'body': body,
          'type': type,
          if (referenceId != null) 'referenceId': referenceId,
          if (screen != null) 'screen': screen,
        });
      }).catchError((e) {
        debugPrint('[SellerNotification] Push trigger failed: $e');
      });
    } catch (e) {
      debugPrint('[SellerNotification] Push trigger failed: $e');
    }
  }
}
