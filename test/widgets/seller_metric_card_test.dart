import 'package:app/constants/seller_theme_constants.dart';
import 'package:app/widgets/seller/seller_metric_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard's "Today's snapshot" row — three equal cards across. This
/// mirrors `_buildMetricsGrid`'s layout and copy at a given device width so
/// the narrow-cell behaviour stays guarded. Each card is a label, its number
/// and a one-line state subtitle ("Needs restock" / "All stocked up") — the
/// words carry the state so it is never colour-only.
///
/// NOTE: widget tests render with the fallback test font (Ahem), whose glyphs
/// are a full em wide — far wider than DM Sans. That makes it ideal for
/// catching overflow (the worst case) but useless for judging whether real
/// text fits, so the assertions below only cover what is font-independent.
Widget snapshotRow({required double deviceWidth}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: deviceWidth,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SellerMetricCard(
                    label: 'LOW STOCK',
                    value: '1',
                    valueColor: SellerTheme.rust,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SellerMetricCard(
                    label: 'CUSTOM ORDERS',
                    value: '0',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SellerMetricCard(
                    label: 'BULK RESERVATIONS',
                    value: '1',
                    valueColor: SellerTheme.amberDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const labels = ['LOW STOCK', 'CUSTOM ORDERS', 'BULK RESERVATIONS'];

  // 360dp is the narrowest common Android width (very common in the PH
  // market); 393/412 cover Pixel-class phones.
  for (final width in const [360.0, 393.0, 412.0]) {
    testWidgets('three metric cards lay out without overflow at '
        '${width.toInt()}dp', (tester) async {
      // A RenderFlex overflow anywhere here fails the test automatically —
      // that is the regression this guards (the old full-width Bulk
      // Reservations card was moved into the row).
      await tester.pumpWidget(snapshotRow(deviceWidth: width));
      await tester.pumpAndSettle();

      expect(find.byType(SellerMetricCard), findsNWidgets(3));
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('the three metric cards share one height at '
        '${width.toInt()}dp', (tester) async {
      await tester.pumpWidget(snapshotRow(deviceWidth: width));
      await tester.pumpAndSettle();

      final cards = find.byType(SellerMetricCard);
      final heights = [
        for (var i = 0; i < 3; i++) tester.getSize(cards.at(i)).height,
      ];

      expect(heights[0], heights[1],
          reason: 'Low Stock and Custom Orders must match');
      expect(heights[1], heights[2],
          reason: 'the row must stretch all three cards to the same height');
    });
  }

  group('state signalling', () {
    // The old cards always showed a rust dot — even at zero, both cards
    // cried wolf with the same red dot. The dot must agree with the number.
    testWidgets('the status dot defaults to rust', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SellerMetricCard(label: 'LOW STOCK', value: '0'),
          ),
        ),
      );

      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(
        (dot.decoration! as BoxDecoration).color,
        SellerTheme.rust,
      );
    });

    testWidgets('a clear queue gets a sage dot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SellerMetricCard(
              label: 'LOW STOCK',
              value: '0',
              subtitle: 'All stocked up',
              dotColor: SellerTheme.sage,
            ),
          ),
        ),
      );

      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(
        (dot.decoration! as BoxDecoration).color,
        SellerTheme.sage,
      );
      expect(find.text('All stocked up'), findsOneWidget);
    });

    // A bare GestureDetector exposes nothing to TalkBack/VoiceOver (the
    // documented Bad example) — the card must announce label, number and
    // state as one, and only claim to be a button when it goes somewhere.
    testWidgets('a tappable card announces its full state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerMetricCard(
              label: 'BULK RESERVATIONS',
              value: '2',
              subtitle: 'Awaiting approval',
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(
        find.byType(SellerMetricCard),
      );
      expect(
        semantics.label,
        'BULK RESERVATIONS, 2, Awaiting approval',
      );
      expect(semantics.flagsCollection.isButton, isTrue);
    });
  });
}
