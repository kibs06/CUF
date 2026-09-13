import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../constants/app_constants.dart';
import '../../../constants/seller_theme_constants.dart';
import '../../../services/direct_gcash_service.dart';
import '../../../services/reservation_service.dart';
import '../../../widgets/sole_primary_button.dart';

/// Seller-side verification of a bulk-reservation GCash deposit proof
/// (mirrors the dormant direct-GCash order verification UX): shows the
/// store's static QR + GCash details and the customer's submitted
/// reference + screenshot (signed URL from the private bucket), then
/// Confirm (draws stock) or Reject (terminal, nothing was drawn).
///
/// Data model: proofs live in `bulk_reservation_deposits`
/// (migration 20260913140000) — one per reservation, referenced from
/// `bulk_reservations.deposit_proof_id` once confirmed.
class DepositProofReviewSheet extends StatefulWidget {
  final BulkReservation reservation;
  final VoidCallback onResolved;

  const DepositProofReviewSheet({
    super.key,
    required this.reservation,
    required this.onResolved,
  });

  /// Opens the sheet; refreshes the queue when a decision lands.
  static Future<void> show(
    BuildContext context, {
    required BulkReservation reservation,
    required VoidCallback onResolved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DepositProofReviewSheet(
        reservation: reservation,
        onResolved: onResolved,
      ),
    );
  }

  @override
  State<DepositProofReviewSheet> createState() =>
      _DepositProofReviewSheetState();
}

class _DepositProofReviewSheetState extends State<DepositProofReviewSheet> {
  final _reservationService = ReservationService.instance;
  final _gcashService = DirectGcashService();

  Map<String, dynamic>? _proof;
  String? _proofImageUrl;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProof();
  }

  Future<void> _loadProof() async {
    try {
      final rows = await Supabase.instance.client
          .from('bulk_reservation_deposits')
          .select()
          .eq('reservation_id', widget.reservation.id)
          .limit(1);
      if (!mounted) return;
      if ((rows as List).isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No proof was submitted for this reservation yet.';
        });
        return;
      }
      final proof = Map<String, dynamic>.from(rows.first);
      final path = proof['screenshot_url']?.toString();
      if (path != null && path.isNotEmpty) {
        // The bucket is private — display via a short-lived signed URL.
        _proofImageUrl = await _gcashService.proofScreenshotUrl(path);
      }
      setState(() {
        _proof = proof;
        _loading = false;
      });
      return;
    } catch (e) {
      debugPrint('deposit proof load failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Could not load the proof. Please try again.';
    });
  }

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm deposit received?',
            style: AppConstants.headlineStyle(fontSize: 16)),
        content: Text(
          'Verify the ₱${widget.reservation.depositAmount?.toStringAsFixed(0) ?? '—'} '
          'payment in your GCash app first. Confirming reserves the '
          '${widget.reservation.quantity} units for the customer.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Confirm & hold stock',
              style: AppConstants.bodyStyle(
                  fontWeight: FontWeight.w600, color: SellerTheme.sageDark),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _reservationService.confirmDeposit(widget.reservation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onResolved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: SellerTheme.sage,
          content: Text(
              'Deposit confirmed — ${widget.reservation.quantity} units reserved.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyReservationError(e);
      });
    }
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reject deposit payment',
                    style: AppConstants.headlineStyle(fontSize: 17)),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  maxLength: 150,
                  autofocus: true,
                  style: AppConstants.bodyStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Reason (optional) — the customer sees this',
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Reject payment',
                        style: AppConstants.bodyStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (reason == null || !mounted) return; // cancelled
    setState(() => _busy = true);
    try {
      await _reservationService.rejectDeposit(widget.reservation.id,
          rejectionReason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onResolved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.error,
          content: const Text('Deposit payment rejected.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyReservationError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppConstants.secondary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Verify deposit payment',
                    style: AppConstants.headlineStyle(fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  '${r.quantity} units of ${r.productName} — '
                  '${r.customerName ?? 'A customer'}',
                  style: AppConstants.bodyStyle(
                      fontSize: 12, color: AppConstants.secondary),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  Text(_error!,
                      style: AppConstants.bodyStyle(
                          fontSize: 13, color: AppConstants.error))
                else ...[
                  // Amount + reference card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppConstants.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Expected deposit',
                            style: AppConstants.bodyStyle(
                                fontSize: 11, color: AppConstants.secondary)),
                        Text(
                          '₱${r.depositAmount?.toStringAsFixed(2) ?? '—'}',
                          style: AppConstants.headlineStyle(fontSize: 22),
                        ),
                        if (_proof?['reference_number'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Reference: ${_proof!['reference_number']}',
                            style: AppConstants.monoStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Screenshot
                  Text('Payment screenshot',
                      style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      height: 220,
                      color: AppConstants.secondary.withValues(alpha: 0.06),
                      child: _proofImageUrl == null
                          ? Center(
                              child: Text(
                                'Screenshot unavailable',
                                style: AppConstants.bodyStyle(
                                    fontSize: 12,
                                    color: AppConstants.secondary),
                              ),
                            )
                          : Image.network(
                              _proofImageUrl!,
                              fit: BoxFit.contain,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : const Center(
                                          child: CircularProgressIndicator()),
                              errorBuilder: (_, _, _) => Center(
                                child: Text(
                                  'Could not load the screenshot',
                                  style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      color: AppConstants.secondary),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check your GCash app for this exact amount and reference '
                    'before confirming. Confirming pulls the units out of your '
                    'sellable stock immediately.',
                    style: AppConstants.bodyStyle(
                        fontSize: 11, color: AppConstants.secondary),
                  ),
                ],
                if (_error != null && _proof != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: AppConstants.bodyStyle(
                          fontSize: 12, color: AppConstants.error)),
                ],
                const SizedBox(height: 16),
                if (!_loading && _proof != null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _reject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppConstants.error,
                            side: BorderSide(
                                color:
                                    AppConstants.error.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Reject',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: SolePrimaryButton(
                          label: 'Confirm & Hold Stock',
                          onPressed: _busy ? null : _confirm,
                          isLoading: _busy,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
