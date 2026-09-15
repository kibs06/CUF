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

  /// Highest average product rating first (trigger-maintained
  /// `avg_rating` on products). Ties break toward more reviews.
  topRated,

  /// Most units sold first (aggregated from paid, non-cancelled orders).
  bestSelling,
}

/// Label of the 'Best Sellers' pseudo-category — a *filter* (like the
/// 'On Sale' pseudo-category), not a [SortMode]. See
/// [ProductProvider.categories] / [ProductProvider.getFilteredProducts].
const String kBestSellersCategory = 'Best Sellers';

/// How many products the 'Best Sellers' filter/rail keeps.
///
/// A best-seller set has to be curated: "has sold at least one unit" alone
/// would return most of an established catalog and leave the chip pointless.
/// Top-N of the live `units_sold` aggregation is the rule; catalogs smaller
/// than [kBestSellerLimit] simply return every product that has sold.
const int kBestSellerLimit = 20;

/// Units sold for [product] per the [unitsSold] aggregation (absent = 0).
int unitsSoldOf(Map<String, dynamic> product, Map<String, int> unitsSold) =>
    unitsSold[product['id']?.toString() ?? ''] ?? 0;

/// The 'Best Sellers' set, derived live from the loaded catalog and the
/// `units_sold` aggregation. Single source of truth for BOTH the home rail and
/// the 'Best Sellers' filter, so the rail can never show a product the chip
/// excludes (or vice versa).
///
/// Rules:
/// - only products that have actually sold (units_sold > 0) — a brand-new
///   catalog yields an empty set, and the chip/rail hide themselves;
/// - most-sold first, so the rail and the filtered catalog agree on order;
/// - capped at [limit];
/// - ties break on rating then name, because the catalog list itself is
///   reshuffled per load and an unstable sort would reshuffle the rail too.
List<Map<String, dynamic>> bestSellerProducts(
  List<Map<String, dynamic>> products,
  Map<String, int> unitsSold, {
  int limit = kBestSellerLimit,
}) {
  final ranked = products
      .where((p) => unitsSoldOf(p, unitsSold) > 0)
      .toList()
    ..sort((a, b) {
      final byUnits =
          unitsSoldOf(b, unitsSold).compareTo(unitsSoldOf(a, unitsSold));
      if (byUnits != 0) return byUnits;
      final rA = (a['avg_rating'] as num?)?.toDouble() ?? 0;
      final rB = (b['avg_rating'] as num?)?.toDouble() ?? 0;
      final byRating = rB.compareTo(rA);
      if (byRating != 0) return byRating;
      return (a['name'] ?? '')
          .toString()
          .compareTo((b['name'] ?? '').toString());
    });
  return limit > 0 && ranked.length > limit
      ? ranked.sublist(0, limit)
      : ranked;
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
    case SortMode.topRated:
      return 'Top Rated';
    case SortMode.bestSelling:
      return 'Best Selling';
  }
}

class ProductProvider extends ChangeNotifier {
  final SupabaseService _db;

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;
  String? _selectedCategory = 'All';
  SortMode _sortMode = SortMode.featured;

  /// product_id → total units sold across paid, non-cancelled orders.
  /// Loaded alongside the catalog; missing id = 0 units.
  Map<String, int> _unitsSold = const {};

  ProductProvider() : _db = SupabaseService.instance;

  /// Test seam: a provider seeded with a catalog + sold-count aggregation and
  /// no network access. Mirrors exactly what [loadProducts] leaves in memory
  /// (see [_stampUnitsSold]) so filtering/sorting can be asserted directly.
  @visibleForTesting
  ProductProvider.seeded({
    List<Map<String, dynamic>> products = const [],
    Map<String, int> unitsSold = const {},
  }) : _db = SupabaseService.instance {
    _products = products.map(Map<String, dynamic>.from).toList();
    _unitsSold = Map<String, int>.from(unitsSold);
    _stampUnitsSold();
  }

  /// Copy [units_sold] onto each product map so widgets that render products
  /// directly (product cards) can display it without reaching back into the
  /// provider.
  void _stampUnitsSold() {
    for (final p in _products) {
      p['units_sold'] = _unitsSold[p['id']?.toString()] ?? 0;
    }
  }

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
  // pseudo-categories are appended last, each only when it can actually offer
  // something: 'On Sale' when a product is actively on sale, 'Best Sellers'
  // when a product has sold at least one unit. Both act like filter chips, not
  // real categories — a dead-end chip is never rendered.
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
    if (hasBestSellers) {
      uniqueCats.add(kBestSellersCategory);
    }
    return uniqueCats.toList();
  }

  /// The live best-seller set — most-sold first, never-sold excluded.
  ///
  /// Derived on every read from [_products] + [_unitsSold], so it always
  /// reflects the current aggregation rather than a stale cached snapshot.
  List<Map<String, dynamic>> get bestSellers =>
      bestSellerProducts(_products, _unitsSold);

  /// Whether the catalog holds any best seller at all — gates whether the
  /// 'Best Sellers' chip and the home rail are rendered.
  bool get hasBestSellers =>
      _products.any((p) => unitsSoldOf(p, _unitsSold) > 0);

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
      // Fetch the catalog and the units-sold aggregation in parallel —
      // the sold counts power the Best Selling sort mode.
      final results = await Future.wait([
        _db.fetchProducts(hideOutOfStock: hideOutOfStock),
        _db.fetchUnitsSold().catchError((_) => <String, int>{}),
      ]);
      _products = results[0] as List<Map<String, dynamic>>;
      _unitsSold = results[1] as Map<String, int>;
      _stampUnitsSold();
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

  /// Total units sold for a product (paid, non-cancelled orders).
  /// Returns 0 for products never sold or not in the last aggregation.
  int unitsSoldFor(String productId) => _unitsSold[productId] ?? 0;

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

    // Category filter — 'On Sale' and 'Best Sellers' are pseudo-categories
    // that filter by a derived rule (active sale / live units sold) instead of
    // the product's category field, and they behave identically to one
    // another. Each rule is only applied while it currently yields something:
    // its chip is hidden the moment it doesn't, so the branch below is only
    // reachable if the data changed under a selected chip (sale expired, a
    // reload dropped the units-sold aggregation). That state degrades exactly
    // like a category with no matching products — the empty state, whose
    // "browse all" action clears the selection.
    final bool saleFilterActive =
        _selectedCategory == 'On Sale' && _products.any(isOnSale);
    final bool bestSellerFilterActive =
        _selectedCategory == kBestSellersCategory && hasBestSellers;
    if (saleFilterActive) {
      filtered = filtered.where((p) => isOnSale(p)).toList();
    } else if (bestSellerFilterActive) {
      final bestSellerIds =
          bestSellers.map((p) => p['id']?.toString()).toSet();
      filtered = filtered
          .where((p) => bestSellerIds.contains(p['id']?.toString()))
          .toList();
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
      case SortMode.topRated:
        sorted.sort((a, b) {
          final rA = (a['avg_rating'] as num?)?.toDouble() ?? 0;
          final rB = (b['avg_rating'] as num?)?.toDouble() ?? 0;
          // Higher rating first; ties break toward more reviews so a
          // 5.0 from one review doesn't beat 4.8 from forty.
          final c = rB.compareTo(rA);
          if (c != 0) return c;
          final nA = (a['review_count'] as num?)?.toInt() ?? 0;
          final nB = (b['review_count'] as num?)?.toInt() ?? 0;
          return nB.compareTo(nA);
        });
      case SortMode.bestSelling:
        sorted.sort((a, b) {
          final idA = a['id']?.toString() ?? '';
          final idB = b['id']?.toString() ?? '';
          final uA = _unitsSold[idA] ?? 0;
          final uB = _unitsSold[idB] ?? 0;
          return uB.compareTo(uA);
        });
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
