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

/// "Action needed" amber (amber-700) — the deposit gate's colour, on the status
/// chip, the deposit line and the verify action alike, so one state keeps one
/// colour wherever it appears on the card.
const Color _depositAmber = Color(0xFFB45309);

class _ReservationRequestsScreenState extends State<ReservationRequestsScreen> {
  final _service = ReservationService.instance;
  final _storeService = StoreService.instance;
  List<BulkReservation>? _items;
  String? _storeId;
  String? _error;
  String _filter = 'all'; // all | pending | active (live holds) | resolved
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

  /// Whether a reservation belongs to a group. The single definition of the
  /// grouping: both the list and the tab's count badge read it, so a badge can
  /// never claim a number the list it labels does not show.
  bool _matches(BulkReservation r, String filter) {
    switch (filter) {
      case 'pending':
        return r.isPending;
      case 'active':
        // "Active" = every live hold: unpaid deposit windows + paid holds.
        return r.isAwaitingDeposit || r.isApproved;
      case 'resolved':
        return r.isTerminal;
      default:
        return true;
    }
  }

  List<BulkReservation> get _filtered =>
      (_items ?? const []).where((r) => _matches(r, _filter)).toList();

  int _countFor(String filter) =>
      (_items ?? const []).where((r) => _matches(r, filter)).length;

  /// Empty-state copy per group. A bare "Nothing here" leaves the seller
  /// guessing what belongs in the tab; each group instead names itself and
  /// says what lands there, plus a way to re-check — the empty-state rule
  /// (helpful message + action, never a blank screen).
  String get _emptyTitle {
    switch (_filter) {
      case 'pending':
        return 'Nothing waiting on you';
      case 'active':
        return 'No live holds right now';
      case 'resolved':
        return 'Nothing closed yet';
      default:
        return 'No reservation requests yet';
    }
  }

  String get _emptyHint {
    switch (_filter) {
      case 'pending':
        return 'New reseller requests appear here. Approving one asks the '
            'customer for a 20% GCash deposit within 24 hours.';
      case 'active':
        return 'Approved reservations stay here — unpaid deposit windows and '
            'paid holds — until pickup or expiry.';
      case 'resolved':
        return 'Declined, fulfilled and expired requests end up here for '
            'your records.';
      default:
        return 'When a reseller asks to hold stock in bulk, the request '
            'lands here for your approval.';
    }
  }

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
      backgroundColor: AppConstants.surfaceLight,
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
      backgroundColor: AppConstants.surfaceLight,
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
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Bulk Reservations',
            style: AppConstants.headlineStyle(fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _busy ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _buildBody(filtered),
        ],
      ),
    );
  }

  Widget _buildBody(List<BulkReservation> filtered) {
    if (_error != null && _items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_items == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }

    return Column(
      children: [
        // Status groups — the same pill filters as the pickup queue, with the
        // count in the label, so the two queues read as one screen family.
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip('all', 'All (${_countFor('all')})'),
              _filterChip('pending', 'Pending (${_countFor('pending')})'),
              _filterChip('active', 'Active (${_countFor('active')})'),
              _filterChip('resolved', 'Resolved (${_countFor('resolved')})'),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _emptyTitle,
                          textAlign: TextAlign.center,
                          style: AppConstants.headlineStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _emptyHint,
                          textAlign: TextAlign.center,
                          style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.secondary),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppConstants.primary,
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _SellerReservationTile(
                      reservation: filtered[i],
                      busy: _busy,
                      onApprove: () => _decide(filtered[i], approve: true),
                      onReject: () => _decide(filtered[i], approve: false),
                      onFulfill: () => _fulfill(filtered[i]),
                      onVerifyDeposit: () => DepositProofReviewSheet.show(
                        context,
                        reservation: filtered[i],
                        onResolved: _load,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        label: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? AppConstants.surfaceLight : AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        selectedColor: AppConstants.primary,
        side: BorderSide(
          color: AppConstants.borderGray.withValues(alpha: 0.7),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Same card as an order card: one card language across the seller's
        // queues, including the raised fill and hairline that carry dark mode.
        color: SellerTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SellerTheme.cardBorder),
        boxShadow: SellerTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '${r.quantity} units — ${r.productName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppConstants.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: r.status),
            ],
          ),
          Divider(height: 16, color: SellerTheme.cardBorder),
          Text(
            '${r.customerName ?? 'A customer'}'
            '${r.createdAt != null ? ' · ${_fmt(r.createdAt!)}' : ''}',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary,
            ),
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
                      // The colour leads: it is the variant the customer is
                      // asking for, and what the seller has to pull.
                      '${s['color'] == null ? '' : '${s['color']} · '}'
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
                color: SellerTheme.textSecondary,
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
                color: _depositAmber,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'No stock is held yet — it leaves your inventory only after you confirm their payment.',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: SellerTheme.textMuted,
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
          const SizedBox(height: 12),
          // Actions — 36px-high buttons on the same 10px radius as an order
          // card's, so the two queues are tapped the same way.
          if (r.isPending)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: busy ? null : onReject,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppConstants.error),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Decline',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.error,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton(
                      onPressed: busy ? null : onApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: SellerTheme.sage,
                        disabledBackgroundColor:
                            SellerTheme.sage.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Approve & Hold',
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            )
          // The state's one primary action, full width and tinted by state —
          // the shape an order card's primary button already has.
          else if (r.isAwaitingDeposit)
            _TileAction(
              label: 'Verify Deposit Payment',
              color: _depositAmber,
              busy: busy,
              onPressed: onVerifyDeposit,
            )
          else if (r.isApproved)
            _TileAction(
              label: 'Mark Fulfilled',
              color: SellerTheme.sage,
              busy: busy,
              onPressed: onFulfill,
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

/// The reservation's state, in the same pill as an order's status chip: a
/// tinted pill with mono upper-case text. The tint pairs below are the seller
/// palette's own (see [SellerStatusChip]), so "Pending" here is the same pill
/// as "Pending" on an order — light-on-dark-legible on both brightnesses.
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    String label;
    switch (status) {
      case 'pending':
        bg = SellerTheme.amberBg;
        text = SellerTheme.amberDark;
        label = 'Pending';
      case 'awaiting_deposit':
        bg = SellerTheme.amberBg;
        text = _depositAmber; // action needed — the seller's move
        label = 'Deposit needed';
      case 'approved':
        bg = SellerTheme.sageBg;
        text = SellerTheme.sageDark;
        label = 'Reserved';
      case 'fulfilled':
        bg = SellerTheme.blueBg;
        text = SellerTheme.blue;
        label = 'Fulfilled';
      case 'rejected':
        bg = AppConstants.statusCancelledColor.withValues(alpha: 0.12);
        text = AppConstants.statusCancelledColor;
        label = 'Declined';
      case 'expired':
        bg = AppConstants.statusCancelledColor.withValues(alpha: 0.12);
        text = AppConstants.statusCancelledColor;
        label = 'Expired';
      default:
        bg = AppConstants.secondary.withValues(alpha: 0.1);
        text = AppConstants.secondary;
        label = status == 'cancelled' ? 'Cancelled' : status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppConstants.monoStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }
}

/// A tile's single primary action: full width, 36px, tinted by the state it
/// resolves, with the card's spinner while the call is in flight.
class _TileAction extends StatelessWidget {
  final String label;
  final Color color;
  final bool busy;
  final VoidCallback onPressed;

  const _TileAction({
    required this.label,
    required this.color,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
