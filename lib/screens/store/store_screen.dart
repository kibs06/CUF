import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../models/store.dart';
import '../../providers/product_provider.dart';
import '../../services/store_service.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/shimmer_group.dart';
import 'widgets/store_hero_carousel.dart';
import 'widgets/store_focused_info.dart';
import 'widgets/cross_store_product_row.dart';

/// Multi-store discovery tab — the "walking through a market" experience.
/// Hero carousel → focused info → cross-store products.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final StoreService _storeService = StoreService.instance;
  late PageController _pageController;

  List<Store> _stores = [];
  int _focusedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _loadStores();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    final stores = await _storeService.fetchAllStores();
    if (mounted) {
      setState(() {
        _stores = stores;
        _isLoading = false;
      });
    }
  }

  void _onStoreChanged(int index) {
    setState(() {
      _focusedIndex = index;
    });
  }

  /// Build product count map from all products.
  Map<String, int> _buildProductCounts(List<Map<String, dynamic>> products) {
    final counts = <String, int>{};
    for (final p in products) {
      final storeId = p['store_id'] as String? ?? '';
      counts[storeId] = (counts[storeId] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final allProducts = productProvider.products;
    final productCounts = _buildProductCounts(allProducts);

    // Top picks: newest products from the focused store only
    final focusedStoreId = _stores.isNotEmpty
        ? _stores[_focusedIndex].id
        : '';
    final topPicks = allProducts
        .where((p) => p['store_id']?.toString() == focusedStoreId)
        .toList()
      ..sort((a, b) => '${b['id']}'.compareTo('${a['id']}'));
    final topPicksLimited = topPicks.length > 12
        ? topPicks.sublist(0, 12)
        : topPicks;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Stores', style: AppConstants.headlineStyle(fontSize: 22)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: const [CartIconButton()],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _isLoading
              ? const _StoreScreenSkeleton()
              : _stores.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: 56,
                        color: AppConstants.primary.withAlpha(100),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No stores available yet.',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.secondary.withAlpha(153),
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Section 1 — Hero Store Carousel
                      StoreHeroCarousel(
                        stores: _stores,
                        pageController: _pageController,
                        onStoreChanged: _onStoreChanged,
                        currentIndex: _focusedIndex,
                        productCounts: productCounts,
                      ),

                      // Section 2 — Focused Store Info Strip
                      StoreFocusedInfo(
                        store: _stores[_focusedIndex],
                        productCount:
                            productCounts[_stores[_focusedIndex].id] ?? 0,
                      ),

                      // Section 3 — Top Picks from focused store
                      CrossStoreProductRow(
                        products: topPicksLimited,
                        storeName: _stores[_focusedIndex].name,
                      ),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Skeleton loading state — mirrors hero carousel + focused info + rows
// ═══════════════════════════════════════════════════════════════════

class _StoreScreenSkeleton extends StatelessWidget {
  const _StoreScreenSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ShimmerGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Hero carousel card
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SkeletonBox(
              width: double.infinity,
              height: 260,
              borderRadius: 24,
            ),
          ),
          const SizedBox(height: 20),

          // Focused store info strip
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SkeletonBox(width: 200, height: 16),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SkeletonBox(width: 120, height: 12),
          ),
          const SizedBox(height: 24),

          // Section header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SkeletonBox(width: 140, height: 18),
          ),
          const SizedBox(height: 12),

          // Cross-store product row
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => const _CrossStoreCardSkeleton(),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _CrossStoreCardSkeleton extends StatelessWidget {
  const _CrossStoreCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 150, height: 110, borderRadius: 12),
          SizedBox(height: 8),
          SkeletonBox(width: 120, height: 12),
          SizedBox(height: 6),
          SkeletonBox(width: 80, height: 12),
        ],
      ),
    );
  }
}

