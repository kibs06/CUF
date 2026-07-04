import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/product_service.dart';
import '../../widgets/seller/payment_method_pill.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
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
        return DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.32,
          maxChildSize: 0.62,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final total = _productPrice(product) * quantity;
                return Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
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
                        'Size',
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
                );
              },
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
          onConfirm: (method, tendered) {
            Navigator.of(context).pop();
            _completePOSTransaction(method, tendered);
          },
        );
      },
    );
  }

  Future<void> _completePOSTransaction(
    String paymentMethod,
    double cashTendered,
  ) async {
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final items = List<_POSLineItem>.from(_orderItems.values);

    // Build items list for the order
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
    );

    // Auto-sync active status for each product after POS sale
    for (final item in items) {
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
            onPressed: () {},
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
                  ? const Icon(
                      Icons.qr_code_scanner,
                      color: AppConstants.secondary,
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
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Text(
                    'No matching products',
                    style: AppConstants.bodyStyle(color: Colors.grey.shade500),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
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

    return Opacity(
      opacity: out ? 0.48 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: out ? null : () => _openProductSheet(product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 65,
                child: Container(
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  child: imageUrl.isEmpty
                      ? Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.grey.shade400,
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.grey.shade400,
                          ),
                        ),
                ),
              ),
              Expanded(
                flex: 35,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name'] ?? 'Product',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₱${_productPrice(product).toStringAsFixed(0)}',
                            style: AppConstants.monoStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primary,
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: out
                                ? Colors.grey.shade200
                                : low
                                ? AppConstants.lowStockColor.withValues(
                                    alpha: 0.12,
                                  )
                                : AppConstants.okStockColor.withValues(
                                    alpha: 0.12,
                                  ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            out
                                ? 'Out'
                                : low
                                ? 'Low ($stock)'
                                : 'In Stock',
                            style: AppConstants.bodyStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: out
                                  ? Colors.grey.shade600
                                  : low
                                  ? AppConstants.lowStockColor
                                  : AppConstants.okStockColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
                      'Size ${item.size}',
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$_itemCount items · ₱${_subtotal.toStringAsFixed(0)}',
              style: AppConstants.monoStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _orderItems.isEmpty ? null : _openCheckoutSheet,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(
              'Checkout',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
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
  final void Function(String method, double tendered) onConfirm;

  const _CheckoutSheet({required this.total, required this.onConfirm});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final TextEditingController _tenderedController = TextEditingController();
  String _method = 'Cash';

  double get _tendered => double.tryParse(_tenderedController.text) ?? 0;
  double get _change => (_tendered - widget.total).clamp(0, double.infinity);

  @override
  void dispose() {
    _tenderedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.45,
      maxChildSize: 0.86,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(context).viewInsets.bottom + 22,
            ),
            children: [
              Row(
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
              const Divider(),
              const SizedBox(height: 8),
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
                  const SizedBox(width: 8),
                  const PaymentMethodPill(
                    label: 'Card',
                    isSelected: false,
                    isDisabled: true,
                    disabledTooltip: 'Coming soon',
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
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.accent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (_method == 'Cash' && _tendered < widget.total) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tendered amount is insufficient.'),
                        backgroundColor: AppConstants.error,
                      ),
                    );
                    return;
                  }
                  widget.onConfirm(_method, _tendered);
                },
                child: Text(
                  'Confirm Payment  ₱${widget.total.toStringAsFixed(0)}',
                  style: AppConstants.bodyStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
