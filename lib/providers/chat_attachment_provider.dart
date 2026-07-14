import 'package:flutter/foundation.dart';

import '../services/message_service.dart';

/// Holds failed attachment messages in memory so they survive widget rebuilds.
///
/// When a ChatView is rebuilt (e.g., navigating away and back), failed messages
/// that were only in the widget's `_messages` list would be lost. This provider
/// keeps them in memory keyed by conversation ID, so they can be re-merged
/// into the message list when the chat is reopened or refreshed.
class ChatAttachmentProvider extends ChangeNotifier {
  /// Failed messages keyed by conversation ID.
  final Map<String, List<Message>> _failedMessages = {};

  /// Get failed messages for a conversation.
  List<Message> getFailedMessages(String conversationId) {
    return _failedMessages[conversationId] ?? [];
  }

  /// Get all failed messages across all conversations.
  int get totalFailedCount {
    return _failedMessages.values.fold(0, (sum, msgs) => sum + msgs.length);
  }

  /// Add a failed message for a conversation.
  void addFailedMessage(Message message) {
    final conversationId = message.conversationId;
    _failedMessages.putIfAbsent(conversationId, () => []);
    // Replace if same ID exists (retry that failed again)
    final list = _failedMessages[conversationId]!;
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.add(message);
    }
    notifyListeners();
  }

  /// Remove a failed message (called after successful retry).
  void removeFailedMessage(String conversationId, String messageId) {
    final list = _failedMessages[conversationId];
    if (list != null) {
      list.removeWhere((m) => m.id == messageId);
      if (list.isEmpty) {
        _failedMessages.remove(conversationId);
      }
      notifyListeners();
    }
  }

  /// Clear all failed messages for a conversation.
  void clearFailedMessages(String conversationId) {
    _failedMessages.remove(conversationId);
    notifyListeners();
  }

  /// Merge failed messages into a list of DB messages.
  /// Failed messages are appended at the end (they haven't been sent to DB yet).
  List<Message> mergeWithFailed(List<Message> dbMessages, String conversationId) {
    final failed = getFailedMessages(conversationId);
    if (failed.isEmpty) return dbMessages;

    // Only include failed messages that aren't already in the DB list
    final dbIds = dbMessages.map((m) => m.id).toSet();
    final uniqueFailed = failed.where((m) => !dbIds.contains(m.id)).toList();

    return [...dbMessages, ...uniqueFailed];
  }
}
