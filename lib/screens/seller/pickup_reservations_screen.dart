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

  /// The latest goodwill grant per reservation, so a hold whose deadline the
  /// store moved shows the reason it was moved.
  Map<String, PickupExtensionGrant> _grants = const {};
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
      // Best-effort: the pickup queue must still open on a database where the
      // goodwill trail has not been applied yet (or is briefly unreadable), and
      // the trail is decoration on this screen, not the work itself.
      var grants = <String, PickupExtensionGrant>{};
      try {
        grants = latestGrantByReservation(
            await _service.fetchStoreGrants(storeId));
      } catch (e) {
        debugPrint('pickup extension grants unavailable: $e');
      }
      if (!mounted) return;
      setState(() {
        _storeId = storeId;
        _items = items;
        _grants = grants;
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

  /// GOODWILL: give a live hold more time because the store chooses to.
  ///
  /// Asks for a reason first, and will not proceed without one — the server
  /// requires it too (3–280 characters) and records it in the trail, so a
  /// deadline this screen moves can always be explained later. Separate from the
  /// customer's own extension, with its own budget: being generous here does not
  /// use up anything the customer was entitled to.
  Future<void> _grant(PickupReservation r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _GrantExtensionDialog(reservation: r),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final deadline = await _service.grantExtension(
        reservationId: r.id,
        reason: reason,
      );
      if (!mounted) return;
      final when = deadline == null
          ? 'The hold now runs longer.'
          : 'The hold now runs until '
              '${formatPickupDeadline(deadline)}.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Extended for the customer — $when'),
          backgroundColor: AppConstants.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyPickupReservationError(e)),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  /// "Customer arrived" — records the pickup as a POS sale. The stock was
  /// already drawn when the hold was created, so this does not move stock
  /// again; it records the sale and closes the hold.
  Future<void> _fulfill(PickupReservation r, {String? code}) async {
    final method = await _askPaymentMethod(r);
    if (method == null) return;

    setState(() => _busy = true);
    try {
      // `code` is set only on the counter path, where the seller typed the
      // customer's code rather than tapping a tile: the server then resolves
      // the code for THIS store and runs the ordinary fulfilment. Same sale,
      // same rules — `fulfill_pickup_reservation_by_code` delegates to
      // `fulfill_pickup_reservation` rather than re-implementing it.
      if (code != null) {
        await _service.fulfillByCode(code, paymentMethod: method);
      } else {
        await _service.fulfill(r.id, paymentMethod: method);
      }
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

  /// "How was it paid?" — one sheet, shared by the tile action and the counter
  /// path. Extracted rather than copied so the two cannot ask differently.
  Future<String?> _askPaymentMethod(PickupReservation r) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
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
  }

  /// THE COUNTER FLOW: the customer reads out their code, the seller types it,
  /// and the hold is collected. This is what the code exists for — the seller is
  /// standing next to the customer and neither of them wants to scroll a list
  /// together to work out which hold is the one in front of them.
  ///
  /// It resolves FIRST and shows what it found before taking the payment, so the
  /// seller is never asked "cash or GCash?" about a hold they have not seen and
  /// about to hand over the wrong pair. One typing, one confirmation, one tap.
  Future<void> _collectByCode() async {
    // The typed value is tracked in a plain local rather than a
    // TextEditingController owned by this method. A controller created here
    // cannot be disposed at a safe moment: `showDialog` returns as soon as the
    // route is popped, while the dialog's exit transition is STILL rebuilding
    // the TextField — disposing it there throws "A TextEditingController was
    // used after being disposed" (caught by the counter-flow widget test).
    var typed = '';
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text('Collect by code',
            style: AppConstants.headlineStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type the ${PickupReservation.codeLength}-character code the '
              'customer is showing. Spaces and dashes are fine.',
              style: AppConstants.bodyStyle(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              autofocus: true,
              onChanged: (value) => typed = value,
              // Upper case as it is typed: the code is stored in upper case, and
              // the keyboard default would otherwise make every entry look wrong.
              textCapitalization: TextCapitalization.characters,
              style: AppConstants.monoStyle(fontSize: 20),
              maxLength: PickupReservation.codeLength + 2,
              decoration: InputDecoration(
                hintText: '4F7-K2Q',
                counterText: '',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(ctx, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, typed),
            child: const Text('Find hold'),
          ),
        ],
      ),
    );

    final normalized = code == null ? null : PickupReservation.normalizeCode(code);
    if (normalized == null || normalized.isEmpty) return;

    setState(() => _busy = true);
    try {
      final id = await _service.resolveCode(normalized);
      final hold = await _service.fetchById(id);
      if (!mounted) return;
      setState(() => _busy = false);

      if (hold == null) {
        // The code resolved but the row is not readable — treat it as a miss
        // rather than as a hold to collect: the resolver already proved it is
        // this store's, so this is a transient read problem, not a wrong code.
        _snack('Could not load that hold. Pull to refresh and try again.',
            error: true);
        return;
      }
      if (!hold.isActive) {
        // A resolved hold still RESOLVES (that is the dispute case), so say what
        // it is instead of pretending the code was wrong.
        _snack('That hold is already ${hold.statusLabel.toLowerCase()} — '
            '${hold.quantity} × size ${hold.size} of ${hold.productName}.');
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text('Collect this hold?',
              style: AppConstants.headlineStyle(fontSize: 17)),
          content: Text(
            '${hold.quantity} × size ${hold.size} of ${hold.productName}'
            '${hold.customerName == null || hold.customerName!.isEmpty ? '' : ' for ${hold.customerName}'}'
            '.\n\nCode ${hold.pickupCodeLabel ?? normalized}.',
            style: AppConstants.bodyStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not this one'),
            ),
            // The confirmation is where the amount of work stops: the payment
            // question follows and then the sale is recorded. "One action" is
            // this tap, not a list hunt.
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, collecting'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _fulfill(hold, code: normalized);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(friendlyPickupReservationError(e), error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppConstants.error : AppConstants.success,
        content: Text(message),
      ),
    );
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
          // The counter affordance. An action rather than a field on the page:
          // most of the time nobody types a code, and a permanent input would
          // take the top of a screen whose job is to show the holds.
          IconButton(
            icon: const Icon(Icons.qr_code_2, size: 20),
            onPressed: _busy ? null : _collectByCode,
            tooltip: 'Collect by code',
          ),
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
                        onGrant: () => _grant(shown[i]),
                        grant: _grants[shown[i].id],
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

/// The reason prompt for a goodwill extension.
///
/// A dialog rather than a one-tap button on purpose: the server requires a
/// reason and records it in the trail, so the ask belongs in the flow — a
/// granted deadline is meant to be explainable later, not merely possible.
/// Returns the trimmed reason, or null when the seller backs out.
class _GrantExtensionDialog extends StatefulWidget {
  final PickupReservation reservation;

  const _GrantExtensionDialog({required this.reservation});

  @override
  State<_GrantExtensionDialog> createState() => _GrantExtensionDialogState();
}

class _GrantExtensionDialogState extends State<_GrantExtensionDialog> {
  final _controller = TextEditingController();
  String? _error;

  /// The reasons that actually come up on a counter phone call. Tapping one
  /// fills the field rather than submitting it — the seller still sees, and can
  /// still edit, exactly what will be recorded.
  static const _presets = [
    'Customer is stuck in traffic',
    'Customer called, running late',
    'We closed early today',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    // Mirrors the server's own bound (and the CHECK on the trail).
    if (reason.length < 3 || reason.length > 280) {
      setState(() => _error = 'Add a short reason (3-280 characters).');
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    return AlertDialog(
      backgroundColor: AppConstants.surfaceLight,
      title: Text(
        'Give the customer more time?',
        style: AppConstants.headlineStyle(fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.quantity} ${r.quantity == 1 ? 'pair' : 'pairs'} of size ${r.size}'
            '${r.color == null ? '' : ' (${r.color})'}'
            '${r.pickupDeadline == null ? '' : ' — currently until '
                '${formatPickupDeadline(r.pickupDeadline!)}'}',
            style: AppConstants.bodyStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Text(
            'This adds ${PickupReservation.storeExtensionHours}h and is recorded '
            'as a goodwill extension — the reason is kept with the hold, so a '
            'later deadline can always be explained.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 280,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Why are we giving more time?',
              errorText: _error,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final preset in _presets)
                ActionChip(
                  label: Text(preset,
                      style: AppConstants.bodyStyle(fontSize: 11.5)),
                  backgroundColor: AppConstants.creamDeep,
                  onPressed: () => setState(() {
                    _controller.text = preset;
                    _error = null;
                  }),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: AppConstants.bodyStyle(
                  fontSize: 13, color: AppConstants.secondary)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppConstants.primary),
          child: Text(
            'Give ${PickupReservation.storeExtensionHours}h',
            style: AppConstants.bodyStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _PickupAdminTile extends StatelessWidget {
  final PickupReservation reservation;
  final DateTime now;
  final bool busy;
  final VoidCallback onFulfill;
  final VoidCallback onRelease;
  final VoidCallback onGrant;

  /// The latest goodwill grant on this hold, if the store has made one — so a
  /// deadline that moved has its reason printed right next to it.
  final PickupExtensionGrant? grant;

  const _PickupAdminTile({
    required this.reservation,
    required this.now,
    required this.busy,
    required this.onFulfill,
    required this.onRelease,
    required this.onGrant,
    this.grant,
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
            // The colour the customer chose sits FIRST on the line: it is what
            // decides which pair comes off the shelf.
            '${r.color != null ? '${r.color} · ' : ''}'
            'Size ${r.size} · ${r.quantity} '
            '${r.quantity == 1 ? 'pair' : 'pairs'}'
            // The counter code, on the tile the seller is looking at while the
            // customer reads theirs out: the point is to see at a glance that
            // they match BEFORE anything is handed over.
            '${r.pickupCodeLabel != null ? ' · code ${r.pickupCodeLabel}' : ''}'
            '${r.customerName != null ? ' · ${r.customerName}' : ''}'
            // A later deadline is never a mystery. Both ways it can move are
            // named here: the customer asked (once), or the store chose to give
            // more time — and the latter also prints its reason below.
            '${r.extensionCount > 0 ? ' · extended ×${r.extensionCount}' : ''}'
            '${r.storeExtended ? ' · store +${r.storeExtensionCount}' : ''}',
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
            // GOODWILL, deliberately on its own line rather than beside
            // "Customer arrived": it is not part of the counter workflow, and it
            // asks for a reason before it does anything.
            if (r.canBeGrantedAt(now))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : onGrant,
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                  label: Text(
                    r.grantActionLabel ?? 'Give time',
                    style: AppConstants.bodyStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primary,
                    ),
                  ),
                ),
              ),
            if (grant != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.history_toggle_off,
                        size: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'You gave ${grant!.hoursGranted}h: “${grant!.reason}”',
                        style: AppConstants.bodyStyle(
                          fontSize: 11.5,
                          color: AppConstants.secondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
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
