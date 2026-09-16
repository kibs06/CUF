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
    int storeExtensionCount = 0,
    required Duration left,
    String status = 'active',
    String? code = '4F7K2Q',
  }) =>
      PickupReservation(
        id: id,
        customerId: 'u-1',
        storeId: 's-1',
        productId: 'p-$id',
        size: '40',
        quantity: quantity,
        status: status,
        storeExtensionCount: storeExtensionCount,
        pickupDeadline: DateTime.now().add(left),
        productName: name,
        customerName: 'Ana Cruz',
        pickupCode: code,
      );

  /// The goodwill trail rides along on load, best-effort. Defaulted to empty
  /// here so each test states the trail it wants instead of inheriting one.
  Future<void> open(
    WidgetTester tester,
    List<PickupReservation> items, {
    List<PickupExtensionGrant> grants = const [],
  }) async {
    when(() => mockService.fetchStoreGrants('s-1'))
        .thenAnswer((_) async => grants);
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

  // ══════════════════════════════════════════════════════════════════
  // The store's GOODWILL grant — a deliberate, explainable act, so the
  // screen has to ask for the reason rather than offer a one-tap button.
  // ══════════════════════════════════════════════════════════════════
  testWidgets('a live hold offers the store its own one-tap-free grant',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    // Labelled with the amount of time, never a bare "Extend".
    expect(find.text('Give 24h'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the grant asks WHY before it does anything', (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    await tester.tap(find.text('Give 24h'));
    await tester.pumpAndSettle();

    expect(find.text('Give the customer more time?'), findsOneWidget);
    // The dialog states the hold it is about, so a seller with a queue open
    // cannot grant the wrong one by misreading a list position.
    expect(find.textContaining('1 pair of size 40'), findsOneWidget);
    expect(find.textContaining('goodwill extension'), findsOneWidget);

    await close(tester);
  });

  testWidgets('an empty reason is refused in the dialog, not by the server',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    await tester.tap(find.text('Give 24h'));
    await tester.pumpAndSettle();
    // Confirm without typing: the server would raise INVALID_REASON and the
    // seller would have to explain themselves to a customer twice.
    await tester.tap(find.widgetWithText(FilledButton, 'Give 24h'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add a short reason'), findsOneWidget);
    verifyNever(() => mockService.grantExtension(
          reservationId: any(named: 'reservationId'),
          reason: any(named: 'reason'),
        ));

    await close(tester);
  });

  testWidgets('a preset fills the field, and the grant sends what it shows',
      (tester) async {
    when(() => mockService.grantExtension(
          reservationId: 'a',
          reason: 'Customer is stuck in traffic',
        )).thenAnswer((_) async => DateTime.now().add(const Duration(hours: 44)));

    await open(tester, [
      hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    await tester.tap(find.text('Give 24h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer is stuck in traffic'));
    await tester.pumpAndSettle();
    // The chip only FILLS the reason — it is still visible in the field, and
    // still editable, so nothing is recorded that the seller did not read.
    expect(
      find.widgetWithText(TextField, 'Customer is stuck in traffic'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Give 24h'));
    await tester.pumpAndSettle();

    verify(() => mockService.grantExtension(
          reservationId: 'a',
          reason: 'Customer is stuck in traffic',
        )).called(1);
    expect(find.textContaining('Extended for the customer'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a grant that the server refuses is shown as copy',
      (tester) async {
    when(() => mockService.grantExtension(
          reservationId: any(named: 'reservationId'),
          reason: any(named: 'reason'),
        )).thenThrow(
      Exception('STORE_EXTENSION_LIMIT_REACHED (1) — this hold already had a '
          'goodwill extension'),
    );

    await open(tester, [
      hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20)),
    ]);

    await tester.tap(find.text('Give 24h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer called, running late'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Give 24h'));
    await tester.pumpAndSettle();

    expect(find.textContaining('goodwill extension'), findsWidgets);
    expect(find.textContaining('STORE_EXTENSION_LIMIT_REACHED'), findsNothing);

    await close(tester);
  });

  testWidgets('a spent store budget hides the action rather than failing on tap',
      (tester) async {
    await open(tester, [
      hold(
        id: 'a',
        name: 'Slow Mover',
        storeExtensionCount: 1,
        left: const Duration(hours: 40),
      ),
    ]);

    expect(find.textContaining('store +1'), findsOneWidget);
    expect(find.text('Give 24h'), findsNothing);

    await close(tester);
  });

  testWidgets('a lapsed hold is not offered to the store either',
      (tester) async {
    // Past the deadline the units may be released at any moment, so there is no
    // stock left to promise more time on — only "release" makes sense.
    await open(tester, [
      hold(id: 'a', name: 'Overdue Pair', left: const Duration(minutes: -5)),
    ]);

    expect(find.text('Give 24h'), findsNothing);
    expect(find.text('Release'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the reason the deadline moved is printed on the tile',
      (tester) async {
    // A later deadline with no explanation is exactly what the trail exists to
    // prevent, so the tile shows it back to the store that gave it.
    await open(
      tester,
      [
        hold(
          id: 'a',
          name: 'Slow Mover',
          storeExtensionCount: 1,
          left: const Duration(hours: 40),
        ),
      ],
      grants: [
        PickupExtensionGrant(
          id: 'g-1',
          reservationId: 'a',
          customerId: 'u-1',
          storeId: 's-1',
          grantedBy: 'owner-1',
          hoursGranted: 24,
          reason: 'Customer is stuck in traffic',
        ),
      ],
    );

    expect(find.textContaining('You gave 24h'), findsOneWidget);
    expect(find.textContaining('stuck in traffic'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the tile prints the code the customer will read out',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)),
    ]);

    expect(find.textContaining('code 4F7-K2Q'), findsOneWidget);

    await close(tester);
  });

  testWidgets('the counter action turns a typed code into the hold in front of you',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)),
    ]);
    when(() => mockService.resolveCode(any())).thenAnswer((_) async => 'a');
    when(() => mockService.fetchById('a')).thenAnswer((_) async =>
        hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)));

    await tester.tap(find.byTooltip('Collect by code'));
    await tester.pumpAndSettle();

    // The hint shows the shape of what is being asked for rather than an empty
    // box, so a seller knows a dash and lower case are both fine.
    expect(find.text('4F7-K2Q'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4f7-k2q');
    await tester.tap(find.text('Find hold'));
    await tester.pumpAndSettle();

    // Case and separators are gone before the lookup: the server only knows the
    // stored form, and the seller should not have to type it exactly.
    verify(() => mockService.resolveCode('4F7K2Q')).called(1);
    // ...and the seller confirms against the pair actually in their hand, not
    // against a code they typed.
    expect(find.text('Collect this hold?'), findsOneWidget);
    expect(find.textContaining('1 × size 40 of Fast Mover'), findsOneWidget);
    expect(find.textContaining('Code 4F7-K2Q'), findsOneWidget);

    await tester.tap(find.text('Not this one'));
    await tester.pumpAndSettle();

    // Backing out of the confirmation records nothing — the code was only read.
    verifyNever(() => mockService
        .fulfillByCode(any(), paymentMethod: any(named: 'paymentMethod')));

    await close(tester);
  });

  testWidgets('collecting by code records the sale through the code RPC alone',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)),
    ]);
    when(() => mockService.resolveCode(any())).thenAnswer((_) async => 'a');
    when(() => mockService.fetchById('a')).thenAnswer((_) async =>
        hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)));
    when(() => mockService.fulfillByCode(any(),
            paymentMethod: any(named: 'paymentMethod')))
        .thenAnswer((_) async => 'order-1');

    await tester.tap(find.byTooltip('Collect by code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '4F7-K2Q');
    await tester.tap(find.text('Find hold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, collecting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    verify(() => mockService.fulfillByCode('4F7K2Q', paymentMethod: 'cash'))
        .called(1);
    // NOT the id path as well: two fulfilments for one pair would be two sales.
    verifyNever(() =>
        mockService.fulfill(any(), paymentMethod: any(named: 'paymentMethod')));
    expect(find.text('Pickup recorded as a sale.'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a code this store does not own reads as no match',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)),
    ]);
    when(() => mockService.resolveCode(any())).thenThrow(Exception(
        'NOT_FOUND — no pickup hold for your store matches that code'));

    await tester.tap(find.byTooltip('Collect by code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ZZZZZZ');
    await tester.tap(find.text('Find hold'));
    await tester.pumpAndSettle();

    // Not "that reservation no longer exists": the seller has a code in their
    // hand that matched nothing, which is a different problem to solve.
    expect(find.text('No pickup hold for your store matches that code.'),
        findsOneWidget);
    expect(find.text('Collect this hold?'), findsNothing);

    await close(tester);
  });

  testWidgets('a hold already collected says so instead of reading as a bad code',
      (tester) async {
    await open(tester, [
      hold(id: 'a', name: 'Fast Mover', left: const Duration(hours: 5)),
    ]);
    // A resolved hold still RESOLVES — that is the dispute case ("this is the
    // pair the customer showed me"), so the lookup must not pretend the code
    // was wrong.
    when(() => mockService.resolveCode(any())).thenAnswer((_) async => 'a');
    when(() => mockService.fetchById('a')).thenAnswer((_) async => hold(
          id: 'a',
          name: 'Fast Mover',
          left: const Duration(hours: 5),
          status: 'fulfilled',
        ));

    await tester.tap(find.byTooltip('Collect by code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '4F7-K2Q');
    await tester.tap(find.text('Find hold'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already collected'), findsOneWidget);
    verifyNever(() => mockService
        .fulfillByCode(any(), paymentMethod: any(named: 'paymentMethod')));

    await close(tester);
  });

  testWidgets('a grant on someone else\'s hold is not printed here',
      (tester) async {
    // The trail is keyed by reservation, so a row for another hold must not
    // decorate this one.
    await open(
      tester,
      [hold(id: 'a', name: 'Slow Mover', left: const Duration(hours: 20))],
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

    expect(find.textContaining('You gave'), findsNothing);

    await close(tester);
  });
}
