/// Sale pricing helpers — the SINGLE source of truth for "is this product
/// on sale right now" logic.
///
/// Every screen, provider, service, and widget must go through these
/// functions instead of reimplementing the active-sale date/price
/// comparison inline. This keeps the rule consistent everywhere:
///
/// A product is on sale ONLY when:
///   1. `sale_price` is set and strictly less than `price`, AND
///   2. `sale_starts_at` (if set) is in the past, AND
///   3. `sale_ends_at` (if set) is in the future.
library;

/// Best-effort numeric coercion that handles int/double/string values the
/// way they can come back from Supabase.
double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is int) return value.toDouble();
  if (value is double) return value;
  return double.tryParse(value.toString());
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// True only while the sale is active (see library docs for the rule).
///
/// [now] is injectable for testing; defaults to the current time.
bool isOnSale(Map<String, dynamic> product, {DateTime? now}) {
  final nowUtc = now ?? DateTime.now();
  final price = _asDouble(product['price']) ?? 0;
  final salePrice = _asDouble(product['sale_price']);

  if (salePrice == null || salePrice <= 0) return false;
  // Sale price must be STRICTLY below the original price to count as a
  // discount. Equal or higher values mean "not on sale" (covers a cleared
  // or corrected sale without a DB CHECK constraint).
  if (salePrice >= price) return false;

  final start = _asDate(product['sale_starts_at']);
  if (start != null && nowUtc.isBefore(start)) return false;

  final end = _asDate(product['sale_ends_at']);
  if (end != null && nowUtc.isAfter(end)) return false;

  return true;
}

/// The price the customer actually pays: the sale price while the sale is
/// active, otherwise the original price.
double effectivePrice(Map<String, dynamic> product, {DateTime? now}) {
  if (isOnSale(product, now: now)) {
    return _asDouble(product['sale_price']) ?? _asDouble(product['price']) ?? 0;
  }
  return _asDouble(product['price']) ?? 0;
}

/// Whole-number discount percentage for badges (e.g. -20), or null when not
/// on sale.
int? salePercent(Map<String, dynamic> product, {DateTime? now}) {
  if (!isOnSale(product, now: now)) return null;
  final price = _asDouble(product['price']) ?? 0;
  final salePrice = _asDouble(product['sale_price']) ?? 0;
  if (price <= 0) return null;
  return (((price - salePrice) / price) * 100).round();
}
