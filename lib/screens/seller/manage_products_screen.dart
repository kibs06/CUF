import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/app_constants.dart';
import '../../services/product_service.dart';
import '../../services/store_service.dart';
import 'add_edit_product_screen.dart';
import 'create_store_screen.dart';

/// Seller's product list screen — wired to real Supabase data via [ProductService].
///
/// Grid view of products with FAB for adding, tap to edit, long press for actions.
class ManageProductsScreen extends StatefulWidget {
  const ManageProductsScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
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

  List<Map<String, dynamic>> get _filteredProducts {
    if (_products == null) return [];
    var filtered = List<Map<String, dynamic>>.from(_products!);

    switch (_activeFilter) {
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
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final product = filtered[index];
          return _buildProductCard(product);
        },
      ),
    );
  }

  // ─── PRODUCT CARD ───────────────────────────────────────────────

  Widget _buildProductCard(Map<String, dynamic> product) {
    final imageUrl = _primaryImageUrl(product);
    final stock = _totalStock(product);
    final active = _isActive(product);
    final price = (product['price'] as num?)?.toDouble() ?? 0;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                Expanded(
                  flex: 5,
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
                      // Status badges
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Row(
                          children: [
                            // Active / Inactive badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
                                    : AppConstants.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                active ? 'Active' : 'Out of Stock',
                                style: AppConstants.bodyStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? const Color(0xFF4ECDC4)
                                      : AppConstants.error,
                                ),
                              ),
                            ),
                            if (_isFeatured(product)) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppConstants.statusPendingColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('★ FEATURED',
                                    style: AppConstants.bodyStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Stock badge
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
                            stock == 0 ? 'OUT' : '$stock in stock',
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
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Opacity(
                          opacity: active ? 1.0 : 0.5,
                          child: Text(
                            product['name'] ?? 'Unnamed',
                            style: AppConstants.bodyStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
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
    const filters = ['All', 'Low Stock', 'Out of Stock', 'Featured', 'Inactive'];
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

          return ChoiceChip(
            label: Text('$filter ($count)'),
            selected: selected,
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
    return Shimmer.fromColors(
      baseColor: AppConstants.borderGray.withValues(alpha: 0.3),
      highlightColor: Colors.white,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
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
