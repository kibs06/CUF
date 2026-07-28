import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../services/product_service.dart';
import '../../widgets/seller/seller_inventory_row.dart';

class ManageInventoryScreen extends StatefulWidget {
  const ManageInventoryScreen({super.key});

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen> {
  String _filter = 'all';
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadSellerProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final products = productProvider.products;

    // Build flat list of product-size entries
    final List<Map<String, dynamic>> inventoryItems = [];
    for (var prod in products) {
      final name = prod['name'] ?? '';
      final sizesMap = Map<String, dynamic>.from(prod['sizes'] ?? {});
      for (var entry in sizesMap.entries) {
        if (_search.isNotEmpty && !name.toLowerCase().contains(_search.toLowerCase())) continue;
        final qty = entry.value is int ? entry.value as int : 0;
        if (_filter == 'low' && qty > 5) continue;
        if (_filter == 'out' && qty > 0) continue;
        inventoryItems.add({
          'product_name': name,
          'size': entry.key,
          'stock': qty,
          'product': prod,
        });
      }
    }

    // Group by product name
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (var item in inventoryItems) {
      grouped.putIfAbsent(item['product_name'] as String, () => []).add(item);
    }

    final inStockCount = inventoryItems.where((i) => (i['stock'] as int) > 5).length;
    final lowStockCount = inventoryItems.where((i) {
      final s = i['stock'] as int;
      return s > 0 && s <= 5;
    }).length;
    final outOfStockCount = inventoryItems.where((i) => (i['stock'] as int) == 0).length;

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Inventory',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              // Simple search toggle via dialog
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Search'),
                  content: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search product...'),
                    onChanged: (v) {
                      setState(() => _search = v);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export coming soon')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                _statPill('\u2713 $inStockCount In Stock', AppConstants.okStockColor, () {
                  setState(() => _filter = _filter == 'in' ? 'all' : 'in');
                }),
                const SizedBox(width: 8),
                _statPill('\u26A0 $lowStockCount Low Stock', AppConstants.statusPendingColor, () {
                  setState(() => _filter = _filter == 'low' ? 'all' : 'low');
                }),
                const SizedBox(width: 8),
                _statPill('\u2717 $outOfStockCount Out', AppConstants.lowStockColor, () {
                  setState(() => _filter = _filter == 'out' ? 'all' : 'out');
                }),
              ],
            ),
          ),
          // Inventory list with grouping
          Expanded(
            child: productProvider.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
                : inventoryItems.isEmpty
                    ? Center(
                        child: Text(
                          'No inventory items',
                          style: AppConstants.bodyStyle(color: Colors.grey.shade400),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: grouped.entries.map((entry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Group header
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                child: Text(
                                  entry.key,
                                  style: AppConstants.bodyStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.primary,
                                  ),
                                ),
                              ),
                              ...entry.value.map((item) {
                                final prod = item['product'] as Map<String, dynamic>;
                                final sizesMap = Map<String, dynamic>.from(prod['sizes'] ?? {});
                                final totalMax = sizesMap.values.fold(0, (sum, q) => sum + ((q is int) ? q : 0));
                                final maxStock = totalMax > 0 ? (totalMax + 10) : 20;

                                return SellerInventoryRow(
                                  productName: item['product_name'] as String,
                                  size: item['size'] as String,
                                  currentStock: item['stock'] as int,
                                  maxStock: maxStock,
                                  onStockChanged: (newStock) async {
                                    final sizesCopy = Map<String, int>.from(
                                      (prod['sizes'] as Map).map((k, v) => MapEntry(k, (v is int) ? v : 0))
                                    );
                                    sizesCopy[item['size'] as String] = newStock;
                                    await Provider.of<ProductProvider>(context, listen: false)
                                        .updateProduct(prod['id'], {'sizes': sizesCopy});
                                    // Auto-sync active status based on stock levels
                                    try {
                                      await ProductService.instance
                                          .syncProductActiveStatus(prod['id'].toString());
                                    } catch (_) {
                                      // Silently fail — status will self-correct on next update
                                    }
                                  },
                                );
                              }),
                            ],
                          );
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, Color color, VoidCallback onTap) {
    final isActive = _filter == 'low' && label.contains('Low') ||
        _filter == 'out' && label.contains('Out') ||
        _filter == 'in' && label.contains('In');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: isActive ? Border.all(color: color) : null,
        ),
        child: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isActive ? color : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
