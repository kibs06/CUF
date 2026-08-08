import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/review_provider.dart';
import '../../widgets/sole_star_rating.dart';

/// Screen for writing or editing a DIRECT store review ("Rate this store").
///
/// Separate from product/order-item reviews: one review per customer per
/// store, 1-5 stars + optional comment. Verified-buyer eligibility is
/// enforced by the DB (RLS) and surfaced via `ReviewProvider.canReviewStore`.
///
/// Modes:
/// 1. New review — pass [storeId] + [storeName]
/// 2. Edit — pass [existingReview] (map with id, rating, comment)
class RateStoreScreen extends StatefulWidget {
  final String storeId;
  final String storeName;

  /// Existing review to edit (null = new review).
  final Map<String, dynamic>? existingReview;

  const RateStoreScreen({
    super.key,
    required this.storeId,
    required this.storeName,
    this.existingReview,
  });

  @override
  State<RateStoreScreen> createState() => _RateStoreScreenState();
}

class _RateStoreScreenState extends State<RateStoreScreen> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  bool get _isEditing => widget.existingReview != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final review = widget.existingReview!;
      final rawRating = review['rating'];
      _rating = rawRating is int
          ? rawRating
          : (rawRating is num
              ? rawRating.toInt()
              : int.tryParse(rawRating?.toString() ?? '') ?? 0);
      _commentController.text = review['comment']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating'),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final reviewProvider = Provider.of<ReviewProvider>(context, listen: false);
    final comment = _commentController.text.trim();
    bool success;

    if (_isEditing) {
      success = await reviewProvider.updateStoreReview(
        reviewId: widget.existingReview!['id'].toString(),
        storeId: widget.storeId,
        rating: _rating,
        comment: comment,
      );
    } else {
      success = await reviewProvider.submitStoreReview(
        storeId: widget.storeId,
        rating: _rating,
        comment: comment,
      );
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Review updated!' : 'Thanks for rating this store!'),
            backgroundColor: AppConstants.success,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        final error = reviewProvider.errorMessage ?? 'Something went wrong';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppConstants.error,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Store Review' : 'Rate this Store',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Store name
            Text(
              widget.storeName,
              style: AppConstants.headlineStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _isEditing
                  ? 'Update your rating for this store.'
                  : 'Share your experience with this store and its artisan.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),

            // Star rating selector
            _buildStarRating(),
            const SizedBox(height: 20),

            // Comment field (optional)
            Text(
              'Your review (optional)',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'How was the store? Fast shipping, quality craftsmanship, friendly service?',
                hintStyle: AppConstants.bodyStyle(
                  color: AppConstants.secondary.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppConstants.borderGray.withValues(alpha: 0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppConstants.borderGray.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppConstants.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: AppConstants.bodyStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isSubmitting || _rating == 0) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  disabledBackgroundColor:
                      AppConstants.borderGray.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        _isEditing ? 'Update Review' : 'Submit Review',
                        style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        children: [
          Text(
            'How would you rate this store?',
            style: AppConstants.bodyStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          SoleStarRating(
            rating: _rating,
            size: 40,
            interactive: true,
            onRatingChanged: (rating) => setState(() => _rating = rating),
          ),
          if (_rating > 0) ...[
            const SizedBox(height: 8),
            Text(
              _ratingLabel(_rating),
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }
}
