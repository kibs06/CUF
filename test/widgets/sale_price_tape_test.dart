import 'package:app/providers/sale_tag_provider.dart';
import 'package:app/widgets/hanging_sale_tag.dart';
import 'package:app/widgets/sale_price_tape.dart';
import 'package:app/widgets/sole_product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tape overlay's own key — the wrapper widget stays in the tree after
/// reveal (it just returns the plain price), so tests assert on the overlay.
const _tapeOverlayKey = Key('sale-price-tape-overlay');

/// Taps the tape and runs the full peel (520ms). The bare `pump()` first is
/// important: the peel is scheduled in a post-frame callback, so it must be
/// started before the time-advancing pumps. Then pump frame-by-frame — a
/// single long pump only produces ONE frame, which would stall the peel
/// ticker mid-flight.
Future<void> tapAndPeel(WidgetTester tester, Finder tape) async {
  await tester.tap(tape);
  await tester.pump(); // reveal rebuild + post-frame schedules the peel
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Taps the hanging tag and runs its flip (480ms) + settle bounce (340ms).
/// The tag is independent of the tape — this must NOT peel anything.
Future<void> tapTagOnly(WidgetTester tester, Finder tag) async {
  await tester.tap(tag);
  await tester.pump(); // tag flip starts
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(Widget child, {SaleTagProvider? provider}) {
    return ChangeNotifierProvider<SaleTagProvider>(
      create: (_) => provider ?? SaleTagProvider(),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Widget tape({String id = 'p1', String price = '₱700.00'}) {
    return SalePriceTape(
      productId: id,
      child: Text(price, style: const TextStyle(fontSize: 14)),
    );
  }

  testWidgets('covered price shows tape; tap peels it and reveals the number',
      (tester) async {
    await tester.pumpWidget(wrap(tape()));
    await tester.pump();

    // Tape present, price text already in the tree underneath it.
    expect(find.byKey(_tapeOverlayKey), findsOneWidget);
    expect(find.text('₱700.00'), findsOneWidget);

    await tapAndPeel(tester, find.byKey(_tapeOverlayKey));

    // Tape gone; the price was never re-created, just uncovered.
    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(find.text('₱700.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already-revealed product renders the price with no tape',
      (tester) async {
    final provider = SaleTagProvider()..revealTape('p1');

    await tester.pumpWidget(wrap(tape(), provider: provider));
    await tester.pump();

    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(find.text('₱700.00'), findsOneWidget);
  });

  testWidgets('reduced motion: reveal swaps instantly, no peel', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: wrap(tape()),
      ),
    );
    await tester.pump();

    expect(find.byKey(_tapeOverlayKey), findsOneWidget);

    await tester.tap(find.byKey(_tapeOverlayKey));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(find.text('₱700.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered tape announces its state; revealed announces the price',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(tape(price: '₱1,200.00')));
    await tester.pump();

    expect(
      find.bySemanticsLabel('Sale price hidden, tap to reveal'),
      findsOneWidget,
    );

    await tapAndPeel(tester, find.byKey(_tapeOverlayKey));

    expect(
      find.bySemanticsLabel('Sale price hidden, tap to reveal'),
      findsNothing,
    );
    expect(find.bySemanticsLabel('₱1,200.00'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('layout footprint does not change when the tape comes off',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        Center(
          child: KeyedSubtree(
            key: const Key('tape-holder'),
            child: tape(),
          ),
        ),
      ),
    );
    await tester.pump();

    final covered = tester.getSize(find.byKey(const Key('tape-holder')));

    await tapAndPeel(tester, find.byKey(_tapeOverlayKey));

    final revealed = tester.getSize(find.byKey(const Key('tape-holder')));
    expect(revealed, covered,
        reason: 'the tape is an overlay — the price block must not reflow');
  });

  testWidgets('very long price strings fit without overflow or clipping',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 300,
          child: tape(price: '₱1,234,567,890.00'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(_tapeOverlayKey), findsOneWidget);

    await tapAndPeel(tester, find.byKey(_tapeOverlayKey));

    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(find.text('₱1,234,567,890.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('independence: tapping the tag flips it but does NOT peel the tape',
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

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 240,
          height: 300,
          child: SoleProductCard(product: onSaleProduct, onTap: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HangingSaleTag), findsOneWidget);
    expect(find.byKey(_tapeOverlayKey), findsOneWidget);

    // Tap the TAG → only the tag flips (Option B — the tape stays covered).
    await tapTagOnly(tester, find.byType(HangingSaleTag));

    expect(find.text('-30%'), findsOneWidget); // tag flipped
    expect(find.byKey(_tapeOverlayKey), findsOneWidget); // tape UNTOUCHED
    expect(find.text('₱700.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recycled element for a different product starts covered again',
      (tester) async {
    // No provider in the tree → the tap uses the guest/session-only local
    // flip, which is exactly the state a recycled element must not carry
    // over to a different product.
    Widget home({required String id}) => MaterialApp(
          home: Scaffold(body: Center(child: tape(id: id))),
        );

    await tester.pumpWidget(home(id: 'A'));
    await tester.pump();

    // Guest-reveal product A.
    await tapAndPeel(tester, find.byKey(_tapeOverlayKey));
    expect(find.byKey(_tapeOverlayKey), findsNothing); // A revealed

    // Same element position, now product B — must NOT inherit A's reveal.
    await tester.pumpWidget(home(id: 'B'));
    await tester.pump();

    expect(find.byKey(_tapeOverlayKey), findsOneWidget); // B covered
    expect(find.text('₱700.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tape hit target meets the ~40px minimum on both axes',
      (tester) async {
    await tester.pumpWidget(wrap(tape()));
    await tester.pump();

    final size = tester.getSize(find.byKey(_tapeOverlayKey));
    expect(size.width, greaterThanOrEqualTo(40),
        reason: 'hit area must be comfortably tappable');
    expect(size.height, greaterThanOrEqualTo(40),
        reason: 'hit area must be comfortably tappable');

    // A tap at the very edge of the hit area still peels the tape (the hit
    // box is larger than the visual strip — no dead corners).
    final topLeft = tester.getTopLeft(find.byKey(_tapeOverlayKey));
    await tester.tapAt(topLeft + const Offset(2, 2));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('independence: tapping the tape peels it but does NOT flip the tag',
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

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 240,
          height: 300,
          child: SoleProductCard(product: onSaleProduct, onTap: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Tap the TAPE → only the tape peels (Option B — the tag stays '?').
    await tapAndPeel(tester, find.byKey(_tapeOverlayKey));

    expect(find.byKey(_tapeOverlayKey), findsNothing); // tape peeled
    expect(find.text('?'), findsOneWidget); // tag UNTOUCHED
    expect(find.text('₱700.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revealing the tag then the tape shows both revealed',
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

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 240,
          height: 300,
          child: SoleProductCard(product: onSaleProduct, onTap: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Reveal in either order — each interaction is fully independent.
    await tapAndPeel(tester, find.byKey(_tapeOverlayKey)); // tape first
    await tapTagOnly(tester, find.byType(HangingSaleTag)); // then tag

    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(find.text('-30%'), findsOneWidget);
    expect(find.text('?'), findsNothing);
    expect(find.text('₱700.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
