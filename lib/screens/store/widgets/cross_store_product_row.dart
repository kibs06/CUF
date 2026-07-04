import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../customer/product_detail_screen.dart';

/// "Top Picks from all stores" horizontal scrollable product row.
/// Each card shows product info plus a store attribution tag.
class CrossStoreProductRow extends StatelessWidget {
  final List<Map<String, dynamic>> products;

  const CrossStoreProductRow({
    super.key,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Top Picks',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'from all stores',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withAlpha(127),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Horizontal product row
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final images = product['images'] as List? ?? [];
              final imageUrl = images.isNotEmpty ? images[0] as String : '';

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(product: product),
                    ),
                  );
                },
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppConstants.cardRadius,
                    boxShadow: AppConstants.warmShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product image
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: Image.network(
                          imageUrl,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: AppConstants.borderGray.withAlpha(76),
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: AppConstants.borderGray,
                            ),
                          ),
                        ),
                      ),

                      // Product info
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'] ?? '',
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.secondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // Store attribution
                            Text(
                              product['store_name'] ?? '',
                              style: AppConstants.bodyStyle(
                                fontSize: 10,
                                color: AppConstants.secondary.withAlpha(127),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₱${(product['price'] as double).toStringAsFixed(0)}',
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
            },
          ),
        ),
      ],
    );
  }
}
