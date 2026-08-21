import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import '../screens/customer/buy_again_screen.dart';
import '../screens/customer/product_detail_screen.dart';
import 'horizontal_product_card.dart';

/// "Buy Again" strip on the customer profile — the products the customer
/// has purchased before, in most-recent-purchase order, so re-ordering a
/// favorite is one tap away.
///
/// - [orders] are the customer's raw (unfiltered) orders with `order_items`
///   (as loaded by `OrderProvider.loadMyOrders`). Cancelled orders are
///   excluded — only purchases the customer actually kept count.
/// - Product IDs are resolved against the live catalog, so the strip shows
///   the current (sale-aware) price and out-of-stock / deleted products
///   are dropped, mirroring the Recently Viewed strip.
/// - [onProductOpened] fires after the user pops back from a product
///   detail, letting the owning screen refresh its data.
class BuyAgainSection extends StatelessWidget {
  const BuyAgainSection({
    super.key,
    required this.orders,
    this.onProductOpened,
  });

  final List<Map<String, dynamic>> orders;
  final Future<void> Function()? onProductOpened;

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();

    // Unique product IDs the customer actually purchased, newest order
    // first (orders arrive newest-first), excluding cancelled orders.
    final purchasedIds = <String>[];
    for (final order in orders) {
      if ((order['status'] ?? '').toString().toLowerCase() == 'cancelled') {
        continue;
      }
      final items = order['order_items'] as List? ?? [];
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['product_id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (!purchasedIds.contains(id)) purchasedIds.add(id);
      }
    }

    // Resolve to live catalog products, preserving purchase order. Products
    // no longer in the catalog (deleted / out of stock) are dropped.
    final purchased = purchasedIds
        .map((id) => productProvider.products
            .cast<Map<String, dynamic>?>()
            .firstWhere((p) => p?['id']?.toString() == id,
                orElse: () => null))
        .whereType<Map<String, dynamic>>()
        .toList();

    if (purchased.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 14,
              color: AppConstants.secondary.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Products you buy will show up here',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header with "View Details >" link ──
        Row(
          children: [
            Text(
              'Buy Again',
              style: AppConstants.bodyStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _openAll(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Details',
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
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: purchased.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final prod = purchased[index];
              return HorizontalProductCard(
                product: prod,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(product: prod),
                    ),
                  );
                  await onProductOpened?.call();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Navigate to the full-screen purchased products grid.
  void _openAll(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuyAgainScreen(
          orders: orders,
          onProductOpened: onProductOpened,
        ),
      ),
    );
  }
}
