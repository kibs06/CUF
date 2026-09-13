// Seller's bulk (reseller) reservation queue. Approve opens the
// customer's 24-hour GCash deposit window (stock is NOT moved yet);
// once the customer submits a deposit proof, verify it here — confirming
// pulls the units out of sellable stock. Reject with a reason, or fulfill
// a deposit-paid hold once the reseller picks up.
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/reservation_service.dart';
import '../../services/store_service.dart';
import 'widgets/deposit_proof_review_sheet.dart';
class ReservationRequestsScreen extends StatefulWidget {
  const ReservationRequestsScreen({super.key});

  @override
  State<ReservationRequestsScreen> createState() =>
      _ReservationRequestsScreenState();
}

class _ReservationRequestsScreenState extends State<ReservationRequestsScreen> {
  final _service = ReservationService.instance;
  final _storeService = StoreService.instance;
  List<BulkReservation>? _items;
  String? _storeId;
  String? _error;
  String _filter = 'all'; // all | pending | approved (active holds) | resolved
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Opportunistic sweep: release anything past its deadline.
    await _service.expireStaleReservations();
    try {
      _storeId ??= (await _storeService.getMyStore())?['id']?.toString();
      if (_storeId == null) {
        if (!mounted) return;
        setState(() => _error = 'No store found for this account.');
        return;
      }
      final items = await _service.fetchStoreReservations(_storeId!);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyReservationError(e));
    }
  }

  List<BulkReservation> get _filtered {
    final items = _items ?? const [];
    switch (_filter) {
      case 'pending':
        return items.where((r) => r.isPending).toList();
      case 'approved':
        // "Active" = every live hold: unpaid deposit windows + paid holds.
        return items.where((r) => r.isAwaitingDeposit || r.isApproved).toList();
      case 'resolved':
        return items.where((r) => r.isTerminal).toList();
      default:
        return items;
    }
  }

  int _countOf(String status) =>
      (_items ?? const []).where((r) => r.status == status).length;

  Future<void> _decide(BulkReservation r, {required bool approve}) async {
    int? days;
    String? reason;
    if (approve) {
      final picked = await _pickDeadline(r);
      if (picked == null || !mounted) return; // cancelled
      days = picked;
    } else {
      reason = await _pickRejectionReason();
      if (reason == null || !mounted) return; // cancelled
    }
    setState(() => _busy = true);
    try {
      await _service.decideReservation(
        reservationId: r.id,
        approve: approve,
        days: days,
        rejectionReason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: approve ? SellerTheme.sage : AppConstants.error,
          content: Text(approve
              ? 'Approved — the customer now has 24 hours to pay the deposit.'
              : 'Request declined.'),
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
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deadline picker: quick presets + custom days. Returns days or null.
  Future<int?> _pickDeadline(BulkReservation r) async {
    int selected = 7;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Approve reservation',
                    style: AppConstants.headlineStyle(fontSize: 17)),
                const SizedBox(height: 4),
                Text(
                  'Approving asks the customer to pay a 20% GCash deposit '
                  'within 24 hours. Stock leaves your sellable inventory '
                  'ONLY after you confirm their payment — approving alone '
                  'holds nothing.',
                  style: AppConstants.bodyStyle(
                      fontSize: 12, color: AppConstants.secondary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Hold deadline after the deposit is confirmed: '
                  '${r.quantity} units for the chosen number of days.',
                  style: AppConstants.bodyStyle(
                      fontSize: 12, color: AppConstants.secondary),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in const [1, 3, 7, 14, 30])
                      ChoiceChip(
                        label: Text('$d day${d > 1 ? 's' : ''}'),
                        selected: selected == d,
                        onSelected: (_) => setSheet(() => selected = d),
                        selectedColor: SellerTheme.sageBg,
                        labelStyle: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected == d
                              ? SellerTheme.sageDark
                              : AppConstants.secondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SellerTheme.sage,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'Approve & request deposit (${selected > 1 ? '$selected days' : '1 day'} hold)',
                      style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rejection reason picker with optional free text. Returns '' for a plain
  /// decline, or the typed reason. Null = cancelled.
  Future<String?> _pickRejectionReason() async {
    final ctrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Decline request',
                    style: AppConstants.headlineStyle(fontSize: 17)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 2,
                  maxLength: 150,
                  autofocus: true,
                  style: AppConstants.bodyStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        'Reason (optional) — the customer sees this',
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
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Decline request',
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
  }

  Future<void> _fulfill(BulkReservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Mark as fulfilled?',
            style: AppConstants.headlineStyle(fontSize: 16)),
        content: Text(
          'Use this once the customer paid and picked up the '
          '${r.quantity} units.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Fulfilled',
              style: AppConstants.bodyStyle(
                  fontWeight: FontWeight.w600,
                  color: SellerTheme.sageDark),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.fulfillReservation(r.id);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Bulk Reservations',
            style: AppConstants.headlineStyle(fontSize: 17)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  count: (_items ?? []).length,
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pending',
                  count: _countOf('pending'),
                  selected: _filter == 'pending',
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Active',
                  count: (_items ?? [])
                      .where((r) => r.isAwaitingDeposit || r.isApproved)
                      .length,
                  selected: _filter == 'approved',
                  onTap: () => setState(() => _filter = 'approved'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Resolved',
                  count: (_items ?? [])
                      .where((r) => r.isTerminal)
                      .length,
                  selected: _filter == 'resolved',
                  onTap: () => setState(() => _filter = 'resolved'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _items == null
                ? Center(
                    child: _error != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  style:
                                      AppConstants.bodyStyle(fontSize: 13)),
                              const SizedBox(height: 12),
                              TextButton(
                                  onPressed: _load,
                                  child: const Text('Retry')),
                            ],
                          )
                        : const CircularProgressIndicator(),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Icon(Icons.inventory_2_outlined,
                                  size: 56,
                                  color: AppConstants.secondary
                                      .withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  _filter == 'all'
                                      ? 'No reservation requests yet'
                                      : 'Nothing here',
                                  style: AppConstants.headlineStyle(
                                      fontSize: 15),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) => _SellerReservationTile(
                              reservation: filtered[i],
                              busy: _busy,
                              onApprove: () =>
                                  _decide(filtered[i], approve: true),
                              onReject: () =>
                                  _decide(filtered[i], approve: false),
                              onFulfill: () => _fulfill(filtered[i]),
                              onVerifyDeposit: () =>
                                  DepositProofReviewSheet.show(
                                context,
                                reservation: filtered[i],
                                onResolved: _load,
                              ),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primary.withValues(alpha: 0.12)
              : AppConstants.secondary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppConstants.primary
                    : AppConstants.secondary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? AppConstants.primary
                      : AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SellerReservationTile extends StatelessWidget {
  final BulkReservation reservation;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onFulfill;
  final VoidCallback onVerifyDeposit;

  const _SellerReservationTile({
    required this.reservation,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onFulfill,
    required this.onVerifyDeposit,
  });

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.quantity} units — ${r.productName}',
                      style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.customerName ?? 'A customer'}'
                      '${r.createdAt != null ? ' · ${_fmt(r.createdAt!)}' : ''}',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: r.status),
            ],
          ),
          // Requested size breakdown (informational)
          if (r.requestedSizes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in r.requestedSizes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          AppConstants.secondary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Size ${s['size']}: ${s['quantity']}',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (r.note != null && r.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${r.note}"',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.8),
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (r.isAwaitingDeposit) ...[
            const SizedBox(height: 6),
            Text(
              'Deposit: ₱${(r.depositAmount ?? 0).toStringAsFixed(0)} — waiting for the customer'
              '${r.depositDeadline != null ? ' · ${_fmt(r.depositDeadline!)} to pay' : ''}',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFB45309), // amber-700
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'No stock is held yet — it leaves your inventory only after you confirm their payment.',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (r.isApproved && r.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Held until ${_fmt(r.expiresAt!)}'
              '${r.depositStatus == 'paid' ? ' · deposit ₱${(r.depositAmount ?? 0).toStringAsFixed(0)} paid' : ''}',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SellerTheme.sageDark,
              ),
            ),
          ],
          if (r.status == 'expired') ...[
            const SizedBox(height: 6),
            Text(
              'Expired — stock returned to inventory',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Actions
          if (r.isPending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.error,
                      side: BorderSide(
                          color: AppConstants.error.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Decline',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: busy ? null : onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SellerTheme.sage,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Approve & Hold',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            )
          else if (r.isAwaitingDeposit)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onVerifyDeposit,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('Verify Deposit Payment',
                    style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(44, 36),
                ),
              ),
            )
          else if (r.isApproved)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onFulfill,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Mark Fulfilled',
                    style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: SellerTheme.sageDark,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(44, 36),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    final diff = d.difference(now);
    final date = '${months[d.month]} ${d.day}';
    if (diff.inDays >= 1) return '$date (${diff.inDays}d left)';
    if (diff.inHours >= 1) return '$date (${diff.inHours}h left)';
    if (diff.isNegative) return date;
    return '$date (${diff.inMinutes}m left)';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = SellerTheme.amber;
        label = 'Pending';
      case 'awaiting_deposit':
        color = const Color(0xFFB45309); // amber-700 — action needed
        label = 'Deposit needed';
      case 'approved':
        color = SellerTheme.sage;
        label = 'Reserved';
      case 'rejected':
        color = AppConstants.error;
        label = 'Declined';
      case 'cancelled':
        color = AppConstants.secondary;
        label = 'Cancelled';
      case 'expired':
        color = AppConstants.error;
        label = 'Expired';
      case 'fulfilled':
        color = AppConstants.primary;
        label = 'Fulfilled';
      default:
        color = AppConstants.secondary;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
