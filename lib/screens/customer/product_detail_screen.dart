import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../providers/cart_provider.dart';
import '../../providers/review_provider.dart';
import '../../utils/cart_helpers.dart';
import '../../utils/recently_viewed.dart';
import '../../utils/sale_price.dart';
import '../../widgets/sole_badge.dart';
import '../../widgets/sole_ar_pill.dart';
import '../../widgets/sole_review_card.dart';
import '../../widgets/sole_star_rating.dart';
import 'ar_fitting_screen.dart';
import 'checkout_screen.dart';
import 'write_review_screen.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/seller/fly_to_order_animation.dart';
import '../../widgets/seller/tag_selector.dart';
import '../../widgets/size_guide_modal.dart';
import '../../widgets/hanging_sale_tag.dart';
import '../../widgets/sale_price_tape.dart';
import '../../widgets/sale_countdown_overlay.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({
    super.key,
    required this.product,
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
        color: Colors.white,
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

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedSize;

  /// Selected variant color NAME (real data from product_variants).
  /// Null until the shopper picks one — the first available color is used
  /// by default via [_effectiveColor].
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

  /// The color used for ordering: the shopper's pick, or the first
  /// available color when none is picked yet.
  String? get _effectiveColor {
    final colors = _variantColorNames;
    if (colors.isEmpty) return null;
    if (_selectedColor != null && colors.contains(_selectedColor)) {
      return _selectedColor;
    }
    return colors.first;
  }

  /// Map a variant color NAME (free text from sellers) to a swatch color.
  /// Falls back to a deterministic warm tone from the name when unknown.
  Color _swatchColorFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('brown') || n.contains('tan') || n.contains('camel') ||
        n.contains('cognac') || n.contains('clay') || n.contains('leather')) {
      if (n.contains('dark')) return const Color(0xFF4E342E);
      if (n.contains('light')) return const Color(0xFFA1887F);
      return AppConstants.primary;
    }
    if (n.contains('black') || n.contains('charcoal')) {
      return const Color(0xFF26221E);
    }
    if (n.contains('carob')) return const Color(0xFF3E2723);
    if (n.contains('white') || n.contains('cream') || n.contains('beige') ||
        n.contains('off-white') || n.contains('suede')) {
      return const Color(0xFFF1E8DC);
    }
    if (n.contains('gold') || n.contains('mustard') || n.contains('yellow')) {
      return const Color(0xFFB8860B);
    }
    if (n.contains('red') || n.contains('burgundy') || n.contains('maroon')) {
      return const Color(0xFF9B3B2E);
    }
    if (n.contains('green') || n.contains('olive')) return const Color(0xFF5D6B45);
    if (n.contains('blue') || n.contains('navy')) return const Color(0xFF3F4A63);
    if (n.contains('grey') || n.contains('gray')) return const Color(0xFF9E948A);
    // Deterministic warm fallback keyed off the name.
    const palette = [
      Color(0xFF8B5A2B),
      Color(0xFF6B4A2F),
      Color(0xFFA9703C),
      Color(0xFF4E342E),
      Color(0xFF7C5A38),
      Color(0xFFB8860B),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  /// Build a map of {size: stock} from both inventory and product_variants.
  /// If a size exists in both tables, the higher stock value wins.
  /// Sizes are sorted numerically (EU sizing).
  Map<String, int> _buildSizesMap() {
    final Map<String, int> sizes = {};

    // From inventory table
    final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
    for (final row in inventory) {
      final size = row['size']?.toString();
      final stock = row['stock'] as int? ?? 0;
      if (size != null && size.isNotEmpty) {
        sizes[size] = (sizes[size] ?? 0) + stock;
      }
    }

    // From product_variants table
    final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
    for (final row in variants) {
      final size = row['size']?.toString();
      final stock = row['stock'] as int? ?? 0;
      if (size != null && size.isNotEmpty) {
        // Take the higher stock value if size already exists from inventory
        sizes[size] = ((sizes[size] ?? 0) < stock) ? stock : (sizes[size] ?? 0);
      }
    }

    // Sort numerically by EU size
    final sorted = Map.fromEntries(
      sizes.entries.toList()
        ..sort((a, b) =>
            (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0)),
    );

    return sorted;
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
    _addToCart();
    // Navigate to checkout after the box-pack animation completes
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const CheckoutScreen(),
        ),
      );
    });
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
  List<String> get _sortedImageUrls {
    // Try product_images first (list of {image_url, display_order} maps)
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
            color: Colors.white,
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
                color: Colors.white,
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 160), // High bottom padding for floating pill
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
                      const SizedBox(height: 10),

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
                      ] else
                        Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: AppConstants.monoStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          ),
                        ),
                      // Product tags — real data from products.tags.
                      if (_productTags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final tag in _productTags)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SoleBadge(
                                    label: _tagLabel(tag),
                                    backgroundColor: AppConstants.primary
                                        .withValues(alpha: 0.1),
                                    textColor: AppConstants.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Size Selector Label + unit switcher, with the
                      // Size guide link aligned on the same row.
                      Row(
                        children: [
                          Text(
                            'Select Size',
                            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(width: 10),
                          _UnitSwitcher(
                            current: _sizeUnit,
                            onChanged: (unit) => setState(() => _sizeUnit = unit),
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
                            // Label respects the active unit; the canonical
                            // string stays untouched so variant lookup and
                            // cart keys keep matching the DB rows.
                            final label = displaySizeInUnit(size, _sizeUnit);

                            return GestureDetector(
                              onTap: isAvailable
                                  ? () {
                                      setState(() {
                                        // Map the tapped label back to the
                                        // canonical size for this product
                                        // (bijective conversion, so this
                                        // always resolves to the same size).
                                        _selectedSize = sizesMap.keys.firstWhere(
                                          (s) => displaySizeInUnit(s, _sizeUnit) == label,
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
                                              ? const Color(0xFFF7F5F2)
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
                        _buildQuantityStepper(),
                          ],
                        ),
                      const SizedBox(height: 24),

                      // Color variant swatches — real colors from the
                      // product's variants; hidden when none are set.
                      if (_variantColorNames.isNotEmpty) ...[
                        Text(
                          'Select Color / Leather',
                          style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (final colorName in _variantColorNames)
                              _ColorSwatch(
                                name: colorName,
                                color: _swatchColorFor(colorName),
                                selected: _effectiveColor == colorName,
                                onTap: () => setState(() {
                                  _selectedColor = colorName;
                                }),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),

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
                    ],
                  ),
                ),
              )
            ],
          ),

          // Pinned AR Floating Try-On Pill (stands out, accent teal)
          Positioned(
            left: 20,
            right: 20,
            bottom: 84, // position above buy now buttons
            child: SoleARPill(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ARVirtualFitScreen(preselectedProduct: widget.product),
                  ),
                );
              },
            ),
          ),

          // Outlined Add to Cart / Solid Buy Now bar at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white,
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
                          color: AppConstants.surfaceLight,
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

/// Circular color swatch for a variant color name.
class _ColorSwatch extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppConstants.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: selected
              ? Icon(
                  Icons.check,
                  size: 14,
                  color: color == AppConstants.surfaceLight
                      ? AppConstants.secondary
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

/// Tappable unit switcher chip (US / EU / UK) next to the size label.
/// Opens a small menu — the reference's chevron affordance.
class _UnitSwitcher extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _UnitSwitcher({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: current,
      onSelected: onChanged,
      tooltip: 'Switch size unit',
      itemBuilder: (context) => [
        for (final unit in sizeUnits)
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
          color: Colors.white,
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
