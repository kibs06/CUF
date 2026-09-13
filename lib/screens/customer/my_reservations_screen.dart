import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/reservation_service.dart';
import '../../widgets/sole_card.dart';
import 'bulk_deposit_pay_screen.dart';

/// The customer's bulk (reseller) reservations: request status, countdown
/// on approved holds, cancel action. Reached from Profile.
class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  final _service = ReservationService.instance;
  List<BulkReservation>? _items;
  String? _error;
  bool _cancellingId = false;
  // Refreshes the deposit countdowns on open tiles.
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Opportunistic sweep: release anything past its deadline.
    await _service.expireStaleReservations();
    try {
      final items = await _service.fetchMyReservations();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyReservationError(e));
    }
  }

  /// Opens the deposit payment flow (GCash proof submission). The screen
  /// pops true once a proof is submitted → refresh.
  Future<void> _payDeposit(BulkReservation r) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BulkDepositPayScreen(reservation: r),
      ),
    );
    if (submitted == true) await _load();
  }

  Future<void> _cancel(BulkReservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel reservation?',
            style: AppConstants.headlineStyle(fontSize: 16)),
        content: Text(
          r.isApproved
              ? 'The ${r.quantity} reserved units go back to the store\'s '
                  'stock. Your paid deposit of '
                  '₱${(r.depositAmount ?? 0).toStringAsFixed(0)} is '
                  'NON-REFUNDABLE and will be forfeited.'
              : 'Your request will be withdrawn. No deposit has been paid, '
                  'so nothing is forfeited.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel reservation',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppConstants.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cancellingId = true);
    try {
      await _service.cancelReservation(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: const Text('Reservation cancelled.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.error,
          content: Text(friendlyReservationError(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('My Reservations',
            style: AppConstants.headlineStyle(fontSize: 17)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: _items == null
          ? Center(
              child: _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: AppConstants.bodyStyle(fontSize: 13)),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _items!.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(Icons.inventory_2_outlined,
                            size: 56,
                            color: AppConstants.secondary.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'No reservations yet',
                            style: AppConstants.headlineStyle(fontSize: 15),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            'Tap "Buying to resell?" on any product\nto request a bulk hold.',
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.secondary,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _ReservationTile(
                        reservation: _items![i],
                        cancelling: _cancellingId,
                        onCancel: () => _cancel(_items![i]),
                        onPayDeposit: () => _payDeposit(_items![i]),
                      ),
                    ),
            ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  final BulkReservation reservation;
  final bool cancelling;
  final VoidCallback onCancel;
  final VoidCallback onPayDeposit;

  const _ReservationTile({
    required this.reservation,
    required this.cancelling,
    required this.onCancel,
    required this.onPayDeposit,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppConstants.success;
      case 'pending':
        return const Color(0xFFF59E0B); // amber
      case 'awaiting_deposit':
        return const Color(0xFFD97706); // deeper amber — action needed
      case 'rejected':
      case 'expired':
        return AppConstants.error;
      case 'fulfilled':
        return AppConstants.primary;
      default:
        return AppConstants.secondary;
    }
  }

  /// Human "time left" for the 24h deposit window.
  String _depositTimeLeft(BulkReservation r) {
    final deadline = r.depositDeadline;
    if (deadline == null) return '';
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return 'window closed';
    if (left.inHours >= 1) {
      return '${left.inHours}h ${left.inMinutes % 60}m left';
    }
    return '${left.inMinutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final statusColor = _statusColor(r.status);
    return SoleCard(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      margin: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image (or placeholder)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: r.productImage != null
                ? Image.network(
                    r.productImage!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _imagePlaceholder,
                  )
                : _imagePlaceholder,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppConstants.bodyStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        r.statusLabel,
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.quantity} units · ${r.storeName}',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                  ),
                ),
                if (r.isAwaitingDeposit) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deposit: ₱${(r.depositAmount ?? 0).toStringAsFixed(0)} '
                    '(20% of estimated value)',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primary,
                    ),
                  ),
                  if (r.depositDeadline != null && !r.depositExpired) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Pay by ${_formatDate(r.depositDeadline!)} '
                      '(${_depositTimeLeft(r)})',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFD97706),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'The deposit is NON-REFUNDABLE once paid.',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (r.isApproved && r.expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Held until ${_formatDate(r.expiresAt!)}'
                    '${r.depositStatus == 'paid' ? ' · deposit paid' : ''}',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.success,
                    ),
                  ),
                ],
                if (r.isPending && r.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Requested ${_formatDate(r.createdAt!)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                if (r.depositStatus == 'forfeited') ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deposit forfeited (non-refundable)',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.error,
                    ),
                  ),
                ],
                if (r.rejectionReason != null &&
                    r.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reason: ${r.rejectionReason}',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.error,
                    ),
                  ),
                ],
                if (r.needsDeposit && !cancelling) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onPayDeposit,
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: Text(
                        'Pay Deposit — '
                        '₱${(r.depositAmount ?? 0).toStringAsFixed(0)}',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
                if ((r.isPending || r.isAwaitingDeposit || r.isApproved) &&
                    !cancelling)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 36),
                      ),
                      child: Text(
                        'Cancel',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget get _imagePlaceholder => Container(
        width: 56,
        height: 56,
        color: AppConstants.secondary.withValues(alpha: 0.08),
        child: Icon(Icons.image_outlined,
            size: 22, color: AppConstants.secondary.withValues(alpha: 0.4)),
      );

  static String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
