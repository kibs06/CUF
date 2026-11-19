// Seller's bulk (reseller) reservation queue. Approve opens the
// customer's 24-hour GCash deposit window (stock is NOT moved yet);
// once the customer submits a deposit proof, verify it here — confirming
// pulls the units out of sellable stock. Reject with a reason, or fulfill
// a deposit-paid hold once the reseller picks up.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/reservation_service.dart';
import '../../services/store_service.dart';
import '../../constants/bulk_deposit.dart';
import '../../utils/bulk_reservation_export.dart';
import '../../widgets/seller/bulk_reservation_share_sheet.dart';
import '../../widgets/seller/size_leader_rows.dart';
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

/// What the queue's menu can do with the list currently on screen.
enum _ListExport { share, csv }

class _ReservationRequestsScreenState extends State<ReservationRequestsScreen> {
  final _service = ReservationService.instance;
  final _storeService = StoreService.instance;
  List<BulkReservation>? _items;
  String? _storeId;
  String? _storeName;
  String? _error;
  String _filter = 'all'; // all | pending | active (live holds) | resolved
  bool _busy = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Opportunistic sweep: release anything past its deadline.
    await _service.expireStaleReservations();
    try {
      final store = await _storeService.getMyStore();
      _storeId ??= store?['id']?.toString();
      _storeName = store?['name']?.toString();
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
            'customer for a $kBulkReservationDepositLabel GCash deposit '
            'within 24 hours.';
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
          content: Text(
            approve
                ? 'Approved — the customer now has 24 hours to pay the deposit.'
                : 'Request declined.',
          ),
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
                Text(
                  'Approve reservation',
                  style: AppConstants.headlineStyle(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'Approving asks the customer to pay a '
                  '$kBulkReservationDepositLabel GCash deposit within 24 '
                  'hours. Stock leaves your sellable inventory '
                  'ONLY after you confirm their payment — approving alone '
                  'holds nothing. Pickup only: the customer collects the '
                  'units at your store, nothing is shipped.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Hold deadline after the deposit is confirmed: '
                  '${r.quantity} units for the chosen number of days.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                  ),
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Approve & request deposit (${selected > 1 ? '$selected days' : '1 day'} hold)',
                      style: AppConstants.bodyStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Decline request',
                  style: AppConstants.headlineStyle(fontSize: 17),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
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
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Decline request',
                      style: AppConstants.bodyStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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

  Future<void> _fulfill(BulkReservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Mark as fulfilled?',
          style: AppConstants.headlineStyle(fontSize: 16),
        ),
        content: Text(
          'Use this once the customer paid and picked up the '
          '${r.quantity} units.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Fulfilled',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.w600,
                color: SellerTheme.sageDark,
              ),
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

  /// The tab's own name, so an exported list says which slice it is.
  String get _filterLabel {
    switch (_filter) {
      case 'pending':
        return 'Pending';
      case 'active':
        return 'Active';
      case 'resolved':
        return 'Resolved';
      default:
        return 'All';
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppConstants.error : AppConstants.primary,
        content: Text(message),
      ),
    );
  }

  /// Opens the preview page first: a seller decides what leaves the phone
  /// after seeing it laid out, not from a two-line text snippet. The PDF is
  /// built only from that page's buttons.
  Future<void> _shareList() async {
    final list = _filtered;
    if (list.isEmpty) {
      _toast('Nothing to share in this list yet.');
      return;
    }
    await showBulkReservationShareSheet(
      context,
      items: list,
      filterLabel: _filterLabel,
      storeName: _storeName,
    );
  }

  Future<void> _downloadList() async {
    final list = _filtered;
    if (list.isEmpty) {
      _toast('Nothing to download in this list yet.');
      return;
    }
    setState(() => _exporting = true);
    try {
      // The BOM is for Excel: without it a CSV opened by double-click turns
      // the peso sign and accents into mojibake.
      final csv = '\uFEFF${reservationsCsv(list)}';
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await FileSaver.instance.saveAs(
        name: 'bulk-reservations-$day',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      _toast(
        saved == null
            ? 'Download cancelled — no file was saved.'
            : 'Saved to $saved',
      );
    } catch (e) {
      _toast('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Bulk Reservations',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _busy ? null : _load,
            tooltip: 'Refresh',
          ),
          // The list is what a seller takes to a supplier or to a spreadsheet,
          // so both exits sit one tap from the queue they describe. It exports
          // the CURRENT tab: "share this list" must mean the list on screen.
          PopupMenuButton<_ListExport>(
            enabled: !_exporting,
            tooltip: 'Share or download this list',
            icon: const Icon(Icons.ios_share, size: 19),
            onSelected: (choice) {
              switch (choice) {
                case _ListExport.share:
                  _shareList();
                case _ListExport.csv:
                  _downloadList();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ListExport.share,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_outlined, size: 18),
                  title: Text('Preview & share PDF'),
                ),
              ),
              PopupMenuItem(
                value: _ListExport.csv,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_outlined, size: 18),
                  title: Text('Download as CSV'),
                ),
              ),
            ],
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
                            color: AppConstants.secondary,
                          ),
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
                      storeName: _storeName,
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
            color: selected
                ? AppConstants.surfaceLight
                : AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        selectedColor: AppConstants.primary,
        side: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.7)),
      ),
    );
  }
}

/// One reservation in the queue.
///
/// Collapsed, it answers the three questions the queue exists for — what, who,
/// and how many — plus the one action the state allows. Expanded, it is the
/// record: every size with its colour, the customer's note, the deposit gate,
/// the hold deadline, when the request arrived, and the id a seller quotes when
/// asking about it. It also carries the per-reservation share, because the
/// thing a seller forwards to a supplier is one hold, not the whole queue.
class _SellerReservationTile extends StatefulWidget {
  final BulkReservation reservation;
  final String? storeName;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onFulfill;
  final VoidCallback onVerifyDeposit;

  const _SellerReservationTile({
    required this.reservation,
    this.storeName,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onFulfill,
    required this.onVerifyDeposit,
  });

  @override
  State<_SellerReservationTile> createState() => _SellerReservationTileState();
}

class _SellerReservationTileState extends State<_SellerReservationTile> {
  bool _expanded = false;

  BulkReservation get r => widget.reservation;

  /// Same preview the app bar opens, scoped to this one hold — a seller
  /// forwards one request to a supplier far more often than the whole queue.
  Future<void> _share() async {
    await showBulkReservationShareSheet(
      context,
      items: [r],
      filterLabel: 'Single reservation',
      storeName: widget.storeName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // ── Header — the whole strip toggles the details ─────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
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
                      const SizedBox(width: 2),
                      // Chevron is the affordance: it points the way the card
                      // will move, and turns as the details open.
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: SellerTheme.textMuted,
                        ),
                      ),
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
                  // Collapsed glimpse of the sizes: enough to know whether the
                  // hold is one size or a spread, without opening the card.
                  if (!_expanded && r.requestedSizes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      sizesSummary(r),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppConstants.bodyStyle(
                        fontSize: 11.5,
                        color: SellerTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Details ──────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: _buildDetails(),
                  )
                : const SizedBox(width: double.infinity),
          ),

          // ── Actions — the state's one move, always visible ───────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: _buildActions(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.requestedSizes.isNotEmpty) ...[
          // One size per line, leader to the count: chips forced the reader to
          // parse a sentence, and a pulling list is read down the column.
          Text(
            'SIZES REQUESTED',
            style: AppConstants.monoStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: SellerTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          SizeLeaderRows(reservation: r),
          const SizedBox(height: 8),
        ],
        if (r.note != null && r.note!.trim().isNotEmpty) ...[
          _DetailLine(label: 'Note', value: '"${r.note!.trim()}"'),
          const SizedBox(height: 4),
        ],
        if (r.createdAt != null)
          _DetailLine(label: 'Requested', value: _stamp(r.createdAt!)),
        // The code the customer claimed, and what it took off the price they
        // will pay at pickup — the store has to honour it at handover.
        if (r.voucherCode != null && r.voucherCode!.isNotEmpty)
          _DetailLine(
            label: 'Voucher',
            value:
                '${r.voucherCode} · −₱'
                '${(r.voucherDiscount ?? 0).toStringAsFixed(2)} off at pickup',
          ),
        if (r.depositAmount != null)
          _DetailLine(
            label: 'Deposit',
            value:
                '₱${r.depositAmount!.toStringAsFixed(0)} · ${r.depositStatus}'
                '${r.depositDeadline != null ? ' · due ${_stamp(r.depositDeadline!)}' : ''}',
          ),
        if (r.depositPaidAt != null)
          _DetailLine(label: 'Deposit paid', value: _stamp(r.depositPaidAt!)),
        if (r.expiresAt != null && !r.isTerminal)
          _DetailLine(
            label: r.isApproved ? 'Held until' : 'Window ends',
            value: _stamp(r.expiresAt!),
          ),
        if (r.isAwaitingDeposit) ...[
          const SizedBox(height: 6),
          Text(
            'No stock is held yet — it leaves your inventory only after you confirm their payment.',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: SellerTheme.textMuted,
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
        if (r.rejectionReason != null && r.rejectionReason!.trim().isNotEmpty)
          _DetailLine(label: 'Declined', value: r.rejectionReason!.trim()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'ID ${r.id.length > 8 ? r.id.substring(0, 8) : r.id}',
                style: AppConstants.monoStyle(
                  fontSize: 10.5,
                  color: SellerTheme.textMuted,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share, size: 15),
              label: Text(
                'Share',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: SellerTheme.sageDark,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions() {
    if (r.isPending) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: widget.busy ? null : widget.onReject,
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
                onPressed: widget.busy ? null : widget.onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: SellerTheme.sage,
                  disabledBackgroundColor: SellerTheme.sage.withValues(
                    alpha: 0.6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: widget.busy
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
      );
    }
    if (r.isAwaitingDeposit) {
      return _TileAction(
        label: 'Verify Deposit Payment',
        color: _depositAmber,
        busy: widget.busy,
        onPressed: widget.onVerifyDeposit,
      );
    }
    if (r.isApproved) {
      return _TileAction(
        label: 'Mark Fulfilled',
        color: SellerTheme.sage,
        busy: widget.busy,
        onPressed: widget.onFulfill,
      );
    }
    // Resolved rows have no action left; the card keeps a little breathing
    // room rather than collapsing the padding to nothing.
    return const SizedBox.shrink();
  }

  /// `Nov 20 (3d left)` — a compact deadline for the header line.
  static String _fmt(DateTime d) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final diff = d.difference(now);
    final date = '${months[d.month]} ${d.day}';
    if (diff.inDays >= 1) return '$date (${diff.inDays}d left)';
    if (diff.inHours >= 1) return '$date (${diff.inHours}h left)';
    if (diff.isNegative) return date;
    return '$date (${diff.inMinutes}m left)';
  }

  /// A full timestamp for the details block — the header's relative form
  /// ("3d left") is useful at a glance and useless in a record.
  static String _stamp(DateTime d) {
    final local = d.toLocal();
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h24 = local.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    return '${months[local.month]} ${local.day}, ${local.year} · $h:$mm '
        '${h24 >= 12 ? 'PM' : 'AM'}';
  }
}

/// One `label — value` line in the expanded block. Label in muted caps, value
/// on the next line: a long deposit string wraps instead of squeezing.
class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: SellerTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppConstants.secondary,
              ),
            ),
          ),
        ],
      ),
    );
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
