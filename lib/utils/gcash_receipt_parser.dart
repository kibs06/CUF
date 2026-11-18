/// Receipt-side extraction for the manual GCash proof form.
///
/// The customer attaches the screenshot of the transfer they made; this reads
/// the two fields the form actually needs out of the OCR text so they do not
/// have to retype them:
///
///   * the **reference number** — delegated to [GcashRefExtractor], which is
///     already the app's single answer to "which number on this receipt is the
///     Ref No.?" (label-first, then a scored fallback);
///   * the **amount sent** — the money-looking figure on the receipt, scored so
///     an "Amount Sent" line beats a balance, a fee or a stray price;
///   * the **time the receipt prints** — read so the reviewer can tell when the
///     transfer happened, never surfaced as a field the customer edits.
///
/// The receipt's clock is a CLAIM, not evidence: it comes out of an image the
/// customer could have edited, so it is stored as such. The time the proof
/// actually arrived is stamped by the database, not by this app.
///
/// Nothing here decides whether the payment is valid. The amount is returned so
/// the form can fill the field and say plainly whether it equals the order
/// total; the server re-checks the same equality when the proof is submitted.
///
/// The form shows the reference and amount read-only: they come from the image
/// and cannot be typed over, so a parse miss is answered with a clearer
/// screenshot rather than by hand (the sender name is still typed).
///
/// Pure Dart (no platform calls) so it is unit-testable without ML Kit.
library;

import 'gcash_ref_extractor.dart';

/// What a receipt screenshot yielded.
class GcashReceiptParse {
  /// Reference-number result (may be undetected).
  final GcashRefExtraction reference;

  /// Amount read off the receipt, in pesos. Null when no figure was read.
  final double? amount;

  /// The text line the amount came from, for the read-back in the UI.
  final String? amountLine;

  /// The moment the receipt itself says the transfer happened, as a UTC
  /// instant. Null when the receipt carries no readable clock — a date on its
  /// own is not a time.
  ///
  /// The printed clock is Philippine time, so the wall-clock fields are read
  /// as Asia/Manila (UTC+8) rather than as this phone's local time: a device
  /// set to another timezone must not shift a claim about a receipt printed
  /// in the Philippines. The value is already normalised to UTC, so
  /// `toUtc()` on it changes nothing.
  ///
  /// This is only ever what the image claims. It is sent with the proof so a
  /// verifier can compare it with when the proof arrived, and it is never
  /// shown to the customer as an editable field.
  final DateTime? paidAt;

  /// The line [paidAt] was read from, so the value can be traced back.
  final String? paidAtLine;

  const GcashReceiptParse({
    this.reference = GcashRefExtraction.empty,
    this.amount,
    this.amountLine,
    this.paidAt,
    this.paidAtLine,
  });

  /// Nothing read — the form falls back to manual entry.
  static const GcashReceiptParse empty = GcashReceiptParse();

  /// True when the screenshot yielded nothing usable — the form asks for the
  /// values to be typed in instead.
  bool get isEmpty => !reference.detected && amount == null;

  bool get hasAmount => amount != null;
}

class GcashReceiptParser {
  /// A money figure with two decimals, optionally preceded by a peso marker.
  /// The decimals are required: GCash prints `PHP 650.00`, and insisting on
  /// them keeps a bare digit run (i.e. a reference number) from being read as
  /// an amount. The lookarounds stop the match from starting (or ending) in the
  /// middle of a longer number — `4043.67` must read as 4043.67, never 43.67.
  static final RegExp _money = RegExp(
    r'(?<![0-9])(?:₱|PHP|Php|php|P)?\s*([0-9]+(?:,[0-9]{3})*\.[0-9]{2})(?![0-9])',
  );

  /// Lines that carry an amount, strongest first. GCash's send receipt says
  /// "Amount Sent"; a cash-in receipt says "Total Amount".
  static const List<String> _strongWords = [
    'amount sent',
    'total amount',
    'amount received',
    'you sent',
    'sent money',
  ];
  static const List<String> _weakWords = ['amount', 'total', 'sent'];

  /// Never an amount, whichever half of the row they appear on: a reference
  /// line, and figures that describe something other than what left the
  /// wallet.
  static const List<String> _neverMoneyWords = [
    'ref no',
    'reference',
    'balance',
    'fee',
    'charge',
    'available',
  ];

  /// Context-only exclusions. These label a different figure, but they are only
  /// trusted on the line ABOVE a bare value — a "Ref No." label above a figure
  /// must not hide it, because GCash prints the reference directly under the
  /// amount.
  static const List<String> _notTheTransferWords = [
    'balance',
    'fee',
    'charge',
    'available',
  ];

  /// Parse OCR lines from a GCash receipt screenshot.
  static GcashReceiptParse parse(List<String> lines) {
    final reference = GcashRefExtractor.extract(lines);
    final hit = _findAmount(lines, reference.reference);
    final stamp = _findDateTime(lines);
    if (hit == null) {
      return GcashReceiptParse(
        reference: reference,
        paidAt: stamp?.at,
        paidAtLine: stamp?.line,
      );
    }
    return GcashReceiptParse(
      reference: reference,
      amount: hit.amount,
      amountLine: hit.line,
      paidAt: stamp?.at,
      paidAtLine: stamp?.line,
    );
  }

  /// Month names as GCash prints them; only the first three letters matter.
  static const List<String> _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// A receipt stamp: `Nov 17, 2026 07:41 AM` or `17 Nov 2026, 7:41 PM`, with
  /// the clock optional so a date-only receipt is not mistaken for a time.
  static final RegExp _stamp = RegExp(
    r'(?:'
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+'
    r'(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})'
    r'|'
    r'(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+'
    r'(\d{4})'
    r')'
    r'(?:[\s,]+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]\.?m\.?)?)?',
    caseSensitive: false,
  );

  /// The printed clock's offset. The Philippines has been a single zone at
  /// UTC+8 with no daylight saving since 1978, so this is a constant and not a
  /// lookup — there is no date on a receipt where +08:00 is wrong.
  static const Duration _manilaOffset = Duration(hours: 8);

  /// The first line that carries a month, a day, a year and a clock.
  static ({DateTime at, String line})? _findDateTime(List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = _stamp.firstMatch(line);
      if (match == null) continue;

      final month = _monthIndex(match.group(1) ?? match.group(5)!);
      final day = int.tryParse(match.group(2) ?? match.group(4)!);
      final year = int.tryParse(match.group(3) ?? match.group(6)!);
      final hourText = match.group(7);
      final minuteText = match.group(8);
      if (month == null || day == null || year == null) continue;
      // No clock, no time: a bare date cannot pin a transfer to an hour, and
      // guessing 00:00 would invent evidence.
      if (hourText == null || minuteText == null) continue;

      var hour = int.parse(hourText);
      final minute = int.parse(minuteText);
      final half = (match.group(10) ?? '').toLowerCase().replaceAll('.', '');
      if (half == 'pm' && hour < 12) hour += 12;
      if (half == 'am' && hour == 12) hour = 0;
      if (hour > 23 || minute > 59) continue;

      // Reject impossible calendar days (Feb 31) instead of letting DateTime
      // roll them forward into March. Built as UTC only so the calendar check
      // cannot be bent by the device's zone; the offset is applied after.
      final wall = DateTime.utc(year, month, day, hour, minute);
      if (wall.year != year || wall.month != month || wall.day != day) continue;
      // 07:41 printed in Manila is 23:41Z the day before — the instant the
      // receipt means, whichever timezone this phone is set to.
      return (at: wall.subtract(_manilaOffset), line: line);
    }
    return null;
  }

  static int? _monthIndex(String word) {
    final lower = word.toLowerCase();
    if (lower.length < 3) return null;
    final index = _months.indexOf(lower.substring(0, 3));
    return index < 0 ? null : index + 1;
  }

  /// Pick the most likely "amount sent" figure. Returns null when no line
  /// reads as money at all (the caller then leaves the field to the customer).
  static ({double amount, String line})? _findAmount(
    List<String> lines,
    String? referenceDigits,
  ) {
    ({double amount, String line, int score})? best;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();

      // The label and the figure are usually on separate lines — GCash prints
      // "Amount Sent" and then "PHP 650.00" — so the nearest line above is
      // part of this figure's context.
      final above = _labelAbove(lines, i);

      // A reference line is a number, not money (it has no decimals, so the
      // money pattern already refuses it; this is belt-and-braces), and a
      // balance or a fee is a different figure from what the customer sent.
      if (_neverMoneyWords.any(lower.contains)) continue;
      if (_notTheTransferWords.any(above.contains)) continue;

      final match = _money.firstMatch(line);
      if (match == null) continue;
      final amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (amount == null || amount <= 0) continue;

      // The same digits as the reference number are never the amount.
      final digits = match.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      if (referenceDigits != null && digits == referenceDigits) continue;

      var score = 0;
      if (_strongWords.any(lower.contains) ||
          _strongWords.any(above.contains)) {
        score += 60;
      } else if (_weakWords.any(lower.contains) ||
          _weakWords.any(above.contains)) {
        score += 30;
      }
      // A line that is essentially just the figure ("₱650.00") is a strong
      // receipt layout; the peso marker on its own adds a little.
      final nonSpace = line.replaceAll(' ', '');
      if (nonSpace.length <= 12) score += 15;
      if (line.contains('₱') || lower.startsWith('php')) score += 5;

      if (best == null || score > best.score) {
        best = (amount: amount, line: line, score: score);
      }
    }
    if (best == null) return null;
    return (amount: best.amount, line: best.line);
  }

  /// The nearest non-empty line above [index], lowercased — the label half of
  /// a receipt row whose value sits on the next line.
  static String _labelAbove(List<String> lines, int index) {
    for (var i = index - 1; i >= 0; i--) {
      final text = lines[i].trim();
      if (text.isNotEmpty) return text.toLowerCase();
    }
    return '';
  }
}
