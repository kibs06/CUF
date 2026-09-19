import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_constants.dart';
import '../utils/sale_price.dart';
import '../utils/compact_number.dart';
import 'sole_star_rating.dart';
import 'hanging_sale_tag.dart';
import 'sale_price_tape.dart';
import 'sale_countdown_overlay.dart';

class SoleProductCard extends StatelessWidget {
  final dynamic product; // Can be a map or a model
  final VoidCallback onTap;

  /// When non-null, the image section uses [AspectRatio] instead of
  /// [Expanded], making the card self-sizing for masonry layouts.
  /// When null (default), the card fills its parent height as before.
  final double? imageAspectRatio;

  const SoleProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.imageAspectRatio,
  });

  /// The card's outer surface — carries the 1px hairline. Exposed so widget
  /// tests can assert the edge is never lightened back into invisibility on
  /// the (also white) page behind it.
  static const Key hairlineKey = Key('product-card-hairline');

  @override
  Widget build(BuildContext context) {
    // The sale-expiry watcher re-renders this card with a `now` past the
    // sale end the instant the countdown hits zero, so the hanging tag,
    // price tape and sale-price line all fall back to non-sale together —
    // no stale frozen sale UI on an idle screen.
    return SaleEndWatcher(
      product: product,
      builder: (context, now) => _buildCard(context, now),
    );
  }

  Widget _buildCard(BuildContext context, DateTime now) {
    // Gracefully handle dynamic Map or custom model data
    final String name = product['name'] ?? 'Artisan Shoe';
    final double price = (product['price'] is int)
        ? (product['price'] as int).toDouble()
        : (product['price'] ?? 0.0);
    // Sale-aware display values (single source of truth: sale_price.dart).
    // `now` comes from SaleEndWatcher — the sale expires the moment the
    // countdown reaches zero.
    final bool onSale = isOnSale(product, now: now);
    final double displayPrice = effectivePrice(product, now: now);
    final int? salePct = salePercent(product, now: now);
    final DateTime? saleEnd =
        DateTime.tryParse(product['sale_ends_at']?.toString() ?? '');
    final List<dynamic> images = product['images'] ?? [];
    final String imageUrl = images.isNotEmpty
        ? images.first
        : 'https://images.unsplash.com/photo-1549298916-b41d501d3772?q=80&w=600&auto=format&fit=crop';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        // The hanging sale tag is allowed to overlap the card edge, so the
        // outer stack must not clip it.
        clipBehavior: Clip.none,
        children: [
          Container(
            key: hairlineKey,
            // Card fill and page are BOTH pure white, so this 1px hairline
            // is what actually draws the card's edge (the warm shadow only
            // adds depth). Uses the neutral hairline token rather than a
            // tinted clay wash, which vanished at 8% alpha. The 1px border
            // also insets the child by 1px, which is why the image clip
            // below uses a 15px radius against this 16px card radius.
            decoration: BoxDecoration(
              color: AppConstants.surfaceLight,
              borderRadius: AppConstants.cardRadius,
              boxShadow: AppConstants.warmShadow,
              border: Border.all(
                color: AppConstants.borderGray,
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
                    child: _buildImageSection(
                      imageUrl,
                      onSale: onSale,
                      saleEndsAt: saleEnd,
                    ),
                  )
                else
                  Expanded(
                    child: _buildImageSection(
                      imageUrl,
                      onSale: onSale,
                      saleEndsAt: saleEnd,
                    ),
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
                      // Rating + sold-count row. Stars plus the exact
                      // average (e.g. 4.5) so customers see the precise
                      // score; the compact sold count (1k, 2.5m) sits on
                      // the right. Either can appear alone.
                      if ((product['review_count'] as int? ?? 0) > 0 ||
                          (product['units_sold'] as int? ?? 0) > 0) ...[
                        const SizedBox(height: 2),
                        // Also a Wrap (see the price row below for the full
                        // reasoning): the stars and the score are one unit that
                        // must stay together, and the sold count is the one that
                        // can move to its own line when the card is narrow at a
                        // large text scale — a Row here overflowed by 129px at
                        // 1.3x on a 132px card. The nested Row is `min` because
                        // a Wrap hands its children unbounded width.
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 6,
                          children: [
                            if ((product['review_count'] as int? ?? 0) > 0)
                              // Stars and score are one unit and must never be
                              // separated, and the stars are fixed-size graphics
                              // while the score doubles at a 2x scale — so at the
                              // top of the scale the pair needs ~141px in a
                              // ~108px card. `FittedBox` shrinks the pair rather
                              // than overflowing it, which keeps the score a real
                              // number (an ellipsised "4…" would not be one).
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SoleStarRating(
                                      rating: ((product['avg_rating'] as num?)?.toDouble() ?? 0.0).round(),
                                      size: 13,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ((product['avg_rating'] as num?)?.toDouble() ?? 0.0)
                                          .toStringAsFixed(1),
                                      style: AppConstants.bodyStyle(
                                        fontSize: 10,
                                        color: AppConstants.secondary.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if ((product['units_sold'] as int? ?? 0) > 0)
                              Text(
                                '${compactNumber(product['units_sold'] as int)} sold',
                                style: AppConstants.bodyStyle(
                                  fontSize: 10,
                                  color: AppConstants.secondary.withValues(alpha: 0.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 2),
                      // A Wrap, not a Row: at the largest text scale a price and
                      // a category cannot both fit across a two-column card on a
                      // narrow phone, and a Row overflowed by ~148px doing the
                      // arithmetic. Wrapping drops the category onto its own line
                      // at that scale — nothing shrinks and nothing ellipsises,
                      // which matters most on a price ("₱1099…" is a different
                      // price; a shrunken one is at least true). On one line it
                      // is laid out exactly as the Row was.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 6,
                        children: [
                          if (onSale) ...[
                            // Sale price (hidden behind a peel-away tape until
                            // the user reveals it) + always-visible original.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SalePriceTape(
                                  productId: product['id']?.toString() ?? '',
                                  child: Text(
                                    '₱${displayPrice.toStringAsFixed(2)}',
                                    style: AppConstants.monoStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppConstants.primary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₱${price.toStringAsFixed(2)}',
                                  style: AppConstants.monoStyle(
                                    fontSize: 11,
                                    color: AppConstants.secondary.withValues(alpha: 0.5),
                                  ).copyWith(
                                      decoration: TextDecoration.lineThrough),
                                ),
                              ],
                            ),
                          ] else
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
                              color: AppConstants.secondary.withValues(alpha: 0.6),
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
          // Hanging sale tag — clipped to the top-right corner, body dangling
          // off the edge. Purely an overlay (never affects masonry sizing or
          // the grid contract); the ~10px overhang stays inside the 16px grid
          // gutter so it never collides with a neighbor card.
          if (onSale)
            Positioned(
              top: 3,
              right: -10,
              child: HangingSaleTag(
                productId: product['id']?.toString() ?? '',
                salePercent: salePct,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageSection(
    String imageUrl, {
    required bool onSale,
    DateTime? saleEndsAt,
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(15),
        topRight: Radius.circular(15),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (context, url) => Container(
              color: AppConstants.borderGray.withValues(alpha: 0.3),
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
              color: AppConstants.borderGray.withValues(alpha: 0.3),
              child: const Icon(Icons.broken_image_outlined,
                  color: AppConstants.primary),
            ),
          ),
          // Sale countdown — a gradient scrim band across the bottom of the
          // image. A pure overlay (never affects masonry sizing or the HOT
          // DEALS grid contract), and only for sales that actually end
          // (open-ended sales with a NULL end date show nothing at all).
          if (onSale && saleEndsAt != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SaleCountdownOverlay(saleEndsAt: saleEndsAt),
            ),
        ],
      ),
    );
  }
}
