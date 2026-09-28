import 'dart:io';
import 'dart:typed_data';

import 'package:app/constants/app_constants.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/review_provider.dart';
import 'package:app/screens/customer/product_detail_screen.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:app/services/try_on_prefetch.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The V2.6 prefetch is the one thing on this screen that reaches the network
/// without the customer asking for anything — so the property worth testing here
/// is not that it warms a model (that is `test/services/try_on_prefetch_test.dart`,
/// against a temp cache and fake rows) but that **the product page is never
/// worse off for it**.
///
/// The tests mount the real `ProductDetailScreen`. Every case asserts both
/// halves: the prefetch really ran with this product (so a page that ignored the
/// feature could not pass by doing nothing), and the page rendered exactly as it
/// does without it — name, price, and the Add to Cart control, with no exception
/// surfacing.
///
/// **Why the failure modes here stop at the cache.** `testWidgets` runs inside a
/// fake-async zone, where `tester.pump` advances a fake clock and a real
/// `dart:io` future — `File.exists()`, the verified `.glb` write — never
/// completes. Every path through `ShoeModelService.ensureLocal` starts with that
/// file call, so the download stage cannot be driven to completion from a widget
/// test; opening `tester.runAsync` to allow it also lets the *unrelated*
/// runtime font fetch (`google_fonts`, whose families are downloaded and not
/// bundled) run and fail as a test error, which would make this file test the
/// harness instead of the page. The download, integrity and cache-hit paths are
/// therefore pinned where they belong — in the service tests, with a temp
/// directory and real I/O — and what is proven *here* is that the page survives
/// the failures it can be given: resolution (the un-applied table, a dead
/// network) and an unavailable cache.
void main() {
  initialiseAndRun();
}

void initialiseAndRun() {
  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('product_prefetch_test');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  Uint8List bytesOf(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => (i * 7) % 256));

  /// A prefetch whose model read fails with [error].
  TryOnPrefetch failingPrefetch(_FakeModelSource source) => TryOnPrefetch(
        enabled: true,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: () async => tempRoot,
        ),
      );

  group('a prefetch that fails leaves the page untouched', () {
    testWidgets('a model table that does not exist yet', (tester) async {
      // The shipped state of V2: the migration is un-applied, so every read of
      // `product_models` fails. A build with the switch on must look exactly
      // like today's.
      final source = _FakeModelSource()
        ..rowsError = Exception('relation "product_models" does not exist');

      await _pumpPage(tester, prefetch: failingPrefetch(source));

      expect(source.rowsCalls, 1, reason: 'the prefetch really ran');
      expect(source.productIds, ['product-1']);
      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    });

    testWidgets('a network error while reading the rows', (tester) async {
      final source = _FakeModelSource()
        ..rowsError = const SocketException('offline');

      await _pumpPage(tester, prefetch: failingPrefetch(source));

      expect(source.rowsCalls, 1);
      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    });

    testWidgets('a cache it cannot use', (tester) async {
      // The first thing the write path does is ask for the cache directory.
      // A refusal there is the whole storage stage's failure mode, and it is
      // reachable without real I/O — the provider is the injected seam.
      final source = _FakeModelSource()..rows = [_modelRow(bytesOf(64))];
      final prefetch = TryOnPrefetch(
        enabled: true,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: () async =>
              throw const FileSystemException('read-only'),
        ),
      );

      await _pumpPage(tester, prefetch: prefetch);

      expect(source.rowsCalls, 1, reason: 'the prefetch really ran');
      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    });

    testWidgets('a product with no model at all', (tester) async {
      // Not a failure, but the common case today — nothing has been uploaded —
      // and the one that must be indistinguishable from the feature being off.
      final source = _FakeModelSource();

      await _pumpPage(tester, prefetch: failingPrefetch(source));

      expect(source.rowsCalls, 1);
      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    });
  });

  group('the switch', () {
    testWidgets('off means the page never reads the model table', (tester) async {
      final source = _FakeModelSource()..rows = [_modelRow(bytesOf(64))];
      final prefetch = TryOnPrefetch(
        enabled: false,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: () async => tempRoot,
        ),
      );

      await _pumpPage(tester, prefetch: prefetch);

      expect(source.rowsCalls, 0);
      expect(source.downloadCalls, 0);
      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    });

    testWidgets('with the shipped default and no seam, the page mounts clean',
        (tester) async {
      // A plain run: the screen builds its own prefetch, which is disabled, so
      // nothing is read and the page is exactly today's. This is the rollback
      // guarantee at the page level.
      await tester.pumpWidget(_wrapPage(ProductDetailScreen(product: _product)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    }, skip: AppConstants.tryOnPrefetchEnabled);

    testWidgets('with the switch ON and no seam, the real wiring is still safe',
        (tester) async {
      // The production path in its worst state: the screen constructs a real
      // `TryOnPrefetch`, which reads a `product_models` table that is **not
      // applied**, through real Supabase. The page must be unaffected — this is
      // the configuration someone flipping the flag early would ship.
      await tester.pumpWidget(_wrapPage(ProductDetailScreen(product: _product)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_pageRendered(), isTrue);
      await _expectNoException(tester);
    }, skip: !AppConstants.tryOnPrefetchEnabled);
  });
}

/// What the page must still show after any prefetch outcome: its name, its
/// price, and the control the customer came for.
bool _pageRendered() =>
    find.text('Artisan Penny Loafer').evaluate().isNotEmpty &&
    find.textContaining('1099').evaluate().isNotEmpty &&
    find.text('Add to Cart').evaluate().isNotEmpty;

Future<void> _expectNoException(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull,
      reason: 'a prefetch may never surface an error into the page');
}

Map<String, dynamic> _modelRow(Uint8List bytes) => {
      'id': 1,
      'variant_id': null,
      'storage_path': 'store-1/product-1/model.glb',
      'sha256': sha256.convert(bytes).toString(),
      'version': 1,
      'shoe_side': 'right',
    };

/// A product complete enough that the page renders without touching Supabase:
/// sizes come from `inventory` + `product_variants`, and the variants carry
/// colours so the page never fires its `_fetchVariantColors` read.
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
      ],
      'inventory': const [
        {'size': 'EU 42', 'stock': 3},
      ],
      'product_customizations': const [],
    };

Future<void> _pumpPage(
  WidgetTester tester, {
  required TryOnPrefetch prefetch,
}) async {
  await tester.pumpWidget(_wrapPage(ProductDetailScreen(
    product: _product,
    tryOnPrefetch: prefetch,
  )));
  // The prefetch is fire-and-forget: a few frames let its resolution stage —
  // which is pure async, no device I/O — land before the assertions read the
  // fake's counters.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The four providers the page's own build reads — all mocks, stubbed with the
/// members the page (and the cart button) touch. `CartProvider` cannot be
/// constructed in a test at all: its constructor reaches for
/// `Supabase.instance`, which is un-initialised under `flutter test`.
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

/// The read seam, in memory: rows from a list, bytes from a map, and an error
/// for the read side so a test can make resolution fail.
class _FakeModelSource implements ShoeModelDataSource {
  List<Map<String, dynamic>> rows = [];
  Map<String, Uint8List> files = {};
  Object? rowsError;
  final List<String> productIds = [];
  int downloadCalls = 0;

  int get rowsCalls => productIds.length;

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async {
    productIds.add(productId);
    final failure = rowsError;
    if (failure != null) throw failure;
    return rows;
  }

  @override
  Future<Uint8List> download(String storagePath) async {
    downloadCalls++;
    final bytes = files[storagePath];
    if (bytes == null) throw Exception('Object not found: $storagePath');
    return bytes;
  }
}
