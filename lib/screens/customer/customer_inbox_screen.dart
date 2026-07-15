import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/message_provider.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/chat/chat_view.dart';

/// Customer's inbox screen showing all conversations with stores.
class CustomerInboxScreen extends StatefulWidget {
  const CustomerInboxScreen({super.key});

  @override
  State<CustomerInboxScreen> createState() => _CustomerInboxScreenState();
}

class _CustomerInboxScreenState extends State<CustomerInboxScreen> {
  String? _customerId;
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
    });

    // Auto-refresh when connection is restored
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        _loadConversations();
      }
      _wasOffline = !isOnline;
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _customerId = userId);
    context.read<MessageProvider>().loadConversationsForCustomer(userId);
    context.read<MessageProvider>().subscribeToInbox(customerId: userId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Messages',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
      ),
      body: provider.isLoadingConversations
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            )
          : provider.conversations.isEmpty
              ? _buildEmptyState()
              : _buildConversationList(provider),
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
              size: 64,
              color: AppConstants.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation with a store from their profile or an order.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(MessageProvider provider) {
    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: () async {
        if (_customerId != null) {
          await provider.loadConversationsForCustomer(_customerId!);
        }
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.conversations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 1),
        itemBuilder: (context, index) {
          final conv = provider.conversations[index];
          return _buildConversationTile(conv);
        },
      ),
    );
  }

  Widget _buildConversationTile(dynamic conv) {
    final provider = context.read<MessageProvider>();
    final unreadCount = provider.unreadCountFor(conv.id);
    final hasUnread = unreadCount > 0;

    return ListTile(
      tileColor: hasUnread
          ? AppConstants.primary.withValues(alpha: 0.05)
          : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppConstants.primary.withValues(alpha: 0.15),
          child: Text(
            (conv.storeName ?? 'S')[0].toUpperCase(),
            style: AppConstants.bodyStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                conv.storeName ?? 'Store',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                  color: AppConstants.secondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasUnread)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppConstants.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            conv.lastMessagePreview ?? 'No messages yet',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              color: hasUnread
                  ? AppConstants.secondary
                  : AppConstants.secondary.withValues(alpha: 0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Text(
          conv.relativeTime,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        onTap: () {
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
    );
  }
}
