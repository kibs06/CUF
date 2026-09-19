import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../constants/app_constants.dart';
import '../../../utils/product_grid_ratio.dart';
import '../../customer/product_detail_screen.dart';
import '../../../widgets/sole_product_card.dart';

/// The focused store's products in the same two-column masonry grid as the
/// rest of the customer catalog.
class CrossStoreProductRow extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final String storeName;

  const CrossStoreProductRow({
    super.key,
    required this.products,
    this.storeName = 'all stores',
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.feedMargin,
            28,
            AppConstants.feedMargin,
            4,
          ),
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
              Flexible(
                child: Text(
                  'from $storeName',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withAlpha(127),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        MasonryGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.feedMargin,
          ),
          crossAxisCount: 2,
          crossAxisSpacing: AppConstants.productGridGutter,
          mainAxisSpacing: AppConstants.productGridGutter,
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return SoleProductCard(
              product: product,
              imageAspectRatio: productGridRatio(product),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(product: product),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
