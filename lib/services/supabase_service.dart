import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../exceptions/stock_unavailable_exception.dart';
import '../utils/cart_helpers.dart';
import '../utils/product_stock.dart';
import 'seller_notification_service.dart';

/// Default timeout for all Supabase network calls.
const _defaultTimeout = Duration(seconds: 15);

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// Lightweight reachability check — pings Supabase with a minimal query.
  Future<void> ping() async {
    await _client.from('profiles').select('id').limit(1)
        .timeout(_defaultTimeout);
  }

  String? _currentUserId() => _client.auth.currentUser?.id;

  String _requiredUserId() {
    final id = _currentUserId();
    if (id == null) {
      throw Exception('You must be logged in to do that.');
    }
    return id;
  }

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle()
        .timeout(_defaultTimeout);
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw Exception('Login failed. Please try again.');
    }

    final profile = await getProfile(user.id);
    if (profile == null) {
      throw Exception('Profile row not found for this account.');
    }

    return {
      'user': {'id': user.id, 'email': user.email ?? email.trim()},
      'profile': profile,
    };
  }

  Future<Map<String, dynamic>> signUp(
    String fullName,
    String email,
    String password,
    bool applyAsSeller,
  ) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName},
    );
    final user = response.user;
    if (user == null) {
      throw Exception('Sign up failed. Please try again.');
    }

    final profileData = {
      'id': user.id,
      'full_name': fullName.trim(),
      'email': email.trim(),
      'role': AppConstants.roleCustomer,
      'seller_status': applyAsSeller ? AppConstants.statusPending : 'none',
      'avatar_url': null,
      'phone': null,
    };

    await _client.from('profiles').upsert(profileData);
    final profile = await getProfile(user.id) ?? profileData;

    return {
      'user': {'id': user.id, 'email': user.email ?? email.trim()},
      'profile': profile,
    };
  }

  Future<Map<String, dynamic>> updateProfile(
    String id,
    String fullName, {
    String? phone,
    String? avatarUrl,
    String? bio,
    String? gender,
    String? birthday,
  }) async {
    final update = <String, dynamic>{
      'full_name': fullName.trim(),
      'phone': phone,
    };
    if (avatarUrl != null) update['avatar_url'] = avatarUrl;
    if (bio != null) update['bio'] = bio;
    if (gender != null) update['gender'] = gender;
    if (birthday != null) update['birthday'] = birthday;

    final data = await _client
        .from('profiles')
        .update(update)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(data);
  }

  /// Writes the foot-profile snapshot onto a profiles row and returns the
  /// refreshed row. Full scan fidelity lives in `foot_measurements`; these
  /// columns are the cheap snapshot other screens read (see migration
  /// 20260812130000_add_customer_profile_fields.sql).
  Future<Map<String, dynamic>> updateProfileFootSnapshot(
    String profileId, {
    double? sizeEu,
    String? widthLabel,
    required String source,
  }) async {
    final data = await _client
        .from('profiles')
        .update({
          'foot_size_ph': sizeEu,
          'foot_width': widthLabel,
          'foot_profile_source': source,
          'foot_profile_updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', profileId)
        .select()
        .single()
        .timeout(_defaultTimeout);
    return Map<String, dynamic>.from(data);
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<Map<String, dynamic>?> getProfileByEmail(String email) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Fetch products, optionally scoped to a specific store.
  ///
  /// When [storeId] is provided, only products belonging to that store are
  /// returned (seller/POS context). When null, all active products are
  /// returned (customer/admin context).
  ///
  /// [hideOutOfStock] removes products with zero stock on every size from
  /// the result (customer browse surfaces). It uses the `inventory`
  /// relation — the authoritative stock source for checkout — so hidden
  /// products are exactly the ones a customer cannot purchase. Sellers and
  /// admins keep the full list (default false) so they can still see and
  /// restock them; restocked products reappear automatically on the next
  /// fetch.
  Future<List<Map<String, dynamic>>> fetchProducts({
    String? storeId,
    bool hideOutOfStock = false,
  }) async {
    var query = _client
        .from('products')
        .select(
          '*, stores(name), product_images(image_url, display_order), inventory(size, stock), product_variants(size, stock, color), product_color_images(url, color_name, display_order)',
        );

    if (storeId != null) {
      query = query.eq('store_id', storeId);
    }

    final data = await query
        .order('created_at', ascending: false)
        .timeout(_defaultTimeout);

    var products = (data as List)
        .map((row) => _mapProduct(Map<String, dynamic>.from(row)))
        .toList();

    if (hideOutOfStock) {
      products = purchasableProducts(products);
    }

    return products;
  }

  /// Fetch a single product by ID in the customer-facing shape
  /// (same select + [_mapProduct] as [fetchProducts]). Used by the
  /// deep-link handler to open a shared product link.
  Future<Map<String, dynamic>?> fetchProductById(String productId) async {
    final data = await _client
        .from('products')
        .select(
          '*, stores(name), product_images(image_url, display_order), inventory(size, stock), product_variants(size, stock, color), product_color_images(url, color_name, display_order)',
        )
        .eq('id', productId)
        .maybeSingle()
        .timeout(_defaultTimeout);
    return data == null ? null : _mapProduct(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> addProduct(
    Map<String, dynamic> productData,
  ) async {
    final sellerId = _requiredUserId();
    final storeId = await _storeIdForSeller(sellerId);
    if (storeId == null) {
      throw Exception('No store is linked to this seller account.');
    }

    final inserted = await _client
        .from('products')
        .insert({
          'store_id': storeId,
          'seller_id': sellerId,
          'name': productData['name'],
          'category': productData['category'] ?? 'General',
          'price': productData['price'],
          'description': productData['description'],
          'collection': productData['collection'],
          'sku': productData['sku'],
          'is_featured': productData['is_featured'] ?? false,
          'is_published': productData['is_published'] ?? true,
          'sale_price': productData['sale_price'],
          'sale_starts_at': productData['sale_starts_at'],
          'sale_ends_at': productData['sale_ends_at'],
        })
        .select()
        .single();

    final productId = inserted['id'].toString();
    await _upsertInventory(productId, productData['sizes']);
    await _insertProductImages(productId, productData['images']);

    return _mapProduct(Map<String, dynamic>.from(inserted));
  }

  /// Update a product row and/or its relations.
  ///
  /// When [productData] contains only relation data (e.g. `sizes` for the
  /// Adjust Stock editor), the product row is left untouched and no product
  /// SELECT is issued — the returned map is then empty and should be
  /// ignored by callers.
  Future<Map<String, dynamic>> updateProduct(
    dynamic id,
    Map<String, dynamic> productData,
  ) async {
    final productId = id.toString();
    final update = <String, dynamic>{};

    for (final key in [
      'name',
      'category',
      'price',
      'description',
      'collection',
      'sku',
      'is_featured',
      'is_published',
      'sale_price',
      'sale_starts_at',
      'sale_ends_at',
    ]) {
      if (productData.containsKey(key)) {
        update[key] = productData[key];
      }
    }

    Map<String, dynamic> product = {};
    if (update.isNotEmpty) {
      final data = await _client
          .from('products')
          .update(update)
          .eq('id', productId)
          .select()
          .single();
      product = Map<String, dynamic>.from(data);
    }
    // When only relation data changed (e.g. Adjust Stock sends just
    // {'sizes': ...}), skip the pointless product SELECT — a redundant
    // round-trip that could abort the inventory write on a flaky network.

    if (productData.containsKey('sizes')) {
      await _upsertInventory(productId, productData['sizes']);
    }
    if (productData.containsKey('images')) {
      await _insertProductImages(productId, productData['images']);
    }

    return _mapProduct(product);
  }

  Future<void> deleteProduct(dynamic id) async {
    await _client
        .from('products')
        .update({'is_published': false})
        .eq('id', id.toString());
  }

  /// Fetch a single order by ID (for status summary in chat).
  Future<Map<String, dynamic>?> fetchOrderById(dynamic orderId) async {
    final data = await _client
        .from('orders')
        .select('id, status, updated_at, created_at')
        .eq('id', orderId.toString())
        .maybeSingle()
        .timeout(_defaultTimeout);
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final data = await _client
        .from('orders')
        .select(
          '*, profiles!orders_customer_id_fkey(full_name, email), order_items(*, products(name))',
        )
        .order('created_at', ascending: false)
        .timeout(_defaultTimeout);

    return (data as List)
        .map((row) => _mapOrder(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Attempt to delete an orphaned orders row (order with no items).
  /// Called when order_items insert fails after the orders row was committed.
  /// Requires the DELETE RLS policy from migration 20260704_add_orders_delete_policy.sql.
  /// If the migration hasn't been applied yet, this will silently fail (RLS blocks it).
  Future<void> _cleanupOrphanedOrder(dynamic orderId) async {
    try {
      await _client.from('orders').delete().eq('id', orderId);
      debugPrint('[ORDER-CLEANUP] Deleted orphaned order: $orderId');
    } catch (cleanupError) {
      debugPrint('[ORDER-CLEANUP] WARNING: Could not delete orphaned order $orderId (likely RLS blocked): $cleanupError');
    }
  }

  Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData,
  ) async {
    // Note: createOrder has its own internal try/catch with rollback logic,
    // so we add timeout at the individual query level below.
    final userId = _requiredUserId();
    final items = orderData['items'] as List<Map<String, dynamic>>? ?? [];
    if (items.isEmpty) throw Exception('No items to order.');

    // Determine order source: 'pos' for in-person sales, 'online' for customer orders.
    // POS orders skip the pending→preparing→ready pipeline and land in 'received' directly.
    final source = orderData['source']?.toString() ?? 'online';
    final isPos = source == 'pos';

    debugPrint('[ORDER-CREATE] Starting order creation for user: $userId, items: ${items.length}, source: $source');

    // Look up store_id from the first product
    Map<String, dynamic> productMap;
    try {
      final firstProduct = await _client
          .from('products')
          .select('id, store_id, price')
          .eq('id', items.first['product_id'].toString())
          .single();
      productMap = Map<String, dynamic>.from(firstProduct);
    } catch (e) {
      throw Exception('Product lookup failed for ${items.first['product_id']}: $e');
    }

    final method = _normalizePaymentMethod(orderData['payment_method']);
    final shippingAddress = orderData['shipping_address'];

    // STEP 1: Create the orders row (committed immediately — no transaction wrapper).
    // POS orders: status='received', payment_status='paid' (transaction is complete at checkout).
    // Online orders: status='pending', payment_status depends on method.
    Map<String, dynamic> orderMap;
    try {
      final insertData = <String, dynamic>{
        'customer_id': userId,
        'store_id': productMap['store_id'],
        'status': isPos ? 'received' : 'pending',
        'fulfillment': 'pickup',
        'total_amount': orderData['total_amount'],
        'payment_method': method,
        'payment_status': isPos ? 'paid' : (method == 'cash' ? 'unpaid' : 'paid'),
        'notes': orderData['delivery_address'],
        'source': source,
      };
      // Persist tendered/change for POS cash transactions
      if (isPos && method == 'cash') {
        final tendered = (orderData['amount_tendered'] as num?)?.toDouble();
        if (tendered != null) {
          insertData['amount_tendered'] = tendered;
          insertData['change_amount'] = (tendered - ((orderData['total_amount'] as num?)?.toDouble() ?? 0)).clamp(0, double.infinity);
        }
      }
      // Persist GCash reference number for manual verification
      final gcashRef = orderData['gcash_reference_number']?.toString();
      if (gcashRef != null && gcashRef.isNotEmpty) {
        insertData['gcash_reference_number'] = gcashRef;
      }
      if (shippingAddress != null) {
        insertData['shipping_address'] = shippingAddress;
      }
      final order = await _client
          .from('orders')
          .insert(insertData)
          .select()
          .single();
      orderMap = Map<String, dynamic>.from(order);
      debugPrint('[ORDER-CREATE] Orders row inserted: id=${orderMap["id"]}');
    } catch (e) {
      throw Exception('Order insert failed: $e');
    }

    // Batch-fetch all inventory rows for every product in this order
    // in a single query (eliminates N+1 per-item queries).
    final productIds = items
        .map((item) => item['product_id'].toString())
        .toSet()
        .toList();
    final Map<String, List<Map<String, dynamic>>> invByProduct = {};
    if (productIds.isNotEmpty) {
      final allInvRows = await _client
          .from('inventory')
          .select('product_id, size, stock')
          .inFilter('product_id', productIds)
          .gt('stock', 0);
      for (final row in (allInvRows as List)) {
        final pid = row['product_id'].toString();
        invByProduct.putIfAbsent(pid, () => []).add({
          'size': row['size']?.toString() ?? '',
          'stock': (row['stock'] as num?)?.toInt() ?? 0,
        });
      }
    }

    // STEP 2: Insert order_items rows (separate calls — NOT atomic with step 1).
    // If ANY order_items insert fails, we delete the orphaned orders row
    // and surface the real error to the caller.
    final orderId = orderMap['id'];
    final insertedItemIds = <dynamic>[]; // track what we inserted for rollback
    Map<String, dynamic>? failingItem; // track which item caused the failure
    try {
      for (final item in items) {
        // Resolve size using the shared helper (exact → normalized match)
        final cartSize = (item['size']?.toString().isNotEmpty ?? false)
            ? item['size'].toString()
            : '';
        final productId = item['product_id'].toString();
        final invRows = invByProduct[productId] ?? [];
        final resolved = resolveInventoryStock(
          inventoryRows: invRows,
          productId: productId,
          cartSize: cartSize,
          productName: item['product_name']?.toString() ?? 'Product',
        );
        // Use the inventory-matched size if found; fall back to cartSize
        // for backwards compat during the cart_items.size migration period.
        String size = resolved >= 0 ? invRows.firstWhere(
          (r) => normalizeSize(r['size']?.toString() ?? '') == normalizeSize(cartSize),
          orElse: () => {'size': cartSize},
        )['size']!.toString() : cartSize;

        final payload = {
          'order_id': orderId,
          'product_id': productId,
          'size': size,
          'quantity': item['quantity'] ?? 1,
          'unit_price': item['unit_price'] ?? 0,
        };
        debugPrint('[ORDER-CREATE] Inserting order_item: $payload');

        try {
          final result = await _client.from('order_items').insert(payload).select('id').single();
          insertedItemIds.add(result['id']);
          debugPrint('[ORDER-CREATE] order_item inserted: id=${result["id"]}');
        } catch (e) {
          failingItem = item; // remember which item failed
          debugPrint('[ORDER-CREATE] order_item INSERT FAILED: $e');
          if (e is PostgrestException) {
            debugPrint('[ORDER-CREATE] PostgrestException details:');
            debugPrint('  code: ${e.code}');
            debugPrint('  message: ${e.message}');
            debugPrint('  details: ${e.details}');
            debugPrint('  hint: ${e.hint}');
          }
          // Re-throw — will be caught by the outer handler below
          rethrow;
        }
      }
    } catch (e) {
      // order_items insert failed — clean up the orphaned orders row
      debugPrint('[ORDER-CREATE] ═══ ROLLING BACK: order_items failed, deleting orphaned order $orderId ═══');
      await _cleanupOrphanedOrder(orderId);

      // Also delete any order_items that were successfully inserted before the failure
      if (insertedItemIds.isNotEmpty) {
        try {
          await _client.from('order_items').delete().inFilter('id', insertedItemIds);
        } catch (_) {}
      }

      // Surface the REAL error — not a generic stock message
      if (e is PostgrestException &&
          e.code == 'P0001' &&
          e.message.toLowerCase().contains('insufficient stock')) {
        // DB trigger rejected the insert due to stock check —
        // reference the ACTUAL failing item, not items.first
        final fi = failingItem ?? items.first;
        throw StockUnavailableException(
          productName: fi['product_name']?.toString() ?? 'Product',
          size: fi['size']?.toString() ?? '',
          requestedQty: (fi['quantity'] as num?)?.toInt() ?? 1,
        );
      }
      // All other errors: surface the real Postgres error message
      if (e is PostgrestException) {
        throw Exception('Order failed: ${e.message} (code: ${e.code})');
      }
      rethrow;
    }

    debugPrint('[ORDER-CREATE] Order created successfully: id=$orderId, items=${items.length}, source=$source');

    // ── Status history for POS orders ──────────────────────────────
    // POS orders are inserted directly with status='received' (terminal),
    // so the trg_record_order_status_change trigger (AFTER UPDATE) never fires.
    // Write the initial history row explicitly so POS orders have an audit trail.
    if (isPos) {
      final orderIdInt = int.tryParse(orderId.toString());
      if (orderIdInt != null) {
        try {
          await _client.from('order_status_history').insert({
            'order_id': orderIdInt,
            'status': 'received',
            'changed_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint('[ORDER-CREATE] Could not write POS status history: $e');
        }
      }
    }

    // ── Notification: new_order ────────────────────────────────────
    // Fire-and-forget: notify the seller that a new order was placed.
    final storeId = productMap['store_id']?.toString();
    final totalAmount = (orderData['total_amount'] as num?)?.toDouble() ?? 0.0;
    if (storeId != null) {
      SellerNotificationService.instance.createNewOrder(
        storeId: storeId,
        orderId: orderId.toString(),
        totalAmount: totalAmount,
      ); // intentionally not awaited — don't block order creation
    }

    // ── Push: unpaid ──────────────────────────────────────────────
    // Fire-and-forget: push to the customer about their new order.
    final shortId = orderId.toString().length >= 8
        ? orderId.toString().substring(0, 8)
        : orderId.toString();
    _triggerCustomerPush(
      recipientUserId: userId,
      type: 'unpaid',
      title: 'Order placed',
      body: 'Order #$shortId is awaiting payment',
      referenceId: orderId.toString(),
      screen: 'order_tracking',
    );

    return _mapOrder({
      ...orderMap,
      'order_items': items
          .map((item) => {
                'product_id': item['product_id'],
                'size': item['size'] ?? '',
                'quantity': item['quantity'] ?? 1,
                'unit_price': item['unit_price'] ?? 0,
              })
          .toList(),
    });
  }

  Future<Map<String, dynamic>> updateOrderStatus(
    dynamic orderId,
    String newStatus,
  ) async {
    final dbStatus = _mapUiStatusToDb(newStatus);
    final data = await _client
        .from('orders')
        .update({'status': dbStatus})
        .eq('id', orderId.toString())
        .select()
        .single()
        .timeout(_defaultTimeout);
    final mapped = _mapOrder(Map<String, dynamic>.from(data));

    // ── Write order_status_history row ──────────────────────────
    // order_status_history.order_id is BIGINT, so parse from string.
    final orderIdInt = int.tryParse(orderId.toString());
    if (orderIdInt != null) {
      try {
        await _client.from('order_status_history').insert({
          'order_id': orderIdInt,
          'status': dbStatus,
          'changed_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[ORDER-STATUS] Could not write status history: $e');
      }
    }

    // ── DB notification + push for customer ────────────────────
    final customerId = data['customer_id']?.toString();
    if (customerId != null) {
      final shortId = orderId.toString().length >= 8
          ? orderId.toString().substring(0, 8)
          : orderId.toString();
      if (dbStatus == 'delivered') {
        _createCustomerNotification(
          userId: customerId,
          category: 'review',
          title: 'Order delivered',
          body: 'Order #$shortId has arrived. Tap to confirm receipt.',
          orderId: orderId.toString(),
        );
      } else if (dbStatus == 'received') {
        _createCustomerNotification(
          userId: customerId,
          category: 'review',
          title: 'Order received',
          body: 'Order #$shortId was confirmed. Tap to rate your purchase.',
          orderId: orderId.toString(),
        );
      }
      switch (dbStatus) {
        case 'preparing':
          _triggerCustomerPush(
            recipientUserId: customerId,
            type: 'processing',
            title: 'Order update',
            body: 'Order #$shortId is being prepared',
            referenceId: orderId.toString(),
            screen: 'order_tracking',
          );
          break;
        case 'ready':
          _triggerCustomerPush(
            recipientUserId: customerId,
            type: 'shipped',
            title: 'Order shipped',
            body: 'Order #$shortId is ready',
            referenceId: orderId.toString(),
            screen: 'order_tracking',
          );
          break;
        case 'received':
          _triggerCustomerPush(
            recipientUserId: customerId,
            type: 'review',
            title: 'How was it?',
            body: 'Order #$shortId was delivered — leave a review',
            referenceId: orderId.toString(),
            screen: 'order_tracking',
          );
          break;
        case 'cancelled':
          // Fetch the cancellation reason from the order row
          final orderRow = await _client
              .from('orders')
              .select('cancellation_reason')
              .eq('id', orderId.toString())
              .maybeSingle()
              .timeout(_defaultTimeout);
          final reason = orderRow?['cancellation_reason']?.toString();
          final reasonText = (reason != null && reason.isNotEmpty)
              ? ' Reason: $reason'
              : '';
          _createCustomerNotification(
            userId: customerId,
            category: 'returns',
            title: 'Order cancelled',
            body: 'Order #$shortId has been cancelled.$reasonText',
            orderId: orderId.toString(),
          );
          _triggerCustomerPush(
            recipientUserId: customerId,
            type: 'returns',
            title: 'Order cancelled',
            body: 'Order #$shortId has been cancelled.$reasonText',
            referenceId: orderId.toString(),
            screen: 'order_tracking',
          );
          break;
      }
    }

    return mapped;
  }

  /// Maps UI-facing status labels to the DB-level values that the
  /// orders_status_check constraint allows.
  String _mapUiStatusToDb(String status) {
    // Maps seller UI labels → DB-legal values.
    // 'delivered' now maps to itself (Part D: customer must confirm → 'received').
    switch (status.toLowerCase()) {
      case 'confirmed':
        return 'preparing';
      default:
        // 'pending', 'placed', 'ready', 'delivered', 'received', 'cancelled'
        // all pass through unchanged — they're already DB-legal.
        return status.toLowerCase();
    }
  }

  // ─── DB NOTIFICATION HELPER ──────────────────────────────────

  /// Insert a row into the `notifications` table (customer-facing).
  /// Fire-and-forget — failures are caught and logged.
  void _createCustomerNotification({
    required String userId,
    required String category,
    required String title,
    required String body,
    String? orderId,
  }) {
    try {
      _client.from('notifications').insert({
        'user_id': userId,
        'category': category,
        'title': title,
        'message': body,
        'order_id': orderId,
        'is_read': false,
        'is_deleted': false,
      }).catchError((e) {
        debugPrint('[SupabaseService] Customer notification insert failed: $e');
      });
    } catch (e) {
      debugPrint('[SupabaseService] Customer notification insert failed: $e');
    }
  }

  // ─── PUSH NOTIFICATION HELPERS ─────────────────────────────────

  /// Fire-and-forget push to a customer device via the send-notification-push
  /// edge function. Failures are caught and logged, never propagated.
  void _triggerCustomerPush({
    required String recipientUserId,
    required String type,
    required String title,
    required String body,
    String? referenceId,
    String? screen,
  }) {
    try {
      _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': recipientUserId,
        'title': title,
        'body': body,
        'type': type,
        'referenceId': ?referenceId,
        'screen': ?screen,
      }).catchError((e) {
        debugPrint('[SupabaseService] Customer push trigger failed: $e');
        return FunctionResponse(status: 500);
      });
    } catch (e) {
      debugPrint('[SupabaseService] Customer push trigger failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomizations() async {
    final data = await _client
        .from('customization_requests')
        .select()
        .order('created_at', ascending: false)
        .timeout(_defaultTimeout);
    return (data as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      return {
        'id': map['id'],
        'customer_id': map['customer_id'],
        'base_name': map['base_product_id'] ?? 'Custom Shoe',
        'color': map['color_choice'] ?? '',
        'material': map['material_choice'] ?? '',
        'special_request': map['special_request'] ?? '',
        'status': map['status'],
        'created_at': map['created_at'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> createCustomization(
    Map<String, dynamic> data,
  ) async {
    final userId = _requiredUserId();
    final storeId = await _firstActiveStoreId();
    if (storeId == null) {
      throw Exception('No active store is available for customization.');
    }
    final inserted = await _client
        .from('customization_requests')
        .insert({
          'customer_id': userId,
          'store_id': storeId,
          'color_choice': data['color'],
          'material_choice': data['material'],
          'special_request': data['special_request'],
          'status': 'pending',
        })
        .select()
        .single()
        .timeout(_defaultTimeout);
    final result = Map<String, dynamic>.from(inserted);

    // ── Notification: custom_order_request ──────────────────────────
    // Fire-and-forget: notify the seller about a new custom order request.
    // storeId is guaranteed non-null (checked + thrown above).
    final customerName = await _client
        .from('profiles')
        .select('full_name')
        .eq('id', userId)
        .maybeSingle()
        .then<String>((p) => p?['full_name']?.toString() ?? 'Customer');
    SellerNotificationService.instance.createCustomOrderRequest(
      storeId: storeId,
      requestId: result['id'].toString(),
      customerName: customerName,
    ); // intentionally not awaited

    return result;
  }

  Future<List<Map<String, dynamic>>> fetchProfiles() async {
    final data = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false)
        .timeout(_defaultTimeout);
    return (data as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> updateProfileRole(String userId, String newRole) async {
    await _client.from('profiles').update({'role': newRole}).eq('id', userId);
  }

  Future<void> approveSellerApplication(String userId) async {
    await _client
        .from('profiles')
        .update({
          'seller_status': AppConstants.statusApproved,
          'role': AppConstants.roleSeller,
        })
        .eq('id', userId);
  }

  Future<void> rejectSellerApplication(String userId) async {
    await _client
        .from('profiles')
        .update({'seller_status': AppConstants.statusRejected})
        .eq('id', userId);
  }

  /// Permanently deletes a user (profile + auth account + owned stores).
  ///
  /// Runs the admin-only SECURITY DEFINER RPC `admin_delete_user` (migration
  /// 20260817120000_admin_delete_user.sql) — the anon-key client cannot
  /// delete auth.users rows directly, so the privilege check happens inside
  /// the function. Throws if the caller is not an admin.
  Future<void> deleteUserPermanently(String userId) async {
    await _client.rpc('admin_delete_user', params: {'target_user_id': userId});
  }

  Future<void> _upsertInventory(dynamic productId, dynamic sizes) async {
    if (sizes == null) return;
    final sizesMap = Map<String, dynamic>.from(sizes as Map);
    final rows = sizesMap.entries
        .map(
          (entry) => {
            'product_id': productId.toString(),
            'size': entry.key,
            'stock': entry.value is int
                ? entry.value
                : int.tryParse('${entry.value}') ?? 0,
          },
        )
        .toList();
    if (rows.isNotEmpty) {
      try {
        // onConflict must name the composite (product_id, size) key: the
        // live `inventory` table guards it with a UNIQUE constraint (not
        // the primary key), so without it PostgREST tries to INSERT every
        // restock and dies with code 23505 on inventory_product_id_size_key.
        await _client
            .from('inventory')
            .upsert(rows, onConflict: 'product_id,size');
      } catch (e) {
        debugPrint(
            '[SupabaseService] inventory upsert FAILED for $productId: $e');
        rethrow;
      }
      // Keep product_variants.stock in sync with the authoritative inventory
      // rows. Without this, the Adjust Stock editor (which writes only
      // `inventory`) drifts from `product_variants` — and the next product
      // save would regenerate inventory FROM variants, silently wiping the
      // seller's stock adjustments.
      await _syncVariantStock(productId.toString(), rows);
    }
  }

  /// Distribute inventory totals (size → stock) onto the matching
  /// `product_variants` rows so the two tables never drift.
  ///
  /// Variants may have multiple rows per size (one per color). The delta
  /// between the current variant total and the new inventory total is
  /// applied row-by-row (each row clamped at 0) until fully absorbed.
  Future<void> _syncVariantStock(
    String productId,
    List<Map<String, dynamic>> inventoryRows,
  ) async {
    List<dynamic> variants;
    try {
      variants = await _client
          .from('product_variants')
          .select('id, size, stock')
          .eq('product_id', productId);
    } catch (e) {
      // Best-effort: the inventory write (authoritative for checkout) has
      // already succeeded — a variant sync hiccup must never fail it.
      debugPrint('[SupabaseService] variant stock sync failed: $e');
      return;
    }
    if (variants.isEmpty) return;

    final bySize = <String, List<Map<String, dynamic>>>{};
    for (final v in variants) {
      final row = Map<String, dynamic>.from(v);
      bySize.putIfAbsent(row['size'].toString(), () => []).add(row);
    }

    for (final inv in inventoryRows) {
      final size = inv['size'].toString();
      final target = (inv['stock'] as num?)?.toInt() ?? 0;
      final sizeVariants = bySize[size];
      if (sizeVariants == null || sizeVariants.isEmpty) continue;

      final currentStocks = sizeVariants
          .map((v) => (v['stock'] as num?)?.toInt() ?? 0)
          .toList();
      final newStocks = distributeVariantStock(currentStocks, target);

      for (var i = 0; i < sizeVariants.length; i++) {
        if (newStocks[i] == currentStocks[i]) continue;
        try {
          await _client
              .from('product_variants')
              .update({'stock': newStocks[i]})
              .eq('id', sizeVariants[i]['id']);
        } catch (e) {
          // Best-effort: one row's failure shouldn't abort the rest. The
          // inventory write (authoritative for checkout) already succeeded.
          debugPrint('[SupabaseService] variant stock sync failed: $e');
        }
      }
    }
  }

  Future<void> _insertProductImages(dynamic productId, dynamic images) async {
    if (images is! List || images.isEmpty) return;
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < images.length; i++) {
      final imageUrl = images[i]?.toString();
      if (imageUrl == null || imageUrl.isEmpty) continue;
      rows.add({
        'product_id': productId.toString(),
        'image_url': imageUrl,
        'display_order': i,
      });
    }
    if (rows.isNotEmpty) {
      await _client.from('product_images').insert(rows);
    }
  }

  Future<String?> _storeIdForSeller(String sellerId) async {
    final store = await _client
        .from('stores')
        .select('id')
        .eq('owner_id', sellerId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
    return store?['id']?.toString();
  }

  Future<String?> _firstActiveStoreId() async {
    final store = await _client
        .from('stores')
        .select('id')
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
    return store?['id']?.toString();
  }

  Map<String, dynamic> _mapProduct(Map<String, dynamic> row) {
    final images = row['product_images'] is List
        ? List<Map<String, dynamic>>.from(
            (row['product_images'] as List).map(
              (image) => Map<String, dynamic>.from(image),
            ),
          )
        : <Map<String, dynamic>>[];
    images.sort(
      (a, b) => ((a['display_order'] ?? 0) as int).compareTo(
        (b['display_order'] ?? 0) as int,
      ),
    );

    final inventory = row['inventory'] is List
        ? row['inventory'] as List
        : <dynamic>[];
    final sizes = <String, int>{};
    for (final item in inventory) {
      final map = Map<String, dynamic>.from(item as Map);
      sizes[map['size'].toString()] = (map['stock'] as num?)?.toInt() ?? 0;
    }

    return {
      ...row,
      'id': row['id']?.toString(),
      'price': (row['price'] as num?)?.toDouble() ?? 0.0,
      'sale_price': (row['sale_price'] as num?)?.toDouble(),
      'images': images.map((image) => image['image_url'].toString()).toList(),
      'sizes': sizes,
      'store_name': row['stores'] is Map ? row['stores']['name'] : null,
    };
  }

  Map<String, dynamic> _mapOrder(Map<String, dynamic> row) {
    final items = row['order_items'] is List ? row['order_items'] as List : [];
    final firstItem = items.isNotEmpty
        ? Map<String, dynamic>.from(items.first as Map)
        : <String, dynamic>{};

    final profile = row['profiles'] is Map
        ? Map<String, dynamic>.from(row['profiles'] as Map)
        : null;

    return {
      ...row,
      'id': row['id']?.toString(),
      'product_id': firstItem['product_id']?.toString(),
      'size': firstItem['size'] ?? '',
      'quantity': (firstItem['quantity'] as num?)?.toInt() ?? 1,
      'total_amount': (row['total_amount'] as num?)?.toDouble() ?? 0.0,
      'payment_method': row['payment_method'] ?? '',
      'delivery_address': row['notes'] ?? '',
      'amount_tendered': row['amount_tendered'],
      'change_amount': row['change_amount'],
      'profiles': profile,
      'items_count': items.fold<int>(
        0,
        (sum, item) =>
            sum +
            ((item is Map ? item['quantity'] as num? : null)?.toInt() ?? 0),
      ),
    };
  }

  String _normalizePaymentMethod(dynamic method) {
    final value = method?.toString().toLowerCase() ?? 'cash';
    if (value.contains('gcash')) return 'gcash';
    if (value.contains('card')) return 'card';
    return 'cash';
  }

  // ── Account Deletion ──────────────────────────────────────────

  /// Submit an account deletion request via Edge Function.
  /// Returns a map with `success` (bool) and `message` (String).
  Future<Map<String, dynamic>> requestAccountDeletion({String? reason}) async {
    final res = await _client.functions.invoke(
      'request-account-deletion',
      body: {'reason': reason},
    );
    if (res.data is Map<String, dynamic>) {
      return res.data as Map<String, dynamic>;
    }
    return {'success': false, 'message': 'Unexpected response'};
  }
}
