/// Delivery date estimation utilities.
///
/// Computes a concrete calendar date for the checkout delivery estimate
/// by advancing a start date by a configurable number of *business days*
/// (Monday–Friday only). Weekends are skipped; no holiday calendar is
/// applied (none exists in the project).
library;

/// Number of business days (Mon–Fri) used to compute the estimated
/// delivery date. Midpoint of the former 3–5 day range.
const int deliveryBusinessDays = 4;

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Returns the date that is [businessDays] business days after [startDate].
///
/// Saturdays and Sundays are skipped while counting. A start date that
/// falls on a weekend still counts only weekdays from that point on.
/// Returns the date *at* the final business day (not one past it).
DateTime getEstimatedDeliveryDate(
  DateTime startDate, {
  int businessDays = deliveryBusinessDays,
}) {
  if (businessDays <= 0) return startDate;

  var date = DateTime(startDate.year, startDate.month, startDate.day);
  var remaining = businessDays;
  while (remaining > 0) {
    date = DateTime(date.year, date.month, date.day + 1);
    // Weekday check: DateTime.monday == 1 ... sunday == 7
    if (date.weekday <= DateTime.friday) {
      remaining--;
    }
  }
  return date;
}

/// Formats [date] as `Weekday, Mon D, YYYY` (e.g. "Wednesday, Aug 12, 2026").
///
/// Pure-Dart formatting (the project does not use the `intl` package).
String formatDeliveryDate(DateTime date) {
  final weekday = _weekdayNames[date.weekday - 1];
  final month = _monthNames[date.month - 1];
  return '$weekday, $month ${date.day}, ${date.year}';
}
