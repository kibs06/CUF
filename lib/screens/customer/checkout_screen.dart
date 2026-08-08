import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../constants/app_constants.dart';
import '../../models/address_model.dart';
import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../utils/delivery_date.dart';
import '../../services/gcash_payment_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';
import 'address_book_screen.dart';
import 'tracking_screen.dart';

/// Stages of the online GCash payment flow.
enum _GcashStage { none, launching, waiting, confirming, failed }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with SingleTickerProviderStateMixin {
  int _checkoutStep = 0; // 0: Details/Payment, 1: Confirmation

  final _formKey = GlobalKey<FormState>();
  String _paymentMethod = 'GCash';
  Address? _selectedAddress;

  // Confirmed order data (populated after successful placement)
  String? _placedOrderId;
  Map<String, dynamic>? _placedOrder;
  double _placedTotal = 0;

  // ── Online GCash payment flow (edge-function driven) ────────────
  GcashPaymentService? _gcashService;
  Timer? _gcashPollTimer;
  StreamSubscription<Uri>? _appLinksSub;
  AppLinks? _appLinks;
  _GcashStage _gcashStage = _GcashStage.none;
  String? _gcashOrderId;
  String? _gcashCheckoutUrl;
  List<Map<String, dynamic>> _gcashItems = [];
  int _gcashPollAttempts = 0;
  String? _gcashErrorMessage;

  bool get _isGcashFlowActive => _gcashStage != _GcashStage.none;

  // Cart validation state
  bool _isValidatingCart = false;
  List<_CartItemValidation> _itemValidations = [];
  bool _isSubmitting = false;

  // Animation controller for checkmark
  late AnimationController _checkController;
  late Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );

    // Load address book and validate cart on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAddress();
      _validateCart();
    });
  }

  @override
  void dispose() {
    _gcashPollTimer?.cancel();
    _appLinksSub?.cancel();
    _checkController.dispose();
    super.dispose();
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
    debugPrint('[CHECKOUT-SCREEN] _validateCart() called — items: ${cart.items.length}, selected: ${cart.selectedCount}');
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
    if (cart.selectedItems.isEmpty) return false;
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
          content: Text('Please select a delivery address before placing your order.'),
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

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);

    final items = cart.selectedItems;
    if (items.isEmpty) return;

    // Calculate total from selected items
    double orderTotal = 0;
    for (final item in items) {
      orderTotal += (item['price'] as double) * (item['quantity'] as int);
    }
    orderTotal += cart.selectedDeliveryFee; // ₱100 delivery

    // GCash: real redirect payment — the server creates the order in
    // 'awaiting_payment' and returns a PayMongo checkout URL. The cart is
    // cleared only AFTER the verified webhook marks the order paid.
    if (_paymentMethod == 'GCash') {
      await _startGcashCheckout(items: items);
      return;
    }

    // Build items list for the order
    final orderItems = items.map((item) => {
      'product_id': item['product_id'],
      'product_name': item['product_name'] ?? 'Product',
      'size': item['size'] ?? '',
      'variant_id': item['variant_id'],
      'quantity': item['quantity'] as int,
      'unit_price': item['price'] as double,
    }).toList();

    final order = await orderProvider.placeOrder(
      customerId: auth.profile?['id'] ?? '',
      items: orderItems,
      totalAmount: orderTotal,
      deliveryAddress: _selectedAddress!.formattedAddress,
      paymentMethod: _paymentMethod,
      shippingAddress: _selectedAddress!.toSnapshot(),
    );

    if (order != null && mounted) {
      // Clear ordered items from the server AND local state
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

      setState(() {
        _itemValidations = [];
        _checkoutStep = 1;
        _placedOrderId = order['id']?.toString();
        _placedOrder = order;
        _placedTotal = orderTotal;
      });

      _checkController.forward();
    } else if (mounted) {
      final stockErr = orderProvider.stockError;
      final errorMsg = stockErr?.friendlyMessage ??
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
                  child: const Text(
                    'Go to Cart',
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
  // GCASH FLOW — create intent → system browser → deep-link/button
  // return → poll get-payment-status → confirm ONLY when paid
  // ═══════════════════════════════════════════════════════════════

  Future<void> _startGcashCheckout({
    required List<Map<String, dynamic>> items,
  }) async {
    final gcash = _gcashService ??= GcashPaymentService();
    final idempotencyKey = const Uuid().v4();
    _gcashItems = items;

    setState(() {
      _isSubmitting = true;
      _gcashStage = _GcashStage.launching;
      _gcashErrorMessage = null;
    });

    try {
      final result = await gcash.createIntent(
        idempotencyKey: idempotencyKey,
        items: items
            .map((i) => {
                  'product_id': i['product_id'],
                  'size': i['size'] ?? '',
                  'quantity': i['quantity'],
                })
            .toList(),
        deliveryAddress: _selectedAddress?.formattedAddress,
        shippingAddress: _selectedAddress?.toSnapshot(),
      );

      if (!mounted) return;
      _gcashOrderId = result.orderId;
      _gcashCheckoutUrl = result.checkoutUrl;
      _setupAppLinks();

      setState(() {
        _isSubmitting = false;
        _gcashStage = _GcashStage.waiting;
      });

      // System browser (decision: external) — the browser hands the
      // gcash:// deep link to the GCash app natively.
      await launchUrl(
        Uri.parse(result.checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
    } on GcashPaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _gcashStage = _GcashStage.none;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppConstants.error,
        ),
      );
    } catch (e) {
      debugPrint('[CHECKOUT-GCASH] createIntent error: $e');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _gcashStage = _GcashStage.none;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start the GCash payment. Please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  /// Listen for the deep-link return (solvision://checkout/gcash) while the
  /// GCash flow is active. The "I've Completed Payment" button covers every
  /// return path, so the link is a convenience, not a dependency.
  void _setupAppLinks() {
    _appLinks ??= AppLinks();
    _appLinksSub ??= _appLinks!.uriLinkStream.listen((Uri? uri) {
      if (uri != null && uri.scheme == 'solvision') {
        _onGcashReturn();
      }
    }, onError: (Object e) {
      debugPrint('[CHECKOUT-GCASH] app_links error: $e');
    });
    // Warm relaunch (app was killed, then reopened via the link).
    unawaited(_appLinks!.getInitialLink().then((Uri? uri) {
      if (uri != null && uri.scheme == 'solvision' && _isGcashFlowActive) {
        _onGcashReturn();
      }
    }));
  }

  /// The customer returned from GCash (deep link or button) — start
  /// polling the authoritative status.
  void _onGcashReturn() {
    if (_gcashOrderId == null) return;
    if (_gcashStage == _GcashStage.waiting ||
        _gcashStage == _GcashStage.confirming) {
      setState(() => _gcashStage = _GcashStage.confirming);
      _startGcashPolling();
    }
  }

  void _startGcashPolling() {
    _gcashPollTimer?.cancel();
    _gcashPollAttempts = 0;
    unawaited(_pollGcashStatus());
    _gcashPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollGcashStatus()),
    );
  }

  Future<void> _pollGcashStatus() async {
    final orderId = _gcashOrderId;
    if (orderId == null) return;
    _gcashPollAttempts++;
    try {
      final status = await _gcashService!.getStatus(orderId);
      if (!mounted) return;

      if (status.paid) {
        _gcashPollTimer?.cancel();
        await _finalizeGcashOrder(status);
        return;
      }
      final terminal = status.paymentStatus == 'failed' ||
          status.status == 'cancelled' ||
          status.intentStatus == 'failed' ||
          status.intentStatus == 'expired';
      if (terminal) {
        _gcashPollTimer?.cancel();
        setState(() {
          _gcashStage = _GcashStage.failed;
          _gcashErrorMessage = _gcashFailureMessage(status);
        });
        return;
      }
      // Still pending — keep polling until the timeout budget is spent.
      if (_gcashPollAttempts >= 30) {
        _gcashPollTimer?.cancel();
        setState(() {
          _gcashStage = _GcashStage.waiting;
          _gcashErrorMessage =
              'Your payment is still being confirmed. You can check again, or we will finalize your order automatically.';
        });
      }
    } catch (e) {
      debugPrint('[CHECKOUT-GCASH] poll error: $e');
      if (!mounted) return;
      if (_gcashPollAttempts >= 30) {
        _gcashPollTimer?.cancel();
        setState(() {
          _gcashStage = _GcashStage.waiting;
          _gcashErrorMessage =
              'We had trouble checking your payment. Please check again in a moment.';
        });
      }
    }
  }

  /// Payment confirmed by the webhook — load the real order row, clear the
  /// cart (server + local), and show the confirmation step.
  Future<void> _finalizeGcashOrder(GcashStatusResult status) async {
    try {
      final order = await Supabase.instance.client
          .from('orders')
          .select('*')
          .eq('id', status.orderId)
          .single();
      if (!mounted) return;
      final cart = context.read<CartProvider>();
      final items = cart.selectedItems;
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
      if (!mounted) return;
      setState(() {
        _itemValidations = [];
        _checkoutStep = 1;
        _gcashStage = _GcashStage.none;
        _placedOrderId = order['id']?.toString();
        _placedOrder = Map<String, dynamic>.from(order);
        _placedTotal = status.totalAmount;
      });
      _checkController.forward();
    } catch (e) {
      debugPrint('[CHECKOUT-GCASH] finalize error: $e');
      if (!mounted) return;
      setState(() {
        _gcashStage = _GcashStage.waiting;
        _gcashErrorMessage =
            'Your payment was confirmed, but we had trouble loading your order. You can find it under My Orders.';
      });
    }
  }

  String _gcashFailureMessage(GcashStatusResult status) {
    if (status.intentStatus == 'expired') {
      return 'Your payment session expired before the payment was completed. No charge was made — you can try again.';
    }
    if (status.status == 'cancelled' || status.paymentStatus == 'failed') {
      return 'Your payment was not completed and no charge was made. You can try again with GCash or choose Cash on Pickup.';
    }
    return 'Your payment could not be confirmed. No charge was made — you can try again.';
  }

  /// Abandon the GCash flow (no charge yet). The pending order is closed
  /// server-side by the expiry sweep; the cart is left intact.
  void _cancelGcashFlow() {
    _gcashPollTimer?.cancel();
    setState(() {
      _gcashStage = _GcashStage.none;
      _gcashErrorMessage = null;
      _gcashOrderId = null;
      _gcashCheckoutUrl = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

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
                icon:
                    const Icon(Icons.arrow_back, color: AppConstants.secondary),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _checkoutStep == 1
              ? _buildConfirmationStep()
              : _isGcashFlowActive
                  ? _buildGcashFlow()
                  : _buildFormStep(cart),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // GCASH FLOW UI
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGcashFlow() {
    switch (_gcashStage) {
      case _GcashStage.launching:
      case _GcashStage.confirming:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppConstants.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _gcashStage == _GcashStage.launching
                    ? 'Connecting to GCash…'
                    : 'Confirming your payment…',
                style: AppConstants.headlineStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _gcashStage == _GcashStage.launching
                    ? 'Please wait while we prepare a secure payment.'
                    : 'We are verifying your payment with GCash. This usually takes a few seconds.',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );

      case _GcashStage.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppConstants.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.payment, size: 34, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  'Payment not completed',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  _gcashErrorMessage ??
                      'Your payment could not be completed. No charge was made.',
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: SolePrimaryButton(
                    label: 'Try Again',
                    onPressed: () => unawaited(
                      _startGcashCheckout(items: _gcashItems),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cancelGcashFlow,
                  child: const Text('Back to Checkout'),
                ),
              ],
            ),
          ),
        );

      case _GcashStage.waiting:
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppConstants.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 38,
                    color: AppConstants.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Complete your payment in GCash',
                  textAlign: TextAlign.center,
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  'We opened GCash to authorize your payment. Once you are done, return here and your order will be confirmed automatically.',
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                if (_gcashErrorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _gcashErrorMessage!,
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.error,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: SolePrimaryButton(
                    label: "I've Completed Payment",
                    onPressed: _onGcashReturn,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    final url = _gcashCheckoutUrl;
                    if (url != null) {
                      unawaited(
                        launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ),
                      );
                    }
                  },
                  child: const Text('Open GCash again'),
                ),
                TextButton(
                  onPressed: _cancelGcashFlow,
                  child: Text(
                    'Cancel Checkout',
                    style: AppConstants.bodyStyle(
                      color: AppConstants.secondary.withValues(alpha: 0.6),
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
  // STEP 1: Order Summary + Delivery + Payment + Submit
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFormStep(CartProvider cart) {
    final selectedItems = cart.selectedItems;
    final selectedCount = cart.selectedCount;

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
                  text: '${v.productName} is no longer available. Please remove it from your cart.',
                  bgColor: AppConstants.error.withValues(alpha: 0.08),
                  borderColor: AppConstants.error.withValues(alpha: 0.2),
                  iconColor: AppConstants.error,
                ),

            // ── Insufficient stock banners ────────────────────
            for (final v in _itemValidations)
              if (v.isAvailable && v.insufficientStock)
                _buildBanner(
                  icon: Icons.warning_amber_outlined,
                  text: '${v.productName} only has ${v.currentStock} left in stock. Please reduce quantity to $v.currentStock or less.',
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
            Text('Order Summary ($selectedCount item${selectedCount != 1 ? 's' : ''})',
                style: AppConstants.headlineStyle(fontSize: 16)),
            const SizedBox(height: 12),
            SoleCard(
              color: Colors.white,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (int i = 0; i < selectedItems.length; i++) ...[
                    _OrderItemRow(item: selectedItems[i]),
                    if (i < selectedItems.length - 1)
                      const Divider(
                          height: 1,
                          color: AppConstants.borderGray,
                          indent: 14,
                          endIndent: 14),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Section 2: Deliver To ─────────────────────────
            Text('Deliver To',
                style: AppConstants.headlineStyle(fontSize: 16)),
            const SizedBox(height: 12),
            _buildDeliveryCard(),
            const SizedBox(height: 24),

            // ── Section 3: Payment ────────────────────────────
            Text('Payment Method',
                style: AppConstants.headlineStyle(fontSize: 16)),
            const SizedBox(height: 12),
            SoleCard(
              color: Colors.white,
              child: Column(
                children: [
                  _buildPaymentRadio('GCash', 'Pay using GCash e-wallet',
                      Icons.account_balance_wallet_outlined),
                  const Divider(color: AppConstants.borderGray, height: 1),
                  _buildPaymentRadio('Cash on Pickup',
                      'Pay cash at Carcar studio', Icons.storefront_outlined),
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
                            'Your payment information is encrypted and secure',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(alpha: 0.45),
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

            // ── Section 4: Price Breakdown & Submit ───────────
            SoleCard(
              color: AppConstants.primary.withValues(alpha: 0.04),
              child: Column(
                children: [
                  _priceRow('Subtotal', '₱${cart.selectedSubtotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                  _priceRow('Delivery Fee', '₱${cart.selectedDeliveryFee.toStringAsFixed(2)}'),
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
                            color: AppConstants.secondary.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Estimated delivery: ${formatDeliveryDate(getEstimatedDeliveryDate(DateTime.now()))}',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.secondary.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppConstants.borderGray, height: 20),
                  _priceRow(
                    'Total Amount Due',
                    '₱${cart.selectedTotal.toStringAsFixed(2)}',
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
        color: Colors.white,
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
                const Icon(
                  Icons.chevron_right,
                  color: AppConstants.primary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Has a selected address
    return SoleCard(
      color: Colors.white,
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
                            color: AppConstants.secondary.withValues(alpha: 0.5),
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

  Widget _priceRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppConstants.bodyStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        )),
        Text(value, style: AppConstants.monoStyle(
          fontSize: bold ? 16 : 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: bold ? AppConstants.primary : AppConstants.secondary,
        )),
      ],
    );
  }

  Widget _buildPaymentRadio(
      String method, String subtitle, IconData icon) {
    // Wrap in Material so the tap ripple/selection highlight paints on a
    // Material ancestor instead of being hidden by SoleCard's DecoratedBox.
    return Material(
      color: Colors.transparent,
      child: RadioListTile(
        activeColor: AppConstants.primary,
        value: method,
        groupValue: _paymentMethod,
        title: Row(
          children: [
            Icon(icon, color: AppConstants.primary, size: 20),
            const SizedBox(width: 8),
            Text(method,
                style:
                    AppConstants.bodyStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        subtitle: Text(subtitle,
            style:
                AppConstants.bodyStyle(fontSize: 12, color: Colors.black54)),
        onChanged: (val) {
          setState(() {
            _paymentMethod = val as String;
          });
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STEP 2: Confirmation
  // ═══════════════════════════════════════════════════════════════

  Widget _buildConfirmationStep() {
    final orderIdDisplay = _placedOrderId != null
        ? '#${_placedOrderId!.length > 8 ? _placedOrderId!.substring(_placedOrderId!.length - 8) : _placedOrderId}'
        : 'N/A';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: AppConstants.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 48,
                  color: AppConstants.surfaceLight,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Thank You!',
              style: AppConstants.headlineStyle(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              'Your order has been successfully placed with the artisan studio.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SoleCard(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _confirmationRow('Order ID', orderIdDisplay),
                  const SizedBox(height: 8),
                  _confirmationRow('Total', '₱${_placedTotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  _confirmationRow('Payment Type', _paymentMethod),
                ],
              ),
            ),
            const SizedBox(height: 40),
            SolePrimaryButton(
              label: 'Track My Order',
              onPressed: _placedOrder != null
                  ? () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => OrderTrackingScreen(order: _placedOrder!),
                        ),
                      );
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text(
                'Back to Home',
                style: AppConstants.bodyStyle(
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _confirmationRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppConstants.bodyStyle(color: Colors.black54)),
        Text(
          value,
          style: AppConstants.monoStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppConstants.primary,
          ),
        ),
      ],
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
                child: const Icon(Icons.broken_image, size: 18, color: AppConstants.primary),
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
                  'EU ${item['size']} · ${item['color']} · Qty: $quantity',
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
