import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../customer/product_detail_screen.dart';
import '../../customer/ar_fitting_screen.dart';
import '../../../widgets/sole_product_card.dart';

/// "Top Picks from a store" section.
/// Shows products from a single store in a 2-column layout using Wrap.
/// No shrinkWrap overhead — cards are laid out naturally.
class CrossStoreProductRow extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final String storeName;

  const CrossStoreProductRow({
    super.key,
    required this.products,
    this.storeName = 'all stores',
  });

  /// Deterministic image aspect ratio per card keyed off product id.
  double _imageAspectRatioFor(dynamic product) {
    const ratios = [1.0, 0.78, 1.22, 0.95];
    final id = product['id']?.toString() ?? '';
    final key = id.isEmpty ? 0 : id.hashCode;
    return ratios[key.abs() % ratios.length];
  }

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

        // 2-column grid using Wrap — no shrinkWrap, no height estimation.
        // Each child takes ~50% width minus spacing.
        LayoutBuilder(
          builder: (context, constraints) {
            final spacing = 14.0;
            final cardWidth = (constraints.maxWidth - spacing) / 2;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: products.map((product) {
                return SizedBox(
                  width: cardWidth,
                  child: SoleProductCard(
                    product: product,
                    imageAspectRatio: _imageAspectRatioFor(product),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: product),
                        ),
                      );
                    },
                    onTryOnTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ARVirtualFitScreen(
                            preselectedProduct: product,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
