import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/review_service.dart';

/// Provider for product reviews state.
///
/// Mirrors `ProductProvider` conventions: services throw exceptions,
/// providers catch and set `_errorMessage`, UI reads from getters.
///
/// Supports both per-product reviews and per-order-item reviews.
class ReviewProvider extends ChangeNotifier {
  final ReviewService _reviewService = ReviewService.instance;

  // ── Per-product state ────────────────────────────────────────
  List<Map<String, dynamic>> _reviews = [];
  Map<String, dynamic>? _myReview;
  Map<String, dynamic>? _ratingSummary;
  bool _isLoading = false;
  bool _canReview = false;
  String? _errorMessage;

  // ── Per-order-item state ─────────────────────────────────────
  List<Map<String, dynamic>> _orderItems = [];
  bool _isLoadingOrderItems = false;

  // ── Seller review state ──────────────────────────────────────
  List<Map<String, dynamic>> _storeReviews = [];
  bool _isLoadingStoreReviews = false;

  // ─── GETTERS ────────────────────────────────────────────────────

  List<Map<String, dynamic>> get reviews => _reviews;
  Map<String, dynamic>? get myReview => _myReview;
  Map<String, dynamic>? get ratingSummary => _ratingSummary;
  bool get isLoading => _isLoading;
  bool get canReview => _canReview;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> get orderItems => _orderItems;
  bool get isLoadingOrderItems => _isLoadingOrderItems;

  List<Map<String, dynamic>> get storeReviews => _storeReviews;
  bool get isLoadingStoreReviews => _isLoadingStoreReviews;

  double get avgRating {
    if (_ratingSummary == null) return 0.0;
    return (_ratingSummary!['avg_rating'] as num?)?.toDouble() ?? 0.0;
  }

  int get reviewCount {
    if (_ratingSummary == null) return 0;
    return (_ratingSummary!['review_count'] as num?)?.toInt() ?? 0;
  }

  Map<int, int> get breakdown {
    if (_ratingSummary == null) return {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final raw = _ratingSummary!['breakdown'] as Map? ?? {};
    return {
      for (var entry in raw.entries)
        int.parse(entry.key.toString()): (entry.value as num?)?.toInt() ?? 0,
    };
  }

  /// Count of items in the current order that haven't been reviewed yet.
  int get unreviwedItemCount =>
      _orderItems.where((item) => item['review'] == null).length;

  /// Whether all items in the current order have been reviewed.
  bool get allItemsReviewed =>
      _orderItems.isNotEmpty && _orderItems.every((item) => item['review'] != null);

  // ═══════════════════════════════════════════════════════════════
  //  PER-PRODUCT REVIEWS
  // ═══════════════════════════════════════════════════════════════

  /// Load all reviews, my review, can-review status, and rating summary
  /// for a product. Fires all queries in parallel.
  Future<void> loadReviews(String productId) async {
    // Guard: skip if productId is null/empty to prevent fetching ALL reviews
    if (productId.isEmpty) {
      _reviews = [];
      _myReview = null;
      _canReview = false;
      _ratingSummary = {'avg_rating': 0.0, 'review_count': 0, 'breakdown': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}};
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _reviewService.getReviews(productId),
        _reviewService.getMyReview(productId),
        _reviewService.canReview(productId),
        _reviewService.getRatingSummary(productId),
      ]);

      _reviews = results[0] as List<Map<String, dynamic>>;
      _myReview = results[1] as Map<String, dynamic>?;
      _canReview = results[2] as bool;
      _ratingSummary = results[3] as Map<String, dynamic>;
    } catch (e) {
      _errorMessage = 'Failed to load reviews: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Submit a new per-product review.
  Future<bool> submitReview({
    required String productId,
    required int rating,
    String? title,
    String? body,
    List<XFile>? images,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _reviewService.submitReview(
        productId: productId,
        rating: rating,
        title: title,
        body: body,
        images: images,
      );

      await loadReviews(productId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to submit review: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update an existing per-product review.
  Future<bool> updateReview({
    required String reviewId,
    required String productId,
    required int rating,
    String? title,
    String? body,
    List<XFile>? newImages,
    List<String>? removedImageIds,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _reviewService.updateReview(
        reviewId: reviewId,
        rating: rating,
        title: title,
        body: body,
        newImages: newImages,
        removedImageIds: removedImageIds,
      );

      await loadReviews(productId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update review: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete a per-product review.
  Future<bool> deleteReview({
    required String reviewId,
    required String productId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _reviewService.deleteReview(reviewId);
      await loadReviews(productId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete review: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  PER-ORDER-ITEM REVIEWS (Shopee/Lazada-style)
  // ═══════════════════════════════════════════════════════════════

  /// Load all items in an order with their review status.
  Future<void> loadOrderItems(String orderId) async {
    _isLoadingOrderItems = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _orderItems = await _reviewService.getOrderItemsWithReviewStatus(orderId);
    } catch (e) {
      _errorMessage = 'Failed to load order items: $e';
    }

    _isLoadingOrderItems = false;
    notifyListeners();
  }

  /// Submit a review for a specific order item.
  Future<bool> submitOrderItemReview({
    required String orderId,
    required String orderItemId,
    required String productId,
    required String storeId,
    required int rating,
    String? comment,
    List<XFile>? images,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _reviewService.submitOrderItemReview(
        orderId: orderId,
        orderItemId: orderItemId,
        productId: productId,
        storeId: storeId,
        rating: rating,
        comment: comment,
        images: images,
      );

      // Reload order items to pick up the new review
      await loadOrderItems(orderId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to submit review: $e';
      _isLoadingOrderItems = false;
      notifyListeners();
      return false;
    }
  }

  /// Update an existing per-order-item review.
  Future<bool> updateOrderItemReview({
    required String reviewId,
    required String orderId,
    required int rating,
    String? comment,
    List<XFile>? newImages,
    List<String>? removedImageIds,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _reviewService.updateOrderItemReview(
        reviewId: reviewId,
        rating: rating,
        comment: comment,
        newImages: newImages,
        removedImageIds: removedImageIds,
      );

      await loadOrderItems(orderId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update review: $e';
      _isLoadingOrderItems = false;
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  SELLER REVIEWS
  // ═══════════════════════════════════════════════════════════════

  /// Load all reviews for the seller's store.
  Future<void> loadStoreReviews(String storeId) async {
    _isLoadingStoreReviews = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _storeReviews = await _reviewService.getStoreReviews(storeId);
    } catch (e) {
      _errorMessage = 'Failed to load reviews: $e';
    }

    _isLoadingStoreReviews = false;
    notifyListeners();
  }

  /// Seller reply to a review.
  Future<bool> sellerReply({
    required String reviewId,
    required String reply,
    String? storeId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _reviewService.sellerReply(reviewId: reviewId, reply: reply);

      // Reload store reviews if we have a store ID
      if (storeId != null) {
        await loadStoreReviews(storeId);
      }
      return true;
    } catch (e) {
      _errorMessage = 'Failed to post reply: $e';
      _isLoadingStoreReviews = false;
      notifyListeners();
      return false;
    }
  }

  // ─── RESET ──────────────────────────────────────────────────────

  /// Clear state when navigating away from a product.
  void reset() {
    _reviews = [];
    _myReview = null;
    _ratingSummary = null;
    _canReview = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear order-item review state.
  void resetOrderItems() {
    _orderItems = [];
    _errorMessage = null;
    notifyListeners();
  }
}
