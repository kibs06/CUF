import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class OrderService {
  final SupabaseService _db;
  final SupabaseClient _client;

  OrderService({SupabaseService? db, SupabaseClient? client})
    : _db = db ?? SupabaseService.instance,
      _client = client ?? Supabase.instance.client;

  Future<String> placeOrder(Map<String, dynamic> dto) async {
    final order = await _db.createOrder(dto);
    return order['id'].toString();
  }



  /// Get order IDs for a store via products → order_items chain.
  /// Optionally limit the number of IDs returned (applied at DB level).
  Future<List<dynamic>> _getOrderIdsForStore(
    String storeId, {
    String? status,
    int? limit,
  }) async {
    final productRows = await _client
        .from('products')
        .select('id')
        .eq('store_id', storeId);
    final productIds = (productRows as List)
        .map((r) => (r as Map)['id'])
        .toList();
    if (productIds.isEmpty) return [];

    final itemRows = await _client
        .from('order_items')
        .select('order_id')
        .inFilter('product_id', productIds);
    final orderIds = (itemRows as List)
        .map((r) => (r as Map)['order_id'])
        .toSet()
        .toList();
    if (orderIds.isEmpty) return [];

    // Filters → order → limit (order before limit so DB sorts first)
    var query = _client
        .from('orders')
        .select('id')
        .inFilter('id', orderIds);
    if (status != null) {
      query = query.eq('status', status);
    }
    var ordered = query.order('created_at', ascending: false);
    if (limit != null) {
      ordered = ordered.limit(limit);
    }
    final rows = await ordered;
    return (rows as List).map((r) => (r as Map)['id']).toList();
  }

  /// Fetch orders for a store, filtered server-side.
  Future<List<Map<String, dynamic>>> fetchStoreOrders(
    String storeId, {
    String? status,
  }) async {
    final orderIds = await _getOrderIdsForStore(storeId, status: status);
    if (orderIds.isEmpty) return [];

    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'created_at',
        )
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);

    final orders = (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final customerIds = orders
        .map((o) => o['customer_id'] as dynamic)
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, Map<String, dynamic>> profilesMap = {};
    if (customerIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name, email')
          .inFilter('id', customerIds);
      for (final row in profiles as List) {
        final map = Map<String, dynamic>.from(row);
        profilesMap[map['id']] = map;
      }
    }

    final itemsData = await _client
        .from('order_items')
        .select('order_id, product_id, size, quantity')
        .inFilter('order_id', orderIds);

    final productIds = itemsData
        .map((i) => (i as Map)['product_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> productNameMap = {};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name')
          .inFilter('id', productIds);
      for (final row in products as List) {
        final map = Map<String, dynamic>.from(row);
        productNameMap[map['id']] = map['name'] ?? '';
      }
    }

    final itemsByOrder = <dynamic, List<Map<String, dynamic>>>{};
    for (final item in itemsData as List) {
      final map = Map<String, dynamic>.from(item);
      final orderId = map['order_id'];
      map['product_name'] = productNameMap[map['product_id']] ?? '';
      itemsByOrder.putIfAbsent(orderId, () => []).add(map);
    }

    for (final order in orders) {
      final profile = profilesMap[order['customer_id']];
      if (profile != null) {
        order['profiles'] = profile;
      }
      final items = itemsByOrder[order['id']] ?? [];
      order['order_items'] = items;
      order['quantity'] = items.fold<int>(
        0,
        (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
      );
    }

    return orders;
  }

  /// Most recent N orders for a store with customer name and product name.
  Future<List<Map<String, dynamic>>> getRecentOrders(
    String storeId, {
    int limit = 5,
  }) async {
    final orderIds = await _getOrderIdsForStore(storeId, limit: limit);
    if (orderIds.isEmpty) return [];

    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, total_amount, status, created_at',
        )
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);

    final orders = (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final customerIds = orders
        .map((o) => o['customer_id'] as dynamic)
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> nameMap = {};
    if (customerIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', customerIds);
      for (final row in profiles as List) {
        final map = Map<String, dynamic>.from(row);
        nameMap[map['id']] = map['full_name'] ?? 'Customer';
      }
    }

    final itemsData = await _client
        .from('order_items')
        .select('order_id, product_id, quantity')
        .inFilter('order_id', orderIds);

    final productIds = itemsData
        .map((i) => (i as Map)['product_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> productNames = {};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name')
          .inFilter('id', productIds);
      for (final row in products as List) {
        final map = Map<String, dynamic>.from(row);
        productNames[map['id']] = map['name'] ?? '';
      }
    }

    Map<dynamic, String> orderProductNames = {};
    Map<dynamic, int> orderQuantities = {};
    for (final item in itemsData as List) {
      final map = Map<String, dynamic>.from(item);
      final orderId = map['order_id'];
      if (!orderProductNames.containsKey(orderId)) {
        orderProductNames[orderId] = productNames[map['product_id']] ?? '';
      }
      orderQuantities[orderId] = (orderQuantities[orderId] ?? 0) +
          ((map['quantity'] as num?)?.toInt() ?? 0);
    }

    for (final order in orders) {
      order['customer_name'] = nameMap[order['customer_id']] ?? 'Customer';
      order['product_name'] = orderProductNames[order['id']] ?? '';
      order['quantity'] = orderQuantities[order['id']] ?? 0;
    }

    return orders;
  }

  /// Count of orders grouped by status for a store.
  Future<Map<String, int>> getOrderCountByStatus(String storeId) async {
    final orderIds = await _getOrderIdsForStore(storeId);
    if (orderIds.isEmpty) return {};

    final data = await _client
        .from('orders')
        .select('id, status')
        .inFilter('id', orderIds)
        .neq('status', 'cancelled');

    final counts = <String, int>{};
    for (final row in data as List) {
      final status = row['status'] as String? ?? 'unknown';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _db.updateOrderStatus(orderId, newStatus);
  }

  /// Fetch all orders for the currently logged-in customer.
  /// Returns orders with their items (product name, size, quantity) joined.
  Future<List<Map<String, dynamic>>> fetchMyOrders() async {
    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'payment_status, created_at, store_id, '
          'order_items(id, product_id, size, quantity, unit_price, '
          'products(name, category, product_images(image_url, display_order)))',
        )
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
