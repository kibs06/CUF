import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'review_thread_section.dart';
import 'review_vote_buttons.dart';
import 'sole_star_rating.dart';

/// Renders a single review: stars, comment, photos, reviewer name,
/// and an optional seller reply block.
class SoleReviewCard extends StatelessWidget {
  /// The review map. Expected keys:
  /// `rating`, `comment`, `created_at`, `reviewer_name`, `reviewer_avatar`,
  /// `is_verified`, `review_images`, `seller_reply`, `seller_reply_at`.
  final Map<String, dynamic> review;

  /// Show the seller-reply block when present.
  final bool showSellerReply;

  /// Show the "Verified Purchase" badge.
  final bool showVerifiedBadge;

  /// Show the helpful / not-helpful vote row.
  final bool showVotes;

  /// Show the discussion thread (author + customer replies). Hidden for
  /// demo reviews, whose ids exist only on-device.

  /// Show the discussion thread (author + customer replies). Hidden for
  /// demo reviews, whose ids exist only on-device.
  final bool showDiscussion;

  const SoleReviewCard({
    super.key,
    required this.review,
    this.showSellerReply = true,
    this.showVerifiedBadge = true,
    this.showVotes = true,
    this.showDiscussion = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDemo = review['is_demo'] == true;
    final reviewerName = review['reviewer_name']?.toString() ?? 'Customer';
    final reviewerAvatar = review['reviewer_avatar']?.toString();
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? review['body']?.toString() ?? '';
    final title = review['title']?.toString();
    final isVerified = review['is_verified'] as bool? ?? false;
    final createdAt = review['created_at']?.toString();
    final images = review['review_images'] as List<dynamic>? ?? [];
    final sellerReply = review['seller_reply']?.toString();
    final sellerReplyAt = review['seller_reply_at']?.toString();
    final isPinned = review['is_pinned'] == true;
    // DEMO ONLY: mock reviews carry `is_demo: true` (see
    // lib/data/demo_reviews.dart). They get a visible Demo pill and their
    // vote row is suppressed — fake ids exist only on-device, never in
    // the DB, so voting on them must stay impossible.

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Reviewer info row ──────────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppConstants.primary.withValues(alpha: 0.1),
                backgroundImage: reviewerAvatar != null && reviewerAvatar.isNotEmpty
                    ? NetworkImage(reviewerAvatar)
                    : null,
                child: reviewerAvatar == null || reviewerAvatar.isEmpty
                    ? Text(
                        reviewerName.isNotEmpty ? reviewerName[0].toUpperCase() : '?',
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            reviewerName,
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPinned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConstants.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.push_pin,
                                  size: 9,
                                  color: AppConstants.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Pinned',
                                  style: AppConstants.bodyStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // DEMO ONLY pill — marks mock reviews so they are
                        // never mistaken for real feedback. Remove with
                        // lib/data/demo_reviews.dart before real deployment.
                        if (isDemo) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7E57C2)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Demo',
                              style: AppConstants.bodyStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF7E57C2),
                              ),
                            ),
                          ),
                        ],
                        if (isVerified && showVerifiedBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConstants.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Verified',
                              style: AppConstants.bodyStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        SoleStarRating(rating: rating, size: 14),
                        if (_formatDate(createdAt).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(createdAt),
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Title ──────────────────────────────────────────
          if (title != null && title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              title,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
          ],

          // ── Comment ────────────────────────────────────────
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ],

          // ── Review images ──────────────────────────────────
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final img = images[index];
                  final url = img is Map ? img['image_url']?.toString() : null;
                  if (url == null || url.isEmpty) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => _openFullScreen(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          width: 80,
                          height: 80,
                          color: AppConstants.borderGray.withValues(alpha: 0.2),
                          child: const Icon(Icons.broken_image, size: 20),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // ── Helpfulness votes ──────────────────────────────
          // Demo reviews never reach the DB (a vote insert would violate
          // the review_votes FK), so instead of the DB-backed buttons
          // they get a local-only row: deterministic seeded counts, taps
          // flip the vote in-memory and never leave the device.
          if (showVotes &&
              (review['id']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            if (isDemo)
              _DemoVoteRow(reviewId: review['id'].toString())
            else
              ReviewVoteButtons(reviewId: review['id'].toString()),
          ],

          // ── Seller reply ───────────────────────────────────
          if (showSellerReply && sellerReply != null && sellerReply.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.primary.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.store_outlined,
                        size: 14,
                        color: AppConstants.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Seller Reply',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                      if (sellerReplyAt != null) ...[
                        const Spacer(),
                        Text(
                          _formatDate(sellerReplyAt),
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            color: AppConstants.secondary.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sellerReply,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Discussion thread (under the seller reply) ─────
          // Real reviews only: demo ids never reach the DB, so there is
          // no thread to load and no row a comment could reference.
          if (showDiscussion &&
              !isDemo &&
              (review['id']?.toString() ?? '').isNotEmpty)
            ReviewThreadSection(reviewId: review['id'].toString()),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }
}

/// Local-only thumbs up/down for demo reviews: seeded counts derived from
/// the review id (stable across rebuilds), one active vote at a time,
/// fully in-memory — nothing touches the database.
class _DemoVoteRow extends StatefulWidget {
  const _DemoVoteRow({required this.reviewId});

  final String reviewId;

  @override
  State<_DemoVoteRow> createState() => _DemoVoteRowState();
}

class _DemoVoteRowState extends State<_DemoVoteRow> {
  late int _helpful;
  late int _notHelpful;
  bool? _myVote;

  @override
  void initState() {
    super.initState();
    final seed = widget.reviewId.hashCode.abs();
    // Busier-looking reviews read as more "real" than flat zeros;
    // good reviews skew positive, bad ones skew negative.
    _helpful = 3 + (seed % 17);
    _notHelpful = seed % 4;
  }

  void _tap(bool value) {
    setState(() {
      if (_myVote == value) {
        // Tapping the active vote removes it.
        _myVote = null;
        if (value) {
          _helpful--;
        } else {
          _notHelpful--;
        }
      } else {
        if (_myVote == true) _helpful--;
        if (_myVote == false) _notHelpful--;
        _myVote = value;
        if (value) {
          _helpful++;
        } else {
          _notHelpful++;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Was this helpful?',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 2),
        _DemoVoteButton(
          selected: _myVote == true,
          count: _helpful,
          outlineIcon: Icons.thumb_up_outlined,
          filledIcon: Icons.thumb_up,
          semanticLabel: 'Mark review helpful',
          onTap: () => _tap(true),
        ),
        _DemoVoteButton(
          selected: _myVote == false,
          count: _notHelpful,
          outlineIcon: Icons.thumb_down_outlined,
          filledIcon: Icons.thumb_down,
          semanticLabel: 'Mark review not helpful',
          onTap: () => _tap(false),
        ),
      ],
    );
  }
}

/// Borderless vote button matching [ReviewVoteButtons] styling, minus the
/// spring animation and DB round-trip (demo-only, local state).
class _DemoVoteButton extends StatelessWidget {
  const _DemoVoteButton({
    required this.selected,
    required this.count,
    required this.outlineIcon,
    required this.filledIcon,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool selected;
  final int count;
  final IconData outlineIcon;
  final IconData filledIcon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? filledIcon : outlineIcon,
                size: 16,
                color: selected
                    ? AppConstants.primary
                    : AppConstants.secondary.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? AppConstants.primary
                      : AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
