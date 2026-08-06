import 'package:flutter/material.dart';
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

  // Fetch all categories present in the products list.
  // An 'On Sale' pseudo-category is appended when at least one product is
  // actively on sale — it acts like a filter chip, not a real category.
  List<String> get categories {
    final Set<String> uniqueCats = {'All'};
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
    notifyListeners();

    try {
      final storeId = await ProductService.instance.getSellerStoreId();
      if (storeId == null) {
        // Seller has no store — return empty, don't leak all products
        _products = [];
      } else {
        _products = await _db.fetchProducts(storeId: storeId);
      }
    } catch (_) {
      // Gracefully handle empty
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

    // Search keyword
    if (searchKeyword.isNotEmpty) {
      filtered = filtered
          .where(
            (p) => p['name'].toLowerCase().contains(
              searchKeyword.trim().toLowerCase(),
            ),
          )
          .toList();
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

  // Add Product (UC015)
  Future<bool> addProduct(Map<String, dynamic> productData) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.addProduct(productData);
      await loadProducts();
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
      await loadProducts();
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
      await loadProducts();
      return true;
    } catch (_) {
      return false;
    }
  }
}
