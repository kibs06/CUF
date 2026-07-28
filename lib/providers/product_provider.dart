import 'package:flutter/material.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';

class ProductProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;
  String? _selectedCategory = 'All';

  List<Map<String, dynamic>> get products => _products;
  bool get isLoading => _isLoading;
  String? get selectedCategory => _selectedCategory;

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

  // Filtered products list
  List<Map<String, dynamic>> getFilteredProducts(String searchKeyword) {
    List<Map<String, dynamic>> filtered = _products;

    if (_selectedCategory != 'All' && _selectedCategory != null) {
      filtered = filtered
          .where((p) => p['category'] == _selectedCategory)
          .toList();
    }

    if (searchKeyword.isNotEmpty) {
      filtered = filtered
          .where(
            (p) => p['name'].toLowerCase().contains(
              searchKeyword.trim().toLowerCase(),
            ),
          )
          .toList();
    }

    return filtered;
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
