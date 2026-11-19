import 'dart:convert';

import 'package:app/services/reservation_service.dart';
import 'package:app/utils/bulk_reservation_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

BulkReservation _r({
  String id = 'e1056ef2-0000-4000-8000-000000000001',
  int quantity = 63,
  String productName = 'Tassel Loafer',
  String status = 'pending',
  String? note,
  List<Map<String, dynamic>> sizes = const [],
  double? deposit,
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
  customerName: 'Keith Abalo',
  depositAmount: deposit,
  depositStatus: deposit == null ? 'not_required' : 'unpaid',
  createdAt: DateTime(2026, 11, 20, 0, 18),
);

void main() {
  test('builds a real PDF for a list', () async {
    final bytes = await buildBulkReservationPdf(
      reservations: [
        _r(
          sizes: [
            {'color': 'Black', 'size': '38', 'quantity': 8},
            {'color': 'Black', 'size': '39', 'quantity': 10},
          ],
        ),
        _r(id: 'r2', quantity: 12, status: 'approved', deposit: 1500),
      ],
      storeName: 'VeeJay Footwear',
      filterLabel: 'All',
    );

    expect(bytes.length, greaterThan(1000));
    // Every PDF starts with the same five bytes.
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('an empty list still produces a page that says so', () async {
    final bytes = await buildBulkReservationPdf(reservations: const []);
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });

  test('sizesLine names colour and size, and says so when there are none', () {
    expect(
      sizesLine(
        _r(
          sizes: [
            {'color': 'Black', 'size': '38', 'quantity': 8},
          ],
        ),
      ),
      'Black · Size 38: 8',
    );
    expect(sizesLine(_r()), 'Not specified');
  });
}
