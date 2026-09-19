/// Deciding whether a product actually stocks the customer's size.
///
/// Pure Dart — no Flutter — so the match rule is unit-testable without a
/// widget harness, following `size_key.dart`'s precedent. `size_key.dart` owns
/// what a stored size *means*; this file owns the one comparison every
/// size-aware surface must share, so a card, a rail and a product page can
/// never disagree about whether "my size" is available.
///
/// See `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §5.2 (the match rule), §8 R1 (the
/// wrong-confident-claim risk) and §8 R4 (never contradicting the buy button).
library;

import '../models/foot_measurement.dart';
import 'size_key.dart';

/// The band a catalog size must fall inside to be believed as EU.
///
/// The union of the two bands the app itself issues — kids' 22→35
/// (`customerKidsEuSizes`) and adult 35→48 (`customerEuSizes`) — so a child's
/// size is matched as readily as an adult's. Outside it a value is treated as
/// an unknown system and never matched: a stored `'9'` that is really a US 9
/// must not be read as EU 9 (plan §8 R1).
const double kPlausibleEuMin = 22;
const double kPlausibleEuMax = 48;

/// The systems this app can resolve into EU on its own. A size prefixed with
/// anything else (`'JP 25'`, `'CHN 42'`) is a system the app owns no chart for,
/// so it is skipped rather than guessed at.
const List<String> _knownSizeSystems = ['EU', 'US', 'UK'];

/// How a product relates to the customer's size.
enum SizeMatchKind {
  /// The product sells exactly the customer's size. Whether it can be *bought*
  /// is [StockedSize.stock]'s answer, not this one — a stocked size with 0
  /// units is sold out, not absent.
  exact,

  /// The product does not sell the customer's size, but holds something within
  /// [kNearSizeToleranceEu] of it. Reported as "closest is …" — never
  /// substituted silently (plan §8 R3).
  near,
}

/// A product's answer to "do you have my size?".
class StockedSize {
  /// The catalog size that answered, in EU.
  final double euSize;

  /// Units available on [euSize], summed across the product's colours, from
  /// the authoritative `inventory` relation. 0 means the size exists and is
  /// sold out.
  final int stock;

  final SizeMatchKind kind;

  const StockedSize({
    required this.euSize,
    required this.stock,
    required this.kind,
  });

  /// Whether this size can be bought right now.
  bool get isAvailable => stock > 0;
}

/// The product's stock per EU size, from the authoritative `inventory`
/// relation.
///
/// `inventory` only, deliberately: `product_stock.dart`'s `totalStock` and
/// checkout both treat it as the source of truth, and `product_variants` is
/// derived from it — adding the
/// two would inflate every figure and could contradict the buy button (plan
/// §8 R2/R4). Rows for the same size sum, because a product legitimately holds
/// one row per colour (Black EU 42: 2, Brown EU 42: 3 → 5 available on EU 42).
///
/// Keys are `double` and compared with `==`. Every value originates from
/// `double.tryParse` of a digits-only string, and halves and whole numbers are
/// exactly representable in binary — so `42.5` from the catalog and `42.5` from
/// the profile are the same key.
Map<double, int> stockByEuSize(Map<String, dynamic> product) {
  final inventory = product['inventory'];
  if (inventory is! List) return const {};

  final bySize = <double, int>{};
  for (final row in inventory) {
    if (row is! Map) continue;

    final raw = row['size']?.toString() ?? '';
    // A prefix the app owns no chart for is an unknown system, not EU.
    if (!_knownSizeSystems.contains(sizeSystem(raw))) continue;

    final eu = sizeNumberInEu(raw);
    if (eu == null) continue;
    if (eu < kPlausibleEuMin || eu > kPlausibleEuMax) continue;

    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    bySize[eu] = (bySize[eu] ?? 0) + (stock < 0 ? 0 : stock);
  }
  return bySize;
}

/// The size in [product]'s stock that answers [euSize].
///
/// An exact size wins even when it is sold out — the product *does* sell it —
/// so a caller can say "sold out" instead of silently offering the next size
/// down, which would be a different shoe on a different fit. Only when the
/// product does not sell the size at all does the nearest one within
/// [kNearSizeToleranceEu] answer, as [SizeMatchKind.near].
///
/// Returns null when the product holds nothing close enough to mention, or no
/// size data at all — every caller must then render nothing rather than guess.
StockedSize? matchStockedSize(Map<String, dynamic> product, double euSize) {
  final stock = stockByEuSize(product);
  if (stock.isEmpty) return null;

  final exact = stock[euSize];
  if (exact != null) {
    return StockedSize(
      euSize: euSize,
      stock: exact,
      kind: SizeMatchKind.exact,
    );
  }

  double? nearest;
  var nearestDistance = double.infinity;
  for (final candidate in stock.keys) {
    final distance = (candidate - euSize).abs();
    if (distance > kNearSizeToleranceEu) continue;
    // Equally-near ties resolve DOWN, to the smaller size: when the data
    // cannot choose, never advertise a size above the customer's own.
    if (distance < nearestDistance ||
        (distance == nearestDistance &&
            candidate < (nearest ?? double.infinity))) {
      nearest = candidate;
      nearestDistance = distance;
    }
  }
  if (nearest == null) return null;

  return StockedSize(
    euSize: nearest,
    stock: stock[nearest]!,
    kind: SizeMatchKind.near,
  );
}

/// Whether [product] can be bought right now in [euSize].
///
/// The one rule every surface that *suggests* products should use: an exact
/// size with stock behind it. A near size is not the customer's size, and a
/// sold-out exact size is not available.
bool stocksMySize(Map<String, dynamic> product, double euSize) {
  final match = matchStockedSize(product, euSize);
  return match != null && match.kind == SizeMatchKind.exact && match.isAvailable;
}

/// The customer's size for shopping, in EU, or null when they never gave one.
///
/// Order: the profile snapshot, then a scan already in memory.
///
/// The snapshot wins because `AuthProvider.saveFootProfile` is written by BOTH
/// paths — the scan results screens and the manual picker — so it always holds
/// the most recent size the customer gave us, while a measurement left in
/// memory can be older than a manual entry typed after it. The scan is the
/// fallback for the cases the snapshot cannot cover: a write that failed (it is
/// best-effort) or a size stored before the column existed.
///
/// Deliberately does NOT fetch: a signed-in customer's snapshot is already on
/// hand, and browse surfaces must never wait on — or fail because of — a
/// network call. No size resolves → null → every surface renders nothing.
double? shoppingEuSizeFrom(
  Map<String, dynamic>? profile, {
  FootMeasurement? measurement,
}) {
  final raw = profile?['foot_size_ph'];
  if (raw != null && raw.toString().trim().isNotEmpty) {
    final eu = sizeNumberInEu(raw.toString());
    if (eu != null) return eu;
  }

  final scanned = measurement?.effectiveEuSize;
  if (scanned != null && scanned.trim().isNotEmpty) {
    return sizeNumberInEu(scanned);
  }
  return null;
}

/// A resolved EU size as a display label — `42.0` → `'EU 42'`.
///
/// Routed through [formatSize] so no surface hardcodes an `'EU '` literal (the
/// P0 cleanup in the plan's §6).
String euSizeLabel(double euSize) => formatSize(formatSizeNumber(euSize));
