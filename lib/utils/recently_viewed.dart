import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence helper for recently viewed products.
///
/// Stores a JSON array of lightweight product summaries in SharedPreferences,
/// capped at 20 items, most recent first. Follows the same pattern used for
/// `last_visited_store_id`/`last_visited_store_name` in CustomerHomeScreen.
class RecentlyViewedService {
  RecentlyViewedService._();
  static final RecentlyViewedService instance = RecentlyViewedService._();

  static const String _key = 'recently_viewed_products';
  static const int _maxItems = 20;

  /// Load recently viewed products from SharedPreferences.
  /// Returns a list of product summaries, most recent first.
  Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json == null || json.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(json);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Push a product to the front of the recently viewed list.
  /// Dedupes if already present, caps at [_maxItems].
  Future<void> pushProduct(Map<String, dynamic> product) async {
    final summary = {
      'id': product['id']?.toString() ?? '',
      'name': product['name']?.toString() ?? '',
      'price': product['price'] ?? 0,
      'imageUrl': _extractFirstImage(product),
    };

    final list = await load();

    // Remove existing entry for this product (dedupe)
    list.removeWhere((item) => item['id'] == summary['id']);

    // Insert at front
    list.insert(0, summary);

    // Cap at max
    if (list.length > _maxItems) {
      list.removeRange(_maxItems, list.length);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Extract the first product image URL from the product map.
  static String _extractFirstImage(Map<String, dynamic> product) {
    // Try product_images first (list of {image_url, display_order} maps)
    final raw = product['product_images'] as List? ?? [];
    if (raw.isNotEmpty && raw.first is Map) {
      final images = List<Map<String, dynamic>>.from(raw);
      images.sort((a, b) =>
          (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
      return images.first['image_url']?.toString() ?? '';
    }
    // Fall back to flat 'images' list
    final images = product['images'] as List? ?? [];
    if (images.isNotEmpty) return images.first.toString();
    return '';
  }
}