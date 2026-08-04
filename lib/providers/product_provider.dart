import 'package:flutter/material.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';

enum SortMode {
  newest,
  priceLowToHigh,
  priceHighToLow,
  nameAZ,
  nameZA,
}

String sortModeLabel(SortMode mode) {
  switch (mode) {
    case SortMode.newest:
      return 'Newest';
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
  SortMode _sortMode = SortMode.newest;

  List<Map<String, dynamic>> get products => _products;
  bool get isLoading => _isLoading;
  String? get selectedCategory => _selectedCategory;
  SortMode get sortMode => _sortMode;

  // Fetch all categories present in the products list
  List<String> get categories {
    final Set<String> uniqueCats = {'All'};
    for (var prod in _products) {
      if (prod.containsKey('category')) {
        uniqueCats.add(prod['category']);
      }
    }
    return uniqueCats.toList();
  }

  /// Load ALL products (customer / admin screens).
  Future<void> loadProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      _products = await _db.fetchProducts();
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

  /// Returns the price value from a product map, handling both int and double.
  double _extractPrice(Map<String, dynamic> product) {
    final price = product['price'];
    if (price is int) return price.toDouble();
    if (price is double) return price;
    return 0.0;
  }

  /// Filtered + sorted products list.
  List<Map<String, dynamic>> getFilteredProducts(String searchKeyword) {
    List<Map<String, dynamic>> filtered = _products;

    // Category filter
    if (_selectedCategory != 'All' && _selectedCategory != null) {
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
      case SortMode.newest:
        sorted.sort((a, b) {
          final aTime = a['created_at']?.toString() ?? '';
          final bTime = b['created_at']?.toString() ?? '';
          return bTime.compareTo(aTime); // newest first
        });
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
    } catch (_) {
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
