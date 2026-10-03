import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/review_provider.dart';
import 'package:app/screens/customer/product_detail_screen.dart';
import 'package:app/services/try_on_prefetch.dart';
import 'package:app/utils/product_images.dart';
import 'package:app/widgets/color_thumbnail_swatch.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **The product page opens on the product's own gallery, and only a tapped
/// colour replaces it.**
///
/// This is the rule a live product got wrong: `_sortedImageUrls` keyed off
/// `_effectiveColor`, which falls back to the *first colour name* before anyone
/// has tapped anything. A coloured product therefore opened on
/// `colors/<first>/…` while the store card — which reads the same
/// `product_images` the card's own `productImageUrls` reads — showed the
/// product's first photo. The seller saw two different photos for one product,
/// and when that colour's file was missing the hero was simply blank.
///
/// What is pinned here is the whole rule, as a shopper experiences it:
///
///  1. **No tap, product photos.** The hero draws `productImageUrls(product)`,
///     the same list, in the same seller-arranged order, that the card draws.
///  2. **A tapped colour swaps it — and tapping it again swaps back.** The
///     swatch ring follows the shopper's tap, and a second tap on the ringed
///     swatch is a *deselect*: nothing is ringed and the product's own photos
///     are the hero again.
///  3. **A tapped colour with no photos leaves the product's gallery up** —
///     the fallback is the seller's own gallery, never an empty hero.
///
/// `_effectiveColor` keeps its other job (pricing, variant resolution, the size
/// grid) — that is `cart_helpers`' and the size grid's own subject, and changing
/// it here would be this test overreaching.
///
/// The colour selector's **placement** is asserted here too, because it is the
/// same section and the same fixture: the swatch row sits above the size grid.
/// The size grid is filtered to the active colour (`_buildSizesMap`), so the
/// colour is the choice the sizes depend on and is asked first on the page.
///
/// The page is the real `ProductDetailScreen`; only its four providers are
/// mocks, and the try-on prefetch is explicitly disabled so a network-shaped
/// concern cannot colour a gallery assertion.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the page opens on the product\u2019s own photos, as the card shows them',
      (tester) async {
    await _pumpPage(tester);

    expect(
      _heroImageUrls(tester),
      [productImageUrls(_product).first],
      reason: 'the page must open on the photo the card opens on — the '
          'product\u2019s first, never the first colour\u2019s',
    );
  });

  testWidgets('tapping a colour swaps the hero to that colour\u2019s photos',
      (tester) async {
    await _pumpPage(tester);
    await _tapSwatch(tester, 'Black');

    expect(
      _heroImageUrls(tester),
      ['https://example.test/black.jpg'],
      reason: 'once a colour is tapped, its own gallery is what the shopper '
          'asked to see',
    );
  });

  testWidgets('the colour selector is asked before the size grid',
      (tester) async {
    await _pumpPage(tester);

    // Scroll the lower label into view. `scrollUntilVisible` builds it first,
    // so this does not depend on how tall the hero is on the test surface.
    // The scrollable must be named: the page also holds the hero pager and the
    // horizontal swatch row, and the helper refuses an ambiguous finder.
    await tester.scrollUntilVisible(
      find.text('Select Size'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    final colour = find.text('Select Color / Leather');
    final size = find.text('Select Size');
    expect(colour, findsOneWidget);
    expect(size, findsOneWidget);
    expect(
      tester.getTopLeft(colour).dy,
      lessThan(tester.getTopLeft(size).dy),
      reason: 'the size grid is filtered to the active colour, so the colour '
          'is the choice the sizes depend on — it is asked first',
    );
  });

  testWidgets('tapping the ringed colour again deselects, gallery and all',
      (tester) async {
    await _pumpPage(tester);

    expect(_swatchSelected(tester, 'Black'), isFalse,
        reason: 'no colour is ringed until the shopper taps one — the ring '
            'is the pick, not `_effectiveColor`\u2019s first-colour fallback');

    await _tapSwatch(tester, 'Black');
    expect(_swatchSelected(tester, 'Black'), isTrue);
    expect(_heroImageUrls(tester), ['https://example.test/black.jpg']);

    await _tapSwatch(tester, 'Black');
    expect(_swatchSelected(tester, 'Black'), isFalse,
        reason: 'a second tap is a deselect — nothing may stay ringed');
    expect(
      _heroImageUrls(tester),
      [productImageUrls(_product).first],
      reason: 'deselecting returns the page to the product\u2019s own photos',
    );
  });

  testWidgets('a tapped colour with no photos leaves the product gallery up',
      (tester) async {
    await _pumpPage(tester);
    // Tan has variants but no `product_color_images` row — the state the
    // migration leaves existing coloured products in, and the exact case that
    // used to blank the hero.
    await _tapSwatch(tester, 'Tan');

    expect(
      _heroImageUrls(tester),
      [productImageUrls(_product).first],
      reason: 'the fallback for a colour with no gallery is the product\u2019s '
          'own gallery, not an empty hero',
    );
  });
}

/// The URLs the hero carousel is currently drawing.
///
/// The hero is the screen's only `PageView`, and its pages are
/// `CachedNetworkImage`s — so this reads exactly the carousel, not the store
/// avatar or any other image on the page. `PageView.builder` builds only the
/// visible page, which is the one the shopper sees.
List<String> _heroImageUrls(WidgetTester tester) => tester
    .widgetList<CachedNetworkImage>(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(CachedNetworkImage),
      ),
    )
    .map((image) => image.imageUrl)
    .toList();

Finder _swatch(String name) => find.byWidgetPredicate(
      (widget) => widget is ColorThumbnailSwatch && widget.name == name,
      description: 'the $name colour swatch',
    );

/// Whether the named swatch is drawing its selection ring.
bool _swatchSelected(WidgetTester tester, String name) =>
    tester.widget<ColorThumbnailSwatch>(_swatch(name)).selected;

Future<void> _tapSwatch(WidgetTester tester, String name) async {
  final swatch = _swatch(name);
  // The swatch row sits below the hero, so it may need scrolling into view
  // before it can be tapped at all.
  await tester.ensureVisible(swatch);
  await tester.pump();
  await tester.tap(swatch);
  await tester.pump();
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(_wrapPage(ProductDetailScreen(
    product: _product,
    // Off on purpose: this file tests the gallery, and a best-effort prefetch
    // resolving models over a non-existent table must not be part of the story.
    tryOnPrefetch: TryOnPrefetch(enabled: false),
  )));
  await tester.pump(const Duration(milliseconds: 300));
}

/// A product complete enough that the page renders without touching Supabase:
/// sizes come from `inventory` + `product_variants`, and the variants carry the
/// colours so the page never fires its own colour read.
///
/// `product_images` is deliberately out of display order (two.jpg is stored
/// first) so "opens on the product's own photos" also means *sorted*, and Black
/// — the first variant colour, and therefore the one `_effectiveColor` falls
/// back to — carries a photo the page must still not open on.
Map<String, dynamic> get _product => {
      'id': 'product-1',
      'name': 'Artisan Penny Loafer',
      'description': 'Handmade in Carcar.',
      'price': 1099.0,
      'category': 'Casual',
      'store_id': 'store-1',
      'store_name': 'Carcar Leatherworks',
      'tags': const <String>[],
      'avg_rating': 4.8,
      'review_count': 12,
      'product_images': const [
        {'image_url': 'https://example.test/two.jpg', 'display_order': 1},
        {'image_url': 'https://example.test/one.jpg', 'display_order': 0},
      ],
      'product_color_images': const [
        {
          'color_name': 'Black',
          'url': 'https://example.test/black.jpg',
          'display_order': 0,
        },
      ],
      'product_variants': const [
        {'id': 'variant-1', 'size': 'EU 42', 'stock': 3, 'color': 'Black'},
        {'id': 'variant-2', 'size': 'EU 42', 'stock': 2, 'color': 'Tan'},
      ],
      'inventory': const [
        {'size': 'EU 42', 'stock': 5},
      ],
      'product_customizations': const [],
    };

/// The four providers the page's own build reads — all mocks, stubbed with the
/// members the page touches. `CartProvider` cannot be constructed in a test at
/// all: its constructor reaches for `Supabase.instance`, which is
/// un-initialised under `flutter test`.
Widget _wrapPage(Widget page) {
  final auth = _MockAuthProvider();
  when(() => auth.profile).thenReturn(null);
  when(() => auth.currentUser).thenReturn(null);

  final cart = _MockCartProvider();
  when(() => cart.itemCount).thenReturn(0);

  final products = _MockProductProvider();
  when(() => products.unitsSoldFor(any())).thenReturn(0);

  final reviews = _MockReviewProvider();
  when(() => reviews.reviewCount).thenReturn(0);
  when(() => reviews.canReview).thenReturn(false);
  when(() => reviews.myReview).thenReturn(null);
  when(() => reviews.reviews).thenReturn([]);
  when(() => reviews.isLoading).thenReturn(false);
  when(() => reviews.ratingSummary).thenReturn(null);
  when(() => reviews.errorMessage).thenReturn(null);
  when(() => reviews.orderItems).thenReturn([]);
  when(() => reviews.loadReviews(any())).thenAnswer((_) async {});

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ReviewProvider>.value(value: reviews),
      ChangeNotifierProvider<CartProvider>.value(value: cart),
      ChangeNotifierProvider<ProductProvider>.value(value: products),
    ],
    child: MaterialApp(home: page),
  );
}

class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

class _MockReviewProvider extends Mock
    with ChangeNotifier
    implements ReviewProvider {}

class _MockCartProvider extends Mock
    with ChangeNotifier
    implements CartProvider {}

class _MockProductProvider extends Mock
    with ChangeNotifier
    implements ProductProvider {}
