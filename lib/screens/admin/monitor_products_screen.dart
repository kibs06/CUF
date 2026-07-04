import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../widgets/sole_card.dart';

class MonitorProductsScreen extends StatefulWidget {
  const MonitorProductsScreen({super.key});

  @override
  State<MonitorProductsScreen> createState() => _MonitorProductsScreenState();
}

class _MonitorProductsScreenState extends State<MonitorProductsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
    });
  }

  int _getTotalStock(Map<String, dynamic> sizes) {
    int total = 0;
    sizes.forEach((_, qty) {
      if (qty is int) {
        total += qty;
      }
    });
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Product Monitor Console',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          productProvider.isLoading
              ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
              : productProvider.products.isEmpty
                  ? Center(child: Text('No products tracked.', style: AppConstants.bodyStyle(color: Colors.black45)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: productProvider.products.length,
                      itemBuilder: (context, index) {
                        final prod = productProvider.products[index];
                        final double price = (prod['price'] is int) ? (prod['price'] as int).toDouble() : (prod['price'] ?? 0.0);
                        final sizes = Map<String, dynamic>.from(prod['sizes'] ?? {});
                        final total = _getTotalStock(sizes);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: SoleCard(
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      prod['name'] ?? '',
                                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    Text(
                                      '₱${price.toStringAsFixed(0)}',
                                      style: AppConstants.monoStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppConstants.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Category: ${prod['category']}',
                                  style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                                ),
                                const SizedBox(height: 12),
                                const Divider(color: AppConstants.borderGray),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Sizes Stock Levels:',
                                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      'Total Units: $total',
                                      style: AppConstants.monoStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: total < 10 ? AppConstants.error : AppConstants.success,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: sizes.entries.map((entry) {
                                    final size = entry.key;
                                    final qty = entry.value as int;
                                    final lowStock = qty < 3;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: lowStock
                                            ? AppConstants.error.withOpacity(0.08)
                                            : AppConstants.primary.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: lowStock
                                              ? AppConstants.error.withOpacity(0.3)
                                              : AppConstants.primary.withOpacity(0.12),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '$size: ',
                                            style: AppConstants.monoStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '$qty',
                                            style: AppConstants.monoStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: lowStock ? AppConstants.error : AppConstants.secondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}
