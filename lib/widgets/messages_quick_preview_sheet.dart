import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../providers/message_provider.dart';
import '../screens/customer/customer_inbox_screen.dart';
import 'chat/chat_view.dart';
import '../services/message_service.dart';

/// Quick preview bottom sheet showing the customer's most recent conversations.
///
/// Opened by tapping the [FloatingMessageButton].
/// Shows top 3–5 conversations with store avatar, last message, time, and unread indicator.
/// Tapping a conversation navigates to ChatView.
/// Footer has "See all messages" → CustomerInboxScreen.
class MessagesQuickPreviewSheet extends StatefulWidget {
  const MessagesQuickPreviewSheet({super.key});

  @override
  State<MessagesQuickPreviewSheet> createState() =>
      _MessagesQuickPreviewSheetState();
}

class _MessagesQuickPreviewSheetState extends State<MessagesQuickPreviewSheet> {
  @override
  void initState() {
    super.initState();
    // Ensure conversations are loaded (but don't re-subscribe — the
    // home screen already manages the inbox subscription).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLoaded();
    });
  }

  Future<void> _ensureLoaded() async {
    if (!mounted) return;
    final provider = context.read<MessageProvider>();
    // Only fetch if conversations haven't been loaded yet
    if (provider.conversations.isEmpty) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await provider.loadConversationsForCustomer(userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageProvider>();
    final conversations = provider.conversations;
    final topConversations = conversations.take(5).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppConstants.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppConstants.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Messages',
                        style: AppConstants.headlineStyle(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppConstants.borderGray.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                color: AppConstants.borderGray,
                indent: 20,
                endIndent: 20,
              ),

              // Content
              Expanded(
                child: provider.isLoadingConversations
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppConstants.primary,
                        ),
                      )
                    : topConversations.isEmpty
                        ? _buildEmptyState()
                        : _buildConversationList(
                            topConversations, scrollController),
              ),

              // Footer: See all messages
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppConstants.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(); // close sheet first
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerInboxScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.all_inbox_outlined, size: 18),
                    label: Text(
                      'See all messages',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primary,
                      side: const BorderSide(color: AppConstants.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppConstants.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 14),
            Text(
              'No messages yet',
              style: AppConstants.headlineStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation from any store page.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(
    List<Conversation> conversations,
    ScrollController scrollController,
  ) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 1),
      itemBuilder: (context, index) {
        final conv = conversations[index];
        return _buildConversationTile(conv);
      },
    );
  }

  Widget _buildConversationTile(Conversation conv) {
    final provider = context.read<MessageProvider>();
    final unreadCount = provider.unreadCountFor(conv.id);
    final hasUnread = unreadCount > 0;
    final storeInitial = (conv.storeName ?? 'S').isNotEmpty
        ? (conv.storeName ?? 'S')[0].toUpperCase()
        : 'S';

    return Material(
      color: hasUnread
          ? AppConstants.primary.withValues(alpha: 0.05)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop(); // close sheet
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatView(
                conversationId: conv.id,
                viewerRole: 'customer',
                otherPartyName: conv.storeName ?? 'Store',
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Store avatar (initials circle)
              CircleAvatar(
                radius: 22,
                backgroundColor: AppConstants.primary.withValues(alpha: 0.12),
                child: Text(
                  storeInitial,
                  style: AppConstants.bodyStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Store name + time
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conv.storeName ?? 'Store',
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: AppConstants.secondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          conv.relativeTime,
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            color:
                                AppConstants.secondary.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Last message preview + unread indicator
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conv.lastMessagePreview ?? 'No messages yet',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                              color: hasUnread
                                  ? AppConstants.secondary
                                  : AppConstants.secondary
                                      .withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: const BoxDecoration(
                              color: AppConstants.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                unreadCount > 9
                                    ? '9+'
                                    : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppConstants.secondary.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
