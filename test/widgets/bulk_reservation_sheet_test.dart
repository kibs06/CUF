import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/screens/customer/widgets/bulk_reservation_sheet.dart';
import 'package:app/services/reservation_service.dart';
import 'package:app/widgets/sole_primary_button.dart';

class MockReservationService extends Mock implements ReservationService {}

final product = <String, dynamic>{
  'id': 'p-1',
  'name': 'Sole Runner',
  'store_id': 's-1',
  'store_name': 'CUFMAI Store',
  'price': 100.0,
  'sale_price': null,
  'sale_starts_at': null,
  'sale_ends_at': null,
};

void main() {
  late MockReservationService mockService;

  setUp(() {
    mockService = MockReservationService();
  });

  /// Opens the sheet inside a real MaterialApp/Scaffold so taps work.
  Future<void> open(
    WidgetTester tester, {
    Map<String, Map<String, int>> stockByColor = const {
      '': {'40': 10, '41': 5},
    },
    String? initialColor,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showBulkReservationSheet(
                context,
                product: product,
                stockByColor: stockByColor,
                initialColor: initialColor,
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

  /// The sheet is taller than the test viewport (product row + size rows), so
  /// the CTA has to be scrolled into view before it can be tapped.
  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Send Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Request'));
    await tester.pumpAndSettle();
  }

  /// The stepper inside the row for [size] — the rows are ordered by size, so
  /// index 0 is the smallest.
  Future<void> stepSize(WidgetTester tester, String size, int times) async {
    final row = find.ancestor(
      of: find.text(size),
      matching: find.byType(Row),
    );
    final plus = find.descendant(of: row, matching: find.byIcon(Icons.add));
    for (var i = 0; i < times; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
  }

  testWidgets('says WHICH product is being requested', (tester) async {
    await open(tester);

    // The request is keyed on product_id, so the sheet has to name the
    // product itself rather than lean on the page behind it.
    expect(find.text('Sole Runner'), findsOneWidget);
    expect(find.textContaining('₱100 each'), findsOneWidget);
  });

  testWidgets('cannot submit until at least one size is picked', (tester) async {
    await open(tester);

    expect(find.text('Total: pick at least one size'), findsOneWidget);
    final button = tester.widget<SolePrimaryButton>(
      find.byType(SolePrimaryButton),
    );
    expect(button.onPressed, isNull);

    await submit(tester);

    verifyNever(() => mockService.requestReservation(
          productId: any(named: 'productId'),
          storeId: any(named: 'storeId'),
          quantity: any(named: 'quantity'),
          requestedSizes: any(named: 'requestedSizes'),
          note: any(named: 'note'),
        ));
  });

  testWidgets('sends exactly the sizes picked, tagged with the colour', (
    tester,
  ) async {
    when(() => mockService.requestReservation(
          productId: any(named: 'productId'),
          storeId: any(named: 'storeId'),
          quantity: any(named: 'quantity'),
          requestedSizes: any(named: 'requestedSizes'),
          note: any(named: 'note'),
        )).thenAnswer((_) async => 'r-1');

    await open(tester);

    await stepSize(tester, '40', 2);
    await stepSize(tester, '41', 1);

    expect(find.text('Total: 3 pairs'), findsOneWidget);

    await submit(tester);

    final captured = verify(() => mockService.requestReservation(
          productId: 'p-1',
          storeId: 's-1',
          quantity: captureAny(named: 'quantity'),
          requestedSizes: captureAny(named: 'requestedSizes'),
          note: any(named: 'note'),
        )).captured;

    expect(captured[0], 3);
    // Only the picked sizes travel — the old sheet guessed a breakdown from
    // stock levels, which the seller could not tell apart from a real request.
    expect(captured[1], [
      {'size': '40', 'quantity': 2},
      {'size': '41', 'quantity': 1},
    ]);
  });

  testWidgets('a size can never be asked for beyond its own stock', (
    tester,
  ) async {
    await open(tester, stockByColor: const {
      '': {'41': 2},
    });

    await stepSize(tester, '41', 5);

    expect(find.text('Total: 2 pairs'), findsOneWidget);
    await submit(tester);
  });

  testWidgets('a multi-colour product picks the colour and tags every line', (
    tester,
  ) async {
    when(() => mockService.requestReservation(
          productId: any(named: 'productId'),
          storeId: any(named: 'storeId'),
          quantity: any(named: 'quantity'),
          requestedSizes: any(named: 'requestedSizes'),
          note: any(named: 'note'),
        )).thenAnswer((_) async => 'r-1');

    await open(
      tester,
      stockByColor: const {
        'Brown': {'40': 4},
        'Black': {'41': 6},
      },
      initialColor: 'Black',
    );

    // Both colours offered, the carried-over one selected, and only that
    // colour's sizes are listed.
    expect(find.text('Brown'), findsOneWidget);
    expect(find.text('Black'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('40'), findsNothing);
    expect(find.textContaining('Black · ₱100 each'), findsOneWidget);

    await stepSize(tester, '41', 2);
    await submit(tester);

    final captured = verify(() => mockService.requestReservation(
          productId: any(named: 'productId'),
          storeId: any(named: 'storeId'),
          quantity: any(named: 'quantity'),
          requestedSizes: captureAny(named: 'requestedSizes'),
          note: any(named: 'note'),
        )).captured;

    expect(captured[0], [
      {'size': '41', 'quantity': 2, 'color': 'Black'},
    ]);
  });

  testWidgets('switching colour starts the counts over', (tester) async {
    await open(
      tester,
      stockByColor: const {
        'Brown': {'40': 4},
        'Black': {'41': 6},
      },
      initialColor: 'Brown',
    );

    await stepSize(tester, '40', 3);
    expect(find.text('Total: 3 pairs'), findsOneWidget);

    // Sizes are per colour, so a Brown count must not silently become a Black
    // request for a size Black may not even have.
    await tester.tap(find.text('Black'));
    await tester.pumpAndSettle();

    expect(find.text('Total: pick at least one size'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
  });

  testWidgets('a colourless product hides the colour picker', (tester) async {
    await open(tester);

    expect(find.text('Color'), findsNothing);
    expect(find.text('Sizes'), findsOneWidget);
  });

  testWidgets('a refusal keeps the sheet open with readable copy', (
    tester,
  ) async {
    when(() => mockService.requestReservation(
          productId: any(named: 'productId'),
          storeId: any(named: 'storeId'),
          quantity: any(named: 'quantity'),
          requestedSizes: any(named: 'requestedSizes'),
          note: any(named: 'note'),
        )).thenThrow(
      const PostgrestException(message: 'NOT_ENOUGH_STOCK', code: 'P0001'),
    );

    await open(tester);
    await stepSize(tester, '40', 1);
    await submit(tester);

    // Still open (the sheet did not pop), so the customer can adjust.
    expect(find.text('20% GCash deposit if approved'), findsOneWidget);
    expect(find.text('Send Request'), findsOneWidget);
  });
}
