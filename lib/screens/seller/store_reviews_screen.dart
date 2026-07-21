import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../../constants/app_constants.dart';
import '../../providers/review_provider.dart';
import '../../widgets/sole_star_rating.dart';
import '../../widgets/sole_review_card.dart';

/// Seller-facing screen showing all reviews for their store's products.
/// Sellers can view reviews and post public replies.
class SellerReviewsScreen extends StatefulWidget {
  final String storeId;

  const SellerReviewsScreen({super.key, required this.storeId});

  @override
  State<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends State<SellerReviewsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReviewProvider>().loadStoreReviews(widget.storeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Customer Reviews',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer<ReviewProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingStoreReviews) {
            return const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            );
          }

          final reviews = provider.storeReviews;

          if (reviews.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppConstants.primary.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rate_review_outlined,
                        size: 34,
                        color: AppConstants.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No reviews yet',
                      style: AppConstants.bodyStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Customer reviews will appear here\nonce they rate their orders.',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withAlpha(153),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Calculate aggregate stats
          double avgRating = 0;
          if (reviews.isNotEmpty) {
            final total = reviews.fold<int>(
              0,
              (sum, r) => sum + ((r['rating'] as num?)?.toInt() ?? 0),
            );
            avgRating = total / reviews.length;
          }

          return RefreshIndicator(
            color: AppConstants.primary,
            onRefresh: () => provider.loadStoreReviews(widget.storeId),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppConstants.sellerShadow,
                  ),
                  child: Row(
                    children: [
                      Column(
                        children: [
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: AppConstants.monoStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                          ),
                          SoleStarRating(
                            rating: avgRating.round(),
                            size: 16,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Reviews list
                ...reviews.map((review) => _SellerReviewCard(
                      review: review,
                      storeId: widget.storeId,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Seller Review Card (with reply capability)
// ══════════════════════════════════════════════════════════════════

class _SellerReviewCard extends StatefulWidget {
  final Map<String, dynamic> review;
  final String storeId;

  const _SellerReviewCard({required this.review, required this.storeId});

  @override
  State<_SellerReviewCard> createState() => _SellerReviewCardState();
}

class _SellerReviewCardState extends State<_SellerReviewCard> {
  bool _isReplying = false;
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
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
    final productName = widget.review['product_name']?.toString() ?? '';
    final itemSize = widget.review['item_size']?.toString();
    final sellerReply = widget.review['seller_reply']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product info
          if (productName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$productName${itemSize != null ? ' · $itemSize' : ''}',
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

          // Reply CTA (if not replying and no existing reply)
          if (!_isReplying && sellerReply == null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: GestureDetector(
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
            ),

          // Reply text field
          if (_isReplying) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
