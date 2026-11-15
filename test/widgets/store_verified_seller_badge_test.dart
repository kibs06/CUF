import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/store.dart';
import 'package:app/providers/cart_provider.dart';
import 'package:app/providers/follow_provider.dart';
import 'package:app/providers/product_provider.dart';
import 'package:app/providers/review_provider.dart';
import 'package:app/screens/store/store_profile_screen.dart';
import 'package:app/services/store_service.dart';

/// **The public store page carries the seller's Verified Seller badge, and a
/// pull-to-refresh picks a newly granted badge up.**
///
/// `profiles.seller_verified_at` is written by the approval trigger while the
/// seller is on another device, so the customer's already-open store page is
/// the surface that goes stale first. The page's own `RefreshIndicator` calls
/// the same `_loadData` that resolves `isSellerVerified`, so this pins both
/// halves: the badge renders from the real store page, and refreshing without
/// reopening the page makes it appear.
class _MockStoreService extends Mock implements StoreService {}

class _MockProductProvider extends Mock implements ProductProvider {}

class _MockReviewProvider extends Mock implements ReviewProvider {}

class _MockFollowProvider extends Mock implements FollowProvider {}

class _MockCartProvider extends Mock implements CartProvider {}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a verified owner shows the Verified Seller badge in the hero',
      (tester) async {
    await _pumpStore(tester, verified: true);

    expect(find.text('Verified Seller'), findsOneWidget,
        reason: 'the buyer-facing badge must render on the store page');
  });

  testWidgets('an unverified owner shows no badge, and pull-to-refresh picks '
      'up a badge granted while the page was open', (tester) async {
    final harness = await _pumpStore(tester, verified: false);
    expect(find.text('Verified Seller'), findsNothing);

    // The approval trigger lands on the other side of the app.
    harness.verified = true;

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(harness.isSellerVerifiedCalls, greaterThan(1),
        reason: 'refreshing must re-read the trust flag, not reuse a cached one');
    expect(find.text('Verified Seller'), findsOneWidget,
        reason: 'the refreshed page must show the badge without a reopen');
  });
}

class _Harness {
  bool verified = false;
  int isSellerVerifiedCalls = 0;
}

Future<_Harness> _pumpStore(WidgetTester tester,
    {required bool verified}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final storeService = _MockStoreService();
  final harness = _Harness()..verified = verified;

  final store = Store(
    id: 'store-1',
    name: 'Verified Footwear',
    location: 'Manila',
    ownerId: 'owner-1',
    createdAt: DateTime(2026, 1, 1),
  );

  when(() => storeService.fetchStoreById(any()))
      .thenAnswer((_) async => store);
  when(() => storeService.isSellerVerified(any())).thenAnswer((_) async {
    harness.isSellerVerifiedCalls++;
    return harness.verified;
  });
  when(() => storeService.getStoryEntriesForStore(any()))
      .thenAnswer((_) async => <Map<String, dynamic>>[]);
  when(() => storeService.getFollowerCount(any())).thenAnswer((_) async => 0);

  final products = _MockProductProvider();
  when(() => products.products).thenReturn(<Map<String, dynamic>>[]);
  when(() => products.loadProducts(hideOutOfStock: true))
      .thenAnswer((_) async {});

  final reviews = _MockReviewProvider();
  when(() => reviews.loadStoreLevelReviews(any())).thenAnswer((_) async {});
  when(() => reviews.storeLevelReviews).thenReturn(<Map<String, dynamic>>[]);
  when(() => reviews.myStoreReview).thenReturn(null);
  when(() => reviews.canReviewStore).thenReturn(false);
  when(() => reviews.isLoadingStoreLevelReviews).thenReturn(false);

  final follows = _MockFollowProvider();
  when(() => follows.isFollowing(any())).thenReturn(false);
  when(() => follows.followerCountFor(any(), fallback: any(named: 'fallback')))
      .thenReturn(0);

  final cart = _MockCartProvider();
  when(() => cart.itemCount).thenReturn(0);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductProvider>.value(value: products),
        ChangeNotifierProvider<ReviewProvider>.value(value: reviews),
        ChangeNotifierProvider<FollowProvider>.value(value: follows),
        ChangeNotifierProvider<CartProvider>.value(value: cart),
      ],
      child: MaterialApp(
        home: StoreProfileScreen(
          storeId: store.id,
          storeService: storeService,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}
