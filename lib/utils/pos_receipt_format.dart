/// Formatting shared by every copy of a POS receipt — the PDF the customer
/// takes, and the email that lands in their Gmail.
///
/// Keeping one set of helpers is the point: the paper, the screen and the
/// email must never disagree about the receipt code, the money or the time.
/// Pure functions, no widgets, no clock reads.
library;

const _months = [
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

/// `₱1,234.50` — the peso sign included. The PDF builder folds it to `PHP `
/// because the base fonts cannot draw the glyph; the email keeps it.
String formatPeso(num value) {
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final sign = value < 0 ? '-' : '';
  return '$sign₱$grouped.${parts[1]}';
}

/// The order id is a UUID; the first block is the code every card, receipt and
/// email prints as `#16C13EA7`.
String receiptCode(Object? id) {
  final raw = (id ?? '').toString();
  if (raw.isEmpty) return '—';
  final head = raw.length >= 8 ? raw.substring(0, 8) : raw;
  return head.toUpperCase();
}

/// `Nov 19, 2026 · 4:12 PM`
String receiptStamp(DateTime dt) {
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final meridiem = dt.hour < 12 ? 'AM' : 'PM';
  return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour:$minute $meridiem';
}

/// The sale's timestamp in the phone's time zone, or null if unreadable.
DateTime? receiptTime(Map<String, dynamic> order) => DateTime.tryParse(
      order['created_at']?.toString() ?? '',
    )?.toLocal();

/// `Cash`, `GCash`, `Bank transfer` — never the raw database value.
String paymentMethodLabel(Object? method) {
  final value = (method ?? 'Cash').toString().trim();
  if (value.isEmpty) return 'Cash';
  if (value.toLowerCase() == 'gcash') return 'GCash';
  return value[0].toUpperCase() + value.substring(1);
}
