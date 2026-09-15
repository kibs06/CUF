import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app/screens/seller/pickup_reservations_screen.dart';
import 'package:app/services/pickup_reservation_service.dart';
import 'package:app/services/store_service.dart';

class MockPickupReservationService extends Mock
    implements PickupReservationService {}

class MockStoreService extends Mock implements StoreService {}

void main() {
  late MockPickupReservationService mockService;
  late MockStoreService mockStore;

  setUp(() {
    mockService = MockPickupReservationService();
    mockStore = MockStoreService();
    when(() => mockStore.getMyStore())
        .thenAnswer((_) async => {'id': 's-1', 'name': 'CUFMAI Store'});
    // The opportunistic sweeps ride along on load; they must never be fatal.
    when(() => mockService.expireStale()).thenAnswer((_) async => 0);
    when(() => mockService.sendReminders()).thenAnswer((_) async => 0);
  });

  /// `_now` inside the screen is real wall-clock, so fixtures are relative to
  /// it — a hold "inside the 2-hour window" has to actually be inside it.
  PickupReservation hold({
    required String id,
    required String name,
    int quantity = 1,
    required Duration left,
    String status = 'active',
  }) =>
      PickupReservation(
        id: id,
        customerId: 'u-1',
        storeId: 's-1',
        productId: 'p-$id',
        size: '40',
        quantity: quantity,
        status: status,
        pickupDeadline: DateTime.now().add(left),
        productName: name,
        customerName: 'Ana Cruz',
      );

  Future<void> open(
    WidgetTester tester,
    List<PickupReservation> items,
  ) async {
    when(() => mockService.fetchForStore('s-1'))
        .thenAnswer((_) async => items);
    await tester.pumpWidget(
      MaterialApp(
        home: PickupReservationsScreen(
          service: mockService,
          storeService: mockStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The screen runs a 30-second ticker; disposing the tree cancels it, and a
  /// live timer at the end of a test is a failure in `flutter_test`.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('shows what is off the shelf and what is coming back',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', quantity: 2, left: const Duration(minutes: 90)),
      hold(id: 'b', name: 'Slow Mover', left: const Duration(hours: 18)),
    ]);

    // 2 holds / 3 pairs held now; 2 of those pairs return within 2h.
    expect(find.text('2 holds · 3 pairs held'), findsOneWidget);
    expect(find.text('2 pairs back within 2h'), findsOneWidget);
    expect(find.text('Lapsing soon (1)'), findsOneWidget);
    expect(find.text('Being held (2)'), findsOneWidget);

    await close(tester);
  });

  testWidgets('says nothing about returns when nothing is lapsing',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    expect(find.text('1 hold · 1 pair held'), findsOneWidget);
    // No zero-line to render, and no chip to tap.
    expect(find.textContaining('back within'), findsNothing);
    expect(find.textContaining('Lapsing soon'), findsNothing);

    await close(tester);
  });

  testWidgets('counts a lapsed hold as stock coming back, and says so',
      (tester) async {
    // Past its deadline and not yet swept: the seller can release it now.
    await open(tester, [
      hold(id: 'a', name: 'Overdue Pair', left: const Duration(minutes: -5)),
    ]);

    expect(find.textContaining('back within 2h'), findsOneWidget);
    expect(find.text('1 lapsed — releases on the next load'), findsOneWidget);
    expect(find.text('Lapsing soon (1)'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the lapsing chip narrows the list to the urgent holds',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', quantity: 2, left: const Duration(minutes: 30)),
      hold(id: 'b', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    expect(find.text('Fast Mover'), findsOneWidget);
    expect(find.text('Slow Mover'), findsOneWidget);

    await tester.tap(find.text('Lapsing soon (1)'));
    await tester.pumpAndSettle();

    // Only the hold whose stock is about to walk back on the shelf.
    expect(find.text('Fast Mover'), findsOneWidget);
    expect(find.text('Slow Mover'), findsNothing);

    await close(tester);
  });

  testWidgets('the "Show" affordance in the band jumps straight to them',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', left: const Duration(minutes: 30)),
      hold(id: 'b', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Fast Mover'), findsOneWidget);
    expect(find.text('Slow Mover'), findsNothing);

    await close(tester);
  });

  testWidgets('resolved holds are not counted or offered as lapsing',
      (tester) async {
    await open(tester, [
      hold(
        id: 'a',
        name: 'Collected Pair',
        quantity: 2,
        left: const Duration(minutes: -60),
        status: 'fulfilled',
      ),
    ]);

    expect(find.text('Being held (0)'), findsOneWidget);
    expect(find.textContaining('pairs held'), findsNothing);
    expect(find.textContaining('Lapsing soon'), findsNothing);
    expect(find.text('No pickup reservations are being held right now.'),
        findsOneWidget);

    await close(tester);
  });
}
