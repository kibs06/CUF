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

  /// Whether the customer's orders have been fetched at least once.
  /// Lets the Profile "My Orders" panel trigger a single load so its
  /// badge counts are populated without re-fetching on every build.
  bool _myOrdersLoaded = false;

  /// The auth user whose orders are currently cached. When the signed-in
  /// user changes (or signs out), the cached orders are cleared so stale
  /// counts are never shown to the next account.
  String? _myOrdersUserId;

  OrderProvider() {
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final uid = state.session?.user.id;
      if (uid != _myOrdersUserId) {
        _myOrdersUserId = uid;
        _myOrders = [];
        _filteredMyOrders = [];
        _myOrdersLoaded = false;
        _myOrdersError = null;
        notifyListeners();
      }
    });
  }

  List<Map<String, dynamic>> get orders => _orders;
  List<Map<String, dynamic>> get customizations => _customizations;
  List<Map<String, dynamic>> get profiles => _profiles;

  /// Directly sets a profile's role in the local cache and notifies
  /// listeners (admin console local-only role assignment).
  void setProfileRole(String userId, String role) {
    final index = _profiles.indexWhere((p) => p['id'] == userId);
    if (index != -1) {
      _profiles[index]['role'] = role;
      notifyListeners();
    }
  }
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  StockUnavailableException? get stockError => _stockError;

  List<Map<String, dynamic>> get myOrders => _filteredMyOrders;
  bool get isLoadingMyOrders => _isLoadingMyOrders;
  String? get myOrdersError => _myOrdersError;
  String get myOrdersFilter => _myOrdersFilter;
  bool get hasLoadedMyOrders => _myOrdersLoaded;

  /// Counts of the customer's orders per My Orders tab, computed from the
  /// same in-memory orders (and the same [matchesMyOrdersFilter] predicates)
  /// as the tab lists themselves — so the Profile "My Orders" panel badges
  /// always match what each tab shows.
  Map<String, int> get myOrdersCounts =>
      Map.unmodifiable(computeMyOrdersCounts(_myOrders));

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
    String? gcashReference,
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
        'shipping_address': ?shippingAddress,
        'source': source,
        'amount_tendered': ?amountTendered,
        'gcash_reference_number': ?gcashReference,
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
      _myOrdersLoaded = true;
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
    _filteredMyOrders = _myOrders
        .where((order) => matchesMyOrdersFilter(order, _myOrdersFilter))
        .toList();
  }

  // ── Delete cancelled order ────────────────────────────────────

  /// Optimistically remove a cancelled order from the local list.
  /// Returns the deleted order data so it can be restored if the user undoes.
  Map<String, dynamic>? deleteOrder(dynamic orderId) {
    final index = _orders.indexWhere((o) => o['id'] == orderId);
    if (index == -1) return null;
    final orderData = Map<String, dynamic>.from(_orders[index]);
    _orders.removeAt(index);
    notifyListeners();
    return orderData;
  }

  /// Restore a previously deleted order back into the local list.
  void restoreOrder(Map<String, dynamic> orderData) {
    _orders.insert(0, orderData);
    notifyListeners();
  }

  /// Permanently delete a cancelled order from the database.
  Future<void> permanentlyDeleteOrder(dynamic orderId) async {
    await Supabase.instance.client
        .from('orders')
        .delete()
        .eq('id', orderId);
  }

  // ── My Orders: swipe-to-delete (Returns tab) ───────────────────

  /// Optimistically remove one of the customer's orders from both the raw
  /// and filtered lists. Returns the removed entry (with its original
  /// positions) so it can be restored if the user taps Undo.
  DeletedMyOrder? deleteMyOrder(dynamic orderId) {
    final filteredIndex =
        _filteredMyOrders.indexWhere((o) => o['id'] == orderId);
    if (filteredIndex == -1) return null;

    final rawIndex = _myOrders.indexWhere((o) => o['id'] == orderId);
    final data = Map<String, dynamic>.from(_filteredMyOrders[filteredIndex]);
    _filteredMyOrders.removeAt(filteredIndex);
    if (rawIndex != -1) _myOrders.removeAt(rawIndex);
    notifyListeners();
    return DeletedMyOrder(
      data: data,
      index: filteredIndex,
      rawIndex: rawIndex,
    );
  }

  /// Reinsert a previously removed order at its original positions.
  /// Called from the Undo action before any database delete has run.
  void restoreMyOrder(DeletedMyOrder deleted) {
    _filteredMyOrders.insert(
      deleted.index.clamp(0, _filteredMyOrders.length),
      Map<String, dynamic>.from(deleted.data),
    );
    if (deleted.rawIndex != -1) {
      _myOrders.insert(
        deleted.rawIndex.clamp(0, _myOrders.length),
        Map<String, dynamic>.from(deleted.data),
      );
    }
    notifyListeners();
  }

  /// Commit the permanent delete against Supabase. Only called after the
  /// undo window expires. On failure, reinserts the order locally so the
  /// UI never silently loses data, and returns false.
  Future<bool> permanentlyDeleteMyOrder(DeletedMyOrder deleted) async {
    try {
      await _orderService.deleteOrder(deleted.data['id'].toString());
      return true;
    } catch (e) {
      debugPrint('OrderProvider.permanentlyDeleteMyOrder error: $e');
      restoreMyOrder(deleted);
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
      // Fire-and-forget: email the applicant the good news (the in-app
      // notification is written by the DB trigger). Failure to send must
      // never fail the approval itself.
      _triggerApprovalEmail(userId, outcome: 'approved');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectSeller(String userId, {String? reason}) async {
    try {
      await _db.rejectSellerApplication(userId);
      await loadProfiles();
      // Fire-and-forget: email the applicant about the decision. Failure to
      // send must never fail the rejection itself.
      _triggerApprovalEmail(userId, outcome: 'rejected', reason: reason);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fire-and-forget invoke of the `send-approval-email` edge function.
  /// Errors are caught and logged — never propagated to the caller.
  void _triggerApprovalEmail(
    String userId, {
    required String outcome,
    String? reason,
  }) {
    try {
      Supabase.instance.client.functions
          .invoke('send-approval-email', body: {
        'userId': userId,
        'outcome': outcome,
        if (reason != null && reason.isNotEmpty) 'rejectionReason': reason,
      }).catchError((e) {
        debugPrint('[OrderProvider] Approval email trigger failed: $e');
        return FunctionResponse(status: 500);
      });
    } catch (e) {
      debugPrint('[OrderProvider] Approval email trigger failed: $e');
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

  /// Permanently deletes a user (profile + auth account + owned stores)
  /// via the admin-only `admin_delete_user` RPC. Refreshes the list after.
  Future<bool> deleteUserPermanently(String userId) async {
    try {
      await _db.deleteUserPermanently(userId);
      await loadProfiles();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// The My Orders tab filter keys, in display order.
const List<String> myOrdersFilterKeys = [
  'all',
  'unpaid',
  'processing',
  'shipped',
  'review',
  'returns',
];

/// Whether [order] belongs in the given My Orders tab ([filter]).
///
/// Single source of truth shared by the tab list filtering
/// (`OrderProvider._applyMyOrdersFilter`) and the per-tab badge counts
/// (`computeMyOrdersCounts`), so the Profile "My Orders" panel badges can
/// never drift from the actual tab lists. Status/payment_status are matched
/// case-insensitively, mirroring the legacy behavior.
bool matchesMyOrdersFilter(Map<String, dynamic> order, String filter) {
  final status = (order['status'] ?? '').toString().toLowerCase();
  final paymentStatus =
      (order['payment_status'] ?? '').toString().toLowerCase();

  switch (filter) {
    case 'unpaid':
      return paymentStatus == 'unpaid' && status != 'cancelled';
    case 'processing':
      return status == 'pending' ||
          status == 'placed' ||
          status == 'preparing';
    case 'shipped':
      return status == 'ready';
    case 'review':
      return status == 'received';
    case 'returns':
      return status == 'cancelled';
    default:
      // 'all' (and any unknown key) matches every order.
      return true;
  }
}

/// Per-tab counts for a raw customer order list, keyed by [myOrdersFilterKeys].
///
/// Note that statuses with no tab home (`delivered`, `cancellation_requested`)
/// are only counted under `all`.
Map<String, int> computeMyOrdersCounts(List<Map<String, dynamic>> orders) {
  final counts = <String, int>{
    for (final key in myOrdersFilterKeys) key: 0,
  };
  for (final order in orders) {
    for (final key in myOrdersFilterKeys) {
      if (matchesMyOrdersFilter(order, key)) {
        counts[key] = counts[key]! + 1;
      }
    }
  }
  return counts;
}

/// A customer order removed optimistically from the My Orders lists,
/// together with its original positions so Undo can restore it exactly.
class DeletedMyOrder {
  final Map<String, dynamic> data;

  /// Position in the filtered My Orders list at removal time.
  final int index;

  /// Position in the unfiltered list, or -1 if not present there.
  final int rawIndex;

  const DeletedMyOrder({
    required this.data,
    required this.index,
    required this.rawIndex,
  });
}
