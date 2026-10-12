/// The three feeds a customer's launcher tile can show, and the rotation between
/// them.
///
/// Pure Dart over a list of product rows — no provider, no widget, no network —
/// because this runs in the widget's **background isolate**, where none of those
/// exist, and because "which three products does the tile show?" is a decision
/// worth testing without a phone.
///
/// Every rule that decides whether a product *qualifies* is imported, never
/// re-spelled: a live sale is [isOnSale] (the same rule the ON SALE poster and
/// every tag use), and "in my size" is [productsInMySize] (the same rule as
/// Home's "Based on your size" grid). This file decides only which shelf is being
/// shown and in what order.
library;

import 'dart:math';

import '../models/customer_widget_data.dart';
import 'product_shelf.dart';
import 'sale_price.dart';

/// The products [group] qualifies, in the shelf's own order, cut down to [limit]
/// — with **one slot filled at random** (see [_cap]).
///
/// **Two groups keep the catalog's own order and one does not, and the difference
/// is the meaning of the group.** `newArrivals` is ordered by `created_at`
/// descending because that IS what "new" means — a shuffle would make the group
/// a lie. The other two are handed back in the order the caller supplied, which
/// is the shuffled catalog the app already deals per load.
///
/// A product with an unreadable `created_at` sorts LAST rather than first: an
/// unknown age is not evidence of newness, and letting it win the top slot would
/// put a possibly-ancient product in front of the newest one on the tile.
List<Map<String, dynamic>> feedForGroup(
  CustomerWidgetGroup group,
  Iterable<Map<String, dynamic>> products, {
  required double? euSize,
  String? category,
  int limit = kCustomerWidgetProductSlots,
  DateTime? now,
  Random? random,
  String? avoidId,
}) {
  switch (group) {
    case CustomerWidgetGroup.newArrivals:
      final sorted = products.toList()..sort(newestFirst);
      return _cap(sorted, limit, random, avoidId);

    case CustomerWidgetGroup.inMySize:
      // The shelf is asked for EVERYTHING (limit 0) and capped below, so the one
      // random pick is the same code path for all three shelves — a shelf that
      // capped its own way would make the tile's behaviour depend on which shelf
      // was showing.
      return _cap(
        productsInMySize(products, euSize: euSize, category: category),
        limit,
        random,
        avoidId,
      );

    case CustomerWidgetGroup.onSale:
      return _cap(
        products.where((product) => isOnSale(product, now: now)).toList(),
        limit,
        random,
        avoidId,
      );
  }
}

/// Newest first; anything with no readable `created_at` goes last.
int newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  final DateTime? left = _createdAt(a);
  final DateTime? right = _createdAt(b);
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return right.compareTo(left);
}

DateTime? _createdAt(Map<String, dynamic> product) {
  final raw = product['created_at'];
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

/// [products], cut down to [limit] — and at ONE slot, chosen at random.
///
/// **The tile is one card, and which card it is has to change.** The shelves are
/// stable things (the newest, the ones in your size, the ones on sale), so taking
/// the first of a shelf would put the same product on the tile for as long as it
/// stayed newest — with the app sync running on every launch and every return to
/// the foreground, a customer would see one product for hours and conclude the
/// tile was stuck. So the single slot is drawn at random from the qualifying shelf
/// on every refresh, which is the behaviour asked for: *one card, in random*.
///
/// [random] is injectable rather than created here so the choice is testable with
/// a seed; production passes a fresh `Random()` (see `CustomerWidgetService`). A
/// null [random] falls back to the shelf's own order, which keeps this function
/// usable as a pure "what qualifies" query — [limit] `0` returns everything.
///
/// [avoidId] is the product the tile is showing right now. When the shelf holds
/// anything else, it is **not** chosen again: a random pick repeats the previous
/// product one time in *n*, and a refresh that lands on the same card is
/// indistinguishable from a refresh that did not run. The exclusion is dropped
/// when it would empty the shelf, so a one-product shelf still draws its product
/// rather than a blank tile.
List<Map<String, dynamic>> _cap(
  List<Map<String, dynamic>> products,
  int limit,
  Random? random,
  String? avoidId,
) {
  if (limit <= 0 || products.isEmpty) return products;

  if (limit == 1) {
    if (random == null) return products.length == 1 ? products : products.sublist(0, 1);

    var pool = products;
    if (avoidId != null && products.length > 1) {
      final withoutPrevious =
          products.where((p) => p['id']?.toString() != avoidId).toList();
      if (withoutPrevious.isNotEmpty) pool = withoutPrevious;
    }
    return <Map<String, dynamic>>[pool[random.nextInt(pool.length)]];
  }

  return products.length > limit ? products.sublist(0, limit) : products;
}

/// Which group the tile shows next.
///
/// [available] is the groups that actually have products right now — a group with
/// nothing in it is never shown empty, which is the whole reason the rotation
/// takes the set rather than assuming the next one is usable.
///
/// [advance] is the difference between the two kinds of refresh. **True is the
/// scheduled background run**, which moves the tile on one group per refresh (the
/// behaviour the tile was asked for: a rotating window on the catalog). **False is
/// an app-driven sync** — a login, a return to the foreground — which re-renders
/// the group already on screen with fresh numbers. Advancing there too would mean
/// the tile changed every time the customer opened the app, which is not a
/// refresh, it is a slot machine.
///
/// Returns null when [available] is empty: the caller's answer to that is to
/// clear the tile, not to show a heading over nothing.
CustomerWidgetGroup? pickGroup({
  required Set<CustomerWidgetGroup> available,
  required int lastShownIndex,
  required bool advance,
}) {
  if (available.isEmpty) return null;

  // An out-of-range index (a payload written by an older build, or a cleared one)
  // is treated as "before the first group" rather than as an error: scanning
  // forward from it lands on the first available group, which is the only sane
  // thing an unknown position can mean.
  //
  // ⚠️ Normalised to -1, not merely checked for `current`. A stale index from a
  // build that knew MORE groups (or a garbage one) still advances by wrapping
  // otherwise: `99` would land mid-rotation — a tile that jumps to an arbitrary
  // group on the first refresh and then rotates from there. The two out-of-range
  // ends have to mean one thing, and it is "the beginning".
  final normalized = lastShownIndex.isFinite &&
          lastShownIndex >= 0 &&
          lastShownIndex < CustomerWidgetGroup.values.length
      ? lastShownIndex
      : -1;

  final current = normalized >= 0 && normalized < CustomerWidgetGroup.values.length
      ? CustomerWidgetGroup.values[normalized]
      : null;
  if (!advance && current != null && available.contains(current)) return current;

  for (var step = 1; step <= CustomerWidgetGroup.values.length; step++) {
    final index = (normalized + step) % CustomerWidgetGroup.values.length;
    final candidate = CustomerWidgetGroup.values[index];
    if (available.contains(candidate)) return candidate;
  }

  return null;
}
