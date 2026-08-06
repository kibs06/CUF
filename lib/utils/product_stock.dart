/// Stock helpers for customer-facing product maps (as produced by
/// `SupabaseService._mapProduct`).
///
/// The `inventory` relation is the app's AUTHORITATIVE stock source —
/// checkout (`cart_service.dart`) validates against it and treats a
/// missing inventory match as out of stock. These helpers share that
/// semantics so the customer catalog hides exactly what is unpurchasable.
library;

/// Total purchasable stock across every size of a product.
///
/// Sums `inventory.stock` rows. Products with no inventory rows total 0
/// (they cannot be added to cart or checked out), matching the
/// `resolveInventoryStock` convention of -1 = no match → out of stock.
int totalStock(Map<String, dynamic> product) {
  final inventory = product['inventory'];
  if (inventory is! List) return 0;
  return inventory.fold<int>(
    0,
    (sum, item) => sum + (((item is Map ? item['stock'] : null) as num?)?.toInt() ?? 0),
  );
}

/// Whether a product has no stock on any size (hidden from customer browse).
bool isOutOfStock(Map<String, dynamic> product) => totalStock(product) <= 0;

/// Products a customer can purchase right now — removes anything with zero
/// stock on every size (the `hideOutOfStock` browse rule). Products that
/// have no `inventory` rows at all (legacy rows) also total 0 and are
/// excluded, matching checkout's out-of-stock semantics.
///
/// This is the "hide until restocked" filter: an out-of-stock product drops
/// out of the catalog here, and comes back automatically on the next fetch
/// once a seller restocks it (any inventory row > 0).
List<Map<String, dynamic>> purchasableProducts(
  List<Map<String, dynamic>> products,
) =>
    products.where((p) => !isOutOfStock(p)).toList();

/// Distribute a target total stock across one size's variant rows, in row
/// order, clamping each row at 0.
///
/// Used to keep `product_variants` in sync with the authoritative
/// `inventory` totals when a seller adjusts/restocks stock. Positive deltas
/// land on the first row; negative deltas drain rows until fully absorbed
/// (a row can never go below 0). Returns one new stock value per input.
List<int> distributeVariantStock(List<int> currentStocks, int target) {
  final result = List<int>.from(currentStocks);
  var delta =
      target - currentStocks.fold<int>(0, (sum, stock) => sum + stock);
  if (delta == 0) return result;
  for (var i = 0; i < result.length; i++) {
    if (delta == 0) break;
    final newStock = (result[i] + delta).clamp(0, 99999);
    delta -= newStock - result[i];
    result[i] = newStock;
  }
  return result;
}
