import 'package:app/providers/sale_tag_provider.dart';
import 'package:app/widgets/hanging_sale_tag.dart';
import 'package:app/widgets/sole_product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(Widget child, {SaleTagProvider? provider}) {
    return ChangeNotifierProvider<SaleTagProvider>(
      create: (_) => provider ?? SaleTagProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
  }

  testWidgets('unrevealed tag invites a tap, then flips to the discount',
      (tester) async {
    await tester.pumpWidget(
      wrap(const HangingSaleTag(productId: 'p1', salePercent: 23)),
    );
    await tester.pump();

    // Unrevealed face.
    expect(find.text('?'), findsOneWidget);
    expect(find.text('-23%'), findsNothing);

    // Tap → optimistic flip + rebuild.
    await tester.tap(find.byType(HangingSaleTag));
    await tester.pump();
    // Let the flip (480ms) + settle bounce (340ms) + sparkles (500ms) run.
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('-23%'), findsOneWidget);
    expect(find.text('?'), findsNothing);

    // One-way: tapping again never replays or un-reveals.
    await tester.tap(find.byType(HangingSaleTag));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('-23%'), findsOneWidget);
  });

  testWidgets('already-revealed product renders the discount without a tap',
      (tester) async {
    final provider = SaleTagProvider()..reveal('p1');

    await tester.pumpWidget(
      wrap(const HangingSaleTag(productId: 'p1', salePercent: 30), provider: provider),
    );
    await tester.pump();

    expect(find.text('-30%'), findsOneWidget);
    expect(find.text('?'), findsNothing);
  });

  testWidgets('reduced motion: reveal swaps instantly without animation',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: wrap(const HangingSaleTag(productId: 'p1', salePercent: 15)),
      ),
    );
    await tester.pump();

    expect(find.text('?'), findsOneWidget);

    await tester.tap(find.byType(HangingSaleTag));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('-15%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes a semantic label that reflects the tag state',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      wrap(const HangingSaleTag(productId: 'p1', salePercent: 40)),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Sale tag, tap to reveal discount'),
      findsOneWidget,
    );

    await tester.tap(find.byType(HangingSaleTag));
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.bySemanticsLabel('On sale, 40 percent off'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('SoleProductCard: sale product gets the tag, no Try On badge',
      (tester) async {
    final onSaleProduct = {
      'id': 'prod-1',
      'name': 'Sale Boot',
      'price': 1000,
      'sale_price': 700,
      'sale_starts_at': null,
      'sale_ends_at': null,
      'images': <String>[],
      'category': 'Boots',
      'review_count': 0,
    };
    var cardTaps = 0;

    await tester.pumpWidget(
      // Wide enough for the Ahem test font (every glyph = full font-size
      // square) so the price row can't overflow in the test environment.
      wrap(
        SizedBox(
          width: 240,
          height: 300,
          child: SoleProductCard(
            product: onSaleProduct,
            onTap: () => cardTaps++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Hanging tag present (unrevealed "?" face — its own "SALE" micro-label
    // is fine); old red pill and Try-On badge gone.
    expect(find.byType(HangingSaleTag), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    expect(find.text('Try On'), findsNothing);
    expect(find.text('SALE -30%'), findsNothing); // old pill format is gone
    expect(find.text('₱700.00'), findsOneWidget); // sale price shown
    expect(tester.takeException(), isNull);

    // Unrevealed: tapping the tag reveals — and does NOT navigate the card.
    await tester.tap(find.byType(HangingSaleTag));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('-30%'), findsOneWidget);
    expect(cardTaps, 0);

    // Revealed: the tag no longer absorbs taps — they fall through to the
    // card underneath (navigate), so the corner isn't a dead zone.
    await tester.tap(find.byType(HangingSaleTag));
    await tester.pump();
    expect(cardTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SoleProductCard: non-sale product has no hanging tag',
      (tester) async {
    final plainProduct = {
      'id': 'prod-2',
      'name': 'Plain Boot',
      'price': 1000,
      'sale_price': null,
      'images': <String>[],
      'category': 'Boots',
      'review_count': 0,
    };

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 240,
          height: 300,
          child: SoleProductCard(product: plainProduct, onTap: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HangingSaleTag), findsNothing);
    expect(find.text('₱1000.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
