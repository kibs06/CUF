import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/app_constants.dart';
import '../../services/supabase_service.dart';
import '../../utils/sale_price.dart';
import '../../widgets/seller/tag_selector.dart';
import 'product_detail_screen.dart';

/// Screen showing all products that share a specific tag.
/// Navigated to when a customer taps a tag badge on the product detail screen.
class TagProductsScreen extends StatefulWidget {
  final String tagId;

  const TagProductsScreen({super.key, required this.tagId});

  @override
  State<TagProductsScreen> createState() => _TagProductsScreenState();
}

class _TagProductsScreenState extends State<TagProductsScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final allProducts = await SupabaseService.instance.fetchProducts();
      // Filter products that have this tag
      final filtered = allProducts.where((p) {
        final tags = p['tags'] as List? ?? [];
        return tags.any((t) => t?.toString() == widget.tagId);
      }).toList();

      if (mounted) {
        setState(() {
          _products = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _tagLabel(String id) {
    for (final group in tagGroups) {
      for (final preset in group.presets) {
        if (preset.id == id) return preset.label;
      }
    }
    return id
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          _tagLabel(widget.tagId),
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? _buildShimmer()
          : _error != null
              ? _buildError()
              : _products.isEmpty
                  ? _buildEmpty()
                  : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _loadProducts,
      child: MasonryGridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          return _buildProductCard(product);
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    // Get primary image
    final images = product['product_images'] as List? ?? [];
    String? imageUrl;
    if (images.isNotEmpty && images.first is Map) {
      final sorted = List<Map<String, dynamic>>.from(images);
      sorted.sort((a, b) =>
          (a['display_order'] as int? ?? 0).compareTo(b['display_order'] as int? ?? 0));
      imageUrl = sorted.first['image_url']?.toString();
    } else {
      final flatImages = product['images'] as List? ?? [];
      if (flatImages.isNotEmpty) imageUrl = flatImages.first.toString();
    }

    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final onSale = isOnSale(product);
    final displayPrice = onSale ? effectivePrice(product) : price;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppConstants.cardRadius,
          boxShadow: AppConstants.warmShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: AppConstants.borderGray.withValues(alpha: 0.3),
                          child: const Center(
                            child: Icon(Icons.image, color: AppConstants.borderGray),
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: AppConstants.borderGray.withValues(alpha: 0.3),
                          child: const Center(
                            child: Icon(Icons.image_outlined, color: AppConstants.borderGray, size: 32),
                          ),
                        ),
                      )
                    : Container(
                        color: AppConstants.borderGray.withValues(alpha: 0.3),
                        child: const Center(
                          child: Icon(Icons.image_outlined, color: AppConstants.borderGray, size: 32),
                        ),
                      ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? 'Product',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (onSale) ...[
                    Text(
                      '₱${displayPrice.toStringAsFixed(2)}',
                      style: AppConstants.monoStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.error,
                      ),
                    ),
                    Text(
                      '₱${price.toStringAsFixed(2)}',
                      style: AppConstants.monoStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ).copyWith(decoration: TextDecoration.lineThrough),
                    ),
                  ] else
                    Text(
                      '₱${price.toStringAsFixed(2)}',
                      style: AppConstants.monoStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: AppConstants.borderGray.withValues(alpha: 0.3),
      highlightColor: Colors.white,
      child: MasonryGridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        itemCount: 6,
        itemBuilder: (_, i) => Container(
          height: i.isEven ? 220 : 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppConstants.cardRadius,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppConstants.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('Failed to load products', style: AppConstants.headlineStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(fontSize: 13, color: AppConstants.secondary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: AppConstants.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_off_outlined, size: 64, color: AppConstants.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'No products with this tag',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'No products are tagged with "${_tagLabel(widget.tagId)}" yet.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
