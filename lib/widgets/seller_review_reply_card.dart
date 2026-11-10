import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../constants/seller_theme_constants.dart';
import '../providers/review_provider.dart';
import 'sole_review_card.dart';

/// One customer review with the seller's reply block and reply composer.
///
/// Shared by the seller reviews grid's product page (and any future seller
/// surface that needs to answer a review): read-only review card on top,
/// "Reply to review" CTA when unanswered, inline composer when replying.
class SellerReviewReplyCard extends StatefulWidget {
  final Map<String, dynamic> review;
  final String storeId;

  const SellerReviewReplyCard({
    super.key,
    required this.review,
    required this.storeId,
  });

  @override
  State<SellerReviewReplyCard> createState() => _SellerReviewReplyCardState();
}

class _SellerReviewReplyCardState extends State<SellerReviewReplyCard> {
  bool _isReplying = false;
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _togglePin() async {
    final review = widget.review;
    final reviewId = review['id'].toString();
    final productId = review['product_id']?.toString() ?? '';
    if (productId.isEmpty) return;
    final pinned = review['is_pinned'] == true;

    final provider = Provider.of<ReviewProvider>(context, listen: false);
    final success = await provider.togglePin(
      reviewId: reviewId,
      productId: productId,
      pinned: !pinned,
      storeId: widget.storeId,
    );

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pinned ? 'Review unpinned.' : 'Review pinned to top!'),
          backgroundColor: AppConstants.success,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to pin review'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  Future<void> _submitReply() async {
    final reply = _replyController.text.trim();
    if (reply.isEmpty) return;

    final provider = Provider.of<ReviewProvider>(context, listen: false);
    final reviewId = widget.review['id'].toString();

    final success = await provider.sellerReply(
      reviewId: reviewId,
      reply: reply,
      storeId: widget.storeId,
    );

    if (mounted && success) {
      setState(() {
        _isReplying = false;
        _replyController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply posted!'),
          backgroundColor: AppConstants.success,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to post reply'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemSize = widget.review['item_size']?.toString();
    final sellerReply = widget.review['seller_reply']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Size line (the product name lives on the page header above).
          if (itemSize != null && itemSize.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Size $itemSize',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Review card (read-only, with seller reply block)
          SoleReviewCard(
            review: widget.review,
            showSellerReply: true,
            showVerifiedBadge: true,
          ),

          // Reply + pin actions
          if (!_isReplying)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                children: [
                  if (sellerReply == null || sellerReply.isEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _isReplying = true),
                      child: Text(
                        'Reply to review',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ),
                  if ((sellerReply == null || sellerReply.isEmpty) &&
                      (widget.review['product_id']?.toString() ?? '')
                          .isNotEmpty)
                    const SizedBox(width: 16),
                  if ((widget.review['product_id']?.toString() ?? '')
                      .isNotEmpty)
                    GestureDetector(
                      onTap: _togglePin,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.review['is_pinned'] == true
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 14,
                            color: AppConstants.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            widget.review['is_pinned'] == true
                                ? 'Unpin'
                                : 'Pin review',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Reply text field
          if (_isReplying) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SellerTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SellerTheme.cardBorder),
                boxShadow: AppConstants.sellerShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Reply',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _replyController,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Write a reply to this review...',
                      hintStyle: AppConstants.bodyStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppConstants.sellerSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppConstants.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: AppConstants.bodyStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          _isReplying = false;
                          _replyController.clear();
                        }),
                        child: Text(
                          'Cancel',
                          style: AppConstants.bodyStyle(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submitReply,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          'Post Reply',
                          style: AppConstants.bodyStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
