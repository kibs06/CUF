import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item_with_details.dart';
import '../services/cart_service.dart';

/// Hybrid persistent cart provider.
///
/// - In-memory [Map] for instant UI updates (survives hot-reload).
/// - SharedPreferences local cache keyed by user ID.
/// - Supabase-backed source of truth (survives logout/login, device switch).
///
/// Mutations are optimistic: local state + cache update immediately,
/// then a background Supabase write fires. On failure the optimistic
/// update is rolled back and [_lastError] is set.
class CartProvider extends ChangeNotifier {
  // ─── Internal state ─────────────────────────────────────────────

  final Map<String, Map<String, dynamic>> _items = {};
  final Set<String> _selectedKeys = {};
  String? _userId;
  StreamSubscription<AuthState>? _authSubscription;
  bool _hydrated = false;

  /// Last error from a failed background sync. Cart screen can watch
  /// this and show a SnackBar, then call [clearError].
  String? _lastError;
  String? get lastError => _lastError;

  // ─── Public getters (unchanged API) ─────────────────────────────

  Map<String, Map<String, dynamic>> get items => _items;
  Set<String> get selectedKeys => Set.unmodifiable(_selectedKeys);

  int get itemCount =>
      _items.values.fold(0, (sum, item) => sum + (item['quantity'] as int));

  double get subtotal => _items.values.fold(
        0.0,
        (sum, item) =>
            sum + ((item['price'] as double) * (item['quantity'] as int)),
      );

  double get deliveryFee => subtotal > 0 ? 100.0 : 0.0;
  double get total => subtotal + deliveryFee;

  // ── Selected-item computed getters ──────────────────────────────

  int get selectedCount => _selectedKeys.fold(
        0,
        (sum, key) => sum + ((_items[key]?['quantity'] as int?) ?? 0),
      );

  double get selectedSubtotal => _selectedKeys.fold(
        0.0,
        (sum, key) {
          final item = _items[key];
          if (item == null) return sum;
          return sum + ((item['price'] as double) * (item['quantity'] as int));
        },
      );

  double get selectedDeliveryFee => selectedSubtotal > 0 ? 100.0 : 0.0;
  double get selectedTotal => selectedSubtotal + selectedDeliveryFee;

  bool get allSelected =>
      _items.isNotEmpty && _selectedKeys.length == _items.length;

  bool isStoreFullySelected(String storeId) {
    final storeKeys = _items.entries
        .where((e) => (e.value['store_id']?.toString() ?? '') == storeId)
        .map((e) => e.key);
    return storeKeys.isNotEmpty && storeKeys.every(_selectedKeys.contains);
  }

  bool isStorePartiallySelected(String storeId) {
    final storeKeys = _items.entries
        .where((e) => (e.value['store_id']?.toString() ?? '') == storeId)
        .map((e) => e.key)
        .toList();
    final selCount = storeKeys.where(_selectedKeys.contains).length;
    return selCount > 0 && selCount < storeKeys.length;
  }

  List<Map<String, dynamic>> get groupedByStore {
    final map = <String, Map<String, dynamic>>{};
    for (final entry in _items.entries) {
      final storeId = entry.value['store_id']?.toString() ?? 'unknown';
      final storeName =
          entry.value['store_name']?.toString() ?? 'Unknown Store';
      if (!map.containsKey(storeId)) {
        map[storeId] = {
          'store_id': storeId,
          'store_name': storeName,
          'items': <Map<String, dynamic>>[],
        };
      }
      (map[storeId]!['items'] as List).add(entry.value);
    }
    return map.values.toList();
  }

  List<Map<String, dynamic>> get selectedItems => _items.entries
      .where((e) => _selectedKeys.contains(e.key))
      .map((e) => e.value)
      .toList();

  // ─── Constructor + auth state listening ─────────────────────────

  CartProvider() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthStateChanged);

    // Hydrate immediately if there's already an active session
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      _userId = currentUserId;
      _hydrateFromCache(currentUserId);
      _syncFromServer(currentUserId);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _onAuthStateChanged(AuthState state) {
    final session = state.session;

    if (session != null) {
      final userId = session.user.id;
      if (_userId == userId && _hydrated) return; // Same user, already loaded
      _userId = userId;
      _hydrateFromCache(userId);
      _syncFromServer(userId);
    } else {
      // Signed out — clear local state + cache, but keep Supabase rows
      _userId = null;
      _hydrated = false;
      _items.clear();
      _selectedKeys.clear();
      _clearCacheForCurrentUser();
      notifyListeners();
    }
  }

  // ─── Local cache (SharedPreferences) ───────────────────────────

  String get _cacheKey => 'cart_cache_${_userId ?? "anon"}';

  Future<void> _hydrateFromCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('cart_cache_$userId');
      if (json == null || json.isEmpty) {
        _hydrated = true;
        return;
      }

      final List<dynamic> decoded = jsonDecode(json);
      _items.clear();
      for (final item in decoded) {
        final map = Map<String, dynamic>.from(item);
        final key = map['id'] as String;
        _items[key] = map;
      }
      // Items start deselected by default
      _selectedKeys.clear();
      _hydrated = true;
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: cache hydrate failed: $e');
      _hydrated = true;
    }
  }

  Future<void> _writeToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_items.values.toList());
      await prefs.setString(_cacheKey, json);
    } catch (e) {
      debugPrint('CartProvider: cache write failed: $e');
    }
  }

  Future<void> _clearCacheForCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }

  // ─── Server sync ────────────────────────────────────────────────

  Future<void> _syncFromServer(String userId) async {
    try {
      final serverItems = await CartService.instance.fetchCart(userId);
      // Preserve size/color from existing local items when server returns empty.
      // The cart_items table has no size column, so fetchCart loses size when
      // the product_variants LEFT JOIN returns null (no variant entry).
      final oldItems = Map<String, Map<String, dynamic>>.from(_items);
      _items.clear();
      for (final item in serverItems) {
        final map = item.toCartItemMap();
        final key = map['id'] as String;
        final oldItem = oldItems[key];
        if (oldItem != null) {
          if ((map['size']?.toString().isEmpty ?? true) &&
              (oldItem['size']?.toString().isNotEmpty ?? false)) {
            map['size'] = oldItem['size'];
          }
          if ((map['color'] == 'none' || map['color'] == null) &&
              oldItem['color'] != null &&
              oldItem['color'] != 'none' &&
              (oldItem['color']?.toString().isNotEmpty ?? false)) {
            map['color'] = oldItem['color'];
          }
        }
        _items[key] = map;
      }
      // Items start deselected by default
      _selectedKeys.clear();
      await _writeToCache();
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: server sync failed: $e');
      _lastError = 'Could not sync cart from server.';
      notifyListeners();
    }
  }

  // ─── Selection toggles (unchanged) ─────────────────────────────

  void toggleItem(String cartKey) {
    if (_selectedKeys.contains(cartKey)) {
      _selectedKeys.remove(cartKey);
    } else {
      _selectedKeys.add(cartKey);
    }
    notifyListeners();
  }

  void toggleStore(String storeId) {
    final storeKeys = _items.entries
        .where((e) => (e.value['store_id']?.toString() ?? '') == storeId)
        .map((e) => e.key)
        .toList();
    final allSel = storeKeys.every(_selectedKeys.contains);
    for (final key in storeKeys) {
      if (allSel) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    }
    notifyListeners();
  }

  void toggleAll() {
    if (allSelected) {
      _selectedKeys.clear();
    } else {
      _selectedKeys.addAll(_items.keys);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedKeys.addAll(_items.keys);
    notifyListeners();
  }

  // ─── Cart mutations (optimistic + background sync) ─────────────

  void addToCart({
    required String productId,
    required String productName,
    required String imageUrl,
    required double price,
    required String size,
    String? color,
    String? storeId,
    String? storeName,
    String? variantId,
    double additionalPrice = 0,
    Map<String, dynamic>? customizations,
    int quantity = 1,
  }) {
    final effectivePrice = price + additionalPrice;
    final cartKey = '$productId-$size-${color ?? 'none'}';

    if (_items.containsKey(cartKey)) {
      _items[cartKey]!['quantity'] =
          (_items[cartKey]!['quantity'] as int) + quantity;
    } else {
      _items[cartKey] = {
        'id': cartKey,
        'server_id': null, // filled after server confirms
        'product_id': productId,
        'product_name': productName,
        'imageUrl': imageUrl,
        'price': effectivePrice,
        'additional_price': additionalPrice,
        'size': size,
        'color': color ?? 'none',
        'quantity': quantity,
        'store_id': storeId ?? 'unknown',
        'store_name': storeName ?? 'Unknown Store',
        'variant_id': variantId,
        'customizations': customizations,
      };
      // Auto-select new items so they're ready for checkout
      _selectedKeys.add(cartKey);
    }
    notifyListeners();
    _writeToCache();

    // Background Supabase write
    if (_userId != null) {
      _syncAddToServer(
        cartKey: cartKey,
        productId: productId,
        variantId: variantId,
        quantity: quantity,
        customizations: customizations,
      );
    }
  }

  Future<void> _syncAddToServer({
    required String cartKey,
    required String productId,
    String? variantId,
    required int quantity,
    Map<String, dynamic>? customizations,
  }) async {
    try {
      final size = _items[cartKey]?['size']?.toString();
      final serverId = await CartService.instance.addOrUpdateItem(
        userId: _userId!,
        productId: productId,
        variantId: variantId,
        quantity: quantity,
        customizations: customizations,
        size: size,
      );
      // Update server_id so subsequent mutations can reference it
      if (_items.containsKey(cartKey) && _items[cartKey]!['server_id'] == null) {
        _items[cartKey]!['server_id'] = serverId;
        _writeToCache();
      }
    } catch (e) {
      debugPrint('CartProvider: sync add failed: $e');
      // Roll back optimistic update
      if (_items.containsKey(cartKey)) {
        final currentQty = _items[cartKey]!['quantity'] as int;
        if (currentQty > quantity) {
          _items[cartKey]!['quantity'] = currentQty - quantity;
        } else {
          _items.remove(cartKey);
          _selectedKeys.remove(cartKey);
        }
        notifyListeners();
        _writeToCache();
      }
      _lastError = 'Failed to sync cart. Please check your connection.';
      notifyListeners();
    }
  }

  void removeFromCart(String cartKey) {
    final removed = _items.remove(cartKey);
    _selectedKeys.remove(cartKey);
    notifyListeners();
    _writeToCache();

    // Background server delete
    if (_userId != null && removed != null) {
      final serverId = removed['server_id'] as String?;
      if (serverId != null) {
        _syncRemoveFromServer(serverId);
      }
    }
  }

  Future<void> _syncRemoveFromServer(String cartItemId) async {
    try {
      await CartService.instance.removeItem(cartItemId);
    } catch (e) {
      debugPrint('CartProvider: sync remove failed: $e');
      // Re-fetch from server to restore consistency
      if (_userId != null) _syncFromServer(_userId!);
    }
  }

  void incrementQuantity(String cartKey) {
    if (!_items.containsKey(cartKey)) return;
    final newQty = (_items[cartKey]!['quantity'] as int) + 1;
    _items[cartKey]!['quantity'] = newQty;
    notifyListeners();
    _writeToCache();

    // Background server update
    if (_userId != null) {
      final serverId = _items[cartKey]!['server_id'] as String?;
      if (serverId != null) {
        CartService.instance
            .updateQuantity(cartItemId: serverId, newQuantity: newQty)
            .catchError((e) {
          debugPrint('CartProvider: sync increment failed: $e');
          // Roll back
          if (_items.containsKey(cartKey)) {
            _items[cartKey]!['quantity'] = newQty - 1;
            notifyListeners();
            _writeToCache();
          }
        });
      }
    }
  }

  void decrementQuantity(String cartKey) {
    if (!_items.containsKey(cartKey)) return;
    final currentQty = _items[cartKey]!['quantity'] as int;

    if (currentQty > 1) {
      _items[cartKey]!['quantity'] = currentQty - 1;
      notifyListeners();
      _writeToCache();

      // Background server update
      if (_userId != null) {
        final serverId = _items[cartKey]!['server_id'] as String?;
        if (serverId != null) {
          CartService.instance
              .updateQuantity(cartItemId: serverId, newQuantity: currentQty - 1)
              .catchError((e) {
            debugPrint('CartProvider: sync decrement failed: $e');
            if (_items.containsKey(cartKey)) {
              _items[cartKey]!['quantity'] = currentQty;
              notifyListeners();
              _writeToCache();
            }
          });
        }
      }
    } else {
      // Quantity would hit 0 → remove entirely
      removeFromCart(cartKey);
    }
  }

  /// Clear cart locally and on Supabase.
  /// Called after a successful order placement.
  void clearCart() {
    _items.clear();
    _selectedKeys.clear();
    notifyListeners();
    _writeToCache();

    // Background server clear
    if (_userId != null) {
      CartService.instance.clearCart(_userId!).catchError((e) {
        debugPrint('CartProvider: sync clear failed: $e');
      });
    }
  }

  /// Remove specific items from the server by their Supabase row IDs.
  /// Used after order placement to delete only the ordered items,
  /// preserving unselected items (e.g. from other stores).
  Future<void> removeServerItems(List<String> serverIds) async {
    if (_userId == null || serverIds.isEmpty) return;
    try {
      await CartService.instance.removeItems(_userId!, serverIds);
    } catch (e) {
      debugPrint('CartProvider: server removeItems failed: $e');
      // Re-fetch from server to restore consistency
      _syncFromServer(_userId!);
    }
  }

  /// Remove (or reduce) cart lines that were just paid for.
  ///
  /// Keeps the customer's cart honest when a GCash payment is confirmed:
  /// lines fully covered by the purchase are removed (local + server),
  /// and lines where the bought quantity is less than the cart quantity
  /// are reduced to the remainder (applied locally AND on the server).
  /// Items NOT in the purchase are left untouched (e.g. things the
  /// customer added to the cart while the payment was still awaiting).
  ///
  /// Idempotent: calling it again after items were already removed is a
  /// no-op.
  ///
  /// [purchasedItems] entries need at least `product_id` and `size`;
  /// `quantity` is used when present (defaults to 1).
  Future<void> removePurchasedItems(
    List<Map<String, dynamic>> purchasedItems,
  ) async {
    if (_userId == null || purchasedItems.isEmpty) return;

    final adjustments = computePurchasedAdjustments(_items, purchasedItems);
    final keysToRemove = adjustments.$1;
    final serverIdsToRemove = adjustments.$2;
    final newQuantitiesByKey = adjustments.$3;

    var mutated = false;
    if (keysToRemove.isNotEmpty) {
      for (final key in keysToRemove) {
        _items.remove(key);
        _selectedKeys.remove(key);
      }
      mutated = true;
    }

    final quantityUpdates = <(String, int)>[];
    for (final entry in newQuantitiesByKey.entries) {
      final item = _items[entry.key];
      if (item == null) continue;
      item['quantity'] = entry.value; // apply locally
      final serverId = item['server_id'] as String?;
      if (serverId != null) quantityUpdates.add((serverId, entry.value));
      mutated = true;
    }

    if (mutated) {
      notifyListeners();
      _writeToCache();
    }

    if (serverIdsToRemove.isNotEmpty) {
      await removeServerItems(serverIdsToRemove);
    }
    for (final (serverId, qty) in quantityUpdates) {
      CartService.instance
          .updateQuantity(cartItemId: serverId, newQuantity: qty)
          .catchError((e) {
        debugPrint('CartProvider: purchased-item qty sync failed: $e');
      });
    }
  }

  /// Reconcile the cart against the customer's recently-PAID orders.
  ///
  /// Covers the path where the app was killed mid-GCash-payment and the
  /// webhook confirmed while the user was away: when they next open the
  /// cart, any lines that were actually paid for are removed so they
  /// can't be accidentally re-ordered. Scoped to orders confirmed in the
  /// last 30 minutes (the awaiting_payment window) to keep the query
  /// cheap; safe to call on every cart screen load.
  Future<void> reconcilePurchasedCart() async {
    if (_userId == null || _items.isEmpty) return;
    try {
      final since = DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toIso8601String();
      final orders = await Supabase.instance.client
          .from('orders')
          .select('order_items(product_id, size, quantity)')
          .eq('customer_id', _userId!)
          .eq('payment_status', 'paid')
          .gte('created_at', since)
          .limit(10);
      if (orders.isEmpty) return;
      final purchased = <Map<String, dynamic>>[];
      for (final order in orders.whereType<Map>()) {
        final items = order['order_items'];
        if (items is! List) continue;
        purchased.addAll(
          items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
        );
      }
      if (purchased.isEmpty) return;
      await removePurchasedItems(purchased);
    } catch (e) {
      debugPrint('CartProvider: reconcilePurchasedCart failed: $e');
    }
  }

  /// Fallback: clear the entire server cart for this user.
  /// Used when ordered items have no server_id (background sync
  /// hadn't completed) so targeted deletion isn't possible.
  Future<void> clearCartFromServer() async {
    if (_userId == null) return;
    try {
      await CartService.instance.clearCart(_userId!);
    } catch (e) {
      debugPrint('CartProvider: server clearCart failed: $e');
    }
  }

  /// Clear error state.
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Force a re-sync from the server (e.g., pull-to-refresh).
  Future<void> refreshFromServer() async {
    if (_userId != null) {
      await _syncFromServer(_userId!);
    }
  }

  /// Validate cart against live product data for checkout.
  /// Returns validation results without mutating the cart.
  Future<List<CartValidationResult>> validateForCheckout() async {
    if (_userId == null) return [];
    return CartService.instance.validateCartForCheckout(_userId!, _items);
  }

  /// Remove unavailable items from cart based on validation results.
  /// Call after [validateForCheckout] when the user confirms.
  void removeUnavailableItems(List<CartValidationResult> results) {
    for (final result in results) {
      if (!result.isAvailable) {
        // Match by server_id (Supabase cart_items.id) to target specific variants
        final keysToRemove = _items.entries
            .where((e) => e.value['server_id'] == result.cartItemId)
            .map((e) => e.key)
            .toList();
        for (final key in keysToRemove) {
          removeFromCart(key);
        }
      }
    }
  }
}

/// Pure computation for [CartProvider.removePurchasedItems] — kept
/// separate from the provider so the cart/order reconciliation logic
/// is unit-testable without Supabase.
///
/// Returns `(keysToRemove, serverIdsToRemove, newQuantitiesByKey)`:
///   • keysToRemove — cart keys fully covered by the purchase;
///   • serverIdsToRemove — server row ids for those removed lines;
///   • newQuantitiesByKey — cart key → remaining quantity for lines
///     only partially covered (the caller applies these locally AND
///     syncs them to the server).
(List<String>, List<String>, Map<String, int>) computePurchasedAdjustments(
  Map<String, Map<String, dynamic>> cartItems,
  List<Map<String, dynamic>> purchasedItems,
) {
  // Aggregate bought quantities per product+size key.
  final bought = <String, int>{};
  for (final item in purchasedItems) {
    final key = '${item['product_id']}|${item['size'] ?? ''}';
    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
    bought[key] = (bought[key] ?? 0) + qty;
  }

  final keysToRemove = <String>[];
  final serverIdsToRemove = <String>[];
  final newQuantitiesByKey = <String, int>{};

  for (final entry in cartItems.entries) {
    final key = entry.key;
    final item = entry.value;
    final productKey = '${item['product_id']}|${item['size'] ?? ''}';
    final boughtQty = bought[productKey];
    if (boughtQty == null || boughtQty <= 0) continue;

    final cartQty = (item['quantity'] as num?)?.toInt() ?? 1;
    final remaining = cartQty - boughtQty;
    final serverId = item['server_id'] as String?;

    if (remaining <= 0) {
      keysToRemove.add(key);
      if (serverId != null) serverIdsToRemove.add(serverId);
    } else {
      newQuantitiesByKey[key] = remaining;
    }
  }

  return (keysToRemove, serverIdsToRemove, newQuantitiesByKey);
}
