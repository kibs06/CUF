import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A small FREE pickup hold (ANQUI item 14): 1–2 units of ONE size of ONE
/// product, held out of stock for 24 hours, no deposit and no approval.
///
/// ⚠️ NOT a [BulkReservation]. Those are deposit-gated reseller holds with
/// an approval step; these are walk-in holds that start holding stock the
/// moment they are created. The two share only the `inventory` hold
/// mechanism and the `reservations` notification category — never mix their
/// statuses or their RPCs.
///
/// Server side: `20260915170000_add_pickup_reservations.sql`.
class PickupReservation {
  /// The cap on a single hold — mirrors
  /// `public.pickup_reservation_max_quantity()` in SQL, asserted by
  /// `test/services/pickup_reservation_contract_test.dart`. Above it the
  /// customer is pointed at the bulk (reseller) flow instead.
  static const int maxQuantity = 2;

  /// Base length of a hold, in hours — mirrors
  /// `public.pickup_reservation_hold_hours()`. Pinned by the contract test.
  static const int holdHours = 24;

  /// How many times a live hold may be extended — mirrors
  /// `public.pickup_reservation_max_extensions()`.
  static const int maxExtensions = 1;

  /// Hours one extension buys — mirrors
  /// `public.pickup_reservation_extension_hours()`.
  static const int extensionHours = 24;

  /// The longest any hold can run: the base window plus every allowed
  /// extension. The server enforces this as a table CHECK, so the app must not
  /// promise more than it does.
  static const int maxHoldHours = holdHours * (1 + maxExtensions);

  final String id;
  final String customerId;
  final String storeId;
  final String productId;
  final String size;
  final int quantity;
  final int reservedStock;

  /// 'active' | 'fulfilled' | 'cancelled' | 'expired'
  final String status;
  final DateTime? pickupDeadline;
  final DateTime? createdAt;
  final DateTime? fulfilledAt;
  final String? fulfilledOrderId;
  final DateTime? reminderSentAt;

  /// How many times this hold has already been extended (`0..maxExtensions`).
  final int extensionCount;

  // Joined display fields.
  final String productName;
  final String? productImage;
  final String storeName;
  final String? customerName;

  const PickupReservation({
    required this.id,
    required this.customerId,
    required this.storeId,
    required this.productId,
    required this.size,
    required this.quantity,
    this.reservedStock = 0,
    required this.status,
    this.pickupDeadline,
    this.createdAt,
    this.fulfilledAt,
    this.fulfilledOrderId,
    this.reminderSentAt,
    this.extensionCount = 0,
    this.productName = '',
    this.productImage,
    this.storeName = '',
    this.customerName,
  });

  bool get isActive => status == 'active';
  bool get isFulfilled => status == 'fulfilled';
  bool get isTerminal =>
      status == 'fulfilled' || status == 'cancelled' || status == 'expired';

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'Holding for pickup';
      case 'fulfilled':
        return 'Collected';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
    }
    return status;
  }

  /// Time left before the hold is released. Negative once lapsed (the
  /// opportunistic sweep will expire it on the next screen load).
  Duration timeLeftFrom(DateTime now) {
    final deadline = pickupDeadline;
    if (deadline == null) return Duration.zero;
    return deadline.difference(now);
  }

  /// True when the hold lapses within [threshold] — drives the "expiring
  /// soon" styling. Mirrors the server's T-2h reminder window.
  bool isExpiringSoonAt(DateTime now, {Duration threshold = const Duration(hours: 2)}) {
    if (!isActive) return false;
    final left = timeLeftFrom(now);
    return left > Duration.zero && left <= threshold;
  }

  /// Past its deadline but not yet swept.
  bool hasLapsedAt(DateTime now) =>
      isActive && pickupDeadline != null && timeLeftFrom(now) <= Duration.zero;

  /// Extensions still available on this hold.
  int get extensionsLeft =>
      (maxExtensions - extensionCount).clamp(0, maxExtensions);

  /// May the customer still ask for more time?
  ///
  /// Every one of these is a rule the server enforces, so offering the action
  /// when it cannot succeed would only produce a rejection:
  ///
  /// * it has to still be **live** — once the deadline has passed the sweep may
  ///   release the stock at any moment, so extending would promise stock nobody
  ///   can guarantee;
  /// * the deadline has to be **known** — "before it expires" is unanswerable
  ///   for a malformed row, and the server's column is NOT NULL anyway;
  /// * the cap has to be unused.
  bool canExtendAt(DateTime now) =>
      isActive &&
      pickupDeadline != null &&
      !hasLapsedAt(now) &&
      extensionsLeft > 0;

  /// 'Extend 24h', or null when there is no time left to ask for.
  String? get extendActionLabel =>
      extensionsLeft > 0 ? 'Extend ${extensionHours}h' : null;

  /// The line under the countdown: what extending means for this store, and
  /// whether it has already been used.
  String? get extensionNote {
    if (!isActive) return null;
    if (extensionCount > 0) {
      return 'Extended — a hold cannot be extended twice '
          '(max ${maxHoldHours}h).';
    }
    return 'Need longer? Extend once for ${extensionHours}h, up to '
        '${maxHoldHours}h total.';
  }

  /// '5h 12m left' / 'expires in under a minute' / 'expired'.
  String countdownLabelAt(DateTime now) {
    if (!isActive) return statusLabel;
    // `pickup_deadline` is NOT NULL in SQL, so this only happens for a
    // malformed row — but reporting "Expired" then would tell a customer
    // their hold is gone when nothing says it is.
    if (pickupDeadline == null) return 'Deadline unavailable';
    final left = timeLeftFrom(now);
    if (left <= Duration.zero) return 'Expired';
    if (left.inMinutes < 1) return 'Expires in under a minute';
    if (left.inHours < 1) return '${left.inMinutes}m left';
    return '${left.inHours}h ${left.inMinutes % 60}m left';
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  factory PickupReservation.fromJson(Map<String, dynamic> json) {
    // Joined product fields — the customer-side query nests
    // products(name, stores(name), product_images(...)); the seller-side
    // nests products(name) + profiles(name).
    String productName = '';
    String? image;
    String storeName = '';
    String? customerName;

    final product = json['products'];
    if (product is Map) {
      productName = product['name']?.toString() ?? '';
      final store = product['stores'];
      if (store is Map) storeName = store['name']?.toString() ?? '';
      final images = product['product_images'];
      if (images is List && images.isNotEmpty) {
        final sorted = images.whereType<Map>().toList()
          ..sort((a, b) => ((a['display_order'] as num?)?.toInt() ?? 0)
              .compareTo((b['display_order'] as num?)?.toInt() ?? 0));
        image = sorted.first['image_url']?.toString();
      }
    }
    final profile = json['profiles'];
    if (profile is Map) customerName = profile['name']?.toString();

    return PickupReservation(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      reservedStock: (json['reserved_stock'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'active',
      pickupDeadline: _parseDate(json['pickup_deadline']),
      createdAt: _parseDate(json['created_at']),
      fulfilledAt: _parseDate(json['fulfilled_at']),
      fulfilledOrderId: json['fulfilled_order_id']?.toString(),
      reminderSentAt: _parseDate(json['reminder_sent_at']),
      extensionCount: (json['extension_count'] as num?)?.toInt() ?? 0,
      productName: productName,
      productImage: image,
      storeName: storeName,
      customerName: customerName,
    );
  }
}

/// The dashboard's pickup numbers, derived from a single light query so the
/// headline count and the lapsing badge always agree.
class PickupStoreStats {
  /// Live holds (`status = 'active'`).
  final int active;

  /// Holds whose stock returns within the T-2h window, including any already
  /// past their deadline that the sweep has not reached yet.
  final int lapsing;
  final int returningUnits;

  const PickupStoreStats({
    this.active = 0,
    this.lapsing = 0,
    this.returningUnits = 0,
  });
}

/// A store's pickup holds at a glance — what is off the shelf right now, and
/// (the part a seller actually needs *ahead of time*) which holds are about to
/// lapse and how much stock that puts back.
///
/// Pure arithmetic over rows already in hand, so it is unit-testable and can be
/// computed from either the full reservations (the seller screen) or a light
/// `quantity`/`pickup_deadline` select (the dashboard).
class PickupHoldSummary {
  /// Every `active` hold, whether or not it is close to lapsing.
  final int activeHolds;
  final int activeUnits;

  /// Still inside their 24 hours but inside the last [window] — the same
  /// 2-hour window the server's T-2h reminder uses, so the screen and the
  /// notification agree about what "about to lapse" means.
  final int lapsingHolds;
  final int lapsingUnits;
  final int lapsedHolds;
  final int lapsedUnits;

  const PickupHoldSummary({
    this.activeHolds = 0,
    this.activeUnits = 0,
    this.lapsingHolds = 0,
    this.lapsingUnits = 0,
    this.lapsedHolds = 0,
    this.lapsedUnits = 0,
  });

  static const Duration window = Duration(hours: 2);

  /// Units that go back on the shelf unless someone collects them: everything
  /// already past its deadline (the sweep just has not run yet) plus everything
  /// lapsing inside [window].
  int get returningUnits => lapsingUnits + lapsedUnits;
  int get returningHolds => lapsingHolds + lapsedHolds;

  bool get isEmpty => activeHolds == 0;
  bool get hasReturning => returningUnits > 0;

  /// '3 holds · 4 pairs held' — what is off the shelf now.
  String get heldLabel =>
      '$activeHolds ${activeHolds == 1 ? 'hold' : 'holds'} · '
      '$activeUnits ${activeUnits == 1 ? 'pair' : 'pairs'} held';

  /// '2 pairs back within 2h' — null when nothing is about to come back, so the
  /// caller renders nothing rather than a zero.
  String? get returningLabel {
    if (!hasReturning) return null;
    return '$returningUnits ${returningUnits == 1 ? 'pair' : 'pairs'} back '
        'within ${window.inHours}h';
  }

  /// '1 lapsed — releases on the next load' — null when none.
  String? get lapsedLabel {
    if (lapsedHolds == 0) return null;
    return '$lapsedHolds lapsed — releases on the next load';
  }

  factory PickupHoldSummary.from(
    Iterable<PickupReservation> items,
    DateTime now,
  ) =>
      PickupHoldSummary.fromRows(
        items.map((r) => <String, dynamic>{
          'status': r.status,
          'quantity': r.quantity,
          'pickup_deadline': r.pickupDeadline?.toIso8601String(),
        }),
        now,
      );

  /// Works on a partial select too, so the dashboard does not have to fetch the
  /// joins the full screen needs.
  factory PickupHoldSummary.fromRows(
    Iterable<Map<String, dynamic>> rows,
    DateTime now,
  ) {
    var activeHolds = 0, activeUnits = 0;
    var lapsingHolds = 0, lapsingUnits = 0;
    var lapsedHolds = 0, lapsedUnits = 0;

    for (final row in rows) {
      if ((row['status']?.toString() ?? 'active') != 'active') continue;
      // A hold is always at least one unit (SQL CHECK quantity > 0), so a
      // missing count reads as 1: under-reporting stock that is about to come
      // back is the worse error, because nobody goes looking for it.
      final qty = (row['quantity'] as num?)?.toInt() ?? 1;
      final deadline = row['pickup_deadline'] == null
          ? null
          : DateTime.tryParse(row['pickup_deadline'].toString())?.toLocal();

      activeHolds++;
      activeUnits += qty;

      if (deadline == null) continue; // unknown deadline: held, not lapsing
      final left = deadline.difference(now);
      if (left <= Duration.zero) {
        lapsedHolds++;
        lapsedUnits += qty;
      } else if (left <= window) {
        lapsingHolds++;
        lapsingUnits += qty;
      }
    }

    return PickupHoldSummary(
      activeHolds: activeHolds,
      activeUnits: activeUnits,
      lapsingHolds: lapsingHolds,
      lapsingUnits: lapsingUnits,
      lapsedHolds: lapsedHolds,
      lapsedUnits: lapsedUnits,
    );
  }
}

/// Client for the pickup reservation RPCs. Deliberately a SEPARATE service
/// from `ReservationService` (bulk holds): the two flows have different
/// rules, different statuses and different tables, and mixing them is how
/// a deposit step ends up in a free hold.
class PickupReservationService {
  static final PickupReservationService instance = PickupReservationService();

  final SupabaseClient _client;

  PickupReservationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Customer: hold [quantity] (1..[PickupReservation.maxQuantity]) units of
  /// [size] for 24 hours. Stock is held immediately, server-side.
  ///
  /// Throws a `PostgrestException` whose message maps through
  /// [friendlyPickupReservationError].
  Future<String> request({
    required String productId,
    required String size,
    required int quantity,
  }) async {
    final id = await _client.rpc('request_pickup_reservation', params: {
      'p_product_id': productId,
      'p_size': size,
      'p_quantity': quantity,
    });
    return id.toString();
  }

  /// Customer (their own) or the store owner: release the hold early.
  Future<void> cancel(String reservationId) async {
    await _client.rpc('cancel_pickup_reservation',
        params: {'p_reservation_id': reservationId});
  }

  /// Store owner: the customer arrived. Records the pickup as a POS sale
  /// and returns the new order id.
  Future<String?> fulfill(String reservationId, {
    String paymentMethod = 'cash',
  }) async {
    final orderId = await _client.rpc('fulfill_pickup_reservation', params: {
      'p_reservation_id': reservationId,
      'p_payment_method': paymentMethod,
    });
    return orderId?.toString();
  }

  /// Customer: my holds, newest first. The seller's side of each row comes
  /// along for display (store name for "pick up at").
  Future<List<PickupReservation>> fetchMine() async {
    final rows = await _client
        .from('pickup_reservations')
        .select('*, products(name, stores(name), product_images(image_url, display_order))')
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map<PickupReservation>(
            (r) => PickupReservation.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Store owner: every hold for [storeId], newest first.
  Future<List<PickupReservation>> fetchForStore(String storeId) async {
    final rows = await _client
        .from('pickup_reservations')
        .select('*, products(name), profiles(name)')
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map<PickupReservation>(
            (r) => PickupReservation.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Store owner: the dashboard's one-liner — how many holds are live, and how
  /// many are about to hand their stock back.
  ///
  /// A light select (no joins) because the dashboard only needs counts, and ONE
  /// query so the headline number and the "lapsing" badge can never come from
  /// two different snapshots.
  Future<PickupStoreStats> fetchStoreStats(String storeId) async {
    final rows = await _client
        .from('pickup_reservations')
        .select('quantity, pickup_deadline, status')
        .eq('store_id', storeId)
        .eq('status', 'active');
    final summary = PickupHoldSummary.fromRows(
      (rows as List).map((r) => Map<String, dynamic>.from(r as Map)),
      DateTime.now(),
    );
    return PickupStoreStats(
      active: summary.activeHolds,
      lapsing: summary.returningHolds,
      returningUnits: summary.returningUnits,
    );
  }

  /// Customer: ask for more time on a live hold.
  ///
  /// Only the customer may extend (a store extending its own hold is a bulk
  /// reservation), only before the deadline passes, and only up to
  /// [PickupReservation.maxExtensions] times — the server enforces all three,
  /// and the CHECK constraint on `pickup_deadline` caps the total window at
  /// [PickupReservation.maxHoldHours] hours no matter what.
  ///
  /// Returns the NEW deadline (local) when the server reports one, so the caller
  /// can confirm the new time without assuming the extension length.
  Future<DateTime?> extend(String reservationId) async {
    final result = await _client.rpc(
      'extend_pickup_reservation',
      params: {'p_reservation_id': reservationId},
    );
    final raw = result?.toString();
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  /// Opportunistic expiry sweep (there is no pg_cron in this database, so
  /// the app runs it on load — same pattern as the bulk reservations and
  /// the GCash expiry). Never throws: any later call finishes the job.
  Future<int> expireStale() async {
    try {
      final n = await _client.rpc('expire_pickup_reservations');
      return (n as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('expire_pickup_reservations sweep failed: $e');
      return 0;
    }
  }

  /// Opportunistic T-2h reminder sweep. Exactly-once server-side (guarded by
  /// `reminder_sent_at`), so calling it on every load cannot spam anyone.
  Future<int> sendReminders() async {
    try {
      final n = await _client.rpc('send_pickup_reservation_reminders');
      return (n as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('send_pickup_reservation_reminders sweep failed: $e');
      return 0;
    }
  }
}

/// Shown for BOTH the RPC's serial duplicate check and the partial unique
/// index that catches a concurrent double-submit (`23505`).
const String kPickupAlreadyHoldingCopy =
    'You already have an active pickup hold on this size. Cancel it first, '
    'or wait for it to expire.';

/// Maps the pickup RPCs' stable error codes to customer-readable copy.
///
/// The codes are raised as `P0001` with a short code at the front of the
/// message (see the migration), so this matches on prefix rather than on an
/// exact string — the numbers in `INSUFFICIENT_STOCK (3) < 4` vary.
String friendlyPickupReservationError(Object error) {
  var raw = error.toString();
  if (error is PostgrestException) raw = error.message;

  if (raw.contains('NOT_AUTHENTICATED')) {
    return 'Please sign in again to reserve for pickup.';
  }
  // A CONCURRENT double-submit never reaches the RPC's own
  // `RESERVATION_ALREADY_EXISTS` check — both callers pass it, and the loser
  // is stopped by the partial unique index instead, so it arrives as 23505.
  // It is the same situation, so it gets the same words (one constant, so the
  // two paths cannot drift apart).
  if ((error is PostgrestException && error.code == '23505') ||
      raw.contains('23505')) {
    return kPickupAlreadyHoldingCopy;
  }
  if (raw.contains('ABOVE_PICKUP_CAP')) {
    return 'Pickup holds are limited to ${PickupReservation.maxQuantity} pairs. '
        'For more than that, ask the store for a bulk reservation.';
  }
  if (raw.contains('RESERVATION_ALREADY_EXISTS')) {
    return kPickupAlreadyHoldingCopy;
  }
  if (raw.contains('EXTENSION_LIMIT_REACHED')) {
    return 'This hold has already been extended, and a store cannot be asked '
        'to wait longer than ${PickupReservation.maxHoldHours} hours. Reserve '
        'again once it lapses.';
  }
  if (raw.contains('HOLD_LAPSED')) {
    return 'This hold has already run out of time — nothing can be held for '
        'you on it now.';
  }
  if (raw.contains('INSUFFICIENT_STOCK')) {
    return 'That size no longer has enough stock. Please pick another size '
        'or quantity.';
  }
  if (raw.contains('SIZE_REQUIRED')) {
    return 'Choose a size to reserve for pickup.';
  }
  if (raw.contains('PRODUCT_NOT_FOUND')) {
    return 'This product is no longer available.';
  }
  if (raw.contains('INVALID_QUANTITY')) {
    return 'Choose at least one pair.';
  }
  if (raw.contains('INVALID_PAYMENT_METHOD')) {
    return 'Choose how the customer paid — cash or GCash.';
  }
  if (raw.contains('FORBIDDEN')) {
    return 'You cannot change this pickup reservation.';
  }
  if (raw.contains('ALREADY_RESOLVED')) {
    return 'This pickup reservation was already completed, cancelled or '
        'expired. Pull to refresh.';
  }
  if (raw.contains('NOT_FOUND')) {
    return 'That pickup reservation no longer exists.';
  }
  return 'Something went wrong with the pickup reservation. Please try again.';
}
