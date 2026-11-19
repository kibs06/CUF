// Text and CSV for the seller's bulk-reservation queue.
//
// Kept out of the screen so the shape of an exported list is testable: a
// reseller's buy sheet is read on a phone, forward in a chat, or opened in a
// spreadsheet, and all three have to say the same thing. Pure functions only —
// the screen owns the share sheet and the file picker.
import '../services/reservation_service.dart';

/// CSV needs a cell that never breaks the row: quotes doubled, and any cell
/// containing a comma, quote or newline wrapped in quotes. Customer notes are
/// free text, so this is not hypothetical.
String csvCell(Object? value) {
  final text = (value ?? '')
      .toString()
      .replaceAll('\r\n', ' ')
      .replaceAll('\n', ' ');
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// The size breakdown as one line: `Black · 38: 4, Black · 39: 6`.
///
/// Colour is optional on a request, so a row without one reads `38: 4` rather
/// than a dangling separator.
String sizesSummary(BulkReservation r) => r.requestedSizes
    .map((s) {
      final colour = (s['color'] ?? '').toString().trim();
      final size = (s['size'] ?? '').toString().trim();
      final qty = (s['quantity'] ?? '').toString().trim();
      final label = size.isEmpty ? 'Size' : 'Size $size';
      return '${colour.isEmpty ? '' : '$colour · '}$label: $qty';
    })
    .join(', ');

/// The sizes as label/quantity pairs, for the surfaces that print one per line
/// instead of a comma-joined sentence.
///
/// The label is `EU: 35` (the scale the catalogue uses), prefixed with the
/// colour when the request names one, so a two-colour request still reads as
/// two separate lines. A size that already carries its scale is left alone
/// rather than becoming `EU: EU 35`.
List<({String label, String quantity})> sizeLeaderRows(BulkReservation r) {
  return r.requestedSizes.map((s) {
    final colour = (s['color'] ?? '').toString().trim();
    final rawSize = (s['size'] ?? '').toString().trim();
    final size = rawSize.isEmpty
        ? 'Size'
        : (rawSize.toUpperCase().startsWith('EU') ? rawSize : 'EU: $rawSize');
    final qty = (s['quantity'] ?? '').toString().trim();
    return (label: colour.isEmpty ? size : '$colour · $size', quantity: qty);
  }).toList();
}

/// One reservation as plain text — the unit both the per-card share button and
/// the whole-list share use, so a seller forwarding one request and forwarding
/// the queue never get two different descriptions of the same hold.
String reservationSummaryText(BulkReservation r) {
  final lines = <String>[
    '${r.quantity} units — ${r.productName.isEmpty ? 'Product' : r.productName}',
    'Status: ${r.statusLabel}',
    if (r.customerName != null && r.customerName!.trim().isNotEmpty)
      'Customer: ${r.customerName}',
    if (r.createdAt != null) 'Requested: ${_stamp(r.createdAt!)}',
    if (r.requestedSizes.isNotEmpty) 'Sizes: ${sizesSummary(r)}',
    if (r.note != null && r.note!.trim().isNotEmpty)
      'Note: "${r.note!.trim()}"',
    if (r.depositAmount != null)
      'Deposit: ₱${r.depositAmount!.toStringAsFixed(0)} (${r.depositStatus})'
          '${r.depositDeadline != null ? ' — due ${_stamp(r.depositDeadline!)}' : ''}',
    if (r.expiresAt != null && r.isApproved)
      'Held until: ${_stamp(r.expiresAt!)}',
    if (r.rejectionReason != null && r.rejectionReason!.trim().isNotEmpty)
      'Declined reason: ${r.rejectionReason!.trim()}',
  ];
  return lines.join('\n');
}

/// The whole [list] as a message, with a total so a reseller reading it in a
/// chat can see the size of the order at a glance.
String reservationsShareText(
  List<BulkReservation> list, {
  String? filterLabel,
  String? storeName,
}) {
  if (list.isEmpty) return 'No bulk reservations to share.';
  final units = list.fold<int>(0, (sum, r) => sum + r.quantity);
  final buffer = StringBuffer()
    ..writeln('Bulk reservations${storeName == null ? '' : ' — $storeName'}')
    ..writeln(
      '${list.length} request${list.length == 1 ? '' : 's'}'
      '${filterLabel == null ? '' : ' ($filterLabel)'} · $units units',
    )
    ..writeln();
  for (var i = 0; i < list.length; i++) {
    buffer
      ..writeln('${i + 1}. ${reservationSummaryText(list[i])}')
      ..writeln();
  }
  return buffer.toString().trimRight();
}

/// The [list] as spreadsheet rows, newest first as shown on screen.
///
/// A leading BOM is added by the caller-side file save, not here, so this
/// function stays plain text (Excel needs the BOM to read ₱ and accents).
String reservationsCsv(List<BulkReservation> list) {
  const header = [
    'Reservation id',
    'Product',
    'Quantity',
    'Status',
    'Customer',
    'Requested sizes',
    'Note',
    'Requested at',
    'Hold expires',
    'Deposit amount',
    'Deposit status',
    'Deposit deadline',
    'Declined reason',
  ];
  final rows = <String>[header.map(csvCell).join(',')];
  for (final r in list) {
    rows.add(
      [
        r.id,
        r.productName,
        r.quantity,
        r.statusLabel,
        r.customerName ?? '',
        sizesSummary(r),
        r.note ?? '',
        r.createdAt == null ? '' : _stamp(r.createdAt!),
        r.expiresAt == null ? '' : _stamp(r.expiresAt!),
        r.depositAmount == null ? '' : r.depositAmount!.toStringAsFixed(2),
        r.depositStatus,
        r.depositDeadline == null ? '' : _stamp(r.depositDeadline!),
        r.rejectionReason ?? '',
      ].map(csvCell).join(','),
    );
  }
  return rows.join('\n');
}

String _stamp(DateTime d) {
  final local = d.toLocal();
  final h24 = local.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final mm = local.minute.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $h:$mm ${h24 >= 12 ? 'PM' : 'AM'}';
}
