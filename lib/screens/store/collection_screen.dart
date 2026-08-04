import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/sole_product_card.dart';
import '../customer/product_detail_screen.dart';
import '../customer/ar_fitting_screen.dart';

/// Deterministic image aspect ratio per card keyed off product id.
double _imageAspectRatioFor(dynamic product) {
  const ratios = [1.0, 0.78, 1.22, 0.95];
  final id = product['id']?.toString() ?? '';
  final key = id.isEmpty ? 0 : id.hashCode;
  return ratios[key.abs() % ratios.length];
}

class CollectionScreen extends StatelessWidget {
  final String collectionName;
  final String categoryFilter;
  final String? storeId; // Optional: filter by store

  const CollectionScreen({
    super.key,
    required this.collectionName,
    required this.categoryFilter,
    this.storeId,
  });

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    var filtered = productProvider.products
        .where((p) =>
            (p['category'] as String).toLowerCase() ==
            categoryFilter.toLowerCase())
        .toList();

    // If storeId provided, further filter by store
    if (storeId != null) {
      filtered = filtered.where((p) => p['store_id'] == storeId).toList();
    }

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          collectionName,
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppConstants.secondary,
        actions: const [CartIconButton()],
      ),
      body: RefreshIndicator(
        color: AppConstants.primary,
        onRefresh: () async {
          await Provider.of<ProductProvider>(context, listen: false).loadProducts();
        },
        child: Stack(
          children: [
            AppConstants.noiseOverlay(opacity: 0.03),
            filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: AppConstants.primary.withAlpha(100),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No products in this collection yet.',
                              style: AppConstants.bodyStyle(
                                color: AppConstants.secondary.withAlpha(153),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : MasonryGridView.count(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final prod = filtered[index];
                      return SoleProductCard(
                        product: prod,
                        imageAspectRatio: _imageAspectRatioFor(prod),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailScreen(product: prod),
                            ),
                          );
                        },
                        onTryOnTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ARVirtualFitScreen(
                                preselectedProduct: prod,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
