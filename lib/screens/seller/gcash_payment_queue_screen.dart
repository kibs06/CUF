import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/direct_gcash_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';

/// Seller-facing queue of gateway-free GCash orders waiting for the
/// seller to confirm (or reject) the customer's proof of payment.
///
/// The seller cross-checks the submitted GCash reference number +
/// screenshot against their own GCash app, then taps Confirm (order
/// enters the normal pipeline) or Reject (order cancelled, stock
/// released, customer notified). Only the store owner can act — the RPCs
/// enforce this server-side.
class GcashPaymentQueueScreen extends StatefulWidget {
  const GcashPaymentQueueScreen({super.key});

  @override
  State<GcashPaymentQueueScreen> createState() =>
      _GcashPaymentQueueScreenState();
}

class _GcashPaymentQueueScreenState extends State<GcashPaymentQueueScreen> {
  final _service = DirectGcashService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  final Map<String, String?> _signedUrls = {};

  // 1-second tick so deadline countdowns stay live.
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Opportunistic expiry sweep (idempotent; clears overdue orders).
    unawaited(_service.expireOverdue());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      // The seller's own store (one store per seller).
      final storeRows = await client
          .from('stores')
          .select('id')
          .eq('owner_id', client.auth.currentUser?.id ?? '');
      if ((storeRows as List).isEmpty) {
        setState(() {
          _loading = false;
          _orders = [];
        });
        return;
      }
      final storeId = (storeRows as List).first['id'].toString();

      final orders = await client
          .from('orders')
          .select(
            'id, customer_id, total_amount, payment_confirmation_deadline, '
            'created_at, gcash_payment_proofs(*), '
            'profiles!orders_customer_id_fkey(full_name)',
          )
          .eq('store_id', storeId)
          .eq('status', 'awaiting_payment_confirmation')
          .order('created_at', ascending: false);

      final list = (orders as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Pre-fetch signed URLs for the proof screenshots (private bucket).
      final signed = <String, String?>{};
      for (final o in list) {
        final proofs = o['gcash_payment_proofs'];
        if (proofs is List && proofs.isNotEmpty) {
          final p = Map<String, dynamic>.from(proofs.first as Map);
          final path = p['screenshot_url']?.toString();
          if (path != null && path.isNotEmpty) {
            signed[o['id'].toString()] =
                await _service.proofScreenshotUrl(path);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _orders = list;
        _signedUrls..clear()..addAll(signed);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[GCASH-QUEUE] load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load payments to confirm.';
      });
    }
  }

  Future<void> _confirmOrder(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    final shortId = orderId.length >= 8
        ? orderId.substring(orderId.length - 8)
        : orderId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm payment received?'),
        content: Text(
          'Order #$shortId — mark as paid and start preparing? Make sure the '
          'reference number matches a real GCash transaction in your app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Received'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.confirmPayment(orderId);
      if (!mounted) return;
      setState(() => _orders.removeWhere((o) => o['id'].toString() == orderId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed — order is now in your queue.'),
          backgroundColor: AppConstants.success,
        ),
      );
    } on DirectGcashException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppConstants.error,
        ),
      );
      _load();
    }
  }

  Future<void> _rejectOrder(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    final shortId = orderId.length >= 8
        ? orderId.substring(orderId.length - 8)
        : orderId;
    final reasonController = TextEditingController();
    final rejected = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order #$shortId will be cancelled and the items released back '
              'to stock. The customer will see your reason.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Reason (shown to the customer)',
                hintText: 'e.g. No matching GCash transaction found',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (rejected != true || !mounted) return;

    try {
      await _service.rejectPayment(orderId, reasonController.text.trim());
      if (!mounted) return;
      setState(() => _orders.removeWhere((o) => o['id'].toString() == orderId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment rejected — order cancelled, stock released.'),
          backgroundColor: AppConstants.success,
        ),
      );
    } on DirectGcashException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppConstants.error,
        ),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Payments to Confirm',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppConstants.primary,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 44,
                color: AppConstants.secondary,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 160,
                child: SolePrimaryButton(
                  label: 'Retry',
                  onPressed: _load,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_orders.isEmpty) {
      return RefreshIndicator(
        color: AppConstants.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            const Icon(
              Icons.check_circle_outline,
              size: 52,
              color: AppConstants.success,
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Nothing to confirm',
                style: AppConstants.bodyStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'New GCash orders waiting for your confirmation\nwill appear here.',
                textAlign: TextAlign.center,
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

    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (context, index) => _OrderCard(
          order: _orders[index],
          screenshotUrl: _signedUrls[_orders[index]['id'].toString()],
          now: _now,
          onConfirm: () => _confirmOrder(_orders[index]),
          onReject: () => _rejectOrder(_orders[index]),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String? screenshotUrl;
  final DateTime now;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _OrderCard({
    required this.order,
    required this.screenshotUrl,
    required this.now,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final orderId = order['id'].toString();
    final shortId =
        orderId.length >= 8 ? orderId.substring(orderId.length - 8) : orderId;
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final deadline = DateTime.tryParse(
      order['payment_confirmation_deadline']?.toString() ?? '',
    );
    final customer = order['profiles'] is Map
        ? (order['profiles'] as Map)['full_name']?.toString() ?? 'Customer'
        : 'Customer';

    final proofs = order['gcash_payment_proofs'];
    final proof = proofs is List && proofs.isNotEmpty
        ? Map<String, dynamic>.from(proofs.first as Map)
        : null;
    final reference = proof?['reference_number']?.toString() ?? '—';

    final remaining = deadline?.difference(now) ?? Duration.zero;
    final expired = remaining.isNegative || remaining == Duration.zero;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoleCard(
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
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                    color: AppConstants.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #$shortId',
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        customer,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: AppConstants.monoStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Reference No.', reference),
            const SizedBox(height: 6),
            _row(
              'Window',
              expired
                  ? 'Expired'
                  : '${_formatDuration(remaining)} left',
              valueColor: expired
                  ? AppConstants.error
                  : AppConstants.statusPendingColor,
            ),
            if (proof != null &&
                (proof['submitted_at']?.toString().isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              _row(
                'Submitted',
                _formatWhen(proof['submitted_at'].toString()),
              ),
            ],
            if (screenshotUrl != null && screenshotUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  screenshotUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 140,
                    width: double.infinity,
                    color: AppConstants.borderGray.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: expired ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.error,
                      side: BorderSide(
                        color: AppConstants.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: expired ? null : onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.success,
                      ),
                      child: const Text('Confirm Received'),
                    ),
                  ),
                ),
              ],
            ),
            if (expired) ...[
              const SizedBox(height: 8),
              Text(
                'This window has lapsed — the order was (or will be) '
                'auto-cancelled and stock released.',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.error,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppConstants.secondary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _formatWhen(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final h = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day} $h:${local.minute.toString().padLeft(2, '0')} $ampm';
  }
}
