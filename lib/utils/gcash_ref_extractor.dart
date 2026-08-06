/// GCash reference-number extraction from OCR text.
///
/// The POS "scan to fill reference number" flow feeds the text lines
/// recognized by ML Kit text recognition (OCR — not barcode scanning) into
/// [GcashRefExtractor.extract]. GCash "Express Send" receipts print the
/// reference number as plain text next to a "Ref No." label, e.g.
///
///   Ref No.  4043 676 687260
///
/// Strategy (in order):
/// 1. **Label-first** — a line containing a reference label ("ref no",
///    "reference number", "ref #", case-insensitive) is the strongest signal.
///    Its digits are used; if the label line itself has too few digits, the
///    next line is checked (some layouts split the label and the number).
/// 2. **Fallback** — scan every line for a plausible digit run (10–16 digits,
///    with a strong preference for the 13 digits GCash uses) while excluding
///    money/amount lines, dates and times, and scoring grouped digit runs
///    higher. The best candidate plus a short candidate list are returned so
///    the UI can let the seller pick if it is ambiguous.
///
/// The extractor is pure Dart (no platform calls) so it is fully unit-testable.
library;

/// Result of [GcashRefExtractor.extract].
class GcashRefExtraction {
  /// Best candidate, digits only (spaces/formatting stripped for storage).
  /// Null when nothing plausible was found.
  final String? reference;

  /// Up to 3 top candidates (digits only) for the ambiguous case — the UI can
  /// show them as tappable choices instead of guessing silently.
  final List<String> candidates;

  /// Whether the reference was found on a "Ref No."-labeled line (highest
  /// confidence signal).
  final bool matchedLabel;

  /// The best candidate grouped the way GCash receipts print it, so the
  /// seller can visually double-check it (e.g. `4043676687260` →
  /// `4043 676 687260`).
  final String displayGrouped;

  bool get detected => reference != null;

  const GcashRefExtraction({
    this.reference,
    this.candidates = const [],
    this.matchedLabel = false,
    this.displayGrouped = '',
  });

  static const GcashRefExtraction empty = GcashRefExtraction();
}

class GcashRefExtractor {
  /// Plausible reference-number lengths seen on GCash receipts. GCash
  /// reference numbers are 13 digits; the range tolerates OCR splitting or
  /// merging artifacts without over-fitting to a single example.
  static const int minDigits = 10;
  static const int maxDigits = 16;
  static const int idealDigits = 13;

  static final RegExp _refLabel =
      RegExp(r'ref(?:erence)?\s*(?:no|num|number|#)', caseSensitive: false);

  /// Money-looking decimal (thousands separator + 2 decimals) — an amount,
  /// not a reference.
  static final RegExp _decimalAmount =
      RegExp(r'[0-9]{1,3}(?:,[0-9]{3})+\.[0-9]{2}');
  static final RegExp _plainDecimal = RegExp(r'\d+\.\d{2}');

  /// Lines containing these words are treated as amounts/context, never as a
  /// reference number.
  static const List<String> _moneyWords = [
    '₱', 'php', 'peso', 'amount', 'total', 'balance', 'change',
    'due', 'paid', 'fee', 'vat', 'discount', 'charge', 'cash',
  ];

  /// Grouped digit runs (e.g. `4043 676 687260`) — a hallmark of printed
  /// reference numbers. GCash's grouping is 4-3-6, so tokens may be up to 6
  /// digits (a 3-4-only pattern would never match a real receipt).
  static final RegExp _groupedRun = RegExp(r'^\d{3,6}(?: \d{3,6})+$');

  /// Philippine mobile number (exactly `09` + 9 digits) — common on receipts
  /// as contact info, never a reference number.
  static final RegExp _phMobile = RegExp(r'^09\d{9}$');

  static GcashRefExtraction extract(List<String> lines) {
    // ── 1. Label-first: a "Ref No." line is the strongest signal ──
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!_refLabel.hasMatch(line)) continue;

      final digits = _digitsOf(line);
      if (_isPlausible(digits)) {
        return _result(digits, matchedLabel: true);
      }
      // Label present but no plausible digits on the line — some receipts
      // put the number on the following line.
      if (i + 1 < lines.length) {
        final next = _digitsOf(lines[i + 1]);
        if (_isPlausible(next)) {
          return _result(next, matchedLabel: true);
        }
      }
    }

    // ── 2. Fallback: score every line, excluding money/date-like lines ──
    final scored = <({String digits, int score})>[];
    for (final raw in lines) {
      final line = raw.trim();
      final digits = _digitsOf(line);
      if (!_isPlausible(digits)) continue;
      if (_looksLikeMoneyOrDate(line)) continue;
      final score = _score(line, digits);
      // Only keep positive-score lines — a lone phone number or prose number
      // should never be surfaced as a "reference number".
      if (score > 0) {
        scored.add((digits: digits, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) return GcashRefExtraction.empty;

    final candidates = scored.take(3).map((e) => e.digits).toSet().toList();
    return _result(
      scored.first.digits,
      matchedLabel: false,
      candidates: candidates,
    );
  }

  /// Strip all non-digit characters (keeps spaces, dots, dashes out).
  static String _digitsOf(String line) =>
      line.replaceAll(RegExp(r'[^0-9]'), '');

  static bool _isPlausible(String digits) =>
      digits.length >= minDigits && digits.length <= maxDigits;

  static bool _looksLikeMoneyOrDate(String line) {
    final lower = line.toLowerCase();
    if (_moneyWords.any(lower.contains)) {
      return true;
    }
    if (_decimalAmount.hasMatch(line)) {
      return true;
    }
    if (_plainDecimal.hasMatch(line)) {
      return true;
    }
    // Date / time separators — "07/15/2026 10:30" is not a reference number.
    if (line.contains('/') || line.contains(':')) {
      return true;
    }
    return false;
  }

  static int _score(String line, String digits) {
    var score = 0;
    if (digits.length == idealDigits) {
      score += 100;
    } else if (digits.length >= minDigits) {
      score += 20;
    }
    // A line that is mostly digits (e.g. "4043 676 687260") is far more
    // likely to be the reference than prose containing a long number.
    // A lone PH mobile number (contact info on receipts) is NOT a reference.
    if (_phMobile.hasMatch(digits)) {
      return -50;
    }
    final nonSpace = line.replaceAll(' ', '');
    if (nonSpace.isNotEmpty) {
      final ratio = digits.length / nonSpace.length;
      if (ratio > 0.85) {
        score += 30;
      } else if (ratio > 0.5) {
        score += 10;
      }
    }
    // Grouped runs are the printed-reference style.
    if (_groupedRun.hasMatch(line)) {
      score += 40;
    }
    return score;
  }

  static GcashRefExtraction _result(String digits,
      {required bool matchedLabel, List<String>? candidates}) {
    final all = candidates ?? [digits];
    return GcashRefExtraction(
      reference: digits,
      candidates: all,
      matchedLabel: matchedLabel,
      displayGrouped: formatGrouped(digits),
    );
  }

  /// Format a reference number the way GCash receipts print it for display,
  /// so the seller can verify the value against the receipt before confirming:
  /// 13-digit references use GCash's 4-3-6 grouping (`4043676687260` →
  /// `4043 676 687260`); other lengths fall back to 4-digit chunks.
  ///
  /// The STORED value stays digits-only (spaces removed) —
  /// `gcash_reference_number` is a plain text column and clean digits are
  /// easier to compare/query.
  static String formatGrouped(String digits) {
    if (digits.length == idealDigits) {
      return '${digits.substring(0, 4)} '
          '${digits.substring(4, 7)} ${digits.substring(7)}';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
