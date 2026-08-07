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
import '../../widgets/size_guide_modal.dart';
import '../../widgets/hanging_sale_tag.dart';

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
  String _selectedColor = 'Burnished Clay';
  bool _isDescriptionExpanded = false;
  bool _isLoadingSizes = false;
  bool _isAddingToCart = false;

  // Image carousel state
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  // Button press animation (scale down/up on tap)
  late final AnimationController _buttonPressController;
  late final Animation<double> _buttonScaleAnimation;

  // GlobalKeys for fly-to-cart overlay animation
  final GlobalKey _productImageKey = GlobalKey();
  final GlobalKey _cartIconKey = GlobalKey();

  final List<String> _colors = ['Burnished Clay', 'Carob Dark', 'Off-White Suede', 'Saddle Brown'];
  final List<Color> _colorValues = [
    AppConstants.primary,
    AppConstants.secondary,
    AppConstants.surfaceLight,
    const Color(0xFFB8860B),
  ];

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
      color: _selectedColor,
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
      color: _selectedColor,
      storeId: widget.product['store_id']?.toString(),
      storeName: widget.product['store_name']?.toString(),
      variantId: variantId,
      additionalPrice: additionalPrice,
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
  Future<void> _shareProduct() async {
    final name = widget.product['name'] ?? 'CUFMAI Footwear';
    final price = effectivePrice(widget.product);
    final priceStr = '₱${price.toStringAsFixed(2)}';
    final storeName = widget.product['store_name'] ?? 'CUFMAI';

    final text = 'Check out $name — only $priceStr at $storeName!\n\nBrowse more artisan footwear on the CUFMAI app.';

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

  Widget _buildImageCarousel() {
    final imageUrls = _sortedImageUrls;

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
        // Main swipeable image area
        AspectRatio(
          aspectRatio: 1.0,
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
                color: Colors.black.withOpacity(0.55),
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
        if (isOnSale(widget.product))
          Positioned(
            top: 52,
            left: -7,
            child: HangingSaleTag(
              productId: widget.product['id']?.toString() ?? '',
              salePercent: salePercent(widget.product),
            ),
          ),

        // Dot indicators — bottom center
        if (imageUrls.length > 1)
          Positioned(
            bottom: 12,
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
      baseColor: AppConstants.borderGray.withOpacity(0.4),
      highlightColor: AppConstants.borderGray.withOpacity(0.1),
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

  // ─── SIZE SKELETON ───────────────────────────────────────────────

  /// Shimmer skeleton placeholders for the size selector row.
  Widget _buildSizeSkeleton() {
    return Shimmer.fromColors(
      baseColor: AppConstants.borderGray.withOpacity(0.3),
      highlightColor: AppConstants.borderGray.withOpacity(0.1),
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
    final sizesMap = _buildSizesMap();
    final double price = (widget.product['price'] is int)
        ? (widget.product['price'] as int).toDouble()
        : (widget.product['price'] ?? 0.0);
    final String description = widget.product['description'] ?? 'No description available.';

    // Sale-aware display values (single source of truth: sale_price.dart)
    final bool onSale = isOnSale(widget.product);
    final double displayPrice = effectivePrice(widget.product);
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
                    color: Colors.black.withOpacity(0.3),
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
                        color: Colors.black.withOpacity(0.3),
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
                  background: _buildImageCarousel(),
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
                            backgroundColor: AppConstants.primary.withOpacity(0.15),
                            textColor: AppConstants.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Price tag — sale-aware: strikethrough original +
                      // sale price + savings/end-date note.
                      if (onSale) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₱${displayPrice.toStringAsFixed(2)}',
                              style: AppConstants.monoStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₱${price.toStringAsFixed(2)}',
                              style: AppConstants.monoStyle(
                                fontSize: 14,
                                color:
                                    AppConstants.secondary.withOpacity(0.5),
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
                      const SizedBox(height: 24),

                      // Size Selector Label
                      Row(
                        children: [
                          Text(
                            'Select Size (EU)',
                            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => SizeGuideModal.show(context),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.straighten_outlined,
                                    size: 14,
                                    color: AppConstants.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Size guide',
                                    style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppConstants.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Size Selector row
                      if (_isLoadingSizes)
                        _buildSizeSkeleton()
                      else if (sizesMap.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppConstants.borderGray.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: AppConstants.secondary.withOpacity(0.5),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'No sizes available for this product.',
                                style: AppConstants.bodyStyle(
                                  fontSize: 13,
                                  color: AppConstants.secondary.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child:                      Row(
                        children: sizesMap.entries.map((entry) {
                          final size = entry.key;
                          final stock = entry.value;
                              final isAvailable = stock > 0;
                              final isSelected = _selectedSize == size;

                              final isLowStock = isAvailable && stock <= 5;

                              return GestureDetector(
                                onTap: isAvailable
                                    ? () {
                                        setState(() {
                                          _selectedSize = size;
                                        });
                                      }
                                    : null,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppConstants.primary
                                            : (isAvailable ? Colors.white : AppConstants.borderGray.withOpacity(0.2)),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppConstants.primary
                                              : AppConstants.borderGray.withOpacity(0.5),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Text(
                                              size,
                                              style: AppConstants.monoStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected
                                                    ? AppConstants.surfaceLight
                                                    : (isAvailable
                                                        ? AppConstants.secondary
                                                        : AppConstants.secondary.withOpacity(0.3)),
                                              ),
                                            ),
                                            if (!isAvailable)
                                              // Strikethrough for unavailable sizes
                                              Transform.rotate(
                                                angle: -0.5,
                                                child: Container(
                                                  width: 32,
                                                  height: 2,
                                                  color: AppConstants.error.withOpacity(0.5),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Low stock label below the size chip
                                    if (isLowStock)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2, right: 8),
                                        child: Text(
                                          'Only $stock left',
                                          style: AppConstants.bodyStyle(
                                            fontSize: 9,
                                            color: AppConstants.error,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Color variant swatches
                      Text(
                        'Select Color / Leather',
                        style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: List.generate(_colors.length, (index) {
                          final colorName = _colors[index];
                          final colorVal = _colorValues[index];
                          final isSelected = _selectedColor == colorName;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = colorName;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? AppConstants.primary : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: colorVal,
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        size: 14,
                                        color: colorVal == AppConstants.surfaceLight
                                            ? AppConstants.secondary
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ),
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
                            color: AppConstants.secondary.withOpacity(0.8),
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
