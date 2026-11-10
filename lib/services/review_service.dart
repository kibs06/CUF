import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Totals + the viewer's own vote for one review's helpfulness buttons.
class ReviewVoteSummary {
  final int helpful;
  final int notHelpful;

  /// The current user's vote: true = helpful, false = not helpful,
  /// null = no vote (or signed out).
  final bool? myVote;

  const ReviewVoteSummary({
    required this.helpful,
    required this.notHelpful,
    required this.myVote,
  });

  factory ReviewVoteSummary.empty() =>
      const ReviewVoteSummary(helpful: 0, notHelpful: 0, myVote: null);
}

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

  /// Pinned reviews first, then newest. Sorted client-side (not via
  /// `.order('is_pinned')`) so the list keeps working against a database
  /// that has not applied the pin migration yet — a server-side order on
  /// a missing column fails the whole query and would hide every review.
  static int _pinnedFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ap = a['is_pinned'] == true ? 0 : 1;
    final bp = b['is_pinned'] == true ? 0 : 1;
    if (ap != bp) return ap.compareTo(bp);
    final ac = a['created_at']?.toString() ?? '';
    final bc = b['created_at']?.toString() ?? '';
    return bc.compareTo(ac);
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

      final list = (data as List).map((row) {
        final map = _normalizeOrderItemReview(row);
        return map;
      }).toList();
      list.sort(_pinnedFirst);
      return list;
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

      final list =
          (data as List).map((row) => _normalizeOrderItemReview(row)).toList();
      list.sort(_pinnedFirst);
      return list;
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

    // Tell the seller (bell row + push, fire-and-forget — never fail the
    // submit for a notification that did not land).
    unawaited(
      _notifySellerNewReview(
        storeId: storeId,
        productId: productId,
        rating: rating,
        comment: comment,
        reviewId: reviewId,
      ),
    );
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

    // Tell the customer (bell row + push, fire-and-forget).
    unawaited(_notifyCustomerReply(reviewId: reviewId, reply: reply.trim()));
  }

  // ═══════════════════════════════════════════════════════════════
  //  HELPFULNESS VOTES (review_votes table — thumbs up / down)
  // ═══════════════════════════════════════════════════════════════

  /// Totals + the current user's vote for one review.
  Future<ReviewVoteSummary> getReviewVote(String reviewId) async {
    if (reviewId.isEmpty) return ReviewVoteSummary.empty();
    try {
      final rows = await _client
          .from('review_votes')
          .select('user_id,is_helpful')
          .eq('review_id', reviewId);
      final uid = _client.auth.currentUser?.id;
      var helpful = 0;
      var notHelpful = 0;
      bool? mine;
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['is_helpful'] == true) {
          helpful++;
        } else {
          notHelpful++;
        }
        if (uid != null && map['user_id']?.toString() == uid) {
          mine = map['is_helpful'] == true;
        }
      }
      return ReviewVoteSummary(
        helpful: helpful,
        notHelpful: notHelpful,
        myVote: mine,
      );
    } catch (_) {
      return ReviewVoteSummary.empty();
    }
  }

  /// Cast or change the current user's vote on a review.
  Future<void> voteReview({
    required String reviewId,
    required bool isHelpful,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('review_votes').upsert(
      {
        'review_id': reviewId,
        'user_id': userId,
        'is_helpful': isHelpful,
      },
      onConflict: 'review_id,user_id',
    );

    // A helpful vote tells the author someone valued their words (bell row
    // + push, fire-and-forget). "Not helpful" stays silent, and voting on
    // your own review never notifies.
    if (isHelpful) {
      unawaited(
        _notifyAuthorHelpful(reviewId: reviewId, voterId: userId),
      );
    }
  }

  /// Pin (or unpin) a review as the product's spotlight. Pinning one review
  /// unpins the product's previous pin first — the partial unique index
  /// `uq_reviews_pinned_per_product` makes a double-pin impossible even
  /// under a race. The DB trigger `guard_review_pin` refuses non-sellers.
  Future<void> setReviewPinned({
    required String reviewId,
    required String productId,
    required bool pinned,
  }) async {
    if (pinned) {
      await _client
          .from('reviews')
          .update({'is_pinned': false})
          .eq('product_id', productId)
          .eq('is_pinned', true)
          .neq('id', reviewId);
    }
    await _client
        .from('reviews')
        .update({'is_pinned': pinned})
        .eq('id', reviewId);
  }

  /// Remove the current user's vote on a review (tapping the active vote).
  Future<void> removeVote(String reviewId) async {
    final userId = _client.auth.currentUser!.id;
    await _client
        .from('review_votes')
        .delete()
        .eq('review_id', reviewId)
        .eq('user_id', userId);
  }

  // ═══════════════════════════════════════════════════════════════
  //  REVIEW EVENT NOTIFICATIONS (bell row + push, fire-and-forget)
  //
  //  The row is the fact (lands on the bell the recipient actually
  //  reads: seller_notifications for sellers, notifications for
  //  customers); the push is the wake-up for a backgrounded app.
  //  None of these may ever throw — a notification must not fail the
  //  review, reply, or vote that already succeeded.
  // ═══════════════════════════════════════════════════════════════

  Future<String> _reviewProductName(String productId) async {
    try {
      final row = await _client
          .from('products')
          .select('name')
          .eq('id', productId)
          .maybeSingle();
      final name = row?['name']?.toString().trim() ?? '';
      return name.isEmpty ? 'your product' : name;
    } catch (_) {
      return 'your product';
    }
  }

  /// Seller bell + push when one of their products gets reviewed.
  Future<void> _notifySellerNewReview({
    required String storeId,
    required String productId,
    required int rating,
    String? comment,
    required String reviewId,
  }) async {
    try {
      final productName = await _reviewProductName(productId);
      final snippet = (comment ?? '').trim();
      final short = snippet.length > 90
          ? '${snippet.substring(0, 90)}…'
          : snippet;
      final title = 'New $rating★ review — $productName';
      final body = short.isEmpty
          ? 'A customer rated $productName $rating out of 5. Tap to read.'
          : '$rating★: "$short"';

      await _client.from('seller_notifications').insert({
        'store_id': storeId,
        'type': 'new_review',
        'title': title,
        'body': body,
        'reference_id': reviewId,
        'metadata': {
          'product_id': productId,
          'kind': 'new_review',
          'rating': rating,
          'snippet': short,
          'product_name': productName,
        },
      });

      final store = await _client
          .from('stores')
          .select('owner_id')
          .eq('id', storeId)
          .maybeSingle();
      final ownerId = store?['owner_id']?.toString();
      if (ownerId == null || ownerId.isEmpty) return;

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': ownerId,
        'title': title,
        'body': '$body Tap to view.',
        'type': 'new_review',
        'referenceId': storeId,
        'screen': 'seller_reviews',
      });
    } catch (e) {
      debugPrint('[ReviewService] New-review notify failed (non-fatal): $e');
    }
  }

  /// Customer bell + push when the seller replies to their review.
  Future<void> _notifyCustomerReply({
    required String reviewId,
    required String reply,
  }) async {
    try {
      final row = await _client
          .from('reviews')
          .select('customer_id, product_id, rating, comment, products(name)')
          .eq('id', reviewId)
          .maybeSingle();
      if (row == null) return;
      final customerId = row['customer_id']?.toString() ?? '';
      final productId = row['product_id']?.toString() ?? '';
      if (customerId.isEmpty || productId.isEmpty) return;
      final product = row['products'];
      final productName = product is Map
          ? (product['name']?.toString() ?? 'your item')
          : 'your item';
      final rating = (row['rating'] as num?)?.toInt() ?? 0;

      final short =
          reply.length > 90 ? '${reply.substring(0, 90)}…' : reply;
      final title = 'The seller replied to your review';
      final body = '"$short" — on $productName. Tap to view.';

      await _client.from('notifications').insert({
        'user_id': customerId,
        'category': 'review',
        'title': title,
        'message': body,
        'is_read': false,
        'is_deleted': false,
        'metadata': {
          'product_id': productId,
          'review_id': reviewId,
          'kind': 'reply',
          'rating': rating,
          'snippet': short,
          'product_name': productName,
        },
      });

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': customerId,
        'title': title,
        'body': body,
        'type': 'review_reply',
        'referenceId': productId,
        'screen': 'product_detail',
      });
    } catch (e) {
      debugPrint('[ReviewService] Reply notify failed (non-fatal): $e');
    }
  }

  /// Author bell + push when someone marks their review helpful.
  Future<void> _notifyAuthorHelpful({
    required String reviewId,
    required String voterId,
  }) async {
    try {
      final row = await _client
          .from('reviews')
          .select('customer_id, product_id, rating, comment, products(name)')
          .eq('id', reviewId)
          .maybeSingle();
      if (row == null) return;
      final authorId = row['customer_id']?.toString() ?? '';
      final productId = row['product_id']?.toString() ?? '';
      if (authorId.isEmpty || authorId == voterId || productId.isEmpty) {
        return;
      }
      final product = row['products'];
      final productName = product is Map
          ? (product['name']?.toString() ?? 'your review')
          : 'your review';
      final rating = (row['rating'] as num?)?.toInt() ?? 0;
      final comment = (row['comment']?.toString() ?? '').trim();
      final snippet = comment.length > 90
          ? '${comment.substring(0, 90)}…'
          : comment;

      final title = 'Someone found your review helpful';
      final body = 'Your review on $productName got a thumbs up. Tap to view.';

      await _client.from('notifications').insert({
        'user_id': authorId,
        'category': 'review',
        'title': title,
        'message': body,
        'is_read': false,
        'is_deleted': false,
        'metadata': {
          'product_id': productId,
          'review_id': reviewId,
          'kind': 'helpful',
          'rating': rating,
          'snippet': snippet,
          'product_name': productName,
        },
      });

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': authorId,
        'title': title,
        'body': body,
        'type': 'review_helpful',
        'referenceId': productId,
        'screen': 'product_detail',
      });
    } catch (e) {
      debugPrint('[ReviewService] Helpful-vote notify failed (non-fatal): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  REVIEW DISCUSSION THREAD (review_comments — flat, newest last)
  //
  //  The review author can reply under the seller's reply, and any
  //  other signed-in customer can comment on the thread too. Demo
  //  reviews (is_demo, on-device only) never reach here — the thread
  //  widget stays hidden for them.
  // ═══════════════════════════════════════════════════════════════

  /// All comments on a review, oldest first, with author names.
  Future<List<Map<String, dynamic>>> getReviewComments(String reviewId) async {
    try {
      final data = await _client
          .from('review_comments')
          .select('*, profiles!user_id(full_name, avatar_url)')
          .eq('review_id', reviewId)
          .order('created_at', ascending: true);
      return (data as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        final profile = map['profiles'];
        map['author_name'] = profile is Map
            ? (profile['full_name'] ?? 'Customer')
            : 'Customer';
        map['author_avatar'] =
            profile is Map ? profile['avatar_url'] : null;
        return map;
      }).toList();
    } catch (e) {
      debugPrint('[ReviewService] getReviewComments failed: $e');
      return [];
    }
  }

  /// Post a comment on a review as the current user. Notifies the review
  /// author (unless it's their own comment) and the seller — both
  /// fire-and-forget, never throwing.
  Future<bool> addReviewComment({
    required String reviewId,
    required String text,
  }) async {
    final userId = _client.auth.currentUser?.id;
    final trimmed = text.trim();
    if (userId == null || trimmed.isEmpty) return false;
    try {
      await _client.from('review_comments').insert({
        'review_id': reviewId,
        'user_id': userId,
        'comment': trimmed.length > 500
            ? trimmed.substring(0, 500)
            : trimmed,
      });
      unawaited(_notifyAuthorComment(reviewId: reviewId, commenterId: userId));
      unawaited(_notifySellerComment(reviewId: reviewId, commenterId: userId));
      return true;
    } catch (e) {
      debugPrint('[ReviewService] addReviewComment failed: $e');
      return false;
    }
  }

  /// Author bell + push when someone comments on their review thread.
  Future<void> _notifyAuthorComment({
    required String reviewId,
    required String commenterId,
  }) async {
    try {
      final row = await _client
          .from('reviews')
          .select('customer_id, product_id, rating, comment, products(name)')
          .eq('id', reviewId)
          .maybeSingle();
      if (row == null) return;
      final authorId = row['customer_id']?.toString() ?? '';
      final productId = row['product_id']?.toString() ?? '';
      if (authorId.isEmpty || authorId == commenterId || productId.isEmpty) {
        return;
      }
      final product = row['products'];
      final productName = product is Map
          ? (product['name']?.toString() ?? 'your review')
          : 'your review';
      final rating = (row['rating'] as num?)?.toInt() ?? 0;

      final title = 'New reply on your review';
      final body = 'Someone commented on your review of $productName. Tap to join.';

      await _client.from('notifications').insert({
        'user_id': authorId,
        'category': 'review',
        'title': title,
        'message': body,
        'is_read': false,
        'is_deleted': false,
        'metadata': {
          'product_id': productId,
          'review_id': reviewId,
          'kind': 'comment',
          'rating': rating,
          'snippet': body,
          'product_name': productName,
        },
      });

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': authorId,
        'title': title,
        'body': body,
        'type': 'review_comment',
        'referenceId': productId,
        'screen': 'product_detail',
      });
    } catch (e) {
      debugPrint('[ReviewService] Comment notify failed (non-fatal): $e');
    }
  }

  /// Seller bell + push when a review thread on their store gets a comment.
  Future<void> _notifySellerComment({
    required String reviewId,
    required String commenterId,
  }) async {
    try {
      final row = await _client
          .from('reviews')
          .select('store_id, product_id, rating, comment')
          .eq('id', reviewId)
          .maybeSingle();
      if (row == null) return;
      final storeId = row['store_id']?.toString() ?? '';
      final productId = row['product_id']?.toString() ?? '';
      if (storeId.isEmpty || productId.isEmpty) return;
      final productName = await _reviewProductName(productId);
      final rating = (row['rating'] as num?)?.toInt() ?? 0;
      final snippet = (row['comment']?.toString() ?? '').trim();
      final short = snippet.length > 90
          ? '${snippet.substring(0, 90)}…'
          : snippet;

      final title = 'New reply on a review — $productName';
      final body = short.isEmpty
          ? 'A customer joined the discussion. Tap to read.'
          : 'Discussion on "$short"';

      await _client.from('seller_notifications').insert({
        'store_id': storeId,
        'type': 'review_comment',
        'title': title,
        'body': body,
        'reference_id': reviewId,
        'metadata': {
          'product_id': productId,
          'kind': 'review_comment',
          'rating': rating,
          'snippet': short,
          'product_name': productName,
        },
      });

      final store = await _client
          .from('stores')
          .select('owner_id')
          .eq('id', storeId)
          .maybeSingle();
      final ownerId = store?['owner_id']?.toString();
      if (ownerId == null || ownerId.isEmpty || ownerId == commenterId) return;

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': ownerId,
        'title': title,
        'body': '$body Tap to view.',
        'type': 'review_comment',
        'referenceId': storeId,
        'screen': 'seller_reviews',
      });
    } catch (e) {
      debugPrint(
          '[ReviewService] Seller-comment notify failed (non-fatal): $e');
    }
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
  //  STORE-LEVEL REVIEWS (store_reviews table — direct "Rate this store")
  // ═══════════════════════════════════════════════════════════════

  /// All direct store reviews for a store, joined with reviewer profiles.
  Future<List<Map<String, dynamic>>> getStoreLevelReviews(String storeId) async {
    try {
      final data = await _client
          .from('store_reviews')
          .select('*, profiles!customer_id(full_name, avatar_url)')
          .eq('store_id', storeId)
          .order('created_at', ascending: false);

      return (data as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        final profile = map['profiles'];
        if (profile is Map) {
          map['reviewer_name'] = profile['full_name'] ?? 'Customer';
          map['reviewer_avatar'] = profile['avatar_url'];
        } else {
          map['reviewer_name'] = 'Customer';
          map['reviewer_avatar'] = null;
        }
        return map;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// The current user's direct store review for a store (or null).
  Future<Map<String, dynamic>?> getMyStoreReview(String storeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final data = await _client
          .from('store_reviews')
          .select('*, profiles!customer_id(full_name, avatar_url)')
          .eq('store_id', storeId)
          .eq('customer_id', userId)
          .maybeSingle();

      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        final profile = map['profiles'];
        map['reviewer_name'] =
            profile is Map ? (profile['full_name'] ?? 'Customer') : 'Customer';
        map['reviewer_avatar'] =
            profile is Map ? profile['avatar_url'] : null;
        return map;
      }
    } catch (_) {
      // Not found or RLS-blocked — treat as "no review" and return null.
    }

    return null;
  }

  /// Whether the current user can rate a store: verified buyer (has a
  /// 'received' order from this store) and hasn't already reviewed it.
  Future<bool> canReviewStore(String storeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      // Already reviewed? The UNIQUE(store_id, customer_id) also blocks
      // duplicate inserts at the DB level.
      final existing = await _client
          .from('store_reviews')
          .select('id')
          .eq('store_id', storeId)
          .eq('customer_id', userId)
          .maybeSingle();
      if (existing != null) return false;

      // Must have a completed ('received') order from this store.
      final orders = await _client
          .from('orders')
          .select('id')
          .eq('customer_id', userId)
          .eq('store_id', storeId)
          .eq('status', 'received')
          .limit(1);
      return (orders as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Submit a direct store review (1-5 stars + optional comment).
  Future<void> submitStoreReview({
    required String storeId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser!.id;
    if (rating < 1 || rating > 5) {
      throw Exception('Store review rating must be 1–5, got $rating');
    }

    await _client.from('store_reviews').insert({
      'store_id': storeId,
      'customer_id': userId,
      'rating': rating,
      'comment': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
    });
  }

  /// Update the current user's store review.
  Future<void> updateStoreReview({
    required String reviewId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser!.id;

    final existing = await _client
        .from('store_reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only edit your own store reviews.');
    }

    await _client.from('store_reviews').update({
      'rating': rating,
      'comment': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
    }).eq('id', reviewId);
  }

  /// Delete the current user's store review.
  Future<void> deleteStoreReview(String reviewId) async {
    final userId = _client.auth.currentUser!.id;

    final existing = await _client
        .from('store_reviews')
        .select('customer_id')
        .eq('id', reviewId)
        .single();
    if (existing['customer_id'] != userId) {
      throw Exception('You can only delete your own store reviews.');
    }

    await _client.from('store_reviews').delete().eq('id', reviewId);
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

    unawaited(
      _notifySellerNewReview(
        storeId: storeId,
        productId: trimmedProductId,
        rating: rating,
        comment: body,
        reviewId: reviewId,
      ),
    );
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
        // Ignore per-image failures so one bad file doesn't abort the rest.
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
    } catch (_) {
      // Best-effort cleanup — never throw for missing/deleted files.
    }
  }
}
