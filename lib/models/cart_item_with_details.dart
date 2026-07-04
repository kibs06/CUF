/// Bundles a raw [cart_items] row with joined product and variant data
/// so the UI has everything it needs in one round-trip from Supabase.
class CartItemWithDetails {
  final String id;
  final String userId;
  final String productId;
  final String? variantId;
  final int quantity;
  final Map<String, dynamic>? customizations;
  final DateTime createdAt;
  final DateTime updatedAt;

  // From joined products table
  final String productName;
  final String? imageUrl;
  final bool isActive;
  final String? storeId;
  final String? storeName;
  final double price; // base product price

  // From joined product_variants table (nullable — cart item may not have a variant)
  final String size;
  final String? color;
  final int stock;
  final double additionalPrice;

  // Raw size from cart_items.size column (may differ from variant-based size
  // if the variant JOIN returned a different format). Used for inventory lookup.
  final String? cartSize;

  const CartItemWithDetails({
    required this.id,
    required this.userId,
    required this.productId,
    this.variantId,
    required this.quantity,
    this.customizations,
    required this.createdAt,
    required this.updatedAt,
    required this.productName,
    this.imageUrl,
    this.isActive = true,
    this.storeId,
    this.storeName,
    this.price = 0,
    this.size = '',
    this.color,
    this.stock = 0,
    this.additionalPrice = 0,
    this.cartSize,
  });

  /// Effective unit price = base price + variant additional price.
  double get unitPrice => price + additionalPrice;

  /// Line total = unitPrice × quantity.
  double get lineTotal => unitPrice * quantity;

  /// Convert to the legacy map format expected by CartProvider consumers.
  ///
  /// Keys match the existing CartProvider item structure so cart_screen,
  /// checkout_screen, and product_detail_screen continue to work unchanged.
  Map<String, dynamic> toCartItemMap() {
    return {
      'id': _compositeKey,
      'server_id': id,
      'product_id': productId,
      'product_name': productName,
      'imageUrl': imageUrl ?? '',
      'price': unitPrice,
      'additional_price': additionalPrice,
      'size': size,
      'color': color ?? 'none',
      'quantity': quantity,
      'store_id': storeId ?? 'unknown',
      'store_name': storeName ?? 'Unknown Store',
      'variant_id': variantId,
      'customizations': customizations,
      // Pass through the raw cart_items.size for inventory lookup
      'cart_size': cartSize,
    };
  }

  /// Composite key matching the existing convention: `productId-size-color`.
  String get _compositeKey => '$productId-$size-${color ?? 'none'}';
}

/// Result of validating a single cart line item against live product data.
///
/// Used by [CartService.validateCartForCheckout] and displayed by the
/// checkout screen as inline banners before the customer places an order.
class CartValidationResult {
  final String cartItemId;
  final String productId;
  final String productName;
  final bool isAvailable; // product is active AND stock > 0
  final double currentPrice; // fresh price from DB
  final int currentStock; // fresh stock from DB
  final bool priceChanged; // true if currentPrice != cartPrice
  final double cartPrice; // price the customer saw in the cart
  final int cartQuantity; // quantity in the customer's cart
  final bool insufficientStock; // cartQuantity > currentStock
  final String matchedInventorySize; // which inventory size was matched
  final String resolutionMethod; // how size was resolved (for logging)

  const CartValidationResult({
    required this.cartItemId,
    required this.productId,
    required this.productName,
    required this.isAvailable,
    required this.currentPrice,
    required this.currentStock,
    required this.priceChanged,
    required this.cartPrice,
    this.cartQuantity = 1,
    this.insufficientStock = false,
    this.matchedInventorySize = '',
    this.resolutionMethod = '',
  });
}
