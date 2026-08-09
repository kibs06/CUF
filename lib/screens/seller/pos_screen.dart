import 'dart:async';

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
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/seller/fly_to_order_animation.dart';
import 'gcash_ref_scanner_screen.dart';
import 'pos_barcode_scanner.dart';
import 'pos_history_screen.dart';

class POSScreen extends StatefulWidget {
  final bool isStandalonePage;

  const POSScreen({super.key, this.isStandalonePage = false});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen>
    with TickerProviderStateMixin {
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

  /// Target of the fly-to-order flight — the Order segment of the top toggle.
  /// Resolves while the flight fires; also anchors the landing pulse.
  final GlobalKey _orderSegmentKey = GlobalKey();
  late final AnimationController _orderPulseController;
  late final Animation<double> _orderPulseScale;

  /// Quick fade when switching Products ⇄ Order panels — consistent motion
  /// language without losing each panel's state (IndexedStack stays mounted).
  late final AnimationController _panelFadeController;
  late final Animation<double> _panelFade;

  @override
  void initState() {
    super.initState();
    _orderPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    // Landing pulse: a quick scale-up (with a back overshoot) then settle.
    _orderPulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_orderPulseController);
    _panelFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..value = 1; // start fully visible; fade in on each panel switch
    _panelFade = CurvedAnimation(
      parent: _panelFadeController,
      curve: Curves.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadSellerProducts();
    });
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _orderPulseController.dispose();
    _panelFadeController.dispose();
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

  void _addLineItem(
    Map<String, dynamic> product,
    String size,
    int quantity, {
    Offset? source,
  }) {
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
      // Deliberately do NOT switch to the Order panel here — the seller
      // stays on Products and taps the Order segment when they're ready.
      // The bottom strip and the fly-to-Order animation still show the
      // updated count/total immediately.
    });

    // Fly-to-order animation — fired AFTER the real state update above, so
    // the flight is purely cosmetic and can never gate or delay the order
    // data. If the Add button's position wasn't captured (unlikely), fall
    // back to screen center so the animation never crashes or misfires.
    if (mounted) {
      final images = product['images'] as List?;
      final imageUrl = images?.isNotEmpty == true ? '${images!.first}' : null;
      FlyToOrderAnimation.show(
        context: context,
        source: source ??
            Offset(
              MediaQuery.of(context).size.width / 2,
              MediaQuery.of(context).size.height / 2,
            ),
        targetKey: _orderSegmentKey,
        imageUrl: imageUrl,
        onLanded: _pulseOrderSegment,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to order'),
        backgroundColor: AppConstants.success,
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  /// Brief bounce on the Order segment when a flight lands.
  void _pulseOrderSegment() {
    if (!mounted) return;
    _orderPulseController.forward(from: 0);
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

    // Captured synchronously in the Add button's onPressed — the sheet pops
    // immediately after, so the button's global position must be read first.
    final addButtonKey = GlobalKey();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
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
                          key: addButtonKey,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppConstants.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            // Read the button's global position BEFORE the
                            // sheet pops — it is the flight's source point.
                            final box = addButtonKey.currentContext
                                ?.findRenderObject() as RenderBox?;
                            Offset? source;
                            if (box != null && box.hasSize) {
                              source = box.localToGlobal(
                                Offset(
                                  box.size.width / 2,
                                  box.size.height / 2,
                                ),
                              );
                            }
                            Navigator.of(context).pop();
                            _addLineItem(
                              product,
                              selectedSize,
                              quantity,
                              source: source,
                            );
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
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
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
    HapticFeedback.mediumImpact();

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
                  segments: [
                    ButtonSegment<int>(
                      value: 0,
                      label: const SizedBox(
                        width: 96,
                        child: Text(
                          'Products',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      icon: const Icon(Icons.grid_view_outlined),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: SizedBox(
                        // Flight target + landing-pulse anchor. Lives on a
                        // stable render widget so the GlobalKey always
                        // resolves while the flight is running.
                        key: _orderSegmentKey,
                        width: 96,
                        child: AnimatedBuilder(
                          animation: _orderPulseScale,
                          builder: (context, child) => Transform.scale(
                            scale: 1 + _orderPulseScale.value * 0.35,
                            child: child,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Order'),
                              if (_itemCount > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  constraints:
                                      const BoxConstraints(minWidth: 18),
                                  decoration: BoxDecoration(
                                    color: _panelIndex == 1
                                        ? Colors.white
                                        : AppConstants.primary,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.18,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '$_itemCount',
                                    textAlign: TextAlign.center,
                                    style: AppConstants.monoStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _panelIndex == 1
                                          ? AppConstants.primary
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                    ),
                  ],
                  selected: {_panelIndex},
                  onSelectionChanged: (selection) {
                    setState(() => _panelIndex = selection.first);
                    _panelFadeController.forward(from: 0);
                  },
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
                child: FadeTransition(
                  opacity: _panelFade,
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
      // Skeleton grid — reuse the shared ShimmerBox so the first paint feels
      // instant instead of a bare spinner.
      return MasonryGridView.count(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        itemCount: 8,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppConstants.cardRadius,
            boxShadow: AppConstants.sellerShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AspectRatio(
                aspectRatio: 1.0,
                child: ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(width: 120, height: 12, borderRadius: 6),
                    SizedBox(height: 8),
                    ShimmerBox(width: 56, height: 12, borderRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateWidget(
                      icon: Icons.search_off_rounded,
                      title: 'No matching products',
                      subtitle: 'Try a different keyword or category.',
                    ),
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
      child: _PressScale(
        enabled: !out,
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
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: AppConstants.stadiumRadius,
                        ),
                        child: Text(
                          badgeText,
                          style: AppConstants.bodyStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = _scanHistory[index];
          final products = context.read<ProductProvider>().products;
          final match = products.where((p) => p['id'].toString() == entry.productId).toList();
          final product = match.isNotEmpty ? match.first : null;
          final hasStock = product != null && _availableSizes(product).isNotEmpty;

          return GestureDetector(
            onTap: hasStock ? () => _openProductSheet(product) : null,
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
            OutlinedButton(
              onPressed: _confirmClearOrder,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.error,
                side: BorderSide(
                  color: AppConstants.error.withValues(alpha: 0.35),
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Clear',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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
    final images = item.product['images'] as List?;
    final imageUrl = images?.isNotEmpty == true ? '${images!.first}' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.sellerShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product thumbnail — same source as the grid tiles; falls back to
          // the stock icon when a product has no image.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 38,
              height: 38,
              child: imageUrl.isEmpty
                  ? _orderLineFallbackImage()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          _orderLineFallbackImage(),
                    ),
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

  /// Placeholder for an order line without an image — the same soft beige
  /// tile + stock icon used by the product grid's image-less state.
  Widget _orderLineFallbackImage() {
    return Container(
      color: AppConstants.primary.withValues(alpha: 0.14),
      child: const Icon(
        Icons.inventory_2_outlined,
        size: 18,
        color: AppConstants.primary,
      ),
    );
  }

  Widget _quantityButton(IconData icon, bool enabled, VoidCallback onPressed) {
    // Bordered stepper with a generous tap target — the wide horizontal
    // padding keeps the − and + buttons clearly separated from the count so
    // sellers don't mis-tap between them.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkResponse(
        radius: 24,
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? AppConstants.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: enabled
                  ? AppConstants.primary.withValues(alpha: 0.35)
                  : Colors.grey.shade300,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppConstants.primary : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
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
    final showCheckout = _panelIndex == 1;
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
          // Checkout button — Order tab only. Slides in from the right when
          // the seller opens the Order panel and slides back out to the right
          // on Products. Driven directly by _panelIndex (single source of
          // truth) via implicit animations, so rapid tab switches retarget
          // cleanly instead of queuing. The button keeps its layout slot, so
          // the summary above never reflows — only the button moves.
          IgnorePointer(
            ignoring: !showCheckout,
            child: AnimatedSlide(
              offset: showCheckout ? Offset.zero : const Offset(1.25, 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              child: AnimatedOpacity(
                opacity: showCheckout ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        hasItems ? AppConstants.accent : Colors.grey.shade300,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppConstants.buttonRadius,
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
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppConstants.accent, Color(0xFF3DBDB4)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.accent.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ],
                ),
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
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
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
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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

    // NOTE: order_items and order_status_history are intentionally NOT
    // written here — the inventory-decrement trigger fires on order_items
    // INSERT, so stock must not move until the seller confirms payment.
    // Both are written in _confirmGcashPayment() at that exact point.
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
      // Mark the pending order paid first, then write the line items. The
      // inventory-decrement trigger fires on order_items INSERT, so stock
      // only moves at this confirmation point — never when the QR screen
      // opens, and never for a cancelled attempt.
      await Supabase.instance.client.from('orders').update({
        'payment_status': 'paid',
        if (_gcashRefController.text.trim().isNotEmpty)
          'gcash_reference_number': _gcashRefController.text.trim(),
      }).eq('id', orderId);

      // Write the line items — the only point stock is decremented for
      // GCash sales. A failure here surfaces as _gcashError (below) and
      // onConfirm is not called, so no partial transaction completes.
      final items = widget.items.values.map((item) => {
        'order_id': orderId,
        'product_id': item.product['id'],
        'size': item.size,
        'quantity': item.quantity,
        'unit_price': widget.productPrice(item.product),
      }).toList();
      // Single batched insert = one transaction: if any line fails the
      // trigger (e.g. insufficient stock), the WHOLE batch rolls back — a
      // paid order can never end up with partial items or partial stock,
      // and a retry can't duplicate already-inserted rows.
      await Supabase.instance.client.from('order_items').insert(items);

      // Status history alongside the items so the order timeline is complete.
      await Supabase.instance.client.from('order_status_history').insert({
        'order_id': orderId,
        'status': 'received',
        'changed_at': DateTime.now().toIso8601String(),
      });

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
  /// pending order exists. A pending order holds no inventory — order_items
  /// are only written at confirm time — so cancelling never touches stock;
  /// it simply deletes the lightweight orders row.
  Future<void> _cancelGcashPayment() async {
    if (_gcashOrderId != null) {
      try {
        // Safety net only: order_items are no longer written until payment
        // is confirmed (see _confirmGcashPayment), so there are normally no
        // items to delete here, and stock is never decremented until then —
        // nothing to reverse on cancel. Kept defensive in case a future code
        // path inserts items earlier again.
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

/// Subtle press-scale micro-interaction: the child scales down briefly while
/// pressed and springs back on release — the premium-feel tap feedback used
/// across POS tappable cards. Sits outside the InkWell so both ripple and
/// scale coexist.
class _PressScale extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _PressScale({required this.child, this.enabled = true});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // A raw Listener (not GestureDetector): pointer events bypass the gesture
    // arena, so this reliably fires even though the inner InkWell owns the tap
    // gesture. The InkWell still supplies the ripple + tap action.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled
          ? (_) => setState(() => _pressed = true)
          : null,
      onPointerUp: widget.enabled
          ? (_) => setState(() => _pressed = false)
          : null,
      onPointerCancel: widget.enabled
          ? (_) => setState(() => _pressed = false)
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
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
