# Full Source: checkout_screen.dart + app_constants.dart

## lib/screens/customer/checkout_screen.dart

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../models/cart_item_with_details.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/address_service.dart';
import '../../services/order_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_text_field.dart';
import 'address_form_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  OrderService? _orderService;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _paymentMethod;
  String? _address;
  String? _selectedAddressId;
  AddressService? _addressService;
  List<Map<String, dynamic>> _addresses = [];
  String? _customerName;
  String? _contactNumber;
  String? _deliveryInstruction;
  bool _useSeparateInfo = false;
  String? _gcashLink;
  bool _isGcashChecking = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _orderService = OrderService();
    _addressService = AddressService();
    await _loadAddresses();
    final authProvider = context.read<AuthProvider>();
    _customerName = authProvider.profile?['full_name'] as String? ?? '';
    _contactNumber = authProvider.profile?['contact_number'] as String? ?? '';
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await _addressService!.getAddresses();
      if (mounted) {
        setState(() {
          _addresses = addresses;
          final defaultAddr = addresses.cast<Map<String, dynamic>?>().firstWhere(
                (a) => a?['is_default'] == true,
                orElse: () => addresses.isNotEmpty ? addresses.first : null,
              );
          if (defaultAddr != null) {
            _selectedAddressId = defaultAddr['id'] as String?;
            _address = _formatAddress(defaultAddr);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading addresses: $e')),
        );
      }
    }
  }

  String _formatAddress(Map<String, dynamic> addr) {
    final parts = <String>[
      if (addr['street'] != null && (addr['street'] as String).isNotEmpty)
        addr['street'] as String,
      if (addr['barangay'] != null && (addr['barangay'] as String).isNotEmpty)
        addr['barangay'] as String,
      if (addr['city'] != null && (addr['city'] as String).isNotEmpty)
        addr['city'] as String,
      if (addr['province'] != null && (addr['province'] as String).isNotEmpty)
        addr['province'] as String,
      if (addr['zip_code'] != null && (addr['zip_code'] as String).isNotEmpty)
        addr['zip_code'] as String,
    ];
    return parts.join(', ');
  }

  Future<void> _submitOrder() async {
    if (_paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method')),
      );
      return;
    }
    if (_selectedAddressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery address')),
      );
      return;
    }
    if (_useSeparateInfo) {
      if (_customerName == null || _customerName!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter the customer name')),
        );
        return;
      }
      if (_contactNumber == null || _contactNumber!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter the contact number')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final cart = context.read<CartProvider>();
      final result = await _orderService!.createOrder(
        paymentMethod: _paymentMethod!,
        addressId: _selectedAddressId!,
        customerName: _useSeparateInfo ? _customerName! : null,
        contactNumber: _useSeparateInfo ? _contactNumber! : null,
        deliveryInstruction: _deliveryInstruction,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // All GCash payments go to "pending" — the webhook marks them paid.
        // All other payments (COD) go directly to "confirmed".
        if (_paymentMethod == 'gcash_qr') {
          setState(() => _isGcashChecking = true);
          // Give the webhook a moment to process
          Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() => _isGcashChecking = false);
            // After 3 seconds, try to fetch the latest order to see if
            // the webhook has succeeded.
            _checkGcashPaymentStatus(result['order_id']);
          });
        } else {
          cart.clearCart();
          _showSuccessDialog(
            orderId: result['order_id']?.toString() ?? '',
            paymentMethod: _paymentMethod!,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to create order'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppConstants.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _checkGcashPaymentStatus(String? orderId) async {
    if (orderId == null) return;
    try {
      final order = await _orderService!.getOrderById(int.parse(orderId));
      if (!mounted) return;
      if (order != null && order.status == 'confirmed') {
        // Clear cart
        final cart = context.read<CartProvider>();
        cart.clearCart();
        _showSuccessDialog(
          orderId: orderId,
          paymentMethod: 'gcash_qr',
        );
      } else {
        // Show pending status
        _showGcashPendingDialog(orderId: orderId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking payment status: $e')),
      );
    }
  }

  void _showSuccessDialog({
    required String orderId,
    required String paymentMethod,
  }) {
    final isGcash = paymentMethod == 'gcash_qr';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Order Placed!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #$orderId'),
            const SizedBox(height: 8),
            if (isGcash)
              const Text(
                'Your payment via GCash has been confirmed. '
                'You will receive a notification once your order is processed.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              )
            else
              const Text(
                'Your order has been placed successfully! '
                'You will receive a notification once your order is confirmed.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGcashPendingDialog({required String orderId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Pending'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #$orderId'),
            const SizedBox(height: 8),
            const Text(
              'Your GCash payment is being processed. '
              'Please wait for the confirmation notification.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: AppConstants.surface,
        foregroundColor: AppConstants.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Delivery Address Section
                    _buildDeliveryAddressSection(),
                    const SizedBox(height: 16),

                    // Contact Info Section
                    _buildContactInfoSection(),
                    const SizedBox(height: 16),

                    // Payment Method Section
                    _buildPaymentSection(),
                    const SizedBox(height: 16),

                    // Order Summary Section
                    _buildOrderSummary(cart),
                    const SizedBox(height: 16),

                    // Action Buttons
                    _buildActionButtons(cart),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDeliveryAddressSection() {
    return SoleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Delivery Address',
                style: AppConstants.subtitleStyle()?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const AddressFormScreen(),
                    ),
                  );
                  if (result == true) {
                    _loadAddresses();
                  }
                },
                child: const Text('Add Address'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_addresses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No address found. Please add a delivery address.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedAddressId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: _addresses.map((addr) {
                final id = addr['id'] as String;
                final label = _formatAddress(addr);
                return DropdownMenuItem(value: id, child: Text(label));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedAddressId = val;
                  final selected = _addresses.firstWhere(
                    (a) => a['id'] == val,
                    orElse: () => <String, dynamic>{},
                  );
                  _address = _formatAddress(selected);
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContactInfoSection() {
    return SoleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 20),
              const SizedBox(width: 8),
              Text(
                'Contact Information',
                style: AppConstants.subtitleStyle()?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Switch(
                value: _useSeparateInfo,
                onChanged: (v) => setState(() => _useSeparateInfo = v),
              ),
              Text(
                'Separate',
                style: AppConstants.captionStyle(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_useSeparateInfo) ...[
            SoleTextField(
              label: 'Customer Name',
              initialValue: _customerName ?? '',
              onChanged: (v) => _customerName = v,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            SoleTextField(
              label: 'Contact Number',
              initialValue: _contactNumber ?? '',
              onChanged: (v) => _contactNumber = v,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            SoleTextField(
              label: 'Delivery Instruction (optional)',
              initialValue: _deliveryInstruction ?? '',
              onChanged: (v) => _deliveryInstruction = v,
              maxLines: 2,
            ),
          ],
          if (!_useSeparateInfo)
            Text(
              'Using your account profile name and contact number.',
              style: AppConstants.captionStyle(),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection() {
    return SoleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Payment Method',
                style: AppConstants.subtitleStyle()?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPaymentRadio('gcash_qr', 'GCash QR'),
          const SizedBox(height: 4),
          _buildPaymentRadio('cod', 'Cash on Delivery'),
        ],
      ),
    );
  }

  Widget _buildPaymentRadio(String value, String label) {
    return RadioListTile<String>(
      title: Text(label, style: AppConstants.bodyStyle()),
      value: value,
      groupValue: _paymentMethod,
      onChanged: (v) => setState(() => _paymentMethod = v),
      activeColor: AppConstants.primary,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildOrderSummary(CartProvider cart) {
    return SoleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Order Summary',
                style: AppConstants.subtitleStyle()?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _priceRow('Subtotal', '₱${cart.selectedSubtotal.toStringAsFixed(2)}'),
          const SizedBox(height: 4),
          _priceRow('Delivery Fee',
              cart.selectedDeliveryFee > 0 ? '₱100.00' : 'Free'),
          const SizedBox(height: 4),
          _priceRow('Total', '₱${cart.selectedTotal.toStringAsFixed(2)}',
              isTotal: true),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? (AppConstants.subtitleStyle()
                      ?.copyWith(fontWeight: FontWeight.bold) ??
                  const TextStyle(fontWeight: FontWeight.bold))
              : AppConstants.bodyStyle(),
        ),
        Text(
          value,
          style: isTotal
              ? (AppConstants.subtitleStyle()
                      ?.copyWith(fontWeight: FontWeight.bold) ??
                  const TextStyle(fontWeight: FontWeight.bold))
              : AppConstants.bodyStyle(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(CartProvider cart) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: SolePrimaryButton(
            text: _isGcashChecking
                ? 'Verifying Payment...'
                : (_isSubmitting ? 'Placing Order...' : 'Place Order'),
            onPressed: (_isSubmitting || _isGcashChecking)
                ? null
                : () {
                    if (_formKey.currentState!.validate()) {
                      _submitOrder();
                    }
                  },
          ),
        ),
        if (_isGcashChecking) ...[
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Please wait while we confirm your payment...',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
```

## lib/constants/app_constants.dart

```dart
import 'package:flutter/material.dart';

class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // Supabase
  static const String url = 'https://psczvbfoybqhjeqssimw.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzY3p2YmZveWJxaGplcXNzaW13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjMxMzE5MDAsImV4cCI6MjAzODcwNzkwMH0.V4Mx3_Nx3e5zY_pqlHKa5UqRO5n5wf0T0jl0ZBSLl0E';
  static const String maptilerKey = 'ZsHghTkRWCoZDpjMxUir';

  // Colors
  static const Color primary = Color(0xFF8B4513);
  static const Color primaryVariant = Color(0xFF6B3410);
  static const Color secondary = Color(0xFFD4A574);
  static const Color background = Color(0xFFFEFAF5);
  static const Color surface = Color(0xFFFFF8F0);
  static const Color error = Color(0xFFB00020);
  static const Color onPrimary = Colors.white;
  static const Color onSecondary = Colors.white;
  static const Color onBackground = Color(0xFF1A1A2E);
  static const Color onSurface = Color(0xFF1A1A2E);
  static const Color onError = Colors.white;
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57F17);
  static const Color info = Color(0xFF1565C0);

  // Role colors
  static const Color customerColor = Color(0xFF2E7D32);
  static const Color sellerColor = Color(0xFF1565C0);
  static const Color courierColor = Color(0xFF6A1B9A);
  static const Color adminColor = Color(0xFFC62828);

  // Status colors
  static const Color statusPending = Color(0xFFF57F17);
  static const Color statusConfirmed = Color(0xFF2E7D32);
  static const Color statusShipped = Color(0xFF1565C0);
  static const Color statusDelivered = Color(0xFF1B5E20);
  static const Color statusCancelled = Color(0xFFB00020);
  static const Color statusReturned = Color(0xFF6A1B9A);

  // Typography
  static const String _fontFamily = 'DM Sans';

  static TextStyle? headlineStyle() {
    return const TextStyle(
      fontFamily: _fontFamily,
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: onBackground,
    );
  }

  static TextStyle? subtitleStyle() {
    return const TextStyle(
      fontFamily: _fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: onSurface,
    );
  }

  static TextStyle? bodyStyle() {
    return const TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: onSurface,
    );
  }

  static TextStyle? captionStyle() {
    return const TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.normal,
      color: Colors.grey,
    );
  }

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // Border Radius
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;

  // Roles
  static const String roleCustomer = 'customer';
  static const String roleSeller = 'seller';
  static const String roleCourier = 'courier';
  static const String roleAdmin = 'admin';

  // Role display names
  static const Map<String, String> roleNames = {
    roleCustomer: 'Customer',
    roleSeller: 'Seller',
    roleCourier: 'Courier',
    roleAdmin: 'Admin',
  };
}
```