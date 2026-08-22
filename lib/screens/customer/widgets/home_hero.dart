import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../constants/app_constants.dart';
import '../../../providers/banner_provider.dart';
import '../../../providers/product_provider.dart';

/// Full-bleed hero at the top of [CustomerHomeScreen].
///
/// Displays a real banner carousel fetched from Supabase. Each banner has
/// an image background, optional eyebrow/title/CTA, and optional link.
/// Falls back to a gradient-only state while loading or when no banners exist.
class HomeHero extends StatefulWidget {
  const HomeHero({
    super.key,
    this.onCartTap,
    this.cartCount = 0,
    this.searchController,
    this.searchFocusNode,
    this.onSearchChanged,
  });

  /// Called when the cart icon is tapped.
  final VoidCallback? onCartTap;

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

/// Default fallback banners shown when no active Supabase banners exist.
/// Each entry mirrors the real-banner shape so the same carousel machinery
/// can render them — the `_assetPath` field signals local asset vs network URL.
const _defaultBanners = <Map<String, dynamic>>[
  {
    '_assetPath': 'assets/images/default_hero_banner.png',
    'eyebrow_text': 'Carcar City, Philippines',
    'title': 'Made by hand,\nmade to last.',
    'link_type': 'none',
  },
  {
    '_assetPath': 'assets/images/default_hero_banner_2.png',
    'eyebrow_text': 'Carcar City, Philippines',
    'title': 'Every pair,\nready for you.',
    'link_type': 'none',
  },
  {
    '_assetPath': 'assets/images/default_hero_banner_3.png',
    'eyebrow_text': 'Carcar City, Philippines',
    'title': 'From our stalls,\nto your steps.',
    'link_type': 'none',
  },
];

class _HomeHeroState extends State<HomeHero> {
  late final PageController _bannerController;
  Timer? _bannerTimer;
  int _bannerIndex = 0;
  bool _isSearchFocused = false;
  bool _isUserDragging = false;

  @override
  void initState() {
    super.initState();
    _bannerController = PageController();
    widget.searchFocusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.searchFocusNode?.removeListener(_onFocusChange);
    _bannerController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = widget.searchFocusNode?.hasFocus ?? false;
    if (focused != _isSearchFocused) {
      setState(() => _isSearchFocused = focused);
    }
  }

  /// Start or restart the auto-scroll timer.
  void _startAutoScroll(int bannerCount) {
    _bannerTimer?.cancel();
    if (bannerCount <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_bannerController.hasClients || _isUserDragging) return;
      final next = (_bannerIndex + 1) % bannerCount;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Handle CTA tap based on the current banner's link_type/link_value.
  void _handleCtaTap(Map<String, dynamic> banner) {
    final linkType = banner['link_type']?.toString() ?? 'none';
    final linkValue = banner['link_value']?.toString();

    switch (linkType) {
      case 'category':
        if (linkValue != null && linkValue.isNotEmpty) {
          context.read<ProductProvider>().selectCategory(linkValue);
        }
        break;
      case 'product':
        if (linkValue != null && linkValue.isNotEmpty) {
          _openProduct(linkValue);
        }
        break;
      case 'url':
        if (linkValue != null && linkValue.isNotEmpty) {
          _openUrl(linkValue);
        }
        break;
      case 'none':
      default:
        // No link — CTA is non-interactive or not rendered
        break;
    }
  }

  Future<void> _openProduct(String productId) async {
    try {
      final product = await Supabase.instance.client
          .from('products')
          .select()
          .eq('id', productId)
          .maybeSingle();
      if (product != null && mounted) {
        // The parent screen handles navigation — we can't push from here
        // since we don't have the navigator context. Instead, we'll use a
        // callback pattern. For now, log that we'd navigate.
        debugPrint('[HomeHero] Would navigate to product: $productId');
      }
    } catch (e) {
      debugPrint('[HomeHero] Failed to fetch product for CTA: $e');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = context.select<BannerProvider, List<Map<String, dynamic>>>(
      (p) => p.banners,
    );
    final isLoading = context.select<BannerProvider, bool>(
      (p) => p.isLoading,
    );
    final categories = context.select<ProductProvider, List<String>>(
      (p) => p.categories,
    );
    final selectedCategory = context.select<ProductProvider, String?>(
      (p) => p.selectedCategory,
    );
    final selectCategory = context.read<ProductProvider>().selectCategory;

    // When no real banners exist, use the built-in default carousel.
    final bannerCount = banners.length;
    final activeBanners = bannerCount > 0 ? banners : _defaultBanners;
    final isDefault = bannerCount == 0 && !isLoading;
    final displayCount = activeBanners.length;

    // Start auto-scroll when banners are available.
    if (displayCount > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAutoScroll(displayCount);
      });
    }

    // Clamp page index if banners changed.
    if (_bannerIndex >= displayCount && displayCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _bannerIndex = 0);
          _bannerController.jumpToPage(0);
        }
      });
    }

    return SizedBox(
      height: 340,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: banner carousel (real or default) ──
          if (displayCount > 0)
            _buildBannerCarousel(activeBanners)
          else if (isLoading)
            _buildLoadingSkeleton()
          else
            _buildGradientFallback(),

          // ── Dark overlay for text readability ──
          // IgnorePointer so touches pass through to the PageView below.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xEB0A0806).withValues(alpha: 0.92),
                      const Color(0x590A0806).withValues(alpha: 0.35),
                      const Color(0x260A0806).withValues(alpha: 0.15),
                      const Color(0x8C0A0806).withValues(alpha: 0.55),
                    ],
                    stops: const [0.0, 0.40, 0.62, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Content overlay ──
          // GestureDetector with translucent lets horizontal drags pass
          // through to the PageView below while keeping taps on the
          // search bar, cart icon, and category tabs functional.
          SafeArea(
            bottom: false,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon row: search bar + cart
                  _buildIconRow(),

                  // Frosted category chips
                  _buildChips(categories, selectedCategory, selectCategory),

                  const Spacer(),

                  // Hero text block + CTA + dots
                  if (displayCount > 0)
                    _buildBottomContent(activeBanners),
                ],
              ),
            ),
          ),

          // Brand mark — only shown in the default fallback state
          // Aligned with the left-side headline text (same bottom offset)
          if (isDefault)
            Positioned(
              right: 18,
              bottom: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'CUFMAI',
                    style: AppConstants.headlineStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ).copyWith(letterSpacing: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Carcar United Footwear',
                    style: AppConstants.bodyStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Manufacturing Inc.',
                    style: AppConstants.bodyStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Banner carousel (PageView) — handles both network URLs and local assets ──

  Widget _buildBannerCarousel(List<Map<String, dynamic>> banners) {
    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: PageView.builder(
        controller: _bannerController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: banners.length,
        onPageChanged: (index) {
          setState(() => _bannerIndex = index);
          _startAutoScroll(banners.length);
        },
        itemBuilder: (context, index) {
          final banner = banners[index];
          final assetPath = banner['_assetPath']?.toString();
          final imageUrl = banner['image_url']?.toString();

          // Local asset (default fallback banners)
          if (assetPath != null && assetPath.isNotEmpty) {
            return Image.asset(
              assetPath,
              fit: BoxFit.cover,
              alignment: const Alignment(0.0, -0.24),
              errorBuilder: (_, _, _) => _buildGradientFallback(),
            );
          }

          // Network URL (real Supabase banners)
          return CachedNetworkImage(
            imageUrl: imageUrl ?? '',
            fit: BoxFit.cover,
            placeholder: (_, _) => _buildGradientFallback(),
            errorWidget: (_, _, _) => _buildGradientFallback(),
          );
        },
      ),
    );
  }

  // ── Manual horizontal drag handling ─────────────────────────
  // Claims horizontal drags explicitly so the parent CustomScrollView
  // (vertical) doesn't steal them from the PageView.

  void _onHorizontalDragStart(DragStartDetails details) {
    _isUserDragging = true;
    _bannerTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    final offset = _bannerController.offset - delta;
    _bannerController.jumpTo(
      offset.clamp(0.0, _bannerController.position.maxScrollExtent),
    );
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    final page = _bannerController.page?.round() ?? _bannerIndex;
    final count = _bannerController.position.viewportDimension > 0
        ? (_bannerController.position.maxScrollExtent /
                _bannerController.position.viewportDimension + 1)
            .round()
        : 1;

    int targetPage;
    if (velocity.abs() > 300) {
      // Fast swipe — go to next/previous page
      targetPage = velocity < 0 ? (page + 1).clamp(0, count - 1) : (page - 1).clamp(0, count - 1);
    } else {
      // Slow drag — snap to nearest page
      targetPage = page;
    }

    _bannerController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() => _bannerIndex = targetPage);

    // Resume auto-scroll after a brief pause
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _isUserDragging = false;
        _startAutoScroll(count);
      }
    });
  }

  // ── Gradient fallback for broken images / loading state ──────

  Widget _buildGradientFallback() {
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
    );
  }

  // ── Loading skeleton ──────────────────────────────────────────

  Widget _buildLoadingSkeleton() {
    return _buildGradientFallback();
  }

  // ── Icon row: search + cart ───────────────────────────────────

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
                    child: const Icon(
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

  // ── Bottom content with banner data ─────────────────────────

  Widget _buildBottomContent(
    List<Map<String, dynamic>> banners,
  ) {
    final currentBanner = banners.isNotEmpty ? banners[_bannerIndex.clamp(0, banners.length - 1)] : null;
    final eyebrow = currentBanner?['eyebrow_text']?.toString();
    final title = currentBanner?['title']?.toString();
    final ctaLabel = currentBanner?['cta_label']?.toString();
    final linkType = currentBanner?['link_type']?.toString() ?? 'none';

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
                if (eyebrow != null && eyebrow.isNotEmpty)
                  Text(
                    eyebrow.toUpperCase(),
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFC89B5C),
                      letterSpacing: 2,
                    ),
                  ),
                if (eyebrow != null && eyebrow.isNotEmpty) const SizedBox(height: 4),
                if (title != null && title.isNotEmpty)
                  Text(
                    title.toUpperCase(),
                    style: AppConstants.headlineStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ).copyWith(height: 1.05),
                  ),
                if (ctaLabel != null && ctaLabel.isNotEmpty && linkType != 'none') ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      if (currentBanner != null) _handleCtaTap(currentBanner);
                    },
                    child: Text(
                      '${ctaLabel.toUpperCase()} →',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ).copyWith(decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Page indicator dots (bottom-left)
          if (banners.length > 1)
            Positioned(
              left: 18,
              bottom: 16,
              child: Row(
                children: List.generate(banners.length, (i) {
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



}

// ═══════════════════════════════════════════════════════════════
// Private helper widgets
// ═══════════════════════════════════════════════════════════════

/// Circular icon button with optional unread-count dot or count badge.
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



