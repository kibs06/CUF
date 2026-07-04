import 'package:flutter/material.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, Map<String, dynamic>> _items = {};

  /// Set of cart keys that are currently selected for checkout.
  final Set<String> _selectedKeys = {};

  Map<String, Map<String, dynamic>> get items => _items;

  Set<String> get selectedKeys => Set.unmodifiable(_selectedKeys);

  int get itemCount => _items.values.fold(0, (sum, item) => sum + (item['quantity'] as int));

  double get subtotal => _items.values.fold(
        0.0,
        (sum, item) => sum + ((item['price'] as double) * (item['quantity'] as int)),
      );

  double get deliveryFee => subtotal > 0 ? 100.0 : 0.0; // Flat local Cebu delivery fee

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

  bool get allSelected => _items.isNotEmpty && _selectedKeys.length == _items.length;

  /// Whether every item in the given [storeId] group is selected.
  bool isStoreFullySelected(String storeId) {
    final storeKeys = _items.entries
        .where((e) => (e.value['store_id']?.toString() ?? '') == storeId)
        .map((e) => e.key);
    return storeKeys.isNotEmpty && storeKeys.every(_selectedKeys.contains);
  }

  /// Whether at least one (but not all) items in the given [storeId] group are selected.
  bool isStorePartiallySelected(String storeId) {
    final storeKeys = _items.entries
        .where((e) => (e.value['store_id']?.toString() ?? '') == storeId)
        .map((e) => e.key)
        .toList();
    final selectedCount = storeKeys.where(_selectedKeys.contains).length;
    return selectedCount > 0 && selectedCount < storeKeys.length;
  }

  // ── Selection toggles ──────────────────────────────────────────

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
    final allSelected = storeKeys.every(_selectedKeys.contains);
    for (final key in storeKeys) {
      if (allSelected) {
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

  /// Auto-select all items (used on first load).
  void selectAll() {
    _selectedKeys.addAll(_items.keys);
    notifyListeners();
  }

  /// Returns items grouped by store_id.
  /// Each entry: { 'store_id': String, 'store_name': String, 'items': List<Map> }
  List<Map<String, dynamic>> get groupedByStore {
    final map = <String, Map<String, dynamic>>{};
    for (final entry in _items.entries) {
      final storeId = entry.value['store_id']?.toString() ?? 'unknown';
      final storeName = entry.value['store_name']?.toString() ?? 'Unknown Store';
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

  /// Get selected items as a list (for passing to checkout).
  List<Map<String, dynamic>> get selectedItems =>
      _items.entries.where((e) => _selectedKeys.contains(e.key)).map((e) => e.value).toList();

  // ── Cart mutation (store_id/store_name are optional for backward compat) ──

  void addToCart({
    required String productId,
    required String productName,
    required String imageUrl,
    required double price,
    required String size,
    String? color,
    String? storeId,
    String? storeName,
    int quantity = 1,
  }) {
    // Use 'none' if color is null — prevents key mismatch
    final cartKey = '$productId-$size-${color ?? 'none'}';

    if (_items.containsKey(cartKey)) {
      _items[cartKey]!['quantity'] = (_items[cartKey]!['quantity'] as int) + quantity;
    } else {
      _items[cartKey] = {
        'id': cartKey,
        'product_id': productId,
        'product_name': productName,
        'imageUrl': imageUrl,
        'price': price,
        'size': size,
        'color': color ?? 'none',
        'quantity': quantity,
        'store_id': storeId ?? 'unknown',
        'store_name': storeName ?? 'Unknown Store',
      };
      _selectedKeys.add(cartKey); // Auto-select new items
    }
    notifyListeners();
  }

  void removeFromCart(String cartKey) {
    _items.remove(cartKey);
    _selectedKeys.remove(cartKey);
    notifyListeners();
  }

  void incrementQuantity(String cartKey) {
    if (_items.containsKey(cartKey)) {
      _items[cartKey]!['quantity'] = (_items[cartKey]!['quantity'] as int) + 1;
      notifyListeners();
    }
  }

  void decrementQuantity(String cartKey) {
    if (_items.containsKey(cartKey)) {
      final currentQty = _items[cartKey]!['quantity'] as int;
      if (currentQty > 1) {
        _items[cartKey]!['quantity'] = currentQty - 1;
      } else {
        _items.remove(cartKey);
        _selectedKeys.remove(cartKey);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    _selectedKeys.clear();
    notifyListeners();
  }
}
