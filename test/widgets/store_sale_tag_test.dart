import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/store_sale.dart';
import 'package:app/widgets/store_sale_tag.dart';

/// The Stores tab's hang-tag pill: its two faces, its one announced sentence,
/// its single tap target, and its idle beat.
///
/// The *rule* ("is this store on sale") is not tested here — it is
/// `store_sale_test.dart`'s. This widget only owns the looks.

StoreSale sale({int count = 2, int? discount = 30, DateTime? ends}) =>
    StoreSale(count: count, bestDiscount: discount, earliestEnd: ends);

Widget wrap(Widget child, {bool reducedMotion = false}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Center(child: child),
    ),
  ),
);

/// The tag's own lean, as the widget receives it — `turns`, not radians.
double turnsOf(WidgetTester tester) =>
    tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;

void main() {
  testWidgets('shows the best discount under the UP TO qualifier', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(StoreSaleTag(sale: sale(), onTap: () {})));

    // The same qualifier the ON SALE poster uses: a store-level number must
    // never read as "everything is 30% off".
    expect(find.text('UP TO'), findsOneWidget);
    expect(find.text('-30%'), findsOneWidget);
  });

  testWidgets('falls back to a bare face when the sale is too small to floor', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(StoreSaleTag(sale: sale(count: 1, discount: null), onTap: () {})),
    );

    // Not hidden, not "-0%": the store IS on sale, so the tag says so.
    expect(find.byType(StoreSaleTag), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('SALE'), findsOneWidget);
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('announces one sentence, and it is a button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(StoreSaleTag(sale: sale(), onTap: () {})));

    expect(
      find.bySemanticsLabel(
        RegExp(r'On sale: 2 items, up to 30 percent off'),
      ),
      findsOneWidget,
    );

    final data = tester
        .getSemantics(find.byType(StoreSaleTag))
        .getSemanticsData();
    expect(data.label, contains('On sale: 2 items, up to 30 percent off'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('the whole tag is one target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(StoreSaleTag(sale: sale(), onTap: () => taps++)),
    );

    await tester.tap(find.byType(StoreSaleTag));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('the tag is the fixed pill size the row lays out against', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(StoreSaleTag(sale: sale(), onTap: () {})));

    expect(
      tester.getSize(find.byType(StoreSaleTag)),
      const Size(StoreSaleTag.width, StoreSaleTag.height),
    );
  });

  testWidgets('the beat leans the tag and squares it again', (tester) async {
    await tester.pumpWidget(
      wrap(StoreSaleTag(sale: sale(), onTap: () {}, animate: true)),
    );

    expect(turnsOf(tester), 0, reason: 'at rest, before the first beat');

    // The stillness is a Timer, so nothing has moved until it elapses.
    await tester.pump(StoreSaleTag.dangleHold);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      turnsOf(tester),
      greaterThan(0),
      reason: 'the focused card invites the tap with a lean',
    );

    // The beat ENDS at zero — a finished lean must leave no tilt behind.
    await tester.pump(StoreSaleTag.dangleLean + StoreSaleTag.dangleBack);
    await tester.pump(const Duration(milliseconds: 250));
    expect(turnsOf(tester), 0);
  });

  testWidgets('an unfocused tag never moves', (tester) async {
    await tester.pumpWidget(
      wrap(StoreSaleTag(sale: sale(), onTap: () {})),
    );

    await tester.pump(StoreSaleTag.dangleHold + const Duration(seconds: 2));
    expect(turnsOf(tester), 0);
  });

  testWidgets('reduced motion keeps it still even on the focused card', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        StoreSaleTag(sale: sale(), onTap: () {}, animate: true),
        reducedMotion: true,
      ),
    );

    await tester.pump(StoreSaleTag.dangleHold + const Duration(seconds: 2));
    expect(turnsOf(tester), 0);
  });
}
