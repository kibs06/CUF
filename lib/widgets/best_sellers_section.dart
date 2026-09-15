import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import '../screens/customer/product_detail_screen.dart';
import 'horizontal_product_card.dart';
import 'sole_badge.dart';

/// "Best Sellers" strip on the customer home — the top-selling products,
/// most-sold first, as a horizontally-scrolling rail.
///
/// Feeds off the **same** live data the catalog already has: it reads
/// [ProductProvider.bestSellers], which is derived from the products and the
/// `units_sold` aggregation that `loadProducts()` fetched in parallel. No
/// second query, no cached snapshot — when a product sells (or a refresh
/// reloads the aggregation) the rail re-renders with the rest of the catalog.
///
/// The inclusion rule lives in one place, [bestSellerProducts], so the rail
/// and the 'Best Sellers' filter chip can never disagree about what a best
/// seller is. A catalog with nothing sold yet renders nothing at all.
///
/// - [onSeeAll] is the header action ("See all"); the home screen wires it to
///   the same selection the 'Best Sellers' chip performs, so both land on the
///   same filtered catalog.
class BestSellersSection extends StatelessWidget {
  const BestSellersSection({super.key, this.onSeeAll});

  final VoidCallback? onSeeAll;

  /// Strip height — matches the profile's "Buy Again" / "Recently Viewed"
  /// rails, which use the same 130x180 [HorizontalProductCard].
  static const double railHeight = 180;

  @override
  Widget build(BuildContext context) {
    final bestSellers = context.watch<ProductProvider>().bestSellers;
    if (bestSellers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(
            children: [
              // Expanded + FittedBox(scaleDown) so a narrow screen or a large
              // text scale shrinks the label group instead of overflowing the
              // row (same guarantee the strip cards make).
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Best Sellers',
                        style: AppConstants.headlineStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 10),
                      const SoleBadge(
                        label: 'MOST SOLD',
                        icon: Icons.trending_up,
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                      ),
                    ],
                  ),
                ),
              ),
              if (onSeeAll != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSeeAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppConstants.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: bestSellers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final prod = bestSellers[index];
              return HorizontalProductCard(
                product: prod,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(product: prod),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
