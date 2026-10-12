/// The **customer** home-screen widget's payload.
///
/// The same launcher tile serves both roles: a seller sees their dashboard
/// numbers, a customer sees products. This is the customer half of the wire
/// format, and it is a SEPARATE class from `SellerWidgetData` on purpose —
/// neither payload can be rendered by the other's layouts (one is six counters,
/// the other is three photographs and their prices), and keeping them apart
/// means a change to one cannot blank a field in the other.
///
/// The same two rules from the seller payload apply here, for the same reasons:
///
///   * **Everything is a primitive.** `home_widget` persists to
///     `SharedPreferences` on Android and a shared plist on iOS, so no nested map
///     or model object crosses the boundary — the flattening happens in
///     [toWidgetValues], once, where a test can see it.
///   * **Every string is pre-formatted.** `RemoteViews` cannot format a currency,
///     so both the number and its display string are written and the native side
///     picks a field. The one string that is NOT written here is the group's own
///     name ("New arrivals" / "In your size" / "On sale"): that is static copy and
///     lives in `res/values/strings.xml` with the rest of the widget's words,
///     selected natively from the group's wire value.
///
/// Pure Dart on purpose: no Flutter, no Supabase, no platform channel, so the
/// formatting and the serialisation are testable without an engine — which
/// matters more here than for the seller payload, because this one is also built
/// inside a background isolate.
library;

import 'seller_widget_data.dart' show formatClockTime;

/// How many products a tile can carry.
///
/// **One.** The customer tile is a 3×3 card showing a single product — its
/// photograph, name and price — and the shelf it was drawn from changes which
/// product is on it, not how many. The number is fixed here and the picker caps
/// itself to it, because a widget has no scroll and no pagination: a second
/// product would be a second design at every size rather than more of the same
/// one, and the tile the owner asked for is deliberately a *window* on the
/// catalog — a new product each refresh — rather than a list of three.
///
/// The per-slot key helpers below are still slot-indexed rather than collapsed to
/// single names, because the wire format is shared with the layouts and the
/// provider reads `customer_product_<slot>_*`; one slot is a value the picker
/// obeys, not a different key shape. If a second slot ever comes back, the keys,
/// the eraser and the native arrays all follow with it.
const int kCustomerWidgetProductSlots = 1;

/// Which of the three shelves a tile is currently showing.
///
/// **One group at a time, rotating** — the tile has room for a photograph and a
/// price, not for three shelves with their own headings. The rotation is advanced
/// by the scheduled background refresh (see `CustomerWidgetService`), so the tile
/// is a rotating window on the catalog rather than a fixed favourite.
///
/// [wire] is a cross-language constant: the Kotlin provider maps it to a label in
/// `strings.xml` and to its own branching, so the three values are a contract
/// pinned on both sides by a test. Renaming one silently drops the tile's heading
/// to its placeholder rather than failing a build.
///
/// The order is the rotation order.
enum CustomerWidgetGroup {
  /// Newest products first — "what is new".
  newArrivals('new'),

  /// Products that stock the customer's own size, on their own scale.
  inMySize('suggested'),

  /// Products whose sale is live right now.
  onSale('sale');

  const CustomerWidgetGroup(this.wire);

  final String wire;

  /// The group a stored wire value names, or null for anything unrecognised —
  /// including a value written by an older build, which must never be guessed at.
  static CustomerWidgetGroup? fromWire(String? raw) {
    if (raw == null) return null;
    for (final group in CustomerWidgetGroup.values) {
      if (group.wire == raw) return group;
    }
    return null;
  }
}

/// Stable keys for the customer payload — see `SellerWidgetKeys` for why the
/// values are short, flat and spelled once.
///
/// The per-product keys are built by [productId] and friends rather than listed,
/// and BOTH the writer ([CustomerWidgetData.toWidgetValues]) and the eraser
/// ([all]) go through those same functions, so the one-list-per-slot shape cannot
/// come apart: a slot the writer fills is a slot the eraser clears.
class CustomerWidgetKeys {
  const CustomerWidgetKeys._();

  /// What the tile is, as far as the customer half is concerned: [stateFeed]
  /// (products below), [stateEmpty] (signed in as a customer with nothing to
  /// show), or blank (not a customer at all — draw the seller layouts).
  ///
  /// **One key rather than two.** "Is this a customer?" and "are there products?"
  /// are a single three-way answer, and splitting them into a role flag plus a
  /// content flag makes a fourth combination representable — customer, no products,
  /// not-empty — that nothing means and every reader would have to decide about.
  ///
  /// The native side branches on THIS, never on "is a name empty": a product row
  /// can legitimately carry a blank name, and a blank name must not hide a row.
  static const String state = 'customer_state';

  static const String stateFeed = 'feed';

  static const String stateEmpty = 'empty';

  /// One of [CustomerWidgetGroup]'s wire values.
  static const String group = 'customer_group';

  /// The size the suggestion was built on, already labelled (`EU 42`), or blank
  /// when the group is not the size one. Pre-formatted because the label's unit
  /// comes from the same helper the rest of the app prints sizes with.
  static const String sizeLabel = 'customer_size_label';

  /// Which group was shown last, as an index into [CustomerWidgetGroup]. Read
  /// back before each scheduled refresh to pick the next one.
  static const String rotation = 'customer_rotation';

  static const String updatedAtLabel = 'customer_updated_at_label';

  static String productId(int slot) => 'customer_product_${slot}_id';
  static String productName(int slot) => 'customer_product_${slot}_name';
  static String productPrice(int slot) => 'customer_product_${slot}_price';

  /// The small tag beside the price — a live discount (`-20%`) or blank. Blank is
  /// the normal case: two of the three groups have nothing extra to say that their
  /// own heading does not already say.
  static String productBadge(int slot) => 'customer_product_${slot}_badge';

  /// Absolute path to the cached thumbnail on this device, or blank when the
  /// product has no photograph or the download failed. A PATH and not a URL: the
  /// native side cannot fetch, and the file is decoded in the app's own process
  /// before the bitmap is handed to the launcher.
  static String productImage(int slot) => 'customer_product_${slot}_image';

  /// Every key this payload can write, so the eraser cannot miss one.
  ///
  /// Built from the same slot functions the writer uses, which is what keeps the
  /// two in step as the slot count changes — and a test still asserts the writer's
  /// key set and this list are identical, because that is the property that
  /// actually matters.
  static final List<String> all = <String>[
    state,
    group,
    sizeLabel,
    rotation,
    updatedAtLabel,
    for (var slot = 1; slot <= kCustomerWidgetProductSlots; slot++) ...<String>[
      productId(slot),
      productName(slot),
      productPrice(slot),
      productBadge(slot),
      productImage(slot),
    ],
  ];
}

/// One product as a tile can draw it: a photograph, a name, a price and maybe a
/// discount tag.
///
/// The tile draws exactly one of these ([kCustomerWidgetProductSlots]); the type
/// is a list member anyway so the payload, the picker and the native slot loop
/// stay shaped for more than one.
class CustomerWidgetProduct {
  const CustomerWidgetProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.badge,
    this.imagePath = '',
  });

  /// The product's id, which is also the whole of its tap target's payload: the
  /// row's `PendingIntent` carries `solvision://product/<id>` and the app fetches
  /// the product on arrival. The tile therefore never has to ship the fields the
  /// detail screen needs.
  final String id;

  final String name;
  final double price;

  /// A live discount (`-20%`), or blank.
  final String badge;

  /// Absolute path to the thumbnail cached on this device, or blank.
  final String imagePath;

  String get priceLabel => formatPesoPrice(price);
}

/// A customer's launcher feed: one group of products, plus what the heading needs
/// to name it.
class CustomerWidgetData {
  const CustomerWidgetData({
    required this.group,
    required this.products,
    required this.sizeLabel,
    required this.rotationIndex,
    required this.updatedAt,
  });

  final CustomerWidgetGroup group;

  /// At most [kCustomerWidgetProductSlots]; the caller builds this with the
  /// picker, which caps itself.
  final List<CustomerWidgetProduct> products;

  /// `EU 42` when [group] is [CustomerWidgetGroup.inMySize], else blank.
  final String sizeLabel;

  /// Index of [group] within [CustomerWidgetGroup.values] — stored so the next
  /// scheduled refresh knows which group to advance past.
  final int rotationIndex;

  final DateTime updatedAt;

  /// A customer with nothing to show.
  ///
  /// Not the same statement as "signed out" and not the same as "not a
  /// customer": the account IS a customer and the tile has no products for it
  /// (an empty catalog, or a fetch that failed). The tile says so, instead of
  /// falling back to the seller layouts' "sign in" copy — which is what a
  /// signed-in customer would otherwise be shown, and would be wrong twice over.
  static Map<String, Object?> emptyStateValues() => <String, Object?>{
        CustomerWidgetKeys.state: CustomerWidgetKeys.stateEmpty,
      };

  /// A short, absolute clock time — `2:31 PM`, the same rule (and the same
  /// helper) the seller tile uses, and absolute for the same reason: a snapshot
  /// with no timer must not claim to be live.
  String get updatedAtLabel => formatClockTime(updatedAt);

  /// Flattens to the primitive bag the native widget reads.
  ///
  /// **Every key is written, every time — including the empty slots.** The native
  /// side hides an unused row by its blank id rather than by a missing key, and
  /// the eraser list has to match this map exactly, which a conditional writer
  /// would quietly break.
  Map<String, Object?> toWidgetValues() {
    final values = <String, Object?>{
      CustomerWidgetKeys.state: CustomerWidgetKeys.stateFeed,
      CustomerWidgetKeys.group: group.wire,
      CustomerWidgetKeys.sizeLabel: sizeLabel,
      CustomerWidgetKeys.rotation: rotationIndex,
      CustomerWidgetKeys.updatedAtLabel: updatedAtLabel,
    };

    for (var slot = 1; slot <= kCustomerWidgetProductSlots; slot++) {
      final product = slot <= products.length ? products[slot - 1] : null;
      values[CustomerWidgetKeys.productId(slot)] = product?.id ?? '';
      values[CustomerWidgetKeys.productName(slot)] = product?.name ?? '';
      values[CustomerWidgetKeys.productPrice(slot)] = product?.priceLabel ?? '';
      values[CustomerWidgetKeys.productBadge(slot)] = product?.badge ?? '';
      values[CustomerWidgetKeys.productImage(slot)] = product?.imagePath ?? '';
    }

    return values;
  }

  @override
  String toString() => 'CustomerWidgetData(group: ${group.wire}, '
      'products: ${products.length}, size: $sizeLabel)';
}

/// `₱2,499` — whole pesos with thousands separators, which is how every price in
/// the app is written.
///
/// Mirrors the `_formatCurrency` family the product cards and the seller screens
/// each carry (there is no shared price formatter in `lib/utils/`, and this file
/// must not import Flutter to reach one). Floored to whole pesos for the same
/// reason those are: the app's prices are whole pesos, and a tile has no room for
/// a `.00` that is never anything else.
String formatPesoPrice(double amount) {
  final bool negative = amount < 0;
  final int whole = amount.abs().floor();
  final String grouped = whole.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]},',
      );
  return negative ? '-₱$grouped' : '₱$grouped';
}

/// `-20%` — the same badge the product cards print, from the same rule.
///
/// Blank when there is no live discount. There is deliberately no button or
/// decoration for it: the badge sits in a slot the native side hides when it is
/// empty, so "no discount" costs no space on the tile.
String formatDiscountBadge(int? percent) =>
    (percent == null || percent <= 0) ? '' : '-$percent%';
