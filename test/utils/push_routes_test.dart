import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/push_routes.dart';

void main() {
  group('screenForPushType', () {
    test('seller reservation pushes land on the reservation queue', () {
      for (final type in [
        'bulk_reservation_request',
        'bulk_reservation_deposit_proof',
        'bulk_reservation',
        'bulk_reservation_deposit',
      ]) {
        expect(screenForPushType(type), 'seller_reservations', reason: type);
      }
    });

    test('customer reservation pushes land on their reservation list', () {
      for (final type in [
        'bulk_reservation_approved',
        'bulk_reservation_declined',
        'bulk_reservation_deposit_declined',
        'bulk_reservation_deposit_confirmed',
      ]) {
        expect(screenForPushType(type), 'my_reservations', reason: type);
      }
    });

    test('unrelated and missing types stay unrouted', () {
      expect(screenForPushType('order_shipped'), isNull);
      expect(screenForPushType(null), isNull);
    });
  });
}
