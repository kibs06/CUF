import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/store.dart';

/// Unit tests for Store's schedule-aware open status (isOpenAt / isOpenNow).
///
/// Regression guard for the bug where a store kept showing "Open Now" well
/// past its posted close time (e.g. 7:11 PM with 8:00 AM–5:30 PM hours),
/// because the UI showed the raw `is_open` DB flag that nothing refreshed.
void main() {
  Store makeStore({
    bool isOpen = true,
    bool autoScheduleEnabled = true,
    String? openTime = '08:00:00',
    String? closeTime = '17:30:00',
    bool manualOverride = false,
  }) {
    return Store(
      id: 'store-1',
      name: 'Demo Store',
      location: 'Manila',
      createdAt: DateTime(2026, 1, 1),
      isOpen: isOpen,
      autoScheduleEnabled: autoScheduleEnabled,
      openTime: openTime,
      closeTime: closeTime,
      manualOverride: manualOverride,
    );
  }

  group('isOpenAt — normal schedule 08:00–17:30', () {
    test('open during the day', () {
      expect(makeStore().isOpenAt(DateTime(2026, 8, 17, 10, 0)), isTrue);
    });

    test('closed before opening', () {
      expect(makeStore().isOpenAt(DateTime(2026, 8, 17, 7, 59)), isFalse);
    });

    test('open exactly at opening time (open is inclusive)', () {
      expect(makeStore().isOpenAt(DateTime(2026, 8, 17, 8, 0)), isTrue);
    });

    test('closed exactly at closing time (close is exclusive)', () {
      expect(makeStore().isOpenAt(DateTime(2026, 8, 17, 17, 30)), isFalse);
    });

    test('open just before closing', () {
      expect(makeStore().isOpenAt(DateTime(2026, 8, 17, 17, 29)), isTrue);
    });

    test('closed after closing time — the reported bug (7:11 PM)', () {
      expect(makeStore().isOpenAt(DateTime(2026, 8, 17, 19, 11)), isFalse);
    });
  });

  group('isOpenAt — overnight schedule 18:00–02:00', () {
    Store overnight() => makeStore(openTime: '18:00:00', closeTime: '02:00:00');

    test('open in the evening', () {
      expect(overnight().isOpenAt(DateTime(2026, 8, 17, 20, 0)), isTrue);
    });

    test('open after midnight', () {
      expect(overnight().isOpenAt(DateTime(2026, 8, 18, 1, 0)), isTrue);
    });

    test('open exactly at opening time', () {
      expect(overnight().isOpenAt(DateTime(2026, 8, 17, 18, 0)), isTrue);
    });

    test('closed exactly at closing time', () {
      expect(overnight().isOpenAt(DateTime(2026, 8, 18, 2, 0)), isFalse);
    });

    test('closed in the middle of the day', () {
      expect(overnight().isOpenAt(DateTime(2026, 8, 17, 12, 0)), isFalse);
    });

    test('closed just before opening', () {
      expect(overnight().isOpenAt(DateTime(2026, 8, 17, 17, 59)), isFalse);
    });
  });

  group('isOpenAt — precedence', () {
    test('no schedule → falls back to the is_open flag', () {
      expect(
        makeStore(openTime: null, closeTime: null, isOpen: false)
            .isOpenAt(DateTime(2026, 8, 17, 10, 0)),
        isFalse,
      );
      expect(
        makeStore(openTime: null, closeTime: null, isOpen: true)
            .isOpenAt(DateTime(2026, 8, 17, 10, 0)),
        isTrue,
      );
    });

    test('manual override (seller closed) wins inside hours', () {
      // Seller manually closed at 10 AM, within posted hours.
      expect(
        makeStore(isOpen: false, manualOverride: true)
            .isOpenAt(DateTime(2026, 8, 17, 10, 0)),
        isFalse,
      );
    });

    test('manual override (seller opened) wins outside hours', () {
      // Seller manually opened at 8 PM, after the 5:30 PM close.
      expect(
        makeStore(isOpen: true, manualOverride: true)
            .isOpenAt(DateTime(2026, 8, 17, 20, 0)),
        isTrue,
      );
    });

    test('unparseable hours → falls back to the is_open flag', () {
      expect(
        makeStore(openTime: 'garbage', closeTime: null, isOpen: true)
            .isOpenAt(DateTime(2026, 8, 17, 19, 11)),
        isTrue,
      );
    });
  });

  group('isOpenNow', () {
    test('store without hours reflects the raw is_open flag', () {
      expect(
        makeStore(openTime: null, closeTime: null, isOpen: false).isOpenNow,
        isFalse,
      );
      expect(
        makeStore(openTime: null, closeTime: null, isOpen: true).isOpenNow,
        isTrue,
      );
    });

    test('returns a bool for a scheduled store', () {
      expect(makeStore().isOpenNow, isA<bool>());
    });
  });
}
