/// Who a product is for — the one place that decides what an audience value
/// *means*.
///
/// Pure Dart, no Flutter: the same precedent as `customer_profile_fields.dart`
/// and `size_key.dart`, so the rule is unit-testable without a widget harness.
///
/// The value is STATED by a seller, never inferred — see
/// `docs/AI/PRODUCT_AUDIENCE_PLAN.md` §1.1 for why the size band cannot stand
/// in for it (EU is unisex, so Men's and Women's share one band, and the
/// kids' band overlaps the adult one at the top).
///
/// Deliberately a SEPARATE file from `customer_profile_fields.dart`, which is
/// about the shopper's own sign-up and foot-profile fields: a product's
/// audience is a different question. The three shared string values and labels
/// are imported from there rather than re-spelled, so `'women'` and `"Women's"`
/// cannot come to mean one thing on a profile and another on a product.
library;

import 'customer_profile_fields.dart';
import 'size_key.dart';

/// The children's audience value — the one band whose sizes can be checked.
///
/// Men's and Women's share the ENTIRE adult band (EU sizing is unisex and only
/// the US/UK *chart* differs), so a size can never contradict either of them.
const String kKidsAudience = 'kids';

/// The one audience that is not a rail.
///
/// A genuinely unisex product (a plain sandal, a house slipper) is a real
/// answer, but listing it in Men's, Women's AND Kids' would put the same card
/// three times down the feed. Rail surfaces must skip it.
const String kUnisexAudience = 'unisex';

/// Every value `products.audience` may hold, in display order, with the label
/// to render for it.
///
/// The first three are `customerFootSizeCategories` — the shopper-side
/// vocabulary the AR scan and the manual picker already write
/// (`foot_measurements.shoe_category`, `profiles.foot_size_category`) — spread
/// in rather than re-declared. `unisex` is the one addition, and it exists
/// ONLY here: the shopper's own scale is never `unisex`, because a customer
/// always shops on one chart.
const List<(String, String)> productAudienceOptions = [
  ...customerFootSizeCategories,
  (kUnisexAudience, 'Unisex'),
];

/// The audiences that get a rail, in fixed order.
///
/// Explicit rather than computed as "the options minus unisex" at each call
/// site: this list is what a later phase's rails iterate and what the guard
/// test in `test/utils/product_audience_test.dart` pins — including that it
/// still matches the shopper-side vocabulary and that `unisex` is absent.
const List<String> productRailAudiences = ['men', 'women', kKidsAudience];

/// The canonical audience value for a stored string, or null.
///
/// **Exact match, deliberately.** No trimming and no case folding, because
/// this value comes from a `TEXT` column whose CHECK constraint is itself an
/// exact comparison (`audience IN ('men','women','kids','unisex')`) and from a
/// closed chip list on the seller form — so anything that is not already
/// canonical is not one of our values, and normalising it would only invent a
/// meaning the database does not hold. `'Men'` and `'unisex '` are null, not
/// `'men'` and `'unisex'`.
///
/// This also matches the existing house parser (`footSizeCategoryLabel` /
/// `savedFootSizeCategory`, which compare exactly and fall back to null), and
/// keeps the "never a guess" rule: an unrecognised, empty or malformed value
/// is null, and every caller must then render nothing rather than pick a
/// default audience.
String? productAudienceFrom(String? raw) {
  if (raw == null) return null;
  for (final (value, _) in productAudienceOptions) {
    if (value == raw) return value;
  }
  return null;
}

/// The children's band, read from the same list the size picker offers
/// (`customerKidsEuSizes`) so the warning cannot drift from what a customer is
/// actually able to enter.
final double _kidsBandMin = double.parse(customerKidsEuSizes.first);
final double _kidsBandMax = double.parse(customerKidsEuSizes.last);

/// Whether a product's sizes contradict the audience a seller picked.
///
/// Only Kids' can be contradicted: a product marked Kids' whose every stocked
/// size sits outside the children's band (EU 22–35) is almost certainly a
/// mis-tapped chip, and a soft note is worth showing. `unisex`/null claim no
/// band, so nothing can contradict them.
///
/// **Warning only, and one-directional.** This never blocks a save, never
/// rewrites the audience, and never rewrites a size — a stated value stays
/// visible and fixable rather than being reinterpreted behind the seller's
/// back (plan §0 decision 5). Callers render it as an inline note.
///
/// False unless every size is readable AND every one of them is outside the
/// band: with no sizes yet, or a custom/unparseable size in the list, there is
/// nothing solid enough to contradict, so nothing is claimed. Sizes go through
/// [sizeNumberInEu] — the same parser the rest of the app uses — so an adult
/// `'EU 42'`, a bare `'42'`, and a kids' `'EU 28'` are read the way the catalog
/// reads them.
bool audienceSizeMismatch({
  required String? audience,
  required Iterable<String> sizes,
}) {
  if (audience != kKidsAudience) return false;
  var sawASize = false;
  for (final raw in sizes) {
    final eu = sizeNumberInEu(raw);
    // One unreadable size means we do not know what this product stocks.
    if (eu == null) return false;
    // A single kids'-band size is enough to confirm the audience is right.
    if (eu >= _kidsBandMin && eu <= _kidsBandMax) return false;
    sawASize = true;
  }
  return sawASize;
}

/// The shopping scale a product's US/UK size labels are drawn on — `'men'`,
/// `'women'`, `'kids'`, or null for "no scale known".
///
/// **The one place the chart precedence lives** (plan §P3, decision #7). Call it
/// once per product and pass the result to [sizeUnitsForCategory] and to
/// `formatSize` / `displaySizeInUnit`'s `category:` — never rebuild this chain
/// at a call site, or the product page and the cart can start disagreeing about
/// which chart EU 42 is read on.
///
/// Precedence, in order:
///
///  1. **`men` / `women` on the product** → THAT product's chart, whatever scale
///     the shopper saved. A woman browsing a men's-cut shoe reads the men's
///     label, because the *item* is sold on the men's chart. This is the whole
///     change: before, the shopper's own scale won.
///  2. **`kids`** → the kids' scale, which [sizeUnitsForCategory] already
///     renders as EU-only — there is no child US/UK chart to draw on (see its
///     doc for why an offset would be a lie). Representing "EU only" as the
///     scale key is the existing convention, so nothing new is invented here.
///  3. **unset (`null`) or unrecognised** → the shopper's own scale, **exactly
///     what the product page passed before this helper existed** — including
///     the null, because a null scale is what makes `formatSize` fall back to
///     men's downstream rather than to a guessed women's chart. With every
///     product in the catalog still unset, this is the branch they all take.
///  4. **`unisex`** → the men's chart ([kDefaultSizeCategory]), the same answer
///     the app already gives when nothing is known about the shopper either.
///
/// [audienceEnabled] is the feature switch — callers pass
/// `AppConstants.productAudienceEnabled`. It is a parameter rather than a read
/// of that constant so this file stays pure Dart (no Flutter), and it is the
/// whole guard: while the switch is `false` this returns today's exact value for
/// every product, so the phase is invisible until it is turned on.
String? productSizeChart({
  required Map<String, dynamic>? product,
  required Map<String, dynamic>? profile,
  required bool audienceEnabled,
}) {
  if (!audienceEnabled) return savedFootSizeCategory(profile);
  return switch (productAudienceFrom(product?['audience']?.toString())) {
    'men' => kDefaultSizeCategory,
    'women' => 'women',
    kKidsAudience => kKidsAudience,
    kUnisexAudience => kDefaultSizeCategory,
    // Null and anything unrecognised: the shopper's own scale, verbatim.
    _ => savedFootSizeCategory(profile),
  };
}

/// The label to render for a canonical audience value, or null.
///
/// Null for null, for an unrecognised value, and for anything that came back
/// from `productAudienceFrom` as null — a caller that has a label is
/// guaranteed to have a real audience.
String? productAudienceLabel(String? value) {
  if (value == null) return null;
  for (final (key, label) in productAudienceOptions) {
    if (key == value) return label;
  }
  return null;
}
