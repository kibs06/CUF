import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/sale_price.dart';

/// A single app-wide one-second ticker shared by every visible countdown.
///
/// Per-card `Timer.periodic`s are the classic grid-jank trap (N timers firing
/// on the same interval); this keeps the actual timer at exactly one per app.
/// Widgets subscribe while visible and unsubscribe in `dispose`, so the timer
/// starts lazily on the first subscription and stops as soon as the last
/// visible countdown scrolls away — no leaks on a long catalog grid.
///
/// Subscribers count *ticks* rather than re-reading the wall clock, which
/// keeps countdowns deterministic under `flutter_test`'s fake timers while
/// behaving identically in production.
class SaleCountdownTicker {
  SaleCountdownTicker._();

  static final SaleCountdownTicker instance = SaleCountdownTicker._();

  final ValueNotifier<int> _ticks = ValueNotifier<int>(0);
  Timer? _timer;
  int _listeners = 0;

  void addListener(VoidCallback listener) {
    _ticks.addListener(listener);
    _listeners++;
    if (_timer == null) {
      _timer =
          Timer.periodic(const Duration(seconds: 1), (_) => _ticks.value++);
    }
  }

  void removeListener(VoidCallback listener) {
    _ticks.removeListener(listener);
    _listeners--;
    if (_listeners <= 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Test hook: tear down the shared timer so a test can't leak a pending
  /// periodic timer into the next one.
  @visibleForTesting
  void debugReset() {
    _timer?.cancel();
    _timer = null;
    _listeners = 0;
    _ticks.value = 0;
  }
}

/// Watches one product's `sale_ends_at` and, the instant the sale expires,
/// rebuilds its subtree with a `now` that is *past* the end — so any
/// `isOnSale(product, now: now)` / `effectivePrice(product, now: now)` call
/// inside falls back to the regular non-sale rendering (tag, tape, countdown
/// and price line all together, with no stale frozen state).
///
/// This uses a single one-shot [Timer] per on-sale product (scheduled for the
/// exact expiry moment), NOT a per-second subscription — cards that are still
/// showing a countdown stay idle between the timer's schedule and its fire.
///
/// The [builder] receives the `now` to render with: `DateTime.now()` while the
/// sale is live, `saleEndsAt + 1s` once expired. Grid builders recycle element
/// States across products, so [didUpdateWidget] re-schedules (and un-expires)
/// whenever the product (or its `sale_ends_at`) changes.
class SaleEndWatcher extends StatefulWidget {
  /// The product being watched. Only `sale_ends_at` is read; a Map or a model
  /// both work (dynamic access, same as `SoleProductCard`'s product).
  final dynamic product;

  /// Builds the subtree with the `now` that should drive sale evaluation.
  final Widget Function(BuildContext context, DateTime now) builder;

  const SaleEndWatcher({super.key, required this.product, required this.builder});

  @override
  State<SaleEndWatcher> createState() => _SaleEndWatcherState();
}

class _SaleEndWatcherState extends State<SaleEndWatcher> {
  Timer? _expiryTimer;
  bool _expired = false;

  DateTime? get _saleEnd =>
      DateTime.tryParse(widget.product?['sale_ends_at']?.toString() ?? '');

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant SaleEndWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product != widget.product ||
        oldWidget.product?['sale_ends_at'] != widget.product?['sale_ends_at']) {
      // Recycled element for a different product (or the sale dates changed):
      // start over — a previous product's expiry must never leak over.
      _expired = false;
      _schedule();
    }
  }

  void _schedule() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final end = _saleEnd;
    if (end == null) return; // open-ended sale — nothing ever expires
    if (!isOnSale(widget.product)) return; // not active — nothing to fall back from
    final delay = end.difference(DateTime.now());
    if (delay <= Duration.zero) return; // already over — parent renders non-sale
    _expiryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _expired = true);
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cheap re-check: if the sale became ACTIVE after mount (e.g. its
    // `sale_starts_at` was in the future and the card rebuilt without the
    // product map changing, so didUpdateWidget didn't reschedule), make sure
    // the expiry timer gets created now. Guarded by the null timer — a sale
    // that has no end date stays null forever and the check just no-ops.
    if (!_expired && _expiryTimer == null && isOnSale(widget.product)) {
      _schedule();
    }
    final DateTime now;
    if (_expired) {
      final end = _saleEnd;
      // Strictly past the end so `isOnSale`'s `nowUtc.isAfter(end)` is true.
      now = (end ?? DateTime.now()).add(const Duration(seconds: 1));
    } else {
      now = DateTime.now();
    }
    return widget.builder(context, now);
  }
}

/// A countdown readout overlaid on a product image telling the customer how
/// much longer the sale lasts.
///
/// Formats:
///  * **> 24h remaining** — `"2 days left"` / `"1 day left"` (whole days,
///    floored: 47 hours shows "1 day left").
///  * **≤ 24h remaining** — a live ticking `HH:MM:SS` clock (real seconds,
///    tabular digits so nothing jitters). The format is re-evaluated on every
///    tick, so a countdown left open across the 24h boundary flips over on its
///    own.
///  * **< 1h remaining** — the band deepens to a richer golden yellow + a
///    slow, gentle pulse (static urgent color under reduced-motion settings).
///
/// The band is **yellow** (amber — the same accent as the app's "HOT DEALS"
/// badge) with dark brown text, and it always spans the full width of its
/// image edge-to-edge — it is the caller's job to pin it `left: 0, right: 0`
/// so there are no gaps beside it.
///
/// `saleEndsAt == null` (open-ended sale) renders **nothing at all** — no
/// invented urgency. The overlay also hides itself the instant its countdown
/// hits zero (the parent's [SaleEndWatcher] handles the full non-sale
/// fallback of tag/tape/price at the same moment).
class SaleCountdownOverlay extends StatefulWidget {
  /// The countdown target (`products.sale_ends_at`). NULL → renders nothing.
  final DateTime? saleEndsAt;

  /// Smaller text/padding for the Recently Viewed strip thumbnail.
  final bool compact;

  const SaleCountdownOverlay({
    super.key,
    required this.saleEndsAt,
    this.compact = false,
  });

  @override
  State<SaleCountdownOverlay> createState() => _SaleCountdownOverlayState();
}

class _SaleCountdownOverlayState extends State<SaleCountdownOverlay>
    with SingleTickerProviderStateMixin {
  // Yellow countdown band (amber — same accent as the app's "HOT DEALS"
  // badge): calm amber normally; a deeper golden yellow when <1h remains
  // (plus the slow pulse). Dark brown text keeps strong contrast.
  static const Color _calm = Color(0xFFFFC107);
  static const Color _urgent = Color(0xFFF0A500);

  Duration _remaining = Duration.zero;
  bool _subscribed = false;
  String? _lastDisplay;

  // Created eagerly (not `late final`) — a lazily-initialized controller that
  // is only ever touched in dispose() would try to look up ancestors on a
  // deactivated element and crash the widget tree.
  late final AnimationController _pulseController;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _syncSubscription();
  }

  @override
  void didUpdateWidget(covariant SaleCountdownOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.saleEndsAt != widget.saleEndsAt) _syncSubscription();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (motion != _reducedMotion) {
      _reducedMotion = motion;
      if (_reducedMotion) _pulseController.stop();
    }
  }

  void _syncSubscription() {
    final end = widget.saleEndsAt;
    if (end == null) {
      _remaining = Duration.zero;
      _lastDisplay = null;
      _unsubscribe();
      return;
    }
    _remaining = end.difference(DateTime.now());
    _lastDisplay = _displayFor(_remaining);
    if (_remaining <= Duration.zero) {
      // Sale already over at mount — nothing to count down.
      _unsubscribe();
      return;
    }
    if (!_subscribed) {
      SaleCountdownTicker.instance.addListener(_onTick);
      _subscribed = true;
    }
  }

  void _unsubscribe() {
    if (_subscribed) {
      SaleCountdownTicker.instance.removeListener(_onTick);
      _subscribed = false;
    }
  }

  void _onTick() {
    final end = widget.saleEndsAt;
    if (end == null) return;

    final ticked = _remaining - const Duration(seconds: 1);
    // Prefer the tick-driven countdown (deterministic in tests, smooth in
    // production), but never let it drift ahead of the wall clock — if the
    // app was backgrounded and timers paused, the countdown catches up.
    final wall = end.difference(DateTime.now());
    final remaining = ticked < wall ? ticked : wall;
    if (remaining == _remaining) return;
    _remaining = remaining;

    if (remaining <= Duration.zero) {
      // Reached zero: hide ourselves. The SaleEndWatcher parent flips the
      // whole card back to non-sale at the same moment.
      _lastDisplay = null;
      _unsubscribe();
      if (mounted) setState(() {});
      return;
    }

    final display = _displayFor(remaining);
    if (display == _lastDisplay) return;
    _lastDisplay = display;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _unsubscribe();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.saleEndsAt;
    if (end == null || _remaining <= Duration.zero) {
      return const SizedBox.shrink();
    }

    final bool clockMode = _remaining <= const Duration(hours: 24);
    final bool urgent = _remaining < const Duration(hours: 1);
    final String text =
        clockMode ? _formatClock(_remaining) : _formatDays(_remaining);
    final double fontSize = widget.compact ? 9.0 : 11.0;
    final double iconSize = widget.compact ? 9.0 : 12.0;

    // Idle/urgency pulse — a slow gentle breathing of the band, never a
    // fast flash; skipped entirely under reduced-motion settings.
    if (urgent && !_reducedMotion) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1.0; // land fully visible, no dim flash
    }

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.hourglass_bottom,
          size: iconSize,
          color: AppConstants.secondary.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 4),
        // scaleDown keeps long strings / large text scales from overflowing.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            key: const Key('sale-countdown-text'),
            style: AppConstants.monoStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
        ),
      ],
    );

    // One band style everywhere: full-width yellow, dark text. The parent
    // pins it left:0/right:0 so it always reaches both edges (no gaps).
    final Widget band = KeyedSubtree(
      key: const Key('sale-countdown-band'),
      child: Container(
        key: urgent ? const Key('sale-countdown-urgent') : null,
        width: double.infinity,
      padding: widget.compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // Subtle amber gradient: a hair lighter at the top edge so the band
        // reads as stuck onto the photo rather than a flat printed bar.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: urgent
              ? const [_urgent, Color(0xFFE09500)]
              : const [Color(0xFFFFD54F), _calm],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(child: content),
      ),
    );

    final Widget visible = urgent && !_reducedMotion
        ? AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Opacity(
              opacity: 0.78 + 0.22 * _pulseController.value,
              child: child,
            ),
            child: band,
          )
        : band;

    return IgnorePointer(
      child: Semantics(
        // Human-readable remaining time (minute resolution in clock mode), so
        // a screen reader never parses a raw HH:MM:SS digit by digit. The
        // label only changes ~once a minute — no per-second announcements.
        label: _semanticsFor(_remaining),
        child: ExcludeSemantics(child: visible),
      ),
    );
  }
}

// ── Formatting ────────────────────────────────────────────────────

String _pad2(int v) => v.toString().padLeft(2, '0');

/// Live `HH:MM:SS` (clock mode, ≤ 24h remaining).
String _formatClock(Duration remaining) {
  final h = remaining.inHours;
  final m = remaining.inMinutes % 60;
  final s = remaining.inSeconds % 60;
  return '${_pad2(h)}:${_pad2(m)}:${_pad2(s)}';
}

/// Whole days, floored ("2 days left" / "1 day left").
String _formatDays(Duration remaining) {
  final d = remaining.inDays;
  return '$d ${d == 1 ? 'day' : 'days'} left';
}

/// The visible text for a remaining duration, or null when there is nothing
/// to show (expired). Returned value is what gates rebuilds — in days mode the
/// text is stable for ~a day, so those cards effectively never re-render.
String? _displayFor(Duration remaining) {
  if (remaining <= Duration.zero) return null;
  return remaining > const Duration(hours: 24)
      ? _formatDays(remaining)
      : _formatClock(remaining);
}

String _semanticsFor(Duration remaining) {
  if (remaining > const Duration(hours: 24)) {
    final d = remaining.inDays;
    return 'Sale ends in $d ${d == 1 ? 'day' : 'days'}';
  }
  final h = remaining.inHours;
  final m = remaining.inMinutes % 60;
  return 'Sale ends in $h ${h == 1 ? 'hour' : 'hours'} and $m '
      '${m == 1 ? 'minute' : 'minutes'}';
}
