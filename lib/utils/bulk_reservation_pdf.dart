import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/reservation_service.dart';
import 'bulk_reservation_export.dart';

/// Builds a bulk-reservation list as a PDF the seller can send or file.
///
/// The sheet it prints is the same "shopping list" the preview shows: one
/// block per reservation, every fact the card reveals when expanded, and a
/// header that says which slice of the queue it is. Both come from the same
/// [BulkReservation] rows, so paper and screen cannot disagree.
///
/// Helvetica has no Unicode coverage, so every string is folded by
/// [_printable] — `₱` becomes `PHP`, an em dash becomes `-`. (Same trade-off
/// as the POS receipt; a bundled TTF is the upgrade path if the peso sign is
/// ever needed on paper.)
Future<Uint8List> buildBulkReservationPdf({
  required List<BulkReservation> reservations,
  String? storeName,
  String filterLabel = 'All',
  DateTime? generatedAt,
}) async {
  final when = generatedAt ?? DateTime.now();
  final units = reservations.fold<int>(0, (sum, r) => sum + r.quantity);
  final shop = _printable((storeName ?? '').trim());

  final doc = pw.Document(
    title: 'Bulk reservations',
    author: shop.isEmpty ? 'CUFMAI' : shop,
    subject: 'Bulk reservation list',
  );

  const ink = PdfColor.fromInt(0xFF1F1B16);
  const muted = PdfColor.fromInt(0xFF6B5E52);
  const accent = PdfColor.fromInt(0xFF4F6B35);
  const hairline = PdfColor.fromInt(0xFFD9D2C7);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                _printable(
                  'Bulk reservations${shop.isEmpty ? '' : ' - $shop'}',
                ),
                style: const pw.TextStyle(fontSize: 9, color: muted),
              ),
            ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _printable('CUFMAI · ${_stamp(when)}'),
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        // ── Header ────────────────────────────────────────────────────
        pw.Text(
          'Bulk reservations',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        if (shop.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              shop,
              style: const pw.TextStyle(fontSize: 12, color: muted),
            ),
          ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            _printable(
              '$filterLabel · ${reservations.length} '
              'request${reservations.length == 1 ? '' : 's'} · $units '
              'unit${units == 1 ? '' : 's'}',
            ),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
        ),
        pw.SizedBox(height: 14),

        if (reservations.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: hairline, width: 0.7),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'No reservations in this list.',
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
          ),

        // ── One block per reservation ─────────────────────────────────
        for (var i = 0; i < reservations.length; i++) ...[
          _reservationBlock(reservations[i], index: i + 1),
          pw.SizedBox(height: 10),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _reservationBlock(BulkReservation r, {required int index}) {
  const ink = PdfColor.fromInt(0xFF1F1B16);
  const muted = PdfColor.fromInt(0xFF6B5E52);
  const hairline = PdfColor.fromInt(0xFFD9D2C7);

  final rows = <List<String>>[
    [
      'Customer',
      _printable(
        (r.customerName ?? '').trim().isEmpty
            ? 'A customer'
            : r.customerName!.trim(),
      ),
    ],
    ['Requested', r.createdAt == null ? '—' : _stamp(r.createdAt!)],
    if (r.depositAmount != null)
      [
        'Deposit',
        'PHP ${r.depositAmount!.toStringAsFixed(2)} · ${r.depositStatus}'
            '${r.depositDeadline == null ? '' : ' · due ${_stamp(r.depositDeadline!)}'}',
      ],
    if (r.expiresAt != null && !r.isTerminal)
      [r.isApproved ? 'Held until' : 'Window ends', _stamp(r.expiresAt!)],
    if (r.rejectionReason != null && r.rejectionReason!.trim().isNotEmpty)
      ['Declined', _printable(r.rejectionReason!.trim())],
    if (r.note != null && r.note!.trim().isNotEmpty)
      ['Note', _printable('"${r.note!.trim()}"')],
    ['ID', r.id],
  ];

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: hairline, width: 0.7),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                _printable(
                  '$index. ${r.quantity} units - '
                  '${r.productName.isEmpty ? 'Product' : r.productName}',
                ),
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: hairline, width: 0.7),
                borderRadius: pw.BorderRadius.circular(20),
              ),
              child: pw.Text(
                _printable(r.statusLabel.toUpperCase()),
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: muted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        for (final row in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 78,
                  child: pw.Text(
                    row[0],
                    style: const pw.TextStyle(fontSize: 8.5, color: muted),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    row[1],
                    style: const pw.TextStyle(fontSize: 9, color: ink),
                  ),
                ),
              ],
            ),
          ),
        // Sizes one per line with a leader to the count — the same shape the
        // preview page and the card's details block show.
        for (final size in sizeLeaderRows(r))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: 78,
                  child: pw.Text(
                    _printable(size.label),
                    style: const pw.TextStyle(fontSize: 8.5, color: muted),
                  ),
                ),
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.symmetric(horizontal: 6),
                    height: 0.5,
                    color: hairline,
                  ),
                ),
                pw.Text(
                  _printable(size.quantity),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// `Black · Size 38: 4, Black · Size 39: 9` — the same shape the card shows.
String sizesLine(BulkReservation r) {
  if (r.requestedSizes.isEmpty) return 'Not specified';
  return r.requestedSizes
      .map((s) {
        final colour = (s['color'] ?? '').toString().trim();
        final size = (s['size'] ?? '').toString().trim();
        final qty = (s['quantity'] ?? '').toString().trim();
        return '${colour.isEmpty ? '' : '$colour · '}Size $size: $qty';
      })
      .join(', ');
}

String _stamp(DateTime d) {
  final local = d.toLocal();
  const months = [
    '',
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
  final h24 = local.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final mm = local.minute.toString().padLeft(2, '0');
  return '${months[local.month]} ${local.day}, ${local.year} · $h:$mm '
      '${h24 >= 12 ? 'PM' : 'AM'}';
}

/// Folds text into the base PDF font's WinAnsi range so nothing silently
/// disappears. The peso sign is the one that matters: a seller reading
/// "PHP 1,500.00" believes the number; a dropped glyph leaves " 1,500.00".
String _printable(String input) {
  var text = input;
  const replacements = {
    '₱': 'PHP ',
    '\u2014': '-', // em dash
    '\u2013': '-', // en dash
    '·': '-',
    '\u2018': "'",
    '\u2019': "'",
    '\u201C': '"',
    '\u201D': '"',
    '\u2026': '...',
    '\u00A0': ' ',
  };
  replacements.forEach((from, to) => text = text.replaceAll(from, to));
  // Last resort: anything still outside Latin-1 becomes '?' rather than a
  // missing glyph — visible to the reader, and never a silent truncation.
  return String.fromCharCodes(text.runes.map((r) => r <= 0xFF ? r : 0x3F));
}
