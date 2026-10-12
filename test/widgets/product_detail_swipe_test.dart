import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/review_provider.dart';
import 'package:app/screens/customer/product_detail_screen.dart';
import 'package:app/services/try_on_prefetch.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A product page opened from a list can be swiped through that list.**
///
/// The page has always been pushed with one product and nothing else, so
/// "next" and "previous" did not exist: a customer who wanted the card beside
/// the one they tapped had to go back and find it again. A caller that HAS the
/// list now passes it, and the page becomes a pager over that list, in the
/// caller's own order.
///
/// What is pinned here is the whole behaviour, as a shopper meets it:
///
///  1. **No list, no pager.** The overwhelming majority of pushes pass one
///     product. A page that invented a list to swipe through would be a worse
///     answer than no swipe at all, so the lone product is exactly the page it
///     has always been — no position chip, and a horizontal drag that moves
///     nothing.
///  2. **One product is not a list either.** A list of one is the same page as
///     no list, chip included: `1 / 1` would advertise a swipe that cannot
///     happen.
///  3. **A swipe lands on the CALLER'S next product, in the caller's order.**
///     The catalog is shuffled per load and each surface filters it differently,
///     so the list is carried in rather than re-derived — "next" has to be the
///     card that was actually beside the one tapped, which is what this asserts
///     against a list deliberately given in a non-alphabetical, non-price order.
///  4. **The chip says where it is.** `2 / 3` in the app bar, because a swipe
///     nobody discovers is not a feature.
///
/// The drag is made in the page's BODY, not over the hero, and that is not an
/// accident of the test: the hero is itself a horizontal carousel of the
/// product's photos (its own `PageView`), so a sideways drag over the photograph
/// pages the photographs. Clearing the hero is where the product swipe lives.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a lone product is not a pager \u2014 no chip, and a drag moves nothing',
      (tester) async {
    await _pumpPage(tester);
    _expectNoChip(tester);

    await _swipeLeft(tester);

    expect(
      _heroPhotoUrls(tester),
      [_photoOf(_browse[0])],
      reason: 'a page opened with one product has nothing to swipe to, so a '
          'sideways drag must leave it exactly where it was',
    );
    _expectNoChip(tester);
  });

  testWidgets('a list of one is not a pager either', (tester) async {
    // The same page as no list. `1 / 1` would say there is a swipe here, and
    // there is not.
    await _pumpPage(tester, products: _browse.take(1).toList());
    _expectNoChip(tester);
  });

  testWidgets('a page opened from a list says where the product sits',
      (tester) async {
    await _pumpPage(tester, products: _browse);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(_heroPhotoUrls(tester), [_photoOf(_browse[0])]);
  });

  testWidgets('swiping left opens the next product in the caller\u2019s list',
      (tester) async {
    await _pumpPage(tester, products: _browse);

    await _swipeLeft(tester);

    expect(
      _heroPhotoUrls(tester),
      [_photoOf(_browse[1])],
      reason: 'the swipe must land on the product that was next in the list the '
          'caller pushed, in that order \u2014 not on a re-derived catalogue order',
    );
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('1 / 3'), findsNothing);
  });

  testWidgets('swiping right goes back to the previous product', (tester) async {
    await _pumpPage(tester, products: _browse, index: 1);
    expect(find.text('2 / 3'), findsOneWidget);

    await _swipeRight(tester);

    expect(_heroPhotoUrls(tester), [_photoOf(_browse[0])]);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('an index past the end of the list is clamped, not asserted',
      (tester) async {
    // The list can change under a tap \u2014 a refresh between the grid painting and
    // the tap landing \u2014 and an out-of-range index would otherwise assert inside
    // `PageController` and take the screen down.
    await _pumpPage(tester, products: _browse, index: 99);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(_heroPhotoUrls(tester), [_photoOf(_browse[2])]);
  });
}

/// The list a caller would push \u2014 three products, and deliberately in an order
/// that is neither alphabetical by name nor by price, so "the next one" can only
/// be right if the list itself is the source of the order.
final List<Map<String, dynamic>> _browse = [
  _product('product-1', 'Artisan Penny Loafer', 1099, 'one'),
  _product('product-2', 'Bayanihan Runner', 2499, 'two'),
  _product('product-3', 'Cebu Trail Sandal', 650, 'three'),
];

String _photoOf(Map<String, dynamic> product) =>
    (product['product_images'] as List).first['image_url'] as String;

Map<String, dynamic> _product(String id, String name, double price, String photo) => {
      'id': id,
      'name': name,
      'description': 'Handmade in Carcar.',
      'price': price,
      'category': 'Casual',
      'store_id': 'store-1',
      'store_name': 'Carcar Leatherworks',
      'tags': const <String>[],
      'avg_rating': 4.8,
      'review_count': 12,
      'product_images': [
        {'image_url': 'https://example.test/$photo.jpg', 'display_order': 0},
      ],
      'product_color_images': const <Map<String, dynamic>>[],
      'product_variants': const [
        {'id': 'variant-1', 'size': 'EU 42', 'stock': 3, 'color': 'Black'},
      ],
      'inventory': const [
        {'size': 'EU 42', 'stock': 5},
      ],
      'product_customizations': const [],
    };

Future<void> _pumpPage(
  WidgetTester tester, {
  List<Map<String, dynamic>>? products,
  int index = 0,
}) async {
  final list = products;
  await tester.pumpWidget(_wrapPage(ProductDetailScreen(
    product: list == null ? _browse[0] : list[index.clamp(0, list.length - 1)],
    browseList: list,
    browseIndex: index,
    // Off on purpose, as in the gallery suite: a best-effort prefetch resolving
    // models over a non-existent table has no business in a navigation test.
    tryOnPrefetch: TryOnPrefetch(enabled: false),
  )));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The page the shopper sees has no position chip at all.
void _expectNoChip(WidgetTester tester) {
  final chip = RegExp(r'^\d+ / \d+$');
  final chips = find
      .byWidgetPredicate(
        (widget) => widget is Text && chip.hasMatch(widget.data ?? ''),
        description: 'a browse position chip',
      )
      .evaluate()
      .toList();
  expect(
    chips,
    isEmpty,
    reason: 'a page with nothing to swipe to must not show a position: the '
        'only swipe on this page is the photograph carousel',
  );
}

/// A sideways drag **in the body**, below the hero.
///
/// The hero is a horizontal photo carousel, so a drag that starts on the
/// photograph pages the photographs \u2014 by design. The product swipe is
/// everywhere else on the page, which is where this starts.
Future<void> _swipeLeft(WidgetTester tester) => _swipe(tester, -400);

Future<void> _swipeRight(WidgetTester tester) => _swipe(tester, 400);

/// The drag itself, and the pumps that land it.
///
/// Deliberately **not** `pumpAndSettle`: the page carries a perpetual animation
/// (the shoe-preview's idle pulse), so "settled" never arrives and the helper
/// would time out rather than report the swipe. Fixed-duration pumps are enough
/// for a page snap — the ballistic scroll is over inside a few hundred
/// milliseconds — and they leave the assertion reading a decided page.
Future<void> _swipe(WidgetTester tester, double dx) async {
  final pager = tester.getRect(find.byType(PageView).first);
  await tester.flingFrom(
    Offset(pager.center.dx, pager.bottom - 160),
    Offset(dx, 0),
    1200,
  );
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// The photo the hero is currently drawing.
///
/// The hero carousel is the *innermost* `PageView` on the page now that the page
/// itself is a pager, so this reads the visible page's own carousel rather than
/// every image inside the outer one. `PageView.builder` builds only the visible
/// page, which is the page the shopper is looking at.
List<String> _heroPhotoUrls(WidgetTester tester) => tester
    .widgetList<CachedNetworkImage>(
      find.descendant(
        of: find.byType(PageView).last,
        matching: find.byType(CachedNetworkImage),
      ),
    )
    .map((image) => image.imageUrl)
    .toList();

/// The four providers the page's own build reads \u2014 all mocks, stubbed with the
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
