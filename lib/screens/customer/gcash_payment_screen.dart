import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_constants.dart';
import '../../providers/cart_provider.dart';
import '../../services/deep_link_service.dart';
import '../../services/gcash_payment_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';
import 'tracking_screen.dart';

/// Where the customer sits while their GCash payment is in flight.
enum _PayPhase { confirming, paid, failed, expired, cancelled, conflict }

/// PayMongo GCash payment screen (attempt #6).
///
/// Reached from checkout right after `create-gcash-payment-intent`, or
/// resumed (tracking screen / deep link / pending-checkout dialog).
/// Responsibilities:
///   • Opens PayMongo's hosted checkout in the SYSTEM browser (never an
///     in-app webview — the GCash handoff relies on the gcash:// custom
///     scheme that WebViews don't intercept).
///   • POLLS get-payment-status — the deep-link return and the app-life
///     resume only trigger an immediate poll; they never mark anything
///     paid by themselves. The server webhook is the only source of truth.
///   • Renders honest terminal states: paid / failed / expired /
///     cancelled / payment_conflict — no "guessing whether I was charged".
class GcashPaymentScreen extends StatefulWidget {
  final GcashIntentResult intent;

  const GcashPaymentScreen({super.key, required this.intent});

  /// True while this screen is open — the global deep-link handler skips
  /// warm returns (this screen's own poll is authoritative).
  static bool isOpen = false;

  @override
  State<GcashPaymentScreen> createState() => _GcashPaymentScreenState();
}

class _GcashPaymentScreenState extends State<GcashPaymentScreen>
    with WidgetsBindingObserver {
  final GcashPaymentService _service = GcashPaymentService();

  _PayPhase _phase = _PayPhase.confirming;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  StreamSubscription<Uri>? _linkSub;
  bool _hasOpenedBrowser = false;
  bool _isCancelling = false;
  bool _isOpening = false;

  DateTime? _expiry;
  String _countdown = '';

  @override
  void initState() {
    super.initState();
    GcashPaymentScreen.isOpen = true;
    _expiry = widget.intent.expiresAt;
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    _startCountdown();
    // Warm-return deep link → poll immediately (the poll is authoritative).
    _linkSub = DeepLinkService.instance.uriStream.listen((uri) {
      if (DeepLinkService.isGcashReturn(uri)) _pollNow();
    });
  }

  @override
  void dispose() {
    GcashPaymentScreen.isOpen = false;
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App came back from the GCash/browser handoff — re-check the real
    // status immediately instead of assuming success or failure.
    if (state == AppLifecycleState.resumed) _pollNow();
  }

  // ─── Polling ───────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollNow();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollNow());
  }

  Future<void> _pollNow() async {
    try {
      final s = await _service.getStatus(widget.intent.orderId);
      if (!mounted) return;
      final next = _phaseFor(s);
      if (next != _phase) setState(() => _phase = next);
      if (s.expiresAt != null) _expiry = s.expiresAt;

      if (next == _PayPhase.paid || next == _PayPhase.conflict) {
        // Money captured — the items were left in the cart while
        // awaiting payment, so remove them now that the server-confirmed
        // order_items exist. Only stop polling once the cart is actually
        // cleaned up (a transient failure retries on the next tick).
        final cleaned = await _clearPurchasedFromCart();
        if (cleaned) {
          _pollTimer?.cancel();
          _countdownTimer?.cancel();
        }
      } else if (next != _PayPhase.confirming) {
        // Terminal failed/expired/cancelled — stop polling.
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
      }
    } catch (e) {
      // Transient network/function error — keep the last state and let
      // the next tick retry; never flip to a terminal state from an error.
      debugPrint('[GCASH-PAY] poll error (retrying): $e');
    }
  }

  /// Remove the paid-for items from the cart (server + local).
  ///
  /// The checkout keeps items in the cart while the payment is awaiting;
  /// once the server-confirmed order is paid, the webhook has
  /// materialized order_items, so this screen removes exactly those
  /// (quantity-aware — lines fully bought are removed, partially bought
  /// lines are reduced). Items added to the cart while payment was
  /// pending are left alone.
  ///
  /// Returns true when the cleanup is done (or the cart had nothing to
  /// remove); false on failure so the caller can keep polling and retry.
  Future<bool> _clearPurchasedFromCart() async {
    try {
      final order = await Supabase.instance.client
          .from('orders')
          .select('order_items(product_id, size, quantity)')
          .eq('id', widget.intent.orderId)
          .maybeSingle();
      if (!mounted) return true;
      final items = order?['order_items'];
      if (items is! List || items.isEmpty) return true; // nothing to remove
      await context.read<CartProvider>().removePurchasedItems(
        items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
      );
      return true;
    } catch (e) {
      debugPrint('[GCASH-PAY] clear purchased from cart failed (retrying): $e');
      return false;
    }
  }

  _PayPhase _phaseFor(GcashStatusResult s) {
    if (s.paid || s.status == 'pending') return _PayPhase.paid;
    if (s.status == 'payment_conflict') return _PayPhase.conflict;
    if (s.status == 'cancelled') {
      final reason = s.cancellationReason?.toLowerCase() ?? '';
      if (reason.contains('expired')) return _PayPhase.expired;
      if (reason.contains('cancelled by customer')) return _PayPhase.cancelled;
      if (reason.contains('not completed') || reason.contains('failed')) {
        return _PayPhase.failed;
      }
      return _PayPhase.cancelled;
    }
    return _PayPhase.confirming;
  }

  // ─── Countdown ─────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer?.cancel();
    void tick() {
      if (!mounted) return;
      final left = _expiry == null
          ? Duration.zero
          : _expiry!.difference(DateTime.now());
      final countdown = left.isNegative
          ? '0m 00s'
          : '${left.inMinutes}m ${(left.inSeconds % 60).toString().padLeft(2, '0')}s';
      if (countdown != _countdown) setState(() => _countdown = countdown);
      // The window closed but the server hasn't marked it yet (sweep is
      // every 5 min) — force an authoritative poll now instead of
      // sitting on "0m 00s" until the next sweep tick.
      if (left.isNegative && _phase == _PayPhase.confirming) _pollNow();
    }

    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  // ─── Actions ───────────────────────────────────────────────────

  Future<void> _openGcash() async {
    if (_isOpening || _isCancelling) return; // double-tap guard
    final url = widget.intent.checkoutUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No payment link available. Please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }
    setState(() {
      _isOpening = true;
      _hasOpenedBrowser = true;
    });
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication, // system browser, not a webview
    );
    if (mounted) {
      setState(() => _isOpening = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open GCash. Please tap Open GCash again.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _cancelCheckout() async {
    if (_isCancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this checkout?'),
        content: const Text(
          'No charge has been made yet. Cancelling releases this checkout so you can place a new order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep It'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppConstants.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      final cancelled = await _service.cancelPending(widget.intent.orderId);
      if (!mounted) return;
      if (cancelled) {
        setState(() => _phase = _PayPhase.cancelled);
      } else {
        // Already resolved while the dialog was open — re-check.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This checkout already resolved.'),
            backgroundColor: AppConstants.success,
          ),
        );
        await _pollNow();
      }
    } on GcashPaymentException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppConstants.error),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  /// Paid / conflict: fetch the real order (with items + product images)
  /// and open the tracking screen.
  Future<void> _goToTracking() async {
    try {
      final order = await Supabase.instance.client
          .from('orders')
          .select(
            '*, order_items(id, product_id, size, quantity, unit_price, products(name, product_images(image_url, display_order)))',
          )
          .eq('id', widget.intent.orderId)
          .single();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(order: order),
        ),
      );
    } catch (e) {
      debugPrint('[GCASH-PAY] tracking fetch failed: $e');
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: const Text('GCash Payment', style: TextStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: _goHome,
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPhaseHeader(),
                const SizedBox(height: 20),
                _buildAmountCard(),
                const SizedBox(height: 20),
                if (_phase == _PayPhase.confirming) _buildActionCard(),
                if (_phase != _PayPhase.confirming) _buildTerminalCard(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseHeader() {
    final (icon, color, title, subtitle) = switch (_phase) {
      _PayPhase.confirming => (
        _hasOpenedBrowser ? Icons.hourglass_top : Icons.account_balance_wallet_outlined,
        AppConstants.primary,
        _hasOpenedBrowser ? 'Confirming your payment…' : 'Complete payment in GCash',
        _hasOpenedBrowser
            ? 'Checking with your bank. This usually takes a few seconds — please wait.'
            : 'Tap Open GCash to authorize the exact amount in the GCash app.',
      ),
      _PayPhase.paid => (
        Icons.check_circle,
        AppConstants.success,
        'Payment confirmed!',
        'Your payment was verified by PayMongo. The store will start preparing your order.',
      ),
      _PayPhase.failed => (
        Icons.error_outline,
        AppConstants.error,
        'Payment not completed',
        'The GCash payment failed or was cancelled before finishing. No charge was made.',
      ),
      _PayPhase.expired => (
        Icons.timer_off_outlined,
        AppConstants.error,
        'Payment window expired',
        'The payment window closed before you paid, so this checkout was released. You can place a new order anytime.',
      ),
      _PayPhase.cancelled => (
        Icons.cancel_outlined,
        AppConstants.secondary,
        'Checkout cancelled',
        'This checkout was cancelled. No charge was made — you can place a new order anytime.',
      ),
      _PayPhase.conflict => (
        Icons.help_outline,
        AppConstants.error,
        'Payment received — needs review',
        'Your payment went through, but the store needs to review your order before it can be prepared. Contact the store for help.',
      ),
    };

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.65),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAmountCard() {
    final orderTotal = widget.intent.orderTotal;
    return SoleCard(
      color: Colors.white,
      child: Column(
        children: [
          Text(
            'Amount to pay',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₱${widget.intent.amount.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
          const Divider(color: AppConstants.borderGray, height: 28),
          _row('Items + Delivery', orderTotal),
          const SizedBox(height: 6),
          _row('GCash Service Fee', widget.intent.feeAmount),
          const Divider(color: AppConstants.borderGray, height: 20),
          _row('Total Due', widget.intent.amount, bold: true),
          if (_phase == _PayPhase.confirming) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: AppConstants.statusPendingColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Complete within $_countdown',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.statusPendingColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, double value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '₱${value.toStringAsFixed(2)}',
          style: AppConstants.monoStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: bold ? AppConstants.primary : AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard() {
    return Column(
      children: [
        SolePrimaryButton(
          label: _isCancelling ? 'Cancelling…' : 'Open GCash',
          onPressed: _isCancelling ? null : _openGcash,
          icon: const Icon(Icons.open_in_new, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Text(
          'You will be taken to GCash, then returned here automatically.',
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: AppConstants.secondary.withValues(alpha: 0.55),
          ),
        ),
        if (_hasOpenedBrowser) ...[
          const SizedBox(height: 6),
          Text(
            'Still here? Tap Open GCash again to resume the payment page.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.primary.withValues(alpha: 0.8),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: _isCancelling ? null : _cancelCheckout,
          child: const Text('Cancel this checkout'),
        ),
      ],
    );
  }

  Widget _buildTerminalCard() {
    final isPaid = _phase == _PayPhase.paid;
    final isConflict = _phase == _PayPhase.conflict;
    return Column(
      children: [
        if (isPaid || isConflict)
          SizedBox(
            width: double.infinity,
            child: SolePrimaryButton(
              label: isConflict ? 'View Order' : 'Track My Order',
              onPressed: _goToTracking,
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: SolePrimaryButton(
              label: 'Back to Home',
              onPressed: _goHome,
            ),
          ),
      ],
    );
  }
}
