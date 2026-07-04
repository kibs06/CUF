/// Shared helpers for cart operations: variant resolution, size normalization,
/// and inventory stock lookup.
///
/// Used by `product_detail_screen.dart`, `ar_fitting_screen.dart`,
/// `cart_service.dart`, and `supabase_service.dart` to ensure consistent
/// logic across all cart/checkout paths.
library;

import 'package:flutter/foundation.dart';

// ─── VARIANT RESOLUTION ───────────────────────────────────────────

/// Resolves a product variant from a list of variants given a selected size
/// and optional color.
///
/// Used by both `product_detail_screen.dart` and `ar_fitting_screen.dart`
/// to ensure the same variant-lookup logic is always applied when adding
/// items to the cart — preventing bugs like null `variant_id` when a screen
/// forgets to perform the lookup.
///
/// Returns a record with the matched `variantId` (nullable — null means no
/// matching variant exists in the database) and the variant's
/// `additionalPrice` (defaults to 0 when no variant matches).
({String? variantId, double additionalPrice}) resolveVariant({
  required List<dynamic> variants,
  required String size,
  String? color,
}) {
  String? variantId;
  double additionalPrice = 0;
  for (final v in variants) {
    if (v['size']?.toString() == size) {
      // Prefer an exact color match, but accept any color if none matched yet
      if (v['color']?.toString() == color || variantId == null) {
        variantId = v['id']?.toString();
        additionalPrice = (v['additional_price'] as num?)?.toDouble() ?? 0;
        // If color matches exactly, we've found the best match — stop
        if (v['color']?.toString() == color) break;
      }
    }
  }
  return (variantId: variantId, additionalPrice: additionalPrice);
}

// ─── SIZE NORMALIZATION ───────────────────────────────────────────

/// Strip alpha prefix from a size string: "EU40" → "40", "US9" → "9".
///
/// Used to normalize cart sizes against inventory sizes and DB trigger
/// sizes, which may store different formats.
String normalizeSize(String size) {
  return size.replaceAll(RegExp(r'[A-Za-z]+'), '');
}

/// Normalize a size string for display purposes.
/// If the size is purely numeric, returns it as-is.
/// If it has a prefix like "EU", returns the prefix + number.
/// Empty string returns empty string.
String normalizeSizeForDisplay(String size) {
  final stripped = normalizeSize(size);
  if (stripped.isEmpty) return size;
  // If original had a prefix, preserve it for display
  if (size.length > stripped.length) {
    final prefix = size.substring(0, size.length - stripped.length);
    return '$prefix$stripped';
  }
  return stripped;
}

// ─── INVENTORY STOCK RESOLUTION ───────────────────────────────────

/// Matches an inventory row by product_id and size, with logging.
///
/// Returns the stock value if a match is found, or -1 if no match.
/// Logs every step for debugging the false "no longer available" bug.
int resolveInventoryStock({
  required List<Map<String, dynamic>> inventoryRows,
  required String productId,
  required String cartSize,
  required String productName,
}) {
  debugPrint('[STOCK-RESOLVE] ─── $productName (product: $productId) ───');
  debugPrint('[STOCK-RESOLVE] Cart size (raw): "$cartSize"');
  debugPrint('[STOCK-RESOLVE] Inventory rows fetched: ${inventoryRows.length}');
  for (final row in inventoryRows) {
    debugPrint('[STOCK-RESOLVE]   → size="${row['size']}", stock=${row['stock']}');
  }

  if (inventoryRows.isEmpty) {
    debugPrint('[STOCK-RESOLVE] ❌ No inventory rows found for this product');
    return -1;
  }

  if (cartSize.isEmpty) {
    debugPrint('[STOCK-RESOLVE] ❌ Cart size is empty — cannot match');
    return -1;
  }

  // 1) Exact match
  for (final row in inventoryRows) {
    if (row['size']?.toString() == cartSize) {
      final stock = row['stock'] as int;
      debugPrint('[STOCK-RESOLVE] ✅ Exact match: "${row['size']}" → stock=$stock');
      return stock;
    }
  }

  // 2) Numeric match (strip "EU"/"US" prefix)
  final normalizedCart = normalizeSize(cartSize);
  debugPrint('[STOCK-RESOLVE] No exact match. Trying normalized: "$normalizedCart"');
  for (final row in inventoryRows) {
    final normalizedInv = normalizeSize(row['size']?.toString() ?? '');
    if (normalizedInv == normalizedCart) {
      final stock = row['stock'] as int;
      debugPrint('[STOCK-RESOLVE] ✅ Normalized match: "${row['size']}" (normalized: "$normalizedInv") → stock=$stock');
      return stock;
    }
  }

  // 3) NO fallback — return -1 (data bug, not something to paper over)
  debugPrint('[STOCK-RESOLVE] ❌ No match found for cart size "$cartSize" (normalized: "$normalizedCart")');
  debugPrint('[STOCK-RESOLVE] ❌ Available sizes: ${inventoryRows.map((r) => '"${r['size']}"').join(', ')}');
  return -1;
}
