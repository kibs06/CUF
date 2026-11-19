import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/reservation_service.dart';
import '../../utils/bulk_reservation_pdf.dart';
import 'size_leader_rows.dart';

/// Shows the reservation list as a page before anything leaves the phone.
///
/// The share sheet used to open on a two-line text snippet, which is not what a
/// reseller's buy sheet is: they need the sizes, the customer, the deposit and
/// the id, laid out like a shopping list they can read at a glance. So the tap
/// now lands here first — a paper-like preview of exactly what the PDF will
/// contain — and the PDF is only built when the seller asks for it.
///
/// One reservation (from a card's Share) previews as a one-row list, so there is
/// a single layout and a single PDF shape to reason about.
Future<void> showBulkReservationShareSheet(
  BuildContext context, {
  required List<BulkReservation> items,
  String filterLabel = 'All',
  String? storeName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BulkReservationShareSheet(
      items: items,
      filterLabel: filterLabel,
      storeName: storeName,
    ),
  );
}

class _BulkReservationShareSheet extends StatefulWidget {
  final List<BulkReservation> items;
  final String filterLabel;
  final String? storeName;

  const _BulkReservationShareSheet({
    required this.items,
    required this.filterLabel,
    required this.storeName,
  });

  @override
  State<_BulkReservationShareSheet> createState() =>
      _BulkReservationShareSheetState();
}

class _BulkReservationShareSheetState
    extends State<_BulkReservationShareSheet> {
  bool _busy = false;
  String? _error;

  List<BulkReservation> get _items => widget.items;
  int get _units => _items.fold<int>(0, (sum, r) => sum + r.quantity);
  String get _fileName {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    return 'bulk-reservations-$day';
  }

  Future<Uint8List> _pdf() => buildBulkReservationPdf(
    reservations: _items,
    storeName: widget.storeName,
    filterLabel: widget.filterLabel,
  );

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _pdf();
      // The share sheet needs a real file; the OS copies it to whichever app
      // is chosen and reaps the temp dir afterwards.
      final dir = await Directory.systemTemp.createTemp('bulk-reservations');
      final file = File('${dir.path}/$_fileName.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Bulk reservations — ${widget.filterLabel}',
          text: widget.storeName == null
              ? 'Bulk reservations (${widget.filterLabel}).'
              : 'Bulk reservations — ${widget.storeName} (${widget.filterLabel}).',
        ),
      );
    } catch (e) {
      debugPrint('[Reservations] PDF share failed: $e');
      if (mounted) setState(() => _error = 'Could not share the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _pdf();
      final saved = await FileSaver.instance.saveAs(
        name: _fileName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.primary,
          content: Text(
            saved == null
                ? 'Download cancelled — no file was saved.'
                : 'Saved to $saved',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.secondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reservation list',
                    style: AppConstants.headlineStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_items.length} request${_items.length == 1 ? '' : 's'} · '
                    '$_units unit${_units == 1 ? '' : 's'} · ${widget.filterLabel}'
                    '${widget.storeName == null ? '' : ' · ${widget.storeName}'}',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: SellerTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // ── The page itself ─────────────────────────────────────
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  // The raised seller card, not a literal white: on the dark
                  // theme this page has to lift off the sheet, not glare.
                  color: SellerTheme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SellerTheme.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No reservations in this list.',
                          style: AppConstants.bodyStyle(
                            fontSize: 12.5,
                            color: AppConstants.secondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        shrinkWrap: true,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(
                            height: 1,
                            color: SellerTheme.cardBorder,
                          ),
                        ),
                        itemBuilder: (_, i) =>
                            _PreviewBlock(index: i + 1, reservation: _items[i]),
                      ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  _error!,
                  style: AppConstants.bodyStyle(
                    fontSize: 11.5,
                    color: AppConstants.error,
                  ),
                ),
              ),

            // ── Actions ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _download,
                        icon: const Icon(Icons.download_outlined, size: 17),
                        label: Text(
                          'Download PDF',
                          style: AppConstants.bodyStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SellerTheme.sageDark,
                          side: BorderSide(
                            color: SellerTheme.sage.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _share,
                        icon: _busy
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.ios_share, size: 17),
                        label: Text(
                          'Share PDF',
                          style: AppConstants.bodyStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: SellerTheme.sage,
                          disabledBackgroundColor: SellerTheme.sage.withValues(
                            alpha: 0.6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'The PDF carries the same details as this page.',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: SellerTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One reservation on the preview page — a shopping-list row group: what and
/// how many on top, then the facts the seller reads out to a supplier.
class _PreviewBlock extends StatelessWidget {
  final int index;
  final BulkReservation reservation;

  const _PreviewBlock({required this.index, required this.reservation});

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final rows = <(String, String)>[
      (
        'Customer',
        (r.customerName ?? '').trim().isEmpty
            ? 'A customer'
            : r.customerName!.trim(),
      ),
      if (r.createdAt != null) ('Requested', _stamp(r.createdAt!)),
      if (r.depositAmount != null)
        (
          'Deposit',
          '₱${r.depositAmount!.toStringAsFixed(2)} · ${r.depositStatus}'
              '${r.depositDeadline == null ? '' : ' · due ${_stamp(r.depositDeadline!)}'}',
        ),
      if (r.expiresAt != null && !r.isTerminal)
        (r.isApproved ? 'Held until' : 'Window ends', _stamp(r.expiresAt!)),
      if (r.note != null && r.note!.trim().isNotEmpty)
        ('Note', '"${r.note!.trim()}"'),
      if (r.rejectionReason != null && r.rejectionReason!.trim().isNotEmpty)
        ('Declined', r.rejectionReason!.trim()),
      ('ID', r.id),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '$index. ${r.quantity} units — '
                '${r.productName.isEmpty ? 'Product' : r.productName}',
                style: AppConstants.bodyStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SellerTheme.cardBorder.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                r.statusLabel.toUpperCase(),
                style: AppConstants.monoStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: SellerTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 82,
                  child: Text(
                    row.$1,
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: SellerTheme.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: AppConstants.bodyStyle(
                      fontSize: 11.5,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Sizes last and aligned: the line a supplier actually reads, so it
        // gets the leader rows rather than the usual key/value row.
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(
                'Sizes',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: SellerTheme.textMuted,
                ),
              ),
            ),
            Expanded(child: SizeLeaderRows(reservation: r)),
          ],
        ),
      ],
    );
  }

  static String _stamp(DateTime d) {
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
}
