import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/review_provider.dart';
import '../../widgets/sole_star_rating.dart';
import '../../widgets/shimmer_group.dart';
import 'write_review_screen.dart';

/// Screen showing all items in a delivered order, each with a "Rate & Review"
/// button or the existing review summary. Shopee/Lazada-style per-item flow.
class OrderReviewScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderReviewScreen({super.key, required this.order});

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderId = widget.order['id'].toString();
      context.read<ReviewProvider>().loadOrderItems(orderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount =
        (widget.order['total_amount'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Rate Your Order',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer<ReviewProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingOrderItems) {
            return const _OrderReviewSkeleton();
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppConstants.error),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to load order items',
                      style: AppConstants.bodyStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final items = provider.orderItems;

          if (items.isEmpty) {
            return Center(
              child: Text(
                'No items found in this order.',
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            );
          }

          final reviewedCount = items.where((i) => i['review'] != null).length;
          final totalCount = items.length;

          return Column(
            children: [
              // Header card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppConstants.warmShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: reviewedCount == totalCount
                            ? AppConstants.success.withValues(alpha: 0.1)
                            : AppConstants.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        reviewedCount == totalCount
                            ? Icons.check_circle_outline
                            : Icons.rate_review_outlined,
                        color: reviewedCount == totalCount
                            ? AppConstants.success
                            : AppConstants.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reviewedCount == totalCount
                                ? 'All items reviewed!'
                                : 'Review your items',
                            style: AppConstants.bodyStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$reviewedCount of $totalCount items reviewed · ₱${totalAmount.toStringAsFixed(0)}',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Items list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final review = item['review'] as Map<String, dynamic>?;
                    final hasReview = review != null;

                    return _OrderItemCard(
                      item: item,
                      hasReview: hasReview,
                      review: review,
                      onTapReview: () => _navigateToReview(item),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _navigateToReview(Map<String, dynamic> item) async {
    final orderId = widget.order['id'].toString();
    final storeId = widget.order['store_id']?.toString();
    if (storeId == null || storeId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This order is missing store information. Cannot submit review.'),
          ),
        );
      }
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WriteReviewScreen(
          productId: item['product_id'].toString(),
          productName: item['product_name']?.toString() ?? 'Product',
          orderItemId: item['id'].toString(),
          orderId: orderId,
          storeId: storeId,
          existingReview: item['review'],
        ),
      ),
    );

    // Refresh if a review was submitted/updated
    if (result == true && mounted) {
      context.read<ReviewProvider>().loadOrderItems(orderId);
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// Order Item Card
// ══════════════════════════════════════════════════════════════════

class _OrderItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool hasReview;
  final Map<String, dynamic>? review;
  final VoidCallback onTapReview;

  const _OrderItemCard({
    required this.item,
    required this.hasReview,
    this.review,
    required this.onTapReview,
  });

  @override
  Widget build(BuildContext context) {
    final productName = item['product_name']?.toString() ?? 'Product';
    final size = item['size']?.toString() ?? '';
    final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
    final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = item['product_image_url']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTapReview,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppConstants.warmShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product row
              Row(
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                  const SizedBox(width: 12),

                  // Product info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [if (size.isNotEmpty) 'Size: $size', 'Qty: $quantity'].join(' · '),
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₱${unitPrice.toStringAsFixed(2)}',
                          style: AppConstants.monoStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  Icon(
                    Icons.chevron_right,
                    color: AppConstants.secondary.withValues(alpha: 0.3),
                  ),
                ],
              ),

              // Review status / CTA
              if (hasReview) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.success.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      SoleStarRating(
                        rating: (review!['rating'] as num?)?.toInt() ?? 0,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          review!['comment']?.toString() ?? 'Reviewed',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'Edit',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppConstants.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppConstants.primary.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star_outline_rounded,
                        size: 18,
                        color: AppConstants.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Rate & Review',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.shopping_bag_outlined, size: 24, color: AppConstants.primary),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Skeleton loading state — mirrors header card + order-item cards
// ══════════════════════════════════════════════════════════════════

class _OrderReviewSkeleton extends StatelessWidget {
  const _OrderReviewSkeleton();

  @override
  Widget build(BuildContext context) {
    // Default physics: keeps the skeleton scrollable if it's taller than
    // the viewport on short screens.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ShimmerGroup(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                SkeletonBox(width: 44, height: 44, borderRadius: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 150, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: double.infinity, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Item cards
          for (int i = 0; i < 3; i++) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 56, height: 56, borderRadius: 10),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 140, height: 14),
                            SizedBox(height: 8),
                            SkeletonBox(width: 100, height: 12),
                            SizedBox(height: 8),
                            SkeletonBox(width: 60, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  SkeletonBox(
                    width: double.infinity,
                    height: 38,
                    borderRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
        ),
      ),
    );
  }
}
