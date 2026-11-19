import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pos_receipt_format.dart';

/// Builds the customer's copy of one POS sale as a PDF.
///
/// The on-screen receipt is a proof while the customer stands at the counter;
/// this is the copy they take away, print or send. It is drawn from the same
/// order row the screen reads ([order] with its `order_items`), so the paper
/// and the screen can never disagree about what was sold.
///
/// Amounts are written `PHP 1,234.00` rather than with ₱, and every string is
/// folded into the base font's WinAnsi range by [_printable]: Helvetica has no
/// Unicode support, so a peso sign, an em dash in a store name or a curly
/// quote would otherwise be dropped without a word. Bundling a Unicode TTF is
/// the upgrade path if the shop wants the symbol on paper.
///
/// Pure: no widgets, no network, no file system — it returns bytes and lets
/// the caller decide whether they go to a printer or a share sheet.
Future<Uint8List> buildPosReceiptPdf({
  required Map<String, dynamic> order,
  required String storeName,
  String storeLocation = '',
  String sellerName = '',
}) async {
  final items = (order['order_items'] as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
  final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
  final method = paymentMethodLabel(order['payment_method']);
  final tendered = (order['amount_tendered'] as num?)?.toDouble();
  final change = (order['change_amount'] as num?)?.toDouble();
  final reference = _printable(
    (order['gcash_reference_number'] ?? '').toString().trim(),
  );
  final code = receiptCode(order['id']);
  final placedAt = receiptTime(order);
  final shop = _printable(
    storeName.trim().isEmpty ? 'Store' : storeName.trim(),
  );
  final location = _printable(storeLocation.trim());
  final cashier = _printable(sellerName.trim());

  final doc = pw.Document(
    title: 'Receipt $code',
    author: shop,
    subject: 'POS sales receipt',
  );

  const ink = PdfColor.fromInt(0xFF1F1B16);
  const muted = PdfColor.fromInt(0xFF6B5E52);
  final hairline = pw.BorderSide(
    color: const PdfColor.fromInt(0xFFD9D2C7),
    width: 0.6,
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.fromLTRB(12, 14, 12, 12),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────
          pw.Text(
            shop,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          if (location.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              location,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8.5, color: muted),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Container(height: 0.8, color: const PdfColor.fromInt(0xFFB9AE9E)),
          pw.SizedBox(height: 10),

          // ── Receipt identity ────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'SALES RECEIPT',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: muted,
                  letterSpacing: 1.2,
                ),
              ),
              if (placedAt != null)
                pw.Text(
                  receiptStamp(placedAt),
                  style: const pw.TextStyle(fontSize: 8.5, color: muted),
                ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Receipt #$code',
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          if (cashier.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'Cashier: $cashier',
              style: const pw.TextStyle(fontSize: 8.5, color: muted),
            ),
          ],
          pw.SizedBox(height: 12),

          // ── Items ───────────────────────────────────────────────────
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'ITEM',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 24,
                child: pw.Text(
                  'QTY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 78,
                child: pw.Text(
                  'AMOUNT',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: hairline)),
          ),
          pw.SizedBox(height: 6),
          ...items.map((item) => _itemRow(item, ink, muted)),
          if (items.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text(
                'No line items on this sale.',
                style: const pw.TextStyle(fontSize: 9, color: muted),
              ),
            ),
          pw.SizedBox(height: 6),
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: hairline)),
          ),
          pw.SizedBox(height: 8),

          // ── Total ───────────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                  letterSpacing: 0.6,
                ),
              ),
              pw.Text(
                _money(total),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _line('Paid via', method, ink, muted),
          if (tendered != null) _line('Cash tendered', _money(tendered), ink, muted),
          if (change != null) _line('Change', _money(change), ink, muted),
          if (reference.isNotEmpty) _line('GCash ref', reference, ink, muted),
          pw.SizedBox(height: 14),

          // ── Footer ──────────────────────────────────────────────────
          pw.Text(
            'Thank you for shopping at $shop.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Keep this receipt as your proof of purchase.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7.5, color: muted),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

/// One line item: name, size and unit price on the left, quantity, amount.
pw.Widget _itemRow(
  Map<String, dynamic> item,
  PdfColor ink,
  PdfColor muted,
) {
  final name = _printable((item['product_name'] ?? 'Product').toString());
  final size = _printable((item['size'] ?? '').toString());
  final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
  final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;

  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                name,
                style: pw.TextStyle(fontSize: 9.5, color: ink),
              ),
              if (size.isNotEmpty)
                pw.Text(
                  'Size $size',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              if (quantity > 1)
                pw.Text(
                  '${_money(unitPrice)} each',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
            ],
          ),
        ),
        pw.SizedBox(
          width: 24,
          child: pw.Text(
            '$quantity',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9.5, color: ink),
          ),
        ),
        pw.SizedBox(
          width: 78,
          child: pw.Text(
            _money(unitPrice * quantity),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 9.5, color: ink),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _line(String label, String value, PdfColor ink, PdfColor muted) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8.5, color: muted)),
        pw.Text(value, style: pw.TextStyle(fontSize: 9, color: ink)),
      ],
    ),
  );
}

/// Fold a string into what the PDF base fonts can actually draw.
///
/// Helvetica is a Type1 font with WinAnsi encoding: ASCII plus Latin-1. The
/// characters this app really produces outside that range are typographic
/// dashes and quotes, the peso sign and the ellipsis, so those are translated
/// into their plain equivalents instead of vanishing from the paper. Anything
/// else outside Latin-1 becomes `?` — visible, which is the honest failure.
String _printable(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    switch (rune) {
      case 0x2010:
      case 0x2011:
      case 0x2012:
      case 0x2013:
      case 0x2014:
        buffer.write('-');
      case 0x2018:
      case 0x2019:
        buffer.write("'");
      case 0x201C:
      case 0x201D:
        buffer.write('"');
      case 0x2026:
        buffer.write('...');
      case 0x20B1:
        buffer.write('PHP ');
      case 0x00A0:
        buffer.write(' ');
      default:
        if (rune < 0x20) break;
        buffer.write(rune > 0xFF ? '?' : String.fromCharCode(rune));
    }
  }
  return buffer.toString();
}

/// Peso amounts as the base font can print them: [formatPeso] writes ₱,
/// which Helvetica has no glyph for, so this path folds it to `PHP `.
String _money(num value) => _printable(formatPeso(value));