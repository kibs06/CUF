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
  /// Optionally filter by a single [status] or a list of [statuses],
  /// and optionally limit the number of IDs returned (applied at DB level).
  Future<List<dynamic>> _getOrderIdsForStore(
    String storeId, {
    String? status,
    List<String>? statuses,
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
    if (statuses != null) {
      query = query.inFilter('status', statuses);
    } else if (status != null) {
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
          'created_at, source',
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

  /// Most recent N pending orders for a store with customer name and
  /// product name. Only `pending`/`placed` orders are included.
  Future<List<Map<String, dynamic>>> getRecentOrders(
    String storeId, {
    int limit = 5,
  }) async {
    final orderIds = await _getOrderIdsForStore(
      storeId,
      statuses: const ['pending', 'placed'],
      limit: limit,
    );
    if (orderIds.isEmpty) return [];

    final data = await _client
        .from('orders')
        .select(
          // source is needed by SellerOrderCard to show Online vs Walk-in.
          'id, customer_id, total_amount, status, created_at, source',
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

  /// Fetch POS transaction history for a store.
  ///
  /// Returns only orders with `source='pos'` (in-person sales),
  /// scoped to the given [storeId], ordered most-recent-first.
  /// Each order includes its line items with product names.
  ///
  /// Queries orders directly by store_id + source (no 3-step chain needed)
  /// since orders.store_id is reliably set during order creation.
  Future<List<Map<String, dynamic>>> fetchPosHistory(String storeId) async {
    // Fetch POS-only orders directly (store_id + source filter)
    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'payment_status, notes, created_at, source, '
          'amount_tendered, change_amount',
        )
        .eq('store_id', storeId)
        .eq('source', 'pos')
        .order('created_at', ascending: false);

    final orders = (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (orders.isEmpty) return [];

    // 2. Fetch order items with product names and images
    final allOrderIds = orders.map((o) => o['id']).toList();
    final itemsData = await _client
        .from('order_items')
        .select('order_id, product_id, size, quantity, unit_price')
        .inFilter('order_id', allOrderIds);

    // 3. Fetch product names and images
    final productIds = itemsData
        .map((i) => (i as Map)['product_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> productNames = {};
    Map<dynamic, String> productImages = {};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name, product_images(image_url, display_order)')
          .inFilter('id', productIds);
      for (final row in products as List) {
        final map = Map<String, dynamic>.from(row);
        productNames[map['id']] = map['name'] ?? '';
        // Get first image URL
        final images = map['product_images'] as List? ?? [];
        if (images.isNotEmpty) {
          final sorted = List<Map<String, dynamic>>.from(images)
            ..sort((a, b) => ((a['display_order'] ?? 0) as int)
                .compareTo(((b['display_order'] ?? 0) as int)));
          productImages[map['id']] = sorted.first['image_url']?.toString() ?? '';
        }
      }
    }

    // 4. Group items by order and enrich with product names and images
    final itemsByOrder = <dynamic, List<Map<String, dynamic>>>{};
    for (final item in itemsData as List) {
      final map = Map<String, dynamic>.from(item);
      map['product_name'] = productNames[map['product_id']] ?? '';
      map['product_image'] = productImages[map['product_id']] ?? '';
      itemsByOrder.putIfAbsent(map['order_id'], () => []).add(map);
    }

    for (final order in orders) {
      order['order_items'] = itemsByOrder[order['id']] ?? [];
      order['items_count'] = (order['order_items'] as List)
          .fold<int>(0, (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0));
    }

    return orders;
  }

  /// Fetch all orders for the currently logged-in customer.
  /// Returns orders with their items (product name, size, quantity) joined,
  /// plus the store name for display in order cards.
  Future<List<Map<String, dynamic>>> fetchMyOrders() async {
    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'payment_status, created_at, store_id, '
          'stores(name), '
          'order_items(id, product_id, size, quantity, unit_price, '
          'products(name, category, product_images(image_url, display_order)))',
        )
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Permanently delete a cancelled order (customer-owned action).
  ///
  /// The `status = 'cancelled'` filter is a guardrail: non-cancelled orders
  /// are never deletable through this call, even if invoked programmatically.
  /// Child rows (order_items, order_status_history) cascade via
  /// `ON DELETE CASCADE` on orders.id. RLS additionally scopes the delete
  /// to `auth.uid() = customer_id`.
  Future<void> deleteOrder(String orderId) async {
    await _client
        .from('orders')
        .delete()
        .eq('id', orderId)
        .eq('status', 'cancelled');
  }
}
