/// "In my size" — the ONE rule for which products a customer's own size and
/// shopping scale admit.
///
/// Pure Dart over a list, with no provider, no widget and no network, because
/// the rule now has two callers that can never meet:
///
///   * **the app** — `ProductProvider.productsInSize`, filtering the catalog it
///     already has in memory, behind Home's "Based on your size" grid, and
///   * **the background widget worker** — a cold isolate with a fresh query and
///     no `ProductProvider` at all, choosing what a customer's launcher tile
///     suggests.
///
/// Those two surfaces are the same promise made twice — *these come in my
/// size* — and a tile that suggested a pair the size grid would not show is the
/// shop contradicting itself about the customer's own feet. So the rule is here,
/// once, and `ProductProvider.productsInSize` is a thin delegate to it rather
/// than a second copy that can drift.
///
/// Deliberately a separate file from `size_match.dart` (which answers "does this
/// product stock this size?") and `product_audience.dart` (which answers "who is
/// this product for?"): this is the composition of the two, and keeping it
/// separate is what lets each half stay independently testable.
library;

import 'product_audience.dart';
import 'size_match.dart';

/// The products that stock [euSize] right now, narrowed by [category].
///
/// The exclusion rules come from the existing helpers and are not re-decided
/// here: [stocksMySize] requires an **available, exact** size match (a sold-out
/// size is not a suggestion, and neither is the next size down), and the stated
/// audience narrows the shelf only when the customer has stated a scale.
///
/// **`unisex` counts, and a missing audience does not.** A unisex product in the
/// customer's size genuinely IS in their size — this is a personal shelf, not a
/// curated rail, so the "would appear three times" objection that makes the rails
/// skip unisex does not apply. A product with NO stated audience is excluded
/// whenever a scale IS stated, following the stated-data-only rule the audience
/// rails already use: an unstated audience is never inferred from the size band
/// (EU is unisex, so the band cannot tell Men's from Women's, and the kids' band
/// overlaps the adult one at the top).
///
/// **With no stated scale the shelf stays size-only** rather than guessing one,
/// which is what stops an empty result for a customer who simply never picked a
/// chart.
///
/// [euSize] null returns EMPTY, never a fallback size — every size surface is
/// absent-safe by design. [limit] of 0 means the whole shelf, the convention
/// `productsInAudience` / `productsInSearch` follow.
///
/// The ORDER is the caller's own: this hands back the matches in the order it was
/// given them, which is how the catalog's per-load shuffle survives into the
/// shelf (the app's "fresh feed") and how the widget's own shuffled query decides
/// what a tile looks like.
List<Map<String, dynamic>> productsInMySize(
  Iterable<Map<String, dynamic>> products, {
  required double? euSize,
  String? category,
  int limit = 0,
}) {
  if (euSize == null) return const [];

  final wanted = productAudienceFrom(category);
  final matches = products.where((p) {
    if (!stocksMySize(p, euSize)) return false;
    if (wanted == null || wanted == kUnisexAudience) return true;
    final audience = productAudienceFrom(p['audience']?.toString());
    return audience == wanted || audience == kUnisexAudience;
  }).toList();

  return limit > 0 && matches.length > limit
      ? matches.sublist(0, limit)
      : matches;
}
