/// The one place that decides what a stored size *means*.
///
/// A size string in this app is either `'{SYSTEM} {VALUE}'` (`'EU 40'`,
/// `'US 8'`, `'UK 3.5'`, `'JP 25'`) or a bare value (`'40'`, `'9.5'`). The
/// database never sees the system: every RPC matches sizes digits-only
/// (`regexp_replace(size, '\D', '', 'g')`), so `'EU 40'` and `'40'` are the
/// same row to Postgres. [sizeKey] mirrors that rule exactly.
///
/// Pure Dart — no Flutter — so it is unit-testable without a widget harness
/// (the same precedent as `customer_profile_fields.dart`).
///
/// See `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §4–5 for the defects this closes
/// and `docs/AI/SIZE_VARIANT_FLOW.md` §3.3 for the size-format contract.
library;

/// Which system a bare (prefix-less) size belongs to. Decision #1 in
/// `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §2: **EU**, because every shipped
/// label says EU and the catalog's plausible band is 35–48.
const String kDefaultSizeSystem = 'EU';

/// Plausible EU band. Sizes outside it are treated as an unknown system
/// rather than silently reinterpreted (plan §5.2 step 1).
const double kEuMin = 35;
const double kEuMax = 48;

/// Half a size. The "closest available" tolerance — never a silent
/// substitution (plan §5.2, R3).
const double kNearSizeToleranceEu = 0.5;

/// The shopping size SCALE a US/UK label is drawn on. EU itself is unisex —
/// EU 42 is EU 42 whoever is wearing it — but the US and UK charts are not:
/// EU 42 is **US 9** on the men's chart and **US 10.5** on the women's.
///
/// Stored per customer in `profiles.foot_size_category` and per scan in
/// `foot_measurements.shoe_category` (both `'men' | 'women' | 'kids'`).
/// Men's is only the fallback for a customer who never picked a scale, which
/// is what every other surface in the app already does.
const String kDefaultSizeCategory = 'men';

/// EU → US chart offsets, by scale (plan §4.4).
///
/// This is the single owner of those numbers. Two copies of them used to live
/// in `FootMeasurement.euToUs` and `foot_measurement_utils.euToUs`, while the
/// product page — which needs them to label the size grid — could see neither,
/// so it hardcoded the men's scale.
///
/// Still an approximation: verify against an authoritative chart before
/// trusting the women's offset across the whole range.
const Map<String, double> kEuToUsChartOffset = {
  'men': 33.0,
  'women': 31.5,
  'kids': 33.0,
};

/// EU → UK chart offset. Slightly below the men's US step, as before.
const double kEuToUkChartOffset = 33.5;

/// Units a size can be shown in, EU first because EU is what the catalog and
/// the profile snapshot store.
const List<String> kSizeUnits = ['EU', 'US', 'UK'];

/// The units that can be honestly labelled on [category]'s chart.
///
/// Men's and women's have a US chart (`EU − 33` / `EU − 31.5`) and share the UK
/// step. Kids does not: child sizes are a separate, non-linear scale (EU 22 is
/// roughly UK 5, not `22 − 33.5`), and the men's-derived step this app owns
/// would label a child's EU 22 as 'US -11'. A kids' shopper is therefore
/// offered EU alone — the one label that is never a guess. Adding kids' US/UK
/// needs a real chart, not another offset.
List<String> sizeUnitsForCategory(String? category) =>
    category == 'kids' ? const ['EU'] : kSizeUnits;

/// The EU → US offset for [category]; men's when the scale is unset or
/// unrecognised — never a guessed women's/kids chart.
double euToUsChartOffset(String? category) =>
    kEuToUsChartOffset[category] ?? kEuToUsChartOffset[kDefaultSizeCategory]!;

/// US label for an EU size on [category]'s chart — halves kept exact:
/// EU 42 → 9 (men) / 10.5 (women).
double usSizeFromEu(double eu, {String? category}) =>
    eu - euToUsChartOffset(category);

/// The EU size behind a US size on [category]'s chart.
double euSizeFromUs(double us, {String? category}) =>
    us + euToUsChartOffset(category);

/// UK label for an EU size on the app's single UK chart.
///
/// Deliberately NOT category-aware: the app owns a women's offset for the US
/// chart only, and inventing a women's UK chart here would put this label at
/// odds with `euToUk()` on the scan screens. It stays the approximation it
/// already was.
double ukSizeFromEu(double eu) => eu - kEuToUkChartOffset;

/// The EU size behind a UK size.
double euSizeFromUk(double uk) => uk + kEuToUkChartOffset;

/// A leading system prefix followed by a value: `'EU 40'`, `'EU40'`, `'US 8'`.
/// The value must start with a digit, so a word like `'Other'` is not
/// mistaken for a system.
final RegExp _systemPrefix = RegExp(r'^([A-Za-z]+)\s*([0-9].*)$');

/// Digits only, mirroring the database's `regexp_replace(size, '\D', '', 'g')`.
final RegExp _nonDigit = RegExp(r'[^0-9]');

/// Everything that is not a digit or a dot, so half sizes survive.
final RegExp _nonNumeric = RegExp(r'[^0-9.]');

/// The system (`'EU'` | `'US'` | `'UK'` | `'JP'` | …) a stored size string is
/// in.
///
/// Prefers an explicit prefix; a bare number falls back to
/// [kDefaultSizeSystem]. Strings with no recognizable prefix+number (empty,
/// `'Other'`, garbage) also return the default — pair with [sizeNumber], which
/// returns null for those.
String sizeSystem(String raw) {
  final match = _systemPrefix.firstMatch(raw.trim());
  if (match == null) return kDefaultSizeSystem;
  return match.group(1)!.toUpperCase();
}

/// The numeric value (`'EU 40'` → 40.0, `'9.5'` → 9.5). null when
/// unparseable.
double? sizeNumber(String raw) {
  final cleaned = raw.replaceAll(_nonNumeric, '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// The digits-only key the DATABASE matches on — mirrors
/// `regexp_replace(size, '\D', '', 'g')`.
///
/// Two sizes sharing a key are the same row to every RPC in
/// `supabase/migrations/`, so they must be the same entry in any client map.
/// The mirror is exact: `'UK 3.5'` and `'9.5'` reduce to `'35'` and `'95'`,
/// decimal point included, because the database strips non-digits.
String sizeKey(String raw) => raw.replaceAll(_nonDigit, '');

/// The profile's EU size as a [sizeKey], for comparing against catalog sizes.
String sizeKeyForEu(double euSize) => sizeKey(formatSizeNumber(euSize));

/// Value of [raw] in EU (identity when already EU, and for bare values that
/// default to EU).
///
/// Unknown systems keep their raw value — no per-category offsets, because the
/// three converters this replaced disagreed (plan §4.4). P1's match rule (§5.2
/// step 1) rejects anything outside `[kEuMin, kEuMax]`, which is what makes
/// that safe: a `'JP 25'` stays `25` and is never claimed as EU 25.
double? sizeNumberInEu(String raw) {
  final number = sizeNumber(raw);
  if (number == null) return null;
  final system = sizeSystem(raw);
  if (system == 'EU') return number;
  return convertSizeNumber(number, system, 'EU');
}

/// Render a stored size with its system named: `'EU 40'` / `'US 8'`.
///
/// This is the one label formatter every surface uses instead of a hardcoded
/// `'EU '` literal (plan §4.2). Bare values are named with
/// [kDefaultSizeSystem]; unparseable strings come back verbatim.
///
/// Pass [unit] to display the value converted into another unit (e.g. the
/// product page's US/EU/UK switcher), and [category] to say which shopping
/// scale that unit's chart is drawn on (`'women'` → EU 42 reads US 10.5).
String formatSize(String raw, {String? unit, String? category}) {
  final number = sizeNumber(raw);
  if (number == null) return raw;
  final system = sizeSystem(raw);
  final target = unit ?? system;
  final value = target == system
      ? number
      : convertSizeNumber(number, system, target, category: category);
  return '$target ${formatSizeNumber(value)}';
}

/// Convert a numeric shoe size between units.
///
/// EU is the pivot — it is the system the catalog stores and the only one with
/// a chart offset per scale. [category] selects the US chart (`'men'` by
/// default); EU→UK uses the app's fixed UK step, and UK→US goes through EU.
/// Identical units are identity, and an unknown system is returned unchanged
/// rather than silently treated as one of the three (plan §4.4).
double convertSizeNumber(double value, String from, String to,
    {String? category}) {
  if (from == to) return value;
  final double? eu = switch (from) {
    'EU' => value,
    'US' => euSizeFromUs(value, category: category),
    'UK' => euSizeFromUk(value),
    _ => null,
  };
  if (eu == null) return value;
  return switch (to) {
    'EU' => eu,
    'US' => usSizeFromEu(eu, category: category),
    'UK' => ukSizeFromEu(eu),
    _ => eu,
  };
}

/// Format a numeric size, dropping the decimal for whole numbers:
/// 40.0 → '40', 6.5 → '6.5'.
String formatSizeNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// Order two stored sizes by numeric value — half sizes included.
///
/// `int.tryParse` collapsed `'9.5'` and `'EU 40'` to `0` and sorted them to
/// the front (plan §4.3). Unparseable values sort last, and ties fall back to
/// the raw string so the order is deterministic.
int compareSizes(String a, String b) {
  final na = sizeNumber(a);
  final nb = sizeNumber(b);
  if (na == null && nb == null) return a.compareTo(b);
  if (na == null) return 1;
  if (nb == null) return -1;
  final byNumber = na.compareTo(nb);
  return byNumber != 0 ? byNumber : a.compareTo(b);
}
