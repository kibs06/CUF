import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Disk cache for the customer home feed — the P0 cold-open fix.
///
/// The home feed used to show a shimmer on EVERY open while
/// `ProductProvider.loadProducts()` + `BannerProvider.loadBanners()` re-ran
/// their full network fetches. This service persists the last good payloads
/// as JSON in [SharedPreferences] so providers can paint instantly from disk
/// (stale-while-revalidate) and refresh quietly in the background.
///
/// What is cached (public catalog data only — safe across accounts): the
/// first-page/all-stores product list, slimmed to grid fields (see
/// [slimProduct]) + the `units_sold` aggregation, and the banner rows.
/// Always stale-while-revalidate: every open repaints from disk, then the
/// network replaces it. Prices/stock from cache are for BROWSING only —
/// detail and checkout always revalidate from the network.
class CatalogCacheService {
  CatalogCacheService._();

  static final CatalogCacheService instance = CatalogCacheService._();

  static const String _catalogKeyPrefix = 'catalog_first_page_v1:';
  static const String _bannersKey = 'banners_v1';

  /// Grid/render fields the home feed actually reads. Raw `product_images`,
  /// `product_variants`, `product_color_images` and `stores` embeds are
  /// dropped — the mapped `images` and `store_name` already carry what the
  /// cards need, and detail screens re-fetch the full row via
  /// `fetchProductById`.
  ///
  /// Raw `inventory` is KEPT (slimmed to size/stock pairs): `totalStock`,
  /// `purchasableProducts` and `stockByEuSize` all read the raw relation,
  /// and dropping it would make every cached product read as out of stock.
  static Map<String, dynamic> slimProduct(Map<String, dynamic> p) {
    final images = p['images'];
    final sizes = p['sizes'];
    final tags = p['tags'];
    final inventory = p['inventory'];
    return {
      'id': p['id']?.toString(),
      'name': p['name'],
      'category': p['category'],
      'price': p['price'],
      'sale_price': p['sale_price'],
      'sale_starts_at': p['sale_starts_at']?.toString(),
      'sale_ends_at': p['sale_ends_at']?.toString(),
      'avg_rating': p['avg_rating'],
      'review_count': p['review_count'],
      'units_sold': p['units_sold'] ?? 0,
      'audience': p['audience']?.toString(),
      'collection': p['collection'],
      'is_featured': p['is_featured'],
      'is_published': p['is_published'],
      'store_id': p['store_id']?.toString(),
      'store_name': p['store_name'],
      'description': p['description'],
      'images': images is List
          ? List<String>.from(images.map((e) => '$e'))
          : const <String>[],
      'inventory': inventory is List
          ? List<Map<String, dynamic>>.from(
              inventory.whereType<Map>().map(
                (row) => {
                  'size': row['size']?.toString() ?? '',
                  'stock': (row['stock'] as num?)?.toInt() ?? 0,
                },
              ),
            )
          : const <Map<String, dynamic>>[],
      'sizes': sizes is Map
          ? Map<String, int>.fromEntries(
              sizes.entries.map(
                (e) => MapEntry('${e.key}', (e.value as num?)?.toInt() ?? 0),
              ),
            )
          : const <String, int>{},
      if (tags is List) 'tags': List<String>.from(tags.map((e) => '$e')),
    };
  }

  String _catalogKey({required bool hideOutOfStock}) =>
      '$_catalogKeyPrefix${hideOutOfStock ? 'hideOOS' : 'all'}';

  /// Persist the last good catalog payload. Fire-and-forget from callers —
  /// never blocks the UI thread on the write.
  Future<void> saveCatalog({
    required bool hideOutOfStock,
    required List<Map<String, dynamic>> products,
    required Map<String, int> unitsSold,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'products': products.map(slimProduct).toList(),
        'unitsSold': unitsSold,
      };
      await prefs.setString(
        _catalogKey(hideOutOfStock: hideOutOfStock),
        jsonEncode(payload),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[CatalogCache] saveCatalog failed: $e');
    }
  }

  /// The last saved catalog, or null when nothing was cached or the payload
  /// no longer decodes.
  Future<({List<Map<String, dynamic>> products, Map<String, int> unitsSold})?>
  loadCatalog({required bool hideOutOfStock}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_catalogKey(hideOutOfStock: hideOutOfStock));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final products = (decoded['products'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (products.isEmpty) return null;
      final unitsRaw = decoded['unitsSold'];
      final unitsSold = unitsRaw is Map
          ? Map<String, int>.fromEntries(
              unitsRaw.entries.map(
                (e) => MapEntry('${e.key}', (e.value as num?)?.toInt() ?? 0),
              ),
            )
          : <String, int>{};
      return (products: products, unitsSold: unitsSold);
    } catch (e) {
      if (kDebugMode) debugPrint('[CatalogCache] loadCatalog failed: $e');
      return null;
    }
  }

  Future<void> saveBanners(List<Map<String, dynamic>> banners) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_bannersKey, jsonEncode({'banners': banners}));
    } catch (e) {
      if (kDebugMode) debugPrint('[CatalogCache] saveBanners failed: $e');
    }
  }

  Future<({List<Map<String, dynamic>> banners})?> loadBanners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bannersKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final banners = (decoded['banners'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return banners.isEmpty ? null : (banners: banners);
    } catch (e) {
      if (kDebugMode) debugPrint('[CatalogCache] loadBanners failed: $e');
      return null;
    }
  }
}
