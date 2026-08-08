import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../constants/app_constants.dart';
import '../../../models/store.dart';
import 'stitch_painter.dart';

/// A single hero card for the store carousel.
/// Displays the store brand gradient, stitch overlay, initials, open/closed
/// chip, store name, tagline, and stat pills.
class StoreHeroCard extends StatelessWidget {
  final Store store;
  final double scale;
  final int productCount;

  const StoreHeroCard({
    super.key,
    required this.store,
    this.scale = 1.0,
    this.productCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        height: 260,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: store.color.withAlpha(60),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Banner image or brand gradient background
              Positioned.fill(
                child: store.bannerUrl != null && store.bannerUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: store.bannerUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          decoration: BoxDecoration(
                            gradient: store.cardGradient,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            gradient: store.cardGradient,
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(gradient: store.cardGradient),
                      ),
              ),

              // Dark gradient overlay for text readability
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha(30),
                        Colors.black.withAlpha(160),
                      ],
                    ),
                  ),
                ),
              ),

              // Stitch texture overlay
              Positioned.fill(
                child: CustomPaint(painter: const StitchPainter()),
              ),

              // Card content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: logo avatar + open/closed chip
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Store logo or initials avatar
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppConstants.surfaceLight,
                          backgroundImage:
                              store.logoUrl != null && store.logoUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(store.logoUrl!)
                              : null,
                          child: store.logoUrl == null || store.logoUrl!.isEmpty
                              ? Text(
                                  store.initials,
                                  style: AppConstants.headlineStyle(
                                    fontSize: 20,
                                    color: AppConstants.secondary,
                                  ),
                                )
                              : null,
                        ),
                        // Open/closed chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: store.isOpen
                                ? AppConstants.success
                                : AppConstants.borderGray,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            store.isOpen ? 'OPEN' : 'CLOSED',
                            style: AppConstants.monoStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Store name
                    Text(
                      store.name,
                      style: AppConstants.headlineStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.surfaceLight,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Tagline
                    if (store.tagline != null && store.tagline!.isNotEmpty)
                      Text(
                        store.tagline!,
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          color: Colors.white.withAlpha(190),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                    // Store hours
                    if (store.hoursLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '🕘 ${store.hoursLabel}',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: Colors.white.withAlpha(210),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    const SizedBox(height: 14),

                    // Stat pills row
                    Row(
                      children: [
                        // Rating pill only once the store has reviews
                        // (stores.rating is NULL until the first review)
                        if (store.rating != null) ...[
                          _buildStatPill(
                            '⭐ ${store.rating!.toStringAsFixed(1)}',
                          ),
                          const SizedBox(width: 8),
                        ],
                        _buildStatPill('👟 $productCount'),
                        const SizedBox(width: 8),
                        Flexible(
                          child: _buildStatPill(
                            '📍 ${store.location.split(',').first}',
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
      ),
    );
  }

  Widget _buildStatPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(70), width: 1),
      ),
      child: Text(
        text,
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
