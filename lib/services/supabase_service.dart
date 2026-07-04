import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../exceptions/stock_unavailable_exception.dart';
import '../utils/cart_helpers.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

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
        .maybeSingle();
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
  }) async {
    final update = <String, dynamic>{
      'full_name': fullName.trim(),
      'phone': phone,
    };
    if (avatarUrl != null) update['avatar_url'] = avatarUrl;

    final data = await _client
        .from('profiles')
        .update(update)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(data);
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<List<Map<String, dynamic>>> fetchProducts() async {
    final data = await _client
        .from('products')
        .select(
          '*, stores(name), product_images(image_url, display_order), inventory(size, stock), product_variants(size, stock)',
        )
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => _mapProduct(Map<String, dynamic>.from(row)))
        .toList();
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
        })
        .select()
        .single();

    final productId = inserted['id'].toString();
    await _upsertInventory(productId, productData['sizes']);
    await _insertProductImages(productId, productData['images']);

    return _mapProduct(Map<String, dynamic>.from(inserted));
  }

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
    } else {
      final data = await _client
          .from('products')
          .select()
          .eq('id', productId)
          .single();
      product = Map<String, dynamic>.from(data);
    }

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

  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final data = await _client
        .from('orders')
        .select(
          '*, profiles!orders_customer_id_fkey(full_name, email), order_items(*, products(name))',
        )
        .order('created_at', ascending: false);

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
    final userId = _requiredUserId();
    final items = orderData['items'] as List<Map<String, dynamic>>? ?? [];
    if (items.isEmpty) throw Exception('No items to order.');

    debugPrint('[ORDER-CREATE] Starting order creation for user: $userId, items: ${items.length}');

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

    // STEP 1: Create the orders row (committed immediately — no transaction wrapper).
    Map<String, dynamic> orderMap;
    try {
      final order = await _client
          .from('orders')
          .insert({
            'customer_id': userId,
            'store_id': productMap['store_id'],
            'status': 'pending',
            'fulfillment': 'pickup',
            'total_amount': orderData['total_amount'],
            'payment_method': method,
            'payment_status': method == 'cash' ? 'unpaid' : 'paid',
            'notes': orderData['delivery_address'],
          })
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

    debugPrint('[ORDER-CREATE] Order created successfully: id=$orderId, items=${items.length}');
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
    final data = await _client
        .from('orders')
        .update({'status': newStatus.toLowerCase()})
        .eq('id', orderId.toString())
        .select()
        .single();
    return _mapOrder(Map<String, dynamic>.from(data));
  }

  Future<List<Map<String, dynamic>>> fetchCustomizations() async {
    final data = await _client
        .from('customization_requests')
        .select()
        .order('created_at', ascending: false);
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
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<List<Map<String, dynamic>>> fetchProfiles() async {
    final data = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
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
      await _client.from('inventory').upsert(rows);
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
}
