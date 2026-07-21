import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service handling all review Supabase operations.
///
/// Uses the `reviews` table (Shopee/Lazada-style per-order-item reviews)
/// and `review_images` table for photo attachments.
///
/// Screens should call this service — never Supabase directly.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Safe parsing helpers ──────────────────────────────────────
  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v != null) return int.parse(v.toString());
    return 0;
  }

  /// Fetch all reviews for a product, joined with reviewer profile + images.
  Future<List<Map<String, dynamic>>> getReviews(String productId) async {
    try {
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
        return map;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch the current user's review for a product (or null).
  Future<Map<String, dynamic>?> getMyReview(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final trimmedId = productId.trim();

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

    return null;
  }

  /// Check if the current user can review a product.
  Future<bool> canReview(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final trimmedId = productId.trim();

    // Check if already reviewed
    try {
      final existing = await _client
          .from('reviews')
          .select('id')
          .eq('product_id', trimmedId)
          .eq('customer_id', userId)
          .maybeSingle();
      if (existing != null) return false;
    } catch (_) {}

    // Check if user has a completed order containing this product
    final orders = await _client
        .from('orders')
        .select('id')
        .eq('customer_id', userId)
        .inFilter('status', ['ready', 'received', 'delivered']);

    if (orders.isEmpty) return false;

    final orderIds = (orders as List).map((o) => o["id"].toString()).toList();
    final orderItem = await _client
        .from('order_items')
        .select('id')
        .eq('product_id', trimmedId)
        .inFilter('order_id', orderIds)
        .limit(1)
        .maybeSingle();

    return orderItem != null;
  }

  /// Get rating summary for a product.
  Future<Map<String, dynamic>> getRatingSummary(String productId) async {
    final reviews = await getReviews(productId);

    int totalRating = 0;
    final breakdown = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

    for (final review in reviews) {
      final rating = _asInt(review['rating']);
      if (rating >= 1 && rating <= 5) {
        totalRating += rating;
        breakdown[rating] = (breakdown[rating] ?? 0) + 1;
      }
    }

    final count = reviews.length;
    final avgRating = count > 0 ? (totalRating / count * 100).roundToDouble() / 100 : 0.0;

    return {
      'avg_rating': avgRating,
      'review_count': count,
      'breakdown': breakdown,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  TYPED REVIEW PAYLOAD
  // ═══════════════════════════════════════════════════════════════

  /// Typed payload for review submission. Enforces correct types matching
  /// the real DB schema (see SCHEMA_REFERENCE.md).
  ///
  /// All UUID fields are [String] — never parsed as int.
  /// [productId] is TEXT (not UUID).
  /// [rating] is INT (1–5).
  static Map<String, dynamic> _buildReviewPayload({
    required String orderId,
    required String orderItemId,
    required String productId,
    required String customerId,
    required String storeId,
    required int rating,
    String? comment,
  }) {
    // ── Validate every required UUID is non-empty ────────────────
    final fields = <String, String>{
      'orderId': orderId,
      'orderItemId': orderItemId,
      'productId': productId,
      'customerId': customerId,
      'storeId': storeId,
    };
    for (final entry in fields.entries) {
      if (entry.value.isEmpty) {
        throw Exception(
          'submitReview: ${entry.key} is empty — cannot submit review. '
          'orderId=$orderId, orderItemId=$orderItemId, productId=$productId, '
          'storeId=$storeId',
        );
      }
    }
    if (rating < 1 || rating > 5) {
      throw Exception('submitReview: rating must be 1–5, got $rating');
    }

    return {
      'order_id': orderId,
      'order_item_id': orderItemId,
      'product_id': productId,
      'customer_id': customerId,
      'store_id': storeId,
      'rating': rating,
      'comment': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
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
              _asInt(a['display_order']).compareTo(_asInt(b['display_order'])));
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

    final payload = _buildReviewPayload(
      orderId: orderId,
      orderItemId: orderItemId,
      productId: productId,
      customerId: userId,
      storeId: storeId,
      rating: rating,
      comment: comment,
    );

    final review = await _client
        .from('reviews')
        .insert(payload)
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
  //  SUBMIT / UPDATE / DELETE (reviews table)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitReview({
    required String productId,
    required int rating,
    String? title,
    String? body,
    List<XFile>? images,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final trimmedProductId = productId.trim();

    if (trimmedProductId.isEmpty) {
      throw Exception(
        'submitReview: productId is empty — cannot submit review without a product.',
      );
    }

    // Find a relevant order_id and order_item_id for this product
    String? orderId;
    String? orderItemId;
    String? storeId;

    // Step 1: Fetch all orders for this customer in reviewable statuses.
    final orders = await _client
        .from('orders')
        .select()
        .eq('customer_id', userId)
        .inFilter('status', ['ready', 'received', 'delivered'])
        .order('created_at', ascending: false);

    if (orders.isNotEmpty) {
      // orders.id is UUID — keep as string, don't parse as int.
      final orderIds = (orders as List)
          .map((o) => o['id'].toString())
          .toList();

      // Step 2: Find the order_items row for this product within those orders.
      // The product_id column in order_items references products.id (TEXT).
      final orderItem = await _client
          .from('order_items')
          .select('id, order_id')
          .eq('product_id', trimmedProductId)
          .inFilter('order_id', orderIds)
          .limit(1)
          .maybeSingle();

      if (orderItem != null) {
        orderId = orderItem['order_id'].toString();
        orderItemId = orderItem['id'].toString();
      } else {
        // Debug: log what we searched for to help diagnose mismatches
        debugPrint('[ReviewService] submitReview: no order_item found for productId=$trimmedProductId in orders=$orderIds');
        // Second attempt: try without trim in case the original had no whitespace
        if (trimmedProductId != productId) {
          final orderItemRetry = await _client
              .from('order_items')
              .select('id, order_id')
              .eq('product_id', productId)
              .inFilter('order_id', orderIds)
              .limit(1)
              .maybeSingle();
          if (orderItemRetry != null) {
            orderId = orderItemRetry['order_id'].toString();
            orderItemId = orderItemRetry['id'].toString();
          }
        }
      }

      // Get store_id from the matched order
      if (orderId != null) {
        final order = (orders as List).firstWhere(
          (o) => o['id'].toString() == orderId,
          orElse: () => orders.first,
        );
        storeId = order['store_id']?.toString();
      }
    }

    if (orderItemId == null || orderId == null) {
      throw Exception(
        'Could not find a valid order item to review. '
        'Make sure you have a completed order containing this product.',
      );
    }

    if (storeId == null || storeId.isEmpty) {
      throw Exception(
        'submitReview: storeId is missing for order $orderId — cannot submit review.',
      );
    }

    final payload = _buildReviewPayload(
      orderId: orderId,
      orderItemId: orderItemId,
      productId: trimmedProductId,
      customerId: userId,
      storeId: storeId,
      rating: rating,
      comment: body,
    );

    final review = await _client
        .from('reviews')
        .insert(payload)
        .select()
        .single();

    final reviewId = review['id'].toString();

    if (images != null && images.isNotEmpty) {
      await _uploadReviewImagesNew(reviewId: reviewId, images: images);
    }
  }

  Future<void> updateReview({
    required String reviewId,
    required int rating,
    String? title,
    String? body,
    List<XFile>? newImages,
    List<String>? removedImageIds,
  }) async {
    final userId = _client.auth.currentUser!.id;

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
      'comment': body?.trim().isNotEmpty == true ? body!.trim() : null,
    }).eq('id', reviewId);

    if (removedImageIds != null && removedImageIds.isNotEmpty) {
      for (final imageId in removedImageIds) {
        final img = await _client
            .from('review_images')
            .select('image_url')
            .eq('id', imageId)
            .maybeSingle();
        if (img != null) await _removeStorageFile(img['image_url'] as String);
        await _client.from('review_images').delete().eq('id', imageId);
      }
    }

    if (newImages != null && newImages.isNotEmpty) {
      await _uploadReviewImagesNew(reviewId: reviewId, images: newImages);
    }
  }

  Future<void> deleteReview(String reviewId) async {
    final userId = _client.auth.currentUser!.id;

    final existing = await _client
        .from('reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only delete your own reviews.');
    }

    final images = await _client
        .from('review_images')
        .select('image_url')
        .eq('review_id', reviewId);

    for (final img in (images as List)) {
      await _removeStorageFile(img['image_url'] as String);
    }

    await _client.from('reviews').delete().eq('id', reviewId);
  }

  // ═══════════════════════════════════════════════════════════════
  //  NORMALIZATION HELPERS
  // ═══════════════════════════════════════════════════════════════

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
            _asInt(a['display_order']).compareTo(_asInt(b['display_order'])));
    } else {
      map['review_images'] = <Map<String, dynamic>>[];
    }
    // Ensure both 'body' and 'comment' aliases exist for downstream consumers.
    map['body'] ??= map['comment'];
    map['comment'] ??= map['body'];
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
