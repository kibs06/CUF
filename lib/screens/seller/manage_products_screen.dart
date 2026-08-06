import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/product_service.dart';
import '../../services/store_service.dart';
import '../../utils/sale_price.dart';
import '../../widgets/seller/seller_inventory_row.dart';
import 'add_edit_product_screen.dart';
import 'create_store_screen.dart';

/// Seller's product list screen — wired to real Supabase data via [ProductService].
///
/// Grid view of products with FAB for adding, tap to edit, long press for actions.
/// Each product card's long-press menu also exposes an **Adjust Stock** editor
/// (the standalone inventory screen was merged here).
class ManageProductsScreen extends StatefulWidget {
  /// Optional filter chip to preselect on open (e.g. 'Low Stock') — used by
  /// the dashboard metric and low-stock notifications to deep-link here.
  final String? initialFilter;

  const ManageProductsScreen({super.key, this.initialFilter});

  @override
  State<ManageProductsScreen> createState() => _ManageProductsScreenState();
}

class _ManageProductsScreenState extends State<ManageProductsScreen> {
  final ProductService _productService = ProductService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>>? _products;
  bool _isLoading = true;
  String? _error;
  String _activeFilter = 'All';
  String _search = '';
  bool _isSearching = false;
  String? _deletingProductId;
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter ?? 'All';
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        _loadProducts();
      }
      _wasOffline = !isOnline;
    });
    _loadProducts();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final products = await _productService.getSellerProducts();
      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  int _totalStock(Map<String, dynamic> product) {
    // The `inventory` relation is the authoritative stock source for
    // checkout AND for the Adjust Stock editor — prefer it so the grid's
    // badges/filters reflect what the editor writes. Fall back to variants
    // when no inventory rows exist.
    final inventory =
        product['inventory'] is List ? product['inventory'] as List : [];
    if (inventory.isNotEmpty) {
      return inventory.fold<int>(
          0, (sum, v) => sum + ((v['stock'] as num?)?.toInt() ?? 0));
    }
    final variants = product['product_variants'] is List
        ? product['product_variants'] as List
        : [];
    return variants.fold<int>(
        0, (sum, v) => sum + ((v['stock'] as num?)?.toInt() ?? 0));
  }

  String? _primaryImageUrl(Map<String, dynamic> product) {
    final images = product['product_images'] is List
        ? List<Map<String, dynamic>>.from(product['product_images'])
        : <Map<String, dynamic>>[];
    if (images.isEmpty) return null;

    // Find primary or first by display_order
    images.sort((a, b) =>
        ((a['display_order'] ?? 0) as int)
            .compareTo((b['display_order'] ?? 0) as int));
    final primary = images.firstWhere(
      (i) => i['is_primary'] == true,
      orElse: () => images.first,
    );
    return (primary['url'] ?? primary['image_url'])?.toString();
  }

  bool _isActive(Map<String, dynamic> product) =>
      product['is_active'] ?? true;

  bool _isFeatured(Map<String, dynamic> product) =>
      product['is_featured'] ?? false;

  bool _isOnSale(Map<String, dynamic> product) => isOnSale(product);

  List<Map<String, dynamic>> get _filteredProducts {
    if (_products == null) return [];
    var filtered = List<Map<String, dynamic>>.from(_products!);

    switch (_activeFilter) {
      case 'On Sale':
        filtered = filtered.where((p) => _isOnSale(p)).toList();
        break;
      case 'Low Stock':
        filtered = filtered.where((p) {
          final stock = _totalStock(p);
          return stock > 0 && stock <= 5;
        }).toList();
        break;
      case 'Out of Stock':
        filtered = filtered.where((p) => _totalStock(p) == 0).toList();
        break;
      case 'Featured':
        filtered = filtered.where((p) => _isFeatured(p)).toList();
        break;
      case 'Inactive':
        filtered = filtered.where((p) => !_isActive(p)).toList();
        break;
    }

    if (_search.trim().isNotEmpty) {
      final query = _search.trim().toLowerCase();
      filtered = filtered.where((product) {
        final name = '${product['name'] ?? ''}'.toLowerCase();
        final category = '${product['category'] ?? ''}'.toLowerCase();
        return name.contains(query) || category.contains(query);
      }).toList();
    }

    return filtered;
  }

  int _countFor(String filter) {
    if (_products == null) return 0;
    switch (filter) {
      case 'On Sale':
        return _products!.where((p) => _isOnSale(p)).length;
      case 'Low Stock':
        return _products!.where((p) {
          final stock = _totalStock(p);
          return stock > 0 && stock <= 5;
        }).length;
      case 'Out of Stock':
        return _products!.where((p) => _totalStock(p) == 0).length;
      case 'Featured':
        return _products!.where((p) => _isFeatured(p)).length;
      case 'Inactive':
        return _products!.where((p) => !_isActive(p)).length;
      default:
        return _products!.length;
    }
  }

  // ─── ACTIONS ────────────────────────────────────────────────────

  Future<void> _navigateToAddEdit({Map<String, dynamic>? product}) async {
    // When adding a new product (no product passed), check for store first
    if (product == null) {
      final store = await StoreService.instance.getMyStore();
      if (store == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please set up your store before adding products.'),
              backgroundColor: AppConstants.error,
            ),
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateStoreScreen(),
            ),
          );
        }
        return;
      }
    }

    Map<String, dynamic>? fullProduct;
    if (product != null) {
      // Fetch full product data with all relations for edit mode
      try {
        fullProduct =
            await _productService.getProduct(product['id'].toString());
      } catch (_) {
        fullProduct = product;
      }
    }

    if (!mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditProductScreen(product: fullProduct),
      ),
    );
    if (result == true) _loadProducts();
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Product',
          style: AppConstants.bodyStyle(
              fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${product['name'] ?? 'this product'}"? '
          'This action cannot be undone. Any existing orders containing this product '
          'will retain their order history.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style:
                    AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: AppConstants.bodyStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingProductId = product['id'].toString());
    try {
      await _productService.deleteProduct(product['id'].toString());
      if (mounted) {
        setState(() {
          _deletingProductId = null;
          _products?.removeWhere((p) => p['id'] == product['id']);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product deleted successfully.'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deletingProductId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete product. Please try again.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> product) async {
    final currentlyActive = _isActive(product);
    try {
      await _productService.toggleActive(
          product['id'].toString(), !currentlyActive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                currentlyActive ? 'Product hidden.' : 'Product activated.'),
            backgroundColor: AppConstants.success,
          ),
        );
        _loadProducts();
      }
    } catch (_) {}
  }

  Future<void> _toggleFeatured(Map<String, dynamic> product) async {
    final currentlyFeatured = _isFeatured(product);
    try {
      await _productService.toggleFeatured(
          product['id'].toString(), !currentlyFeatured);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlyFeatured
                ? 'Removed from featured.'
                : 'Marked as featured.'),
            backgroundColor: AppConstants.success,
          ),
        );
        _loadProducts();
      }
    } catch (_) {}
  }

  /// Start or end a product's sale. Mirrors the _toggleFeatured pattern.
  Future<void> _toggleSale(Map<String, dynamic> product) async {
    if (_isOnSale(product)) {
      try {
        await _productService.clearSale(product['id'].toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sale ended — original price restored.'),
              backgroundColor: AppConstants.success,
            ),
          );
          _loadProducts();
        }
      } catch (_) {}
    } else {
      _showSaleDialog(product);
    }
  }

  /// Dialog asking for the sale price + optional end date.
  Future<void> _showSaleDialog(Map<String, dynamic> product) async {
    final basePrice = (product['price'] as num?)?.toDouble() ?? 0;
    final saleCtrl = TextEditingController();
    DateTime? saleEnd;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Put on sale',
          style: AppConstants.bodyStyle(
              fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Original price: ₱${basePrice.toStringAsFixed(2)}',
                style: AppConstants.bodyStyle(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: saleCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Sale price (₱)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2036),
                  );
                  if (picked != null) {
                    setDialogState(() => saleEnd = picked);
                  }
                },
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(
                  saleEnd != null
                      ? 'Ends: ${saleEnd!.year}-${saleEnd!.month.toString().padLeft(2, '0')}-${saleEnd!.day.toString().padLeft(2, '0')}'
                      : 'End date (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: AppConstants.bodyStyle(color: AppConstants.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Start Sale',
                style: AppConstants.bodyStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true) {
      saleCtrl.dispose();
      return;
    }

    final salePrice = double.tryParse(saleCtrl.text.trim());
    if (salePrice == null || salePrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid sale price.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      saleCtrl.dispose();
      return;
    }
    if (salePrice >= basePrice) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale price must be lower than the base price.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      saleCtrl.dispose();
      return;
    }

    try {
      await _productService.setSale(
        product['id'].toString(),
        salePrice: salePrice,
        saleEndsAt: saleEnd,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product is now on sale!'),
            backgroundColor: AppConstants.success,
          ),
        );
        _loadProducts();
      }
    } catch (_) {}
    saleCtrl.dispose();
  }

  void _showProductActions(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product['name'] ?? 'Product',
                style: AppConstants.headlineStyle(fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: AppConstants.primary),
                title: Text('Edit',
                    style: AppConstants.bodyStyle()),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _navigateToAddEdit(product: product);
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined,
                    color: AppConstants.statusReadyColor),
                title: Text('Adjust Stock',
                    style: AppConstants.bodyStyle()),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showStockEditor(product);
                },
              ),
              ListTile(
                leading: Icon(
                  _isActive(product)
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppConstants.statusPendingColor,
                ),
                title: Text(
                  _isActive(product) ? 'Hide from customers' : 'Make active',
                  style: AppConstants.bodyStyle(),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _toggleActive(product);
                },
              ),
              ListTile(
                leading: Icon(
                  _isFeatured(product) ? Icons.star : Icons.star_border,
                  color: AppConstants.statusPendingColor,
                ),
                title: Text(
                  _isFeatured(product)
                      ? 'Remove from featured'
                      : 'Mark as featured',
                  style: AppConstants.bodyStyle(),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _toggleFeatured(product);
                },
              ),
              ListTile(
                leading: Icon(
                  _isOnSale(product)
                      ? Icons.local_offer
                      : Icons.local_offer_outlined,
                  color: _isOnSale(product)
                      ? AppConstants.error
                      : AppConstants.primary,
                ),
                title: Text(
                  _isOnSale(product) ? 'End sale' : 'Put on sale',
                  style: AppConstants.bodyStyle(),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _toggleSale(product);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppConstants.error),
                title: Text('Delete',
                    style:
                        AppConstants.bodyStyle(color: AppConstants.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteProduct(product);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-product stock editor — replaces the standalone inventory screen.
  /// Shows one editable row per size; changes are persisted via
  /// [ProductProvider.updateProduct] (upserts the `inventory` table AND
  /// syncs `product_variants` so the two never drift), then auto-syncs the
  /// product's active status, mirroring the old ManageInventoryScreen
  /// behavior.
  void _showStockEditor(Map<String, dynamic> product) {
    // getSellerProducts() returns raw rows with an `inventory` relation
    // (size/stock), not the mapped `sizes` map — build it the same way
    // SupabaseService._mapProduct does so sizes stay the authoritative source.
    // Fall back to product_variants (summed per size) when no inventory rows
    // exist yet (legacy products) so Adjust Stock always has sizes to edit.
    final sizes = <String, int>{};
    final inventory =
        product['inventory'] is List ? product['inventory'] as List : [];
    for (final item in inventory) {
      final map = Map<String, dynamic>.from(item as Map);
      sizes[map['size'].toString()] =
          (map['stock'] as num?)?.toInt() ?? 0;
    }
    if (sizes.isEmpty) {
      final variants = product['product_variants'] is List
          ? product['product_variants'] as List
          : [];
      for (final v in variants) {
        final map = Map<String, dynamic>.from(v as Map);
        final size = map['size'].toString();
        sizes[size] =
            (sizes[size] ?? 0) + ((map['stock'] as num?)?.toInt() ?? 0);
      }
    }

    final totalMax = sizes.values.fold<int>(0, (sum, q) => sum + q);
    final maxStock = totalMax > 0 ? totalMax + 10 : 20;

    // LIVE sizes map — mutated on every change and persisted as a whole.
    // (Previously each row wrote a snapshot taken at sheet-open time, so
    // adjusting size A then size B silently reverted A's change.)
    final liveSizes = Map<String, int>.from(sizes);

    // Serialize DB writes so rapid taps on the same row can never land out
    // of order (each write persists the full map, so the last queued write
    // always reflects the final state).
    Future<void> writeChain = Future.value();

    Future<void> persistStock(String size, int newStock) async {
      // The row fires this from its 800ms debounce — the screen may already
      // be gone (user closed the sheet and left). Skip rather than throw on
      // a deactivated context.
      if (!mounted) return;
      liveSizes[size] = newStock;
      final snapshot = Map<String, int>.from(liveSizes);
      final provider =
          Provider.of<ProductProvider>(context, listen: false);
      final productId = product['id'].toString();
      writeChain = writeChain.then((_) async {
        // ProductProvider.updateProduct returns false when the DB write
        // fails — always check it so a failed restock is never silent.
        final saved = await provider
            .updateProduct(product['id'], {'sizes': snapshot});
        // Auto-sync active status (best-effort — a sync hiccup must not turn
        // a successful stock write into a reported failure).
        try {
          await ProductService.instance.syncProductActiveStatus(productId);
        } catch (e) {
          debugPrint('Adjust Stock status sync failed: $e');
        }
        if (saved) {
          // Update the grid's stock badges/filters in place instead of a
          // full reload (which would tear down the still-open editor sheet).
          _applyStockToLocalProduct(productId, snapshot);
        } else if (mounted) {
          debugPrint('Adjust Stock save FAILED for size $size ($newStock)');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save stock. Please try again.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Adjust Stock',
                        style: AppConstants.headlineStyle(fontSize: 18),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      color: AppConstants.primary,
                      tooltip: 'Close',
                    ),
                  ],
                ),
                Text(
                  product['name'] ?? 'Product',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppConstants.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: liveSizes.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No stock configured yet',
                              style: AppConstants.bodyStyle(
                                  color: Colors.grey.shade400),
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: liveSizes.entries.map((entry) {
                            return SellerInventoryRow(
                              productName: product['name'] ?? 'Product',
                              size: entry.key,
                              currentStock: entry.value,
                              maxStock: maxStock,
                              onStockChanged: (newStock) async {
                                await persistStock(entry.key, newStock);
                              },
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Update the in-memory product's `inventory` relation in place so the
  /// grid's stock badges and filters reflect Adjust Stock changes without a
  /// full reload (which would tear down the still-open editor sheet).
  void _applyStockToLocalProduct(String productId, Map<String, int> sizes) {
    if (!mounted) return;
    final index =
        _products?.indexWhere((p) => p['id']?.toString() == productId) ?? -1;
    if (index == -1) return;
    final updated = Map<String, dynamic>.from(_products![index]);
    updated['inventory'] = sizes.entries
        .map((e) => {'size': e.key, 'stock': e.value})
        .toList();
    setState(() => _products![index] = updated);
  }

  // ─── BUILD ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _search = value),
                style: AppConstants.bodyStyle(
                    color: Colors.white, fontSize: 15),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: AppConstants.bodyStyle(
                      color: Colors.white60, fontSize: 15),
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Products',
                    style: AppConstants.bodyStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  if (_activeFilter != 'All')
                    Text(
                      '$_activeFilter (${_countFor(_activeFilter)})',
                      style: AppConstants.bodyStyle(
                          fontSize: 11, color: Colors.white70),
                    ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _search = '';
                }
                _isSearching = !_isSearching;
              });
            },
          ),
          IconButton(
            tooltip: 'Add product',
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _navigateToAddEdit(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppConstants.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          'Add Product',
          style: AppConstants.bodyStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        onPressed: () => _navigateToAddEdit(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildShimmer();
    if (_error != null) return _buildError();

    final filtered = _filteredProducts;
    if (filtered.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _loadProducts,
      child: MasonryGridView.count(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final product = filtered[index];
          return _buildProductCard(product, index);
        },
      ),
    );
  }

  /// Deterministic image aspect ratio per card so the grid reads as a real
  /// masonry layout rather than uniform cards with a fancy name. Cycles
  /// through a small set of ratios keyed off the product id (not the list
  /// index) so a card's height stays stable across filtering/re-sorting.
  double _imageAspectRatioFor(Map<String, dynamic> product) {
    const ratios = [1.0, 0.78, 1.22, 0.95];
    final id = product['id']?.toString() ?? '';
    final key = id.isEmpty ? 0 : id.hashCode;
    return ratios[key.abs() % ratios.length];
  }

  // ─── PRODUCT CARD ───────────────────────────────────────────────

  /// Compact badge label for stock count — abbreviates large values
  /// so the badge width stays bounded and doesn't crowd other elements.
  String _stockBadgeLabel(int stock) {
    if (stock == 0) return 'OUT';
    if (stock > 99) return '99+';
    return '$stock';
  }

  Widget _buildProductCard(Map<String, dynamic> product, int index) {
    final imageUrl = _primaryImageUrl(product);
    final stock = _totalStock(product);
    final active = _isActive(product);
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final onSale = _isOnSale(product);
    final displayPrice = onSale ? effectivePrice(product) : price;
    final imageRatio = _imageAspectRatioFor(product);

    final isDeleting = _deletingProductId == product['id'];

    return GestureDetector(
      onTap: isDeleting ? null : () => _navigateToAddEdit(product: product),
      onLongPress: isDeleting ? null : () => _showProductActions(product),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppConstants.cardRadius,
              boxShadow: AppConstants.warmShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image — aspect ratio varies per product to give the grid
                // real masonry rhythm instead of uniform-height tiles.
                AspectRatio(
                  aspectRatio: imageRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        child: Opacity(
                          opacity: isDeleting ? 0.3 : (active ? 1.0 : 0.5),
                          child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: AppConstants.borderGray
                                      .withValues(alpha: 0.3),
                                  child: const Center(
                                    child: Icon(Icons.image,
                                        color: AppConstants.borderGray),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: AppConstants.borderGray
                                      .withValues(alpha: 0.3),
                                  child: const Center(
                                    child: Icon(Icons.broken_image,
                                        color: AppConstants.borderGray),
                                  ),
                                ),
                              )
                            : Container(
                                color: AppConstants.borderGray
                                    .withValues(alpha: 0.3),
                                child: const Center(
                                  child: Icon(Icons.image_outlined,
                                      color: AppConstants.borderGray, size: 32),
                                ),
                              ),
                        ),
                      ),
                      // Featured star badge (compact icon only, top-left)
                      if (_isFeatured(product))
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: AppConstants.statusPendingColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.star,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      // Stock badge (abbreviated for large values, top-right)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: stock == 0
                                ? AppConstants.error
                                : stock <= 5
                                    ? AppConstants.statusPendingColor
                                    : AppConstants.success,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _stockBadgeLabel(stock),
                            style: AppConstants.monoStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Info
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active / Inactive status dot + label
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? AppConstants.success
                                  : AppConstants.error,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            active ? 'Active' : 'Inactive',
                            style: AppConstants.bodyStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: active
                                  ? AppConstants.success
                                  : AppConstants.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product['name'] ?? 'Unnamed',
                        style: AppConstants.bodyStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (onSale) ...[
                        Text(
                          '₱${displayPrice.toStringAsFixed(2)}',
                          style: AppConstants.monoStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.error,
                          ),
                        ),
                        Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: AppConstants.monoStyle(
                            fontSize: 11,
                            color: AppConstants.secondary.withValues(alpha: 0.5),
                          ).copyWith(decoration: TextDecoration.lineThrough),
                        ),
                      ] else
                        Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: AppConstants.monoStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product['category'] ?? '',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color:
                              AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Delete loading overlay
          if (isDeleting)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: AppConstants.cardRadius,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppConstants.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── FILTER BAR ─────────────────────────────────────────────────

  Widget _buildFilterBar() {
    const filters = [
      'All',
      'On Sale',
      'Low Stock',
      'Out of Stock',
      'Featured',
      'Inactive',
    ];
    return Container(
      height: 54,
      color: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = _activeFilter == filter;
          final count = _countFor(filter);

          return FilterChip(
            label: Text('$filter ($count)'),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppConstants.primary,
            backgroundColor: AppConstants.sellerSurface,
            labelStyle: AppConstants.bodyStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppConstants.secondary,
            ),
            onSelected: (_) => setState(() => _activeFilter = filter),
          );
        },
      ),
    );
  }

  // ─── SHIMMER LOADING ────────────────────────────────────────────

  Widget _buildShimmer() {
    // Alternating heights so the loading state previews the masonry
    // rhythm instead of flashing a uniform grid then jumping to staggered.
    const heights = [220.0, 270.0, 250.0, 210.0, 260.0, 230.0];
    return Shimmer.fromColors(
      baseColor: AppConstants.borderGray.withValues(alpha: 0.3),
      highlightColor: Colors.white,
      child: MasonryGridView.count(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        itemCount: heights.length,
        itemBuilder: (_, i) => Container(
          height: heights[i],
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppConstants.cardRadius,
          ),
        ),
      ),
    );
  }

  // ─── ERROR STATE ────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48,
                color: AppConstants.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              'Failed to load products',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── EMPTY STATE ────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_mall_outlined,
                size: 64,
                color: AppConstants.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              _activeFilter == 'All'
                  ? 'No products yet'
                  : 'No products match "$_activeFilter"',
              style: AppConstants.headlineStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _activeFilter == 'All'
                  ? 'Tap + to add your first product.'
                  : 'Try changing the filter.',
              style: AppConstants.bodyStyle(
                  color: AppConstants.secondary.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
