import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/hanging_sale_tag.dart';
import 'package:app/widgets/sale_countdown_overlay.dart';
import 'package:app/widgets/sole_product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tapeOverlayKey = Key('sale-price-tape-overlay');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    // Make sure the shared one-second ticker never leaks into the next test.
    SaleCountdownTicker.instance.debugReset();
  });

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('null sale end (open-ended sale) renders no countdown at all',
      (tester) async {
    await tester.pumpWidget(wrap(const SaleCountdownOverlay(saleEndsAt: null)));
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    expect(find.textContaining('left'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more than 24h shows whole days, floored down', (tester) async {
    // 50 hours → 2 days 2 hours → "2 days left".
    final end50h = DateTime.now().add(const Duration(hours: 50));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end50h)));
    await tester.pump();
    expect(find.text('2 days left'), findsOneWidget);

    // 47 hours floors DOWN to 1 day (documented rounding rule — never an
    // inflated "2 days" for a sub-48h window).
    final end47h = DateTime.now().add(const Duration(hours: 47));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end47h)));
    await tester.pump();
    expect(find.text('1 day left'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('under 24h switches to a live HH:MM:SS clock that ticks',
      (tester) async {
    final end = DateTime.now().add(const Duration(hours: 2));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end)));
    await tester.pump();

    String clock() => tester
        .widget<Text>(find.byKey(const Key('sale-countdown-text')))
        .data!;

    // Clock mode: ~2h remaining shows 01:59:xx (checked with a wide margin so
    // the exact wall-clock alignment of the test can't make it flaky).
    expect(clock(), startsWith('01:59'));

    // One shared ticker — each fake second visibly moves the seconds digits
    // (regression: the clock must tick, not freeze or jump by minutes).
    final before = clock();
    await tester.pump(const Duration(seconds: 1));
    expect(clock(), isNot(before), reason: 'seconds must visibly move');
    expect(clock(), startsWith('01:59')); // only the seconds changed
    await tester.pump(const Duration(seconds: 1));
    expect(clock(), isNot(before), reason: 'keeps ticking every second');
    expect(tester.takeException(), isNull);
  });

  testWidgets('urgency styling kicks in only under 1 hour', (tester) async {
    final end30m = DateTime.now().add(const Duration(minutes: 30));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end30m)));
    await tester.pump();
    expect(find.byKey(const Key('sale-countdown-urgent')), findsOneWidget);

    final end3h = DateTime.now().add(const Duration(hours: 3));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end3h)));
    await tester.pump();
    expect(find.byKey(const Key('sale-countdown-urgent')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('countdown band is amber-yellow with dark, readable text',
      (tester) async {
    final end = DateTime.now().add(const Duration(hours: 3));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end)));
    await tester.pump();

    // Find the band by its dedicated key (stable across future tree changes).
    final bandFinder = find.byKey(const Key('sale-countdown-band'));
    expect(bandFinder, findsOneWidget);
    final band = tester.widget<Container>(find.descendant(
      of: bandFinder,
      matching: find.byType(Container),
    ));
    final gradient =
        (band.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors, contains(const Color(0xFFFFC107)),
        reason: 'the countdown background must be yellow');

    // Dark text on the yellow band (never white-on-yellow).
    final textStyle =
        tester.widget<Text>(find.byKey(const Key('sale-countdown-text'))).style;
    expect(textStyle?.color, AppConstants.secondary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('countdown hides itself when it reaches zero', (tester) async {
    final end = DateTime.now().add(const Duration(seconds: 3));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end)));
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);

    // ≈2.999s → tick → 1.999s → tick → 0.999s → tick → 0 → hidden. No frozen
    // "00:00:00" is ever left on screen.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion: urgent state renders statically, no pulse',
      (tester) async {
    final end = DateTime.now().add(const Duration(minutes: 30));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: wrap(SaleCountdownOverlay(saleEndsAt: end)),
      ),
    );
    await tester.pump();
    // The urgent scrim is still there — just not pulsing.
    expect(find.byKey(const Key('sale-countdown-urgent')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('announces a human-readable remaining time, not raw digits',
      (tester) async {
    final handle = tester.ensureSemantics();
    // 2 days + 1 hour → floored to "2 days".
    final end = DateTime.now().add(const Duration(days: 2, hours: 1));
    await tester.pumpWidget(wrap(SaleCountdownOverlay(saleEndsAt: end)));
    await tester.pump();
    expect(find.bySemanticsLabel('Sale ends in 2 days'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('whole card falls back to non-sale rendering when the sale ends',
      (tester) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    final onSaleProduct = {
      'id': 'prod-1',
      'name': 'Sale Boot',
      'price': 1000,
      'sale_price': 700,
      'sale_starts_at': null,
      'sale_ends_at': end,
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

    // On sale: hanging tag, price tape and countdown all present.
    expect(find.byType(HangingSaleTag), findsOneWidget);
    expect(find.byKey(_tapeOverlayKey), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);

    // Advance past the end: the one-shot expiry timer fires and the card
    // rebuilds with a `now` past the end — every sale element falls back
    // together, nothing stays frozen at "00:00:00".
    await tester.pump(const Duration(seconds: 7));

    expect(find.byType(HangingSaleTag), findsNothing);
    expect(find.byKey(_tapeOverlayKey), findsNothing);
    expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    expect(find.text('₱1000.00'), findsOneWidget); // original price, one line
    expect(find.text('₱700.00'), findsNothing); // sale price gone
    expect(tester.takeException(), isNull);
  });
}
