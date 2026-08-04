import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/product_service.dart';
import '../../widgets/seller/payment_method_pill.dart';
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

  double _productPrice(Map<String, dynamic> product) {
    final value = product['price'];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return double.tryParse('$value') ?? 0;
  }

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
                      // Price
                      Text(
                        '₱${_productPrice(product).toStringAsFixed(0)}',
                        style: AppConstants.monoStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
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
  String _method = 'Cash';

  // PayMongo QR Ph GCash state
  bool _gcashPaymentPending = false;
  String? _gcashQrImageBase64; // PayMongo QR Ph image (base64)
  String? _gcashOrderId;
  bool _gcashCreatingPayment = false;
  String? _gcashError;
  Timer? _pollTimer;

  double get _tendered => double.tryParse(_tenderedController.text) ?? 0;
  double get _change => (_tendered - widget.total).clamp(0, double.infinity);

  bool get _canConfirm {
    if (_method == 'Cash') return true; // validated on press
    // GCash: only confirm if payment is already pending (waiting for webhook)
    return false;
  }

  bool get _canStartGcash => !_gcashCreatingPayment && !_gcashPaymentPending;

  @override
  void dispose() {
    _tenderedController.dispose();
    _pollTimer?.cancel();
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

  /// Start the GCash payment flow: create order + call PayMongo Edge Function.
  Future<void> _startGcashPayment() async {
    if (!_canStartGcash) return;

    setState(() {
      _gcashCreatingPayment = true;
      _gcashError = null;
    });

    try {
      // Step 1: Create the order with pending status
      final orderId = await _createPendingOrder();
      if (orderId == null) throw Exception('Failed to create order');

      // Step 2: Call PayMongo Edge Function to create GCash source
      final response = await Supabase.instance.client.functions.invoke(
        'create-gcash-payment',
        body: {
          'orderId': int.tryParse(orderId) ?? orderId,
          'amount': widget.total,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Payment creation failed';
        throw Exception(error);
      }

      setState(() {
        _gcashOrderId = orderId;
        _gcashQrImageBase64 = response.data['qrImageBase64'];
        _gcashPaymentPending = true;
        _gcashCreatingPayment = false;
      });

      // Step 3: Start polling for payment status
      _startPolling(orderId);
    } catch (e) {
      setState(() {
        _gcashError = e.toString();
        _gcashCreatingPayment = false;
      });
    }
  }

  /// Poll the order's payment_status every 3 seconds.
  void _startPolling(String orderId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final order = await Supabase.instance.client
            .from('orders')
            .select('payment_status')
            .eq('id', orderId)
            .single();

        if (order['payment_status'] == 'paid') {
          _pollTimer?.cancel();
          if (mounted) {
            // Payment confirmed — auto-complete the transaction
            widget.onConfirm('GCash', 0, orderId: orderId);
          }
        }
      } catch (_) {
        // Polling error — will retry on next tick
      }
    });
  }

  /// Cancel the pending GCash payment and clean up the order.
  Future<void> _cancelGcashPayment() async {
    _pollTimer?.cancel();

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

    setState(() {
      _gcashPaymentPending = false;
      _gcashQrImageBase64 = null;
      _gcashOrderId = null;
      _gcashError = null;
    });
  }

  /// Build the QR Ph image from a base64-encoded string.
  Widget _buildQrPhImage(String base64Data) {
    try {
      // Log the raw data for debugging
      debugPrint('[QR-PH] Raw data length: ${base64Data.length}');
      debugPrint('[QR-PH] Starts with: ${base64Data.substring(0, base64Data.length > 60 ? 60 : base64Data.length)}');
      
      // Strip data URI prefix if present (e.g. "data:image/png;base64,...")
      String raw;
      if (base64Data.contains(',')) {
        raw = base64Data.split(',').last;
        debugPrint('[QR-PH] Stripped data URI prefix, raw length: ${raw.length}');
      } else {
        raw = base64Data;
        debugPrint('[QR-PH] No data URI prefix found, using raw data');
      }
      
      final bytes = base64Decode(raw);
      debugPrint('[QR-PH] Decoded bytes length: ${bytes.length}');
      
      if (bytes.isEmpty) {
        debugPrint('[QR-PH] ERROR: Decoded bytes are empty!');
        return const Center(
          child: Text('QR image is empty'),
        );
      }
      
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        width: 280,
        height: 280,
      );
    } catch (e) {
      debugPrint('[QR-PH] ERROR decoding QR image: $e');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppConstants.error, size: 32),
            const SizedBox(height: 8),
            Text(
              'Failed to load QR image',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.error,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              e.toString(),
              style: AppConstants.bodyStyle(
                fontSize: 10,
                color: AppConstants.error.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _method == 'GCash' ? 0.82 : 0.55,
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
                      onPressed: () => Navigator.of(context).pop(),
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
                      Row(
                        children: [
                          PaymentMethodPill(
                            label: 'Cash',
                            isSelected: _method == 'Cash',
                            onTap: () => setState(() => _method = 'Cash'),
                          ),
                          const SizedBox(width: 8),
                          PaymentMethodPill(
                            label: 'GCash',
                            isSelected: _method == 'GCash',
                            onTap: () => setState(() => _method = 'GCash'),
                          ),

                        ],
                      ),
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
                        // ── GCash QR Ph Code (PayMongo) ──
                        if (_gcashPaymentPending && _gcashQrImageBase64 != null) ...[
                          Center(
                            child: Container(
                              width: 300,
                              height: 300,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                                ),
                                boxShadow: AppConstants.sellerShadow,
                              ),
                              child: _buildQrPhImage(_gcashQrImageBase64!),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Status indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppConstants.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Waiting for payment...',
                                style: AppConstants.bodyStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.secondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ask the customer to scan this QR with their GCash app',
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Cancel button
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
                        ]
                        // ── Start GCash Payment button ──
                        else if (!_gcashPaymentPending) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _gcashCreatingPayment ? null : _startGcashPayment,
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
                                _gcashCreatingPayment ? 'Creating payment...' : 'Generate GCash QR',
                                style: AppConstants.bodyStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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
                        backgroundColor: _canConfirm ? AppConstants.accent : Colors.grey.shade300,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: !_canConfirm
                          ? null
                          : () {
                              if (_method == 'Cash' && _tendered < widget.total) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tendered amount is insufficient.'),
                                    backgroundColor: AppConstants.error,
                                  ),
                                );
                                return;
                              }
                              widget.onConfirm(
                                _method,
                                _tendered,
                                // GCash now auto-confirms via polling — no manual ref needed
                              );
                            },
                      child: Text(
                        'Confirm Payment  ₱${widget.total.toStringAsFixed(0)}',
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
