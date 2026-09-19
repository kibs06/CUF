/// Pure helpers for the customer sign-up profile fields and the manual
/// foot-profile entry. Kept free of Flutter widgets so the validation rules
/// (birthday policy, size list, gender self-describe guard) are unit-testable
/// without a widget harness.
library;

import '../constants/app_constants.dart';
import 'size_key.dart';

/// EU shoe sizes offered by the manual foot-profile picker for an adult
/// scale, in half-size steps (35.0 → 48.0) — the same range the scan results
/// screen uses, so a manually-entered size is directly comparable to an
/// AR-recommended one.
const List<String> customerEuSizes = [
  '35', '35.5', '36', '36.5', '37', '37.5', '38', '38.5', '39', '39.5',
  '40', '40.5', '41', '41.5', '42', '42.5', '43', '43.5', '44', '44.5',
  '45', '45.5', '46', '46.5', '47', '47.5', '48',
];

/// EU shoe sizes for the Kids' scale, in the same half-size steps.
///
/// Mirrors `euSizeChart`'s own children's band (`foot_measurement_utils.dart`,
/// 22 → 35). Before this, a child's size could not be entered at all: the
/// picker offered 35 → 48 for every scale, so a kid wearing EU 28 had to pick
/// a size they do not wear. The chart hands 36 and up to the women's/men's
/// bands, so Kids' stops at 35.
const List<String> customerKidsEuSizes = [
  '22', '22.5', '23', '23.5', '24', '24.5', '25', '25.5', '26', '26.5',
  '27', '27.5', '28', '28.5', '29', '29.5', '30', '30.5', '31', '31.5',
  '32', '32.5', '33', '33.5', '34', '34.5', '35',
];

/// The EU sizes the manual picker offers for [category]: the children's band
/// for Kids', the adult band for Men's/Women's — and for an unpicked scale,
/// since the customer has not narrowed it yet.
List<String> customerEuSizesFor(String? category) =>
    category == 'kids' ? customerKidsEuSizes : customerEuSizes;

/// The width labels offered by the manual foot-profile picker. Stored
/// verbatim in `profiles.foot_width` (see AppConstants.footWidthOptions).
const List<String> customerFootWidths = AppConstants.footWidthOptions;

/// The "shopping size" scales the app asks about — the same three values the
/// AR scan stores in `foot_measurements.shoe_category` and the profile
/// snapshot keeps in `profiles.foot_size_category`.
///
/// This is a sizing SCALE, not identity: EU 42 is EU 42 for everyone, but
/// `FootMeasurement.euToUs` labels it US 9 on the men's chart and US 10.5 on
/// the women's. A woman shopping men's shoes picks Men's; the account's
/// `gender` column answers a different question and may be unset.
const List<(String, String)> customerFootSizeCategories = [
  ('men', "Men's"),
  ('women', "Women's"),
  ('kids', "Kids'"),
];

/// Display label for a stored `foot_size_category` value ('men' → "Men's").
/// Null when unset or unrecognised — never a guessed scale.
String? footSizeCategoryLabel(String? value) {
  if (value == null) return null;
  for (final (key, label) in customerFootSizeCategories) {
    if (key == value) return label;
  }
  return null;
}

/// The saved shopping scale from a `profiles` row as a chart key
/// (`'men'` | `'women'` | `'kids'`), or null when the customer never picked
/// one (or the stored value is unrecognised).
///
/// Surface the null rather than defaulting it: a guessed scale is what makes
/// the product page label EU 42 'US 9' for a woman. Callers that must render
/// a US/UK label anyway use `size_key.dart`'s men's fallback explicitly.
String? savedFootSizeCategory(Map<String, dynamic>? profile) {
  if (profile == null) return null;
  final raw = profile['foot_size_category']?.toString();
  return footSizeCategoryLabel(raw) == null ? null : raw;
}

/// Validates a birthday picked at signup.
///
/// Rules (confirmed with the product owner):
///  * required — the field is mandatory;
///  * not in the future — flag, don't silently accept, obviously invalid dates;
///  * at least [AppConstants.minimumSignupAgeYears] years old (13+).
///
/// Returns null when [value] is acceptable, or a human-readable reason.
/// The year-only comparison deliberately ignores the day-of-year so a user
/// turning 13 later this year is NOT rejected on their birthday's eve — an
/// off-by-one rejection on the exact day would be worse than letting them in.
String? validateBirthday(DateTime? value) {
  if (value == null) return 'Please select your birthday';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final picked = DateTime(value.year, value.month, value.day);
  if (picked.isAfter(today)) return 'Birthday can\'t be in the future';
  final minAge = AppConstants.minimumSignupAgeYears;
  if (today.year - picked.year < minAge) {
    return 'You must be at least $minAge years old to sign up';
  }
  return null;
}

/// Guards the 'Self-describe' gender free-text field: it only applies when
/// [selectedOption] is 'Self-describe', and must not be blank in that case.
/// Any other selection (or no selection — the field is optional) is fine.
String? validateGenderSelfDescribe(String? selectedOption, String? text) {
  if (selectedOption != 'Self-describe') return null;
  if (text == null || text.trim().isEmpty) {
    return 'Please tell us how you describe yourself';
  }
  return null;
}

/// Formats a birthday for the `DATE` column: local YYYY-MM-DD, so a UTC
/// serialization can never shift the date across midnight (supabase_dart
/// would otherwise send the full ISO-8601 timestamp).
String? formatBirthdayForDb(DateTime? value) {
  if (value == null) return null;
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '${value.year}-$m-$d';
}

/// The effective gender value to persist: the preset option, or the free
/// text when 'Self-describe' was chosen (null when nothing was selected).
String? resolveGenderValue(String? selectedOption, String? selfDescribeText) {
  if (selectedOption == null) return null;
  if (selectedOption == 'Self-describe') {
    final text = selfDescribeText?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }
  return selectedOption;
}

/// One-line summary of the saved foot profile for the Settings row:
/// `'EU 42 · from your AR scan'`, `'EU 40.5 · set manually'`, `'Not set yet'`.
///
/// Display-only. Naming the SOURCE matters: a manually-typed size and a
/// scanned one are both real sizes, but the customer should be able to see
/// which one the app is holding before they change it.
String footProfileSummary(Map<String, dynamic>? profile) {
  if (profile == null || !AppConstants.hasFootSize(profile)) {
    return 'Not set yet';
  }
  final rawSize = profile['foot_size_ph'];
  if (rawSize == null || rawSize.toString().trim().isEmpty) {
    return 'Not set yet';
  }
  final size = formatSize(rawSize.toString());
  final scale =
      footSizeCategoryLabel(profile['foot_size_category']?.toString());
  final withScale = scale == null ? size : '$size · $scale';
  return switch (profile['foot_profile_source']?.toString()) {
    AppConstants.footProfileArScan => '$withScale · from your AR scan',
    AppConstants.footProfileManual => '$withScale · set manually',
    _ => withScale,
  };
}
