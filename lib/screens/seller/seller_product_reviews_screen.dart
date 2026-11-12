import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/review_provider.dart';
import '../../utils/product_images.dart';
import '../../utils/sale_price.dart';
import '../../widgets/product_image_pager.dart';
import '../../widgets/seller_review_reply_card.dart';
import '../../widgets/sole_star_rating.dart';

/// The seller's view of ONE product, opened from the reviews grid.
///
/// Customer-style header (gallery, name, price, rating/sold) with a
/// reviews-only body — no buy bar, no size picker, no cart. Every review
/// keeps the reply composer so the seller answers from the same page.
class SellerProductReviewsScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String storeId;
  final int sold;

  const SellerProductReviewsScreen({
    super.key,
    required this.product,
    required this.storeId,
    this.sold = 0,
  });

  @override
  State<SellerProductReviewsScreen> createState() =>
      _SellerProductReviewsScreenState();
}

class _SellerProductReviewsScreenState
    extends State<SellerProductReviewsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ReviewProvider>();
      if (provider.storeReviews.isEmpty &&
          !provider.isLoadingStoreReviews) {
        provider.loadStoreReviews(widget.storeId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final productId = product['id']?.toString() ?? '';
    final name = product['name']?.toString() ?? 'Product';
    final photos = productImageUrls(product);

    final now = DateTime.now();
    final onSale = isOnSale(product, now: now);
    final displayPrice = effectivePrice(product, now: now);
    final double? originalPrice =
        (product['price'] as num?)?.toDouble();

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.chrome,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppConstants.bodyStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Consumer<ReviewProvider>(
        builder: (context, provider, _) {
          final reviews = provider.storeReviews
              .where((r) => r['product_id']?.toString() == productId)
              .toList();

          double avg = 0;
          if (reviews.isNotEmpty) {
            final total = reviews.fold<int>(
              0,
              (sum, r) => sum + (((r['rating'] as num?)?.toInt() ?? 0)),
            );
            avg = total / reviews.length;
          }

          return RefreshIndicator(
            color: AppConstants.primary,
            onRefresh: () =>
                provider.loadStoreReviews(widget.storeId),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Gallery (customer-style pager) ──
                  if (photos.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ProductImagePager(images: photos),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: AppConstants.bodyStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '₱${displayPrice.toStringAsFixed(2)}',
                        style: AppConstants.monoStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                      if (onSale && originalPrice != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '₱${originalPrice.toStringAsFixed(2)}',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary.withAlpha(128),
                          ).copyWith(
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (reviews.isNotEmpty) ...[
                        SoleStarRating(rating: avg, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          avg.toStringAsFixed(1),
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${reviews.length} review${reviews.length == 1 ? '' : 's'} • ${widget.sold} sold',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary.withAlpha(153),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    'Reviews',
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (provider.isLoadingStoreReviews && reviews.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(
                          color: AppConstants.primary,
                        ),
                      ),
                    )
                  else if (reviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Selling but no reviews yet — reviews from buyers will appear here.',
                          textAlign: TextAlign.center,
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary.withAlpha(153),
                          ),
                        ),
                      ),
                    )
                  else
                    ...reviews.map((review) => SellerReviewReplyCard(
                          review: review,
                          storeId: widget.storeId,
                        )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
