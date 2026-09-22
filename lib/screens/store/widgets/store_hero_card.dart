import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../constants/app_constants.dart';
import '../../../models/store.dart';
import '../../../widgets/sale_countdown_overlay.dart';
import '../../../widgets/store_sale_tag.dart';
import 'stitch_painter.dart';

/// A single hero card for the store carousel.
/// Displays the store brand gradient, stitch overlay, initials, open/closed
/// chip, store name, tagline, and stat pills.
class StoreHeroCard extends StatefulWidget {
  final Store store;
  final double scale;
  final int productCount;

  /// The store's products — the same list [productCount] is counted from, so a
  /// sale tag here can never describe a different shelf than the count beside
  /// it. Passed through to the tag's expiry watcher, which needs the sale fields
  /// to fall back when the last sale ends. Empty (the default) renders no tag
  /// at all.
  final List<Map<String, dynamic>> products;

  /// Whether this is the carousel's focused page — the only card whose sale tag
  /// runs its idle dangle.
  final bool isFocused;

  final VoidCallback? onTap;

  /// Opens the store pre-filtered to its on-sale products. Null renders a tag
  /// with no destination, which is only correct on a card that cannot be
  /// entered at all.
  final VoidCallback? onSaleTap;

  const StoreHeroCard({
    super.key,
    required this.store,
    this.scale = 1.0,
    this.productCount = 0,
    this.products = const [],
    this.isFocused = false,
    this.onTap,
    this.onSaleTap,
  });

  @override
  State<StoreHeroCard> createState() => _StoreHeroCardState();
}

class _StoreHeroCardState extends State<StoreHeroCard> {
  bool _pressed = false;

  Store get store => widget.store;
  double get scale => widget.scale;
  int get productCount => widget.productCount;
  bool get isFocused => widget.isFocused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale * (_pressed ? 0.97 : 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Container(
            height: 260,

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
                    child:
                        store.bannerUrl != null && store.bannerUrl!.isNotEmpty
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
                            decoration: BoxDecoration(
                              gradient: store.cardGradient,
                            ),
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
                                  store.logoUrl != null &&
                                      store.logoUrl!.isNotEmpty
                                  ? CachedNetworkImageProvider(store.logoUrl!)
                                  : null,
                              child:
                                  store.logoUrl == null ||
                                      store.logoUrl!.isEmpty
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
                                color: store.isOpenNow
                                    ? AppConstants.success
                                    : AppConstants.borderGray,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                store.isOpenNow ? 'OPEN' : 'CLOSED',
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
                            // The sale tag, when the store has one. It brings its
                            // own leading gap so an absent sale leaves NO
                            // residual space in the row (the spacing belongs to
                            // the thing it spaces, not to the row).
                            if (widget.products.isNotEmpty)
                              StoreSaleEndWatcher(
                                products: widget.products,
                                builder: (context, sale) {
                                  if (!sale.hasSale) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: StoreSaleTag(
                                      sale: sale,
                                      animate: isFocused,
                                      onTap: widget.onSaleTap ?? () {},
                                    ),
                                  );
                                },
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
