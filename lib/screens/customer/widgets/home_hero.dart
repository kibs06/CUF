import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/app_constants.dart';
import '../../../providers/product_provider.dart';

/// Full-bleed hero at the top of [CustomerHomeScreen].
///
/// Contains the gradient background, icon row (notification + search + cart),
/// greeting, frosted category chips, featured banner carousel with floating
/// product cards, "Shop now" CTA, and page-indicator dots.
///
/// The hero scrolls away as the user scrolls — it is NOT pinned.
class HomeHero extends StatefulWidget {
  const HomeHero({
    super.key,
    this.onCartTap,
    this.onCtaTap,
    this.onProductTap,
    this.cartCount = 0,
    this.searchController,
    this.searchFocusNode,
    this.onSearchChanged,
  });

  /// Called when the cart icon is tapped.
  final VoidCallback? onCartTap;

  /// Called when "SHOP NOW →" is tapped.
  final VoidCallback? onCtaTap;

  /// Called when a floating product card is tapped.
  /// Receives the product data map.
  final ValueChanged<Map<String, dynamic>>? onProductTap;

  /// Number of items in the cart — shown as a badge on the cart icon.
  final int cartCount;

  /// Controller for the search TextField (owned by parent).
  final TextEditingController? searchController;

  /// FocusNode for the search TextField (owned by parent).
  final FocusNode? searchFocusNode;

  /// Called when the search text changes.
  final ValueChanged<String>? onSearchChanged;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  late final PageController _bannerController;
  late final Timer _bannerTimer;
  int _bannerIndex = 0;
  bool _isSearchFocused = false;




  // Featured arrivals — editorial carousel content.
  static const _featuredArrivals = [
    {
      'title': 'The Carcar Craft Revolution',
      'subtitle': 'Discover vegetable-tanned custom designs',
      'image':
          'https://images.unsplash.com/photo-1549298916-b41d501d3772?q=80&w=800&auto=format&fit=crop',
    },
    {
      'title': 'Signature Cordwainer Series',
      'subtitle': 'Double welted artisan soles built for steps',
      'image':
          'https://images.unsplash.com/photo-1533867617858-e7b97e060509?q=80&w=800&auto=format&fit=crop',
    },
    {
      'title': 'Summertime Leather Sandals',
      'subtitle': 'Crafted using sustainable leather cuts',
      'image':
          'https://images.unsplash.com/photo-1543163521-1bf539c55dd2?q=80&w=800&auto=format&fit=crop',
    },
  ];

  @override
  void initState() {
    super.initState();
    _bannerController = PageController();

    widget.searchFocusNode?.addListener(_onFocusChange);

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_bannerController.hasClients) return;
      final next = (_bannerIndex + 1) % _featuredArrivals.length;
      setState(() => _bannerIndex = next);
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    widget.searchFocusNode?.removeListener(_onFocusChange);
    _bannerController.dispose();
    _bannerTimer.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = widget.searchFocusNode?.hasFocus ?? false;
    if (focused != _isSearchFocused) {
      setState(() => _isSearchFocused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.products,
    );
    final categories = context.select<ProductProvider, List<String>>(
      (p) => p.categories,
    );
    final selectedCategory = context.select<ProductProvider, String?>(
      (p) => p.selectedCategory,
    );
    final selectCategory = context.read<ProductProvider>().selectCategory;

    // Two real products for the floating cards (take the first two).
    final floatingProducts = products.length >= 2
        ? [products[0], products[1]]
        : products;

    return SizedBox(
      height: 340,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background gradient ────────────────────────────
          _buildBackground(),

          // ── Content overlay ────────────────────────────────
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon row: search bar + cart
                _buildIconRow(),

                // Frosted category chips
                _buildChips(categories, selectedCategory, selectCategory),

                const Spacer(),

                // Hero text block + floating product cards + CTA + dots
                _buildBottomContent(floatingProducts),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Background gradient ────────────────────────────────────

  Widget _buildBackground() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFD4A574), // warm sand
            Color(0xFFB08050), // golden brown
            Color(0xFF6B4226), // deep chocolate
          ],
        ),
      ),
      child: Stack(
        children: [
          // Warm radial glow in upper-right
          Positioned(
            top: -40,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFDEB4).withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Dark gradient overlay for text readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x590F0A07).withValues(alpha: 0.35),
                    const Color(0xD90F0A07).withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.45],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Icon row: notification bell + search + cart ─────────────

  Widget _buildIconRow() {
    final focused = _isSearchFocused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          // Search bar — real, functional TextField with focus state
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 38,
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: focused
                      ? AppConstants.primary
                      : Colors.white.withValues(alpha: 0.3),
                  width: focused ? 1.5 : 1,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: AppConstants.primary.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
                onChanged: widget.onSearchChanged,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search leather shoes…',
                  hintStyle: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(left: 8, right: 4),
                    decoration: BoxDecoration(
                      color: focused
                          ? AppConstants.primary
                          : AppConstants.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.search,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Cart icon with item count badge
          _IconBadge(
            icon: widget.cartCount > 0
                ? Icons.shopping_bag
                : Icons.shopping_bag_outlined,
            unreadCount: widget.cartCount,
            useAccentBadge: true,
            onTap: widget.onCartTap,
          ),
        ],
      ),
    );
  }

  // ── Category tabs with underline indicator ─────────────────

  Widget _buildChips(
    List<String> categories,
    String? selectedCategory,
    ValueChanged<String> onSelect,
  ) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat;
          return GestureDetector(
            onTap: () => onSelect(cat),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cat,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Underline — grows from center on select
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    height: 2,
                    width: isSelected ? _measureTextWidth(cat) : 0,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Measure the rendered width of [text] at the tab style.
  double _measureTextWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppConstants.bodyStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  // ── Bottom content: hero text, floating cards, CTA, dots ──

  Widget _buildBottomContent(List<Map<String, dynamic>> floatingProducts) {
    return SizedBox(
      height: 160,
      child: Stack(
        children: [
          // Hero text block (left)
          Positioned(
            left: 18,
            bottom: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEW ARRIVALS',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFC89B5C),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CRAFTED\nFOR FALL',
                  style: AppConstants.headlineStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ).copyWith(height: 1.05),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: widget.onCtaTap,
                  child: Text(
                    'SHOP NOW →',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),

          // Floating product cards (right)
          if (floatingProducts.isNotEmpty)
            Positioned(
              right: 14,
              bottom: 44,
              child: _buildFloatingCards(floatingProducts),
            ),

          // Page indicator dots (bottom-left)
          Positioned(
            left: 18,
            bottom: 16,
            child: Row(
              children: List.generate(_featuredArrivals.length, (i) {
                final isActive = _bannerIndex == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isActive ? 14 : 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating product cards ─────────────────────────────────

  Widget _buildFloatingCards(List<Map<String, dynamic>> products) {
    return SizedBox(
      width: 150,
      height: 110,
      child: Stack(
        children: [
          // First card (behind, rotated left)
          if (products.isNotEmpty)
            Positioned(
              left: 0,
              top: 10,
              child: GestureDetector(
                onTap: () => widget.onProductTap?.call(products[0]),
                child: Transform.rotate(
                  angle: -0.035, // ~-2 degrees
                  child: _ProductFloatCard(
                    product: products[0],
                    size: const Size(76, 96),
                  ),
                ),
              ),
            ),

          // Second card (front, rotated right)
          if (products.length > 1)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => widget.onProductTap?.call(products[1]),
                child: Transform.rotate(
                  angle: 0.035, // ~2 degrees
                  child: _ProductFloatCard(
                    product: products[1],
                    size: const Size(76, 96),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Private helper widgets
// ═══════════════════════════════════════════════════════════════

/// Circular icon button with optional unread-count dot or count badge.
///
/// When [useAccentBadge] is true, shows a number badge (like CartIconButton).
/// Otherwise shows a small dot (for notifications).
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    this.unreadCount = 0,
    this.onTap,
    this.useAccentBadge = false,
  });

  final IconData icon;
  final int unreadCount;
  final VoidCallback? onTap;

  /// When true, shows a number count badge (accent color).
  /// When false, shows a small red dot.
  final bool useAccentBadge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            if (unreadCount > 0 && useAccentBadge)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.accent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.accent.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: AppConstants.monoStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (unreadCount > 0 && !useAccentBadge)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppConstants.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single floating product card in the hero — shows product image + price.
class _ProductFloatCard extends StatelessWidget {
  const _ProductFloatCard({
    required this.product,
    required this.size,
  });

  final Map<String, dynamic> product;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product['image_url']?.toString();
    final price = product['price'];

    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        color: AppConstants.surfaceLight,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Product image
            Positioned.fill(
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: AppConstants.surfaceLight,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: AppConstants.surfaceLight,
                        child: Icon(
                          Icons.image_outlined,
                          size: 24,
                          color: AppConstants.secondary.withValues(alpha: 0.3),
                        ),
                      ),
                    )
                  : Container(
                      color: AppConstants.surfaceLight,
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        size: 24,
                        color: AppConstants.secondary.withValues(alpha: 0.3),
                      ),
                    ),
            ),

            // Price tag
            if (price != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '₱${_formatPrice(price)}',
                    style: AppConstants.monoStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price is num) {
      return price.toInt().toString();
    }
    return price?.toString() ?? '0';
  }
}
