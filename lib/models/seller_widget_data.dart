/// The seller home-screen widget's payload.
///
/// A home-screen widget is drawn by the **operating system**, not by Flutter:
/// nothing in `lib/widgets/` renders inside it, and no `Provider`, `BuildContext`
/// or `setState` exists in that process. What crosses the boundary is the flat
/// bag of primitives this class produces, which
/// [SellerWidgetService] hands to `home_widget`.
///
/// Two consequences shape this file, and both are deliberate:
///
///  * **Everything is a primitive.** `home_widget` persists to
///    `SharedPreferences` on Android and to a shared plist on iOS, so the
///    payload is `String`/`int`/`double`/`bool` only. A nested map or a model
///    object is not reliably readable on the native side, so the flattening
///    happens here, once, where a test can see it.
///  * **Every string is pre-formatted.** `RemoteViews` on Android cannot format
///    a currency or a clock — it inflates layout XML and sets text. So the
///    number AND its display string are both written; the native side picks a
///    field and never computes one.
///
/// Pure Dart on purpose: no Flutter import, no Supabase, no platform channel.
/// That is what makes the formatting and the serialisation testable without an
/// engine.
library;

/// Stable keys for the widget payload.
///
/// These are a **wire format**: the Android layout in `res/layout/` and the iOS
/// `TimelineProvider` both read them by name. Renaming one is a breaking change
/// that silently blanks a field on every phone that already has the widget
/// placed, so the values are spelled once here and referenced everywhere else.
class SellerWidgetKeys {
  const SellerWidgetKeys._();

  /// Whether a seller with a store is signed in. The widget's empty state
  /// (customer signed in, signed out, or no store yet) is decided by this one
  /// flag rather than by "is a name empty", because a store genuinely can be
  /// named ""  and must not then look signed-out.
  static const String hasStore = 'seller_has_store';

  static const String storeName = 'seller_store_name';

  /// Raw amount, for any native-side arithmetic or accessibility text.
  static const String todayRevenue = 'seller_today_revenue';

  /// The same amount already formatted (e.g. `₱12.5k`) — see the library note.
  static const String revenueLabel = 'seller_revenue_label';

  static const String pendingOrders = 'seller_pending_orders';
  static const String pendingCustoms = 'seller_pending_customs';
  static const String pendingReservations = 'seller_pending_reservations';
  static const String activePickups = 'seller_active_pickups';

  /// The combined "needs you now" count the widget's badge shows. Written rather
  /// than summed natively so the rule lives in one place (and is unit-tested).
  static const String attentionCount = 'seller_attention_count';

  static const String lowStockCount = 'seller_low_stock';
  static const String unreadNotifications = 'seller_unread_notifications';

  /// Milliseconds since epoch — comparable, machine-readable.
  static const String updatedAtMillis = 'seller_updated_at_millis';

  /// The same instant already formatted (e.g. `2:31 PM`) — see the library note.
  static const String updatedAtLabel = 'seller_updated_at_label';

  /// Every key this payload can write, so `clear()` cannot miss one.
  ///
  /// A hand-maintained list on purpose: `toWidgetValues()` is the writer and
  /// this is the eraser, and a test asserts the two agree. Deriving it by
  /// calling `toWidgetValues()` on an empty payload would silently stop
  /// clearing any key added to the writer behind a branch.
  static const List<String> all = <String>[
    hasStore,
    storeName,
    todayRevenue,
    revenueLabel,
    pendingOrders,
    pendingCustoms,
    pendingReservations,
    activePickups,
    attentionCount,
    lowStockCount,
    unreadNotifications,
    updatedAtMillis,
    updatedAtLabel,
  ];
}

/// A seller's dashboard numbers, reduced to what a widget tile can show.
///
/// Deliberately NOT the dashboard's own `_DashboardData`: that model carries
/// chart series, recent orders and stale-order lists for a scrollable screen.
/// A widget shows five numbers and a store name, and carrying the rest would
/// mean querying for it every background refresh for nothing.
class SellerWidgetData {
  const SellerWidgetData({
    required this.hasStore,
    required this.storeName,
    required this.todayRevenue,
    required this.pendingOrders,
    required this.pendingCustoms,
    required this.pendingReservations,
    required this.activePickups,
    required this.lowStockCount,
    required this.unreadNotifications,
    required this.updatedAt,
  });

  /// Whether a seller with a store is signed in — see [SellerWidgetKeys.hasStore].
  final bool hasStore;
  final String storeName;

  /// Today's takings, online + POS, matching the dashboard's own figure.
  final double todayRevenue;

  /// Orders placed and not yet past the seller's action.
  final int pendingOrders;

  /// Custom (made-to-order) requests still `pending`.
  final int pendingCustoms;

  /// Deposit-gated bulk reservation requests awaiting the seller.
  final int pendingReservations;

  /// Free pickup holds currently holding stock on the shelf.
  final int activePickups;

  /// Product/size rows at or below the low-stock threshold.
  final int lowStockCount;

  /// Unread seller notifications for this store.
  final int unreadNotifications;

  final DateTime updatedAt;

  /// The widget's "needs you now" total: every queue the seller has to act on.
  ///
  /// Summed here rather than on the native side because the composition is a
  /// product decision (which queues count as an interruption) and it is the
  /// number the badge shows.
  int get attentionCount =>
      pendingOrders + pendingCustoms + pendingReservations + activePickups;

  /// The empty state: no seller, no store, nothing to show.
  ///
  /// [updatedAt] is `DateTime.fromMillisecondsSinceEpoch(0)` rather than
  /// `DateTime.now()` so an empty payload can never be mistaken for a fresh
  /// one by anything comparing timestamps.
  factory SellerWidgetData.empty() => SellerWidgetData(
        hasStore: false,
        storeName: '',
        todayRevenue: 0,
        pendingOrders: 0,
        pendingCustoms: 0,
        pendingReservations: 0,
        activePickups: 0,
        lowStockCount: 0,
        unreadNotifications: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Compact currency for a small tile: `₱950`, `₱12.5k`, `₱1.2M`.
  ///
  /// Mirrors the seller charts' own `_formatCurrencyShort`
  /// (`seller_revenue_columns_chart.dart`), so the widget and the dashboard
  /// never disagree about how `₱12,500` reads. Rounded to one decimal because a
  /// widget tile is ~90px wide and `₱12,543.00` does not fit.
  String get revenueLabel => formatCompactPeso(todayRevenue);

  /// A short, absolute clock time for the "as of" line — e.g. `2:31 PM`.
  ///
  /// Absolute rather than relative ("5m ago") because the widget renders from a
  /// snapshot that may be hours old with no timer to age it; "5m ago" frozen on
  /// screen would be a lie, whereas "2:31 PM" stays true.
  String get updatedAtLabel => formatClockTime(updatedAt);

  /// Flattens to the primitive key/value bag the native widget reads.
  Map<String, Object?> toWidgetValues() => <String, Object?>{
        SellerWidgetKeys.hasStore: hasStore,
        SellerWidgetKeys.storeName: storeName,
        SellerWidgetKeys.todayRevenue: todayRevenue,
        SellerWidgetKeys.revenueLabel: revenueLabel,
        SellerWidgetKeys.pendingOrders: pendingOrders,
        SellerWidgetKeys.pendingCustoms: pendingCustoms,
        SellerWidgetKeys.pendingReservations: pendingReservations,
        SellerWidgetKeys.activePickups: activePickups,
        SellerWidgetKeys.attentionCount: attentionCount,
        SellerWidgetKeys.lowStockCount: lowStockCount,
        SellerWidgetKeys.unreadNotifications: unreadNotifications,
        SellerWidgetKeys.updatedAtMillis: updatedAt.millisecondsSinceEpoch,
        SellerWidgetKeys.updatedAtLabel: updatedAtLabel,
      };

  @override
  String toString() => 'SellerWidgetData(store: $storeName, '
      'revenue: $revenueLabel, attention: $attentionCount, '
      'lowStock: $lowStockCount, unread: $unreadNotifications)';
}

/// `₱950`, `₱12.5k`, `₱1.2M` — the compact form used on charts and tiles.
///
/// Negative amounts keep the sign (a refund day is not a zero day).
String formatCompactPeso(double amount) {
  final bool negative = amount < 0;
  final double value = amount.abs();
  final String body;
  if (value >= 1000000) {
    body = '₱${(value / 1000000).toStringAsFixed(1)}M';
  } else if (value >= 1000) {
    body = '₱${(value / 1000).toStringAsFixed(1)}k';
  } else {
    body = '₱${value.floor()}';
  }
  return negative ? '-$body' : body;
}

/// `2:31 PM` — 12-hour clock, the convention the PH-facing screens use.
///
/// Hand-rolled rather than `intl`-based because the payload is built in a
/// background isolate where a locale lookup is a device-dependent variable and
/// this string has exactly one audience.
String formatClockTime(DateTime time) {
  final int hour24 = time.hour;
  final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final String minute = time.minute.toString().padLeft(2, '0');
  final String meridiem = hour24 < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $meridiem';
}
