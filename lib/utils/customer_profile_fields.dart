/// Pure helpers for the customer sign-up profile fields and the manual
/// foot-profile entry. Kept free of Flutter widgets so the validation rules
/// (birthday policy, size list, gender self-describe guard) are unit-testable
/// without a widget harness.
library;

import '../constants/app_constants.dart';

/// EU shoe sizes offered by the manual foot-profile picker, in half-size
/// steps (35.0 → 48.0) — the same range the scan results screen uses, so a
/// manually-entered size is directly comparable to an AR-recommended one.
const List<String> customerEuSizes = [
  '35', '35.5', '36', '36.5', '37', '37.5', '38', '38.5', '39', '39.5',
  '40', '40.5', '41', '41.5', '42', '42.5', '43', '43.5', '44', '44.5',
  '45', '45.5', '46', '46.5', '47', '47.5', '48',
];

/// The width labels offered by the manual foot-profile picker. Stored
/// verbatim in `profiles.foot_width` (see AppConstants.footWidthOptions).
const List<String> customerFootWidths = AppConstants.footWidthOptions;

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
