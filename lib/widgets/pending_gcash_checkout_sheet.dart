import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../services/direct_gcash_service.dart';
import 'sole_card.dart';
import 'sole_primary_button.dart';

/// Action chosen from the pending-GCash-checkout resolution sheet.
/// `null` (dismiss / Not Now) means "do nothing for now".
enum PendingCheckoutAction { complete, cancel }

/// Premium bottom sheet shown when a customer hits the one-open-order cap
/// (23505): they already have an `awaiting_payment_confirmation` GCash order
/// with a live payment window. Renders what they're paying for (items from
/// the order), a real-time countdown, and the three ranked actions:
///
/// 1. **Complete Payment** — full-width filled button (resume the pay screen;
///    becomes "Track My Order" once proof was submitted).
/// 2. **Not Now** — neutral ghost/outlined dismiss.
/// 3. **Cancel Pending Order** — de-emphasized destructive action, below a
///    divider, only offered while no proof has been submitted.
///
/// This is a visual/structural redesign only — the returned action is handled
/// by the caller exactly like the old dialog's 'complete' / 'cancel' strings.
Future<PendingCheckoutAction?> showPendingGcashCheckoutSheet({
  required BuildContext context,
  required PendingGcashOrder pending,

  /// Injectable clock for the live countdown (defaults to [DateTime.now]).
  /// Tests pass a controllable clock so the ticking timer is deterministic.
  DateTime Function()? now,
}) {
  return showModalBottomSheet<PendingCheckoutAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true, // swipe-down dismiss
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _PendingGcashCheckoutSheet(pending: pending, now: now),
  );
}

// ── Amber palette for the urgency accents ────────────────────────────
// Base matches AppConstants.statusPendingColor; the darker shades are
// chosen so the ring and text clear WCAG AA contrast on light surfaces.
const _amber = Color(0xFFF59E0B); // base amber (chip fill / soft tint)
const _amberRing = Color(0xFFB45309); // ring stroke — AA for UI graphics
const _amberText = Color(0xFF92400E); // chip label — AA for body text

class _PendingGcashCheckoutSheet extends StatefulWidget {
  final PendingGcashOrder pending;
  final DateTime Function()? now;

  const _PendingGcashCheckoutSheet({required this.pending, this.now});

  @override
  State<_PendingGcashCheckoutSheet> createState() =>
      _PendingGcashCheckoutSheetState();
}

class _PendingGcashCheckoutSheetState extends State<_PendingGcashCheckoutSheet> {
  // Expandable "In this order" card.
  bool _itemsExpanded = false;

  late final DateTime Function() _now = widget.now ?? DateTime.now;

  PendingGcashOrder get _pending => widget.pending;

  /// The full window length (creation → deadline). Defaults to 30 min if
  /// the creation timestamp is missing, so the ring still has a scale.
  Duration get _totalWindow {
    final deadline = _pending.deadline;
    if (deadline == null) return const Duration(minutes: 30);
    final createdAt = _pending.createdAt;
    if (createdAt != null && deadline.isAfter(createdAt)) {
      return deadline.difference(createdAt);
    }
    return const Duration(minutes: 30);
  }

  void _dismiss() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  void _complete() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(PendingCheckoutAction.complete);
  }

  void _cancel() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(PendingCheckoutAction.cancel);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final proofSubmitted = pending.proofSubmitted;
    final shortId = pending.id.length >= 8
        ? pending.id.substring(pending.id.length - 8)
        : pending.id;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        // Glassmorphism: blur the dimmed checkout screen behind the sheet,
        // then overlay a translucent surface tint so the blur shows through.
        // (The tint must live INSIDE the filter — a background painted before
        // BackdropFilter would be part of the blurred sample itself.)
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppConstants.surfaceLight.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 28 * (1 - t)),
                  child: child,
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: SingleChildScrollView(
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _handleBar(),
                        // ── Badge + close ───────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                          child: Row(
                            children: [
                              _amberBadge(),
                              const Spacer(),
                              IconButton(
                                onPressed: _dismiss,
                                tooltip: 'Not now',
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 22,
                                ),
                                color: AppConstants.secondary
                                    .withValues(alpha: 0.65),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.05),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Headline ────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Text(
                            'You have a pending GCash checkout',
                            style: AppConstants.headlineStyle(fontSize: 21)
                                .copyWith(height: 1.2),
                          ),
                        ),
                        // ── Order meta + amount ─────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  'Order #$shortId',
                                  style: AppConstants.monoStyle(
                                    fontSize: 12,
                                    color: AppConstants.secondary
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                              Text(
                                '₱${pending.totalAmount.toStringAsFixed(2)}',
                                style: AppConstants.monoStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Live countdown chip ─────────────────────
                        if (pending.deadline != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: _CountdownChip(
                              deadline: pending.deadline!,
                              totalWindow: _totalWindow,
                              now: _now,
                            ),
                          ),
                        const SizedBox(height: 18),
                        // ── What you're paying for ──────────────────
                        _itemsCard(),
                        const SizedBox(height: 16),
                        // ── Body copy ───────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            proofSubmitted
                                ? 'Your proof is with the store and they '
                                    'will confirm your order shortly. '
                                    'Follow it from the tracking screen — '
                                    'you can check out again once this one '
                                    'is resolved.'
                                : 'Your payment window is still open and '
                                    'your items are reserved. Finish paying '
                                    'to lock them in — or cancel to release '
                                    'them and check out again.',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.secondary
                                  .withValues(alpha: 0.7),
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // ── Actions ─────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SolePrimaryButton(
                            label: proofSubmitted
                                ? 'Track My Order'
                                : 'Complete Payment',
                            onPressed: _complete,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _dismiss,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppConstants.secondary
                                    .withValues(alpha: 0.75),
                                side: const BorderSide(
                                  color: AppConstants.borderGray,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppConstants.buttonRadius,
                                ),
                                textStyle: AppConstants.bodyStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text('Not Now'),
                            ),
                          ),
                        ),
                        // ── Destructive (de-emphasized, last) ───────
                        if (!proofSubmitted) _cancelRow(),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top handle ─────────────────────────────────────────────────────

  Widget _handleBar() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppConstants.borderGray,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _amberBadge() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: _amber.withValues(alpha: 0.3)),
      ),
      child: const Icon(
        Icons.schedule_rounded,
        size: 24,
        color: _amberRing,
      ),
    );
  }

  // ── "In this order" items card ─────────────────────────────────────

  Widget _itemsCard() {
    final pending = _pending;
    if (pending.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SoleCard(
          color: Colors.white,
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 20,
                color: AppConstants.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Items reserved for this order',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = pending.items;
    final primary = items.first;
    final rest = items.skip(1).toList();
    final showExpand = rest.isNotEmpty;
    // Remaining QUANTITY (not line count) so the toggle stays consistent
    // with the header count chip ("3 items" ↔ "View 2 more items").
    final restQuantity =
        rest.fold<int>(0, (sum, item) => sum + item.quantity);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SoleCard(
        color: Colors.white,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Text(
                    'In this order',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _countChip(pending.itemCount),
                ],
              ),
            ),
            // The primary item is always visible; expanding animates the
            // remaining lines in below it. AnimatedSize (not AnimatedCrossFade)
            // so the collapsed state keeps NO extra rows in the tree — no
            // hidden widgets, no offstage image loads.
            _itemRow(
              primary,
              large: true,
              showPlusBadge: showExpand && !_itemsExpanded,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _itemsExpanded
                  ? Column(
                      children: [
                        for (final item in rest) _itemRow(item, large: false),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            if (showExpand)
              _expandToggle(restQuantity),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _countChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.08),
        borderRadius: AppConstants.stadiumRadius,
      ),
      child: Text(
        '$count item${count == 1 ? '' : 's'}',
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppConstants.primary,
        ),
      ),
    );
  }

  Widget _itemRow(
    PendingGcashItem item, {
    required bool large,
    bool showPlusBadge = false,
  }) {
    final metaParts = <String>[
      if (item.size.isNotEmpty) 'EU ${item.size}',
      'Qty ${item.quantity}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          _thumbnail(item, size: large ? 60 : 44, showPlusBadge: showPlusBadge),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName.isEmpty ? 'Product' : item.productName,
                  style: AppConstants.bodyStyle(
                    fontSize: large ? 14 : 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  metaParts.join(' · '),
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₱${item.lineTotal.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: large ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: AppConstants.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(
    PendingGcashItem item, {
    required double size,
    bool showPlusBadge = false,
  }) {
    final imageUrl = item.imageUrl;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppConstants.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppConstants.borderGray.withValues(alpha: 0.4),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? Icon(
                      Icons.shopping_bag_outlined,
                      size: size * 0.42,
                      color: AppConstants.primary.withValues(alpha: 0.35),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.shopping_bag_outlined,
                        size: size * 0.42,
                        color: AppConstants.primary.withValues(alpha: 0.35),
                      ),
                    ),
            ),
          ),
          if (showPlusBadge)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: AppConstants.stadiumRadius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  '+1',
                  style: AppConstants.bodyStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _expandToggle(int extraQuantity) {
    final expanded = _itemsExpanded;
    return InkWell(
      onTap: () => setState(() => _itemsExpanded = !expanded),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppConstants.primary.withValues(alpha: 0.04),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded
                  ? 'Show fewer items'
                  : 'View $extraQuantity more item${extraQuantity == 1 ? '' : 's'}',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppConstants.primary,
            ),
          ],
        ),
      ),
    );
  }

  // ── Destructive action row (de-emphasized, below a divider) ────────

  Widget _cancelRow() {
    return Column(
      children: [
        const SizedBox(height: 14),
        Divider(
          height: 1,
          color: AppConstants.borderGray.withValues(alpha: 0.6),
          indent: 20,
          endIndent: 20,
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Center(
            child: TextButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Cancel Pending Order'),
              style: TextButton.styleFrom(
                foregroundColor: AppConstants.error,
                textStyle: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Live countdown chip: a small circular progress ring + ticking label.
/// Self-contained (own 1s timer) so only the chip repaints each second
/// instead of the whole sheet.
class _CountdownChip extends StatefulWidget {
  final DateTime deadline;
  final Duration totalWindow;
  final DateTime Function() now;

  const _CountdownChip({
    required this.deadline,
    required this.totalWindow,
    required this.now,
  });

  @override
  State<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<_CountdownChip> {
  Timer? _ticker;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateTimeLeft();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeLeft();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _updateTimeLeft() {
    final left = widget.deadline.difference(widget.now());
    final next = left.isNegative ? Duration.zero : left;
    if (next != _timeLeft && mounted) {
      setState(() => _timeLeft = next);
    }
  }

  bool get _expired => _timeLeft <= Duration.zero;

  double get _progress {
    final total = widget.totalWindow.inMilliseconds;
    if (total <= 0) return 0;
    return (_timeLeft.inMilliseconds / total).clamp(0.0, 1.0);
  }

  String get _label {
    if (_expired) return 'Window closed';
    final h = _timeLeft.inHours;
    final m = _timeLeft.inMinutes % 60;
    final s = _timeLeft.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m left';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s left';
    return '${s}s left';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _expired;
    final labelColor =
        expired ? AppConstants.secondary.withValues(alpha: 0.55) : _amberText;
    final chipColor = expired
        ? AppConstants.borderGray.withValues(alpha: 0.25)
        : _amber.withValues(alpha: 0.12);
    final borderColor = expired
        ? AppConstants.borderGray.withValues(alpha: 0.45)
        : _amber.withValues(alpha: 0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: AppConstants.stadiumRadius,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CustomPaint(
              painter: _CountdownRingPainter(
                progress: _progress,
                trackColor: expired
                    ? AppConstants.borderGray.withValues(alpha: 0.35)
                    : _amber.withValues(alpha: 0.22),
                ringColor: expired ? AppConstants.borderGray : _amberRing,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _label,
            style: AppConstants.monoStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small circular progress ring showing the fraction of the payment window
/// remaining. Sweeps from 12 o'clock clockwise with a rounded cap.
class _CountdownRingPainter extends CustomPainter {
  final double progress; // 0..1 remaining
  final Color trackColor;
  final Color ringColor;

  _CountdownRingPainter({
    required this.progress,
    required this.trackColor,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 2.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final ring = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.ringColor != ringColor;
}
