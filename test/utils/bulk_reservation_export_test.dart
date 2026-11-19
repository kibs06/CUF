import 'package:app/services/reservation_service.dart';
import 'package:app/utils/bulk_reservation_export.dart';
import 'package:flutter_test/flutter_test.dart';

BulkReservation _r({
  String id = 'r1',
  int quantity = 63,
  String productName = 'Tassel Loafer',
  String status = 'pending',
  String? customerName = 'Keith Abalo',
  String? note,
  List<Map<String, dynamic>> sizes = const [],
  double? deposit,
  String depositStatus = 'not_required',
  DateTime? createdAt,
  DateTime? expiresAt,
  DateTime? depositDeadline,
  String? rejectionReason,
}) => BulkReservation(
  id: id,
  customerId: 'c1',
  storeId: 's1',
  productId: 'p1',
  quantity: quantity,
  requestedSizes: sizes,
  note: note,
  status: status,
  productName: productName,
  customerName: customerName,
  depositAmount: deposit,
  depositStatus: depositStatus,
  createdAt: createdAt ?? DateTime(2026, 11, 20, 9, 5),
  expiresAt: expiresAt,
  depositDeadline: depositDeadline,
  rejectionReason: rejectionReason,
);

void main() {
  group('sizesSummary', () {
    test('names the colour when the request carries one', () {
      expect(
        sizesSummary(
          _r(
            sizes: [
              {'color': 'Black', 'size': '38', 'quantity': 4},
              {'color': 'Black', 'size': '39', 'quantity': 6},
            ],
          ),
        ),
        'Black · Size 38: 4, Black · Size 39: 6',
      );
    });

    test(
      'a request without a colour reads as a plain size, not a dangling dot',
      () {
        expect(
          sizesSummary(
            _r(
              sizes: [
                {'size': '40', 'quantity': 18},
              ],
            ),
          ),
          'Size 40: 18',
        );
      },
    );
  });

  group('sizeLeaderRows', () {
    test('gives one aligned row per size, the scale prefixed once', () {
      final rows = sizeLeaderRows(
        _r(
          sizes: [
            {'size': '35', 'quantity': 9},
            {'size': '36', 'quantity': 9},
            {'size': '39', 'quantity': 10},
          ],
        ),
      );
      expect(rows.map((r) => r.label).toList(), ['EU: 35', 'EU: 36', 'EU: 39']);
      expect(rows.map((r) => r.quantity).toList(), ['9', '9', '10']);
    });

    test('keeps the colour on the row it belongs to', () {
      final rows = sizeLeaderRows(
        _r(
          sizes: [
            {'color': 'Black', 'size': '38', 'quantity': 8},
            {'color': 'Brown', 'size': '38', 'quantity': 4},
          ],
        ),
      );
      expect(rows.first.label, 'Black · EU: 38');
      expect(rows.last.label, 'Brown · EU: 38');
    });

    test('does not double the scale on a size that already carries it', () {
      final rows = sizeLeaderRows(
        _r(
          sizes: [
            {'size': 'EU 41', 'quantity': 2},
          ],
        ),
      );
      expect(rows.single.label, 'EU 41');
    });

    test('no sizes means no rows', () {
      expect(sizeLeaderRows(_r()), isEmpty);
    });
  });

  group('reservationSummaryText', () {
    test('leads with units and product, then only the facts it has', () {
      final text = reservationSummaryText(_r());
      expect(text.split('\n').first, '63 units — Tassel Loafer');
      expect(text, contains('Status: Awaiting approval'));
      expect(text, contains('Customer: Keith Abalo'));
      expect(text, isNot(contains('Note:')));
      expect(text, isNot(contains('Deposit:')));
    });

    test('carries the deposit, hold deadline and decline reason when set', () {
      final text = reservationSummaryText(
        _r(
          status: 'awaiting_deposit',
          deposit: 1500,
          depositStatus: 'unpaid',
          depositDeadline: DateTime(2026, 11, 21, 9, 5),
        ),
      );
      expect(text, contains('Deposit: ₱1500 (unpaid)'));
      expect(text, contains('due 2026-11-21 9:05 AM'));

      final declined = reservationSummaryText(
        _r(status: 'rejected', rejectionReason: 'Not enough stock'),
      );
      expect(declined, contains('Declined reason: Not enough stock'));
    });
  });

  group('reservationsShareText', () {
    test('totals the units and counts the requests', () {
      final text = reservationsShareText(
        [_r(), _r(id: 'r2', quantity: 12)],
        storeName: 'VeeJay Footwear',
        filterLabel: 'All',
      );
      expect(text, contains('Bulk reservations — VeeJay Footwear'));
      expect(text, contains('2 requests (All) · 75 units'));
      expect(text, contains('1. 63 units — Tassel Loafer'));
      expect(text, contains('2. 12 units — Tassel Loafer'));
    });

    test('says so plainly when there is nothing to share', () {
      expect(reservationsShareText(const []), 'No bulk reservations to share.');
    });
  });

  group('reservationsCsv', () {
    test('writes a header and one row per reservation', () {
      final csv = reservationsCsv([
        _r(
          sizes: [
            {'color': 'Black', 'size': '38', 'quantity': 4},
          ],
        ),
        _r(id: 'r2', quantity: 12, status: 'approved'),
      ]);
      final lines = csv.split('\n');
      expect(lines.length, 3);
      expect(lines.first, startsWith('Reservation id,Product,Quantity'));
      expect(lines[1], contains('r1,Tassel Loafer,63,Awaiting approval'));
      expect(lines[1], contains('Black · Size 38: 4'));
      expect(lines[2], contains('r2,Tassel Loafer,12,Reserved'));
    });

    test('a note with a comma stays in its own cell, quotes doubled', () {
      final csv = reservationsCsv([
        _r(note: 'Need these by Friday, "rush" if possible'),
      ]);
      expect(csv, contains('"Need these by Friday, ""rush"" if possible"'));
      // Still exactly two lines — the comma did not fan the row out.
      expect(csv.split('\n').length, 2);
    });

    test('keeps colour and size apart from the note column', () {
      final csv = reservationsCsv([
        _r(
          sizes: [
            {'color': 'Brown', 'size': '41', 'quantity': 2},
          ],
          note: 'plain',
        ),
      ]);
      expect(csv.split('\n')[1], contains('Brown · Size 41: 2,plain'));
    });
  });
}
