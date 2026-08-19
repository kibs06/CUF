import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_grid_ratio.dart';
import '../../utils/recently_viewed.dart';
import '../../widgets/sole_product_card.dart';
import 'product_detail_screen.dart';

/// Full-screen "Recently Viewed" grid — the navigation target of the
/// profile section's "See more" control (same app pattern as the "View all"
/// link on the My Orders panel).
///
/// Loads the persisted recently viewed list fresh on entry, resolves items
/// against the live catalog (same rules as the profile strip: deleted /
/// out-of-stock products are dropped), and renders the identical 2-column
/// masonry grid used by the Artisan Catalog.
class RecentlyViewedScreen extends StatefulWidget {
  const RecentlyViewedScreen({super.key, this.onProductOpened});

  /// Fired after the user pops back from a product detail, so the owning
  /// screen can refresh its copy of the list.
  final Future<void> Function()? onProductOpened;

  @override
  State<RecentlyViewedScreen> createState() => _RecentlyViewedScreenState();
}

class _RecentlyViewedScreenState extends State<RecentlyViewedScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await RecentlyViewedService.instance.load();
    if (mounted) {
      setState(() => _items = items);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();

    // Only items still in the live catalog — same filtering as the profile
    // strip so the two can never disagree.
    final liveItems = _items
        .where((item) => productProvider.products.any(
            (p) => p['id']?.toString() == item['id']))
        .toList();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Recently Viewed',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
      ),
      body: liveItems.isEmpty
          ? const _EmptyRecentlyViewed()
          : RefreshIndicator(
              color: AppConstants.primary,
              onRefresh: _load,
              child: MasonryGridView.count(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                itemCount: liveItems.length,
                itemBuilder: (context, index) {
                  final item = liveItems[index];
                  final fullProduct = productProvider.products
                      .cast<Map<String, dynamic>?>()
                      .firstWhere(
                    (p) => p?['id']?.toString() == item['id'],
                    orElse: () => null,
                  );
                  return SoleProductCard(
                    product: fullProduct ?? const {},
                    imageAspectRatio:
                        productGridRatio(fullProduct ?? item),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductDetailScreen(product: fullProduct ?? const {}),
                        ),
                      );
                      // The tapped product moved to the front — reload so
                      // the order reflects it, then let the profile refresh.
                      await _load();
                      await widget.onProductOpened?.call();
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyRecentlyViewed extends StatelessWidget {
  const _EmptyRecentlyViewed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_outlined,
            size: 56,
            color: AppConstants.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 14),
          Text(
            'No recently viewed products yet',
            style: AppConstants.headlineStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Products you view will show up here.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}