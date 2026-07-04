import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item_with_details.dart';
import '../utils/cart_helpers.dart';

/// Service handling all cart-related Supabase operations.
///
/// Follows the singleton pattern used by [ProductService].
/// Screens/providers should call this service — never Supabase directly.
class CartService {
  CartService._();
  static final CartService instance = CartService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── READ ───────────────────────────────────────────────────────

  /// Fetch the user's full cart with joined product and variant data.
  ///
  /// Returns a list of [CartItemWithDetails] objects containing everything
  /// the UI needs: product name, image, price, size, color, stock, store info.
  Future<List<CartItemWithDetails>> fetchCart(String userId) async {
    final data = await _client
        .from('cart_items')
        .select('''
          *,
          products!inner(
            name, is_active, price, store_id,
            product_images(image_url, display_order)
          ),
          product_variants(
            id, size, color, stock, additional_price
          )
        ''')
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    // Batch-fetch store names for all unique store_ids
    final storeIds = <String>{};
    for (final row in data as List) {
      final product = row['products'] as Map<String, dynamic>?;
      final storeId = product?['store_id']?.toString();
      if (storeId != null) storeIds.add(storeId);
    }

    final storeNames = <String, String>{};
    if (storeIds.isNotEmpty) {
      final stores = await _client
          .from('stores')
          .select('id, name')
          .inFilter('id', storeIds.toList());
      for (final store in stores as List) {
        storeNames[store['id'].toString()] =
            store['name']?.toString() ?? 'Unknown Store';
      }
    }

    // Collect product IDs that need inventory fallback (no variant matched)
    final fallbackProductIds = <String>{};
    for (final row in data as List) {
      if (row['product_variants'] == null) {
        fallbackProductIds.add(row['product_id'].toString());
      }
    }

    // Batch-fetch inventory stock for products without variants
    final inventoryStock = <String, int>{}; // {productId-size: stock}
    final inventorySizes = <String, String>{}; // {productId: first size}
    if (fallbackProductIds.isNotEmpty) {
      final invRows = await _client
          .from('inventory')
          .select('product_id, size, stock')
          .inFilter('product_id', fallbackProductIds.toList())
          .gt('stock', 0);
      for (final inv in invRows as List) {
        final pid = inv['product_id'].toString();
        final size = inv['size']?.toString() ?? '';
        final stock = (inv['stock'] as num?)?.toInt() ?? 0;
        final key = '$pid-$size';
        inventoryStock[key] = (inventoryStock[key] ?? 0) + stock;
        if (!inventorySizes.containsKey(pid) && size.isNotEmpty) {
          inventorySizes[pid] = size;
        }
      }
    }

    return (data as List).map((row) {
      final product = row['products'] as Map<String, dynamic>;
      final variant = row['product_variants'] as Map<String, dynamic>?;

      // Extract first image URL sorted by display_order
      final productImages = product['product_images'] as List? ?? [];
      final sortedImages = List<Map<String, dynamic>>.from(productImages)
        ..sort((a, b) => (a['display_order'] as int? ?? 0)
            .compareTo(b['display_order'] as int? ?? 0));
      final imageUrl =
          sortedImages.isNotEmpty ? sortedImages.first['image_url']?.toString() : null;

      final storeId = product['store_id']?.toString();
      final productId = row['product_id'] as String;

      // Resolve size: prefer cart_items.size (authoritative), then variant, then inventory fallback
      final String? rawCartSize = row['size']?.toString();
      String size = (rawCartSize != null && rawCartSize.isNotEmpty)
          ? rawCartSize
          : (variant?['size']?.toString() ?? '');
      if (size.isEmpty && inventorySizes.containsKey(productId)) {
        size = inventorySizes[productId]!;
      }

      // Resolve stock: prefer variant, fall back to inventory
      int stock = (variant?['stock'] as num?)?.toInt() ?? 0;
      if (stock <= 0 && size.isNotEmpty) {
        stock = inventoryStock['$productId-$size'] ?? 0;
      }

      return CartItemWithDetails(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        productId: productId,
        variantId: row['variant_id'] as String?,
        quantity: (row['quantity'] as num?)?.toInt() ?? 1,
        customizations: row['customizations'] as Map<String, dynamic>?,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
        productName: product['name']?.toString() ?? 'Unknown Product',
        imageUrl: imageUrl,
        isActive: product['is_active'] as bool? ?? true,
        storeId: storeId,
        storeName: storeNames[storeId] ?? 'Unknown Store',
        price: (product['price'] as num?)?.toDouble() ?? 0,
        size: size,
        color: variant?['color']?.toString(),
        stock: stock,
        additionalPrice: (variant?['additional_price'] as num?)?.toDouble() ?? 0,
        cartSize: rawCartSize,
      );
    }).toList();
  }

  // ─── CREATE / UPDATE ────────────────────────────────────────────

  /// Add or increment a cart item for the given user.
  ///
  /// If a row with matching (user_id, product_id, variant_id) already exists,
  /// its quantity is incremented by [quantity]. Otherwise a new row is inserted.
  /// Returns the Supabase row ID of the cart item.
  Future<String> addOrUpdateItem({
    required String userId,
    required String productId,
    String? variantId,
    required int quantity,
    Map<String, dynamic>? customizations,
    String? size,
  }) async {
    // Manual lookup instead of relying on upsert, because NULL in unique
    // constraint columns (variant_id, customizations) breaks PostgreSQL
    // dedup (NULL != NULL).
    final query = _client
        .from('cart_items')
        .select('id, quantity')
        .eq('user_id', userId)
        .eq('product_id', productId);

    final filtered = variantId != null
        ? await query.eq('variant_id', variantId).maybeSingle()
        : await query.isFilter('variant_id', null).maybeSingle();

    if (filtered != null) {
      // Row exists — increment quantity, update size if provided
      final update = <String, dynamic>{'quantity': (filtered['quantity'] as int) + quantity};
      if (size != null) update['size'] = size;
      await _client
          .from('cart_items')
          .update(update)
          .eq('id', filtered['id'] as String);
      return filtered['id'] as String;
    } else {
      // Insert new row (size column populated on every insert)
      final result = await _client
          .from('cart_items')
          .insert({
            'user_id': userId,
            'product_id': productId,
            'variant_id': variantId,
            'quantity': quantity,
            'customizations': customizations,
            'size': size,
          })
          .select('id')
          .single();
      return result['id'] as String;
    }
  }

  /// Set the absolute quantity for a cart item.
  ///
  /// If [newQuantity] ≤ 0 the row is deleted instead of stored at 0.
  Future<void> updateQuantity({
    required String cartItemId,
    required int newQuantity,
  }) async {
    if (newQuantity <= 0) {
      await _client.from('cart_items').delete().eq('id', cartItemId);
    } else {
      await _client
          .from('cart_items')
          .update({'quantity': newQuantity})
          .eq('id', cartItemId);
    }
  }

  /// Remove a single cart item by its Supabase row ID.
  Future<void> removeItem(String cartItemId) async {
    await _client.from('cart_items').delete().eq('id', cartItemId);
  }

  /// Remove all cart items for a user. Called after a successful order.
  Future<void> clearCart(String userId) async {
    await _client.from('cart_items').delete().eq('user_id', userId);
  }

  /// Remove specific cart items by their Supabase row IDs.
  /// Called after a successful order to clear only the ordered items,
  /// leaving unselected items (e.g. from other stores) intact.
  Future<void> removeItems(String userId, List<String> cartItemIds) async {
    if (cartItemIds.isEmpty) return;
    await _client
        .from('cart_items')
        .delete()
        .eq('user_id', userId)
        .inFilter('id', cartItemIds);
  }

  // ─── CHECKOUT VALIDATION ────────────────────────────────────────

  /// Re-fetch live price + stock for every cart line item.
  ///
  /// Returns per-item validation results so the checkout screen can show
  /// "price changed" or "out of stock" banners before the customer confirms.
  /// Does NOT mutate the cart.
  ///
  /// PHASE 1 (instrumentation): Logs every value being compared.
  /// PHASE 2 (hard fix): Uses `resolveInventoryStock()` from cart_helpers
  ///   which does exact + normalized match with NO fallback to first-available.
  ///   If no match is found, stock = -1 → item marked unavailable.
  Future<List<CartValidationResult>> validateCartForCheckout(
    String userId,
    Map<String, Map<String, dynamic>> currentCartItems,
  ) async {
    debugPrint('[CHECKOUT-VALIDATE] ═══ Starting validation for user: $userId ═══');
    debugPrint('[CHECKOUT-VALIDATE] Local cart items: ${currentCartItems.length}');

    final serverItems = await fetchCart(userId);
    debugPrint('[CHECKOUT-VALIDATE] Server cart items: ${serverItems.length}');

    // Batch-fetch ALL inventory rows for all products (no stock>0 filter —
    // we need to see zero-stock rows too for accurate logging).
    final productIds = serverItems
        .map((item) => item.productId)
        .toSet()
        .toList();
    final Map<String, List<Map<String, dynamic>>> invByProduct = {};
    if (productIds.isNotEmpty) {
      final allInvRows = await _client
          .from('inventory')
          .select('product_id, size, stock')
          .inFilter('product_id', productIds);
      for (final row in (allInvRows as List)) {
        final pid = row['product_id'].toString();
        invByProduct.putIfAbsent(pid, () => []).add({
          'size': row['size']?.toString() ?? '',
          'stock': (row['stock'] as num?)?.toInt() ?? 0,
        });
      }
      debugPrint('[CHECKOUT-VALIDATE] Inventory rows fetched: ${allInvRows.length} for ${productIds.length} products');
    } else {
      debugPrint('[CHECKOUT-VALIDATE] ⚠️ No products found in cart');
    }

    final results = <CartValidationResult>[];
    for (final serverItem in serverItems) {
      // Find the matching item in the current cart to compare prices
      final cartKey = '${serverItem.productId}-${serverItem.size}-${serverItem.color ?? 'none'}';
      final cartItem = currentCartItems[cartKey];
      final cartPrice = (cartItem?['price'] as double?) ?? serverItem.unitPrice;
      final cartQty = (cartItem?['quantity'] as int?) ?? 1;

      // PHASE 2: Use the shared helper for inventory resolution.
      // The helper logs every step — this is the Phase 1 instrumentation.
      final invRows = invByProduct[serverItem.productId] ?? [];
      final resolved = resolveInventoryStock(
        inventoryRows: invRows,
        productId: serverItem.productId,
        cartSize: serverItem.cartSize ?? serverItem.size,
        productName: serverItem.productName,
      );

      // -1 means no match found → treat as out of stock
      final stock = resolved >= 0 ? resolved : 0;
      final isAvailable = serverItem.isActive && stock > 0;

      debugPrint('[CHECKOUT-VALIDATE] → ${serverItem.productName}: stock=$stock, isActive=${serverItem.isActive}, isAvailable=$isAvailable, qty=$cartQty, insufficient=${cartQty > stock}');

      results.add(CartValidationResult(
        cartItemId: serverItem.id,
        productId: serverItem.productId,
        productName: serverItem.productName,
        isAvailable: isAvailable,
        currentPrice: serverItem.unitPrice,
        currentStock: stock,
        priceChanged: (cartPrice - serverItem.unitPrice).abs() > 0.01,
        cartPrice: cartPrice,
        cartQuantity: cartQty,
        insufficientStock: cartQty > stock,
      ));
    }

    debugPrint('[CHECKOUT-VALIDATE] ═══ Validation complete: ${results.where((r) => !r.isAvailable).length} unavailable, ${results.where((r) => r.insufficientStock).length} insufficient ═══');
    return results;
  }
}
