# Store Screen Source Code

> Raw source for the three key files behind the Store tab carousel and product listing.

---

## `lib/screens/store/store_screen.dart`

```dart
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
              separatorBuilder: (_, _) => const SizedBox(width: 12),
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
```

---

## `lib/screens/store/widgets/cross_store_product_row.dart`

```dart
import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../../utils/product_grid_ratio.dart';
import '../../customer/product_detail_screen.dart';
import '../../../widgets/sole_product_card.dart';

/// "Top Picks from a store" section.
/// Shows products from a single store in a 2-column layout using Wrap.
/// No shrinkWrap overhead — cards are laid out naturally.
class CrossStoreProductRow extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final String storeName;

  const CrossStoreProductRow({
    super.key,
    required this.products,
    this.storeName = 'all stores',
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Top Picks',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'from $storeName',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withAlpha(127),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2-column grid using Wrap — no shrinkWrap, no height estimation.
        // Each child takes ~50% width minus spacing.
        LayoutBuilder(
          builder: (context, constraints) {
            final spacing = 14.0;
            final cardWidth = (constraints.maxWidth - spacing) / 2;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: products.map((product) {
                return SizedBox(
                  width: cardWidth,
                  child: SoleProductCard(
                    product: product,
                    imageAspectRatio: productGridRatio(product),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: product),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
```

---

## `lib/providers/product_provider.dart`

```dart
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';
import '../utils/sale_price.dart';

enum SortMode {
  /// Default browse order — the catalog is shuffled once per
  /// `loadProducts()` call, so this mode shows the shuffled "fresh feed"
  /// rather than a chronological order. Explicit sorts below fully override it.
  featured,
  priceLowToHigh,
  priceHighToLow,
  nameAZ,
  nameZA,
}

String sortModeLabel(SortMode mode) {
  switch (mode) {
    case SortMode.featured:
      return 'Featured';
    case SortMode.priceLowToHigh:
      return 'Price: Low to High';
    case SortMode.priceHighToLow:
      return 'Price: High to Low';
    case SortMode.nameAZ:
      return 'Name: A to Z';
    case SortMode.nameZA:
      return 'Name: Z to A';
  }
}

class ProductProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;
  String? _selectedCategory = 'All';
  SortMode _sortMode = SortMode.featured;

  List<Map<String, dynamic>> get products => _products;
  bool get isLoading => _isLoading;
  String? get selectedCategory => _selectedCategory;
  SortMode get sortMode => _sortMode;

  // Fetch all categories present in the products list, UNIONed with the
  // canonical [AppConstants.productCategories] (the same presets the seller
  // product form offers), so chips like Boots/Sneakers/Slip-ons are always
  // filterable even before any product uses them. Any category actually on a
  // product that isn't canonical (legacy values, custom entries) still shows
  // up, so nothing already filterable disappears. 'All' stays first and the
  // 'On Sale' pseudo-category is appended last when at least one product is
  // actively on sale — it acts like a filter chip, not a real category.
  List<String> get categories {
    final Set<String> uniqueCats = {'All'};
    uniqueCats.addAll(AppConstants.productCategories);
    for (var prod in _products) {
      if (prod.containsKey('category')) {
        uniqueCats.add(prod['category']);
      }
    }
    if (_products.any(isOnSale)) {
      uniqueCats.add('On Sale');
    }
    return uniqueCats.toList();
  }

  /// Load ALL products (customer / admin screens).
  ///
  /// The fetched list is shuffled once right after the fetch so the default
  /// browse order (SortMode.featured) looks fresh each time — a "new
  /// products" feel without any backend change. Filtering and explicit sort
  /// modes still operate on this shuffled base list, so search/category/sort
  /// behavior is unaffected.
  ///
  /// [reshuffle] defaults to true: every load (including pull-to-refresh)
  /// produces a new order. Set to false if a caller wants to preserve the
  /// current session's shuffled order.
  ///
  /// [hideOutOfStock] removes products with no stock on any size — used by
  /// customer browse screens so out-of-stock items disappear from the
  /// catalog and reappear automatically once a seller restocks them.
  /// Sellers and admins keep the full list (default false).
  Future<void> loadProducts({
    bool reshuffle = true,
    bool hideOutOfStock = false,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _products = await _db.fetchProducts(hideOutOfStock: hideOutOfStock);
      if (reshuffle) {
        _products.shuffle();
      }
    } catch (_) {
      // Gracefully handle empty
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load only the current seller's products (POS / seller screens).
  ///
  /// Fetches the seller's store ID via [ProductService] and passes it to
  /// [SupabaseService.fetchProducts] so the query is server-side scoped.
  ///
  /// If the seller has no store yet, returns an empty list instead of
  /// silently fetching all sellers' products.
  Future<void> loadSellerProducts() async {
    _isLoading = true;
    // Clear any previously loaded catalog FIRST so a slow or failed seller
    // fetch can never flash or keep another store's products. The provider
    // is an app-root singleton shared across roles — a prior customer-browse
    // `loadProducts()` may have left the full catalog in memory, and the old
    // silent catch would have kept showing it if this fetch threw.
    _products = [];
    notifyListeners();

    try {
      final storeId = await ProductService.instance.getSellerStoreId();
      if (storeId == null) {
        // Seller has no store — keep empty, don't leak all products.
        // MUST clear the loading flag here (no fall-through past the try).
        _isLoading = false;
        notifyListeners();
        return;
      }
      final fetched = await _db.fetchProducts(storeId: storeId);
      // Defense in depth: even if the query ever drifted, only keep products
      // that actually belong to this seller's store. Other sellers' products
      // can never appear (their store_id differs). Products in this store
      // with a NULL seller_id (e.g. admin-seeded) stay visible; rows tagged
      // with a DIFFERENT seller are dropped as not owned.
      final mySellerId = _db.currentUser?.id;
      _products = fetched.where((p) {
        final belongsToStore = p['store_id']?.toString() == storeId;
        if (!belongsToStore) return false;
        if (mySellerId == null) return true; // no user context — store only
        final ownerId = p['seller_id']?.toString();
        return ownerId == null || ownerId == mySellerId;
      }).toList();
    } catch (e) {
      // A failed seller fetch must NEVER leave another store's products on
      // screen — the list was already cleared above.
      debugPrint('[ProductProvider] loadSellerProducts failed: $e');
      _products = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Set the sort mode and rebuild the UI.
  void setSortMode(SortMode mode) {
    _sortMode = mode;
    notifyListeners();
  }

  /// Returns the EFFECTIVE price (sale-aware) from a product map.
  ///
  /// Delegates to the shared [isOnSale]/[effectivePrice] helpers so the
  /// active-sale rule stays in one place (sale_price.dart). This single
  /// change makes price sorting correct under active sales.
  double _extractPrice(Map<String, dynamic> product) => effectivePrice(product);

  /// Whether a product is currently on sale (delegates to the shared helper).
  bool isProductOnSale(Map<String, dynamic> product) => isOnSale(product);

  /// The price the customer pays right now (delegates to the shared helper).
  double productEffectivePrice(Map<String, dynamic> product) =>
      effectivePrice(product);

  /// Filtered + sorted products list.
  List<Map<String, dynamic>> getFilteredProducts(String searchKeyword) {
    List<Map<String, dynamic>> filtered = _products;

    // Category filter — 'On Sale' is a pseudo-category that filters by the
    // active-sale rule instead of the product's category field. If the sale
    // expired mid-session while 'On Sale' is selected, gracefully fall back
    // to the full list instead of showing a confusing empty state.
    final bool saleFilterActive =
        _selectedCategory == 'On Sale' && _products.any(isOnSale);
    if (saleFilterActive) {
      filtered = filtered.where((p) => isOnSale(p)).toList();
    } else if (_selectedCategory != 'All' && _selectedCategory != null) {
      filtered = filtered
          .where((p) => p['category'] == _selectedCategory)
          .toList();
    }

    // Search keyword — matches the product NAME or any of its TAGS.
    // The name keeps its exact-substring behavior; tags additionally match
    // per-word, so a multi-word query like "handmade leather" finds
    // products tagged with any of those words.
    if (searchKeyword.isNotEmpty) {
      final query = searchKeyword.trim().toLowerCase();
      final words = query
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      filtered = filtered.where((p) {
        final name = (p['name'] ?? '').toString().toLowerCase();
        if (name.contains(query)) return true;
        // Tag match: any whitespace-separated word of the query as a
        // substring of any tag (covers single-word "leather" and
        // multi-word "handmade leather" queries alike).
        final tags = p['tags'];
        if (tags is List) {
          for (final tag in tags) {
            final tagText = tag.toString().toLowerCase();
            if (words.any((w) => tagText.contains(w))) return true;
          }
        }
        return false;
      }).toList();
    }

    // Sort
    final sorted = List<Map<String, dynamic>>.from(filtered);
    switch (_sortMode) {
      // Featured = the shuffled order from loadProducts(); no-op here so the
      // session's shuffle is preserved (never re-sorted per keystroke).
      case SortMode.featured:
        break;
      case SortMode.priceLowToHigh:
        sorted.sort((a, b) => _extractPrice(a).compareTo(_extractPrice(b)));
      case SortMode.priceHighToLow:
        sorted.sort((a, b) => _extractPrice(b).compareTo(_extractPrice(a)));
      case SortMode.nameAZ:
        sorted.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
      case SortMode.nameZA:
        sorted.sort((a, b) => (b['name'] ?? '').toString().compareTo((a['name'] ?? '').toString()));
    }

    return sorted;
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  /// Reload the product list after a write, scoped to the current user's
  /// role.
  ///
  /// The provider is an app-root singleton shared across roles. A seller's
  /// write (add / update / Adjust Stock) must NOT reload the full catalog:
  /// `loadProducts()` fetches every store's products, and the POS/dashboard
  /// render from this same provider — so after a stock adjustment the seller
  /// would suddenly see products that don't belong to them. If the current
  /// user owns a store, reload seller-scoped; otherwise (customer/admin
  /// browsing context) fall back to the full catalog.
  ///
  /// Best-effort: errors are swallowed so a reload hiccup can never flip a
  /// successful DB write into a reported failure — and on failure the
  /// in-memory list simply stays as it was (already seller-scoped for
  /// sellers, so nothing leaks).
  Future<void> _reloadAfterWrite() async {
    try {
      final storeId = await ProductService.instance.getSellerStoreId();
      if (storeId != null) {
        await loadSellerProducts();
      } else {
        await loadProducts();
      }
    } catch (e) {
      debugPrint('[ProductProvider] post-write reload failed: $e');
    }
  }

  // Add Product (UC015)
  Future<bool> addProduct(Map<String, dynamic> productData) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.addProduct(productData);
      await _reloadAfterWrite();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update Product (UC015)
  Future<bool> updateProduct(
    dynamic id,
    Map<String, dynamic> productData,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.updateProduct(id, productData);
      await _reloadAfterWrite();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Log the real reason (e.g. PostgrestException code/message) so a
      // failed write is never a silent dead end during debugging.
      debugPrint('[ProductProvider] updateProduct failed for $id: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Delete Product (UC015)
  Future<bool> deleteProduct(dynamic id) async {
    try {
      await _db.deleteProduct(id);
      await _reloadAfterWrite();
      return true;
    } catch (_) {
      return false;
    }
  }
}
```
