import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/pickup_reservation_service.dart';
import '../../services/store_service.dart';

/// The store's FREE pickup holds (ANQUI item 14): who is holding what, how
/// long is left, and the two actions that resolve it — *customer arrived*
/// (records the pickup as a POS sale) and *release* (they never came).
///
/// NOT the bulk reservation queue (`ReservationRequestsScreen`): those are
/// deposit-gated reseller holds that need approval. A pickup hold is
/// already holding stock when it appears here.
class PickupReservationsScreen extends StatefulWidget {
  const PickupReservationsScreen({super.key, this.service, this.storeService});

  /// Injectable for tests, exactly like `showPickupReservationSheet` — the
  /// summary band and the lapsing filter are the store's whole early-warning
  /// system, so they are asserted rather than eyeballed.
  final PickupReservationService? service;
  final StoreService? storeService;

  @override
  State<PickupReservationsScreen> createState() =>
      _PickupReservationsScreenState();
}

class _PickupReservationsScreenState extends State<PickupReservationsScreen> {
  PickupReservationService get _service =>
      widget.service ?? PickupReservationService.instance;
  StoreService get _storeService =>
      widget.storeService ?? StoreService.instance;

  List<PickupReservation>? _items;
  String? _error;
  String? _storeId;
  bool _busy = false;
  String _filter = 'active';
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Opportunistic sweeps — releases lapsed holds and sends the T-2h
    // reminders (exactly-once server-side).
    await _service.expireStale();
    await _service.sendReminders();
    try {
      final storeId = _storeId ?? await _resolveStoreId();
      if (storeId == null || storeId.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'No store is linked to your account.');
        return;
      }
      final items = await _service.fetchForStore(storeId);
      if (!mounted) return;
      setState(() {
        _storeId = storeId;
        _items = items;
        _now = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPickupReservationError(e));
    }
  }

  /// Same resolution the bulk reservation queue uses, so a seller sees both
  /// queues for the same store.
  Future<String?> _resolveStoreId() async {
    final store = await _storeService.getMyStore();
    return store?['id']?.toString();
  }

  /// "Customer arrived" — records the pickup as a POS sale. The stock was
  /// already drawn when the hold was created, so this does not move stock
  /// again; it records the sale and closes the hold.
  Future<void> _fulfill(PickupReservation r) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer collected',
                  style: AppConstants.headlineStyle(fontSize: 17)),
              const SizedBox(height: 4),
              Text(
                '${r.quantity} × size ${r.size} of ${r.productName}. '
                'This is recorded as an in-store (POS) sale, so it counts in '
                'POS sales, revenue and "sold" counts.',
                style: AppConstants.bodyStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              Text('How was it paid?',
                  style: AppConstants.bodyStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'cash'),
                      child: const Text('Cash'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'gcash'),
                      child: const Text('GCash'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (method == null) return;

    setState(() => _busy = true);
    try {
      await _service.fulfill(r.id, paymentMethod: method);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.success,
          content: Text('Pickup recorded as a sale.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.error,
          content: Text(friendlyPickupReservationError(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _release(PickupReservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Release the hold?',
            style: AppConstants.headlineStyle(fontSize: 16)),
        content: Text(
          '${r.quantity} × size ${r.size} goes back into stock immediately and '
          'the customer is told the hold was released.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep holding'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Release',
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

    setState(() => _busy = true);
    try {
      await _service.cancel(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Hold released — the stock is back.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.error,
          content: Text(friendlyPickupReservationError(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Pickup Reservations',
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
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    final items = _items;
    if (items == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }

    final active = items.where((r) => r.isActive).toList();
    // A hold that has already passed its deadline but not yet been swept still
    // holds stock, so it belongs with the ones about to lapse — that is the
    // seller's chance to release it deliberately rather than waiting.
    bool lapsing(PickupReservation r) =>
        r.isExpiringSoonAt(_now) || r.hasLapsedAt(_now);
    final lapsingItems = active.where(lapsing).toList();
    final summary = PickupHoldSummary.from(active, _now);

    final shown = switch (_filter) {
      'lapsing' => lapsingItems,
      'active' => active,
      _ => items,
    };

    return Column(
      children: [
        if (!summary.isEmpty)
          _HoldSummaryBar(
            summary: summary,
            onShowLapsing: lapsingItems.isEmpty
                ? null
                : () => setState(() => _filter = 'lapsing'),
          ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip('active', 'Being held (${active.length})'),
              if (lapsingItems.isNotEmpty)
                _filterChip('lapsing', 'Lapsing soon (${lapsingItems.length})'),
              _filterChip('all', 'All (${items.length})'),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      switch (_filter) {
                        'active' =>
                          'No pickup reservations are being held right now.',
                        'lapsing' =>
                          'None of the holds are about to lapse — nothing is '
                              'coming back to stock soon.',
                        _ => 'No pickup reservations yet.',
                      },
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppConstants.primary,
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PickupAdminTile(
                        reservation: shown[i],
                        now: _now,
                        busy: _busy,
                        onFulfill: () => _fulfill(shown[i]),
                        onRelease: () => _release(shown[i]),
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

/// The store's at-a-glance band: what is off the shelf, and what is about to
/// come back. Deliberately above the filters, because "what am I about to get
/// back" is a question about the whole store, not about the list being viewed.
class _HoldSummaryBar extends StatelessWidget {
  final PickupHoldSummary summary;
  final VoidCallback? onShowLapsing;

  const _HoldSummaryBar({required this.summary, this.onShowLapsing});

  @override
  Widget build(BuildContext context) {
    final returning = summary.returningLabel;
    final urgent = returning != null;
    final accent =
        urgent ? AppConstants.statusPendingColor : AppConstants.primary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_outline, size: 15, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary.heldLabel,
                  style: AppConstants.bodyStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (returning != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: onShowLapsing,
              child: Row(
                children: [
                  Icon(Icons.undo, size: 15, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      returning,
                      style: AppConstants.bodyStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                  if (onShowLapsing != null)
                    Text(
                      'Show',
                      style: AppConstants.bodyStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (summary.lapsedLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              summary.lapsedLabel!,
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                color: AppConstants.secondary.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickupAdminTile extends StatelessWidget {
  final PickupReservation reservation;
  final DateTime now;
  final bool busy;
  final VoidCallback onFulfill;
  final VoidCallback onRelease;

  const _PickupAdminTile({
    required this.reservation,
    required this.now,
    required this.busy,
    required this.onFulfill,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final urgent = r.isExpiringSoonAt(now);
    final color = !r.isActive
        ? AppConstants.secondary.withValues(alpha: 0.5)
        : (urgent ? AppConstants.statusPendingColor : AppConstants.success);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_outline, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.productName.isEmpty ? 'Product' : r.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.statusLabel.toUpperCase(),
                  style: AppConstants.monoStyle(
                      fontSize: 9, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Size ${r.size} · ${r.quantity} '
            '${r.quantity == 1 ? 'pair' : 'pairs'}'
            '${r.customerName != null ? ' · ${r.customerName}' : ''}'
            // A later deadline is never a mystery: the customer asked for it,
            // once, and the row says so.
            '${r.extensionCount > 0 ? ' · extended ×${r.extensionCount}' : ''}',
            style: AppConstants.bodyStyle(
              fontSize: 12.5,
              color: AppConstants.secondary.withValues(alpha: 0.8),
            ),
          ),
          if (r.isActive) ...[
            const SizedBox(height: 4),
            Text(
              r.countdownLabelAt(now),
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onFulfill,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary,
                      minimumSize: const Size(0, 38),
                    ),
                    child: Text(
                      'Customer arrived',
                      style: AppConstants.bodyStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : onRelease,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    side: BorderSide(
                        color: AppConstants.error.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'Release',
                    style: AppConstants.bodyStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.error,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                r.isFulfilled
                    ? 'Collected and recorded as a POS sale.'
                    : 'Released — the stock went back.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
