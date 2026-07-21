import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_constants.dart';
import 'sole_star_rating.dart';

class SoleProductCard extends StatelessWidget {
  final dynamic product; // Can be a map or a model
  final VoidCallback onTap;
  final VoidCallback? onTryOnTap;

  /// When non-null, the image section uses [AspectRatio] instead of
  /// [Expanded], making the card self-sizing for masonry layouts.
  /// When null (default), the card fills its parent height as before.
  final double? imageAspectRatio;

  const SoleProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onTryOnTap,
    this.imageAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    // Gracefully handle dynamic Map or custom model data
    final String name = product['name'] ?? 'Artisan Shoe';
    final double price = (product['price'] is int)
        ? (product['price'] as int).toDouble()
        : (product['price'] ?? 0.0);
    final List<dynamic> images = product['images'] ?? [];
    final String imageUrl = images.isNotEmpty
        ? images.first
        : 'https://images.unsplash.com/photo-1549298916-b41d501d3772?q=80&w=600&auto=format&fit=crop';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: AppConstants.cardRadius,
          boxShadow: AppConstants.warmShadow,
          border: Border.all(
            color: AppConstants.primary.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: imageAspectRatio != null
              ? MainAxisSize.min
              : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top half: Hero image
            // When imageAspectRatio is provided, use AspectRatio (masonry).
            // Otherwise use Expanded (uniform grid fills parent height).
            if (imageAspectRatio != null)
              AspectRatio(
                aspectRatio: imageAspectRatio!,
                child: _buildImageSection(context, imageUrl),
              )
            else
              Expanded(
                child: _buildImageSection(context, imageUrl),
              ),
            // Bottom half: Name and Price details
            Padding(
              padding: const EdgeInsets.all(12.0),
              key: ValueKey('product_info_${product['id']}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Star rating (hide if no reviews)
                  if ((product['review_count'] as int? ?? 0) > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        SoleStarRating(
                          rating: ((product['avg_rating'] as num?)?.toDouble() ?? 0.0).round(),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${product['review_count']})',
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            color: AppConstants.secondary.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₱${price.toStringAsFixed(2)}',
                        style: AppConstants.monoStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                      Text(
                        product['category'] ?? 'Artisan',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color: AppConstants.secondary.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(BuildContext context, String imageUrl) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(15),
            topRight: Radius.circular(15),
          ),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (context, url) => Container(
              color: AppConstants.borderGray.withOpacity(0.3),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation(AppConstants.primary),
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppConstants.borderGray.withOpacity(0.3),
              child: const Icon(Icons.broken_image_outlined,
                  color: AppConstants.primary),
            ),
          ),
        ),
        // AR "Try On" sticker badge on top-right
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onTryOnTap ?? onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppConstants.accent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    size: 11,
                    color: AppConstants.secondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Try On',
                    style: AppConstants.bodyStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
