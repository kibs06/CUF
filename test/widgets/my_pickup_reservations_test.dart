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
    int storeExtensionCount = 0,
    required Duration left,
    String name = 'Sole Runner',
    String? code = '4F7K2Q',
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
        // Kept in step with the trail: a grant row and a zero counter on the
        // hold would be a server inconsistency, not a UI state.
        storeExtensionCount: storeExtensionCount,
        pickupDeadline: DateTime.now().add(left),
        productName: name,
        storeName: 'CUFMAI Store',
        pickupCode: code,
      );

  Future<void> open(
    WidgetTester tester,
    List<PickupReservation> items, {
    List<PickupExtensionGrant> grants = const [],
  }) async {
    when(() => mockService.fetchMyGrants())
        .thenAnswer((_) async => grants);
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

  testWidgets('the counter code is on the card, not behind a tap',
      (tester) async {
    await open(tester, [hold(left: const Duration(hours: 20))]);

    // Both facts the customer needs while standing at the till — what to show
    // and how long is left — are visible without a tap.
    expect(find.text('Show this code at the counter'), findsOneWidget);
    // Grouped, because it is a thing they SAY, and 4F7-K2Q is read aloud as
    // four-eff-seven-kay-two-queue more reliably than an unbroken run.
    expect(find.text('4F7-K2Q'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a hold without a code shows no band, not a placeholder',
      (tester) async {
    await open(tester, [hold(left: const Duration(hours: 20), code: null)]);

    // A made-up code is worse than none: the seller would type it.
    expect(find.text('Show this code at the counter'), findsNothing);
    expect(find.textContaining('4F7'), findsNothing);

    await close(tester);
  });

  testWidgets('the history is offered only once a store has been generous',
      (tester) async {
    // The two halves are asserted in ONE test on purpose: a condition that is
    // simply always-false would satisfy the first half on its own, and a
    // condition that is always-true would satisfy the second.
    await open(tester, [hold(left: const Duration(hours: 20))]);

    // Nothing to read yet, and the same rule the seller screen's `Lapsing soon`
    // chip follows: an action that opens an empty screen is noise.
    expect(find.byTooltip('Goodwill history'), findsNothing);

    // Disposed first: pumping the same widget type again would REUSE the
    // element, so `initState` — and therefore `_load()` — would never run a
    // second time and this half would be reading the first screen's state.
    await close(tester);
    await open(
      tester,
      [hold(left: const Duration(hours: 20))],
      grants: [
        PickupExtensionGrant(
          id: 'g-1',
          reservationId: 'r-1',
          customerId: 'u-1',
          storeId: 's-1',
          storeName: 'CUFMAI Store',
          hoursGranted: 24,
          reason: 'Customer is stuck in traffic',
          previousDeadline: DateTime(2026, 9, 16, 10, 0),
          newDeadline: DateTime(2026, 9, 17, 10, 0),
          createdAt: DateTime(2026, 9, 16, 9, 0),
        ),
      ],
    );

    expect(find.byTooltip('Goodwill history'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the history outlives the hold it came from', (tester) async {
    // THE reason the history is a screen and not a line on a tile: this grant is
    // on a hold the customer's list no longer contains at all (collected,
    // released, or past the fetch's LIMIT), so without somewhere to list the
    // trail, the only trace of the favour would be a deadline that was quietly
    // later than expected.
    await open(
      tester,
      [hold(left: const Duration(hours: 20))],
      grants: [
        PickupExtensionGrant(
          id: 'g-1',
          reservationId: 'r-gone',
          customerId: 'u-1',
          storeId: 's-1',
          storeName: 'CUFMAI Store',
          productName: 'Sole Runner',
          size: '40',
          hoursGranted: 24,
          reason: 'Customer is stuck in traffic',
          previousDeadline: DateTime(2026, 9, 16, 10, 0),
          newDeadline: DateTime(2026, 9, 17, 10, 0),
          createdAt: DateTime(2026, 9, 16, 9, 0),
        ),
      ],
    );

    expect(find.byTooltip('Goodwill history'), findsOneWidget);

    await tester.tap(find.byTooltip('Goodwill history'));
    await tester.pumpAndSettle();

    expect(find.text('Goodwill from stores'), findsOneWidget);
    expect(find.text('CUFMAI Store'), findsOneWidget);
    expect(find.text('“Customer is stuck in traffic”'), findsOneWidget);

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

  testWidgets('a store\'s goodwill grant is shown WITH its reason',
      (tester) async {
    // The customer's own extension cannot explain a hold that now runs past
    // 48h, so the reason has to be visible to them — not only to the store.
    await open(
      tester,
      [hold(left: const Duration(hours: 40), storeExtensionCount: 1)],
      grants: [
        PickupExtensionGrant(
          id: 'g-1',
          reservationId: 'r-1',
          customerId: 'u-1',
          storeId: 's-1',
          grantedBy: 'owner-1',
          hoursGranted: 24,
          reason: 'Customer called, running late',
        ),
      ],
    );

    expect(find.textContaining('The store gave you +24h'), findsOneWidget);
    expect(find.textContaining('Customer called, running late'), findsOneWidget);
    // The hold's own note (driven by the server's counter) and the trail (the
    // reason) agree about what happened — they come from two different columns,
    // so a screen showing one without the other would read as a partial story.
    expect(find.textContaining('goodwill'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the trail of another hold does not decorate this one',
      (tester) async {
    await open(
      tester,
      [hold(left: const Duration(hours: 20))],
      grants: [
        PickupExtensionGrant(
          id: 'g-9',
          reservationId: 'OTHER',
          customerId: 'u-1',
          storeId: 's-1',
          hoursGranted: 24,
          reason: 'not this hold',
        ),
      ],
    );

    expect(find.textContaining('The store gave you'), findsNothing);

    await close(tester);
  });

  testWidgets('a missing grant trail costs the explanation, not the holds',
      (tester) async {
    // The trail is decoration on this screen: it answers "why is my deadline
    // later?", but the holds themselves are the work. A database where the
    // migration has not been applied yet must still show them (this is the
    // graceful-degradation promise the release notes make).
    when(() => mockService.fetchMyGrants())
        .thenThrow(Exception('relation does not exist'));

    await open(tester, [
      hold(left: const Duration(hours: 20)),
    ]);

    expect(find.text('Sole Runner'), findsOneWidget);
    expect(find.text('Extend 24h'), findsOneWidget);

    await close(tester);
  });
}
