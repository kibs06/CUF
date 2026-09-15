import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app/screens/customer/my_pickup_reservations_screen.dart';
import 'package:app/services/pickup_reservation_service.dart';

class MockPickupReservationService extends Mock
    implements PickupReservationService {}

void main() {
  late MockPickupReservationService mockService;

  setUp(() {
    mockService = MockPickupReservationService();
    // The opportunistic sweeps ride along on load; they must never be fatal.
    when(() => mockService.expireStale()).thenAnswer((_) async => 0);
    when(() => mockService.sendReminders()).thenAnswer((_) async => 0);
  });

  PickupReservation hold({
    String status = 'active',
    int extensionCount = 0,
    required Duration left,
    String name = 'Sole Runner',
  }) =>
      PickupReservation(
        id: 'r-1',
        customerId: 'u-1',
        storeId: 's-1',
        productId: 'p-1',
        size: '40',
        quantity: 2,
        status: status,
        extensionCount: extensionCount,
        pickupDeadline: DateTime.now().add(left),
        productName: name,
        storeName: 'CUFMAI Store',
      );

  Future<void> open(
    WidgetTester tester,
    List<PickupReservation> items,
  ) async {
    when(() => mockService.fetchMine()).thenAnswer((_) async => items);
    await tester.pumpWidget(
      MaterialApp(home: MyPickupReservationsScreen(service: mockService)),
    );
    await tester.pumpAndSettle();
  }

  /// The screen runs a 30-second ticker; disposing the tree cancels it, and a
  /// live timer at the end of a test is a failure in `flutter_test`.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('a live hold offers one extension and says what it means',
      (tester) async {
    await open(tester, [hold(left: const Duration(hours: 20))]);

    expect(find.text('Extend 24h'), findsOneWidget);
    expect(find.textContaining('Extend once for 24h'), findsOneWidget);
    expect(find.textContaining('48h total'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a hold that has already been extended cannot be extended again',
      (tester) async {
    await open(tester, [
      hold(left: const Duration(hours: 20), extensionCount: 1),
    ]);

    expect(find.text('Extend 24h'), findsNothing);
    expect(find.textContaining('cannot be extended twice'), findsOneWidget);
    // It is still just a normal live hold otherwise: release stays available.
    expect(find.text('Release'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a lapsed hold is never offered more time', (tester) async {
    // The sweep may take this stock back at any moment, so the app must not
    // imply the hold can be saved.
    await open(tester, [hold(left: const Duration(minutes: -5))]);

    expect(find.text('Extend 24h'), findsNothing);
    expect(find.text('Expired'), findsOneWidget);

    await close(tester);
  });

  testWidgets('confirming the extension tells the customer the new deadline',
      (tester) async {
    final extended = DateTime.now().add(const Duration(hours: 44));
    when(() => mockService.extend('r-1')).thenAnswer((_) async => extended);

    await open(tester, [hold(left: const Duration(hours: 20))]);
    await tester.tap(find.text('Extend 24h'));
    await tester.pumpAndSettle();

    // The dialog is explicit about the store's side of the bargain.
    expect(find.text('Ask for more time?'), findsOneWidget);
    expect(find.textContaining('nobody else can buy them'), findsOneWidget);
    expect(find.textContaining('only extension a hold gets'), findsOneWidget);

    await tester.tap(find.text('Extend 24h').last);
    await tester.pumpAndSettle();

    verify(() => mockService.extend('r-1')).called(1);
    expect(find.textContaining('Hold extended to'), findsOneWidget);

    await close(tester);
  });

  testWidgets('backing out of the dialog asks the server for nothing',
      (tester) async {
    await open(tester, [hold(left: const Duration(hours: 20))]);
    await tester.tap(find.text('Extend 24h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    verifyNever(() => mockService.extend(any()));
    expect(find.textContaining('Hold extended'), findsNothing);

    await close(tester);
  });

  testWidgets('a refusal is shown as copy, not as a raw failure',
      (tester) async {
    when(() => mockService.extend('r-1')).thenThrow(
      Exception('EXTENSION_LIMIT_REACHED (1) — this hold has already been extended'),
    );

    await open(tester, [hold(left: const Duration(hours: 20))]);
    await tester.tap(find.text('Extend 24h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extend 24h').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('already been extended'), findsOneWidget);
    expect(find.textContaining('EXTENSION_LIMIT_REACHED'), findsNothing);

    await close(tester);
  });

  testWidgets('a resolved hold offers neither action', (tester) async {
    await open(tester, [
      hold(status: 'fulfilled', left: const Duration(hours: -2)),
    ]);

    expect(find.text('Extend 24h'), findsNothing);
    expect(find.text('Release'), findsNothing);
    expect(
      find.text('Collected — recorded as an in-store sale.'),
      findsOneWidget,
    );

    await close(tester);
  });
}
