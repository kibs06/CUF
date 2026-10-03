import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/review_provider.dart';
import '../../utils/cart_helpers.dart';
import '../../utils/product_audience.dart';
import '../../utils/size_key.dart';
import '../../utils/recently_viewed.dart';
import '../../services/supabase_service.dart';
import '../../providers/try_on/try_on_mode.dart';
import '../../services/ar_try_on_channel.dart';
import '../../services/try_on_prefetch.dart';
import '../../utils/sale_price.dart';
import '../../utils/shoe_preview_visibility.dart';
import '../../utils/variant_swatch_color.dart';
import '../../widgets/sole_badge.dart';
import '../../widgets/sole_review_card.dart';
import '../../widgets/sole_star_rating.dart';
import 'checkout_screen.dart';
import '../shared/shoe_preview_screen.dart';
import 'tag_products_screen.dart';
import 'write_review_screen.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/fit_verdict_card.dart';
import '../../widgets/seller/fly_to_order_animation.dart';
import '../../widgets/seller/tag_selector.dart';
import '../../widgets/shoe_preview_3d.dart';
import '../../widgets/size_guide_modal.dart';
import '../../widgets/hanging_sale_tag.dart';
import '../../widgets/sale_price_tape.dart';
import '../../widgets/sale_countdown_overlay.dart';
import '../../widgets/color_thumbnail_swatch.dart';
import 'widgets/bulk_reservation_sheet.dart';
import 'widgets/pickup_reservation_sheet.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  /// Test seam for the V2.6 model prefetch.
  ///
  /// Production builds the real one (the `virtualFitEnabled`-style switch is
  /// inside `TryOnPrefetch` itself). A test injects one wired to fake model rows
  /// and a temp cache directory, so it can prove the page survives a prefetch
  /// that fails — which is the whole promise of mounting one here.
  final TryOnPrefetch? tryOnPrefetch;

  const ProductDetailScreen({
    super.key,
    required this.product,
    this.tryOnPrefetch,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

/// Reviews section for the product detail screen.
class _ReviewsSection extends StatefulWidget {
  final String productId;
  final String productName;
  const _ReviewsSection({required this.productId, required this.productName});

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReviewProvider>().loadReviews(widget.productId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReviewProvider>();

    final reviewCount = provider.reviewCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header with aggregate + Write button ────────────
        Row(
          children: [
            Text(
              'Reviews',
              style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            if (provider.canReview)
              TextButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => WriteReviewScreen(
                        productId: widget.productId,
                        productName: widget.productName,
                      ),
                    ),
                  );
                  if (result == true && mounted) {
                    provider.loadReviews(widget.productId);
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(
                  provider.myReview != null ? 'Edit Review' : 'Write a Review',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Rating summary bar (only if reviews exist) ─────
        if (reviewCount > 0) ...[
          _buildRatingSummary(provider),
          const SizedBox(height: 16),
        ],

        // ── Reviews list or empty state ─────────────────────
        if (provider.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppConstants.primary,
                ),
              ),
            ),
          )
        else if (provider.reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppConstants.borderGray.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 36,
                  color: AppConstants.borderGray,
                ),
                const SizedBox(height: 8),
                Text(
                  'No reviews yet — be the first!',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          )
        else
          ...provider.reviews.map((review) => SoleReviewCard(review: review)),
      ],
    );
  }

  Widget _buildRatingSummary(ReviewProvider provider) {
    final breakdown = provider.breakdown;
    final total = provider.reviewCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: avg rating big number
          Column(
            children: [
              Text(
                provider.avgRating.toStringAsFixed(2),
                style: AppConstants.monoStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: 2),
              SoleStarRating(
                rating: provider.avgRating.round(),
                size: 16,
              ),
              const SizedBox(height: 2),
              Text(
                '$total ${total == 1 ? "review" : "reviews"}',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Right: breakdown bars
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final count = breakdown[star] ?? 0;
                final fraction = total > 0 ? count / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '$star',
                        style: AppConstants.monoStyle(
                          fontSize: 11,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.star_rounded, size: 12, color: AppConstants.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: fraction,
                            backgroundColor: AppConstants.borderGray.withValues(alpha: 0.3),
                            valueColor: const AlwaysStoppedAnimation(AppConstants.accent),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$count',
                          style: AppConstants.monoStyle(
                            fontSize: 10,
                            color: AppConstants.secondary.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// "More from Store" section — horizontal scroll of other products from the
/// same store, shown below the reviews on the product detail screen.
class _MoreFromStoreSection extends StatefulWidget {
  final String storeId;
  final String storeName;
  final String currentProductId;

  const _MoreFromStoreSection({
    required this.storeId,
    required this.storeName,
    required this.currentProductId,
  });

  @override
  State<_MoreFromStoreSection> createState() => _MoreFromStoreSectionState();
}

class _MoreFromStoreSectionState extends State<_MoreFromStoreSection> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreProducts();
  }

  Future<void> _loadStoreProducts() async {
    if (widget.storeId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final all = await SupabaseService.instance.fetchProducts(storeId: widget.storeId);
      // Exclude the current product
      final others = all
          .where((p) => p['id']?.toString() != widget.currentProductId)
          .toList();
      if (mounted) {
        setState(() {
          _products = others;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primary),
          ),
        ),
      );
    }
    if (_products.isEmpty) return const SizedBox.shrink();

    final displayName = widget.storeName.isNotEmpty ? widget.storeName : 'this store';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.storefront_outlined, size: 16, color: AppConstants.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'More from $displayName',
              style: AppConstants.bodyStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppConstants.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final p = _products[index];
              return _StoreProductCard(product: p);
            },
          ),
        ),
      ],
    );
  }
}

/// Compact product card used in the "More from Store" horizontal list.
class _StoreProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _StoreProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    // Primary image
    final images = product['product_images'] as List? ?? [];
    String? imageUrl;
    if (images.isNotEmpty && images.first is Map) {
      final sorted = List<Map<String, dynamic>>.from(images);
      sorted.sort((a, b) =>
          (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
      imageUrl = sorted.first['image_url']?.toString();
    } else {
      final flat = product['images'] as List? ?? [];
      if (flat.isNotEmpty) imageUrl = flat.first.toString();
    }

    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final onSale = isOnSale(product);
    final displayPrice = onSale ? effectivePrice(product) : price;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      },
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: AppConstants.borderGray.withValues(alpha: 0.3),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: AppConstants.borderGray.withValues(alpha: 0.3),
                          child: Icon(Icons.image, color: AppConstants.borderGray, size: 20),
                        ),
                      )
                    : Container(
                        color: AppConstants.borderGray.withValues(alpha: 0.3),
                        child: Icon(Icons.image_outlined, color: AppConstants.borderGray, size: 20),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            // Name — flexes so 2-line names can never push the price past
            // the card's fixed height (RenderFlex overflow guard).
            Expanded(
              child: Text(
                product['name'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppConstants.bodyStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 2),
            // Price
            if (onSale)
              Row(
                children: [
                  Text(
                    '₱${displayPrice.toStringAsFixed(0)}',
                    style: AppConstants.monoStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.error,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '₱${price.toStringAsFixed(0)}',
                    style: AppConstants.monoStyle(
                      fontSize: 10,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ).copyWith(decoration: TextDecoration.lineThrough),
                  ),
                ],
              )
            else
              Text(
                '₱${price.toStringAsFixed(0)}',
                style: AppConstants.monoStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedSize;

  /// The colour the **shopper tapped**, or null while none has been.
  ///
  /// Null is a real state and it is the one the page opens in: with no colour
  /// picked, the gallery shows the product's own photos ([_sortedImageUrls]) and
  /// only a tap swaps it to that colour's. Do not seed this from
  /// [_effectiveColor] — an earlier version read through `_selectedColor ==
  /// null ? first-colour : _selectedColor`, which made the page open on a
  /// colour's photo and left the seller's own gallery unreachable until a tap.
  String? _selectedColor;
  bool _isDescriptionExpanded = false;
  bool _isLoadingSizes = false;
  bool _isAddingToCart = false;

  // Quantity selected by the shopper (stepper below the size grid).
  int _quantity = 1;

  // Active size unit for display (US / EU / UK switcher in the header).
  // Display-only: `_selectedSize` always keeps the canonical DB string so
  // variant lookup and cart keys keep matching the inventory rows.
  String _sizeUnit = 'US';

  // Image carousel state
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  // Button press animation (scale down/up on tap)
  late final AnimationController _buttonPressController;
  late final Animation<double> _buttonScaleAnimation;

  // GlobalKeys for fly-to-cart overlay animation
  final GlobalKey _productImageKey = GlobalKey();
  final GlobalKey _cartIconKey = GlobalKey();

  /// Product tag ids from products.tags (real data), in stored order.
  List<String> get _productTags {
    final raw = widget.product['tags'] as List? ?? [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Product tag id → display label, using the shared tag vocabulary
  /// (tag_selector.dart). Falls back to a readable title-cased form for
  /// legacy free-text tags: 'eco_friendly' → 'Eco friendly'.
  String _tagLabel(String id) {
    for (final group in tagGroups) {
      for (final preset in group.presets) {
        if (preset.id == id) return preset.label;
      }
    }
    return id
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Distinct color names from this product's variants (real data), in
  /// first-seen order. Empty when the product has no color variants — the
  /// "Select Color / Leather" section then stays hidden.
  List<String> get _variantColorNames {
    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    final seen = <String>{};
    final colors = <String>[];
    for (final v in variants) {
      final c = v['color']?.toString().trim() ?? '';
      if (c.isNotEmpty && seen.add(c)) colors.add(c);
    }
    return colors;
  }

  /// The colour used for **ordering and resolution**: the shopper's pick, or the
  /// first available colour when none is picked yet.
  ///
  /// Deliberately *not* the gallery's key — a colour nobody has tapped is still
  /// the right colour to price, resolve a variant against and filter the size
  /// grid by, but it is not a choice the shopper made, so it must not decide
  /// what the page shows them. See [_selectedColourOrNull] and
  /// [_sortedImageUrls].
  String? get _effectiveColor {
    final colors = _variantColorNames;
    if (colors.isEmpty) return null;
    return _selectedColourOrNull ?? colors.first;
  }

  /// The shopper's own pick, or null when there is none to honour.
  ///
  /// The gallery's switch, and the only thing that may change it: the
  /// **evidence of a tap** ([_selectedColor]) plus the colour still existing on
  /// the product — a colour name that a seller renamed away mid-session must
  /// not keep the gallery pointed at photos nothing can resolve.
  String? get _selectedColourOrNull =>
      _selectedColor != null && _variantColorNames.contains(_selectedColor)
          ? _selectedColor
          : null;

  /// Get the first image URL for a color from product_color_images.
  /// Returns null if no color images exist for this color.
  String? _colorThumbnailUrl(String colorName) {
    final colorImagesRaw = widget.product['product_color_images'] as List? ?? [];
    for (final img in colorImagesRaw) {
      if (img is Map && (img['color_name']?.toString() ?? '') == colorName) {
        final url = img['url']?.toString();
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  /// Map a variant color NAME (free text from sellers) to a swatch color.
  ///
  /// Delegates to the shared mapper so the reservation sheets, which draw the
  /// same swatches, can never drift from this picker.
  Color _swatchColorFor(String name) => variantSwatchColor(name);

  /// Total stock across all sizes (inventory + variants).
  int _totalStock() {
    var total = 0;
    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    for (final row in variants) {
      total += row['stock'] as int? ?? 0;
    }
    final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
    for (final row in inventory) {
      total += row['stock'] as int? ?? 0;
    }
    return total;
  }

  /// Build {colour: {size: stock}} for the reservation sheets.
  ///
  /// The sheets must be able to say WHICH variant a hold is for, so unlike
  /// [_buildSizesMap] (the size picker's map, already filtered to the active
  /// colour) this keeps every colour separate. A product without colour
  /// variants uses the single `''` key, which is how the sheets know to hide
  /// the colour picker.
  ///
  /// Sizes merge by [sizeKey] — the database's digits-only identity — so
  /// `'EU 40'` and `'40'` are one row here too (plan §4.1). The map key stays
  /// the variant's real size string, which is what the sheet hands to
  /// `resolveVariant` when the hold is created.
  Map<String, Map<String, int>> _buildStockByColor() {
    final colors = _variantColorNames;
    // colour → sizeKey → canonical raw size string (the variant form wins).
    final canonical = <String, Map<String, String>>{};
    // colour → sizeKey → stock, split by source so `inventory` can win.
    final variantStock = <String, Map<String, int>>{};
    final inventoryStock = <String, Map<String, int>>{};

    void bump(
      Map<String, Map<String, int>> target,
      String color,
      String raw,
      int stock,
    ) {
      final key = sizeKey(raw);
      if (key.isEmpty) return;
      canonical.putIfAbsent(color, () => {})[key] ??= raw;
      final sizes = target.putIfAbsent(color, () => {});
      sizes[key] = (sizes[key] ?? 0) + stock;
    }

    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    for (final row in variants) {
      final color =
          colors.isEmpty ? '' : (row['color']?.toString().trim() ?? '');
      if (colors.isNotEmpty && (color.isEmpty || !colors.contains(color))) {
        continue;
      }
      final raw = row['size']?.toString();
      if (raw == null || raw.trim().isEmpty) continue;
      bump(variantStock, color, raw, row['stock'] as int? ?? 0);
    }

    if (colors.isEmpty) {
      // Inventory is not colour-aware, so it only joins a colourless product.
      final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
      for (final row in inventory) {
        final raw = row['size']?.toString();
        if (raw == null || raw.trim().isEmpty) continue;
        bump(inventoryStock, '', raw, row['stock'] as int? ?? 0);
      }
    }

    // `inventory` is derived from `product_variants` and is the authoritative
    // stock source (lib/utils/product_stock.dart), so where it has a row it
    // wins — summing the two double-counts the same stock (plan §8 R2).
    final result = <String, Map<String, int>>{};
    for (final entry in canonical.entries) {
      final color = entry.key;
      final byRaw = <String, int>{for (final size in entry.value.entries)
        size.value: inventoryStock[color]?.containsKey(size.key) == true
            ? inventoryStock[color]![size.key]!
            : (variantStock[color]?[size.key] ?? 0)};
      // Sizes sorted numerically inside each colour, like the size picker.
      final sorted = byRaw.entries.toList()
        ..sort((a, b) => compareSizes(a.key, b.key));
      result[color] = Map.fromEntries(sorted);
    }
    return result;
  }

  /// Build a map of {size: stock} from both inventory and product_variants.
  ///
  /// Sizes merge by [sizeKey] — the database matches sizes digits-only
  /// (`regexp_replace(size, '\D', '', 'g')`), so `'EU 40'` and `'40'` are one
  /// size and must not become two entries (plan §4.1, R2). The map key stays
  /// the real size string so `_selectedSize` and variant lookup keep matching
  /// `product_variants.size`.
  ///
  /// Where both tables have a row, `inventory` wins: it is derived from
  /// `product_variants` and is the authoritative stock source
  /// (lib/utils/product_stock.dart), so summing the two double-counts.
  /// Sizes sort numerically, half sizes included ([compareSizes]).
  Map<String, int> _buildSizesMap() {
    final activeColor = _effectiveColor;
    // sizeKey → canonical raw size string (the variant form wins).
    final canonical = <String, String>{};
    final variantStock = <String, int>{};
    final inventoryStock = <String, int>{};

    // When a color is selected, filter variants to only that color
    // so the size picker shows only sizes available for that color.
    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    for (final row in variants) {
      final rowColor = row['color']?.toString().trim() ?? '';
      // If a color is selected, skip variants that don't match
      if (activeColor != null && rowColor != activeColor) continue;
      final raw = row['size']?.toString();
      if (raw == null || raw.trim().isEmpty) continue;
      final key = sizeKey(raw);
      if (key.isEmpty) continue;
      canonical[key] ??= raw;
      variantStock[key] = (variantStock[key] ?? 0) + (row['stock'] as int? ?? 0);
    }

    // Inventory is not colour-aware, so it only joins a colourless product.
    if (activeColor == null) {
      final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
      for (final row in inventory) {
        final raw = row['size']?.toString();
        if (raw == null || raw.trim().isEmpty) continue;
        final key = sizeKey(raw);
        if (key.isEmpty) continue;
        canonical[key] ??= raw;
        inventoryStock[key] =
            (inventoryStock[key] ?? 0) + (row['stock'] as int? ?? 0);
      }
    }

    final merged = <String, int>{
      for (final entry in canonical.entries)
        entry.value: inventoryStock.containsKey(entry.key)
            ? inventoryStock[entry.key]!
            : (variantStock[entry.key] ?? 0),
    };
    return Map.fromEntries(
      merged.entries.toList()..sort((a, b) => compareSizes(a.key, b.key)),
    );
  }

  @override
  void initState() {
    super.initState();

    // Button press animation (scale down then back up)
    _buttonPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 100),
    );
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _buttonPressController, curve: Curves.easeInOut),
    );

    // Track this product as recently viewed
    RecentlyViewedService.instance.pushProduct(widget.product);

    // Use _buildSizesMap() — reads from inventory and product_variants,
    // not the non-existent widget.product['sizes'] key
    final sizesMap = _buildSizesMap();
    if (sizesMap.isNotEmpty) {
      for (final entry in sizesMap.entries) {
        if (entry.value > 0) {
          _selectedSize = entry.key;
          break;
        }
      }
      // The store-list query only selects size/stock for variants — make
      // sure full rows (with color) are loaded so the swatches reflect
      // real product data instead of a mock list.
      if (_variantColorNames.isEmpty) {
        _fetchVariantColors();
      }
    } else {
      // Inventory data missing — fetch it from Supabase
      _fetchInventory();
    }

    _prefetchTryOnModel();
    unawaited(_checkLiveModelRow());

    // The v1.0.35 report was pill-only with no words on a phone that verifiably
    // ran the hint build — a state the release still left silent. The suspects
    // were: a resolve-phase failure (reason `noModel`, excluded from the hint by
    // design), and a prefetch that never completed (result null, `modelNotReady`,
    // silent because "open the page again"). Neither can be told apart from the
    // catalogue being honest from the *outside* — so the page stops trying to
    // guess from the outcome alone. After this grace period a still-absent model
    // on a product that HAS one gets words no matter which shape the silence
    // took. One-shot; cancelled in dispose.
    _previewWaitTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _previewWaitedTooLong = true);
    });
  }

  /// What the V2.6 prefetch found, kept because the try-on entry needs the
  /// answer (V3.9) and a fire-and-forget future has nowhere else to leave it.
  /// Declared beside its only reader and writer on purpose.
  TryOnPrefetchResult? _tryOnPrefetchResult;

  /// Warms the model cache for the selection the page opens on (V2.6).
  ///
  /// **Fire-and-forget, and safe to be.** `TryOnPrefetch` converts every
  /// failure — no model, no table, no network, a hash mismatch, an unwritable
  /// cache — into a returned outcome, so this future never completes with an
  /// error and `.ignore()` hides nothing. The page does not await it: a
  /// prefetch that can delay the first frame would be a worse version of the
  /// problem it exists to solve.
  ///
  /// Only the *initial* selection is warmed. Re-warming on every size or colour
  /// tap would download a model per tap, and whether the rendered model even
  /// depends on the selection is a question only V3 can answer — it is per
  /// variant in the schema (D-2) and product-level in practice today.
  ///
  /// ⚠️ **And it can be a no-op on a cold page — the bug the Retry hint and
  /// `_fetchInventory` both feed.** The `size == null` return below is correct
  /// in itself (there is no variant to resolve yet), but a product payload that
  /// arrives without inventory takes the `_fetchInventory()` path above, and the
  /// size only exists *after* that fetch selects one. Nothing used to re-run
  /// this — so the model was never fetched at all, the box never appeared, and
  /// the page looked exactly like a product with no model. On fast Wi-Fi with a
  /// payload that already carries inventory it never fired; on mobile data it
  /// is the bug. `_fetchInventory` now calls back in, and the Retry hint uses
  /// the same method so a customer can also recover from a plain network miss.
  void _prefetchTryOnModel() {
    if (!AppConstants.tryOnPrefetchEnabled && widget.tryOnPrefetch == null) {
      return; // nothing is mounted, so nothing is read
    }

    final productId = widget.product['id']?.toString() ?? '';
    if (productId.isEmpty) return;

    final size = _selectedSize;
    if (size == null) return; // _fetchInventory re-enters here once one is picked

    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    final variantId = resolveVariant(
      variants: variants,
      size: size,
      color: _effectiveColor,
    ).variantId;

    final prefetch = _shoePrefetch ??= widget.tryOnPrefetch ??
        TryOnPrefetch(enabled: AppConstants.tryOnPrefetchEnabled);
    prefetch
        .prefetch(productId: productId, variantId: variantId)
        .then(_recordTryOnAvailability)
        .ignore();
  }

  /// The Retry action on the hint: one fresh attempt, visible while it runs.
  ///
  /// It re-enters [_prefetchTryOnModel] rather than duplicating it — the dedupe
  /// in `TryOnPrefetch._inFlight` makes a concurrent double-call harmless, and
  /// the flag exists only so the hint cannot read as if nothing happened.
  Future<void> _retryShoePreview() async {
    if (_retryingPrefetch) return;
    setState(() => _retryingPrefetch = true);
    _prefetchTryOnModel();
    // Give the attempt a beat to fail or land before the hint comes back; the
    // result itself lands through `_recordTryOnAvailability` either way.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _retryingPrefetch = false);
  }

  /// Records the prefetch's answer.
  ///
  /// The rebuild is deliberate — it can flip the try-on entry from the simulated
  /// screen to the real renderer, which is a capability change rather than a
  /// decoration — and it is compared by value so a re-prefetch for the same
  /// selection cannot rebuild in a loop.
  void _recordTryOnAvailability(TryOnPrefetchResult result) {
    if (!mounted) return;
    final current = _tryOnPrefetchResult;
    if (current?.outcome == result.outcome && current?.path == result.path) {
      return;
    }
    setState(() => _tryOnPrefetchResult = result);
  }

  /// **The product-detail half of V3's capability gate (roadmap V3.9).**
  ///
  /// True only when the switch is on *and* a verified model is already on disk.
  /// "The product has a row" is a different question from "there is something to
  /// render": the native side is handed a local path and never does HTTP
  /// (architecture §2.8), so availability means *cached* — which is exactly what
  /// the prefetch above proves. The AR half of the gate cannot be answered from
  /// here, because it is only discovered when a session tries to start; it is the
  /// session controller's to report.
  bool get _tryOnModelAvailable =>
      // The QA seam short-circuits the question (V3.5): with the bundled block-out
      // flag on there *is* something to render even though `product_models` has no
      // row for this product, which is what makes the same path reachable on a desk
      // as it is with a partner asset. The gate's question is literally "is there
      // something to render", so answering it from the bundle is not a lie.
      AppConstants.tryOnPlaceholderModelEnabled ||
      tryOnModelAvailable(
        enabled: AppConstants.tryOnV3Enabled,
        hasLocalModel: _tryOnPrefetchResult?.hasLocalModel ?? false,
      );

  /// Whether this product has a **live model row** — a catalogue fact, asked
  /// directly from the table the way the catalogue itself would answer, and so
  /// independent of the prefetch's own luck (its failure to resolve is one of
  /// the things this fact exists to distinguish). Cheap: one indexed read, once.
  /// Never blocks anything — if it errors, the page stays silent rather than
  /// crying wolf on every model-less product.
  bool? _productHasLiveModelRow;

  Future<void> _checkLiveModelRow() async {
    try {
      final rows = await Supabase.instance.client
          .from('product_models')
          .select('id')
          .eq('product_id', widget.product['id'].toString())
          .eq('status', 'active')
          .limit(1);
      if (!mounted) return;
      setState(() => _productHasLiveModelRow = (rows as List).isNotEmpty);
    } catch (_) {
      // No answer is a valid answer: leave null, the page stays silent.
    }
  }

  /// The prefetch, rebuilt when the page calls for it again. A late inventory
  /// load (see the `size == null` guard below) and the Retry hint both come
  /// through the same door.
  TryOnPrefetch? _shoePrefetch;

  /// True while a retry the customer asked for is in flight, so the hint can say
  /// "trying…" instead of offering a second concurrent attempt.
  bool _retryingPrefetch = false;

  /// True once the page has been open long enough that a still-null prefetch
  /// result is no longer "in flight" but "never finished" — the state v1.0.35
  /// left silent. The one-shot timer starts in [initState].
  bool _previewWaitedTooLong = false;
  Timer? _previewWaitTimer;

  /// **The inline 3D box's gate** — whether the product page shows the box, and
  /// with it the "Try On in AR" button that lives inside its section.
  ///
  /// ⚠️ The two facts come from different places on purpose, and the distinction
  /// is the one `TryOnPrefetchResult` already draws: `spec` is "this product has
  /// a live model" (a row that passed the authoring contract), `path` is "those
  /// bytes are verified on disk" (the native side is handed a local file and
  /// never does HTTP). A box needs both — a row with no bytes draws nothing, and
  /// a box that appears once the download finishes is a beat of no box, which is
  /// the honest answer rather than a spinner over an empty rectangle.
  ShoePreviewDecision get _shoePreview =>
      resolveShoePreview(
        enabled: AppConstants.shoePreviewEnabled,
        isAndroid: defaultTargetPlatform == TargetPlatform.android,
        hasModel: _tryOnPrefetchResult?.spec != null,
        hasLocalModel: _tryOnPrefetchResult?.path != null,
      );

  /// The whole-point product of this section: the mesh to draw, in the same
  /// payload the AR session sends.
  TryOnModelSpec? get _shoePreviewModel {
    final result = _tryOnPrefetchResult;
    final spec = result?.spec;
    final path = result?.path;
    if (spec == null || path == null) return null;
    return TryOnModelSpec.fromModel(spec, path: path);
  }

  /// Whether the hero shows the 3D icon — the page's only way into the viewer.
  ///
  /// Two facts, and both are needed: `shown` is the build switch, the platform
  /// and the catalogue's honesty about having a model at all, and the model is
  /// **these bytes, verified on disk** (the native side is handed a local path
  /// and never does HTTP). An icon on a product with no model would open a
  /// viewer whose entire content is an apology.
  bool get _showPreviewIcon => _shoePreview.shown && _shoePreviewModel != null;

  /// Open the full-screen 3D viewer. No pause flag is needed here the way the
  /// old inline box needed one: the box belongs to the pushed route, so the
  /// page underneath holds no engine to stop (`ShoePreviewScreen` owns the flag
  /// for its own push into AR).
  Future<void> _openShoePreview() async {
    final model = _shoePreviewModel;
    if (model == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ShoePreviewScreen(
          model: model,
          product: widget.product,
          modelAvailable: _tryOnModelAvailable,
        ),
      ),
    );
  }

  /// The reason last written to the log, so a rebuild storm does not become a log
  /// storm: the answer changes at most a handful of times per page.
  ShoePreviewReason? _loggedPreviewReason;

  /// Writes the box's verdict once per *change*, and deliberately **not** behind
  /// `kDebugMode` — this line exists for the release build on a real phone, which
  /// is the only place the box can be looked at. It is the difference between
  /// "the box is missing" and knowing which of four unrelated things caused it:
  /// `featureOff` is the build, `notAndroid` the platform, `noModel` the
  /// catalogue, and `modelNotReady` the prefetch still running (open the page
  /// again). All four look like an empty page.
  void _logPreviewReason(ShoePreviewReason reason) {
    if (_loggedPreviewReason == reason) return;
    _loggedPreviewReason = reason;
    debugPrint(
      '[shoe-preview] ${reason == ShoePreviewReason.none ? 'shown' : 'hidden'}: '
      '${reason.name} — ${widget.product['name'] ?? widget.product['id']}',
    );
  }

  /// **The 3D notice — words for the one hidden state the icon cannot explain,
  /// or nothing at all.**
  ///
  /// The icon on the photograph is silent by construction: it is there when
  /// there is a model to turn and gone when there is not, which is the honest
  /// answer for a catalogue with no model on this product and the wrong one for
  /// a fault the customer can fix with one tap. So the recoverable states keep
  /// the sentence and the Retry they have always had, in the flow under the size
  /// grid where the box used to sit. Everything else renders nothing — and
  /// leaves no gap, the same rule `FitVerdictCard` follows.
  ///
  /// The condition and the model are read once here rather than twice in the
  /// tree, so the notice cannot be gated by one answer and built from another.
  Widget _shoePreviewNotice() {
    final model = _shoePreviewModel;
    final decision = _shoePreview;
    _logPreviewReason(decision.reason);
    if (!decision.shown || model == null) {
      // Words for every hidden state on a product that HAS a live model — the      // v1.0.35 rule was too tight twice over: a resolve-phase failure computed      // reason `noModel` and was excluded by the no-model-should-be-quiet rule;      // a prefetch that never completed (result null) was silent because      // "modelNotReady" was presumed transient. Both hid a fault the customer      // could have recovered from with one tap.
      //
      // The one state that must stay silent is a product with genuinely no      // model AND no prefetch failure — the catalogue being honest. Everything      // else on such a product is a fault with words: a resolve or download      // failure gets Retry immediately, and a still-null result (prefetch never      // ran — no size yet, or it is hung) gets Retry after the grace period.
      final hasLiveModel = _tryOnPrefetchResult?.spec != null;
      final failed = _tryOnPrefetchResult?.outcome == TryOnPrefetchOutcome.failed;
      final stuck = AppConstants.shoePreviewEnabled &&
          !hasLiveModel &&
          !failed &&
          _previewWaitedTooLong &&
          _productHasLiveModelRow == true; // catalog fact, not prefetch luck
      if (AppConstants.shoePreviewEnabled && (failed || stuck)) {
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: ShoePreviewHint(
            message: _retryingPrefetch
                ? 'Checking for 3D preview…'
                : '3D preview couldn\'t load just now.',
            actionLabel: _retryingPrefetch ? null : 'Retry',
            onAction: _retryShoePreview,
          ),
        );
      }
      return const SizedBox.shrink();
    }
    // Shown, with a model in hand: the icon on the photo is the whole surface,
    // and this helper has nothing left to say.
    return const SizedBox.shrink();
  }

  /// Fetch inventory and variant data if the parent screen didn't include it.
  Future<void> _fetchInventory() async {
    if (!mounted) return;
    setState(() => _isLoadingSizes = true);

    try {
      final productId = widget.product['id'].toString();
      final data = await Supabase.instance.client
          .from('products')
          .select('inventory(*), product_variants(*)')
          .eq('id', productId)
          .single();

      if (!mounted) return;

      setState(() {
        widget.product['inventory'] = data['inventory'];
        widget.product['product_variants'] = data['product_variants'];
        _isLoadingSizes = false;
      });

      // Auto-select first available size after data loads
      final sizesMap = _buildSizesMap();
      for (final entry in sizesMap.entries) {
        if (entry.value > 0) {
          _selectedSize = entry.key;
          break;
        }
      }
      // A size now exists, so the prefetch's `size == null` guard no longer
      // bounces — re-enter it. Without this, a page whose inventory arrives
      // over the network never fetches a model at all: the guard ran in
      // initState before any size existed, and nothing called it again.
      if (_selectedSize != null) _prefetchTryOnModel();
    } catch (_) {
      if (mounted) setState(() => _isLoadingSizes = false);
    }
  }

  /// Fetch full variant rows (incl. color) when the product payload only
  /// carried size/stock. Colors drive the swatches, so we need them even
  /// when sizes already loaded. Never shows the loading skeleton.
  Future<void> _fetchVariantColors() async {
    try {
      final productId = widget.product['id'].toString();
      final data = await Supabase.instance.client
          .from('products')
          .select('product_variants(*)')
          .eq('id', productId)
          .single();
      if (!mounted) return;
      setState(() {
        widget.product['product_variants'] = data['product_variants'];
      });
    } catch (_) {
      // Keep whatever variants we have — the swatch section hides when
      // there are no colors.
    }
  }

  void _addToCart() {
    if (_selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isLoadingSizes
                ? 'Sizes are still loading. Please wait.'
                : 'No sizes available. Please check back later.',
          ),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    // Button press scale animation (guard against rapid taps)
    if (_buttonPressController.status != AnimationStatus.forward) {
      _buttonPressController.forward().then((_) {
        if (mounted) _buttonPressController.reverse();
      });
    }

    // Show success checkmark state on button
    setState(() => _isAddingToCart = true);

    // Get product image URL for the flying thumbnail
    final List<String> imageUrls = _sortedImageUrls;
    final String? imageUrl = imageUrls.isNotEmpty ? imageUrls.first : null;

    // Look up variant_id and additional_price for the selected size+color
    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    final (:variantId, :additionalPrice) = resolveVariant(
      variants: variants,
      size: _selectedSize!,
      color: _effectiveColor,
    );

    // Add to cart with variant + pricing info for Supabase persistence.
    // Uses the EFFECTIVE price so an on-sale product is charged the sale
    // price (sale_price.dart is the single source of truth).
    final cart = Provider.of<CartProvider>(context, listen: false);
    final double price = effectivePrice(widget.product);

    cart.addToCart(
      productId: widget.product['id'].toString(),
      productName: widget.product['name'],
      imageUrl: imageUrl ?? '',
      price: price,
      size: _selectedSize!,
      color: _effectiveColor,
      storeId: widget.product['store_id']?.toString(),
      storeName: widget.product['store_name']?.toString(),
      variantId: variantId,
      additionalPrice: additionalPrice,
      // Quantity set via the stepper below the size grid.
      quantity: _quantity,
    );

    // Pack-the-box fly-to-cart overlay animation (same as the POS): the box
    // GIF draws in around the product thumbnail, then the solid box flies to
    // the cart icon and lands with a ring flash.
    FlyToOrderAnimation.show(
      context: context,
      sourceKey: _productImageKey,
      targetKey: _cartIconKey,
      imageUrl: imageUrl,
    );



    // Revert button to normal "Add to Cart" label after the box-pack
    // animation finishes (~1800 ms) so rapid taps can't stack flights.
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _isAddingToCart = false);
    });
  }

  void _buyNow() {
    if (_selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isLoadingSizes
                ? 'Sizes are still loading. Please wait.'
                : 'No sizes available. Please check back later.',
          ),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    // Get product image URL for the checkout summary row
    final List<String> imageUrls = _sortedImageUrls;
    final String? imageUrl = imageUrls.isNotEmpty ? imageUrls.first : null;

    // Look up variant_id and additional_price for the selected size+color
    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    final (:variantId, :additionalPrice) = resolveVariant(
      variants: variants,
      size: _selectedSize!,
      color: _effectiveColor,
    );

    // Build the item directly — Buy Now NEVER touches the cart, so
    // backing out of checkout leaves My Cart exactly as it was.
    final double price = effectivePrice(widget.product);
    final directItems = [
      {
        'id': 'buynow-${widget.product['id']}-${_selectedSize!}-${_effectiveColor ?? 'none'}',
        'server_id': null,
        'product_id': widget.product['id'].toString(),
        'product_name': widget.product['name'],
        'imageUrl': imageUrl ?? '',
        'price': price + additionalPrice,
        'additional_price': additionalPrice,
        'size': _selectedSize!,
        'color': _effectiveColor ?? 'none',
        'quantity': _quantity,
        'store_id': widget.product['store_id']?.toString() ?? 'unknown',
        'store_name': widget.product['store_name']?.toString() ?? 'Unknown Store',
        'variant_id': variantId,
        'customizations': null,
      },
    ];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CheckoutScreen(directItems: directItems),
      ),
    );
  }

  /// Share this product via the native share sheet.
  ///
  /// The message now includes the product's public URL, which points at the
  /// `product-preview` edge function. Receiving apps (WhatsApp, Messenger,
  /// Facebook, …) fetch that URL and render a rich preview card from its
  /// Open Graph meta tags. Sharing stays text-only (no XFile) — the URL is
  /// what triggers the preview, and it degrades gracefully to plain text.
  Future<void> _shareProduct() async {
    final name = widget.product['name'] ?? 'CUFMAI Footwear';
    final price = effectivePrice(widget.product);
    final priceStr = '₱${price.toStringAsFixed(2)}';
    final storeName = widget.product['store_name'] ?? 'CUFMAI';
    final shareUrl =
        AppConstants.productShareUrl(widget.product['id'].toString());

    final text = 'Check out $name — only $priceStr at $storeName!\n$shareUrl';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: name,
        ),
      );
    } catch (e) {
      debugPrint('[Share] Failed to share product: $e');
    }
  }

  // ─── IMAGE CAROUSEL ────────────────────────────────────────────

  /// Sorted product images for the carousel.
  /// Reads from `product_images` (list of maps) or falls back to `images` (list of strings).
  ///
  /// **The page opens on the PRODUCT's own photos, not a colour's.**
  ///
  /// This used to key off `_effectiveColor`, which falls back to the first
  /// colour name when the shopper has not picked one — so a coloured product
  /// opened on `colors/<first>/…` and the seller's own gallery never appeared at
  /// all. On a live product that read as a bug: the store card showed the
  /// product's first photo, the page it opened showed a different one, and the
  /// seven photos the seller had uploaded were unreachable until a colour was
  /// tapped — and when that colour's own file was missing, the hero was simply
  /// **empty**, which is how this was found: a deleted colour photo left the
  /// page blank where the card was fine.
  ///
  /// Tapping a colour still swaps the gallery to that colour's photos. The key
  /// is [_selectedColourOrNull] — the *evidence of a tap* — never
  /// [_effectiveColor], which falls back to the first colour name and is what
  /// made the page open on a colour it had chosen for itself.
  List<String> get _sortedImageUrls {
    // A colour the shopper actually tapped, and only that, swaps the gallery.
    final color = _selectedColourOrNull;
    if (color != null) {
      final colorImagesRaw = widget.product['product_color_images'] as List? ?? [];
      final colorImages = colorImagesRaw
          .where((img) => img is Map && (img['color_name']?.toString() ?? '') == color)
          .toList();
      if (colorImages.isNotEmpty) {
        final images = List<Map<String, dynamic>>.from(colorImages.map((e) => Map<String, dynamic>.from(e as Map)));
        images.sort((a, b) =>
            (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
        return images.map((e) => e['url'].toString()).toList();
      }
    }

    // Fall back to general product images
    final raw = widget.product['product_images'] as List? ?? [];
    if (raw.isNotEmpty && raw.first is Map) {
      final images = List<Map<String, dynamic>>.from(raw);
      images.sort((a, b) =>
          (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
      return images.map((e) => e['image_url'].toString()).toList();
    }

    // Fall back to flat 'images' list (from SupabaseService._mapProduct)
    final images = widget.product['images'] as List? ?? [];
    return images.map((e) => e.toString()).toList();
  }

  @override
  void dispose() {
    _previewWaitTimer?.cancel();
    _buttonPressController.dispose();
    _imagePageController.dispose();
    super.dispose();
  }

  void _openFullScreenViewer(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const CircularProgressIndicator(
                  color: Colors.white,
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageCarousel(DateTime now) {
    final imageUrls = _sortedImageUrls;
    final DateTime? heroEnd =
        DateTime.tryParse(widget.product['sale_ends_at']?.toString() ?? '');

    if (imageUrls.isEmpty) {
      return KeyedSubtree(
        key: _productImageKey,
        child: _buildImagePlaceholder(),
      );
    }

    return KeyedSubtree(
      key: _productImageKey,
      child: Stack(
      // The hanging tag pokes ~7px past the left edge — don't clip it.
      clipBehavior: Clip.none,
      children: [
        // Main swipeable image area — fills the whole hero edge-to-edge.
        // (Previously wrapped in AspectRatio(1.0), which couldn't fill the
        // flexible space when the hero height (380) didn't match the screen
        // width — the SliverAppBar's brown background showed through as a
        // gap on the right of wider phones.) Images use BoxFit.cover, so
        // they always cover the full area.
        SizedBox.expand(
          child: PageView.builder(
            controller: _imagePageController,
            itemCount: imageUrls.length,
            onPageChanged: (index) {
              setState(() => _currentImageIndex = index);
            },
            itemBuilder: (context, index) {
              final url = imageUrls[index];
              return GestureDetector(
                onTap: () => _openFullScreenViewer(url),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _buildShimmerPlaceholder(),
                  errorWidget: (context, url, error) => _buildImagePlaceholder(),
                ),
              );
            },
          ),
        ),

        // Image counter badge — top right
        if (imageUrls.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentImageIndex + 1} / ${imageUrls.length}',
                style: AppConstants.monoStyle().copyWith(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),

        // Hanging sale tag — the same per-user/per-product object shown on
        // the catalog cards: tap to reveal the discount, stays revealed
        // everywhere for this product. Hangs off the left edge, below the
        // back button, away from the image counter (top-right).
        if (isOnSale(widget.product, now: now))
          Positioned(
            top: 52,
            left: -7,
            child: HangingSaleTag(
              productId: widget.product['id']?.toString() ?? '',
              salePercent: salePercent(widget.product, now: now),
            ),
          ),

        // Sale countdown — the same full-width yellow band as the catalog
        // cards, pinned edge-to-edge across the hero's bottom (no side gaps).
        // Only for sales with an end date; open-ended sales (NULL
        // sale_ends_at) show no countdown at all.
        if (isOnSale(widget.product, now: now) && heroEnd != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SaleCountdownOverlay(saleEndsAt: heroEnd),
          ),

        // Dot indicators — bottom center, raised above the countdown band.
        if (imageUrls.length > 1)
          Positioned(
            bottom: 34,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(imageUrls.length, (index) {
                final isActive = index == _currentImageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppConstants.primary
                        : AppConstants.borderGray,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),

        // The 3D icon — the page's whole entry into the 3D viewer since the
        // pinned "Try On in AR" pill came off it (2026-10-01). It rides on the
        // photograph, above the dot indicators and the sale band, and only on a
        // product whose model is verified on disk: a product with nothing to
        // turn shows no icon rather than a viewer that can only apologise
        // (`_showPreviewIcon`). A tap is a *look*, and the camera behind it stays
        // one tap deeper — the AR pill lives inside the viewer's section.
        if (_showPreviewIcon)
          Positioned(
            right: 12,
            bottom: 50,
            child: Sole3DIconButton(onPressed: _openShoePreview),
          ),
      ],
      ),
    );
  }

  Widget _buildShimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: AppConstants.borderGray.withValues(alpha: 0.4),
      highlightColor: AppConstants.borderGray.withValues(alpha: 0.1),
      child: Container(color: Colors.white),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: AppConstants.surfaceLight,
      child: Center(
        child: Icon(
          Icons.storefront_outlined,
          size: 64,
          color: AppConstants.borderGray,
        ),
      ),
    );
  }

  // ─── QUANTITY ───────────────────────────────────────────────────

  /// Quantity stepper (− / count / +) so shoppers can set quantity ahead
  /// of adding to cart. Wired into [_addToCart] via `_quantity`.
  Widget _buildQuantityStepper() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Quantity',
          style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppConstants.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppConstants.borderGray.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepperButton(Icons.remove_rounded, () {
                if (_quantity > 1) setState(() => _quantity--);
              }),
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$_quantity',
                  textAlign: TextAlign.center,
                  style: AppConstants.monoStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _stepperButton(Icons.add_rounded, () {
                setState(() => _quantity++);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: AppConstants.primary),
      ),
    );
  }

  // ─── SIZE SKELETON ───────────────────────────────────────────────

  /// Shimmer skeleton placeholders for the size selector row.
  Widget _buildSizeSkeleton() {
    return Shimmer.fromColors(
      baseColor: AppConstants.borderGray.withValues(alpha: 0.3),
      highlightColor: AppConstants.borderGray.withValues(alpha: 0.1),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(
            5,
            (_) => Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact "Ends Mon D" label for the sale end date (no intl package
  /// — same manual month-name approach used elsewhere in the app).
  String _formatSaleEnd(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    // Sale-expiry watcher: when the hero countdown hits zero the whole
    // screen rebuilds with a `now` past the sale end — tag, price tape,
    // sale price and savings note all fall back to non-sale together.
    return SaleEndWatcher(
      product: widget.product,
      builder: (context, now) => _buildScaffold(context, now),
    );
  }

  Widget _buildScaffold(BuildContext context, DateTime now) {
    final sizesMap = _buildSizesMap();

    // The scale the US/UK labels are drawn on — EU 42 is 'US 9' on the men's
    // chart and 'US 10.5' on the women's. `productSizeChart` owns the
    // precedence in one place: the PRODUCT's own audience first (a woman
    // browsing a men's-cut shoe reads the men's label), then the shopper's
    // saved scale, then the men's default. While
    // `AppConstants.productAudienceEnabled` is false it returns exactly what
    // this screen passed before the audience column existed, so the labels are
    // unchanged for every product in the catalog.
    final sizeChart = productSizeChart(
      product: widget.product,
      profile: context.watch<AuthProvider>().profile,
      audienceEnabled: AppConstants.productAudienceEnabled,
    );
    // The units this scale can label honestly (EU only for Kids'), and the one
    // the grid actually renders in. The customer's preferred unit is kept in
    // `_sizeUnit` so switching scale back to Men's/Women's restores it.
    final sizeUnits = sizeUnitsForCategory(sizeChart);
    final sizeUnit =
        sizeUnits.contains(_sizeUnit) ? _sizeUnit : sizeUnits.first;
    final double price = (widget.product['price'] is int)
        ? (widget.product['price'] as int).toDouble()
        : (widget.product['price'] ?? 0.0);
    final String description = widget.product['description'] ?? 'No description available.';

    // Sale-aware display values (single source of truth: sale_price.dart).
    // `now` comes from SaleEndWatcher — the sale expires the moment the
    // countdown reaches zero.
    final bool onSale = isOnSale(widget.product, now: now);
    final double displayPrice = effectivePrice(widget.product, now: now);
    final double saveAmount = price - displayPrice;
    final DateTime? saleEndRaw =
        DateTime.tryParse(widget.product['sale_ends_at']?.toString() ?? '');
    final String saleEndLabel = onSale
        ? 'You save ₱${saveAmount.toStringAsFixed(2)}'
            '${saleEndRaw != null ? ' · Ends ${_formatSaleEnd(saleEndRaw.toLocal())}' : ''}'
        : '';

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.02),
          CustomScrollView(
            slivers: [
              // Expandable sliver image header (NO APP BAR)
              SliverAppBar(
                expandedHeight: 380,
                pinned: true,
                backgroundColor: AppConstants.secondary,
                elevation: 0,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                actions: [
                  // Share button
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.share_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    onPressed: () => _shareProduct(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                  const SizedBox(width: 4),
                  CartIconButton(iconKey: _cartIconKey),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildImageCarousel(now),
                ),
              ),

              // Detail content
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 160), // High bottom padding for floating pill
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Name & Category
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.product['name'] ?? 'Carcar Footwear',
                              style: AppConstants.headlineStyle(fontSize: 26),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SoleBadge(
                            label: widget.product['category'] ?? 'Artisan',
                            backgroundColor: AppConstants.primary.withValues(alpha: 0.15),
                            textColor: AppConstants.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Price tag — sale-aware: strikethrough original +
                      // sale price + savings/end-date note. The sale price is
                      // hidden behind a peel-away tape (same reveal state as
                      // the card tags); the original price stays always
                      // visible.
                      if (onSale) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SalePriceTape(
                              productId:
                                  widget.product['id']?.toString() ?? '',
                              // This row is bottom-aligned with the original
                              // price beside it — the padding slack goes ABOVE
                              // the price so its bottom stays flush with the
                              // strikethrough price, while still reserving a
                              // ≥40px hit target.
                              hitPadding:
                                  const EdgeInsets.fromLTRB(10, 22, 10, 0),
                              child: Text(
                                '₱${displayPrice.toStringAsFixed(2)}',
                                style: AppConstants.monoStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₱${price.toStringAsFixed(2)}',
                              style: AppConstants.monoStyle(
                                fontSize: 14,
                                color:
                                    AppConstants.secondary.withValues(alpha: 0.5),
                              ).copyWith(
                                  decoration: TextDecoration.lineThrough),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppConstants.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            saleEndLabel,
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.error,
                            ),
                          ),
                        ),
                      ]                      else
                        Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: AppConstants.monoStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          ),
                        ),
                      // Social proof row — units sold (paid, non-cancelled
                      // orders) + average rating when available. Hidden
                      // entirely for products with no sales and no reviews
                      // so new listings don't show empty counters.
                      Selector<ProductProvider, (int, double, int)>(
                        selector: (_, p) {
                          final pid = widget.product['id']?.toString() ?? '';
                          return (
                            p.unitsSoldFor(pid),
                            (widget.product['avg_rating'] as num?)?.toDouble() ?? 0,
                            (widget.product['review_count'] as num?)?.toInt() ?? 0,
                          );
                        },
                        builder: (context, data, _) {
                          final (sold, avgRating, reviewCount) = data;
                          if (sold <= 0 && reviewCount <= 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                if (sold > 0) ...[
                                  Text(
                                    '$sold sold',
                                    style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppConstants.secondary.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                                if (sold > 0 && reviewCount > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      '·',
                                      style: AppConstants.bodyStyle(
                                        fontSize: 12,
                                        color: AppConstants.secondary.withValues(alpha: 0.3),
                                      ),
                                    ),
                                  ),
                                if (reviewCount > 0) ...[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 15,
                                    color: AppConstants.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${avgRating.toStringAsFixed(1)} ($reviewCount)',
                                    style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      color: AppConstants.secondary.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      // Product tags — real data from products.tags.
                      // Tappable: navigates to a screen showing all products with that tag.
                      if (_productTags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final tag in _productTags)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TagProductsScreen(tagId: tag),
                                        ),
                                      );
                                    },
                                    child: SoleBadge(
                                      label: _tagLabel(tag),
                                      backgroundColor: AppConstants.primary
                                          .withValues(alpha: 0.1),
                                      textColor: AppConstants.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Color variant swatches — real colors from the
                      // product's variants; hidden when none are set.
                      // Shows thumbnail images when color images exist,
                      // falls back to color dots.
                      //
                      // Above the size selector on purpose: the size grid
                      // (`_buildSizesMap`) is filtered to the active colour,
                      // so the colour is the choice the sizes below depend on —
                      // and a swatch tap swaps the gallery above it, so the
                      // photograph answers the tap.
                      //
                      // A tap on the ringed colour is a **deselect**: the gallery
                      // goes back to the product's own photos
                      // ([_sortedImageUrls]) — the app's own `allowDeselect`
                      // behaviour from the seller's colour sheet.
                      if (_variantColorNames.isNotEmpty) ...[
                        Text(
                          'Select Color / Leather',
                          style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final colorName in _variantColorNames)
                                ColorThumbnailSwatch(
                                  name: colorName,
                                  fallbackColor: _swatchColorFor(colorName),
                                  // The ring is the shopper's own pick, not
                                  // `_effectiveColor`'s first-colour fallback:
                                  // nothing is ringed until a tap, and the tap
                                  // that takes a choice off has to be able to
                                  // leave nothing ringed.
                                  selected: _selectedColourOrNull == colorName,
                                  imageUrl: _colorThumbnailUrl(colorName),
                                  onTap: () => setState(() {
                                    // Tapping the colour already showing takes
                                    // the choice back off (`allowDeselect`, the
                                    // seller's own sheet does the same). The
                                    // gallery then falls back to the product's
                                    // photos and pricing/sizes to the first
                                    // colour, exactly as before any tap.
                                    _selectedColor =
                                        _selectedColourOrNull == colorName
                                            ? null
                                            : colorName;
                                    // Reset image carousel when color changes
                                    _currentImageIndex = 0;
                                    _imagePageController.jumpToPage(0);
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Size Selector Label + unit switcher, with the
                      // Size guide link aligned on the same row.
                      Row(
                        children: [
                          Text(
                            'Select Size',
                            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(width: 10),
                          if (sizeUnits.length > 1)
                            _UnitSwitcher(
                              current: sizeUnit,
                              units: sizeUnits,
                              onChanged: (unit) =>
                                  setState(() => _sizeUnit = unit),
                            ),
                          const Spacer(),
                          _SizeHelperLink(
                            icon: Icons.straighten_outlined,
                            label: 'Size guide',
                            onTap: () => SizeGuideModal.show(context),
                          ),
                        ],
                      ),
                      // Size Selector row
                      if (_isLoadingSizes)
                        _buildSizeSkeleton()
                      else if (sizesMap.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppConstants.borderGray.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: AppConstants.secondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'No sizes available for this product.',
                                style: AppConstants.bodyStyle(
                                  fontSize: 13,
                                  color: AppConstants.secondary.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        // Pull the size grid up so it tucks under the label.
                        // (Transform, not a negative margin — Container
                        // asserts margins must be non-negative.)
                        Transform.translate(
                          offset: const Offset(0, -6),
                          child: GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          // Cells are narrower with 4 columns — ease the
                          // ratio so buttons keep a comfortable height.
                          childAspectRatio: 2.6,
                          // Let the corner badge poke past the button edge.
                          clipBehavior: Clip.none,
                          children: sizesMap.entries.map((entry) {
                            final size = entry.key;
                            final stock = entry.value;
                            final isAvailable = stock > 0;
                            final isSelected = _selectedSize == size;

                            final isLowStock = isAvailable && stock <= 5;
                            // Label respects the active unit and the chart the
                            // product is sold on; the canonical string stays
                            // untouched so variant lookup and cart keys keep
                            // matching the DB rows.
                            final label = displaySizeInUnit(size, sizeUnit,
                                category: sizeChart);

                            return GestureDetector(
                              onTap: isAvailable
                                  ? () {
                                      setState(() {
                                        // Map the tapped label back to the
                                        // canonical size for this product
                                        // (bijective conversion, so this
                                        // always resolves to the same size).
                                        _selectedSize = sizesMap.keys.firstWhere(
                                          (s) =>
                                              displaySizeInUnit(s, sizeUnit,
                                                  category: sizeChart) ==
                                              label,
                                          orElse: () => size,
                                        );
                                      });
                                    }
                                  : null,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Inset the button inside its grid cell so
                                  // the width stays a bit tighter than the
                                  // cell while the gap between buttons stays
                                  // small.
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Container(
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppConstants.primary
                                          : (isAvailable
                                              ? AppConstants.sellerCardBg
                                              : AppConstants.borderGray.withValues(alpha: 0.2)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppConstants.primary
                                            : AppConstants.borderGray.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Text(
                                            label,
                                            style: AppConstants.monoStyle(
                                              fontSize: 11,
                                              color: isSelected
                                                  ? AppConstants.surfaceLight
                                                  : (isAvailable
                                                      ? AppConstants.secondary
                                                      : AppConstants.secondary.withValues(alpha: 0.3)),
                                            ),
                                          ),
                                          if (!isAvailable)
                                            // Strikethrough for unavailable sizes
                                            Transform.rotate(
                                              angle: -0.5,
                                              child: Container(
                                                width: 32,
                                                height: 2,
                                                color: AppConstants.error.withValues(alpha: 0.5),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    ),
                                  ),
                                  // Low-stock orange corner badge (like the
                                  // reference): '2 left' overlapping the
                                  // top-right corner of the button.
                                  if (isLowStock)
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppConstants.statusPendingColor,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          '$stock left',
                                          style: AppConstants.bodyStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // ── Fit verdict (V1 of the virtual-fitting roadmap) ──
                        // Sits under the grid it is about and above the buy
                        // controls, because it answers the question the size
                        // buttons just asked. Renders nothing — and leaves no
                        // gap — when the feature is off, the product carries
                        // no last spec, or the customer has no scan to grade
                        // against; the widget owns all of that.
                        FitVerdictCard(
                          product: widget.product,
                          selectedSize: _selectedSize,
                        ),
                        // ── 3D preview notice (V3.10 of the fitting roadmap) ──
                        // The shoe itself is no longer a row here: the 3D icon
                        // on the product photograph opens the full-screen viewer
                        // (`_openShoePreview`). What is left in the flow is the
                        // one state the icon cannot explain — a prefetch that
                        // failed or never finished on a product that has a model
                        // — and it keeps its sentence and its Retry. Renders
                        // nothing, and leaves no gap, in every other case.
                        _shoePreviewNotice(),
                        _buildQuantityStepper(),
                        // Pickup hold — FREE, 1-2 pairs of one size, held 24h.
                        // A different flow from the bulk (reseller) hold
                        // below: this one holds stock immediately and takes
                        // no deposit.
                        if (_totalStock() > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () async {
                                  final reserved =
                                      await showPickupReservationSheet(
                                    context,
                                    product: widget.product,
                                    stockByColor: _buildStockByColor(),
                                    initialColor: _effectiveColor,
                                    initialSize: _selectedSize,
                                  );
                                  // Stock moved out of inventory — refresh the
                                  // size map so the page stops offering it.
                                  if (reserved == true && mounted) {
                                    setState(() {});
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.storefront_outlined,
                                        size: 15,
                                        color: AppConstants.secondary
                                            .withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Reserve for pickup — free, held 24 hours',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppConstants.secondary
                                              .withValues(alpha: 0.7),
                                        ).copyWith(
                                            decoration:
                                                TextDecoration.underline),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Reseller entry point — request a bulk hold from
                        // the seller (shown only when the product has stock).
                        if (_totalStock() > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => showBulkReservationSheet(
                                  context,
                                  product: widget.product,
                                  stockByColor: _buildStockByColor(),
                                  initialColor: _effectiveColor,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 15,
                                        color: AppConstants.secondary
                                            .withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Buying to resell? Request a bulk hold',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppConstants.secondary
                                              .withValues(alpha: 0.7),
                                        ).copyWith(
                                            decoration:
                                                TextDecoration.underline),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ],
                        ),
                      const SizedBox(height: 12),

                      // Description section
                      Text(
                        'The Craftsmanship',
                        style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isDescriptionExpanded = !_isDescriptionExpanded;
                          });
                        },
                        child: Text(
                          description,
                          maxLines: _isDescriptionExpanded ? 100 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            color: AppConstants.secondary.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isDescriptionExpanded = !_isDescriptionExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Text(
                            _isDescriptionExpanded ? 'Read less' : 'Read more',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Reviews Section ──────────────────────
                      _ReviewsSection(
                        productId: widget.product['id'].toString(),
                        productName: widget.product['name'] ?? '',
                      ),
                      const SizedBox(height: 24),

                      // ── More from Store ─────────────────────
                      _MoreFromStoreSection(
                        storeId: widget.product['store_id']?.toString() ?? '',
                        storeName: widget.product['store_name']?.toString() ?? widget.product['stores']?['name']?.toString() ?? '',
                        currentProductId: widget.product['id'].toString(),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),

          // Outlined Add to Cart / Solid Buy Now bar at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: AppConstants.surfaceLight,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  // Add to cart outlined
                  Expanded(
                    flex: 1,
                    child: AnimatedBuilder(
                      animation: _buttonScaleAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _buttonScaleAnimation.value,
                          child: child,
                        );
                      },
                      child: OutlinedButton(
                        onPressed: _isAddingToCart ? null : _addToCart,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _isAddingToCart
                                ? AppConstants.success
                                : AppConstants.primary,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppConstants.buttonRadius),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _isAddingToCart
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppConstants.success,
                                  key: ValueKey('success'),
                                )
                              : Text(
                                  'Add to Cart',
                                  key: const ValueKey('label'),
                                  style: AppConstants.bodyStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Buy Now filled
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _buyNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        shape: RoundedRectangleBorder(borderRadius: AppConstants.buttonRadius),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: Text(
                        'Buy Now',
                        style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold,
                          // Ink on the clay fill, which is pinned.
                          color: AppConstants.inkInverse,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small inline helper link (icon + label) used in the size section.
class _SizeHelperLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SizeHelperLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppConstants.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable unit switcher chip next to the size label.
/// Opens a small menu — the reference's chevron affordance.
///
/// [units] is the set the active shopping scale can label honestly, so a kids'
/// shopper never sees a US/UK step drawn on a chart this app does not own
/// (@see sizeUnitsForCategory).
class _UnitSwitcher extends StatelessWidget {
  final String current;
  final List<String> units;
  final ValueChanged<String> onChanged;

  const _UnitSwitcher({
    required this.current,
    required this.units,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: current,
      onSelected: onChanged,
      tooltip: 'Switch size unit',
      itemBuilder: (context) => [
        for (final unit in units)
          PopupMenuItem(
            value: unit,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unit,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight:
                        unit == current ? FontWeight.bold : FontWeight.normal,
                    color: unit == current
                        ? AppConstants.primary
                        : AppConstants.secondary,
                  ),
                ),
                if (unit == current) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check, size: 14, color: AppConstants.primary),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: AppConstants.primary,
            ),
          ],
        ),
      ),
    );
  }
}
