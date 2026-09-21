import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../utils/sale_price.dart';
import '../utils/compact_number.dart';
import '../utils/product_images.dart';
import 'product_image_pager.dart';
import 'press_sink.dart';
import 'sole_star_rating.dart';
import 'hanging_sale_tag.dart';
import 'sale_price_tape.dart';
import 'sale_countdown_overlay.dart';

/// The photo a product with none of its own falls back to.
const String _fallbackProductImage =
    'https://images.unsplash.com/photo-1549298916-b41d501d3772?q=80&w=600&auto=format&fit=crop';

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

  /// The card's outer surface — carries the 1px card edge. Exposed so widget
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
    final DateTime? saleEnd = DateTime.tryParse(
      product['sale_ends_at']?.toString() ?? '',
    );
    // Every photo, in the seller's order — the card pages through them (see
    // `ProductImagePager`), and a product with none uses the stand-in above.
    final List<String> images = productImageUrls(product);
    final List<String> photos = images.isEmpty
        ? const [_fallbackProductImage]
        : images;
    // The price's style, named once: a sale block and a plain block have to draw
    // the same number, and two copies of a style are two things to edit.
    final TextStyle priceStyle = AppConstants.monoStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: AppConstants.primary,
    );

    // The lift lives under the card, in `PressSink`, so a press can animate the
    // shadow without rebuilding this card (and its image, its text and its sale
    // overlay) on every frame of the way down — and so the fill, the radius and
    // the hairline stay this card's own.
    return PressSink(
      onTap: onTap,
      idle: AppConstants.productCardShadow,
      pressed: AppConstants.productCardShadowPressed,
      borderRadius: AppConstants.productCardRadius,
      child: Stack(
        // The hanging sale tag is allowed to overlap the card edge, so the
        // outer stack must not clip it.
        clipBehavior: Clip.none,
        children: [
          Container(
            key: hairlineKey,
            // Card fill and page are BOTH pure white, so this 1px hairline
            // is what actually draws the card's edge. Uses the neutral
            // hairline token rather than a tinted clay wash, which vanished
            // at 8% alpha. The 1px border also insets the child by 1px,
            // which is why the image clip below uses
            // [AppConstants.productCardImageRadius] — the card's corner less
            // that pixel — rather than this token verbatim.
            //
            // The lift is not here: `PressSink` paints it on the box directly
            // under this one, and animates it to the pressed weight while a
            // finger is on the card (see the two tokens). The poster cards
            // alongside this one deliberately stay flat.
            decoration: BoxDecoration(
              color: AppConstants.surfaceLight,
              borderRadius: AppConstants.productCardRadius,
              border: Border.all(color: AppConstants.cardEdge, width: 1),
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
                      photos,
                      onSale: onSale,
                      saleEndsAt: saleEnd,
                    ),
                  )
                else
                  Expanded(
                    child: _buildImageSection(
                      photos,
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
                                      rating:
                                          ((product['avg_rating'] as num?)
                                                      ?.toDouble() ??
                                                  0.0)
                                              .round(),
                                      size: 13,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ((product['avg_rating'] as num?)
                                                  ?.toDouble() ??
                                              0.0)
                                          .toStringAsFixed(1),
                                      style: AppConstants.bodyStyle(
                                        fontSize: 10,
                                        color: AppConstants.secondary
                                            .withValues(alpha: 0.5),
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
                                  color: AppConstants.secondary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 2),
                      if (onSale)
                        // The sale price (hidden behind a peel-away tape until
                        // the customer reveals it), the original under it — the
                        // two of them ONE tap target, which is what keeps this
                        // block a plain card's spacing ([SalePriceTape
                        // .targetBelow]) — and the category riding the number's
                        // line ([SalePriceTape.sameLine]). All three belong to
                        // the tape, because only the tape knows where the
                        // number's line is: handed the category as a sibling, it
                        // centers on the seam between the two prices.
                        //
                        // Vertical padding only: the horizontal half of the tap
                        // padding is what pushed the number 10px past every
                        // other line in the card — right of the original under
                        // it, right of the name above it, right of the same
                        // price on a card with no sale. The tape's own overhang
                        // is measured from the text, so its look is unchanged.
                        SalePriceTape(
                          productId: product['id']?.toString() ?? '',
                          hitPadding: const EdgeInsets.symmetric(vertical: 4),
                          sameLine: _categoryLabel(),
                          targetBelow: Text(
                            '₱${price.toStringAsFixed(2)}',
                            style: _originalPriceStyle,
                          ),
                          child: Text(
                            '₱${displayPrice.toStringAsFixed(2)}',
                            style: priceStyle,
                          ),
                        )
                      else
                        // A Wrap, not a Row: at the largest text scale a price
                        // and a category cannot both fit across a two-column
                        // card on a narrow phone, and a Row overflowed by ~148px
                        // doing the arithmetic. Wrapping drops the category onto
                        // its own line at that scale — nothing shrinks and
                        // nothing ellipsises, which matters most on a price
                        // ("₱1099…" is a different price; a shrunken one is at
                        // least true). On one line it is laid out exactly as the
                        // Row was, and the category centered against a one-line
                        // price is centered on it.
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 6,
                          children: [
                            Text(
                              '₱${price.toStringAsFixed(2)}',
                              style: priceStyle,
                            ),
                            _categoryLabel(),
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

  /// The strikethrough original price's style.
  ///
  /// Shared by the line itself and by the invisible twin that reserves that
  /// line's height on the price row (see [_categoryLabel]), so the two can never
  /// disagree about how tall the line is — which is what the alignment is built
  /// on.
  TextStyle get _originalPriceStyle => AppConstants.monoStyle(
    fontSize: 11,
    color: AppConstants.secondary.withValues(alpha: 0.5),
  ).copyWith(decoration: TextDecoration.lineThrough);

  /// The product's category, as the label beside the price.
  ///
  /// One widget, drawn in whichever of the two price blocks is in play. On a
  /// card with no sale the block's `Wrap` centers it against the price, which
  /// puts it on the price's line. On a sale card it is handed to
  /// [SalePriceTape.sameLine] instead, which centers it on the number's line the
  /// same way — see that field for why the tape, and not this card, has to own
  /// that placement.
  Widget _categoryLabel() {
    return Text(
      product['category'] ?? 'Artisan',
      style: AppConstants.bodyStyle(
        fontSize: 10,
        color: AppConstants.secondary.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildImageSection(
    List<String> photos, {
    required bool onSale,
    DateTime? saleEndsAt,
  }) {
    return ClipRRect(
      borderRadius: AppConstants.productCardImageRadius,
      child: ProductImagePager(
        images: photos,
        // The sale countdown — a gradient scrim band across the bottom of the
        // photo. A pure overlay (never affects masonry sizing or the HOT DEALS
        // grid contract), and only for sales that actually end (open-ended
        // sales with a NULL end date show nothing at all). It is handed to the
        // pager rather than stacked here so the swipe dots can sit *above* it
        // instead of on top of it.
        bottomOverlay: onSale && saleEndsAt != null
            ? SaleCountdownOverlay(saleEndsAt: saleEndsAt)
            : null,
      ),
    );
  }
}
