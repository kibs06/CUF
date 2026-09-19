import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../utils/product_audience.dart';
import '../../widgets/sole_card.dart';

/// The line the console prints when a product's audience is unset.
///
/// Deliberately not a value label: `productAudienceLabel` returns null for
/// unset, because unset is the absence of a stated audience rather than a
/// fourth kind of it (the plan's decision #1 keeps `unisex` as the only "for
/// anyone" answer). Spelled the same as the "Not set" chip on the seller's
/// form, so an admin reading one and a seller reading the other are looking at
/// the same state.
const String kAudienceUnsetLabel = 'Not set';

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
                        // Through the shared vocabulary — this console never
                        // spells "Men's" itself, so it cannot drift from the
                        // seller's form or the customer's rails.
                        final audience =
                            productAudienceLabel(prod['audience']?.toString());

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: SoleCard(
                            color: AppConstants.surfaceLight,
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
                                const SizedBox(height: 4),
                                // The audience state, per product. This is the
                                // admin's half of the backfill picture: the
                                // seller's own screen counts what is missing,
                                // and this one shows which is which, without an
                                // admin having to open the seller's editor.
                                // Disclosure only — no bulk edit, because this
                                // console has no selection or action pattern of
                                // any kind to extend (see the CHANGELOG note).
                                Row(
                                  children: [
                                    Text(
                                      'Audience: ',
                                      style: AppConstants.bodyStyle(
                                          fontSize: 12, color: Colors.black45),
                                    ),
                                    Text(
                                      audience ?? kAudienceUnsetLabel,
                                      style: AppConstants.bodyStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        // Amber = this app's "needs attention"
                                        // tone, on the one value an admin comes
                                        // here to find.
                                        color: audience == null
                                            ? AppConstants.statusPendingColor
                                            : AppConstants.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Divider(color: AppConstants.borderGray),
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
                                            ? AppConstants.error.withValues(alpha: 0.08)
                                            : AppConstants.primary.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: lowStock
                                              ? AppConstants.error.withValues(alpha: 0.3)
                                              : AppConstants.primary.withValues(alpha: 0.12),
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
