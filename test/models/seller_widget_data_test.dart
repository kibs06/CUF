import 'package:app/models/seller_widget_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seller home-screen widget's payload.
///
/// This file guards the two things about the payload that are *decisions*
/// rather than plumbing, and that nothing else in the app would catch:
///
///  * **The clock and the money are formatted here, not natively.** A widget
///    cannot format — Android's `RemoteViews` renders the strings it is handed,
///    and the iOS timeline provider reads a plist — so a wrong label is wrong on
///    every phone with no stack trace anywhere. These are the tests that pin it.
///  * **The writer and the eraser must agree.** `toWidgetValues()` writes the
///    payload; `SellerWidgetKeys.all` is what `clear()` walks to erase it. A key
///    added to one and not the other leaves another account's numbers on a
///    home screen after logout, which is the failure this feature can least
///    afford.
void main() {
  SellerWidgetData sample({
    bool hasStore = true,
    double todayRevenue = 12500,
    int pendingOrders = 3,
    int pendingCustoms = 2,
    int pendingReservations = 1,
    int activePickups = 4,
    int lowStockCount = 5,
    int unreadNotifications = 7,
    DateTime? updatedAt,
  }) {
    return SellerWidgetData(
      hasStore: hasStore,
      storeName: 'Sole Studio',
      todayRevenue: todayRevenue,
      pendingOrders: pendingOrders,
      pendingCustoms: pendingCustoms,
      pendingReservations: pendingReservations,
      activePickups: activePickups,
      lowStockCount: lowStockCount,
      unreadNotifications: unreadNotifications,
      updatedAt: updatedAt ?? DateTime(2026, 10, 12, 14, 31),
    );
  }

  group('SellerWidgetKeys — the wire format', () {
    test('every key the writer emits is also one the eraser knows', () {
      // The round trip that matters: write, then clear, and nothing survives.
      final written = sample().toWidgetValues().keys.toSet();
      final erased = SellerWidgetKeys.all.toSet();

      expect(
        written.difference(erased),
        isEmpty,
        reason: 'a written key that clear() does not erase survives a logout — '
            'the previous account\'s numbers stay on the home screen',
      );
      expect(
        erased.difference(written),
        isEmpty,
        reason: 'clear() erases a key nothing writes; harmless, but it means '
            'the two lists have already drifted',
      );
    });

    test('keys are namespaced, so they cannot collide with another plugin\'s', () {
      // home_widget shares ONE preferences store across every widget in the
      // app. A bare "orders" would be a collision waiting for the next widget.
      for (final key in SellerWidgetKeys.all) {
        expect(key, startsWith('seller_'), reason: '$key is not namespaced');
      }
    });

    test('the key list has no duplicates', () {
      // A duplicate would make clear() do the same work twice and, worse, hide
      // a typo that silently stopped erasing one field.
      expect(SellerWidgetKeys.all.toSet().length, SellerWidgetKeys.all.length);
    });
  });

  group('attentionCount — the badge number', () {
    test('sums every queue the seller has to act on', () {
      // 3 orders + 2 custom + 1 reservation + 4 pickups
      expect(sample().attentionCount, 10);
    });

    test('is zero when nothing needs the seller', () {
      final quiet = sample(
        pendingOrders: 0,
        pendingCustoms: 0,
        pendingReservations: 0,
        activePickups: 0,
      );
      expect(quiet.attentionCount, 0);
    });

    test('ignores stock and messages — those are not queues to clear', () {
      // Low stock and unread are real signals but they are not a finite
      // "handle these" list, so including them would make the badge stick at a
      // non-zero value that no amount of working through orders could clear.
      final onlyPassive = sample(
        pendingOrders: 0,
        pendingCustoms: 0,
        pendingReservations: 0,
        activePickups: 0,
        lowStockCount: 99,
        unreadNotifications: 42,
      );
      expect(onlyPassive.attentionCount, 0);
    });
  });

  group('revenueLabel — money on a ~90px tile', () {
    test('under a thousand reads as whole pesos', () {
      expect(sample(todayRevenue: 0).revenueLabel, '₱0');
      expect(sample(todayRevenue: 950).revenueLabel, '₱950');
      expect(sample(todayRevenue: 999.99).revenueLabel, '₱999');
    });

    test('thousands and millions compact to one decimal', () {
      expect(sample(todayRevenue: 1000).revenueLabel, '₱1.0k');
      expect(sample(todayRevenue: 12500).revenueLabel, '₱12.5k');
      expect(sample(todayRevenue: 999999).revenueLabel, '₱1000.0k');
      expect(sample(todayRevenue: 1000000).revenueLabel, '₱1.0M');
      expect(sample(todayRevenue: 1234567).revenueLabel, '₱1.2M');
    });

    test('a negative day keeps its sign', () {
      // A refund-heavy day is not a zero day, and rendering it as ₱0 would hide
      // the one number a seller most needs to see.
      expect(formatCompactPeso(-1), '-₱1');
      expect(formatCompactPeso(-2500), '-₱2.5k');
    });
  });

  group('formatClockTime — the "as of" line', () {
    test('uses a 12-hour clock with the boundaries the app expects', () {
      expect(formatClockTime(DateTime(2026, 10, 12, 0, 0)), '12:00 AM');
      expect(formatClockTime(DateTime(2026, 10, 12, 0, 5)), '12:05 AM');
      expect(formatClockTime(DateTime(2026, 10, 12, 9, 7)), '9:07 AM');
      expect(formatClockTime(DateTime(2026, 10, 12, 12, 0)), '12:00 PM');
      expect(formatClockTime(DateTime(2026, 10, 12, 12, 59)), '12:59 PM');
      expect(formatClockTime(DateTime(2026, 10, 12, 13, 0)), '1:00 PM');
      expect(formatClockTime(DateTime(2026, 10, 12, 23, 59)), '11:59 PM');
    });

    test('minutes are always two digits', () {
      // "2:5 PM" is the classic formatting bug; the padLeft is why not.
      expect(formatClockTime(DateTime(2026, 10, 12, 14, 5)), '2:05 PM');
    });
  });

  group('empty state', () {
    test('is not a seller, has no name, and is not "fresh"', () {
      final empty = SellerWidgetData.empty();
      expect(empty.hasStore, isFalse);
      expect(empty.storeName, isEmpty);
      expect(empty.attentionCount, 0);
      // Epoch 0, NOT now(): an empty payload that claimed to be updated this
      // second would read as live data.
      expect(empty.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('carries the empty flag through to the native side', () {
      // The widget decides its empty state off this single boolean, so it has
      // to survive serialisation as a real bool (not "false" the string).
      final values = SellerWidgetData.empty().toWidgetValues();
      expect(values[SellerWidgetKeys.hasStore], isFalse);
    });
  });

  group('toWidgetValues — what the native side actually receives', () {
    test('every value is a primitive a plist and SharedPreferences both hold', () {
      // home_widget persists to SharedPreferences on Android and to a plist on
      // iOS. A nested map or a model object is not readable on either side.
      for (final entry in sample().toWidgetValues().entries) {
        expect(
          entry.value,
          anyOf(isA<String>(), isA<int>(), isA<double>(), isA<bool>()),
          reason: '${entry.key} is ${entry.value.runtimeType}, which is not a '
              'type home_widget can persist on both platforms',
        );
      }
    });

    test('the raw amount is written as a number, the label as a string', () {
      final values = sample(todayRevenue: 12500).toWidgetValues();
      expect(values[SellerWidgetKeys.todayRevenue], 12500.0);
      expect(values[SellerWidgetKeys.revenueLabel], '₱12.5k');
    });

    test('the timestamp is written both ways', () {
      final at = DateTime(2026, 10, 12, 14, 31);
      final values = sample(updatedAt: at).toWidgetValues();
      expect(
        values[SellerWidgetKeys.updatedAtMillis],
        at.millisecondsSinceEpoch,
      );
      expect(values[SellerWidgetKeys.updatedAtLabel], '2:31 PM');
    });
  });
}
