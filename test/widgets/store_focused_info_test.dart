import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/store.dart';
import 'package:app/screens/store/widgets/store_focused_info.dart';

/// The Stores tab's focused info strip must carry the same buyer-facing trust
/// signal the full store page does. The flag arrives on the store query as an
/// embedded profile, so both halves are pinned here: the parser and the badge.
Store _store({required bool sellerVerified}) => Store(
  id: 'store-1',
  name: 'LIDE BETH SHOE TRADING',
  location: 'Carcar',
  createdAt: DateTime(2026, 1, 1),
  sellerVerified: sellerVerified,
);

Widget _wrap(Store store) => MaterialApp(
  home: Scaffold(body: StoreFocusedInfo(store: store, productCount: 6)),
);

void main() {
  testWidgets('a verified store shows the Verified Seller badge', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_store(sellerVerified: true)));

    expect(find.text('LIDE BETH SHOE TRADING'), findsOneWidget);
    expect(find.text('Verified Seller'), findsOneWidget);
    expect(find.text('6 products'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unverified store stays unbadged', (tester) async {
    await tester.pumpWidget(_wrap(_store(sellerVerified: false)));

    expect(find.text('LIDE BETH SHOE TRADING'), findsOneWidget);
    expect(find.text('Verified Seller'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Store.fromMap reads the embedded profile flag', () {
    final verified = Store.fromMap({
      'id': 'store-1',
      'name': 'LIDE BETH SHOE TRADING',
      'location': 'Carcar',
      'created_at': '2026-01-01T00:00:00Z',
      'profiles': {'seller_verified_at': '2026-11-15T00:00:00Z'},
    });
    final unverified = Store.fromMap({
      'id': 'store-2',
      'name': 'Unverified Store',
      'location': 'Carcar',
      'created_at': '2026-01-01T00:00:00Z',
      'profiles': null,
    });

    expect(verified.sellerVerified, isTrue);
    expect(unverified.sellerVerified, isFalse);
  });
}
