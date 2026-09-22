import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/store.dart';
import 'package:app/screens/store/widgets/store_hero_card.dart';
import 'package:app/widgets/sale_countdown_overlay.dart';
import 'package:app/widgets/store_sale_tag.dart';

/// The store banner is now the ONLY way into a store — the full-width "Enter
/// Store" button that used to sit in the info strip below it is gone — so the
/// gesture is load-bearing and pinned here rather than left to a manual pass:
///
///   * a single tap fires,
///   * a flick across the card does NOT (it is a page of the carousel, and a
///     tap only completes when the finger stays put),
///   * the hit area is the card and nothing else — the 6px margin either side
///     is the carousel's peek gutter and belongs to the neighbouring store,
///   * holding the card dips it and releasing puts it back, because a tap
///     whose only feedback is a screen change 300ms later reads as ignored,
///   * removing the callback (the card used on its own) crashes nothing.
///
/// No `bannerUrl` / `logoUrl`: those render through `CachedNetworkImage`, which
/// has no image to fetch in a widget test. The card's own gradient stands in,
/// and the layers above it are exactly the ones a real tap has to get through.
Store store() => Store(
  id: 's1',
  name: 'Valladolid Leather Co.',
  tagline: 'Tradition stitched into every sole',
  location: 'Valladolid, Carcar City, Cebu',
  createdAt: DateTime(2026, 1, 1),
);

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// A catalog product carrying only the fields the sale tag reads. The card never
/// renders images or inventory, so those stay empty.
Map<String, dynamic> product({
  required String id,
  double price = 1000,
  double? salePrice,
  DateTime? endsAt,
}) => {
  'id': id,
  'name': 'Artisan Shoe',
  'category': 'Sneakers',
  'price': price,
  'sale_price': ?salePrice,
  'sale_ends_at': ?endsAt,
  'images': const <String>[],
  'inventory': const <Map<String, dynamic>>[],
};

void main() {
  /// The card's own scale, as the widget receives it. The card has exactly one
  /// [AnimatedScale] — the page scale and the press dip are multiplied into it
  /// rather than nested, so there is nothing to disambiguate here.
  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('a tap on the banner enters the store', (tester) async {
    var entered = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(store: store(), productCount: 9, onTap: () => entered++),
      ),
    );

    await tester.tap(find.byType(StoreHeroCard));
    await tester.pumpAndSettle();

    expect(entered, 1);
  });

  testWidgets('a flick across the card does not', (tester) async {
    var entered = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(store: store(), productCount: 9, onTap: () => entered++),
      ),
    );

    // The same surface is the page the carousel is flicked through: a drag
    // beyond the touch slop must cancel the tap, or every swipe would land in
    // whichever store the finger lifted on.
    await tester.drag(find.byType(StoreHeroCard), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(entered, 0);
    expect(
      scaleOf(tester),
      1.0,
      reason:
          'a cancelled press must not leave the card stuck sunken — the '
          'drag starts as a press-down, so this is the onTapCancel path',
    );
  });

  testWidgets('the peek gutter beside the card is not part of the target', (
    tester,
  ) async {
    var entered = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(store: store(), productCount: 9, onTap: () => entered++),
      ),
    );

    // The card is drawn 6px in from its own box on each side (the carousel's
    // peek gutter). Both edges must be dead.
    final box = tester.getRect(find.byType(StoreHeroCard));
    for (final probe in [
      box.topLeft + const Offset(2, 130), // inside the left gutter
      box.topRight + const Offset(-2, 130), // inside the right gutter
    ]) {
      await tester.tapAt(probe);
      await tester.pumpAndSettle();
    }

    expect(entered, 0);
  });

  testWidgets('a press dips the card, and releasing puts it back', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(StoreHeroCard(store: store(), productCount: 9, onTap: () {})),
    );
    expect(scaleOf(tester), 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StoreHeroCard)),
    );
    // Past the tap-down deadline, still held: no tap has fired yet.
    await tester.pump(const Duration(milliseconds: 150));
    final pressed = scaleOf(tester);
    expect(
      pressed,
      lessThan(1.0),
      reason:
          'holding the card must dip it — a tap with no feedback until '
          'the navigation lands feels ignored',
    );
    expect(
      pressed,
      greaterThan(0.9),
      reason: 'a whole storefront should not visibly shrink',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      scaleOf(tester),
      1.0,
      reason: 'the card must return to the page scale after the press',
    );
  });

  testWidgets('a press does not dip a card with no action', (tester) async {
    await tester.pumpWidget(
      wrap(StoreHeroCard(store: store(), productCount: 9)),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StoreHeroCard)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      scaleOf(tester),
      1.0,
      reason: 'feedback for an action must not fire when there is none',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the press dip keeps the page scale underneath it', (
    tester,
  ) async {
    // The carousel scales the focused card up/down as it swipes; the dip is a
    // *factor* on that, not a replacement for it.
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          scale: 0.95, // a card that is not the focused page
          productCount: 9,
          onTap: () {},
        ),
      ),
    );
    expect(scaleOf(tester), closeTo(0.95, 0.0001));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StoreHeroCard)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      scaleOf(tester),
      closeTo(0.95 * 0.97, 0.0001),
      reason: 'the dip must compound with the page scale, not override it',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the card renders without a callback', (tester) async {
    await tester.pumpWidget(
      wrap(StoreHeroCard(store: store(), productCount: 9)),
    );

    await tester.tap(find.byType(StoreHeroCard));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // ── The sale tag ────────────────────────────────────────────────

  testWidgets('a store on sale carries the tag; a full-price one does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          productCount: 2,
          products: [product(id: 'a', price: 1000, salePrice: 700)],
          onTap: () {},
        ),
      ),
    );

    expect(find.byType(StoreSaleTag), findsOneWidget);
    expect(find.text('-30%'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          productCount: 2,
          products: [product(id: 'a')],
          onTap: () {},
        ),
      ),
    );

    expect(find.byType(StoreSaleTag), findsNothing);
  });

  testWidgets('the tag follows the shared rule — an expired sale is no sale', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          productCount: 2,
          products: [
            product(
              id: 'a',
              price: 1000,
              salePrice: 700,
              endsAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          ],
          onTap: () {},
        ),
      ),
    );

    expect(find.byType(StoreSaleTag), findsNothing);
  });

  testWidgets('nothing on sale leaves no space in the row', (tester) async {
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          productCount: 2,
          products: [product(id: 'a')],
          onTap: () {},
        ),
      ),
    );

    // The watcher is in the row, but an absent sale contributes a zero-size box
    // — the gap belongs to the tag, not to the row, so nothing is reserved.
    expect(tester.getSize(find.byType(StoreSaleEndWatcher)), Size.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the tag opens the sale, not the store', (tester) async {
    var entered = 0;
    var saleTaps = 0;
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          productCount: 2,
          products: [product(id: 'a', price: 1000, salePrice: 700)],
          onTap: () => entered++,
          onSaleTap: () => saleTaps++,
        ),
      ),
    );

    await tester.tap(find.byType(StoreSaleTag));
    await tester.pumpAndSettle();

    expect(saleTaps, 1);
    expect(
      entered,
      0,
      reason: 'the tag has its own destination — it must not fall through',
    );
  });

  testWidgets('the tag clears itself when the last sale ends', (tester) async {
    await tester.pumpWidget(
      wrap(
        StoreHeroCard(
          store: store(),
          productCount: 2,
          products: [
            product(
              id: 'a',
              price: 1000,
              salePrice: 700,
              endsAt: DateTime.now().add(const Duration(seconds: 2)),
            ),
          ],
          onTap: () {},
        ),
      ),
    );

    expect(find.byType(StoreSaleTag), findsOneWidget);

    // Nothing rebuilds the Stores tab when a sale expires, so the watcher is
    // what has to put the tag away.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(StoreSaleTag), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pill row survives a narrow phone at a large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            // The longest storefront the row has to hold at the app's largest
            // supported scale: rating + count + location + the tag.
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: StoreHeroCard(
              store: Store(
                id: 's1',
                name: 'Valladolid Leather Co.',
                location: 'Valladolid, Carcar City, Cebu',
                rating: 4.8,
                createdAt: DateTime(2026, 1, 1),
              ),
              productCount: 42,
              products: [product(id: 'a', price: 1000, salePrice: 700)],
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(StoreSaleTag), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
