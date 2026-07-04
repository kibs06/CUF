# AR Fitting Screen — `_addToCart()` Reference

**File:** `lib/screens/customer/ar_fitting_screen.dart`  
**Lines:** ~173–210  
**Last updated:** July 3, 2026

---

## The function

```dart
void _addToCart() {
  final cart = Provider.of<CartProvider>(context, listen: false);
  final double price = (_activeProduct['price'] is int)
      ? (_activeProduct['price'] as int).toDouble()
      : (_activeProduct['price'] ?? 0.0);
  final List<dynamic> images = _activeProduct['images'] ?? [];

  cart.addToCart(
    productId: _activeProduct['id'].toString(),
    productName: _activeProduct['name'],
    imageUrl: images.isNotEmpty ? images.first : '',
    price: price,
    size: _activeSize,
    color: _activeColor,
  );

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Added ${_activeProduct['name']} (Size $_activeSize) to Cart!'),
      backgroundColor: AppConstants.success,
    ),
  );
}
```

---

## How `_activeSize` is determined

On init and on product switch, the screen picks the first in-stock size from the product's `sizes` map:

```dart
final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});
_activeSize = sizesMap.keys.firstWhere((s) => sizesMap[s] > 0, orElse: () => '39');
```

The user can also tap a size chip to change it (stored in `_activeSize` via `setState`).

---

## Key difference from `product_detail_screen.dart`

| Aspect | `product_detail_screen.dart` | `ar_fitting_screen.dart` |
|--------|-----|------|
| **`variantId` lookup** | ✅ Loops through `product_variants` to find matching `id` by size + color | ❌ **No lookup at all** — passes no `variantId` |
| **`additionalPrice`** | ✅ Reads from `product_variants.additional_price` | ❌ Not included |
| **`storeId` / `storeName`** | ✅ Passed from the product map | ❌ Not passed |
| **Size source** | `_buildSizesMap()` merges inventory + product_variants | `_activeProduct['sizes']` (the legacy flat map from `_mapProduct`) |

### What this means

Because `variantId` is always `null` for AR-fitting-cart items, `fetchCart()` will always hit the **inventory fallback** path — picking the "first size found" from `inventory` (no ORDER BY, arbitrary). This means:

1. The size the customer selected in the AR view (`_activeSize`) may not be the size that `fetchCart()` resolves to.
2. The `cart_items.variant_id` column will be `NULL` for every AR-added item.
3. The `validateCartForCheckout()` fix we just applied (checking `inventory` as authoritative source) is especially important for these items, since their stock was never coming from `product_variants` in the first place.

### Recommended fix

Add the same `variantId` lookup that `product_detail_screen.dart` uses:

```dart
void _addToCart() {
  final cart = Provider.of<CartProvider>(context, listen: false);
  final double price = (_activeProduct['price'] is int)
      ? (_activeProduct['price'] as int).toDouble()
      : (_activeProduct['price'] ?? 0.0);
  final List<dynamic> images = _activeProduct['images'] ?? [];

  // Look up variant_id for the selected size (same as product_detail_screen)
  String? variantId;
  double additionalPrice = 0;
  final variants = _activeProduct['product_variants'] as List<dynamic>? ?? [];
  for (final v in variants) {
    if (v['size']?.toString() == _activeSize) {
      if (v['color']?.toString() == _activeColor || variantId == null) {
        variantId = v['id']?.toString();
        additionalPrice = (v['additional_price'] as num?)?.toDouble() ?? 0;
        if (v['color']?.toString() == _activeColor) break;
      }
    }
  }

  cart.addToCart(
    productId: _activeProduct['id'].toString(),
    productName: _activeProduct['name'],
    imageUrl: images.isNotEmpty ? images.first : '',
    price: price,
    size: _activeSize,
    color: _activeColor,
    variantId: variantId,
    additionalPrice: additionalPrice,
  );

  // ... snackbar
}
```

**Note:** This also requires that `_activeProduct` includes `product_variants` data. Currently, products from `ProductProvider` are fetched via `SupabaseService.fetchProducts()` which does include `product_variants(size, stock)` in the select — so the data should be available as `_activeProduct['product_variants']`.
