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
///     an "Amount Sent" line beats a balance, a fee or a stray price.
///
/// Nothing here decides whether the payment is valid. The amount is returned so
/// the form can PRE-FILL the field and say plainly whether it equals the order
/// total; the server re-checks the same equality when the proof is submitted.
/// A parse miss is never fatal — manual typing stays available.
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

  const GcashReceiptParse({
    this.reference = GcashRefExtraction.empty,
    this.amount,
    this.amountLine,
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
    if (hit == null) {
      return GcashReceiptParse(reference: reference);
    }
    return GcashReceiptParse(
      reference: reference,
      amount: hit.amount,
      amountLine: hit.line,
    );
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
