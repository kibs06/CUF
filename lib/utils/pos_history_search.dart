/// Whether one POS history row matches what the seller typed.
///
/// The three things a seller has in hand when they come back for a sale are
/// the receipt code the customer read out, the amount they remember, and who
/// was behind the counter. So the search is exactly those, not a fuzzy match
/// over every column:
///
///   * receipt code — the first 8 characters of the order id, which is what
///     every receipt card and the PDF print as `#16C13EA7`. A leading `#` is
///     ignored, and the match is case-insensitive because the card shows the
///     code in upper case while the id is lower case in the database;
///   * amount — compared against the total as digits (`2550`, `2550.00`), so
///     typing `2,550` or `₱2550` works too: everything but digits and the
///     decimal point is stripped before the compare;
///   * cashier — the seller name printed on the receipt.
///
/// Pure: no widgets and no clock, so the rules are testable on their own.
library;

bool matchesPosHistoryQuery({
  required Map<String, dynamic> order,
  required String query,
  required String cashierName,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;

  // `#16c13e` and `16c13e` are the same lookup.
  final code = (order['id'] ?? '').toString().toLowerCase();
  final shortCode = code.length >= 8 ? code.substring(0, 8) : code;
  if (shortCode.contains(_codeNeedle(needle))) return true;

  final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
  final amount = total.toStringAsFixed(2);
  final digits = _digitsOnly(needle);
  if (digits.isNotEmpty && amount.contains(digits)) return true;

  return cashierName.toLowerCase().contains(needle);
}

String _codeNeedle(String needle) =>
    needle.startsWith('#') ? needle.substring(1) : needle;

/// `₱2,550.00` → `2550.00`, `2550` → `2550`; anything else → empty.
String _digitsOnly(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isPoint = rune == 0x2E;
    if (isDigit || isPoint) buffer.writeCharCode(rune);
  }
  return buffer.toString();
}
