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

  /// How many times a live hold may be extended by the CUSTOMER — mirrors
  /// `public.pickup_reservation_max_extensions()`.
  static const int maxExtensions = 1;

  /// How many GOODWILL extensions the STORE may grant — mirrors
  /// `public.pickup_reservation_max_store_extensions()`.
  ///
  /// A separate budget from [maxExtensions] on purpose: a store being generous
  /// must not consume the customer's allowance, and a customer using theirs must
  /// not stop a store from being generous.
  static const int maxStoreExtensions = 1;

  /// Hours one extension buys — mirrors
  /// `public.pickup_reservation_extension_hours()`.
  static const int extensionHours = 24;

  /// Hours one STORE goodwill grant buys — mirrors
  /// `public.pickup_reservation_store_extension_hours()`.
  static const int storeExtensionHours = 24;

  /// The longest a hold can run because of the CUSTOMER alone: the base window
  /// plus their own extension. This is what customer-facing copy quotes, since
  /// a store's goodwill is a favour rather than something to count on.
  static const int maxHoldHours = holdHours * (1 + maxExtensions);

  /// The ABSOLUTE ceiling on a hold: the base window plus EVERY budget, which is
  /// what the server's table CHECK enforces
  /// (`pickup_reservation_max_window_hours`). Nothing — not a customer, not a
  /// store, not a hand-written UPDATE — can push a hold past this.
  static const int maxWindowHours =
      holdHours * (1 + maxExtensions + maxStoreExtensions);

  /// The symbols a pickup code is drawn from — mirrors
  /// `public.pickup_code_alphabet()`.
  ///
  /// I, L, O, U, 0 and 1 are absent on purpose: a code is read off a phone
  /// across a counter and frequently spoken aloud, and those are the six that
  /// turn into each other. The set is also the column CHECK's character class,
  /// and the contract test pins all three copies (this constant, the SQL
  /// function, the CHECK) against each other.
  static const String codeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Characters in a pickup code — mirrors `public.pickup_code_length()`.
  static const int codeLength = 6;

  /// What the counter should accept, reduced to the stored form: upper case,
  /// separators gone. Mirrors `public.normalize_pickup_code()` — and copies its
  /// deliberate refusal to substitute look-alikes, so what the app sends the
  /// server is exactly what the seller typed.
  static String normalizeCode(String code) => code
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  final String id;
  final String customerId;
  final String storeId;
  final String productId;
  final String size;

  /// The variant colour the customer is holding, as the seller named it (null
  /// on colourless products and on rows created before the column existed).
  ///
  /// Informational only: the hold is keyed on `(product_id, size)` — see
  /// `20260917120000_add_pickup_reservation_color.sql` — because inventory
  /// itself is colour-blind. It exists so the counter knows WHICH pair to pull
  /// off the shelf.
  final String? color;
  final int quantity;
  final int reservedStock;

  /// 'active' | 'fulfilled' | 'cancelled' | 'expired'
  final String status;
  final DateTime? pickupDeadline;
  final DateTime? createdAt;
  final DateTime? fulfilledAt;
  final String? fulfilledOrderId;
  final DateTime? reminderSentAt;

  /// The code the customer reads out at the counter and the seller types in
  /// (`public.pickup_code_*`). Null only for a row that predates the column and
  /// has not been backfilled — the app renders nothing rather than a placeholder
  /// in that case, since a made-up code is worse than no code.
  final String? pickupCode;

  /// How many times this hold has already been extended (`0..maxExtensions`).
  final int extensionCount;

  /// Goodwill extensions the STORE has granted (`0..maxStoreExtensions`),
  /// counted separately from [extensionCount] — the trail for each one (who,
  /// when, and why) lives in `pickup_reservation_extension_grants`.
  final int storeExtensionCount;

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
    this.color,
    required this.quantity,
    this.reservedStock = 0,
    required this.status,
    this.pickupDeadline,
    this.createdAt,
    this.fulfilledAt,
    this.fulfilledOrderId,
    this.reminderSentAt,
    this.pickupCode,
    this.extensionCount = 0,
    this.storeExtensionCount = 0,
    this.productName = '',
    this.productImage,
    this.storeName = '',
    this.customerName,
  });

  bool get isActive => status == 'active';
  bool get isFulfilled => status == 'fulfilled';

  /// The code, grouped for reading aloud and for typing: `4F7K2Q` becomes
  /// `4F7-K2Q`. Presentation only — the server stores and accepts the ungrouped
  /// form, and [normalizeCode] strips the dash straight back out.
  String? get pickupCodeLabel {
    final code = pickupCode;
    if (code == null || code.length != codeLength) return code;
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }
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

  /// Goodwill extensions the store still has available on this hold.
  int get storeExtensionsLeft =>
      (maxStoreExtensions - storeExtensionCount).clamp(0, maxStoreExtensions);

  /// True when the store has already been generous on this hold.
  bool get storeExtended => storeExtensionCount > 0;

  /// May the STORE still give this hold more time?
  ///
  /// The same gates `grant_pickup_extension` enforces, so the seller UI hides
  /// the action rather than offering one the server will refuse: the hold has to
  /// be live (not lapsed — after the deadline the units may be released at any
  /// moment) and the store's own budget has to be unspent.
  bool canBeGrantedAt(DateTime now) =>
      isActive &&
      pickupDeadline != null &&
      !hasLapsedAt(now) &&
      storeExtensionsLeft > 0;

  /// 'Give 24h', or null when the store's budget for this hold is spent.
  String? get grantActionLabel =>
      storeExtensionsLeft > 0 ? 'Give ${storeExtensionHours}h' : null;

  /// The line under the countdown: what extending means for this store, and
  /// whether it has already been used.
  String? get extensionNote {
    if (!isActive) return null;
    // The store's goodwill is stated in its own words, and never as a limit the
    // customer could rely on — which is why the customer-only copy below still
    // quotes [maxHoldHours] rather than the absolute [maxWindowHours].
    if (storeExtended && extensionCount > 0) {
      return 'Extended by you and by the store — the longest a hold can run is '
          '${maxWindowHours}h.';
    }
    if (storeExtended) {
      return 'The store added ${storeExtensionHours}h for you as a goodwill '
          'extension.';
    }
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

  factory PickupReservation.fromJson(Map<String, dynamic> json) {
    // Joined product fields — the customer-side query nests
    // products(name, stores(name), product_images(...)); the seller-side
    // nests products(name) + profiles(full_name).
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
    // `full_name`, not `name`: asking PostgREST for `profiles.name` fails the
    // whole query (42703) — the column is `full_name`.
    if (profile is Map) customerName = profile['full_name']?.toString();

    return PickupReservation(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      color: _parseColor(json['color']),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      reservedStock: (json['reserved_stock'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'active',
      pickupDeadline: _parseDate(json['pickup_deadline']),
      createdAt: _parseDate(json['created_at']),
      fulfilledAt: _parseDate(json['fulfilled_at']),
      fulfilledOrderId: json['fulfilled_order_id']?.toString(),
      reminderSentAt: _parseDate(json['reminder_sent_at']),
      pickupCode: json['pickup_code']?.toString(),
      extensionCount: (json['extension_count'] as num?)?.toInt() ?? 0,
      storeExtensionCount:
          (json['store_extension_count'] as num?)?.toInt() ?? 0,
      productName: productName,
      productImage: image,
      storeName: storeName,
      customerName: customerName,
    );
  }
}

/// Postgres timestamps arrive as UTC strings with an offset; the app works in
/// local time everywhere it shows one. Top-level (rather than private to
/// `PickupReservation`) because the goodwill trail parses dates too, and two
/// parsers is how one of them ends up wrong.
DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// A variant colour name from the row: trimmed, and null when the column is
/// absent (a select that predates `color`), null, or blank — so the UI hides
/// the line instead of rendering an empty "".
String? _parseColor(dynamic v) {
  final value = v?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

/// One row of the goodwill trail (`pickup_reservation_extension_grants`): the
/// store gave a hold more time, and here is exactly what was given and why.
///
/// The customer sees these on their own holds, the store sees them for its own
/// store — both through RLS, not through a filter the app applies.
class PickupExtensionGrant {
  final String id;
  final String reservationId;
  final String customerId;
  final String storeId;

  /// The seller who granted it. Null once that account is deleted — the record
  /// of the favour is kept, without the name.
  final String? grantedBy;
  final DateTime? previousDeadline;
  final DateTime? newDeadline;
  final int hoursGranted;
  final String reason;
  final DateTime? createdAt;

  /// Display names, carried only by the customer's trail query (which embeds the
  /// hold and, through it, the product and its store).
  ///
  /// They are here rather than looked up from the loaded holds because the
  /// HISTORY exists precisely for grants the hold list may no longer show: a
  /// hold that was collected, cancelled or pushed past the `LIMIT` of the
  /// customer's fetch is still a favour that happened and still has a reason.
  /// Empty strings on the flat selects, where the row is rendered beside a hold
  /// that already knows its own names.
  final String storeName;
  final String productName;
  final String size;

  const PickupExtensionGrant({
    required this.id,
    required this.reservationId,
    required this.customerId,
    required this.storeId,
    this.grantedBy,
    this.previousDeadline,
    this.newDeadline,
    this.hoursGranted = 0,
    this.reason = '',
    this.createdAt,
    this.storeName = '',
    this.productName = '',
    this.size = '',
  });

  factory PickupExtensionGrant.fromJson(Map<String, dynamic> json) {
    // The embedded hold, when the caller asked for it. Every level is probed
    // rather than assumed: the same model is built from the FLAT seller-side
    // select, which has no `pickup_reservations` key at all, and a nested cast
    // there would throw inside a list mapping and take the whole trail down.
    final hold = _nest(json['pickup_reservations']);
    final product = _nest(hold['products']);
    final store = _nest(product['stores']);

    return PickupExtensionGrant(
      id: json['id']?.toString() ?? '',
      reservationId: json['reservation_id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      grantedBy: json['granted_by']?.toString(),
      previousDeadline: _parseDate(json['previous_deadline']),
      newDeadline: _parseDate(json['new_deadline']),
      hoursGranted: (json['hours_granted'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString() ?? '',
      createdAt: _parseDate(json['created_at']),
      storeName: store['name']?.toString() ?? '',
      productName: product['name']?.toString() ?? '',
      size: hold['size']?.toString() ?? '',
    );
  }
}

/// One level of a PostgREST embed as a map, or an empty map when the level is
/// absent (flat select) or not an object (a `null` to-one join). One helper
/// instead of four nested ternaries, so the defensive shape is uniform.
Map<String, dynamic> _nest(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

/// 'Mon 16, 17:30' in LOCAL time — deliberately the same shape the server
/// writes into its pickup notifications (`Mon DD, HH24:MI`), so the seller's
/// confirmation and the customer's notification about the same deadline read
/// alike. Written by hand rather than pulled from `intl` because this is the
/// only format the pickup flow needs.
String formatPickupDeadline(DateTime deadline) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final d = deadline.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, $hh:$mm';
}

/// What the customer's goodwill history says in one line: how many times a store
/// chose to give them more time, how much time that amounts to, and how many
/// stores did it.
///
/// Pure arithmetic over rows already in hand (the same shape as
/// `PickupHoldSummary`), so it is unit-testable and the header cannot disagree
/// with the list it sits above — both are built from the same list.
class PickupGoodwillSummary {
  final int grants;
  final int hours;

  /// Distinct stores, counted by id: two grants from the same store is one store
  /// being generous twice, not two stores.
  final int stores;

  const PickupGoodwillSummary({
    this.grants = 0,
    this.hours = 0,
    this.stores = 0,
  });

  factory PickupGoodwillSummary.of(List<PickupExtensionGrant> grants) {
    final storeIds = <String>{};
    var hours = 0;
    for (final grant in grants) {
      hours += grant.hoursGranted;
      if (grant.storeId.isNotEmpty) storeIds.add(grant.storeId);
    }
    return PickupGoodwillSummary(
      grants: grants.length,
      hours: hours,
      stores: storeIds.length,
    );
  }

  bool get isEmpty => grants == 0;
}

/// The most recent grant per reservation, from a trail fetched newest-first.
///
/// Pure and separate from the fetch so the "which one explains this deadline?"
/// rule is testable without a database: the FIRST row seen for a reservation
/// wins, which is only correct because the query orders by `created_at DESC`.
/// (A trail that arrives oldest-first would silently surface the wrong reason.)
Map<String, PickupExtensionGrant> latestGrantByReservation(
    List<PickupExtensionGrant> grants) {
  final latest = <String, PickupExtensionGrant>{};
  for (final grant in grants) {
    latest.putIfAbsent(grant.reservationId, () => grant);
  }
  return latest;
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
    String? color,
  }) async {
    final params = <String, dynamic>{
      'p_product_id': productId,
      'p_size': size,
      'p_quantity': quantity,
    };
    final hasColor = color != null && color.isNotEmpty;
    if (hasColor) params['p_color'] = color;

    try {
      final id = await _client.rpc('request_pickup_reservation', params: params);
      return id.toString();
    } catch (e) {
      // `p_color` arrives with 20260917120000_add_pickup_reservation_color.sql.
      // On a database that has not had it applied yet, the call fails with
      // "function not found" — and the hold itself must not fail over a
      // label, so retry without it. The colour is informational; the hold is
      // keyed on (product_id, size) either way.
      if (!hasColor) rethrow;
      debugPrint(
        '[PickupReservationService] p_color rejected ($e) — retrying without it',
      );
      final id = await _client.rpc('request_pickup_reservation', params: {
        'p_product_id': productId,
        'p_size': size,
        'p_quantity': quantity,
      });
      return id.toString();
    }
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

  /// Seller: the id of the hold a counter code belongs to, or a thrown error if
  /// nothing for THIS store matches it.
  ///
  /// The scoping is the server's (`find_pickup_reservation_by_code` joins through
  /// `stores.owner_id = auth.uid()`), deliberately — a code is not a secret, so
  /// whoever may look one up is the security boundary, and it does not belong in
  /// client code. Another store's code comes back as the same `NOT_FOUND` as a
  /// code that does not exist, so the app cannot tell them apart either.
  Future<String> resolveCode(String code) async {
    final id = await _client.rpc('find_pickup_reservation_by_code', params: {
      'p_code': PickupReservation.normalizeCode(code),
    });
    final resolved = id?.toString();
    if (resolved == null || resolved.isEmpty) {
      throw Exception('NOT_FOUND — no pickup hold for your store matches that code');
    }
    return resolved;
  }

  /// One hold by id — used after a code resolves, rather than hunting the loaded
  /// list, because the store's list is windowed and the hold a customer is
  /// standing in front of must never be "not in view".
  Future<PickupReservation?> fetchById(String reservationId) async {
    final row = await _client
        .from('pickup_reservations')
        .select('*, products(name), profiles(full_name)')
        .eq('id', reservationId)
        .maybeSingle();
    if (row == null) return null;
    return PickupReservation.fromJson(Map<String, dynamic>.from(row));
  }

  /// Seller: collect a hold from its code in ONE call — the server resolves the
  /// code for this store and then runs the ordinary fulfilment, so this cannot
  /// drift from [fulfill]. Returns the POS order id.
  Future<String?> fulfillByCode(String code, {String paymentMethod = 'cash'}) async {
    final orderId = await _client.rpc('fulfill_pickup_reservation_by_code', params: {
      'p_code': PickupReservation.normalizeCode(code),
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
        .select('*, products(name), profiles(full_name)')
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
  /// This is the SELF-SERVICE path: only the customer may call it, only before
  /// the deadline passes, and only up to [PickupReservation.maxExtensions]
  /// times. A store that wants to be lenient uses [grantExtension] instead — a
  /// separate RPC with its own budget and a recorded reason — so "the customer
  /// asked" and "we chose to give them more time" never look alike in the data.
  /// The server enforces every rule, and the CHECK constraint on
  /// `pickup_deadline` caps the total window at
  /// [PickupReservation.maxWindowHours] hours no matter what.
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

  /// Store owner: give a live hold more time as an explicit GOODWILL action.
  ///
  /// Deliberately not a convenience wrapper around [extend]: the server requires
  /// [reason] (3–280 characters, also enforced by a CHECK on the trail), and it
  /// records who granted it, for whom, from which deadline to which, how many
  /// hours and why. The store's budget is its own
  /// ([PickupReservation.maxStoreExtensions]), so this does not spend the
  /// customer's, and the new deadline gets its own T-2h warning.
  ///
  /// Returns the NEW deadline (local), or null when the server sent none.
  Future<DateTime?> grantExtension({
    required String reservationId,
    required String reason,
  }) async {
    final result = await _client.rpc(
      'grant_pickup_extension',
      params: {'p_reservation_id': reservationId, 'p_reason': reason},
    );
    final raw = result?.toString();
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  /// Columns the turn's own model reads — spelled out so a schema change cannot
  /// silently start feeding the UI nulls.
  static const String _grantColumns = 'id, reservation_id, customer_id, '
      'store_id, granted_by, previous_deadline, new_deadline, hours_granted, '
      'reason, created_at';

  /// The trail's own columns PLUS the hold it explains, for the customer's
  /// history. A SEPARATE constant on purpose: [_grantColumns] is pinned to the
  /// trail's declared columns by the contract test (an embed is not one of
  /// them), and `fetchStoreGrants` must stay a single-table read.
  static const String _grantTrailColumns = '$_grantColumns, '
      'pickup_reservations(size, products(name, stores(name)))';

  /// The goodwill trail for a store, newest first (RLS scopes it to the owner).
  Future<List<PickupExtensionGrant>> fetchStoreGrants(
    String storeId, {
    int limit = 100,
  }) async {
    final rows = await _client
        .from('pickup_reservation_extension_grants')
        .select(_grantColumns)
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map<PickupExtensionGrant>(
            (r) => PickupExtensionGrant.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// The same trail as it concerns the signed-in customer, WITH the names.
  ///
  /// This one feeds the history screen as well as the per-hold note, so the rows
  /// have to be readable on their own: `reservation_id` is the trail's FK, so the
  /// hold is embedded (and through it the product and the store it is held at).
  /// The embed is why a grant stays visible after its hold has been collected or
  /// cancelled — and why a granted hold outside the holds list's own `LIMIT`
  /// still shows up here.
  Future<List<PickupExtensionGrant>> fetchMyGrants({int limit = 100}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return const [];
    final rows = await _client
        .from('pickup_reservation_extension_grants')
        .select(_grantTrailColumns)
        .eq('customer_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map<PickupExtensionGrant>(
            (r) => PickupExtensionGrant.fromJson(Map<String, dynamic>.from(r)))
        .toList();
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
  // NOTE the order: `STORE_EXTENSION_LIMIT_REACHED` CONTAINS
  // `EXTENSION_LIMIT_REACHED`, so the store's cap must be matched first or the
  // seller would be told about the customer's. (Pinned by a unit test.)
  if (raw.contains('STORE_EXTENSION_LIMIT_REACHED')) {
    return 'This hold has already had a goodwill extension from the store. If '
        'the customer needs longer, ask them to reserve again.';
  }
  if (raw.contains('INVALID_REASON')) {
    return 'Add a short reason (3-280 characters) — it is recorded with the '
        'extension so the new deadline can be explained later.';
  }
  if (raw.contains('EXTENSION_LIMIT_REACHED')) {
    // Quotes [PickupReservation.maxHoldHours] — the customer's OWN ceiling —
    // and then says the store may still add time. It must not quote the absolute
    // [PickupReservation.maxWindowHours]: a store's goodwill is a favour, not
    // something the customer may count on, and the number they can act on is
    // their own budget.
    return 'You have already been extended once on this hold, so you cannot ask '
        'again (customer extensions stop at '
        '${PickupReservation.maxHoldHours} hours). The store can still add '
        'time on their side if they are willing.';
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
  // The two code-specific NOT_FOUNDs come FIRST: both contain the bare
  // 'NOT_FOUND' the generic branch below matches, and "that reservation no
  // longer exists" is the wrong thing to tell a seller holding a typed code.
  if (raw.contains('NOT_FOUND') && raw.contains('a code is')) {
    return 'A pickup code is 6 characters — check the code and try again.';
  }
  if (raw.contains('NOT_FOUND') && raw.contains('no pickup hold')) {
    return 'No pickup hold for your store matches that code.';
  }
  if (raw.contains('NOT_FOUND')) {
    return 'That pickup reservation no longer exists.';
  }
  return 'Something went wrong with the pickup reservation. Please try again.';
}
