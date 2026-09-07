import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'sole_card.dart';
import 'sole_primary_button.dart';

/// The shared "Order Confirmed" screen shown after an order is placed.
///
/// Used by BOTH payment paths so they confirm identically:
///   • Cash on Pickup — `checkout_screen.dart` step 2 (right after the
///     order is placed).
///   • GCash (PayMongo) — `gcash_payment_screen.dart` paid phase, once the
///     server-verified webhook has confirmed the payment.
///
/// [checkScale] optionally animates the green check (the checkout's
/// elastic pop); pass null for a static check.
class OrderConfirmationView extends StatelessWidget {
  /// Full order UUID — the last 8 characters are displayed as "#xxxxxxxx".
  final String orderId;

  /// Order total (items + delivery) — mirrors `orders.total_amount`.
  final double total;

  /// Human label for the payment method (e.g. "Cash on Pickup", "GCash").
  final String paymentLabel;

  /// Track My Order action. Null disables the button (order not loaded yet).
  final VoidCallback? onTrackOrder;

  final VoidCallback onBackHome;

  final Animation<double>? checkScale;

  const OrderConfirmationView({
    super.key,
    required this.orderId,
    required this.total,
    required this.paymentLabel,
    required this.onBackHome,
    this.onTrackOrder,
    this.checkScale,
  });

  String get _orderIdDisplay {
    if (orderId.isEmpty) return 'N/A';
    return '#${orderId.length > 8 ? orderId.substring(orderId.length - 8) : orderId}';
  }

  @override
  Widget build(BuildContext context) {
    final check = Container(
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
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (checkScale != null)
              ScaleTransition(scale: checkScale!, child: check)
            else
              check,
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
                  _row('Order ID', _orderIdDisplay),
                  const SizedBox(height: 8),
                  _row('Total', '₱${total.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  _row('Payment Type', paymentLabel),
                ],
              ),
            ),
            const SizedBox(height: 40),
            SolePrimaryButton(
              label: 'Track My Order',
              onPressed: onTrackOrder,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onBackHome,
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

  Widget _row(String label, String value) {
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
