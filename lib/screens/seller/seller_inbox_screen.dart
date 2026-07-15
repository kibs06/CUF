import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/message_provider.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/chat/chat_view.dart';

/// Seller's inbox screen showing all conversations with customers.
class SellerInboxScreen extends StatefulWidget {
  const SellerInboxScreen({super.key});

  @override
  State<SellerInboxScreen> createState() => _SellerInboxScreenState();
}

class _SellerInboxScreenState extends State<SellerInboxScreen> {
  String? _storeId;
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

    // Get store ID for this seller
    final store = await Supabase.instance.client
        .from('stores')
        .select('id')
        .eq('owner_id', userId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

    if (store != null && mounted) {
      final storeId = store['id']?.toString();
      if (storeId != null) {
        setState(() => _storeId = storeId);
        context.read<MessageProvider>().loadConversationsForStore(storeId);
        context.read<MessageProvider>().subscribeToInbox(storeId: storeId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageProvider>();

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Messages',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
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
              style: AppConstants.bodyStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When customers message your store, conversations will appear here.',
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
        if (_storeId != null) {
          await provider.loadConversationsForStore(_storeId!);
        }
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.conversations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 1),
        itemBuilder: (context, index) {
          final conv = provider.conversations[index];
          return _buildConversationTile(conv);
        },
      ),
    );
  }

  Widget _buildConversationTile(dynamic conv) {
    final hasUnread = conv.unreadCount > 0;

    return ListTile(
      tileColor: hasUnread
          ? AppConstants.primary.withValues(alpha: 0.05)
          : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppConstants.primary.withValues(alpha: 0.15),
          child: Text(
            (conv.customerName ?? 'C')[0].toUpperCase(),
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
                conv.customerName ?? 'Customer',
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
                  color: AppConstants.statusConfirmedColor,
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
                viewerRole: 'seller',
                otherPartyName: conv.customerName ?? 'Customer',
              ),
            ),
          );
        },
    );
  }
}
