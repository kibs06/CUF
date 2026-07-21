import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_constants.dart';
import '../../providers/review_provider.dart';
import '../../widgets/sole_star_rating.dart';

/// Screen for writing or editing a product review.
///
/// Supports two modes:
/// 1. Per-product review (legacy) — pass [productId] + [productName]
/// 2. Per-order-item review (Shopee-style) — pass [orderItemId], [orderId], [storeId]
class WriteReviewScreen extends StatefulWidget {
  /// Product being reviewed.
  final String productId;
  final String productName;

  // ── Per-order-item review params (optional) ──────────────────
  /// When non-null, the review is scoped to a specific order item.
  final String? orderItemId;
  final String? orderId;
  final String? storeId;

  /// Existing review to edit (null = new review).
  final Map<String, dynamic>? existingReview;

  const WriteReviewScreen({
    super.key,
    required this.productId,
    required this.productName,
    this.orderItemId,
    this.orderId,
    this.storeId,
    this.existingReview,
  });

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  int _rating = 0;
  final _bodyController = TextEditingController();
  final List<XFile> _newImages = [];
  final List<Map<String, dynamic>> _existingImages = [];
  final List<String> _removedImageIds = [];
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();
  static const int _maxImages = 5;

  bool get _isEditing => widget.existingReview != null;
  bool get _isOrderItemReview => widget.orderItemId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final review = widget.existingReview!;
      final rawRating = review['rating'];
      _rating = rawRating is int ? rawRating : (rawRating is num ? rawRating.toInt() : int.tryParse(rawRating?.toString() ?? '') ?? 0);
      _bodyController.text = review['comment']?.toString() ??
          review['body']?.toString() ??
          '';
      final images = review['review_images'] as List? ?? [];
      for (final img in images) {
        if (img is Map) {
          _existingImages.add(Map<String, dynamic>.from(img));
        }
      }
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  int get _totalImageCount => _existingImages.length + _newImages.length;

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImageCount;
    if (remaining <= 0) return;

    try {
      final images = await _picker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (images.isNotEmpty) {
        final toAdd = images.take(remaining).toList();
        setState(() => _newImages.addAll(toAdd));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick images: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  void _removeExistingImage(int index) {
    final image = _existingImages[index];
    final imageId = image['id']?.toString();
    if (imageId != null) {
      setState(() {
        _removedImageIds.add(imageId);
        _existingImages.removeAt(index);
      });
    }
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
    bool success;

    if (_isOrderItemReview) {
      // Per-order-item review (Shopee/Lazada style)
      if (_isEditing) {
        success = await reviewProvider.updateOrderItemReview(
          reviewId: widget.existingReview!['id'].toString(),
          orderId: widget.orderId!,
          rating: _rating,
          comment: _bodyController.text.trim(),
          newImages: _newImages.isNotEmpty ? _newImages : null,
          removedImageIds: _removedImageIds.isNotEmpty ? _removedImageIds : null,
        );
      } else {
        success = await reviewProvider.submitOrderItemReview(
          orderId: widget.orderId!,
          orderItemId: widget.orderItemId!,
          productId: widget.productId,
          storeId: widget.storeId!,
          rating: _rating,
          comment: _bodyController.text.trim(),
          images: _newImages.isNotEmpty ? _newImages : null,
        );
      }
    } else {
      // Per-product review (legacy)
      if (_isEditing) {
        final reviewId = widget.existingReview!['id'].toString();
        success = await reviewProvider.updateReview(
          reviewId: reviewId,
          productId: widget.productId,
          rating: _rating,
          title: '',
          body: _bodyController.text.trim(),
          newImages: _newImages.isNotEmpty ? _newImages : null,
          removedImageIds: _removedImageIds.isNotEmpty ? _removedImageIds : null,
        );
      } else {
        success = await reviewProvider.submitReview(
          productId: widget.productId,
          rating: _rating,
          title: '',
          body: _bodyController.text.trim(),
          images: _newImages.isNotEmpty ? _newImages : null,
        );
      }
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Review updated!' : 'Review submitted!'),
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
          _isEditing ? 'Edit Review' : 'Write a Review',
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
            // Product name
            if (_isOrderItemReview) ...[
              Row(
                children: [
                  // Product thumbnail
                  if (widget.existingReview?['product_image_url'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: widget.existingReview!['product_image_url'],
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 40,
                          height: 40,
                          color: AppConstants.primary.withValues(alpha: 0.1),
                          child: const Icon(Icons.shopping_bag_outlined, size: 20),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productName,
                          style: AppConstants.bodyStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.existingReview?['item_size'] != null)
                          Text(
                            'Size: ${widget.existingReview!['item_size']}',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                widget.productName,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            const SizedBox(height: 20),

            // Star rating selector
            _buildStarRating(),
            const SizedBox(height: 24),

            // Comment field
            Text(
              'Your review (optional)',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bodyController,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Tell others about your experience with this product...',
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
            const SizedBox(height: 20),

            // Photo picker
            _buildPhotoSection(),
            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isSubmitting || _rating == 0) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  disabledBackgroundColor: AppConstants.borderGray.withValues(alpha: 0.5),
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
            'How would you rate this product?',
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

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Photos (optional)',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              '$_totalImageCount/$_maxImages',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Existing images from server
            ..._existingImages.asMap().entries.map((entry) {
              final index = entry.key;
              final image = entry.value;
              final url = image['image_url']?.toString() ?? '';
              return _buildImageThumbnail(
                imageWidget: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: 80,
                  height: 80,
                  errorWidget: (_, __, ___) => Container(
                    width: 80,
                    height: 80,
                    color: AppConstants.borderGray.withValues(alpha: 0.2),
                    child: const Icon(Icons.broken_image, size: 24),
                  ),
                ),
                onRemove: () => _removeExistingImage(index),
              );
            }),

            // New local images
            ..._newImages.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              return _buildImageThumbnail(
                imageWidget: Image.file(
                  File(file.path),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
                onRemove: () => _removeNewImage(index),
              );
            }),

            // Add photo button
            if (_totalImageCount < _maxImages)
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppConstants.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppConstants.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 22,
                        color: AppConstants.primary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Add',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color: AppConstants.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageThumbnail({
    required Widget imageWidget,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppConstants.borderGray.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageWidget,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
