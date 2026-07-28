import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../exceptions/stock_unavailable_exception.dart';
import '../services/order_service.dart';
import '../services/supabase_service.dart';

class OrderProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService.instance;

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _customizations = [];
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = false;
  String? _errorMessage;
  StockUnavailableException? _stockError;

  // ── My Orders (customer-facing) ─────────────────────────────
  final OrderService _orderService = OrderService();
  List<Map<String, dynamic>> _myOrders = [];
  List<Map<String, dynamic>> _filteredMyOrders = [];
  String _myOrdersFilter = 'all';
  bool _isLoadingMyOrders = false;
  String? _myOrdersError;

  List<Map<String, dynamic>> get orders => _orders;
  List<Map<String, dynamic>> get customizations => _customizations;
  List<Map<String, dynamic>> get profiles => _profiles;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  StockUnavailableException? get stockError => _stockError;

  List<Map<String, dynamic>> get myOrders => _filteredMyOrders;
  bool get isLoadingMyOrders => _isLoadingMyOrders;
  String? get myOrdersError => _myOrdersError;
  String get myOrdersFilter => _myOrdersFilter;

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
  // [source] indicates order origin: 'online' (default) or 'pos' (in-person).
  // POS orders skip the pending→preparing→ready pipeline and land in 'received' directly.
  Future<Map<String, dynamic>?> placeOrder({
    required String customerId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String deliveryAddress,
    required String paymentMethod,
    Map<String, dynamic>? shippingAddress,
    String source = 'online',
    double? amountTendered,
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
        if (shippingAddress != null) 'shipping_address': shippingAddress,
        'source': source,
        if (amountTendered != null) 'amount_tendered': amountTendered,
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

  // ── Order Cancellation ──────────────────────────────────────────

  /// Cancel an order or submit a cancellation request.
  ///
  /// For pending/placed orders, sets status directly to 'cancelled'.
  /// For preparing orders, sets status to 'cancellation_requested'.
  /// Stores the cancellation reason and optional details on the order record.
  Future<bool> cancelOrder({
    required dynamic orderId,
    required String newStatus,
    required String reason,
    String? details,
  }) async {
    try {
      // Store cancellation reason FIRST so that updateOrderStatus()
      // can fetch it for the push notification.
      await Supabase.instance.client
          .from('orders')
          .update({
            'cancellation_reason': reason,
            'cancellation_details': details,
            'cancelled_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      // Update the order status (triggers notification + push)
      await _db.updateOrderStatus(orderId, newStatus);

      // Reload orders to reflect changes
      await loadOrders();
      await loadMyOrders();
      return true;
    } catch (e) {
      debugPrint('OrderProvider.cancelOrder error: $e');
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

  // ── My Orders (customer-facing) ──────────────────────────────

  /// Load all orders for the current customer.
  Future<void> loadMyOrders() async {
    _isLoadingMyOrders = true;
    _myOrdersError = null;
    notifyListeners();

    try {
      _myOrders = await _orderService.fetchMyOrders();
      _applyMyOrdersFilter();
    } catch (e) {
      debugPrint('OrderProvider.loadMyOrders error: $e');
      _myOrdersError = 'Unable to load orders. Please try again.';
      _myOrders = [];
      _filteredMyOrders = [];
    }

    _isLoadingMyOrders = false;
    notifyListeners();
  }

  /// Set the active filter tab and re-filter the loaded orders.
  void setMyOrdersFilter(String filter) {
    _myOrdersFilter = filter;
    _applyMyOrdersFilter();
    notifyListeners();
  }

  void _applyMyOrdersFilter() {
    if (_myOrdersFilter == 'all') {
      _filteredMyOrders = List.from(_myOrders);
      return;
    }

    _filteredMyOrders = _myOrders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      final paymentStatus = (order['payment_status'] ?? '').toString().toLowerCase();

      switch (_myOrdersFilter) {
        case 'unpaid':
          return paymentStatus == 'unpaid' && status != 'cancelled';
        case 'processing':
          return status == 'pending' || status == 'placed' || status == 'preparing';
        case 'shipped':
          return status == 'ready';
        case 'review':
          return status == 'received';
        case 'returns':
          return status == 'cancelled';
        default:
          return true;
      }
    }).toList();
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
