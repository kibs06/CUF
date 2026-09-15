import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/screens/customer/widgets/pickup_reservation_sheet.dart';
import 'package:app/services/pickup_reservation_service.dart';
import 'package:app/widgets/sole_primary_button.dart';

class MockPickupReservationService extends Mock
    implements PickupReservationService {}

final product = <String, dynamic>{
  'id': 'p-1',
  'name': 'Sole Runner',
  'store_id': 's-1',
  'store_name': 'CUFMAI Store',
  'price': 1500.0,
  'sale_price': null,
  'sale_starts_at': null,
  'sale_ends_at': null,
};

void main() {
  late MockPickupReservationService mockService;

  setUp(() {
    mockService = MockPickupReservationService();
  });

  /// Opens the sheet inside a real MaterialApp/Scaffold so taps work.
  Future<void> open(
    WidgetTester tester, {
    required Map<String, int> sizes,
    String? initialSize,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPickupReservationSheet(
                context,
                product: product,
                sizesStock: sizes,
                initialSize: initialSize,
                service: mockService,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapPlus(WidgetTester tester, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }
  }

  testWidgets('says the hold is free and paid for at collection', (
    tester,
  ) async {
    await open(tester, sizes: {'40': 5}, initialSize: '40');

    expect(find.text('Reserve for Pickup'), findsWidgets);
    expect(find.text('FREE to reserve — no deposit'), findsOneWidget);
    expect(find.textContaining('Pay ₱1500 when you collect'), findsOneWidget);
    expect(find.textContaining('24 hours'), findsWidgets);
  });

  testWidgets('prefers the size already chosen on the detail screen', (
    tester,
  ) async {
    await open(tester, sizes: {'40': 5, '41': 4, '42': 3}, initialSize: '41');

    // The chosen chip is rendered with its stock, so the customer can see the
    // selection was carried over.
    expect(find.text('41  (4)'), findsOneWidget);
    expect(find.textContaining('in size 41'), findsOneWidget);
  });

  testWidgets('a single in-stock size needs no tap', (tester) async {
    await open(tester, sizes: {'40': 5});

    expect(find.textContaining('in size 40'), findsOneWidget);
  });

  testWidgets('never offers more than the cap, even when stock is plentiful', (
    tester,
  ) async {
    await open(tester, sizes: {'40': 9}, initialSize: '40');

    await tapPlus(tester, times: 5);

    // 9 in stock, but a free hold is capped at 2 — the stepper must stop
    // rather than let the customer submit something the RPC rejects.
    expect(find.text('2'), findsOneWidget);
    expect(
      find.textContaining('max ${PickupReservation.maxQuantity} per hold'),
      findsOneWidget,
    );
  });

  testWidgets('never offers more than the size actually has', (tester) async {
    await open(tester, sizes: {'40': 1}, initialSize: '40');

    await tapPlus(tester, times: 3);

    // Cap is 2 but this size has 1 — the stock wins.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('points larger orders at the bulk reservation flow', (
    tester,
  ) async {
    await open(tester, sizes: {'40': 9}, initialSize: '40');

    expect(
      find.textContaining('Ask the store for a bulk reservation instead'),
      findsOneWidget,
    );
  });

  testWidgets('cannot submit until a size is chosen', (tester) async {
    // Two sizes and no pre-selection: nothing may be held for the wrong pair.
    // Asserted twice over — the button is visibly inert, and a tap on it still
    // reaches no service call (the sheet double-guards in _submit).
    await open(tester, sizes: {'40': 5, '41': 4});

    expect(find.text('Choose a size'), findsOneWidget);
    final button = tester.widget<SolePrimaryButton>(
      find.byType(SolePrimaryButton),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Reserve for Pickup').last);
    await tester.pumpAndSettle();

    verifyNever(() => mockService.request(
          productId: any(named: 'productId'),
          size: any(named: 'size'),
          quantity: any(named: 'quantity'),
        ));
  });

  testWidgets('a size with no stock is not offered at all', (tester) async {
    await open(tester, sizes: {'40': 0, '41': 4});

    expect(find.textContaining('(0)'), findsNothing);
    expect(find.text('41  (4)'), findsOneWidget);
  });

  testWidgets('submits the chosen size and quantity', (tester) async {
    when(() => mockService.request(
          productId: any(named: 'productId'),
          size: any(named: 'size'),
          quantity: any(named: 'quantity'),
        )).thenAnswer((_) async => 'r-1');

    await open(tester, sizes: {'40': 5}, initialSize: '40');
    await tapPlus(tester);
    await tester.tap(find.text('Reserve for Pickup').last);
    await tester.pumpAndSettle();

    verify(() => mockService.request(
          productId: 'p-1',
          size: '40',
          quantity: 2,
        )).called(1);
  });

  testWidgets('a refusal keeps the sheet open with readable copy', (
    tester,
  ) async {
    when(() => mockService.request(
          productId: any(named: 'productId'),
          size: any(named: 'size'),
          quantity: any(named: 'quantity'),
        )).thenThrow(
      const PostgrestException(
        message: 'RESERVATION_ALREADY_EXISTS',
        code: 'P0001',
      ),
    );

    await open(tester, sizes: {'40': 5}, initialSize: '40');
    await tester.tap(find.text('Reserve for Pickup').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('already have an active pickup hold'),
      findsOneWidget,
    );
    // Still open (the sheet did not pop), so the customer can change size.
    expect(find.text('FREE to reserve — no deposit'), findsOneWidget);
  });
}
