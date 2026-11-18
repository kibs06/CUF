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
/// The success mark animates itself, so neither caller has to own an
/// `AnimationController` — and the GCash path, which used to render it
/// static, now gets the same arrival as cash.
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

  const OrderConfirmationView({
    super.key,
    required this.orderId,
    required this.total,
    required this.paymentLabel,
    required this.onBackHome,
    this.onTrackOrder,
  });

  String get _orderIdDisplay {
    if (orderId.isEmpty) return 'N/A';
    return '#${orderId.length > 8 ? orderId.substring(orderId.length - 8) : orderId}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Both callers sit under an AppBar, so only the bottom/side insets are
      // still the body's to handle.
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Center on a tall screen, scroll on a short one (landscape, small
          // phones): the content used to be a bare Center + Column, so anything
          // shorter than the column simply overflowed.
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 48
                    ? constraints.maxHeight - 48
                    : 0,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _AnimatedSuccessCheck(),
                    const SizedBox(height: 28),
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
                      color: AppConstants.surfaceLight,
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
                    const SizedBox(height: 36),
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            // Was `Colors.black54`, which is almost invisible on the dark
            // surface this card uses in dark mode.
            color: AppConstants.secondary.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppConstants.monoStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The green mark: the circle pops in on an ease-out-back curve, then the
/// tick draws itself with a single rounding stroke. One implicit animation,
/// ~850 ms, no caller plumbing.
///
/// Reduced-motion users get the finished state immediately: the tick is
/// information, not decoration.
class _AnimatedSuccessCheck extends StatelessWidget {
  const _AnimatedSuccessCheck();

  static const Interval _circleCurve = Interval(
    0,
    0.6,
    curve: Curves.easeOutBack,
  );
  static const Interval _checkCurve = Interval(
    0.35,
    1,
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 850),
      builder: (context, t, _) {
        return Transform.scale(
          scale: _circleCurve.transform(t),
          child: Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(
              color: AppConstants.success,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(44, 44),
                painter: _CheckPainter(_checkCurve.transform(t)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final Paint paint = Paint()
      ..color = AppConstants.inkInverse
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.74)
      ..lineTo(size.width * 0.82, size.height * 0.30);

    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
