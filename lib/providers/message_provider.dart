import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/message_service.dart';

/// Holds conversations and messages state for messaging.
///
/// Exposed to both seller and customer sides via Provider.
class MessageProvider extends ChangeNotifier {
  final MessageService _service = MessageService.instance;

  List<Conversation> _conversations = [];
  List<Message> _messages = [];
  bool _isLoadingConversations = false;
  bool _isLoadingMessages = false;
  String? _activeConversationId;
  int _unreadCount = 0;

  /// Per-conversation unread message counts, keyed by conversation ID.
  /// Populated during loadConversationsForCustomer / loadConversationsForStore.
  Map<String, int> _perConversationUnreadCounts = {};

  /// Conversations that were optimistically marked as read by the user.
  /// Prevents `loadConversationsForCustomer` from overwriting the optimistic
  /// `0` with a stale DB count before `markConversationRead` commits.
  /// Cleared per-conversation when a new seller message arrives.
  final Set<String> _optimisticallyReadConversations = {};

  StreamSubscription<List<Map<String, dynamic>>>? _inboxSub;
  StreamSubscription<List<Map<String, dynamic>>>? _conversationSub;

  /// Stored IDs for refreshInbox() — set by load methods.
  String? _customerId;
  String? _storeId;

  // ── Public getters ─────────────────────────────────────────────

  List<Conversation> get conversations => _conversations;
  List<Message> get messages => _messages;
  bool get isLoadingConversations => _isLoadingConversations;
  bool get isLoadingMessages => _isLoadingMessages;
  String? get activeConversationId => _activeConversationId;
  int get unreadCount => _unreadCount;

  /// Per-conversation unread counts (keyed by conversation ID).
  Map<String, int> get perConversationUnreadCounts => _perConversationUnreadCounts;

  /// Total unread message count across all conversations.
  /// This is the sum of per-conversation unread counts (not just the number
  /// of conversations with unread messages).
  int get totalUnreadCount =>
      _perConversationUnreadCounts.values.fold<int>(0, (sum, c) => sum + c);

  /// Unread badge text (capped at 9+).
  /// Uses totalUnreadCount (sum of all unread messages across conversations).
  String get unreadBadge => totalUnreadCount > 9 ? '9+' : (totalUnreadCount > 0 ? '$totalUnreadCount' : '');

  /// Get unread count for a specific conversation.
  int unreadCountFor(String conversationId) =>
      _perConversationUnreadCounts[conversationId] ?? 0;

  // ── Load conversations ─────────────────────────────────────────

  Future<void> loadConversationsForStore(String storeId) async {
    _storeId = storeId;
    _isLoadingConversations = true;
    notifyListeners();

    try {
      _conversations = await _service.getConversationsForStore(storeId);
      // Calculate unread count per conversation
      final counts = <String, int>{};
      int total = 0;
      for (final conv in _conversations) {
        final count = await _service.getUnreadCount(
          conversationId: conv.id,
          readerType: 'seller',
        );
        counts[conv.id] = count;
        if (count > 0) total++;
      }
      _perConversationUnreadCounts = counts;
      _unreadCount = total;
    } catch (e) {
      debugPrint('[MessageProvider] loadConversationsForStore failed: $e');
    }

    _isLoadingConversations = false;
    notifyListeners();
  }

  Future<void> loadConversationsForCustomer(String customerId) async {
    _customerId = customerId;
    _isLoadingConversations = true;
    notifyListeners();

    try {
      _conversations = await _service.getConversationsForCustomer(customerId);
      // Calculate unread count per conversation
      final counts = <String, int>{};
      int total = 0;
      for (final conv in _conversations) {
        // Skip conversations that were optimistically marked as read —
        // keep their count at 0 until a new seller message arrives.
        if (_optimisticallyReadConversations.contains(conv.id)) {
          counts[conv.id] = 0;
          continue;
        }
        final count = await _service.getUnreadCount(
          conversationId: conv.id,
          readerType: 'customer',
        );
        counts[conv.id] = count;
        if (count > 0) total++;
      }
      _perConversationUnreadCounts = counts;
      _unreadCount = total;
    } catch (e) {
      debugPrint('[MessageProvider] loadConversationsForCustomer failed: $e');
    }

    _isLoadingConversations = false;
    notifyListeners();
  }

  /// Force-refresh conversations and unread counts from the database.
  /// Called on tap (before opening inbox/sheet) as a safety net
  /// to guarantee the badge and list reflect the true current state,
  /// even if a Realtime event was missed.
  /// Works for both customer and seller sides.
  Future<void> refreshInbox() async {
    if (_isLoadingConversations) return;
    if (_customerId != null) {
      await loadConversationsForCustomer(_customerId!);
    } else if (_storeId != null) {
      await loadConversationsForStore(_storeId!);
    }
  }

  // ── Optimistic mark-as-read ─────────────────────────────────

  /// Optimistically mark a conversation as read locally, without waiting
  /// for the server round-trip. This immediately zeros the per-conversation
  /// unread count and decrements the total, so the badge and row styling
  /// update instantly when the customer opens a conversation.
  ///
  /// The server-side `markConversationRead()` is called separately by
  /// ChatView; the realtime subscription will reconcile if needed.
  void optimisticMarkAsRead(String conversationId) {
    final previousCount = _perConversationUnreadCounts[conversationId] ?? 0;
    if (previousCount == 0) return; // already read, nothing to do

    _perConversationUnreadCounts[conversationId] = 0;
    if (_unreadCount > 0) _unreadCount--;
    _optimisticallyReadConversations.add(conversationId);
    notifyListeners();
  }

  // ── Load messages ──────────────────────────────────────────────

  Future<void> loadMessages(String conversationId, {String? readerType}) async {
    _activeConversationId = conversationId;
    _isLoadingMessages = true;
    notifyListeners();

    try {
      _messages = await _service.getMessages(conversationId);

      // Mark as read if readerType provided
      if (readerType != null) {
        await _service.markConversationRead(
          conversationId: conversationId,
          readerType: readerType,
        );
        // Update unread count in conversation list
        final convIndex = _conversations.indexWhere((c) => c.id == conversationId);
        if (convIndex != -1 && _unreadCount > 0) {
          _unreadCount--;
        }
        // Clear per-conversation unread count
        _perConversationUnreadCounts[conversationId] = 0;
      }
    } catch (e) {
      debugPrint('[MessageProvider] loadMessages failed: $e');
    }

    _isLoadingMessages = false;
    notifyListeners();
  }

  // ── Send message ───────────────────────────────────────────────

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderType,
    required String body,
    String? orderReferenceId,
  }) async {
    try {
      final message = await _service.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderType: senderType,
        body: body,
        orderReferenceId: orderReferenceId,
      );

      // Add to local messages list
      _messages.add(message);

      // Update conversation preview in list
      final convIndex = _conversations.indexWhere((c) => c.id == conversationId);
      if (convIndex != -1) {
        final old = _conversations[convIndex];
        _conversations[convIndex] = Conversation(
          id: old.id,
          storeId: old.storeId,
          customerId: old.customerId,
          lastMessageAt: message.createdAt,
          lastMessagePreview: body.length > 100 ? '${body.substring(0, 100)}...' : body,
          createdAt: old.createdAt,
          customerName: old.customerName,
          storeName: old.storeName,
          unreadCount: 0,
        );
        // Move to top of list
        final updated = _conversations.removeAt(convIndex);
        _conversations.insert(0, updated);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[MessageProvider] sendMessage failed: $e');
      rethrow;
    }
  }

  // ── Realtime subscriptions ─────────────────────────────────────

  /// Subscribe to conversation list updates (inbox).
  ///
  /// Listens to the conversations table filtered by [storeId] or [customerId].
  /// The DB trigger updates `last_message_at` / `last_message_preview`
  /// on every new message, so a conversation row change means new activity.
  void subscribeToInbox({
    String? storeId,
    String? customerId,
  }) {
    _inboxSub?.cancel();
    _inboxSub = _service.subscribeToInbox(
      storeId: storeId,
      customerId: customerId,
      onUpdate: () {
        // Reload conversations when new activity arrives.
        // Also clear any optimistic read states so fresh DB counts take effect.
        _optimisticallyReadConversations.clear();
        if (storeId != null) {
          loadConversationsForStore(storeId);
        } else if (customerId != null) {
          loadConversationsForCustomer(customerId);
        }
      },
    );
  }

  /// Subscribe to messages within a specific conversation.
  ///
  /// NOTE: ChatView manages its own _messages list and subscribes directly
  /// via MessageService. This method exists for any provider-based consumer
  /// that needs conversation-level message updates.
  void subscribeToConversation(String conversationId) {
    _conversationSub?.cancel();
    _activeConversationId = conversationId;
    _conversationSub = _service.subscribeToConversation(
      conversationId,
      (messages) {
        _messages = messages;
        notifyListeners();
      },
    );
  }

  void unsubscribeFromConversation() {
    _conversationSub?.cancel();
    _conversationSub = null;
    _activeConversationId = null;
  }

  // ── Cleanup ────────────────────────────────────────────────────

  @override
  void dispose() {
    _inboxSub?.cancel();
    _conversationSub?.cancel();
    super.dispose();
  }

  /// Reset state (for logout).
  void reset() {
    _conversations = [];
    _messages = [];
    _unreadCount = 0;
    _perConversationUnreadCounts = {};
    _optimisticallyReadConversations.clear();
    _activeConversationId = null;
    _customerId = null;
    _storeId = null;
    _inboxSub?.cancel();
    _conversationSub?.cancel();
    notifyListeners();
  }
}
