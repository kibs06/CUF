# POS "Add to Order" — Full Source Context

> Bundled on request for AI agents working on the POS flow (Add to Order / checkout / inventory decrement).
> **Last updated:** August 6, 2026
> Files are reproduced verbatim from the repo.

## What's inside

| # | File | Why it matters |
|---|------|----------------|
| 1 | `lib/screens/seller/pos_screen.dart` (2118 lines) | The POS screen — product grid, "Add to Order" bottom sheet, `_orderItems` line-item map, Cash/GCash checkout (`_CheckoutSheet`), order creation via `placeOrder(source: 'pos')`. |
| 2 | `lib/services/order_service.dart` | Order query/write helpers — `placeOrder` (delegates to `SupabaseService.createOrder`), `fetchPosHistory`, the 3-step store-order chain, status updates. |
| 3 | `supabase/migrations/20260711_fix_trigger_security_definer.sql` | Defines `decrement_inventory_on_order` + `decrement_inventory_on_sale` as `SECURITY DEFINER`. Note: POS sales write `order_items` rows, so the trigger that actually decrements for POS is `decrement_inventory_on_order`; `decrement_inventory_on_sale` covers the legacy `sales_transaction_items` path. |

## Key facts for agents

- POS creates `orders` rows via `OrderProvider.placeOrder(source: 'pos')` → `SupabaseService.createOrder()` (status `received`, `payment_status 'paid'`). `sales_transactions` is legacy/dead.
- Inventory decrement happens in the DB trigger on `order_items` INSERT — the app never decrements stock itself.
- Product scoping is app-layer: `ProductProvider.loadSellerProducts()` → `fetchProducts(storeId:)`.

---

# 1. `lib/screens/seller/pos_screen.dart`

```dartimport 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../utils/sale_price.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/product_service.dart';
import '../../services/store_service.dart';
import 'gcash_ref_scanner_screen.dart';
import 'pos_barcode_scanner.dart';
import 'pos_history_screen.dart';

class POSScreen extends StatefulWidget {
  final bool isStandalonePage;

  const POSScreen({super.key, this.isStandalonePage = false});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, _POSLineItem> _orderItems = {};
  String _searchKeyword = '';
  String _selectedCategory = 'All';
  int _panelIndex = 0;
  bool _showSuccessOverlay = false;
  double _lastChange = 0;
  Timer? _successTimer;

  /// Recent barcode scans — most recent first. Max 10 entries.
  final List<_ScanHistoryEntry> _scanHistory = [];
  static const int _maxScanHistory = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadSellerProducts();
    });
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int get _itemCount =>
      _orderItems.values.fold(0, (sum, item) => sum + item.quantity);

  double get _subtotal => _orderItems.values.fold(
    0,
    (sum, item) => sum + (_productPrice(item.product) * item.quantity),
  );

  /// Effective (sale-aware) price.
  ///
  /// Product-sale decision #3: POS applies the active discount so the
  /// register total matches the storefront price. All POS pricing (tile,
  /// size sheet, line items, unit_price) flows through this one method.
  double _productPrice(Map<String, dynamic> product) => effectivePrice(product);

  int _totalStock(Map<String, dynamic> product) {
    final sizes = Map<String, dynamic>.from(product['sizes'] ?? {});
    return sizes.values.fold(0, (sum, qty) => sum + (qty is int ? qty : 0));
  }

  List<String> _availableSizes(Map<String, dynamic> product) {
    final sizes = Map<String, dynamic>.from(product['sizes'] ?? {});
    return sizes.entries
        .where((entry) => entry.value is int && entry.value > 0)
        .map((entry) => entry.key)
        .toList();
  }

  /// Detect the sizing system from a list of size strings.
  /// Returns the most common system prefix, or null if mixed/unknown.
  String? _detectSizeSystem(List<String> sizes) {
    if (sizes.isEmpty) return null;
    final systems = <String, int>{};
    for (final size in sizes) {
      for (final sys in ['EU', 'US', 'UK']) {
        if (size.toUpperCase().startsWith('$sys ')) {
          systems[sys] = (systems[sys] ?? 0) + 1;
        }
      }
    }
    if (systems.isEmpty) return null;
    // Return the most common system
    return systems.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void _addLineItem(Map<String, dynamic> product, String size, int quantity) {
    final key = '${product['id']}_$size';
    setState(() {
      final existing = _orderItems[key];
      if (existing == null) {
        _orderItems[key] = _POSLineItem(
          product: product,
          size: size,
          quantity: quantity,
        );
      } else {
        existing.quantity += quantity;
      }
      _panelIndex = 1;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to order'),
        backgroundColor: AppConstants.success,
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  Future<void> _confirmClearOrder() async {
    if (_orderItems.isEmpty) return;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Clear order?',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This removes every item from the current transaction.',
          style: AppConstants.bodyStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Clear',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldClear == true) {
      setState(_orderItems.clear);
    }
  }

  void _openBarcodeScanner() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PosBarcodeScanner()),
    );
    if (barcode == null || !mounted) return;

    // Search against seller-scoped product list (already loaded)
    // Priority: product barcode > variant SKUs > product-level SKU
    final products = context.read<ProductProvider>().products;
    final codeLower = barcode.toLowerCase();
    final match = products.where((p) {
      // 1. Product-level barcode field (preferred match)
      final productBarcode = '${p['barcode'] ?? ''}'.toLowerCase();
      if (productBarcode.isNotEmpty && productBarcode == codeLower) return true;
      // 2. Top-level sku field
      final topSku = '${p['sku'] ?? ''}'.toLowerCase();
      if (topSku == codeLower) return true;
      // 3. Variants' SKUs
      final variants = p['product_variants'];
      if (variants is List) {
        return variants.any((v) {
          final vSku = '${v['sku'] ?? ''}'.toLowerCase();
          return vSku == codeLower;
        });
      }
      return false;
    }).toList();

    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No product found for barcode: $barcode'),
          backgroundColor: AppConstants.error,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final product = match.first;
    final sizes = _availableSizes(product);
    if (sizes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product['name'] ?? 'Product'} is out of stock'),
          backgroundColor: AppConstants.error,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Haptic + audio feedback on successful scan
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);

    // Add to scan history
    setState(() {
      _scanHistory.removeWhere((e) => e.barcode == barcode);
      _scanHistory.insert(0, _ScanHistoryEntry(
        barcode: barcode,
        productName: product['name'] ?? 'Product',
        productId: product['id'].toString(),
      ));
      if (_scanHistory.length > _maxScanHistory) {
        _scanHistory.removeLast();
      }
    });

    // Open the Size/Qty sheet for the matched product
    _openProductSheet(product);
  }

  void _openProductSheet(Map<String, dynamic> product) {
    final sizes = _availableSizes(product);
    if (sizes.isEmpty) return;

    var selectedSize = sizes.first;
    var quantity = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
        final maxSheetHeight =
            MediaQuery.of(context).size.height * 0.85;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final total = _productPrice(product) * quantity;
            return Container(
              constraints: BoxConstraints(
                maxHeight: maxSheetHeight,
              ),

              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    bottomSafe + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product['name'] ?? 'Product',
                              style: AppConstants.bodyStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Text(
                        '₱${_productPrice(product).toStringAsFixed(0)}',
                        style: AppConstants.monoStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _detectSizeSystem(sizes) != null
                            ? 'Size (${_detectSizeSystem(sizes)})'
                            : 'Size',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: sizes.map((size) {
                          final selected = selectedSize == size;
                          return ChoiceChip(
                            label: Text(size),
                            selected: selected,
                            showCheckmark: false,
                            selectedColor: AppConstants.primary,
                            labelStyle: AppConstants.monoStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppConstants.secondary,
                            ),
                            onSelected: (_) =>
                                setSheetState(() => selectedSize = size),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            'Qty',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            onPressed: quantity > 1
                                ? () => setSheetState(() => quantity--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$quantity',
                            style: AppConstants.monoStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setSheetState(() => quantity++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppConstants.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _addLineItem(product, selectedSize, quantity);
                          },
                          child: Text(
                            'Add to Order  ₱${total.toStringAsFixed(0)}',
                            style: AppConstants.bodyStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openCheckoutSheet() {
    if (_orderItems.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CheckoutSheet(
          total: _subtotal,
          items: _orderItems,
          productPrice: _productPrice,
          onConfirm: (method, tendered, {String? orderId}) {
            Navigator.of(context).pop();
            _completePOSTransaction(method, tendered, orderId: orderId);
          },
        );
      },
    );
  }

  Future<void> _completePOSTransaction(
    String paymentMethod,
    double cashTendered, {
    String? orderId,
  }) async {
    // For GCash, the order was already created by _CheckoutSheet
    // with payment_status='pending'. Only create for Cash flow.
    if (paymentMethod == 'Cash') {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final items = List<_POSLineItem>.from(_orderItems.values);

      final orderItems = items.map((item) => {
        'product_id': item.product['id'],
        'size': item.size,
        'color': 'Standard',
        'quantity': item.quantity,
        'unit_price': _productPrice(item.product),
      }).toList();

      await orderProvider.placeOrder(
        customerId: auth.profile?['id'] ?? 'seller-pos',
        items: orderItems,
        totalAmount: _subtotal,
        deliveryAddress: 'In-store POS',
        paymentMethod: paymentMethod,
        source: 'pos',
        amountTendered: cashTendered,
      );
    }

    // Auto-sync active status for each product after POS sale
    for (final item in _orderItems.values) {
      try {
        await ProductService.instance
            .syncProductActiveStatus(item.product['id'].toString());
      } catch (_) {
        // Silently fail — status will self-correct on next stock update
      }
    }

    if (!mounted) return;
    setState(() {
      _lastChange = paymentMethod == 'Cash'
          ? (cashTendered - _subtotal).clamp(0, double.infinity)
          : 0;
      _orderItems.clear();
      _panelIndex = 0;
      _showSuccessOverlay = true;
    });

    _successTimer?.cancel();
    _successTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSuccessOverlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final categories = <String>{
      'All',
      ...productProvider.products
          .map((product) => product['category'])
          .whereType<String>()
          .where((category) => category.trim().isNotEmpty),
    }.toList();

    var products = productProvider.products;
    if (_selectedCategory != 'All') {
      products = products
          .where((product) => product['category'] == _selectedCategory)
          .toList();
    }
    if (_searchKeyword.trim().isNotEmpty) {
      final query = _searchKeyword.trim().toLowerCase();
      products = products.where((product) {
        final name = '${product['name'] ?? ''}'.toLowerCase();
        final sku = '${product['sku'] ?? ''}'.toLowerCase();
        return name.contains(query) || sku.contains(query);
      }).toList();
    }

    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        automaticallyImplyLeading: widget.isStandalonePage,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'POS',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PosHistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Products'),
                      icon: Icon(Icons.grid_view_outlined),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Order'),
                      icon: Icon(Icons.receipt_long_outlined),
                    ),
                  ],
                  selected: {_panelIndex},
                  onSelectionChanged: (selection) =>
                      setState(() => _panelIndex = selection.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppConstants.primary
                          : Colors.white,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : AppConstants.secondary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _panelIndex,
                  children: [
                    _buildProductsPanel(
                      productProvider.isLoading,
                      products,
                      categories,
                    ),
                    _buildOrderPanel(),
                  ],
                ),
              ),
              _buildCheckoutStrip(),
            ],
          ),
          IgnorePointer(
            ignoring: !_showSuccessOverlay,
            child: AnimatedOpacity(
              opacity: _showSuccessOverlay ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: _buildSuccessOverlay(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsPanel(
    bool isLoading,
    List<Map<String, dynamic>> products,
    List<String> categories,
  ) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppConstants.sellerShadow,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchKeyword = value),
              style: AppConstants.bodyStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search product or scan barcode...',
                hintStyle: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
                prefixIcon: const Icon(Icons.search, color: AppConstants.primary),
                suffixIcon: _searchKeyword.isEmpty
                    ? IconButton(
                        onPressed: _openBarcodeScanner,
                        icon: const Icon(
                          Icons.qr_code_scanner,
                          color: AppConstants.secondary,
                        ),
                      )
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchKeyword = '');
                        },
                        icon: const Icon(
                          Icons.close,
                          color: AppConstants.secondary,
                        ),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final category = categories[index];
              final selected = _selectedCategory == category;
              return ChoiceChip(
                label: Text(category),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppConstants.primary,
                backgroundColor: Colors.white,
                labelStyle: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppConstants.secondary,
                ),
                onSelected: (_) => setState(() => _selectedCategory = category),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemCount: categories.length,
          ),
        ),
        if (_scanHistory.isNotEmpty && _searchKeyword.isEmpty) ...[
          _buildScanHistoryBar(),
        ],
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Text(
                    'No matching products',
                    style: AppConstants.bodyStyle(color: Colors.grey.shade500),
                  ),
                )
              : MasonryGridView.count(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  itemCount: products.length,
                  itemBuilder: (context, index) =>
                      _buildProductTile(products[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildProductTile(Map<String, dynamic> product) {
    final images = product['images'] as List?;
    final imageUrl = images?.isNotEmpty == true ? '${images!.first}' : '';
    final stock = _totalStock(product);
    final out = stock <= 0;
    final low = stock > 0 && stock <= 5;

    // ── Stock badge colors ──
    final Color badgeBg = out
        ? Colors.grey.shade200
        : low
            ? AppConstants.lowStockColor.withValues(alpha: 0.12)
            : AppConstants.okStockColor.withValues(alpha: 0.12);
    final Color badgeFg = out
        ? Colors.grey.shade600
        : low
            ? AppConstants.lowStockColor
            : AppConstants.okStockColor;
    final String badgeText = out
        ? 'Out'
        : low
            ? 'Low ($stock)'
            : 'In Stock';

    return Opacity(
      opacity: out ? 0.48 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppConstants.cardRadius,
          boxShadow: AppConstants.warmShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: out ? null : () => _openProductSheet(product),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Image — fixed height so card is content-driven ──
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    width: double.infinity,
                    color: Colors.grey.shade100,
                    child: imageUrl.isEmpty
                        ? Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.grey.shade300,
                            size: 36,
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.grey.shade300,
                              size: 36,
                            ),
                          ),
                  ),
                ),
                // ── Info block — content-driven height ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Product name
                      Text(
                        product['name'] ?? 'Product',
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Price (sale-aware) + SALE tag
                      Row(
                        children: [
                          Text(
                            '₱${_productPrice(product).toStringAsFixed(0)}',
                            style: AppConstants.monoStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primary,
                            ),
                          ),
                          if (isOnSale(product)) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppConstants.error,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'SALE',
                                style: AppConstants.monoStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Stock badge — flows naturally below price
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText,
                          style: AppConstants.bodyStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: badgeFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanHistoryBar() {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _scanHistory.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = _scanHistory[index];
          final products = context.read<ProductProvider>().products;
          final match = products.where((p) => p['id'].toString() == entry.productId).toList();
          final product = match.isNotEmpty ? match.first : null;
          final hasStock = product != null && _availableSizes(product).isNotEmpty;

          return GestureDetector(
            onTap: hasStock ? () => _openProductSheet(product as Map<String, dynamic>) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasStock
                      ? AppConstants.primary.withValues(alpha: 0.3)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 14,
                    color: hasStock ? AppConstants.primary : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      entry.productName,
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasStock ? AppConstants.secondary : Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderPanel() {
    final orderNumber = DateTime.now().millisecondsSinceEpoch
        .toString()
        .substring(7);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #$orderNumber',
                    style: AppConstants.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TimeOfDay.now().format(context),
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _confirmClearOrder,
              child: Text(
                'Clear',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.error,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_orderItems.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppConstants.sellerShadow,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.point_of_sale_outlined,
                  color: Colors.grey.shade400,
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  'No items in this order yet',
                  style: AppConstants.bodyStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          )
        else
          ..._orderItems.entries.map(
            (entry) => _buildOrderLine(entry.key, entry.value),
          ),
        const SizedBox(height: 12),
        _buildOrderSummary(),
      ],
    );
  }

  Widget _buildOrderLine(String key, _POSLineItem item) {
    final lineTotal = _productPrice(item.product) * item.quantity;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppConstants.sellerShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product['name'] ?? 'Product',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      item.size,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _quantityButton(Icons.remove, item.quantity > 1, () {
                      setState(() => item.quantity--);
                    }),
                    Text(
                      '${item.quantity}',
                      style: AppConstants.monoStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _quantityButton(Icons.add, true, () {
                      setState(() => item.quantity++);
                    }),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${lineTotal.toStringAsFixed(0)}',
                style: AppConstants.monoStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primary,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _orderItems.remove(key)),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppConstants.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quantityButton(IconData icon, bool enabled, VoidCallback onPressed) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppConstants.sellerShadow,
      ),
      child: Column(
        children: [
          _summaryRow('Subtotal:', _subtotal),
          const SizedBox(height: 8),
          _summaryRow('Discount:', 0, prefix: '- '),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL:',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '₱${_subtotal.toStringAsFixed(0)}',
                style: AppConstants.monoStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amount, {String prefix = ''}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          '$prefix₱${amount.toStringAsFixed(0)}',
          style: AppConstants.monoStyle(
            fontSize: 13,
            color: AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutStrip() {
    final hasItems = _orderItems.isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: -2,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_itemCount item${_itemCount == 1 ? '' : 's'}',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: hasItems
                        ? AppConstants.secondary
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₱${_subtotal.toStringAsFixed(0)}',
                  style: AppConstants.monoStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: hasItems
                        ? AppConstants.primary
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  hasItems ? AppConstants.accent : Colors.grey.shade300,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: hasItems ? 2 : 0,
            ),
            onPressed: hasItems ? _openCheckoutSheet : null,
            icon: Icon(
              Icons.arrow_forward,
              size: 18,
              color: hasItems ? Colors.white : Colors.grey.shade500,
            ),
            label: Text(
              'Checkout',
              style: AppConstants.bodyStyle(
                color: hasItems ? Colors.white : Colors.grey.shade500,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.75, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: AppConstants.accent,
                  borderRadius: BorderRadius.circular(41),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 46),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Payment Received',
              style: AppConstants.bodyStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_lastChange > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Change: ₱${_lastChange.toStringAsFixed(0)}',
                style: AppConstants.monoStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {},
                  child: Text(
                    'Receipt',
                    style: AppConstants.bodyStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.accent,
                  ),
                  onPressed: () => setState(() => _showSuccessOverlay = false),
                  child: Text(
                    'New Transaction',
                    style: AppConstants.bodyStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  final double total;
  final Map<String, _POSLineItem> items;
  final double Function(Map<String, dynamic> product) productPrice;
  final void Function(String method, double tendered, {String? orderId}) onConfirm;

  const _CheckoutSheet({
    required this.total,
    required this.items,
    required this.productPrice,
    required this.onConfirm,
  });

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final TextEditingController _tenderedController = TextEditingController();
  final TextEditingController _gcashRefController = TextEditingController();
  final FocusNode _gcashRefFocus = FocusNode();
  String _method = 'Cash';

  // Static-QR GCash state — the seller's own uploaded QR, confirmed manually.
  Map<String, dynamic>? _store; // seller's store (gcash_qr_url, name, number)
  bool _storeLoaded = false;
  bool _gcashPaymentPending = false; // pending order exists & QR is on screen
  String? _gcashOrderId;
  bool _gcashCreatingPayment = false;
  bool _gcashConfirming = false; // 'Payment Received' write in flight
  String? _gcashError;

  double get _tendered => double.tryParse(_tenderedController.text) ?? 0;
  double get _change => (_tendered - widget.total).clamp(0, double.infinity);

  bool get _canConfirm {
    if (_method == 'Cash') return true; // validated on press
    // GCash: confirm only after the pending order exists — the seller taps
    // "Payment Received" once they have verified the money arrived.
    return _gcashOrderId != null;
  }

  bool get _canStartGcash =>
      !_gcashCreatingPayment && !_gcashPaymentPending && _hasGcashQr;

  /// Whether the seller has uploaded a static GCash QR for their store.
  bool get _hasGcashQr =>
      _store?['gcash_qr_url']?.toString().isNotEmpty ?? false;

  /// Fresh per checkout-sheet-open. The QR is upserted to the SAME stable
  /// storage URL on every replacement, so Flutter's ImageCache would otherwise
  /// keep serving the previous (e.g. uncropped) image.
  final String _qrCacheBust =
      DateTime.now().millisecondsSinceEpoch.toString();

  /// The store's GCash QR URL with a cache-busting query param so a replaced
  /// QR is always re-fetched from storage instead of the image cache.
  String? get _gcashQrDisplayUrl {
    final url = _store?['gcash_qr_url']?.toString();
    if (url == null || url.isEmpty) return null;
    return '$url${url.contains('?') ? '&' : '?'}v=$_qrCacheBust';
  }

  @override
  void initState() {
    super.initState();
    _loadGcashSettings();
  }

  /// Load the seller's store so we can show their uploaded GCash QR.
  Future<void> _loadGcashSettings() async {
    try {
      final store = await StoreService.instance.getMyStore();
      if (!mounted) return;
      setState(() {
        _store = store;
        _storeLoaded = true;
      });
    } catch (e) {
      debugPrint('Failed to load store GCash settings: $e');
      if (mounted) setState(() => _storeLoaded = true);
    }
  }

  @override
  void dispose() {
    _tenderedController.dispose();
    _gcashRefController.dispose();
    _gcashRefFocus.dispose();
    super.dispose();
  }

  /// Create order upfront with payment_status='pending' for GCash.
  Future<String?> _createPendingOrder() async {
    final auth = Supabase.instance.client.auth.currentUser;
    if (auth == null) return null;

    // Look up store_id from first product
    final firstItem = widget.items.values.first;
    final storeData = await Supabase.instance.client
        .from('products')
        .select('store_id')
        .eq('id', firstItem.product['id'].toString())
        .single();

    final items = widget.items.values.map((item) => {
      'product_id': item.product['id'],
      'size': item.size,
      'quantity': item.quantity,
      'unit_price': widget.productPrice(item.product),
    }).toList();

    // Insert order with payment_status='pending'
    final order = await Supabase.instance.client
        .from('orders')
        .insert({
          'customer_id': auth.id,
          'store_id': storeData['store_id'],
          'status': 'received',
          'fulfillment': 'pickup',
          'total_amount': widget.total,
          'payment_method': 'gcash',
          'payment_status': 'pending',
          'notes': 'In-store POS',
          'source': 'pos',
        })
        .select('id')
        .single();

    // Insert order items
    for (final item in items) {
      await Supabase.instance.client.from('order_items').insert({
        'order_id': order['id'],
        'product_id': item['product_id'],
        'size': item['size'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
      });
    }

    // Write status history
    await Supabase.instance.client.from('order_status_history').insert({
      'order_id': order['id'],
      'status': 'received',
      'changed_at': DateTime.now().toIso8601String(),
    });

    return order['id'].toString();
  }

  /// Start the static-QR GCash flow: create the pending order, then show the
  /// seller's uploaded QR. NO PayMongo call — the customer scans the seller's
  /// own QR and pays their GCash wallet directly.
  Future<void> _startGcashPayment() async {
    if (!_canStartGcash) return;

    setState(() {
      _gcashCreatingPayment = true;
      _gcashError = null;
    });

    try {
      final orderId = await _createPendingOrder();
      if (orderId == null) throw Exception('Failed to create order');
      if (!mounted) return;
      setState(() {
        _gcashOrderId = orderId;
        _gcashPaymentPending = true;
        _gcashCreatingPayment = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gcashError = e.toString();
        _gcashCreatingPayment = false;
      });
    }
  }

  /// Manual confirmation: the seller has verified the payment arrived in
  /// their own GCash wallet. Marks the pending order paid (optionally with
  /// the GCash reference number from the notification), then completes the
  /// transaction.
  Future<void> _confirmGcashPayment() async {
    final orderId = _gcashOrderId;
    if (orderId == null || _gcashConfirming) return;

    setState(() => _gcashConfirming = true);
    try {
      await Supabase.instance.client.from('orders').update({
        'payment_status': 'paid',
        if (_gcashRefController.text.trim().isNotEmpty)
          'gcash_reference_number': _gcashRefController.text.trim(),
      }).eq('id', orderId);
      widget.onConfirm('GCash', 0, orderId: orderId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gcashError = 'Could not confirm payment: $e');
    } finally {
      if (mounted) setState(() => _gcashConfirming = false);
    }
  }

  /// Cancel the pending GCash payment and clean up the order.
  ///
  /// Also invoked when the sheet is closed (header X or system back) while a
  /// pending order exists — with no webhook to ever confirm it, a stranded
  /// pending order would permanently hold its inventory decrement.
  Future<void> _cancelGcashPayment() async {
    if (_gcashOrderId != null) {
      try {
        // Delete the order and its items
        await Supabase.instance.client
            .from('order_items')
            .delete()
            .eq('order_id', _gcashOrderId!);
        await Supabase.instance.client
            .from('orders')
            .delete()
            .eq('id', _gcashOrderId!);
      } catch (_) {
        // Best effort cleanup
      }
    }

    if (!mounted) return;
    setState(() {
      _gcashPaymentPending = false;
      _gcashOrderId = null;
      _gcashError = null;
    });
  }

  /// Close handler for the header X / system back: if a GCash pending order
  /// exists, cancel it first so no order is ever stranded unpaid.
  Future<void> _handleClose() async {
    if (_gcashPaymentPending) {
      await _cancelGcashPayment();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _gcashInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: AppConstants.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleClose();
      },
      child: DraggableScrollableSheet(
        initialChildSize: _method == 'GCash' ? 0.88 : 0.62,
        minChildSize: 0.45,
        maxChildSize: 0.90,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // ── Header (fixed, not scrollable) ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Payment',
                          style: AppConstants.bodyStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _handleClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              // ── Scrollable content area ──
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total:',
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₱${widget.total.toStringAsFixed(0)}',
                            style: AppConstants.monoStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Method:',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Segmented control matching the Products/Order toggle —
                      // equal-width segments, reliable tap targets, no label
                      // overflow, and a fail-closed disabled GCash segment.
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment<String>(
                            value: 'Cash',
                            label: const SizedBox(
                              width: 84,
                              child: Text(
                                'Cash',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            icon: const Icon(Icons.payments_outlined, size: 18),
                            // Locked while a GCash pending order exists — the
                            // seller must Confirm or Cancel before switching,
                            // so no pending order can ever be stranded.
                            enabled: !_gcashPaymentPending,
                          ),
                          ButtonSegment<String>(
                            value: 'GCash',
                            label: const SizedBox(
                              width: 84,
                              child: Text(
                                'GCash',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            icon: const Icon(Icons.qr_code_2, size: 18),
                            // Fail-closed: GCash stays tappable while store
                            // settings are still loading, but locks the moment
                            // we know no QR has been uploaded.
                            enabled: !_storeLoaded || _hasGcashQr,
                          ),
                        ],
                        selected: {_method},
                        onSelectionChanged: (selection) =>
                            setState(() => _method = selection.first),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? AppConstants.primary
                                : Colors.white,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) {
                              // Disabled (locked) segments render greyed so
                              // the affordance matches the caption below.
                              if (states.contains(WidgetState.disabled)) {
                                return AppConstants.secondary
                                    .withValues(alpha: 0.4);
                              }
                              return states.contains(WidgetState.selected)
                                  ? Colors.white
                                  : AppConstants.secondary;
                            },
                          ),
                        ),
                      ),
                      // Explain why GCash is locked when the store has no QR.
                      if (_storeLoaded && !_hasGcashQr) ...[
                        const SizedBox(height: 8),
                        Text(
                          'GCash needs a QR code — set it up in '
                          'Profile → Payment Methods first.',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            color: AppConstants.secondary.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      if (_method == 'Cash') ...[
                        const SizedBox(height: 20),
                        Text(
                          'Tendered:',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _tenderedController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          style: AppConstants.monoStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            prefixText: '₱ ',
                            filled: true,
                            fillColor: AppConstants.sellerSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Change:',
                              style: AppConstants.bodyStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₱${_change.toStringAsFixed(0)}',
                              style: AppConstants.monoStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_method == 'GCash') ...[
                        const SizedBox(height: 16),
                        // ── GCash Error ──
                        if (_gcashError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppConstants.error.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppConstants.error.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: AppConstants.error, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _gcashError!,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      color: AppConstants.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        // ── Store settings still loading ──
                        if (!_storeLoaded) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppConstants.primary,
                              ),
                            ),
                          ),
                        ]
                        // ── No QR uploaded yet → block GCash ──
                        else if (!_hasGcashQr) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppConstants.statusPendingColor
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppConstants.statusPendingColor
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.qr_code_2,
                                  color: AppConstants.statusPendingColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'GCash is not set up yet',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Upload your GCash QR code first: '
                                        'Profile → Payment Methods.',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 12,
                                          color: AppConstants.secondary
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
                        // ── Ready: create the pending order & show QR ──
                        else if (!_gcashPaymentPending) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  _gcashCreatingPayment ? null : _startGcashPayment,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppConstants.primary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _gcashCreatingPayment
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.qr_code_2, color: Colors.white),
                              label: Text(
                                _gcashCreatingPayment
                                    ? 'Creating order...'
                                    : 'Start GCash Payment',
                                style: AppConstants.bodyStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your uploaded QR code will be shown. The customer scans it and pays your GCash wallet directly — no PayMongo.',
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(alpha: 0.5),
                            ),
                          ),
                        ]
                        // ── Pending order: show static QR + confirm ──
                        else ...[
                          Center(
                            child: Container(
                              width: 280,
                              height: 280,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppConstants.borderGray
                                      .withValues(alpha: 0.5),
                                ),
                                boxShadow: AppConstants.sellerShadow,
                              ),
                              child: Image.network(
                                _gcashQrDisplayUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppConstants.borderGray,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if ((_store?['gcash_account_name']?.toString().trim().isNotEmpty ??
                                  false) ||
                              (_store?['gcash_number']?.toString().trim().isNotEmpty ??
                                  false)) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppConstants.sellerSurface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  if (_store?['gcash_account_name']?.toString().trim().isNotEmpty ??
                                      false)
                                    _gcashInfoRow(
                                      Icons.person_outline,
                                      'Account: ${_store!['gcash_account_name']}',
                                    ),
                                  if (_store?['gcash_number']?.toString().trim().isNotEmpty ??
                                      false)
                                    _gcashInfoRow(
                                      Icons.phone_outlined,
                                      'Number: ${_store!['gcash_number']}',
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            'Ask the customer to scan this QR with their GCash app and pay the amount shown.',
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _gcashRefController,
                                  focusNode: _gcashRefFocus,
                                  keyboardType: TextInputType.number,
                                  style: AppConstants.bodyStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText:
                                        'GCash reference number (optional)',
                                    hintText: 'From the payment notification',
                                    filled: true,
                                    fillColor: AppConstants.sellerSurface,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Scan-to-fill via on-device OCR — the detected
                              // value is always confirmed by the seller first.
                              // Manual typing above remains fully functional.
                              IconButton(
                                tooltip: 'Scan reference number',
                                onPressed: () async {
                                  final ref =
                                      await Navigator.of(context).push<String>(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const GcashRefScannerScreen(),
                                    ),
                                  );
                                  if (!mounted) return;
                                  if (ref != null) {
                                    _gcashRefController.text = ref;
                                    _gcashRefController.selection =
                                        TextSelection.collapsed(
                                      offset: ref.length,
                                    );
                                  }
                                  // Whether the seller scanned a value or chose
                                  // "Enter manually", land them in the field
                                  // to review/type (the value is still
                                  // editable — nothing is auto-submitted).
                                  _gcashRefFocus.requestFocus();
                                  setState(() {});
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      AppConstants.primary.withValues(alpha: 0.08),
                                  side: BorderSide(
                                    color: AppConstants.primary
                                        .withValues(alpha: 0.4),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  minimumSize: const Size(48, 48),
                                ),
                                icon: const Icon(
                                  Icons.document_scanner_outlined,
                                  color: AppConstants.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _cancelGcashPayment,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppConstants.error),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel Payment',
                                style: AppConstants.bodyStyle(
                                  color: AppConstants.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // ── Fixed footer — Confirm button pinned at bottom ──
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _canConfirm
                              ? AppConstants.accent
                              : Colors.grey.shade300,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: !_canConfirm || _gcashConfirming
                            ? null
                            : () {
                                if (_method == 'Cash') {
                                  if (_tendered < widget.total) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Tendered amount is insufficient.'),
                                        backgroundColor: AppConstants.error,
                                      ),
                                    );
                                    return;
                                  }
                                  widget.onConfirm(_method, _tendered);
                                } else {
                                  // GCash: seller confirms they received payment.
                                  _confirmGcashPayment();
                                }
                              },
                        child: Text(
                          _gcashConfirming
                              ? 'Confirming...'
                              : _method == 'GCash'
                                  ? 'Payment Received  ₱${widget.total.toStringAsFixed(0)}'
                                  : 'Confirm Payment  ₱${widget.total.toStringAsFixed(0)}',
                          style: AppConstants.bodyStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      ),
    );
  }
}

class _POSLineItem {
  final Map<String, dynamic> product;
  final String size;
  int quantity;

  _POSLineItem({
    required this.product,
    required this.size,
    required this.quantity,
  });
}

class _ScanHistoryEntry {
  final String barcode;
  final String productName;
  final String productId;

  const _ScanHistoryEntry({
    required this.barcode,
    required this.productName,
    required this.productId,
  });
}

```

---

# 2. `lib/services/order_service.dart`

```dartimport 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class OrderService {
  final SupabaseService _db;
  final SupabaseClient _client;

  OrderService({SupabaseService? db, SupabaseClient? client})
    : _db = db ?? SupabaseService.instance,
      _client = client ?? Supabase.instance.client;

  Future<String> placeOrder(Map<String, dynamic> dto) async {
    final order = await _db.createOrder(dto);
    return order['id'].toString();
  }



  /// Get order IDs for a store via products → order_items chain.
  /// Optionally filter by a single [status] or a list of [statuses],
  /// and optionally limit the number of IDs returned (applied at DB level).
  Future<List<dynamic>> _getOrderIdsForStore(
    String storeId, {
    String? status,
    List<String>? statuses,
    int? limit,
  }) async {
    final productRows = await _client
        .from('products')
        .select('id')
        .eq('store_id', storeId);
    final productIds = (productRows as List)
        .map((r) => (r as Map)['id'])
        .toList();
    if (productIds.isEmpty) return [];

    final itemRows = await _client
        .from('order_items')
        .select('order_id')
        .inFilter('product_id', productIds);
    final orderIds = (itemRows as List)
        .map((r) => (r as Map)['order_id'])
        .toSet()
        .toList();
    if (orderIds.isEmpty) return [];

    // Filters → order → limit (order before limit so DB sorts first)
    var query = _client
        .from('orders')
        .select('id')
        .inFilter('id', orderIds);
    if (statuses != null) {
      query = query.inFilter('status', statuses);
    } else if (status != null) {
      query = query.eq('status', status);
    }
    var ordered = query.order('created_at', ascending: false);
    if (limit != null) {
      ordered = ordered.limit(limit);
    }
    final rows = await ordered;
    return (rows as List).map((r) => (r as Map)['id']).toList();
  }

  /// Fetch orders for a store, filtered server-side.
  Future<List<Map<String, dynamic>>> fetchStoreOrders(
    String storeId, {
    String? status,
  }) async {
    final orderIds = await _getOrderIdsForStore(storeId, status: status);
    if (orderIds.isEmpty) return [];

    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'created_at',
        )
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);

    final orders = (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final customerIds = orders
        .map((o) => o['customer_id'] as dynamic)
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, Map<String, dynamic>> profilesMap = {};
    if (customerIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name, email')
          .inFilter('id', customerIds);
      for (final row in profiles as List) {
        final map = Map<String, dynamic>.from(row);
        profilesMap[map['id']] = map;
      }
    }

    final itemsData = await _client
        .from('order_items')
        .select('order_id, product_id, size, quantity')
        .inFilter('order_id', orderIds);

    final productIds = itemsData
        .map((i) => (i as Map)['product_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> productNameMap = {};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name')
          .inFilter('id', productIds);
      for (final row in products as List) {
        final map = Map<String, dynamic>.from(row);
        productNameMap[map['id']] = map['name'] ?? '';
      }
    }

    final itemsByOrder = <dynamic, List<Map<String, dynamic>>>{};
    for (final item in itemsData as List) {
      final map = Map<String, dynamic>.from(item);
      final orderId = map['order_id'];
      map['product_name'] = productNameMap[map['product_id']] ?? '';
      itemsByOrder.putIfAbsent(orderId, () => []).add(map);
    }

    for (final order in orders) {
      final profile = profilesMap[order['customer_id']];
      if (profile != null) {
        order['profiles'] = profile;
      }
      final items = itemsByOrder[order['id']] ?? [];
      order['order_items'] = items;
      order['quantity'] = items.fold<int>(
        0,
        (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
      );
    }

    return orders;
  }

  /// Most recent N pending orders for a store with customer name and
  /// product name. Only `pending`/`placed` orders are included.
  Future<List<Map<String, dynamic>>> getRecentOrders(
    String storeId, {
    int limit = 5,
  }) async {
    final orderIds = await _getOrderIdsForStore(
      storeId,
      statuses: const ['pending', 'placed'],
      limit: limit,
    );
    if (orderIds.isEmpty) return [];

    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, total_amount, status, created_at',
        )
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);

    final orders = (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final customerIds = orders
        .map((o) => o['customer_id'] as dynamic)
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> nameMap = {};
    if (customerIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', customerIds);
      for (final row in profiles as List) {
        final map = Map<String, dynamic>.from(row);
        nameMap[map['id']] = map['full_name'] ?? 'Customer';
      }
    }

    final itemsData = await _client
        .from('order_items')
        .select('order_id, product_id, quantity')
        .inFilter('order_id', orderIds);

    final productIds = itemsData
        .map((i) => (i as Map)['product_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> productNames = {};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name')
          .inFilter('id', productIds);
      for (final row in products as List) {
        final map = Map<String, dynamic>.from(row);
        productNames[map['id']] = map['name'] ?? '';
      }
    }

    Map<dynamic, String> orderProductNames = {};
    Map<dynamic, int> orderQuantities = {};
    for (final item in itemsData as List) {
      final map = Map<String, dynamic>.from(item);
      final orderId = map['order_id'];
      if (!orderProductNames.containsKey(orderId)) {
        orderProductNames[orderId] = productNames[map['product_id']] ?? '';
      }
      orderQuantities[orderId] = (orderQuantities[orderId] ?? 0) +
          ((map['quantity'] as num?)?.toInt() ?? 0);
    }

    for (final order in orders) {
      order['customer_name'] = nameMap[order['customer_id']] ?? 'Customer';
      order['product_name'] = orderProductNames[order['id']] ?? '';
      order['quantity'] = orderQuantities[order['id']] ?? 0;
    }

    return orders;
  }

  /// Count of orders grouped by status for a store.
  Future<Map<String, int>> getOrderCountByStatus(String storeId) async {
    final orderIds = await _getOrderIdsForStore(storeId);
    if (orderIds.isEmpty) return {};

    final data = await _client
        .from('orders')
        .select('id, status')
        .inFilter('id', orderIds)
        .neq('status', 'cancelled');

    final counts = <String, int>{};
    for (final row in data as List) {
      final status = row['status'] as String? ?? 'unknown';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _db.updateOrderStatus(orderId, newStatus);
  }

  /// Fetch POS transaction history for a store.
  ///
  /// Returns only orders with `source='pos'` (in-person sales),
  /// scoped to the given [storeId], ordered most-recent-first.
  /// Each order includes its line items with product names.
  ///
  /// Queries orders directly by store_id + source (no 3-step chain needed)
  /// since orders.store_id is reliably set during order creation.
  Future<List<Map<String, dynamic>>> fetchPosHistory(String storeId) async {
    // Fetch POS-only orders directly (store_id + source filter)
    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'payment_status, notes, created_at, source, '
          'amount_tendered, change_amount',
        )
        .eq('store_id', storeId)
        .eq('source', 'pos')
        .order('created_at', ascending: false);

    final orders = (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (orders.isEmpty) return [];

    // 2. Fetch order items with product names and images
    final allOrderIds = orders.map((o) => o['id']).toList();
    final itemsData = await _client
        .from('order_items')
        .select('order_id, product_id, size, quantity, unit_price')
        .inFilter('order_id', allOrderIds);

    // 3. Fetch product names and images
    final productIds = itemsData
        .map((i) => (i as Map)['product_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    Map<dynamic, String> productNames = {};
    Map<dynamic, String> productImages = {};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name, product_images(image_url, display_order)')
          .inFilter('id', productIds);
      for (final row in products as List) {
        final map = Map<String, dynamic>.from(row);
        productNames[map['id']] = map['name'] ?? '';
        // Get first image URL
        final images = map['product_images'] as List? ?? [];
        if (images.isNotEmpty) {
          final sorted = List<Map<String, dynamic>>.from(images)
            ..sort((a, b) => ((a['display_order'] ?? 0) as int)
                .compareTo(((b['display_order'] ?? 0) as int)));
          productImages[map['id']] = sorted.first['image_url']?.toString() ?? '';
        }
      }
    }

    // 4. Group items by order and enrich with product names and images
    final itemsByOrder = <dynamic, List<Map<String, dynamic>>>{};
    for (final item in itemsData as List) {
      final map = Map<String, dynamic>.from(item);
      map['product_name'] = productNames[map['product_id']] ?? '';
      map['product_image'] = productImages[map['product_id']] ?? '';
      itemsByOrder.putIfAbsent(map['order_id'], () => []).add(map);
    }

    for (final order in orders) {
      order['order_items'] = itemsByOrder[order['id']] ?? [];
      order['items_count'] = (order['order_items'] as List)
          .fold<int>(0, (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0));
    }

    return orders;
  }

  /// Fetch all orders for the currently logged-in customer.
  /// Returns orders with their items (product name, size, quantity) joined.
  Future<List<Map<String, dynamic>>> fetchMyOrders() async {
    final data = await _client
        .from('orders')
        .select(
          'id, customer_id, status, total_amount, payment_method, '
          'payment_status, created_at, store_id, '
          'order_items(id, product_id, size, quantity, unit_price, '
          'products(name, category, product_images(image_url, display_order)))',
        )
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Permanently delete a cancelled order (customer-owned action).
  ///
  /// The `status = 'cancelled'` filter is a guardrail: non-cancelled orders
  /// are never deletable through this call, even if invoked programmatically.
  /// Child rows (order_items, order_status_history) cascade via
  /// `ON DELETE CASCADE` on orders.id. RLS additionally scopes the delete
  /// to `auth.uid() = customer_id`.
  Future<void> deleteOrder(String orderId) async {
    await _client
        .from('orders')
        .delete()
        .eq('id', orderId)
        .eq('status', 'cancelled');
  }
}

```

---

# 3. `supabase/migrations/20260711_fix_trigger_security_definer.sql`

```sql-- ══════════════════════════════════════════════════════════════════
-- FIX: Add SECURITY DEFINER to inventory trigger functions
-- Date: July 4, 2026
--
-- ROOT CAUSE:
--   The `decrement_inventory_on_order` and `decrement_inventory_on_sale`
--   trigger functions run WITHOUT SECURITY DEFINER, meaning they execute
--   as the calling user (the authenticated customer). The `inventory`
--   table has RLS policies that only allow sellers and admins to UPDATE
--   rows. When a customer places an order, the trigger's UPDATE on
--   inventory is silently blocked by RLS, matching 0 rows, which causes
--   the function to raise 'Insufficient stock' — even when stock is 46.
--
--   The app's SELECT on inventory succeeds (there's a "viewable by
--   everyone" policy), so the app correctly sees stock=46. But the
--   trigger's UPDATE fails because the customer has no UPDATE policy.
--
-- FIX: Add SECURITY DEFINER so the functions run as the function owner
-- (supabase_admin), bypassing RLS. This is safe because these functions
-- only perform controlled stock decrements guarded by `stock >= quantity`.
-- ══════════════════════════════════════════════════════════════════

-- 1) Fix the ORDER trigger function
CREATE OR REPLACE FUNCTION public.decrement_inventory_on_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  update public.inventory
  set stock = stock - new.quantity
  where product_id = new.product_id
    and regexp_replace(size, '\D', '', 'g') = regexp_replace(new.size, '\D', '', 'g')
    and stock >= new.quantity;

  if not found then
    raise exception 'Insufficient stock for product % size %',
      new.product_id, new.size;
  end if;

  return new;
end;
$function$;

-- 2) Fix the SALE trigger function (POS sales have the same issue)
CREATE OR REPLACE FUNCTION public.decrement_inventory_on_sale()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  update public.inventory
  set stock = stock - new.quantity
  where product_id = new.product_id
    and regexp_replace(size, '\D', '', 'g') = regexp_replace(new.size, '\D', '', 'g')
    and stock >= new.quantity;

  if not found then
    raise exception 'Insufficient stock for product % size %',
      new.product_id, new.size;
  end if;

  return new;
end;
$function$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying the migration)
-- ══════════════════════════════════════════════════════════════════

-- A) Confirm SECURITY DEFINER is set on both functions
SELECT proname, proconfig
FROM pg_proc
WHERE proname IN ('decrement_inventory_on_order', 'decrement_inventory_on_sale');

-- B) Confirm inventory has the correct row for the test product
SELECT product_id, size, stock
FROM public.inventory
WHERE product_id = 'aaaaaaaa-0001-0001-0001-000000000001'
ORDER BY size;

-- C) Find and clean up orphaned orders (orders with 0 items)
SELECT o.id, o.status, o.total_amount, o.created_at,
       (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id)
ORDER BY o.created_at DESC;

-- D) Delete orphaned orders (uncomment after reviewing Step C results)
-- DELETE FROM orders
-- WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = orders.id);

```