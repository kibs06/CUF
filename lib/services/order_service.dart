import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'upload_service.dart';

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
  /// Order-list columns including the returns-migration columns. When the
  /// server predates those migrations, the select is retried with
  /// [_storeOrderColumnsLegacy] so the lists still load (proof display
  /// simply shows nothing) — see [_isUnknownReturnColumn].
  static const _storeOrderColumns =
      'id, customer_id, status, total_amount, payment_method, '
      'created_at, source, return_reason, return_details, '
      'return_requested_at, refunded_at, return_proof_path, '
      'return_proof_paths, return_decline_reason, '
      'replacement_method, replacement_carrier, '
      'replacement_tracking_number, replacement_shipped_at';

  static const _storeOrderColumnsLegacy =
      'id, customer_id, status, total_amount, payment_method, '
      'created_at, source';

  /// True when PostgREST is complaining about a returns-migration column
  /// the server does not have yet (mirrors AuthService.isUnknownLocationColumn).
  static bool _isUnknownReturnColumn(PostgrestException e) {
    final message = e.message.toLowerCase();
    const names = [
      'return_proof',
      'return_reason',
      'return_details',
      'return_requested',
      'return_decline',
      'refunded_at',
      'replacement_',
    ];
    if (!names.any(message.contains)) return false;
    return e.code == 'PGRST204' ||
        e.code == '42703' ||
        message.contains('schema cache') ||
        message.contains('does not exist');
  }

  /// True when PostgREST cannot find the RPC overload (server predates it).
  static bool _isUnknownFunction(PostgrestException e, String name) {
    final message = e.message.toLowerCase();
    if (!message.contains(name.toLowerCase())) return false;
    return e.code == 'PGRST202' ||
        message.contains('could not find the function');
  }

  Future<List<dynamic>> _storeOrderRows(
    List<dynamic> orderIds,
    String columns,
  ) async {
    final data = await _client
        .from('orders')
        .select(columns)
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);
    return data as List;
  }

  Future<List<Map<String, dynamic>>> fetchStoreOrders(
    String storeId, {
    String? status,
  }) async {
    final orderIds = await _getOrderIdsForStore(storeId, status: status);
    if (orderIds.isEmpty) return [];

    List<dynamic> data;
    try {
      data = await _storeOrderRows(orderIds, _storeOrderColumns);
    } on PostgrestException catch (e) {
      if (!_isUnknownReturnColumn(e)) rethrow;
      data = await _storeOrderRows(orderIds, _storeOrderColumnsLegacy);
    }

    final orders =
        data.map((row) => Map<String, dynamic>.from(row)).toList();

    final customerIds = orders
        .map((o) => o['customer_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, Map<String, dynamic>> profilesMap = {};
    if (customerIds.isNotEmpty) {
      // Use SECURITY DEFINER RPC instead of direct profiles SELECT.
      // After the profiles RLS tightening (migration 20260901010000),
      // sellers can no longer SELECT * FROM profiles for other users.
      final rpcResult = await _client
          .rpc('get_user_name_email', params: {
            'user_ids': customerIds.map((id) => id.toString()).toList(),
          });
      if (rpcResult is List) {
        for (final row in rpcResult) {
          final map = Map<String, dynamic>.from(row as Map);
          profilesMap[map['id']] = map;
        }
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

    final orders =
        data.map((row) => Map<String, dynamic>.from(row)).toList();

    final customerIds = orders
        .map((o) => o['customer_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> nameMap = {};
    if (customerIds.isNotEmpty) {
      // Use SECURITY DEFINER RPC for cross-user name lookup.
      final rpcResult = await _client
          .rpc('get_user_name_email', params: {
            'user_ids': customerIds.map((id) => id.toString()).toList(),
          });
      if (rpcResult is List) {
        for (final row in rpcResult) {
          final map = Map<String, dynamic>.from(row as Map);
          nameMap[map['id']] = map['full_name'] ?? 'Customer';
        }
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

    final orders =
        data.map((row) => Map<String, dynamic>.from(row)).toList();

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
  static const _myOrdersColumns =
      'id, customer_id, status, total_amount, payment_method, '
      'payment_status, created_at, store_id, return_reason, '
      'return_details, return_requested_at, refunded_at, '
      'return_proof_path, return_proof_paths, return_decline_reason, '
      'replacement_method, replacement_carrier, '
      'replacement_tracking_number, replacement_shipped_at, '
      'stores(name), '
      'order_items(id, product_id, size, quantity, unit_price, '
      'products(name, category, product_images(image_url, display_order)))';

  static const _myOrdersColumnsLegacy =
      'id, customer_id, status, total_amount, payment_method, '
      'payment_status, created_at, store_id, '
      'stores(name), '
      'order_items(id, product_id, size, quantity, unit_price, '
      'products(name, category, product_images(image_url, display_order)))';

  /// plus the store name for display in order cards.
  Future<List<Map<String, dynamic>>> fetchMyOrders() async {
    List<dynamic> data;
    try {
      data = await _myOrderRows(_myOrdersColumns);
    } on PostgrestException catch (e) {
      if (!_isUnknownReturnColumn(e)) rethrow;
      data = await _myOrderRows(_myOrdersColumnsLegacy);
    }

    return data
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<dynamic>> _myOrderRows(String columns) async {
    final data = await _client
        .from('orders')
        .select(columns)
        .order('created_at', ascending: false);
    return data as List;
  }

  /// Request a return for a delivered/received order via the
  /// `request_my_return` RPC (the only customer write path — orders has no
  /// customer UPDATE policy). Returns the new status.
  Future<String> requestReturn({
    required String orderId,
    required String reason,
    String? details,
    List<String>? proofPaths,
  }) async {
    final paths = proofPaths ?? const <String>[];
    try {
      return await _requestReturnRpc(
        orderId: orderId,
        reason: reason,
        details: details,
        params: {'p_proof_paths': paths},
      );
    } on PostgrestException catch (e) {
      // Server predates multi-photo support: the legacy overload takes a
      // single path. Degrade to first-photo-only rather than failing.
      if (!_isUnknownFunction(e, 'request_my_return') || paths.isEmpty) {
        rethrow;
      }
      return _requestReturnRpc(
        orderId: orderId,
        reason: reason,
        details: details,
        params: {'p_proof_path': paths.first},
      );
    }
  }

  Future<String> _requestReturnRpc({
    required String orderId,
    required String reason,
    String? details,
    required Map<String, dynamic> params,
  }) async {
    final data = await _client.rpc('request_my_return', params: {
      'p_order_id': orderId,
      'p_reason': reason,
      'p_details': details,
      ...params,
    });
    if (data is Map && data['status'] != null) {
      return data['status'].toString();
    }
    return 'return_requested';
  }

  /// Customer confirms the shipped replacement arrived.
  ///
  /// RPC rather than an UPDATE: customers have no general UPDATE policy on
  /// `orders`, and the function is what stamps `replacement_received_at`
  /// and tells the store's seller bell. Returns the new status.
  Future<String> confirmReplacementReceived({required String orderId}) async {
    final data = await _client.rpc(
      'confirm_replacement_received',
      params: {'p_order_id': orderId},
    );
    if (data is Map && data['status'] != null) {
      return data['status'].toString();
    }
    return 'replacement_received';
  }

  /// Reconcile stock for an approved replacement: the returned pair goes
  /// back on the shelf and the replacement unit comes off it, per order
  /// line (`apply_return_replacement_inventory`).
  ///
  /// Server-side and one-shot (the function stamps
  /// `orders.replacement_inventory_at`), so a retried approval cannot move
  /// stock twice. Never throws: the decision is already recorded and must
  /// not be undone by an inventory hiccup.
  Future<bool> applyReplacementInventory({required String orderId}) async {
    try {
      await _client.rpc(
        'apply_return_replacement_inventory',
        params: {'p_order_id': orderId},
      );
      return true;
    } catch (e) {
      debugPrint(
        '[OrderService] Replacement inventory not reconciled (non-fatal): $e',
      );
      return false;
    }
  }

  /// Upload a return photo proof to the PRIVATE 'return-proofs' bucket
  /// under `{order_id}/{uuid}.jpg` and return the storage PATH (not a
  /// public URL — the bucket is not public).
  Future<String> uploadReturnProof({
    required String orderId,
    required String filePath,
  }) async {
    return UploadService().uploadFile(
      bucket: 'return-proofs',
      folder: orderId,
      filePath: filePath,
      publicBucket: false,
    );
  }

  /// Upload up to 4 return photo proofs, returning their storage paths.
  Future<List<String>> uploadReturnProofs({
    required String orderId,
    required List<String> filePaths,
  }) async {
    return Future.wait(
      filePaths.map(
        (path) => uploadReturnProof(orderId: orderId, filePath: path),
      ),
    );
  }

  /// Short-lived signed URL for displaying a return proof (the bucket
  /// is private — only the order's customer and its store's seller can
  /// read these objects, enforced by storage policies).
  Future<String?> returnProofUrl(String storagePath) async {
    try {
      return await _client.storage
          .from('return-proofs')
          .createSignedUrl(storagePath, 3600);
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget FCM push to the customer after the seller approves
  /// or declines their return.
  ///
  /// The order status change itself is visible in the customer's Returns
  /// tab / tracking screen; this covers the closed/background app.
  /// Never throws — a push failure must not fail a decision that
  /// already succeeded.
  Future<void> notifyCustomerOfReturnDecision({
    required String customerId,
    required String orderId,
    required bool approved,
    String? declineReason,
  }) async {
    try {
      final shortId =
          orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
      final reason = (declineReason ?? '').trim();
      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': customerId,
        'title': approved ? 'Return approved' : 'Return declined',
        'body': approved
            ? 'Order #$shortId — replacement approved. Bring the item to the physical store for an on-the-spot swap, or wait for the shipped replacement. Tap to view.'
            : reason.isNotEmpty
                ? 'Order #$shortId — declined: $reason. Tap to view or message the store.'
                : 'Order #$shortId — the maker declined the return. Tap to view or message the store.',
        'type': 'return_decision',
        'referenceId': orderId,
        'screen': 'order_tracking',
      });
    } catch (e) {
      debugPrint('[OrderService] Return decision push failed (non-fatal): $e');
    }
  }

  /// Best-effort removal of an orphaned return proof (e.g. the return RPC
  /// rejected the request after the photo was uploaded).
  Future<void> deleteReturnProof(String storagePath) async {
    try {
      await UploadService().deleteFile('return-proofs', storagePath);
    } catch (_) {
      // Best-effort cleanup — never fail the return flow for this.
    }
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
