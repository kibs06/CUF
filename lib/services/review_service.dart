import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service handling all review Supabase operations.
///
/// Supports two review models:
/// 1. **Per-product reviews** (`product_reviews` table) — legacy from initial implementation
/// 2. **Per-order-item reviews** (`reviews` table) — Shopee/Lazada-style (primary going forward)
///
/// Screens should call this service — never Supabase directly.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Cached flag: set to false after first 404 on product_reviews table.
  /// Prevents wasteful HTTP requests to a table that doesn't exist.
  static bool _productReviewsExists = true;

  // ═══════════════════════════════════════════════════════════════
  //  PER-PRODUCT REVIEWS (product_reviews table — legacy)
  // ═══════════════════════════════════════════════════════════════

  /// Fetch all reviews for a product, joined with reviewer profile + images.
  /// Reads from BOTH `product_reviews` (legacy) and `reviews` (new) tables.
  Future<List<Map<String, dynamic>>> getReviews(String productId) async {
    // Fetch from both tables in parallel
    final results = await Future.wait([
      _fetchProductReviews(productId),
      _fetchOrderItemReviews(productId),
    ]);

    final allReviews = [...results[0], ...results[1]];
    // Sort by created_at DESC (most recent first)
    allReviews.sort((a, b) {
      final aDate = a['created_at']?.toString() ?? '';
      final bDate = b['created_at']?.toString() ?? '';
      return bDate.compareTo(aDate);
    });

    return allReviews;
  }

  Future<List<Map<String, dynamic>>> _fetchProductReviews(String productId) async {
    // product_reviews is a legacy table that may not exist in all environments.
    // Return empty list if the table is missing — all reviews live in the
    // 'reviews' table (Shopee/Lazada-style) going forward.
    if (!_productReviewsExists) return [];

    try {
      final data = await _client
          .from('product_reviews')
          .select('''
            *,
            profiles!customer_id(full_name, avatar_url),
            product_review_images(id, image_url, display_order)
          ''')
          .eq('product_id', productId)
          .order('created_at', ascending: false);

      return (data as List).map((row) {
        final map = _normalizeProductReview(row);
        map['_source'] = 'product_reviews';
        return map;
      }).toList();
    } catch (e) {
      // Table doesn't exist — cache this fact and skip future queries.
      _productReviewsExists = false;
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItemReviews(String productId) async {
    try {
      // reviews.product_id is UUID; products.id is TEXT in some environments.
      // Ensure we pass a clean string UUID for the filter to match.
      final data = await _client
          .from('reviews')
          .select('''
            *,
            profiles!customer_id(full_name, avatar_url),
            review_images(id, image_url, display_order)
          ''')
          .eq('product_id', productId.trim())
          .order('created_at', ascending: false);

      return (data as List).map((row) {
        final map = _normalizeOrderItemReview(row);
        map['_source'] = 'reviews';
        return map;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch the current user's review for a product (or null).
  /// Checks both tables.
  Future<Map<String, dynamic>?> getMyReview(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final trimmedId = productId.trim();

    // Check reviews table first (Shopee/Lazada-style)
    try {
      final data = await _client
          .from('reviews')
          .select('''
            *,
            review_images(id, image_url, display_order)
          ''')
          .eq('product_id', trimmedId)
          .eq('customer_id', userId)
          .maybeSingle();

      if (data != null) return _normalizeOrderItemReview(data);
    } catch (_) {}

    // Fall back to product_reviews (legacy, may not exist)
    if (_productReviewsExists) {
      try {
        final data = await _client
            .from('product_reviews')
            .select('''
              *,
              product_review_images(id, image_url, display_order)
            ''')
            .eq('product_id', trimmedId)
            .eq('customer_id', userId)
            .maybeSingle();

        if (data != null) return _normalizeProductReview(data);
      } catch (_) {
        _productReviewsExists = false;
      }
    }

    return null;
  }

  /// Check if the current user can review a product.
  Future<bool> canReview(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final trimmedId = productId.trim();

    // Check if already reviewed in reviews table
    try {
      final existingNew = await _client
          .from('reviews')
          .select('id')
          .eq('product_id', trimmedId)
          .eq('customer_id', userId)
          .maybeSingle();
      if (existingNew != null) return false;
    } catch (_) {}

    // Check if already reviewed in product_reviews (legacy, may not exist)
    if (_productReviewsExists) {
      try {
        final existingLegacy = await _client
            .from('product_reviews')
            .select('id')
            .eq('product_id', trimmedId)
            .eq('customer_id', userId)
            .maybeSingle();
        if (existingLegacy != null) return false;
      } catch (_) {
        _productReviewsExists = false;
      }
    }

    // Check if user has a completed order containing this product
    final orders = await _client
        .from('orders')
        .select('id')
        .eq('customer_id', userId)
        .inFilter('status', ['ready', 'received']);

    if (orders.isEmpty) return false;

    final orderIds = (orders as List).map((o) => o['id']).toList();
    final orderItem = await _client
        .from('order_items')
        .select('id')
        .eq('product_id', trimmedId)
        .inFilter('order_id', orderIds)
        .limit(1)
        .maybeSingle();

    return orderItem != null;
  }

  /// Get rating summary for a product (combines both tables).
  Future<Map<String, dynamic>> getRatingSummary(String productId) async {
    final reviews = await getReviews(productId);

    int totalRating = 0;
    final breakdown = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

    for (final review in reviews) {
      final rating = (review['rating'] as num?)?.toInt() ?? 0;
      if (rating >= 1 && rating <= 5) {
        totalRating += rating;
        breakdown[rating] = (breakdown[rating] ?? 0) + 1;
      }
    }

    final count = reviews.length;
    final avgRating = count > 0 ? (totalRating / count).roundToDouble() : 0.0;

    return {
      'avg_rating': avgRating,
      'review_count': count,
      'breakdown': breakdown,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  PER-ORDER-ITEM REVIEWS (reviews table — Shopee/Lazada-style)
  // ═══════════════════════════════════════════════════════════════

  /// Fetch all reviews for a store (seller side).
  Future<List<Map<String, dynamic>>> getStoreReviews(String storeId) async {
    try {
      final data = await _client
          .from('reviews')
          .select('''
            *,
            profiles!customer_id(full_name, avatar_url),
            review_images(id, image_url, display_order),
            order_items!inner(product_id, size, quantity, products(name))
          ''')
          .eq('store_id', storeId)
          .order('created_at', ascending: false);

      return (data as List).map((row) => _normalizeOrderItemReview(row)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch all items in an order with their review status.
  /// Returns a list of order items, each with a `review` field (null if not reviewed).
  Future<List<Map<String, dynamic>>> getOrderItemsWithReviewStatus(String orderId) async {
    final data = await _client
        .from('order_items')
        .select('''
          id, product_id, size, quantity, unit_price,
          products(name, category, product_images(image_url, display_order))
        ''')
        .eq('order_id', orderId);

    final items = (data as List).map((row) => Map<String, dynamic>.from(row)).toList();

    if (items.isEmpty) return items;

    // Fetch existing reviews for these items
    final itemIds = items.map((i) => i['id']).toList();
    final existingReviews = await _client
        .from('reviews')
        .select('*, review_images(id, image_url, display_order)')
        .inFilter('order_item_id', itemIds);

    // Build a map of order_item_id → review
    final reviewMap = <String, Map<String, dynamic>>{};
    for (final row in (existingReviews as List)) {
      final map = Map<String, dynamic>.from(row);
      final normalized = _normalizeOrderItemReview(map);
      reviewMap[map['order_item_id'].toString()] = normalized;
    }

    // Attach review to each item
    for (final item in items) {
      item['review'] = reviewMap[item['id'].toString()];
      // Normalize product image
      final product = item['products'];
      if (product is Map) {
        item['product_name'] = product['name'] ?? '';
        final productImages = product['product_images'];
        if (productImages is List && productImages.isNotEmpty) {
          final sorted = List<Map<String, dynamic>>.from(
            productImages.map((e) => Map<String, dynamic>.from(e as Map)),
          )..sort((a, b) =>
              (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
          item['product_image_url'] = sorted.first['image_url']?.toString();
        }
      }
    }

    return items;
  }

  /// Submit a review for a specific order item.
  Future<void> submitOrderItemReview({
    required String orderId,
    required String orderItemId,
    required String productId,
    required String storeId,
    required int rating,
    String? comment,
    List<XFile>? images,
  }) async {
    final userId = _client.auth.currentUser!.id;

    final review = await _client
        .from('reviews')
        .insert({
          'order_id': orderId,
          'order_item_id': orderItemId,
          'product_id': productId,
          'customer_id': userId,
          'store_id': storeId,
          'rating': rating,
          'comment': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
        })
        .select()
        .single();

    final reviewId = review['id'].toString();

    // Upload images if any
    if (images != null && images.isNotEmpty) {
      await _uploadReviewImagesNew(reviewId: reviewId, images: images);
    }
  }

  /// Update an existing per-order-item review.
  Future<void> updateOrderItemReview({
    required String reviewId,
    required int rating,
    String? comment,
    List<XFile>? newImages,
    List<String>? removedImageIds,
  }) async {
    final userId = _client.auth.currentUser!.id;

    // Verify ownership
    final existing = await _client
        .from('reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only edit your own reviews.');
    }

    await _client.from('reviews').update({
      'rating': rating,
      'comment': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
    }).eq('id', reviewId);

    // Remove deleted images
    if (removedImageIds != null && removedImageIds.isNotEmpty) {
      for (final imageId in removedImageIds) {
        final img = await _client
            .from('review_images')
            .select('image_url')
            .eq('id', imageId)
            .maybeSingle();
        if (img != null) {
          await _removeStorageFile(img['image_url'] as String);
        }
        await _client.from('review_images').delete().eq('id', imageId);
      }
    }

    // Upload new images
    if (newImages != null && newImages.isNotEmpty) {
      await _uploadReviewImagesNew(reviewId: reviewId, images: newImages);
    }
  }

  /// Seller reply to a review.
  Future<void> sellerReply({
    required String reviewId,
    required String reply,
  }) async {
    await _client.from('reviews').update({
      'seller_reply': reply.trim(),
      'seller_reply_at': DateTime.now().toIso8601String(),
    }).eq('id', reviewId);
  }

  /// Delete a per-order-item review.
  Future<void> deleteOrderItemReview(String reviewId) async {
    final userId = _client.auth.currentUser!.id;

    final existing = await _client
        .from('reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only delete your own reviews.');
    }

    // Fetch images for storage cleanup
    final images = await _client
        .from('review_images')
        .select('image_url')
        .eq('review_id', reviewId);

    for (final img in (images as List)) {
      await _removeStorageFile(img['image_url'] as String);
    }

    // Delete review (cascades to review_images via FK)
    await _client.from('reviews').delete().eq('id', reviewId);
  }

  // ═══════════════════════════════════════════════════════════════
  //  LEGACY SUBMIT (product_reviews table)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitReview({
    required String productId,
    required int rating,
    String? title,
    String? body,
    List<XFile>? images,
  }) async {
    final userId = _client.auth.currentUser!.id;

    // Find a relevant order_id for this product
    String? orderId;
    try {
      final orders = await _client
          .from('orders')
          .select('id')
          .eq('customer_id', userId)
          .inFilter('status', ['ready', 'received']);
      if (orders.isNotEmpty) {
        final orderIds = (orders as List).map((o) => o['id']).toList();
        final orderItem = await _client
            .from('order_items')
            .select('order_id')
            .eq('product_id', productId)
            .inFilter('order_id', orderIds)
            .limit(1)
            .maybeSingle();
        orderId = orderItem?['order_id']?.toString();
      }
    } catch (_) {}

    final review = await _client
        .from('product_reviews')
        .insert({
          'product_id': productId,
          'customer_id': userId,
          'order_id': orderId,
          'rating': rating,
          'title': title?.trim().isNotEmpty == true ? title!.trim() : null,
          'body': body?.trim().isNotEmpty == true ? body!.trim() : null,
          'is_verified': true,
        })
        .select()
        .single();

    final reviewId = review['id'] as int;

    if (images != null && images.isNotEmpty) {
      await _uploadReviewImages(reviewId: reviewId, images: images);
    }
  }

  Future<void> updateReview({
    required int reviewId,
    required int rating,
    String? title,
    String? body,
    List<XFile>? newImages,
    List<int>? removedImageIds,
  }) async {
    final userId = _client.auth.currentUser!.id;

    final existing = await _client
        .from('product_reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only edit your own reviews.');
    }

    await _client.from('product_reviews').update({
      'rating': rating,
      'title': title?.trim().isNotEmpty == true ? title!.trim() : null,
      'body': body?.trim().isNotEmpty == true ? body!.trim() : null,
    }).eq('id', reviewId);

    if (removedImageIds != null && removedImageIds.isNotEmpty) {
      for (final imageId in removedImageIds) {
        final img = await _client
            .from('product_review_images')
            .select('image_url')
            .eq('id', imageId)
            .maybeSingle();
        if (img != null) await _removeStorageFile(img['image_url'] as String);
        await _client.from('product_review_images').delete().eq('id', imageId);
      }
    }

    if (newImages != null && newImages.isNotEmpty) {
      await _uploadReviewImages(reviewId: reviewId, images: newImages);
    }
  }

  Future<void> deleteReview(int reviewId) async {
    final userId = _client.auth.currentUser!.id;

    final existing = await _client
        .from('product_reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only delete your own reviews.');
    }

    final images = await _client
        .from('product_review_images')
        .select('image_url')
        .eq('review_id', reviewId);

    for (final img in (images as List)) {
      await _removeStorageFile(img['image_url'] as String);
    }

    await _client.from('product_reviews').delete().eq('id', reviewId);
  }

  // ═══════════════════════════════════════════════════════════════
  //  NORMALIZATION HELPERS
  // ═══════════════════════════════════════════════════════════════

  Map<String, dynamic> _normalizeProductReview(dynamic row) {
    final map = Map<String, dynamic>.from(row as Map);
    final profile = map['profiles'];
    if (profile is Map) {
      map['reviewer_name'] = profile['full_name'] ?? 'Customer';
      map['reviewer_avatar'] = profile['avatar_url'];
    } else {
      map['reviewer_name'] = 'Customer';
      map['reviewer_avatar'] = null;
    }
    final images = map['product_review_images'];
    if (images is List) {
      map['review_images'] = images
          .map((img) => Map<String, dynamic>.from(img as Map))
          .toList()
        ..sort((a, b) =>
            (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
    } else {
      map['review_images'] = <Map<String, dynamic>>[];
    }
    // Ensure both 'body' and 'comment' are set for downstream consumers.
    // product_reviews table uses 'body'; reviews table uses 'comment'.
    map['comment'] ??= map['body'];
    map['body'] ??= map['comment'];
    return map;
  }

  Map<String, dynamic> _normalizeOrderItemReview(dynamic row) {
    final map = Map<String, dynamic>.from(row as Map);
    final profile = map['profiles'];
    if (profile is Map) {
      map['reviewer_name'] = profile['full_name'] ?? 'Customer';
      map['reviewer_avatar'] = profile['avatar_url'];
    } else {
      map['reviewer_name'] = 'Customer';
      map['reviewer_avatar'] = null;
    }
    final images = map['review_images'];
    if (images is List) {
      map['review_images'] = images
          .map((img) => Map<String, dynamic>.from(img as Map))
          .toList()
        ..sort((a, b) =>
            (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
    } else {
      map['review_images'] = <Map<String, dynamic>>[];
    }
    // Ensure both 'body' and 'comment' are set for downstream consumers.
    // reviews table uses 'comment'; product_reviews table uses 'body'.
    map['comment'] ??= map['body'];
    map['body'] ??= map['comment'];
    // Extract product name from nested join
    final items = map['order_items'];
    if (items is Map) {
      final product = items['products'];
      if (product is Map) {
        map['product_name'] = product['name'] ?? '';
      }
      map['item_size'] = items['size'];
      map['item_quantity'] = items['quantity'];
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════════════
  //  IMAGE UPLOAD HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// Upload images for the new `reviews` table.
  Future<void> _uploadReviewImagesNew({
    required String reviewId,
    required List<XFile> images,
  }) async {
    const bucketName = 'review-images';
    final customerId = _client.auth.currentUser!.id;
    final rows = <Map<String, dynamic>>[];

    for (int i = 0; i < images.length; i++) {
      try {
        final file = images[i];
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        final ext = file.path.split('.').last.toLowerCase();
        final safeExt = ext == 'jpg' ? 'jpeg' : ext;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '$customerId/$reviewId/${timestamp}_$i.$ext';

        await _client.storage.from(bucketName).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: 'image/$safeExt',
                upsert: true,
              ),
            );

        final url = _client.storage.from(bucketName).getPublicUrl(path);
        if (url.isNotEmpty) {
          rows.add({
            'review_id': reviewId,
            'image_url': url,
            'display_order': i,
          });
        }
      } catch (e) {
      }
    }

    if (rows.isNotEmpty) {
      await _client.from('review_images').insert(rows);
    }
  }

  /// Upload images for the legacy `product_reviews` table.
  Future<void> _uploadReviewImages({
    required int reviewId,
    required List<XFile> images,
  }) async {
    const bucketName = 'review-images';
    final customerId = _client.auth.currentUser!.id;
    final rows = <Map<String, dynamic>>[];

    for (int i = 0; i < images.length; i++) {
      try {
        final file = images[i];
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        final ext = file.path.split('.').last.toLowerCase();
        final safeExt = ext == 'jpg' ? 'jpeg' : ext;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '$customerId/$reviewId/${timestamp}_$i.$ext';

        await _client.storage.from(bucketName).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: 'image/$safeExt',
                upsert: true,
              ),
            );

        final url = _client.storage.from(bucketName).getPublicUrl(path);
        if (url.isNotEmpty) {
          rows.add({
            'review_id': reviewId,
            'image_url': url,
            'display_order': i,
          });
        }
      } catch (e) {
      }
    }

    if (rows.isNotEmpty) {
      await _client.from('product_review_images').insert(rows);
    }
  }

  /// Best-effort removal of a file from storage by its public URL.
  Future<void> _removeStorageFile(String url) async {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final bucketIndex = segments.indexOf('review-images');
      if (bucketIndex >= 0 && bucketIndex + 1 < segments.length) {
        final path = segments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from('review-images').remove([path]);
      }
    } catch (_) {}
  }
}
