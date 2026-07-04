import 'package:flutter/material.dart';
import '../exceptions/stock_unavailable_exception.dart';
import '../services/supabase_service.dart';

class OrderProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _customizations = [];
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = false;
  String? _errorMessage;
  StockUnavailableException? _stockError;

  List<Map<String, dynamic>> get orders => _orders;
  List<Map<String, dynamic>> get customizations => _customizations;
  List<Map<String, dynamic>> get profiles => _profiles;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  StockUnavailableException? get stockError => _stockError;

  // Load Orders (UC019, UC023, UC025)
  Future<void> loadOrders() async {
    _isLoading = true;
    notifyListeners();

    try {
      _orders = await _db.fetchOrders();
      // Sort: newest first
      _orders.sort((a, b) => b['id'].compareTo(a['id']));
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  // Place Order (UC013, UC014)
  // [items] is a list of maps, each with: product_id, size, color, quantity, unit_price
  Future<Map<String, dynamic>?> placeOrder({
    required String customerId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String deliveryAddress,
    required String paymentMethod,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _errorMessage = null; // clear previous error
      _stockError = null;
      final order = await _db.createOrder({
        'customer_id': customerId,
        'items': items,
        'total_amount': totalAmount,
        'delivery_address': deliveryAddress,
        'payment_method': paymentMethod,
      });
      await loadOrders();
      _isLoading = false;
      notifyListeners();
      return order;
    } on StockUnavailableException catch (e) {
      debugPrint('OrderProvider.placeOrder stock error: $e');
      _errorMessage = e.friendlyMessage;
      _stockError = e;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('OrderProvider.placeOrder error: $e');
      _errorMessage = 'Something went wrong placing your order. Please try again.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // Update Status (UC019, UC025)
  Future<bool> updateOrderStatus(dynamic orderId, String newStatus) async {
    try {
      await _db.updateOrderStatus(orderId, newStatus);
      await loadOrders();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Load Customizations (UC010, UC011)
  Future<void> loadCustomizations() async {
    _isLoading = true;
    notifyListeners();

    try {
      _customizations = await _db.fetchCustomizations();
      _customizations.sort(
        (a, b) => b['created_at'].compareTo(a['created_at']),
      );
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  // Submit Customization (UC010, UC011)
  Future<bool> submitCustomization({
    required String customerId,
    required String baseName,
    required String color,
    required String material,
    required String specialRequest,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.createCustomization({
        'customer_id': customerId,
        'base_name': baseName,
        'color': color,
        'material': material,
        'special_request': specialRequest,
      });
      await loadCustomizations();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // --- ADMIN ACTIONS (UC004, UC005) ---
  Future<void> loadProfiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      _profiles = await _db.fetchProfiles();
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> approveSeller(String userId) async {
    try {
      await _db.approveSellerApplication(userId);
      await loadProfiles();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectSeller(String userId) async {
    try {
      await _db.rejectSellerApplication(userId);
      await loadProfiles();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deactivateUser(String userId) async {
    try {
      await _db.updateProfileRole(userId, 'customer');
      await loadProfiles();
      return true;
    } catch (_) {
      return false;
    }
  }
}
