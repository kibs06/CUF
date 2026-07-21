import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'seller_notification_service.dart';

/// A single message in a conversation.
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderType; // 'customer' | 'seller'
  final String? body;
  final String? orderReferenceId;
  final bool isRead;
  final DateTime createdAt;
  // Attachment fields
  final String? attachmentUrl;
  final String? attachmentType; // 'image' | 'video'
  final String? attachmentThumbnailUrl;
  final int? attachmentDurationSeconds;
  final int? attachmentSizeBytes;
  // Local-only fields (not persisted to DB)
  final bool isSending; // true while attachment upload is in progress
  final bool sendFailed; // true if upload/send failed
  final File? localFile; // local file reference for showing preview during upload
  final double progress; // 0.0–1.0 upload progress (local-only)

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderType,
    this.body,
    this.orderReferenceId,
    required this.isRead,
    required this.createdAt,
    this.attachmentUrl,
    this.attachmentType,
    this.attachmentThumbnailUrl,
    this.attachmentDurationSeconds,
    this.attachmentSizeBytes,
    this.isSending = false,
    this.sendFailed = false,
    this.localFile,
    this.progress = 0.0,
  });

  /// Create a copy with updated fields (useful for progress updates).
  Message copyWith({
    bool? isSending,
    bool? sendFailed,
    double? progress,
    String? attachmentUrl,
    String? attachmentThumbnailUrl,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderType: senderType,
      body: body,
      orderReferenceId: orderReferenceId,
      isRead: isRead,
      createdAt: createdAt,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentType: attachmentType,
      attachmentThumbnailUrl: attachmentThumbnailUrl ?? this.attachmentThumbnailUrl,
      attachmentDurationSeconds: attachmentDurationSeconds,
      attachmentSizeBytes: attachmentSizeBytes,
      isSending: isSending ?? this.isSending,
      sendFailed: sendFailed ?? this.sendFailed,
      localFile: localFile,
      progress: progress ?? this.progress,
    );
  }

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;
  bool get hasBody => body != null && body!.trim().isNotEmpty;
  bool get isImageMessage => attachmentType == 'image';
  bool get isVideoMessage => attachmentType == 'video';

  /// Preview text for notifications / inbox list.
  String get previewText {
    if (hasBody && hasAttachment) return body!;
    if (hasBody) return body!;
    if (isImageMessage) return '📷 Photo';
    if (isVideoMessage) return '🎥 Video';
    return '';
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id']?.toString() ?? '',
      conversationId: map['conversation_id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      senderType: map['sender_type']?.toString() ?? 'customer',
      body: map['body']?.toString(),
      orderReferenceId: map['order_reference_id']?.toString(),
      isRead: map['is_read'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      attachmentUrl: map['attachment_url']?.toString(),
      attachmentType: map['attachment_type']?.toString(),
      attachmentThumbnailUrl: map['attachment_thumbnail_url']?.toString(),
      attachmentDurationSeconds: (map['attachment_duration_seconds'] as num?)?.toInt(),
      attachmentSizeBytes: (map['attachment_size_bytes'] as num?)?.toInt(),
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

/// A conversation between a customer and a store.
class Conversation {
  final String id;
  final String storeId;
  final String customerId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final DateTime createdAt;

  // Enriched fields (loaded via joins)
  final String? customerName;
  final String? storeName;
  final int unreadCount;

  const Conversation({
    required this.id,
    required this.storeId,
    required this.customerId,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.createdAt,
    this.customerName,
    this.storeName,
    this.unreadCount = 0,
  });

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id']?.toString() ?? '',
      storeId: map['store_id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      lastMessageAt: DateTime.tryParse(map['last_message_at']?.toString() ?? ''),
      lastMessagePreview: map['last_message_preview']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      customerName: map['profiles'] is Map ? map['profiles']['full_name']?.toString() : null,
      storeName: map['stores'] is Map ? map['stores']['name']?.toString() : null,
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Relative time string for last message.
  String get relativeTime {
    if (lastMessageAt == null) return '';
    final diff = DateTime.now().difference(lastMessageAt!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

/// Service for seller-customer messaging.
///
/// Follows the same singleton pattern as other services in the app.
class MessageService {
  MessageService._();
  static final MessageService instance = MessageService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── CONVERSATIONS ────────────────────────────────────────────

  /// Get or create a conversation between a customer and a store.
  /// Customer-side only — creates if none exists.
  Future<Conversation> getOrCreateConversation({
    required String storeId,
    required String customerId,
  }) async {
    // Try to find existing conversation
    final existing = await _client
        .from('conversations')
        .select()
        .eq('store_id', storeId)
        .eq('customer_id', customerId)
        .maybeSingle();

    if (existing != null) {
      return Conversation.fromMap(Map<String, dynamic>.from(existing));
    }

    // Create new conversation (only customers can insert via RLS)
    final inserted = await _client
        .from('conversations')
        .insert({
          'store_id': storeId,
          'customer_id': customerId,
        })
        .select()
        .single();

    return Conversation.fromMap(Map<String, dynamic>.from(inserted));
  }

  /// Get conversations for a store (seller inbox).
  Future<List<Conversation>> getConversationsForStore(String storeId) async {
    final data = await _client
        .from('conversations')
        .select('*, profiles!conversations_customer_id_fkey(full_name)')
        .eq('store_id', storeId)
        .order('last_message_at', ascending: false, nullsFirst: true);

    return (data as List)
        .map((row) => Conversation.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Get conversations for a customer (customer inbox).
  Future<List<Conversation>> getConversationsForCustomer(String customerId) async {
    final data = await _client
        .from('conversations')
        .select('*, stores(name)')
        .eq('customer_id', customerId)
        .order('last_message_at', ascending: false, nullsFirst: true);

    return (data as List)
        .map((row) => Conversation.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Get unread message count for a conversation.
  Future<int> getUnreadCount({
    required String conversationId,
    required String readerType, // 'customer' | 'seller'
  }) async {
    final data = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .eq('sender_type', readerType == 'customer' ? 'seller' : 'customer')
        .eq('is_read', false);

    return (data as List).length;
  }

  /// Check if a conversation has any messages.
  Future<bool> hasMessages(String conversationId) async {
    final data = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .limit(1);

    return (data as List).isNotEmpty;
  }

  // ─── MESSAGES ─────────────────────────────────────────────────

  /// Get messages for a conversation, oldest first for display.
  Future<List<Message>> getMessages(String conversationId, {int limit = 50}) async {
    final data = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(limit);

    return (data as List)
        .map((row) => Message.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Send a message and update conversation metadata.
  ///
  /// [body] is now nullable — a message can be attachment-only.
  /// At least one of [body] or [attachmentUrl] must be provided.
  ///
  /// [id] is optional — if provided, the message row will use this ID
  /// (for matching storage paths). If null, Supabase generates one.
  Future<Message> sendMessage({
    String? id,
    required String conversationId,
    required String senderId,
    required String senderType,
    String? body,
    String? orderReferenceId,
    String? attachmentUrl,
    String? attachmentType,
    String? attachmentThumbnailUrl,
    int? attachmentDurationSeconds,
    int? attachmentSizeBytes,
  }) async {
    final hasBody = body != null && body.trim().isNotEmpty;
    final hasAttachment = attachmentUrl != null && attachmentUrl.isNotEmpty;
    if (!hasBody && !hasAttachment) {
      throw Exception('Message cannot be empty.');
    }

    // Insert message (use provided ID if given for storage path matching)
    final insertData = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_type': senderType,
      'body': hasBody ? body.trim() : null,
      'order_reference_id': orderReferenceId,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'attachment_thumbnail_url': attachmentThumbnailUrl,
      'attachment_duration_seconds': attachmentDurationSeconds,
      'attachment_size_bytes': attachmentSizeBytes,
    };
    if (id != null) insertData['id'] = id;

    final inserted = await _client
        .from('messages')
        .insert(insertData)
        .select()
        .single();

    // Update conversation metadata
    final preview = hasBody && hasAttachment
        ? body.trim()
        : hasBody
            ? (body.trim().length > 100 ? '${body.trim().substring(0, 100)}...' : body.trim())
            : attachmentType == 'image'
                ? '📷 Photo'
                : '🎥 Video';
    await _client
        .from('conversations')
        .update({
          'last_message_at': DateTime.now().toIso8601String(),
          'last_message_preview': preview,
        })
        .eq('id', conversationId);

    // Create notification for the other party
    await _createMessageNotification(
      conversationId: conversationId,
      senderId: senderId,
      senderType: senderType,
      body: hasBody ? body.trim() : (attachmentType == 'image' ? '📷 Photo' : '🎥 Video'),
    );

    return Message.fromMap(Map<String, dynamic>.from(inserted));
  }

  /// Upload an attachment to the message-attachments storage bucket.
  ///
  /// Returns a map with the upload result URL and metadata.
  /// The upload path follows the convention:
  ///   message-attachments/{conversation_id}/{message_id}/{filename}
  ///
  /// [onProgress] is called with a value between 0.0 and 1.0 during upload.
  /// Progress is tracked via chunked file reads: 0.0–0.85 during the read
  /// phase (real byte-level progress), 0.85–1.0 during the network upload.
  Future<Map<String, dynamic>> uploadAttachment({
    required String conversationId,
    required String messageId,
    required String filePath,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    final ext = filePath.split('.').last.toLowerCase();
    final filename = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final storagePath = '$conversationId/$messageId/$filename';

    // Validate MIME type is one the bucket accepts before uploading
    const allowedTypes = {
      'image/jpeg', 'image/png', 'image/webp', 'image/gif',
      'video/mp4', 'video/quicktime', 'video/quicktime-mov',
    };
    if (!allowedTypes.contains(mimeType)) {
      throw UnsupportedError(
        'MIME type "$mimeType" is not allowed by the message-attachments bucket. '
        'Allowed: ${allowedTypes.join(', ')}',
      );
    }

    // ── Chunked file read with real byte-level progress ──
    // Read the file in 1 MB chunks and report progress as bytes read / total.
    // The read phase accounts for 0.0–0.85 of the total progress bar;
    // the network upload accounts for 0.85–1.0.
    const chunkSize = 1024 * 1024; // 1 MB
    final sizeBytes = await file.length();
    final raf = await file.open(mode: FileMode.read);
    final allBytes = <int>[];
    try {
      int bytesRead = 0;
      while (bytesRead < sizeBytes) {
        final remaining = sizeBytes - bytesRead;
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        allBytes.addAll(chunk);
        bytesRead += chunk.length;
        // Report read progress (0.0 → 0.85)
        onProgress?.call((bytesRead / sizeBytes) * 0.85);
      }
    } finally {
      await raf.close();
    }

    // ── Network upload via uploadBinary ──
    onProgress?.call(0.85);
    try {
      await _client.storage.from('message-attachments').uploadBinary(
        storagePath,
        Uint8List.fromList(allBytes),
        fileOptions: FileOptions(
          contentType: mimeType,
          upsert: false,
        ),
      );
    } on StorageException catch (e) {
      debugPrint('[MessageService] Storage upload failed: ${e.message} (status ${e.statusCode})');
      rethrow;
    } catch (e) {
      debugPrint('[MessageService] Upload failed: $e');
      rethrow;
    }
    onProgress?.call(1.0);

    // Get the signed URL (private bucket — not public)
    // Use 1-year expiry so old messages don't break
    final signedUrl = await _client.storage
        .from('message-attachments')
        .createSignedUrl(storagePath, 3600 * 24 * 365);

    return {
      'url': signedUrl,
      'storagePath': storagePath,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
    };
  }

  /// Generate a video thumbnail and return its storage path + signed URL.
  Future<Map<String, String>?> generateVideoThumbnail({
    required String conversationId,
    required String messageId,
    required String videoPath,
  }) async {
    try {
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        quality: 70,
        maxWidth: 300,
      );
      if (thumbnailBytes == null || thumbnailBytes.isEmpty) return null;

      final thumbnailPath = '$conversationId/$messageId/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Upload thumbnail as bytes
      await _client.storage.from('message-attachments').uploadBinary(
        thumbnailPath,
        thumbnailBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );

      final signedUrl = await _client.storage
          .from('message-attachments')
          .createSignedUrl(thumbnailPath, 3600 * 24 * 7);

      return {
        'url': signedUrl,
        'storagePath': thumbnailPath,
      };
    } catch (e) {
      debugPrint('[MessageService] generateVideoThumbnail failed: $e');
      return null;
    }
  }

  /// Mark messages from the other party as read.
  /// Uses the `mark_conversation_read` RPC (SECURITY DEFINER) because
  /// there is no client-side UPDATE policy on the messages table.
  Future<void> markConversationRead({
    required String conversationId,
    required String readerType, // 'customer' | 'seller'
  }) async {
    await _client.rpc('mark_conversation_read', params: {
      'convo_id': conversationId,
      'reader_role': readerType,
    });
  }

  // ─── REALTIME SUBSCRIPTIONS ───────────────────────────────────

  /// Subscribe to messages in a conversation via Realtime.
  ///
  /// The stream emits the full filtered message list after each DB change,
  /// so the caller should replace its local list with the emitted data
  /// rather than appending individual messages.
  StreamSubscription<List<Map<String, dynamic>>> subscribeToConversation(
    String conversationId,
    void Function(List<Message> messages) onMessagesChanged,
  ) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .listen((data) {
          final messages = data
              .map((row) => Message.fromMap(Map<String, dynamic>.from(row)))
              .toList();
          // Explicitly sort oldest-first to guarantee correct chat order
          messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          onMessagesChanged(messages);
        });
  }

  /// Subscribe to inbox updates via the conversations table.
  ///
  /// The DB trigger already updates `last_message_at` and
  /// `last_message_preview` on every new message, so subscribing to
  /// conversation row changes is the correct and efficient approach —
  /// instead of listening to every message insert across all conversations.
  StreamSubscription<List<Map<String, dynamic>>> subscribeToInbox({
    String? storeId,
    String? customerId,
    required void Function() onUpdate,
  }) {
    assert(storeId != null || customerId != null, 'Provide storeId or customerId');
    final filterColumn = storeId != null ? 'store_id' : 'customer_id';
    final filterValue = storeId ?? customerId!;

    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq(filterColumn, filterValue)
        .order('last_message_at', ascending: false)
        .order('created_at', ascending: false)
        .listen((_) {
          onUpdate();
        });
  }

  // ─── TYPING INDICATOR (Broadcast Channels) ──────────────────

  /// Shared channel per conversation for typing broadcasts.
  final Map<String, RealtimeChannel> _typingChannels = {};

  /// Get or create a shared typing channel for a conversation.
  RealtimeChannel _getTypingChannel(String conversationId) {
    return _typingChannels.putIfAbsent(
      conversationId,
      () => _client.channel('typing:$conversationId'),
    );
  }

  /// Broadcast a typing start event on the conversation's Realtime channel.
  void sendTypingStart({
    required String conversationId,
    required String senderId,
    required String senderType,
  }) {
    try {
      _getTypingChannel(conversationId).sendBroadcastMessage(
        event: 'typing',
        payload: {
          'sender_id': senderId,
          'sender_type': senderType,
          'is_typing': true,
        },
      );
    } catch (e) {
      debugPrint('[MessageService] sendTypingStart failed: $e');
    }
  }

  /// Broadcast a typing stop event on the conversation's Realtime channel.
  void sendTypingStop({
    required String conversationId,
    required String senderId,
    required String senderType,
  }) {
    try {
      _getTypingChannel(conversationId).sendBroadcastMessage(
        event: 'typing',
        payload: {
          'sender_id': senderId,
          'sender_type': senderType,
          'is_typing': false,
        },
      );
    } catch (e) {
      debugPrint('[MessageService] sendTypingStop failed: $e');
    }
  }

  /// Subscribe to typing events from the other party.
  /// Returns the RealtimeChannel so the caller can unsubscribe.
  RealtimeChannel subscribeToTyping({
    required String conversationId,
    required String senderId,
    required String senderType,
    required void Function(bool isTyping) onTypingChanged,
  }) {
    final otherType = senderType == 'customer' ? 'seller' : 'customer';
    final channel = _getTypingChannel(conversationId);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final eventSenderId = payload['sender_id']?.toString();
        final eventSenderType = payload['sender_type']?.toString();
        final isTyping = payload['is_typing'] == true;

        // Only show typing from the OTHER party
        if (eventSenderType == otherType && eventSenderId != senderId) {
          onTypingChanged(isTyping);
        }
      },
    );
    channel.subscribe();
    return channel;
  }

  /// Unsubscribe from a typing channel.
  void unsubscribeFromTyping(RealtimeChannel channel, {String? conversationId}) {
    _client.removeChannel(channel);
    if (conversationId != null) {
      _typingChannels.remove(conversationId);
    }
  }

  // ─── NOTIFICATION INTEGRATION ─────────────────────────────────

  /// Create a notification for the recipient of a new message.
  /// For seller→customer messages, also triggers the FCM push via Edge Function.
  Future<void> _createMessageNotification({
    required String conversationId,
    required String senderId,
    required String senderType,
    required String body,
  }) async {
    try {
      // Get conversation details to find the recipient
      final convData = await _client
          .from('conversations')
          .select('store_id, customer_id')
          .eq('id', conversationId)
          .single();

      final storeId = convData['store_id']?.toString();
      final customerId = convData['customer_id']?.toString();

      if (storeId == null || customerId == null) return;

      // Determine recipient based on sender type
      if (senderType == 'customer') {
        // Notify the seller — via SellerNotificationService (deduplication built in)
        // Look up customer name for the notification title
        final senderProfile = await _client
            .from('profiles')
            .select('full_name')
            .eq('id', senderId)
            .maybeSingle();
        final senderName = senderProfile?['full_name']?.toString() ?? 'Customer';
        SellerNotificationService.instance.createNewMessage(
          storeId: storeId,
          conversationId: conversationId,
          senderName: senderName,
          body: body,
        ); // intentionally not awaited
        // Also trigger FCM push to notify the seller on their device
        _triggerPushNotification(
          conversationId: conversationId,
          senderId: senderId,
          senderType: senderType,
          body: body,
        );
      } else {
        // Notify the customer — the DB trigger `notify_on_new_message`
        // handles inserting the notification record into the `notifications`
        // table. Here we only trigger the FCM push via Edge Function.
        _triggerPushNotification(
          conversationId: conversationId,
          senderId: senderId,
          senderType: senderType,
          body: body,
        );
      }
    } catch (e) {
      debugPrint('[MessageService] Notification creation failed: $e');
      // Don't fail the message send if notification fails
    }
  }

  /// Trigger an FCM push notification via the Supabase Edge Function.
  /// This is fire-and-forget — a push failure doesn't block the message send.
  void _triggerPushNotification({
    required String conversationId,
    required String senderId,
    required String senderType,
    required String body,
  }) {
    try {
      // Single join query: conversation → store name
      _client
          .from('conversations')
          .select('store_id, stores(name)')
          .eq('id', conversationId)
          .maybeSingle()
          .then((conv) async {
        if (conv == null) return;
        final storeName = conv['stores'] is Map
            ? (conv['stores']['name']?.toString() ?? 'Store')
            : 'Store';

        // Call the Edge Function (fire-and-forget)
        await _client.functions.invoke('send-message-push', body: {
          'conversation_id': conversationId,
          'sender_id': senderId,
          'sender_type': senderType,
          'body': body,
          'store_name': storeName,
        });
      }).catchError((e) {
        debugPrint('[MessageService] Push notification trigger failed: $e');
      });
    } catch (e) {
      debugPrint('[MessageService] Push notification trigger failed: $e');
    }
  }
}
