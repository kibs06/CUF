import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/sale_price.dart';
import 'press_sink.dart';
import 'sale_countdown_overlay.dart';
import 'sale_price_tape.dart';

/// A compact 130px-wide horizontal strip card shared by the profile's
/// "Recently Viewed" and "Buy Again" sections.
///
/// Renders the product's thumbnail with a compact countdown band when the
/// sale actually ends, the name, and the effective (sale-aware) price — the
/// sale price hides behind the peel-away tape while the original stays
/// struck through, exactly like the catalog cards.
///
/// [product] is the LIVE catalog product (drives price, sale state and
/// expiry); the fallback fields are used only if the product map is empty.
class HorizontalProductCard extends StatelessWidget {
  const HorizontalProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.fallbackImageUrl = '',
    this.fallbackName = '',
    this.fallbackPrice = 0,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;

  final String fallbackImageUrl;
  final String fallbackName;
  final double fallbackPrice;

  static const Key cardEdgeKey = Key('rail-card-edge');
  static const Key thumbnailHairlineKey = cardEdgeKey;

  /// How far the name and the price stand off the card's own edge, each side.
  ///
  /// The strip is only 130px wide and its type was laid out flush against the
  /// card, so the first glyph of the name and of the price sat *on* the 1px
  /// hairline — the block read as bleeding out of the tile rather than as a
  /// caption inside it. Eight px is the product card's own 12 at this card's
  /// scale (~6% of the width), and it still leaves ~112px of line for the name.
  static const double textInset = 8;

  /// First product image, preferring `product_images` (sorted by
  /// display_order) and falling back to the flat `images` list.
  static String firstImage(Map<String, dynamic> product, String fallback) {
    final raw = product['product_images'] as List? ?? [];
    if (raw.isNotEmpty && raw.first is Map) {
      final images = List<Map<String, dynamic>>.from(raw);
      images.sort(
        (a, b) => ((a['display_order'] ?? 0) as num).compareTo(
          ((b['display_order'] ?? 0) as num),
        ),
      );
      final url = images.first['image_url']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    final flat = product['images'] as List? ?? [];
    if (flat.isNotEmpty) return flat.first.toString();
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? stripEnd = DateTime.tryParse(
      product['sale_ends_at']?.toString() ?? '',
    );
    // The expiry watcher re-renders this card with a `now` past the sale
    // end, so the compact countdown and the sale price fall back to
    // non-sale together when it expires.
    return SaleEndWatcher(
      product: product,
      builder: (context, now) {
        final bool onSale = isOnSale(product, now: now);
        final double livePrice = effectivePrice(product, now: now);
        final double originalPrice =
            ((product['price'] is num) ? (product['price'] as num) : 0)
                .toDouble();
        final String name = product['name']?.toString().isNotEmpty == true
            ? product['name']!.toString()
            : fallbackName;

        return SizedBox(
          width: 130,
          height: 180,
          // The same lift the grid card carries, painted by `PressSink` and
          // animated down under a press — a rail of white-on-white tiles needs
          // it for the same reason (see [AppConstants.productCardShadow]). The
          // poster cards keep none.
          child: PressSink(
            onTap: onTap,
            idle: AppConstants.productCardShadow,
            pressed: AppConstants.productCardShadowPressed,
            borderRadius: AppConstants.productCardRadius,
            child: Container(
              key: cardEdgeKey,
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: AppConstants.productCardRadius,
                border: Border.all(color: AppConstants.cardEdge, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail + compact countdown band across its bottom edge
                  // (only for sales that actually end).
                  //
                  // The hairline is a `foregroundDecoration`, NOT a `border`:
                  // a decoration border insets its child by its width, which
                  // would shrink the 130x124 thumbnail and disturb the rail's
                  // fixed 130x180 contract (the text block below is sized by a
                  // FittedBox against the leftover height). Painting it in the
                  // foreground keeps every geometry assertion in
                  // best_sellers_section_test byte-identical.
                  ClipRRect(
                    borderRadius: AppConstants.productCardImageRadius,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        Image.network(
                          firstImage(product, fallbackImageUrl),
                          width: 128,
                          height: 124,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 128,
                            height: 124,
                            color: AppConstants.borderGray.withValues(
                              alpha: 0.2,
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              color: AppConstants.borderGray,
                            ),
                          ),
                        ),
                        if (onSale && stripEnd != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: SaleCountdownOverlay(
                              saleEndsAt: stripEnd,
                              compact: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Text block — Expanded + FittedBox (scaleDown) guarantees
                  // the card never overflows the 180px strip, even when an
                  // on-sale item renders two price lines or the device text
                  // scale is large.
                  Expanded(
                    // The gap is applied OUTSIDE the `FittedBox`, deliberately:
                    // it is a real inset of the card, so the block is measured
                    // against the width that is left (and the text scales to
                    // that) instead of the padding becoming part of the content
                    // the `scaleDown` shrinks.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: textInset,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            if (onSale) ...[
                              // Sale price hides behind a peel-away tape (same
                              // reveal state as the cards' tags).
                              SalePriceTape(
                                productId: product['id']?.toString() ?? '',
                                // 11px text → slightly more padding to keep the
                                // ~40px tap target.
                                hitPadding: const EdgeInsets.fromLTRB(
                                  10,
                                  20,
                                  10,
                                  9,
                                ),
                                child: Text(
                                  '₱${livePrice.toStringAsFixed(2)}',
                                  style: AppConstants.monoStyle(
                                    fontSize: 11,
                                    color: AppConstants.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '₱${originalPrice.toStringAsFixed(2)}',
                                style:
                                    AppConstants.monoStyle(
                                      fontSize: 9,
                                      color: AppConstants.secondary.withValues(
                                        alpha: 0.5,
                                      ),
                                    ).copyWith(
                                      decoration: TextDecoration.lineThrough,
                                    ),
                              ),
                            ] else
                              Text(
                                '₱${livePrice.toStringAsFixed(2)}',
                                style: AppConstants.monoStyle(
                                  fontSize: 11,
                                  color: AppConstants.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
