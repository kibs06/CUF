import 'sale_price.dart';

/// A store's live sale state, derived from its products through the shared
/// [isOnSale] rule — never stored on the store row and never re-decided in a
/// widget.
///
/// The Stores tab already loads the whole catalog and indexes it per store, so
/// this is a summary of data that is already in memory: no column on `stores`,
/// no second query, and nothing to keep in sync. It exists so the tag, its
/// expiry and its copy all read one derivation rather than three.
class StoreSale {
  const StoreSale({
    required this.count,
    required this.bestDiscount,
    this.earliestEnd,
  });

  /// How many of the store's products are on sale right now.
  ///
  /// Derived from the **same product list** the store's product count uses, so
  /// "5 products" and "on sale" can never describe two different sets.
  final int count;

  /// The store's best live discount, floored ("up to"), or null when the sale
  /// is too small to floor — `maxDiscountPercent` returns null under 1%, and the
  /// tag falls back to a bare face rather than printing `-0%`.
  final int? bestDiscount;

  /// The soonest non-null `sale_ends_at` among the on-sale products
  /// ([earliestSaleEnd]) — what the expiry watcher schedules against. Null when
  /// every active sale is open-ended, which schedules nothing.
  final DateTime? earliestEnd;

  /// Whether the store has anything on sale at all — the tag's render gate.
  bool get hasSale => count > 0;

  /// One announced sentence for the tag, so its wording lives with the data
  /// rather than in the painter. A sale with no floorable figure omits the
  /// number instead of claiming `0 percent`.
  String get semanticsLabel {
    final items = count == 1 ? '1 item' : '$count items';
    final off = bestDiscount != null ? ', up to $bestDiscount percent off' : '';
    return "On sale: $items$off. Double tap to see this store's sale items.";
  }
}

/// Summarises [products]' live sale state at [now].
///
/// Composes the shared helpers rather than re-deciding anything: [isOnSale]
/// decides who counts, [maxDiscountPercent] gives the floored best discount and
/// [earliestSaleEnd] the expiry. [now] is injectable so the expiry watcher can
/// re-derive at a deliberately-past moment.
StoreSale storeSaleFrom(
  Iterable<Map<String, dynamic>> products, {
  DateTime? now,
}) {
  final list = products.toList();
  final count = list.where((p) => isOnSale(p, now: now)).length;
  return StoreSale(
    count: count,
    bestDiscount: count == 0 ? null : maxDiscountPercent(list, now: now),
    earliestEnd: count == 0 ? null : earliestSaleEnd(list, now: now),
  );
}
