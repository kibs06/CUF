import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/direct_gcash_service.dart';
import '../../utils/proof_rejection.dart';
import '../../widgets/gcash_flow_kit.dart';
import 'gcash_ref_scanner_screen.dart';
import 'seller_earnings_screen.dart';

/// Seller-facing queue of gateway-free GCash orders waiting for the
/// seller to confirm (or reject) the customer's proof of payment.
///
/// The seller cross-checks the submitted GCash reference number, sender name,
/// amount and screenshot against the PLATFORM GCash statement, then taps
/// Verify & accept (order enters the normal pipeline) or Reject (the customer
/// can resubmit; the 3rd rejection cancels and releases stock). Only the store
/// owner can act — the RPCs enforce this server-side.
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

  /// Recently decided manual-GCash orders (confirmed + rejected), newest
  /// first. Read from `order_payment_events` — seller-readable, unlike the
  /// admin-only `gcash_payment_decision_audit` — so any failure hides this
  /// section instead of breaking the queue.
  List<Map<String, dynamic>> _history = [];
  String? _storeId;

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
      _storeId = storeId;
      unawaited(_loadHistory(client, storeId));

      final orders = await client
          .from('orders')
          .select(
            'id, customer_id, total_amount, order_code, '
            'payment_confirmation_deadline, review_deadline, '
            'created_at, payment_flagged, gcash_payment_proofs(*), '
            'subtotal_amount, discount_amount, '
            'order_items(*, products(name)), '
            'profiles!orders_customer_id_fkey(full_name)',
          )
          .eq('store_id', storeId)
          // Only proofs awaiting a decision. A submitted proof means the
          // money may already be in the platform account, so these never
          // expire on a timer.
          .eq('status', 'payment_under_review')
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

  /// Last 10 confirm/reject decisions for this store's manual-GCash orders.
  /// Fire-and-forget from [_load]: a failure leaves [_history] empty and
  /// the section stays hidden — the queue above is unaffected.
  Future<void> _loadHistory(SupabaseClient client, String storeId) async {
    try {
      final rows = await client
          .from('order_payment_events')
          .select(
            'event_type, notes, created_at, order_id, '
            'orders!inner(store_id, total_amount)',
          )
          .inFilter('event_type', const ['confirmed', 'rejected'])
          .eq('orders.store_id', storeId)
          .order('created_at', ascending: false)
          .limit(10);
      if (!mounted) return;
      setState(() {
        _history = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      debugPrint('[GCASH-QUEUE] history load failed (non-fatal): $e');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Verify this payment?',
          style: AppConstants.headlineStyle(fontSize: 19),
        ),
        content: Text(
          'Order #$shortId — check that the reference, sender name and amount '
          'match a real GCash transaction in the PLATFORM account before you '
          'accept. Accepting starts preparation; CUFMAI pays you out at '
          'the end of the day once the admin confirms the money landed.',
          style: AppConstants.bodyStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verify & Accept'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.verifyPayment(orderId);
      if (!mounted) return;
      setState(() => _orders.removeWhere((o) => o['id'].toString() == orderId));
      if (_storeId != null) {
        unawaited(_loadHistory(Supabase.instance.client, _storeId!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment verified — order is now in your queue.'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reject this proof?',
          style: AppConstants.headlineStyle(fontSize: 19),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Where the money is, before the seller taps: the transfer has
            // already left the customer, and a reject is a decision about the
            // proof — the return trip is a manual transfer by CUFMAI, not
            // something this button does. Saying it here is the difference
            // between a considered reject and a refund the customer has to
            // chase.
            Text(
              'The customer has already sent this money to the platform\'s '
              'GCash account. Rejecting rejects the proof only — it does not '
              'send the money back.',
              style: AppConstants.bodyStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Order #$shortId goes back to the customer with your reason so '
              'they can submit a corrected proof, and CUFMAI refunds the '
              'amount to them manually. On their 3rd rejection the order is '
              'cancelled and the items are released to stock.',
              style: AppConstants.bodyStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            GcashBanner(
              icon: Icons.warning_amber_rounded,
              color: AppConstants.error,
              text: 'Only reject when you cannot find this transfer in your '
                  'GCash statement — a refund is a manual transfer, not a '
                  'button.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Reason (shown to the customer)',
                hintText: 'e.g. No matching GCash transaction found',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
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
      // The RPC answers with what it did: back to the customer, or cancelled
      // on the third rejection. Read it instead of assuming the harmless one —
      // "they can correct it" is a lie on the order that just ended.
      final outcome =
          await _service.rejectProof(orderId, reasonController.text.trim());
      if (!mounted) return;
      final notice = proofRejectionNotice(outcome);
      setState(() => _orders.removeWhere((o) => o['id'].toString() == orderId));
      if (_storeId != null) {
        unawaited(_loadHistory(Supabase.instance.client, _storeId!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notice.text),
          backgroundColor: notice.refundOwed
              ? AppConstants.statusPendingColor
              : AppConstants.success,
          // Long enough to read when it is the refund sentence.
          duration: Duration(seconds: notice.refundOwed ? 8 : 4),
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
          'Payments to confirm',
          style: AppConstants.headlineStyle(fontSize: 19),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Earnings & payouts',
            icon: Icon(
              Icons.account_balance_wallet_outlined,
              color: AppConstants.secondary,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SellerEarningsScreen(),
              ),
            ),
          ),
        ],
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
              Icon(
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
                width: 180,
                child: GcashPrimaryButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  onPressed: _load,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
        children: [
          GcashRiseIn(
            child: GcashFlowHeader(
              eyebrow: 'Manual GCash',
              title: 'Payments to confirm',
              description:
                  'Match each reference, sender name and amount against the '
                  'platform GCash statement. Accepting releases the order for '
                  'preparation; rejecting lets the customer correct it.',
              trailing: _orders.isEmpty
                  ? null
                  : GcashStatusPill(
                      label: '${_orders.length} waiting',
                      color: AppConstants.statusPendingColor,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (_orders.isEmpty)
            GcashRiseIn(
              order: 1,
              child: GcashPanel(
                eyebrow: 'Queue',
                title: 'Nothing to confirm',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 22,
                          color: AppConstants.success,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'New GCash proofs appear here the moment a '
                            'customer submits one.',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppConstants.secondary
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_orders.length, (index) {
              final order = _orders[index];
              return GcashRiseIn(
                key: ValueKey(order['id']),
                order: index > 5 ? 6 : index + 1,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: GcashOrderCard(
                    order: order,
                    screenshotUrl: _signedUrls[order['id'].toString()],
                    now: _now,
                    onConfirm: () => _confirmOrder(order),
                    onReject: () => _rejectOrder(order),
                  ),
                ),
              );
            }),
          if (_history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _DecisionHistory(history: _history),
            ),
        ],
      ),
    );
  }
}

/// Recently decided manual-GCash orders (confirmed + rejected), newest
/// first. Seller-readable via `order_payment_events` — the admin-only
/// decision audit stays retrospective-only, this is the seller's own
/// "what did I just do" list.
class _DecisionHistory extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const _DecisionHistory({required this.history});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'RECENTLY DECIDED',
            style: AppConstants.monoStyle(
              fontSize: 9.5,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ).copyWith(letterSpacing: 1.8),
          ),
        ),
        const SizedBox(height: 8),
        ...history.map((e) {
          final orderId = e['order_id']?.toString() ?? '';
          final shortId = orderId.length >= 8
              ? orderId.substring(orderId.length - 8)
              : orderId;
          final confirmed = e['event_type']?.toString() == 'confirmed';
          final order = e['orders'] is Map
              ? Map<String, dynamic>.from(e['orders'] as Map)
              : <String, dynamic>{};
          final total =
              (order['total_amount'] as num?)?.toDouble() ?? 0;
          final when = _formatWhen(e['created_at']?.toString() ?? '');
          final reason = e['notes']?.toString().trim() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppConstants.primary.withValues(alpha: 0.10),
                ),
                color: AppConstants.primary.withValues(alpha: 0.03),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GcashStatusPill(
                    label: confirmed ? 'Confirmed' : 'Rejected',
                    color: confirmed
                        ? AppConstants.success
                        : AppConstants.error,
                    icon: confirmed ? Icons.check : Icons.close,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #$shortId · ₱${total.toStringAsFixed(2)}',
                          style: AppConstants.bodyStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          confirmed
                              ? when
                              : (reason.isNotEmpty
                                  ? '$when · $reason'
                                  : when),
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: AppConstants.secondary
                                .withValues(alpha: 0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  static String _formatWhen(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h =
        local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day} $h:${local.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class GcashOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String? screenshotUrl;
  final DateTime now;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const GcashOrderCard({
    super.key,
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
    // Every order in this queue is `payment_under_review`: the customer has
    // already paid, so the 30-minute PAY window is irrelevant (and usually
    // already past). `review_deadline` is the 24 h advisory SLA, and the
    // database never cancels a submitted payment — so nothing here may
    // disable the seller's decision.
    final reviewDeadline = DateTime.tryParse(
      order['review_deadline']?.toString() ?? '',
    );
    final customer = order['profiles'] is Map
        ? (order['profiles'] as Map)['full_name']?.toString() ?? 'Customer'
        : 'Customer';

    final proofs = order['gcash_payment_proofs'];
    final proof = proofs is List && proofs.isNotEmpty
        ? Map<String, dynamic>.from(proofs.first as Map)
        : null;
    final reference = proof?['reference_number']?.toString() ?? '—';
    final senderName = proof?['sender_name']?.toString() ?? '—';
    final amountPaid = (proof?['amount_paid'] as num?)?.toDouble();
    final code = order['order_code']?.toString() ?? '—';
    final items = order['order_items'] is List
        ? (order['order_items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];
    final flagged = order['payment_flagged'] == true;

    final slaRemaining = reviewDeadline?.difference(now);
    final slaPassed = slaRemaining != null && slaRemaining.isNegative;
    final amountMatches = amountPaid != null &&
        (amountPaid - total).abs() <= 0.009;

    return GcashPanel(
      eyebrow: 'Order #$shortId',
      title: customer,
      trailing: flagged
          ? GcashStatusPill(
              label: 'Flagged',
              color: AppConstants.error,
              icon: Icons.flag_outlined,
            )
          : GcashStatusPill(
              label: 'Under review',
              color: AppConstants.statusPendingColor,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: AppConstants.monoStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primary,
                  ),
                ),
              ),
              Text(
                'ORDER TOTAL',
                style: AppConstants.monoStyle(
                  fontSize: 9,
                  color: AppConstants.secondary.withValues(alpha: 0.45),
                ).copyWith(letterSpacing: 1.4),
              ),
            ],
          ),
          if (flagged) ...[
            const SizedBox(height: 10),
            GcashBanner(
              icon: Icons.flag_outlined,
              color: AppConstants.error,
              text: 'Flagged by the admin — do not accept. Clear the flag from '
                  'Payment verification before deciding.',
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _productsTile(items),
          ],
          const SizedBox(height: 14),
          GcashInsetTile(
            child: Column(
              children: [
                GcashFactRow(label: 'Order code', value: code),
                GcashFactRow(label: 'Reference', value: reference),
                GcashFactRow(
                  label: 'Sender',
                  value: senderName,
                  mono: false,
                ),
                GcashFactRow(
                  label: 'Amount sent',
                  value: amountPaid == null
                      ? '—'
                      : '₱${amountPaid.toStringAsFixed(2)}',
                  valueColor: amountMatches
                      ? AppConstants.success
                      : AppConstants.error,
                ),
                GcashFactRow(
                  label: 'Mismatch',
                  value: amountMatches
                      ? 'None — matches the order total'
                      : 'Differs from ₱${total.toStringAsFixed(2)}',
                  mono: false,
                  valueColor:
                      amountMatches ? null : AppConstants.error,
                ),
                GcashFactRow(
                  label: 'Review SLA',
                  value: slaRemaining == null
                      ? 'Awaiting your decision'
                      : slaPassed
                          ? 'SLA passed — still payable'
                          : '${_formatDuration(slaRemaining)} left',
                  valueColor: slaPassed
                      ? AppConstants.error
                      : AppConstants.statusPendingColor,
                  mono: false,
                ),
                if (proof != null &&
                    (proof['submitted_at']?.toString().isNotEmpty ?? false))
                  GcashFactRow(
                    label: 'Received',
                    value: _formatWhen(proof['submitted_at'].toString()),
                    mono: false,
                  ),
                // What the receipt itself says, which is not the same clock as
                // when it arrived: a receipt that claims an earlier time than
                // the proof it arrived in is worth a second look. When the
                // screenshot had no readable clock, say so — showing the
                // arrival stamp here would read as the customer's claim.
                if (proof != null)
                  GcashFactRow(
                    label: 'Receipt says',
                    value: (proof['paid_at']?.toString().isNotEmpty ?? false)
                        ? _formatWhen(proof['paid_at'].toString())
                        : 'Not readable on the receipt',
                    mono: false,
                  ),
              ],
            ),
          ),
          if (screenshotUrl != null && screenshotUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            // The crop is enough to recognise a receipt, not enough to read a
            // reference or a clock off it — tapping opens the full picture.
            GestureDetector(
              onTap: () => _openProofViewer(context, screenshotUrl!),
              child: Semantics(
                button: true,
                label: 'Customer payment screenshot. Tap to open it full size.',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Image.network(
                        screenshotUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        semanticLabel: 'Customer payment screenshot',
                        errorBuilder: (_, _, _) => Container(
                          height: 160,
                          width: double.infinity,
                          color: AppConstants.borderGray.withValues(alpha: 0.15),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.zoom_out_map,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Tap to expand',
                                style: AppConstants.bodyStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
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
            ),
          ],
          if (proof != null && reference != '—') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _scanAndCompare(context, reference),
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.document_scanner_outlined, size: 17),
                label: Text(
                  "Scan the receipt's reference",
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // T5: the expected amount, prominent and directly above the
          // seller's decision buttons — the number to cross-check against
          // the platform statement, not memory or the screenshot alone.
          GcashExpectedAmountBanner(total: total),
          if (slaPassed) ...[
            const SizedBox(height: 10),
            Text(
              'The 24 h review SLA has passed. The money is still in the '
              'platform account and the order is NOT auto-cancelled — accept '
              'it if the reference matches, or reject so the customer can '
              'resubmit.',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.error,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              // No glyphs on either decision: at this size the mark crowded
              // the word and read as two separate targets.
              final reject = GcashGhostPill(
                label: 'Reject',
                color: AppConstants.error,
                onPressed: onReject,
              );
              final accept = GcashPrimaryButton(
                label: 'Verify & accept',
                showIcon: false,
                background: AppConstants.success,
                onPressed: onConfirm,
              );
              if (constraints.maxWidth < 320) {
                return Column(
                  children: [
                    accept,
                    const SizedBox(height: 10),
                    reject,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: reject),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: accept),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// What the money is for, line by line.
  ///
  /// The order total alone cannot settle a proof: ₱1.00 is the right transfer
  /// for a ₱1.00 item and the wrong one for a ₱500 shirt, and the seller has
  /// to make that call from the card. Showing the item, its size, how many and
  /// what the line costs turns "does this look right?" into a comparison.
  Widget _productsTile(List<Map<String, dynamic>> items) {
    var subtotal = 0.0;
    final rows = <Widget>[];
    for (final item in items) {
      final product = item['products'];
      final rawName = product is Map ? product['name']?.toString() : null;
      final name = (rawName ?? '').trim();
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final unit = (item['unit_price'] as num?)?.toDouble() ?? 0;
      final line = unit * qty;
      subtotal += line;
      final size = item['size']?.toString().trim() ?? '';
      final detail = [
        if (size.isNotEmpty) 'Size $size',
        if (qty > 1) '$qty × ₱${unit.toStringAsFixed(2)}',
      ].join(' · ');
      rows.add(
        _productRow(
          name: name.isEmpty ? 'Product' : name,
          detail: detail,
          amount: '₱${line.toStringAsFixed(2)}',
        ),
      );
    }

    // The customer paid total_amount, not the goods subtotal, so the block has
    // to reach that number or a correct payment looks short. The fee is taken
    // from the order itself, never assumed: the server writes
    // subtotal_amount (goods, before any voucher) and discount_amount, and
    // total_amount = goods + delivery − discount. Deriving delivery from those
    // keeps this correct on a pickup order (₱0), after a fee change, and on an
    // order placed with a voucher.
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final discount = (order['discount_amount'] as num?)?.toDouble() ?? 0;
    final serverSubtotal = (order['subtotal_amount'] as num?)?.toDouble();
    final goods = serverSubtotal ?? subtotal;
    final delivery = total - goods + discount;
    final voucher = order['voucher_code']?.toString().trim() ?? '';

    return GcashInsetTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRODUCTS',
            style: AppConstants.monoStyle(
              fontSize: 9.5,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ).copyWith(letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          ...rows,
          Divider(
            height: 1,
            color: AppConstants.primary.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 7),
          _productRow(
            name: 'Goods',
            detail: '',
            amount: '₱${goods.toStringAsFixed(2)}',
          ),
          _productRow(
            name: 'Delivery',
            detail: '',
            amount: '₱${delivery.toStringAsFixed(2)}',
          ),
          if (discount > 0)
            _productRow(
              name: 'Voucher',
              detail: voucher.isEmpty ? '' : voucher,
              amount: '− ₱${discount.toStringAsFixed(2)}',
            ),
          _productRow(
            name: 'Total',
            detail: '',
            amount: '₱${total.toStringAsFixed(2)}',
            emphasised: true,
          ),
        ],
      ),
    );
  }

  Widget _productRow({
    required String name,
    required String detail,
    required String amount,
    bool emphasised = false,
  }) {
    final ink = emphasised
        ? AppConstants.secondary
        : AppConstants.secondary.withValues(alpha: 0.9);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppConstants.bodyStyle(
                    fontSize: emphasised ? 13.5 : 13,
                    fontWeight: emphasised ? FontWeight.w800 : FontWeight.w700,
                    height: 1.25,
                    color: emphasised ? ink : null,
                  ),
                ),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      detail,
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            amount,
            style: AppConstants.monoStyle(
              fontSize: emphasised ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: emphasised ? AppConstants.secondary : AppConstants.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// OCR the customer's receipt and compare the detected reference with the
  /// one they submitted. The scanner always shows its finding for
  /// confirmation first; this method only reports whether the two agree, so
  /// a seller still decides, but never has to read a 13-digit number off a
  /// thumbnail by eye.
  Future<void> _scanAndCompare(BuildContext context, String submitted) async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const GcashRefScannerScreen()),
    );
    if (scanned == null || !context.mounted) return;

    String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
    final want = digits(submitted);
    final got = digits(scanned);
    final matches = got.isNotEmpty &&
        want.isNotEmpty &&
        (got == want || got.endsWith(want) || want.endsWith(got));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          matches ? 'Reference matches' : 'Reference does NOT match',
          style: AppConstants.headlineStyle(fontSize: 19),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scanned: $got',
              style: AppConstants.monoStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Submitted: $want',
              style: AppConstants.monoStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              matches
                  ? 'The receipt shows the same reference the customer typed.'
                  : 'Do not accept yet: either the receipt belongs to another '
                      'payment, or the customer mistyped the reference. Reject '
                      'with a reason so they can resubmit.',
              style: AppConstants.bodyStyle(fontSize: 12, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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

/// Full-screen, pinch-zoomable proof screenshot.
///
/// Loading and failure are both said out loud on the black backdrop, so an
/// empty viewer never reads as a proof with nothing on it. Closing is the X;
/// the seller lands back on the same card with its decision still unmade.
void _openProofViewer(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ProofImageViewer(url: url),
  );
}

class _ProofImageViewer extends StatelessWidget {
  final String url;

  const _ProofImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: SizedBox(
        width: size.width - 16,
        height: size.height - 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 200,
                        width: 200,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white70,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Could not load the screenshot. Check your connection '
                        'and tap the proof again.',
                        textAlign: TextAlign.center,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prominent expected-amount display placed directly above the seller's
/// Confirm/Reject buttons (Threat T5 mitigation — reduces seller error by
/// giving the seller the exact number to cross-check against the platform
/// GCash statement, instead of relying on memory or the screenshot alone).
///
/// This is a mitigation, not a technical control: there is no way to
/// cryptographically verify a manual, off-platform GCash transfer.
class GcashExpectedAmountBanner extends StatelessWidget {
  final double total;

  const GcashExpectedAmountBanner({super.key, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2415),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.payments_outlined,
                size: 16,
                color: kGcashReceiptMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify this exact amount in your GCash app',
                  style: AppConstants.bodyStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: kGcashReceiptMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₱${total.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: kGcashReceiptInk,
            ),
          ),
        ],
      ),
    );
  }
}
