# `addToCart()` Flow + `fetchCart()` Inventory Fallback — Reference

**Source files:**
- `lib/screens/customer/product_detail_screen.dart` — `_addToCart()`
- `lib/providers/cart_provider.dart` — `addToCart()`
- `lib/services/cart_service.dart` — `addOrUpdateItem()`, `fetchCart()`

**Last updated:** July 3, 2026

---

## 1. How `variant_id` is determined (Product Detail Screen → `_addToCart()`)

When the customer taps "Add to Cart," the product detail screen looks up the `variant_id` from the `product_variants` table by matching the selected size + color:

```dart
// lib/screens/customer/product_detail_screen.dart — _addToCart()
void _addToCart() {
  if (_selectedSize == null) {
    // show error snackbar
    return;
  }

  // Look up variant_id and additional_price for the selected size+color
  String? variantId;
  double additionalPrice = 0;
  final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
  for (final v in variants) {
    if (v['size']?.toString() == _selectedSize) {
      if (v['color']?.toString() == _selectedColor || variantId == null) {
        variantId = v['id']?.toString();
        additionalPrice = (v['additional_price'] as num?)?.toDouble() ?? 0;
        if (v['color']?.toString() == _selectedColor) break;
      }
    }
  }

  // Add to cart with variant + pricing info
  final cart = Provider.of<CartProvider>(context, listen: false);
  cart.addToCart(
    productId: widget.product['id'].toString(),
    productName: widget.product['name'],
    imageUrl: imageUrl ?? '',
    price: price,
    size: _selectedSize!,        // ← the raw size string (e.g. "40" or "EU40")
    color: _selectedColor,
    storeId: widget.product['store_id']?.toString(),
    storeName: widget.product['store_name']?.toString(),
    variantId: variantId,         // ← may be null if no product_variants row exists
    additionalPrice: additionalPrice,
  );
}
```

### Key observation: `variantId` can be null

If the product has **no entries in `product_variants`** (common for products created via the older `SupabaseService.addProduct()` flow, which only writes to `inventory`), `variantId` will be `null`. The size is still passed as the raw string from `_buildSizesMap()`.

---

## 2. What `_buildSizesMap()` returns (size source)

The size chips on the product detail screen are built from **both** `inventory` and `product_variants`, merged:

```dart
// lib/screens/customer/product_detail_screen.dart — _buildSizesMap()
Map<String, int> _buildSizesMap() {
  final Map<String, int> sizes = {};

  // From inventory table (e.g. "40" → 100 stock)
  final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
  for (final row in inventory) {
    final size = row['size']?.toString();
    final stock = row['stock'] as int? ?? 0;
    if (size != null && size.isNotEmpty) {
      sizes[size] = (sizes[size] ?? 0) + stock;
    }
  }

  // From product_variants table (e.g. "EU40" → 100 stock)
  final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
  for (final row in variants) {
    final size = row['size']?.toString();
    final stock = row['stock'] as int? ?? 0;
    if (size != null && size.isNotEmpty) {
      sizes[size] = ((sizes[size] ?? 0) < stock) ? stock : (sizes[size] ?? 0);
    }
  }

  // Sort numerically
  final sorted = Map.fromEntries(
    sizes.entries.toList()
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0)),
  );
  return sorted;
}
```

**⚠️ This means the size chips show BOTH `"40"` (from inventory) and `"EU40"` (from product_variants) as separate options if both tables have entries for the same product.** The customer sees and picks whichever one is displayed.

---

## 3. `addToCart()` in CartProvider

Stores the cart item locally, auto-selects it, and writes to Supabase in the background:

```dart
// lib/providers/cart_provider.dart — addToCart()
void addToCart({
  required String productId,
  required String productName,
  required String imageUrl,
  required double price,
  required String size,
  String? color,
  String? storeId,
  String? storeName,
  String? variantId,        // ← nullable
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
      'server_id': null,
      'product_id': productId,
      'product_name': productName,
      'imageUrl': imageUrl,
      'price': effectivePrice,
      'additional_price': additionalPrice,
      'size': size,              // ← stored as-is (e.g. "40" or "EU40")
      'color': color ?? 'none',
      'quantity': quantity,
      'store_id': storeId ?? 'unknown',
      'store_name': storeName ?? 'Unknown Store',
      'variant_id': variantId,   // ← nullable, stored as-is
      'customizations': customizations,
    };
    _selectedKeys.add(cartKey);
  }
  notifyListeners();
  _writeToCache();

  // Background Supabase write
  if (_userId != null) {
    _syncAddToServer(
      cartKey: cartKey,
      productId: productId,
      variantId: variantId,   // ← written to cart_items.variant_id
      quantity: quantity,
      customizations: customizations,
    );
  }
}
```

### What gets written to `cart_items` in Supabase

| Column | Value |
|--------|-------|
| `user_id` | Current user's UUID |
| `product_id` | Product UUID |
| `variant_id` | `variantId` — **may be null** if no `product_variants` row matched |
| `quantity` | 1 (or incremented if same cart key exists) |
| `customizations` | null (unless AR/custom order) |

**⚠️ `cart_items` has NO `size` column.** The size is only recoverable via the `product_variants` LEFT JOIN in `fetchCart()`.

---

## 4. `fetchCart()` — The inventory fallback (when `variant_id` is null)

This is the critical path. When `cart_items.variant_id` is null, the LEFT JOIN with `product_variants` returns null, and the inventory fallback kicks in:

```dart
// lib/services/cart_service.dart — fetchCart()
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

  // ... (store names batch-fetch omitted for clarity) ...

  // ── INVENTORY FALLBACK START ──────────────────────────────

  // Collect product IDs that need inventory fallback (no variant matched)
  final fallbackProductIds = <String>{};
  for (final row in data as List) {
    if (row['product_variants'] == null) {      // ← LEFT JOIN returned null
      fallbackProductIds.add(row['product_id'].toString());
    }
  }

  // Batch-fetch inventory stock for products without variants
  final inventoryStock = <String, int>{};       // {productId-size: stock}
  final inventorySizes = <String, String>{};     // {productId: first size}
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
        inventorySizes[pid] = size;             // ← picks the FIRST size found
      }
    }
  }

  // ── INVENTORY FALLBACK END ────────────────────────────────

  return (data as List).map((row) {
    final variant = row['product_variants'] as Map<String, dynamic>?;
    final productId = row['product_id'] as String;

    // Resolve size: prefer variant, fall back to inventory lookup
    String size = variant?['size']?.toString() ?? '';
    if (size.isEmpty && inventorySizes.containsKey(productId)) {
      size = inventorySizes[productId]!;        // ← first size from inventory
    }

    // Resolve stock: prefer variant, fall back to inventory
    int stock = (variant?['stock'] as num?)?.toInt() ?? 0;
    if (stock <= 0 && size.isNotEmpty) {
      stock = inventoryStock['$productId-$size'] ?? 0;
    }

    return CartItemWithDetails(
      // ...
      size: size,                                // ← resolved size
      stock: stock,                              // ← resolved stock
      // ...
    );
  }).toList();
}
```

### What size does the fallback pick?

The `inventorySizes` map stores the **first size found** for each product (from the inventory query, which has no explicit ORDER BY). This means:

- If `inventory` has rows `("40", 50), ("41", 30), ("42", 20)`, the fallback picks `"40"` (first row returned by Supabase).
- The size format depends on what was written to `inventory` — typically bare numbers (`"40"`) because `_upsertInventory()` uses the map key from the seller's input.

---

## 5. The full data flow — end to end

```
PRODUCT DETAIL SCREEN
  _buildSizesMap() reads inventory + product_variants
  → shows size chips (may show both "40" and "EU40" if both tables have entries)
  → customer taps "40" (or "EU40")

_addToCart()
  → looks up variantId from product_variants where size matches
  → if no match: variantId = null
  → calls cart.addToCart(size: "40", variantId: null)

CART PROVIDER
  addToCart() stores locally: { size: "40", variant_id: null }
  → background sync to Supabase: cart_items.variant_id = NULL

SERVER SYNC (on next app start or auth change)
  fetchCart() does: cart_items LEFT JOIN product_variants ON variant_id
  → variant_id is NULL → LEFT JOIN returns null → variant = null
  → inventory fallback fires:
      SELECT product_id, size, stock FROM inventory
      WHERE product_id = <productId> AND stock > 0
  → inventorySizes[productId] = "40" (first size found)
  → size resolves to "40" ✓

ORDER CREATION (createOrder)
  receives: item['size'] = "40" (from cart)
  → batch-fetches inventory: SELECT ... WHERE product_id IN (...) AND stock > 0
  → exact match: "40" == "40" ✓ → uses "40"
  → inserts order_items with size: "40"
  → DB trigger: inventory WHERE size = "40" → finds row → decrements stock ✓
```

---

## 6. The problem scenario (when it breaks)

```
IF product_variants has "EU40" but inventory has "40":
  → _buildSizesMap() shows BOTH "40" and "EU40" as separate size chips
  → customer taps "EU40"
  → variantId = <some UUID> (found in product_variants)
  → cart stores: { size: "EU40", variant_id: "<uuid>" }

  → fetchCart() LEFT JOIN succeeds (variant_id is not null)
  → size = "EU40" (from product_variants)
  → stock = X (from product_variants, which may be 0!)

  → createOrder() receives size: "EU40"
  → batch-fetches inventory: inventory has "40" (not "EU40")
  → exact match: "EU40" != "40" ✗
  → numeric match: strips "EU" → "40" == "40" ✓ → uses "40"
  → inserts order_items with size: "40"
  → DB trigger: inventory WHERE size = "40" → finds row → decrements stock ✓

  BUT: the VALIDATION check (validateCartForCheckout) uses fetchCart(),
  which returns stock from product_variants (may be 0), NOT inventory (100+).
  → isAvailable = false → "No longer available" banner → blocked!
```

**The validation uses variant stock (possibly 0) while the actual stock is in inventory (100+).** This is why customers see "no longer available" even though inventory has plenty of stock.

---

## 7. Summary of the gap

| Stage | Size used | Stock source | Works? |
|-------|-----------|-------------|--------|
| Product detail (size chips) | `"40"` or `"EU40"` | inventory + product_variants merged | ✅ |
| `addToCart()` | `"EU40"` (from chip) | — | ✅ |
| `fetchCart()` (cart display) | `"EU40"` (from variant) | product_variants stock | ⚠️ may be 0 |
| `validateCartForCheckout()` | `"EU40"` (from fetchCart) | product_variants stock | ❌ may block |
| `createOrder()` | `"40"` (resolved from inventory) | — | ✅ |
| DB trigger | `"40"` (exact match) | inventory stock | ✅ |

**The bug is in the validation step** — it reads stock from `product_variants` (which may be 0) instead of `inventory` (which has the real stock). The fix would be to also check inventory stock in `validateCartForCheckout()`, or to ensure `product_variants` stock is kept in sync with `inventory`.
