import 'package:app/utils/demo_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('demoGcashReference', () {
    // The database accepts a GCash reference only as 12–13 digits and refuses
    // one it has already seen on a paid order or a deposit proof, so a demo
    // reference has to satisfy the same two rules a real one does.
    test('is 13 digits, as the server expects', () {
      final ref = demoGcashReference();
      expect(ref.length, 13);
      expect(RegExp(r'^[0-9]{13}$').hasMatch(ref), isTrue);
    });

    test('never repeats, even inside the same microsecond', () {
      final fixed = DateTime.utc(2026, 11, 19, 12);
      final refs = {
        demoGcashReference(now: fixed),
        demoGcashReference(now: fixed),
        demoGcashReference(now: fixed),
      };
      expect(refs.length, 3);
    });

    test('stays digits-only for a range of clocks', () {
      for (var i = 0; i < 50; i++) {
        final at = DateTime.utc(2026, 1, 1).add(Duration(milliseconds: i * 37));
        final ref = demoGcashReference(now: at);
        expect(RegExp(r'^[0-9]{13}$').hasMatch(ref), isTrue, reason: ref);
      }
    });
  });

  group('demoDepositScreenshotPath', () {
    // submit_bulk_reservation_deposit_proof refuses a path whose first segment
    // is not the reservation id, so a demo proof must keep that shape.
    test('starts with the reservation id and names itself as a demo', () {
      const reservationId = '8f14e45f-ceea-467a-9c1c-1f0c8c7a1b2c';
      final path = demoDepositScreenshotPath(reservationId);

      expect(path.split('/').first, reservationId);
      expect(path, contains('demo'));
    });
  });
}
