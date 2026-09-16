import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/customer/pickup_goodwill_screen.dart';
import 'package:app/services/pickup_reservation_service.dart';

/// The customer's goodwill history: every time a STORE gave one of their holds
/// more time, and why.
///
/// The point of the screen is that it outlives the hold — so the tests that
/// matter here are the ones about a grant whose hold is gone (collected,
/// released, or simply older than the holds list) and about the row still being
/// readable when the embed brings back nothing.
void main() {
  PickupExtensionGrant grant({
    String id = 'g-1',
    String reservationId = 'r-1',
    String storeId = 's-1',
    String storeName = 'CUFMAI Store',
    String productName = 'Sole Runner',
    String size = '42',
    int hours = 24,
    String reason = 'Customer is stuck in traffic',
    // The trail's timestamps are all NOT NULL, so they are on by default; a test
    // that wants the defensive branch turns them off rather than passing three
    // nulls through parameters that are non-nullable by design.
    bool withTimestamps = true,
  }) =>
      PickupExtensionGrant(
        id: id,
        reservationId: reservationId,
        customerId: 'u-1',
        storeId: storeId,
        storeName: storeName,
        productName: productName,
        size: size,
        hoursGranted: hours,
        reason: reason,
        previousDeadline: withTimestamps ? DateTime(2026, 9, 16, 10, 0) : null,
        newDeadline: withTimestamps ? DateTime(2026, 9, 17, 10, 0) : null,
        createdAt: withTimestamps ? DateTime(2026, 9, 16, 9, 0) : null,
      );

  Future<void> open(WidgetTester tester, List<PickupExtensionGrant> grants) {
    return tester.pumpWidget(
      MaterialApp(home: PickupGoodwillScreen(grants: grants)),
    );
  }

  testWidgets('a gift reads as a store, the pair, the time and the reason',
      (tester) async {
    await open(tester, [grant()]);

    // Who did it, and how much time it was worth.
    expect(find.text('CUFMAI Store'), findsOneWidget);
    expect(find.text('+24h'), findsOneWidget);
    // ...what it was for, because "a store was kind" is only meaningful about a
    // specific pair.
    expect(find.text('Sole Runner · size 42'), findsOneWidget);
    // ...the sentence the store wrote, quoted as a sentence.
    expect(find.text('“Customer is stuck in traffic”'), findsOneWidget);
    // ...and the move itself, not just the later deadline.
    expect(
      find.textContaining('Your hold moved from'),
      findsOneWidget,
    );
    expect(find.textContaining('Given '), findsOneWidget);
  });

  testWidgets('the header counts exactly what the list below shows',
      (tester) async {
    await open(tester, [
      grant(id: 'a', storeId: 's-1'),
      grant(id: 'b', storeId: 's-2', hours: 24),
      grant(id: 'c', storeId: 's-1'),
    ]);

    expect(find.text('3 extensions · 72h of extra time'), findsOneWidget);
    expect(find.text('2 stores kept your pair off the shelf for you.'),
        findsOneWidget);
    // One row per grant — the header is not counting something the list hides.
    expect(find.text('+24h'), findsNWidgets(3));
  });

  testWidgets('one gift is not described in the plural', (tester) async {
    await open(tester, [grant()]);

    expect(find.text('1 extension · 24h of extra time'), findsOneWidget);
    expect(find.text('1 store kept your pair off the shelf for you.'),
        findsOneWidget);
  });

  testWidgets('a grant whose hold brought back no names is still readable',
      (tester) async {
    // The embed can legitimately come back empty (a to-one join that matched
    // nothing), and the reason is the point of the row, so it must not be the
    // thing that disappears.
    await open(tester, [
      grant(storeName: '', productName: '', size: ''),
    ]);

    expect(find.text('A store'), findsOneWidget);
    expect(find.text('“Customer is stuck in traffic”'), findsOneWidget);
    // No half-empty " · size " row where the names would have been: the only
    // ` · ` left on screen is the header's own separator.
    expect(find.textContaining('size '), findsNothing);
    expect(find.textContaining(' · '), findsOneWidget);
  });

  testWidgets('a grant with no recorded deadline move skips that line',
      (tester) async {
    // A row the server cannot currently produce (all three stamps are NOT NULL),
    // which is exactly why it is worth pinning: this screen is the only place a
    // missing deadline would render as the word "null".
    await open(tester, [grant(withTimestamps: false)]);

    expect(find.textContaining('Your hold'), findsNothing);
    expect(find.textContaining('Given '), findsNothing);
    expect(find.text('“Customer is stuck in traffic”'), findsOneWidget);
  });

  testWidgets('the screen says which extensions are NOT in this list',
      (tester) async {
    await open(tester, [grant()]);

    // The customer's own one-per-hold extension lives on the hold, not here.
    // Saying so is what stops the list reading as incomplete.
    expect(find.textContaining('Your own extensions are not listed here'),
        findsOneWidget);
  });

  testWidgets('no favours yet is an explanation, not a blank screen',
      (tester) async {
    await open(tester, const []);

    expect(find.text('No store has given you extra time yet.'), findsOneWidget);
    expect(
      find.textContaining('the store can choose to keep your pair off the '
          'shelf for longer'),
      findsOneWidget,
    );
  });
}
