import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/pickup_reservation_service.dart';
import '../../widgets/sole_card.dart';

/// The customer's FREE pickup holds (ANQUI item 14): what is being held,
/// how long is left, and a cancel action.
///
/// Separate from `MyReservationsScreen` (bulk reseller holds with the
/// deposit gate) — these holds are free, have no deposit, and start holding
/// stock the moment they are created.
class MyPickupReservationsScreen extends StatefulWidget {
  const MyPickupReservationsScreen({super.key, this.service});

  /// Injectable for tests: the extension rules are the one place this screen
  /// can make a promise the server refuses to keep.
  final PickupReservationService? service;

  @override
  State<MyPickupReservationsScreen> createState() =>
      _MyPickupReservationsScreenState();
}

class _MyPickupReservationsScreenState
    extends State<MyPickupReservationsScreen> {
  PickupReservationService get _service =>
      widget.service ?? PickupReservationService.instance;

  List<PickupReservation>? _items;
  String? _error;
  bool _busy = false;

  /// Re-renders the countdowns without a round trip.
  Timer? _ticker;

  /// Read once per build so every row on screen judges "expiring soon"
  /// against the same instant.
  DateTime _now = DateTime.now();

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
    // Opportunistic sweeps (no pg_cron in this database): expire anything
    // lapsed, and let anyone inside the last 2 hours be reminded once.
    await _service.expireStale();
    await _service.sendReminders();
    try {
      final items = await _service.fetchMine();
      if (!mounted) return;
      setState(() {
        _items = items;
        _now = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPickupReservationError(e));
    }
  }

  /// "I am on my way, but I will not make it." One extra window, then the
  /// store's patience is spent — so the dialog says what the store is being
  /// asked for, not just what the customer gets.
  Future<void> _extend(PickupReservation r) async {
    final now = DateTime.now();
    final newDeadline = r.pickupDeadline?.add(
      const Duration(hours: PickupReservation.extensionHours),
    );
    final lastOne = r.extensionsLeft <= 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ask for more time?',
            style: AppConstants.headlineStyle(fontSize: 16)),
        content: Text(
          'The store keeps your ${r.quantity} × size ${r.size} off the shelf '
          'until ${newDeadline == null ? 'later' : _dateTimeLabel(newDeadline)}'
          '${r.storeName.isNotEmpty ? ' at ${r.storeName}' : ''} — nobody else '
          'can buy them in the meantime.\n\n'
          '${lastOne ? 'This is the only extension a hold gets, so the store is '
              'never left holding stock indefinitely.' : 'You can extend once more after this.'}'
          '\n\nIt is still free, and you still pay when you collect.',
          style: AppConstants.bodyStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Extend ${PickupReservation.extensionHours}h',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppConstants.primary,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The dialog can sit open across the deadline; re-check before asking the
    // server, so the customer is not told "extended" by a screen that is
    // already stale.
    if (!r.canExtendAt(now)) {
      await _load();
      return;
    }

    setState(() => _busy = true);
    try {
      final deadline = await _service.extend(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.success,
          content: Text(
            deadline == null
                ? 'Hold extended.'
                : 'Hold extended to ${_dateTimeLabel(deadline)} — the store is '
                    'still holding it for you.',
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
          content: Text(friendlyPickupReservationError(e)),
        ),
      );
      // A refusal is usually "it already lapsed" — show the truth.
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// 'Sep 16, 18:30' — matches how the bulk reservation screens show a
  /// deadline; the project has no shared date formatter.
  static String _dateTimeLabel(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  Future<void> _cancel(PickupReservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Release this hold?',
            style: AppConstants.headlineStyle(fontSize: 16)),
        content: Text(
          'The ${r.quantity} × size ${r.size} goes back on the shelf and '
          'someone else can buy it. Nothing is charged — this hold is free.',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
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
          content: Text('Hold released — the stock is back on the shelf.'),
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
        title: Text('My Pickup Reservations',
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
      return _centered(_error!, retry: true);
    }
    final items = _items;
    if (items == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }
    if (items.isEmpty) {
      return _centered(
        'No pickup reservations yet.\nUse "Reserve for pickup" on a product '
        'to hold a pair for 24 hours — it is free.',
      );
    }

    final active = items.where((r) => r.isActive).toList();
    final past = items.where((r) => !r.isActive).toList();

    return RefreshIndicator(
      color: AppConstants.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (active.isNotEmpty) ...[
            _sectionLabel('Being held for you (${active.length})'),
            for (final r in active) ...[
              _PickupTile(
                reservation: r,
                now: _now,
                onCancel: _busy ? null : () => _cancel(r),
                onExtend: (_busy || !r.canExtendAt(_now))
                    ? null
                    : () => _extend(r),
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (past.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionLabel('Earlier holds'),
            for (final r in past) ...[
              _PickupTile(reservation: r, now: _now, onCancel: null),
              const SizedBox(height: 12),
            ],
          ],
          // The caveat that matters: this is not an order.
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Text(
              'A pickup reservation is a free 24-hour hold, not an order — '
              'you pay in store when you collect. Unclaimed holds are '
              'released automatically.',
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                color: AppConstants.secondary.withValues(alpha: 0.6),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppConstants.primary,
          ),
        ),
      );

  Widget _centered(String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                retry ? Icons.error_outline : Icons.bookmark_border,
                size: 44,
                color: AppConstants.secondary.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              if (retry) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _load,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _PickupTile extends StatelessWidget {
  final PickupReservation reservation;
  final DateTime now;
  final VoidCallback? onCancel;
  final VoidCallback? onExtend;

  const _PickupTile({
    required this.reservation,
    required this.now,
    this.onCancel,
    this.onExtend,
  });

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final urgent = r.isExpiringSoonAt(now);
    final lapsed = r.hasLapsedAt(now);
    final color = !r.isActive
        ? AppConstants.secondary.withValues(alpha: 0.5)
        : (urgent || lapsed ? AppConstants.statusPendingColor : AppConstants.success);

    return SoleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  image: r.productImage != null
                      ? DecorationImage(
                          image: NetworkImage(r.productImage!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: r.productImage == null
                    ? const Icon(Icons.image_outlined,
                        size: 20, color: AppConstants.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.productName.isEmpty ? 'Product' : r.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Size ${r.size} · ${r.quantity} '
                      '${r.quantity == 1 ? 'pair' : 'pairs'}'
                      '${r.storeName.isNotEmpty ? ' · ${r.storeName}' : ''}',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              _chip(r.statusLabel, color),
            ],
          ),
          const SizedBox(height: 10),
          if (r.isActive) ...[
            Row(
              children: [
                Icon(
                  urgent || lapsed ? Icons.timer_off_outlined : Icons.schedule,
                  size: 15,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.countdownLabelAt(now),
                    style: AppConstants.bodyStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
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
          // What more time would cost the store, and whether it has already
          // been asked for — the note stays visible after the cap is used, so
          // a later deadline on the seller's side always has an explanation.
          if (r.extensionNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.more_time,
                    size: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.extensionNote!,
                      style: AppConstants.bodyStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  // Driven by the label, never a bare "Extend": the amount of
                  // time is the whole offer, so a button without it should not
                  // exist rather than fall back to something vague.
                  if (onExtend != null && r.extendActionLabel != null)
                    TextButton(
                      onPressed: onExtend,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        r.extendActionLabel!,
                        style: AppConstants.bodyStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (!r.isActive)
            Text(
              r.isFulfilled
                  ? 'Collected — recorded as an in-store sale.'
                  : 'Released — the stock went back on the shelf.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppConstants.monoStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      );
}
