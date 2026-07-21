import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../models/followed_store.dart';
import '../../providers/follow_provider.dart';
import '../../services/message_service.dart';
import '../../widgets/chat/chat_view.dart';
import '../store/store_profile_screen.dart';
import '../store/store_screen.dart';

/// Centered modal dialog listing every store the customer follows,
/// with swipe gestures and a ••• more-options button on each row.
class FollowingListDialog extends StatefulWidget {
  const FollowingListDialog({super.key});

  @override
  State<FollowingListDialog> createState() => _FollowingListDialogState();
}

class _FollowingListDialogState extends State<FollowingListDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        context.read<FollowProvider>().reconcileCount(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final followProvider = context.watch<FollowProvider>();

    // Fixed-size dialog — outer card never resizes as rows change.
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Following',
                      style: AppConstants.headlineStyle(fontSize: 20),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),

            // ── List (fills all remaining fixed space) ──────────
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                child: _buildDialogBody(followProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Dialog Body ───────────────────────────────────────────────
  Widget _buildDialogBody(FollowProvider followProvider) {
    if (!followProvider.isLoaded) return _buildLoadingState();
    if (followProvider.errorMessage != null) {
      return _buildErrorState(followProvider.errorMessage!);
    }
    if (followProvider.followedStores.isEmpty) return _buildEmptyState();
    return SlidableAutoCloseBehavior(
      closeWhenOpened: true,
      closeWhenTapped: true,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: followProvider.followedStores.length,
        separatorBuilder: (a, b) => const Divider(
          height: 1,
          color: Color(0xFFE5E7EB),
          indent: 72,
          endIndent: 16,
        ),
        itemBuilder: (context, index) {
          final store = followProvider.followedStores[index];
          return _FollowingRow(
            store: store,
            onUnfollow: () => _handleUnfollow(context, store),
            onMessage: () => _openConversation(context, store),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StoreProfileScreen(storeId: store.storeId),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ─── Unfollow Handler ──────────────────────────────────────────
  Future<void> _handleUnfollow(BuildContext context, FollowedStore store) async {
    final followProvider = context.read<FollowProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await followProvider.toggle(store.storeId);
    } catch (_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null && mounted) {
        await followProvider.loadForUser(userId);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Couldn't unfollow ${store.name}. Try again."),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Unfollowed ${store.name}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppConstants.primary,
          onPressed: () async {
            try {
              await followProvider.toggle(store.storeId);
            } catch (_) {
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text("Couldn't undo — try following again manually.")),
                );
              }
            }
          },
        ),
      ),
    );
  }

  // ─── Message Handler ───────────────────────────────────────────
  Future<void> _openConversation(BuildContext context, FollowedStore store) async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) return;

    try {
      final conversation = await MessageService.instance.getOrCreateConversation(
        storeId: store.storeId,
        customerId: customerId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            conversationId: conversation.id,
            viewerRole: 'customer',
            otherPartyName: store.name,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open chat: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  // ─── Loading State ─────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 14, color: Colors.grey.shade200),
                      const SizedBox(height: 6),
                      Container(width: 80, height: 12, color: Colors.grey.shade100),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ),
      ),
    );
  }

  // ─── Error State ───────────────────────────────────────────────
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppConstants.error.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(message, style: AppConstants.bodyStyle(fontSize: 14, color: AppConstants.secondary), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                final userId = Supabase.instance.client.auth.currentUser?.id;
                if (userId != null) context.read<FollowProvider>().loadForUser(userId);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(backgroundColor: AppConstants.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: AppConstants.borderGray),
            const SizedBox(height: 16),
            Text("You're not following any stores yet", style: AppConstants.bodyStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppConstants.secondary), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Discover artisan stores and tap Follow to see them here.', style: AppConstants.bodyStyle(fontSize: 13, color: AppConstants.secondary.withValues(alpha: 0.5)), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreScreen()));
              },
              style: OutlinedButton.styleFrom(side: BorderSide(color: AppConstants.primary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Browse Stores', style: AppConstants.bodyStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Following Row
// ══════════════════════════════════════════════════════════════════

class _FollowingRow extends StatelessWidget {
  final FollowedStore store;
  final VoidCallback onUnfollow;
  final VoidCallback onMessage;
  final VoidCallback onTap;

  const _FollowingRow({
    required this.store,
    required this.onUnfollow,
    required this.onMessage,
    required this.onTap,
  });

  /// Long-press / ••• tap opens an action sheet with Message/Unfollow.
  void _showActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Message'),
              onTap: () { Navigator.pop(ctx); onMessage(); },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_alt_1, color: Color(0xFFE74C3C)),
              title: const Text('Unfollow', style: TextStyle(color: Color(0xFFE74C3C))),
              onTap: () { Navigator.pop(ctx); onUnfollow(); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brandColor = AppConstants.parseBrandColor(store.color);
    final followerText = store.followerCount == 1 ? '1 follower' : '${store.followerCount} followers';
    final semLabel = '${store.name}, $followerText. Long press or tap ••• for options.';

    return GestureDetector(
      onLongPress: () => _showActionsSheet(context),
      child: Semantics(
        label: semLabel,
        button: true,
        child: Slidable(
          key: ValueKey(store.storeId),

          // Swipe RIGHT → Unfollow (auto-commits on full swipe, Gmail-style)
          startActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.28,
            dismissible: DismissiblePane(
              confirmDismiss: () async { HapticFeedback.mediumImpact(); return true; },
              onDismissed: () => onUnfollow(),
            ),
            children: [
              SlidableAction(
                onPressed: (_) { HapticFeedback.mediumImpact(); onUnfollow(); },
                backgroundColor: const Color(0xFFE74C3C),
                foregroundColor: Colors.white,
                icon: Icons.person_remove_alt_1,
                label: 'Unfollow',
                // Sharp corners — no borderRadius
              ),
            ],
          ),

          // Swipe LEFT → Message (tap required, no auto-trigger)
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.28,
            children: [
              SlidableAction(
                onPressed: (_) => onMessage(),
                backgroundColor: AppConstants.accent,
                foregroundColor: Colors.white,
                icon: Icons.chat_bubble_outline,
                label: 'Message',
                // Sharp corners — no borderRadius
              ),
            ],
          ),

          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  // ── Store avatar ─────────────────────────────
                  _buildAvatar(brandColor),
                  const SizedBox(width: 12),

                  // ── Name + tagline + follower count ─────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.name, style: AppConstants.bodyStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (store.tagline != null && store.tagline!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(store.tagline!, style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.secondary.withValues(alpha: 0.5)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 2),
                        Text(followerText, style: AppConstants.bodyStyle(fontSize: 11, color: AppConstants.secondary.withValues(alpha: 0.4))),
                      ],
                    ),
                  ),

                  // ── ••• more-options button (replaces "Following" pill) ──
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onPressed: () => _showActionsSheet(context),
                    tooltip: 'More options',
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(Color brandColor) {
    if (store.logoUrl != null && store.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(store.logoUrl!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsAvatar(brandColor)),
      );
    }
    return _initialsAvatar(brandColor);
  }

  Widget _initialsAvatar(Color brandColor) {
    final initials = store.name.isNotEmpty ? store.name[0].toUpperCase() : '?';
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: brandColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(initials, style: AppConstants.headlineStyle(fontSize: 18, color: brandColor))),
    );
  }
}
