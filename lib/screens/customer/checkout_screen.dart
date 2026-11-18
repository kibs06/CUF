import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import '../../models/address_model.dart';
import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../utils/delivery_date.dart';
import '../../utils/size_key.dart';
import '../../services/direct_gcash_service.dart';
import '../../services/voucher_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/order_confirmation_view.dart';
import '../../widgets/sole_primary_button.dart';
import 'address_book_screen.dart';
import 'gcash_pay_screen.dart';
import 'tracking_screen.dart';

class CheckoutScreen extends StatefulWidget {
  /// Direct-checkout items (Buy Now flow). When provided, checkout runs
  /// entirely from this list — the cart is neither read for items nor
  /// written to, so backing out returns to the product with the cart
  /// untouched. When null, checkout operates on the cart's selected
  /// items (normal Cart → Checkout flow).
  final List<Map<String, dynamic>>? directItems;

  const CheckoutScreen({super.key, this.directItems});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _checkoutStep = 0; // 0: Details/Payment, 1: Confirmation

  final _formKey = GlobalKey<FormState>();
  String _paymentMethod = 'GCash';
  Address? _selectedAddress;

  // Confirmed order data (populated after successful placement)
  String? _placedOrderId;
  Map<String, dynamic>? _placedOrder;
  double _placedTotal = 0;

  // Buy Now direct-checkout mode (widget.directItems != null): the
  // ordered items come straight from the product screen and the cart
  // is never touched — no reads for totals, no removals after purchase.
  bool get _isDirectCheckout => widget.directItems != null;

  /// The items this checkout will order: the passed-in direct list in
  /// Buy Now mode, otherwise the cart's selected items.
  List<Map<String, dynamic>> _checkoutItems(CartProvider cart) =>
      _isDirectCheckout ? widget.directItems! : cart.selectedItems;

  double _checkoutSubtotal(List<Map<String, dynamic>> items) => items.fold(
    0.0,
    (sum, item) =>
        sum + ((item['price'] as double) * (item['quantity'] as int)),
  );

  // Cart validation state
  bool _isValidatingCart = false;
  List<_CartItemValidation> _itemValidations = [];
  bool _isSubmitting = false;

  // Voucher (ANQUI item #5). The client only ever sends the CODE — the
  // discount shown here comes from the server-side quote, and the orders
  // trigger re-evaluates it inside the order's own transaction, so a
  // stale quote can never be charged.
  final _voucherController = TextEditingController();
  VoucherQuote? _voucherQuote;
  String? _voucherError;
  bool _voucherApplying = false;

  /// The server quote only counts once it actually granted a discount.
  VoucherQuote? get _appliedVoucher =>
      (_voucherQuote?.hasDiscount ?? false) ? _voucherQuote : null;

  double get _voucherDiscount => _appliedVoucher?.discountAmount ?? 0;

  /// The checkout cart in the shape the server prices from — it looks unit
  /// prices up itself, so only identity + quantity are sent.
  List<Map<String, dynamic>> _voucherItems(List<Map<String, dynamic>> items) =>
      items
          .map(
            (i) => {
              'product_id': i['product_id'],
              'size': i['size'] ?? '',
              'quantity': i['quantity'],
            },
          )
          .toList();

  @override
  void initState() {
    super.initState();

    // Load address book and validate cart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAddress();
      _validateCart();
    });
  }

  @override
  void dispose() {
    _voucherController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // VOUCHER — quote a code server-side and show the real discount
  // ═══════════════════════════════════════════════════════════════

  /// Asks the server what this code is worth against the CURRENT cart and
  /// stores the result. Returns the quote (null when there is nothing to
  /// price). [silent] skips the inline error line — used by the pre-submit
  /// re-check, where the caller decides what to tell the customer.
  Future<VoucherQuote?> _applyVoucher(
    String code, {
    bool silent = false,
  }) async {
    final cart = context.read<CartProvider>();
    final items = _voucherItems(_checkoutItems(cart));
    if (items.isEmpty) return null;

    setState(() {
      _voucherApplying = true;
      if (!silent) _voucherError = null;
    });

    final quote = await VoucherService().validate(code: code, items: items);
    if (!mounted) return quote;

    setState(() {
      _voucherApplying = false;
      if (quote.hasDiscount) {
        _voucherQuote = quote;
        _voucherController.text = quote.code;
        _voucherError = null;
      } else if (!silent) {
        _voucherQuote = null;
        _voucherError = quote.message.isNotEmpty
            ? quote.message
            : 'That code could not be applied.';
      }
    });

    return quote;
  }

  /// The voucher stopped being valid between entry and submit. Never
  /// proceed silently at the higher price — ask.
  Future<bool> _confirmDropVoucher(String code, String reason) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Voucher no longer valid'),
        content: Text(
          reason.isEmpty
              ? 'The code "$code" can no longer be applied. Continue without it?'
              : '$reason\n\nContinue without "$code"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Review my cart'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue without it'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  void _clearVoucher() {
    setState(() {
      _voucherQuote = null;
      _voucherError = null;
      _voucherController.clear();
    });
  }

  Widget _buildVoucherBody() {
    final applied = _appliedVoucher;

    if (applied != null) {
      return Row(
        children: [
          const Icon(
            Icons.local_offer_outlined,
            size: 18,
            color: AppConstants.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  applied.code,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.secondary,
                  ),
                ),
                Text(
                  'You save ₱${applied.discountAmount.toStringAsFixed(2)}',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.success,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _voucherApplying ? null : _clearVoucher,
            child: const Text('Remove'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _voucherController,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enabled: !_voucherApplying,
                decoration: InputDecoration(
                  hintText: 'Voucher code',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  filled: true,
                  fillColor: AppConstants.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppConstants.borderGray.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                onSubmitted: (value) => _applyVoucher(value),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _voucherApplying
                  ? null
                  : () => _applyVoucher(_voucherController.text),
              child: _voucherApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Apply'),
            ),
          ],
        ),
        if (_voucherError != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                size: 15,
                color: AppConstants.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _voucherError!,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.error,
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'Discount codes are verified on our server and applied to your order total.',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.45),
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD ADDRESS — fetch default/saved address on init
  // ═══════════════════════════════════════════════════════════════

  void _loadAddress() {
    final auth = context.read<AuthProvider>();
    final userId = auth.profile?['id'] ?? auth.currentUser?['id'];
    if (userId == null) return;

    final addressProvider = context.read<AddressProvider>();
    addressProvider.loadAddresses(userId).then((_) {
      if (mounted && _selectedAddress == null) {
        // Auto-select the default address
        final addr = addressProvider.defaultAddress;
        if (addr != null) {
          setState(() => _selectedAddress = addr);
          addressProvider.setSelectedAddress(addr);
        }
      }
    });
  }

  Future<void> _pickAddress() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.profile?['id'] ?? auth.currentUser?['id'];
    if (userId == null) return;

    // Ensure addresses are loaded
    final addressProvider = context.read<AddressProvider>();
    if (addressProvider.addresses.isEmpty) {
      await addressProvider.loadAddresses(userId);
    }
    if (!mounted) return;

    final result = await Navigator.of(context).push<Address>(
      MaterialPageRoute(
        builder: (_) => const AddressBookScreen(selectionMode: true),
      ),
    );

    if (result != null && mounted) {
      setState(() => _selectedAddress = result);
      addressProvider.setSelectedAddress(result);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // VALIDATION — shows warnings, does NOT auto-remove items
  // ═══════════════════════════════════════════════════════════════

  Future<void> _validateCart() async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    // Buy Now direct checkout: items aren't in the cart, so the cart
    // validation service (which validates server cart rows) doesn't
    // apply. Order placement re-validates stock server-side anyway.
    if (_isDirectCheckout) return;
    debugPrint(
      '[CHECKOUT-SCREEN] _validateCart() called — items: ${cart.items.length}, selected: ${cart.selectedCount}',
    );
    if (cart.items.isEmpty) {
      if (_itemValidations.isNotEmpty) {
        setState(() => _itemValidations = []);
      }
      return;
    }

    setState(() {
      _isValidatingCart = true;
      _itemValidations = [];
    });

    try {
      final results = await cart.validateForCheckout();
      if (!mounted) return;

      final validations = results.map((r) {
        return _CartItemValidation(
          productName: r.productName,
          isAvailable: r.isAvailable,
          currentPrice: r.currentPrice,
          cartPrice: r.cartPrice,
          priceChanged: r.priceChanged,
          currentStock: r.currentStock,
          cartQuantity: r.cartQuantity,
          insufficientStock: r.insufficientStock,
        );
      }).toList();

      setState(() {
        _itemValidations = validations;
        _isValidatingCart = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isValidatingCart = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // STOCK + ADDRESS GATE — blocks Place Order
  // ═══════════════════════════════════════════════════════════════

  bool _canSubmitOrder(CartProvider cart) {
    if (_checkoutItems(cart).isEmpty) return false;
    if (_isValidatingCart) return false;
    if (_selectedAddress == null) return false; // Must have an address
    for (final v in _itemValidations) {
      if (!v.isAvailable || v.insufficientStock) return false;
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // SUBMIT — creates order with ALL selected items + address snapshot
  // ═══════════════════════════════════════════════════════════════

  Future<void> _submitCheckout() async {
    if (_isValidatingCart) return;
    if (!_formKey.currentState!.validate()) return;

    // Block if no address selected
    if (_selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a delivery address before placing your order.',
          ),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    // Re-validate stock immediately before submission
    await _validateCart();
    if (!mounted) return;
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (!_canSubmitOrder(cart)) return;

    // A voucher is only worth what the server says it is worth RIGHT NOW:
    // the cart, the code's window, or its usage cap may have moved since it
    // was applied. The order trigger checks again (that is the enforcement),
    // so this is purely so the customer gets a clear message here instead of
    // a failed payment.
    final applied = _appliedVoucher;
    if (applied != null) {
      final quote = await _applyVoucher(applied.code, silent: true);
      if (!mounted) return;
      if (quote == null || !quote.hasDiscount) {
        final proceed = await _confirmDropVoucher(
          applied.code,
          quote?.message ?? '',
        );
        if (!mounted || !proceed) return;
        _clearVoucher();
      }
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);

    final items = _checkoutItems(cart);
    if (items.isEmpty) return;

    // Calculate total from selected items
    double orderTotal = 0;
    for (final item in items) {
      orderTotal += (item['price'] as double) * (item['quantity'] as int);
    }
    orderTotal += orderTotal > 0 ? 100.0 : 0.0; // ₱100 delivery
    orderTotal -= _voucherDiscount; // server re-applies this on insert

    // GCash (manual): the server creates the order in
    // 'awaiting_payment_confirmation' (stock reserved) and returns the
    // platform account + order code. The customer pays in their own GCash
    // app and submits proof; a seller verifies it and an admin reconciles
    // the funds before any payout.
    if (_paymentMethod == 'GCash') {
      await _startGcashCheckout(
        items: items,
        voucherCode: _appliedVoucher?.code,
      );
      return;
    }

    // Build items list for the order
    final orderItems = items
        .map(
          (item) => {
            'product_id': item['product_id'],
            'product_name': item['product_name'] ?? 'Product',
            'size': item['size'] ?? '',
            'variant_id': item['variant_id'],
            'quantity': item['quantity'] as int,
            'unit_price': item['price'] as double,
          },
        )
        .toList();

    final order = await orderProvider.placeOrder(
      customerId: auth.profile?['id'] ?? '',
      items: orderItems,
      totalAmount: orderTotal,
      deliveryAddress: _selectedAddress!.formattedAddress,
      paymentMethod: _paymentMethod,
      shippingAddress: _selectedAddress!.toSnapshot(),
      voucherCode: _appliedVoucher?.code,
    );

    if (order != null && mounted) {
      // Clear ordered items from the server AND local state. In Buy Now
      // direct mode nothing was ever added to the cart, so there's
      // nothing to remove.
      if (!_isDirectCheckout) {
        final orderedServerIds = items
            .map((item) => item['server_id'] as String?)
            .where((id) => id != null)
            .cast<String>()
            .toList();
        if (orderedServerIds.isNotEmpty) {
          await cart.removeServerItems(orderedServerIds);
        } else {
          await cart.clearCartFromServer();
        }
        for (final item in items) {
          final key = item['id'] as String;
          cart.removeFromCart(key);
        }
      }

      setState(() {
        _itemValidations = [];
        _checkoutStep = 1;
        _placedOrderId = order['id']?.toString();
        _placedOrder = order;
        // The server owns the money — with a voucher the trigger has
        // already rewritten total_amount, so display what it returned.
        _placedTotal =
            (order['total_amount'] as num?)?.toDouble() ?? orderTotal;
      });
    } else if (mounted) {
      final stockErr = orderProvider.stockError;
      final errorMsg =
          stockErr?.friendlyMessage ??
          orderProvider.errorMessage ??
          'Something went wrong placing your order. Please try again.';
      debugPrint('Checkout failed: $errorMsg');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          backgroundColor: AppConstants.error,
          content: Row(
            children: [
              Expanded(
                child: Text(
                  errorMsg,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (stockErr != null)
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    _isDirectCheckout ? 'Go Back' : 'Go to Cart',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  /// Take the customer to the GCash checkout they already have open, from the
  /// "awaiting confirmation" refusal. The tracking screen is the right
  /// destination rather than the pay screen: it renders the live countdown and
  /// carries both endings (finish paying, or cancel the order), and it loads the
  /// platform account itself — the pay screen expects those details to be handed
  /// to it by the flow that created the order.
  Future<void> _openPendingGcashCheckout() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    try {
      final pending = await DirectGcashService().fetchPendingCheckout();
      if (!mounted) return;
      if (pending == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'That checkout is no longer open. Place the order again.',
            ),
          ),
        );
        return;
      }
      final order = await Supabase.instance.client
          .from('orders')
          .select('*')
          .eq('id', pending.id)
          .single();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(order: order),
        ),
      );
    } catch (e) {
      debugPrint('[CHECKOUT] open pending gcash failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open your pending checkout. Find it under My Orders.',
          ),
        ),
      );
    }
  }

  // MANUAL GCASH FLOW: the server creates the order (stock reserved, 30-min
  // pay window) and returns the PLATFORM GCash account + order code. The
  // customer pays in their own GCash app and submits the proof on the next
  // screen; a seller verifies it and an admin reconciles the funds.
  Future<void> _startGcashCheckout({
    required List<Map<String, dynamic>> items,
    String? voucherCode,
  }) async {
    // Vouchers are applied by the cash order RPC only. Charging full price
    // would be worse than refusing, so stop before the order exists.
    if (voucherCode != null && voucherCode.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vouchers can\'t be used with GCash yet. Remove the voucher or '
            'choose cash on pickup.',
          ),
          backgroundColor: AppConstants.error,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await DirectGcashService().createCheckout(
        items: items
            .map(
              (i) => {
                'product_id': i['product_id'],
                'size': i['size'] ?? '',
                'quantity': i['quantity'],
              },
            )
            .toList(),
        deliveryAddress: _selectedAddress?.formattedAddress,
        shippingAddress: _selectedAddress?.toSnapshot(),
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // The items stay in the cart until the order is actually paid — the
      // customer may abandon here and still see their cart intact.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GcashPayScreen(
            orderId: result.orderId,
            storeId: result.storeId,
            totalAmount: result.totalAmount,
            deadline: result.deadline,
            storeName: result.storeName,
            orderCode: result.orderCode,
            gcashQrUrl: result.gcashQrUrl,
            gcashNumber: result.gcashNumber,
            gcashAccountName: result.gcashAccountName,
          ),
        ),
      );
    } on DirectGcashException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // The one-open-order cap is not a dead end: the order it is complaining
      // about is the customer's own, waiting to be paid or cancelled. Make the
      // message itself a way into it.
      final hasOpenCheckout = e.code == '23505';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: GestureDetector(
            onTap: hasOpenCheckout ? _openPendingGcashCheckout : null,
            child: Text(e.message),
          ),
          action: hasOpenCheckout
              ? SnackBarAction(
                  label: 'Open',
                  textColor: Colors.white,
                  onPressed: _openPendingGcashCheckout,
                )
              : null,
          backgroundColor: AppConstants.error,
          duration: Duration(seconds: hasOpenCheckout ? 8 : 5),
        ),
      );
    } catch (e) {
      debugPrint('[CHECKOUT-GCASH] create checkout error: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start the GCash checkout. Please try again.',
          ),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          _checkoutStep == 0 ? 'Checkout Details' : 'Order Confirmed',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _checkoutStep == 0
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _checkoutStep == 1 ? _buildConfirmationStep() : _buildFormStep(cart),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STEP 1: Order Summary + Delivery + Payment + Submit
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFormStep(CartProvider cart) {
    // Buy Now passes its own item list; the cart's selection is ignored.
    final selectedItems = _checkoutItems(cart);
    final selectedCount = selectedItems.fold<int>(
      0,
      (sum, item) => sum + (item['quantity'] as int),
    );
    final selectedSubtotal = _checkoutSubtotal(selectedItems);
    final selectedDeliveryFee = selectedSubtotal > 0 ? 100.0 : 0.0;
    final voucherDiscount = _voucherDiscount;
    final selectedTotal =
        selectedSubtotal + selectedDeliveryFee - voucherDiscount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Validation banner ─────────────────────────────
            if (_isValidatingCart)
              _buildBanner(
                icon: Icons.sync,
                text: 'Verifying prices and availability...',
                bgColor: AppConstants.primary.withValues(alpha: 0.08),
                borderColor: AppConstants.primary.withValues(alpha: 0.2),
                iconColor: AppConstants.primary,
              ),

            // ── Out of stock banners ──────────────────────────
            for (final v in _itemValidations)
              if (!v.isAvailable)
                _buildBanner(
                  icon: Icons.error_outline,
                  text:
                      '${v.productName} is no longer available. Please remove it from your cart.',
                  bgColor: AppConstants.error.withValues(alpha: 0.08),
                  borderColor: AppConstants.error.withValues(alpha: 0.2),
                  iconColor: AppConstants.error,
                ),

            // ── Insufficient stock banners ────────────────────
            for (final v in _itemValidations)
              if (v.isAvailable && v.insufficientStock)
                _buildBanner(
                  icon: Icons.warning_amber_outlined,
                  text:
                      '${v.productName} only has ${v.currentStock} left in stock. Please reduce quantity to $v.currentStock or less.',
                  bgColor: AppConstants.error.withValues(alpha: 0.08),
                  borderColor: AppConstants.error.withValues(alpha: 0.2),
                  iconColor: AppConstants.error,
                ),

            // ── Price change banners ──────────────────────────
            for (final v in _itemValidations)
              if (v.priceChanged && v.isAvailable && !v.insufficientStock)
                _buildBanner(
                  icon: Icons.price_change_outlined,
                  text:
                      '${v.productName} — Price updated to ₱${v.currentPrice.toStringAsFixed(2)}',
                  bgColor: AppConstants.primary.withValues(alpha: 0.06),
                  borderColor: AppConstants.primary.withValues(alpha: 0.15),
                  iconColor: AppConstants.primary,
                ),

            // ── Section 1: Order Summary ──────────────────────
            Text(
              'Order Summary ($selectedCount item${selectedCount != 1 ? 's' : ''})',
              style: AppConstants.headlineStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            SoleCard(
              color: AppConstants.surfaceLight,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (int i = 0; i < selectedItems.length; i++) ...[
                    _OrderItemRow(item: selectedItems[i]),
                    if (i < selectedItems.length - 1)
                      Divider(
                        height: 1,
                        color: AppConstants.borderGray,
                        indent: 14,
                        endIndent: 14,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Section 2: Deliver To ─────────────────────────
            Text('Deliver To', style: AppConstants.headlineStyle(fontSize: 16)),
            const SizedBox(height: 12),
            _buildDeliveryCard(),
            const SizedBox(height: 24),

            // ── Section 3: Payment ────────────────────────────
            Text(
              'Payment Method',
              style: AppConstants.headlineStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            SoleCard(
              color: AppConstants.surfaceLight,
              child: Column(
                children: [
                  RadioGroup<String>(
                    groupValue: _paymentMethod,
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => _paymentMethod = val);
                    },
                    child: Column(
                      children: [
                        _buildPaymentRadio(
                          'GCash',
                          'Pay the store directly via GCash',
                          Icons.account_balance_wallet_outlined,
                        ),
                        Divider(color: AppConstants.borderGray, height: 1),
                        _buildPaymentRadio(
                          'Cash on Pickup',
                          'Pay cash at Carcar studio',
                          Icons.storefront_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Secure checkout indicator
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: AppConstants.secondary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You\'ll pay the CUFMAI GCash account, then upload your receipt. The store verifies it before your order is prepared — no gateway fee.',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(
                                alpha: 0.45,
                              ),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Section 4: Voucher code ───────────────────────
            Text('Voucher', style: AppConstants.headlineStyle(fontSize: 16)),
            const SizedBox(height: 12),
            SoleCard(
              color: AppConstants.surfaceLight,
              child: _buildVoucherBody(),
            ),
            const SizedBox(height: 24),

            // ── Section 5: Price Breakdown & Submit ───────────
            SoleCard(
              color: AppConstants.primary.withValues(alpha: 0.04),
              child: Column(
                children: [
                  _priceRow(
                    'Subtotal',
                    '₱${selectedSubtotal.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 6),
                  _priceRow(
                    'Delivery Fee',
                    '₱${selectedDeliveryFee.toStringAsFixed(2)}',
                  ),
                  if (voucherDiscount > 0) ...[
                    const SizedBox(height: 6),
                    _priceRow(
                      'Voucher (${_appliedVoucher?.code ?? ''})',
                      '−₱${voucherDiscount.toStringAsFixed(2)}',
                      color: AppConstants.success,
                    ),
                  ],
                  // Manual GCash: no gateway, so no gateway surcharge line at
                  // all. (The old 'GCash Fee — None' row hinted at a fee that
                  // does not exist in this flow.)
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.schedule_outlined,
                            size: 13,
                            color: AppConstants.secondary.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Estimated delivery: ${formatDeliveryDate(getEstimatedDeliveryDate(DateTime.now()))}',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: AppConstants.borderGray, height: 20),
                  _priceRow(
                    'Total Amount Due',
                    '₱${selectedTotal.toStringAsFixed(2)}',
                    bold: true,
                  ),
                  const SizedBox(height: 16),
                  SolePrimaryButton(
                    label: 'Complete Order',
                    onPressed: (_isSubmitting || !_canSubmitOrder(cart))
                        ? null
                        : _submitCheckout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Delivery Card ───────────────────────────────────────────

  Widget _buildDeliveryCard() {
    // No addresses saved at all
    if (_selectedAddress == null) {
      return SoleCard(
        color: AppConstants.surfaceLight,
        child: GestureDetector(
          onTap: _pickAddress,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppConstants.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_location_alt_outlined,
                    size: 20,
                    color: AppConstants.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a delivery address',
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Required to place your order',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppConstants.primary),
              ],
            ),
          ),
        ),
      );
    }

    // Has a selected address
    return SoleCard(
      color: AppConstants.surfaceLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  size: 20,
                  color: AppConstants.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _selectedAddress!.recipientName,
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedAddress!.recipientPhone,
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedAddress!.formattedAddress,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickAddress,
            child: Text(
              'Change',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppConstants.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required String text,
    required Color bgColor,
    required Color borderColor,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? AppConstants.secondary,
          ),
        ),
        Text(
          value,
          style: AppConstants.monoStyle(
            fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color:
                color ?? (bold ? AppConstants.primary : AppConstants.secondary),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRadio(String method, String subtitle, IconData icon) {
    // Wrap in Material so the tap ripple/selection highlight paints on a
    // Material ancestor instead of being hidden by SoleCard's DecoratedBox.
    // Group selection (groupValue/onChanged) is handled by the enclosing
    // RadioGroup<String>.
    return Material(
      color: Colors.transparent,
      child: RadioListTile(
        activeColor: AppConstants.primary,
        value: method,
        title: Row(
          children: [
            Icon(icon, color: AppConstants.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              method,
              style: AppConstants.bodyStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STEP 2: Confirmation
  // ═══════════════════════════════════════════════════════════════

  Widget _buildConfirmationStep() {
    return OrderConfirmationView(
      orderId: _placedOrderId ?? '',
      total: _placedTotal,
      paymentLabel: _paymentMethod,
      onTrackOrder: _placedOrder != null
          ? () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(order: _placedOrder!),
                ),
              );
            }
          : null,
      onBackHome: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Order Item Row (shown in checkout summary)
// ═════════════════════════════════════════════════════════════════

class _OrderItemRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final price = item['price'] as double;
    final quantity = item['quantity'] as int;
    final lineTotal = price * quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item['imageUrl'] ?? '',
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 48,
                height: 48,
                color: AppConstants.borderGray.withValues(alpha: 0.2),
                child: const Icon(
                  Icons.broken_image,
                  size: 18,
                  color: AppConstants.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + variant
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['product_name'] ?? '',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatSize(item['size']?.toString() ?? '')} · ${item['color']} · Qty: $quantity',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Price
          Text(
            '₱${lineTotal.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Validation result helper
// ═════════════════════════════════════════════════════════════════

class _CartItemValidation {
  final String productName;
  final bool isAvailable;
  final double currentPrice;
  final double cartPrice;
  final bool priceChanged;
  final int currentStock;
  final int cartQuantity;
  final bool insufficientStock;

  const _CartItemValidation({
    required this.productName,
    required this.isAvailable,
    required this.currentPrice,
    required this.cartPrice,
    required this.priceChanged,
    required this.currentStock,
    this.cartQuantity = 1,
    this.insufficientStock = false,
  });
}
