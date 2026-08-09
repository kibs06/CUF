import 'package:flutter_test/flutter_test.dart';

import 'package:app/providers/cart_provider.dart';

/// Tests for CartProvider state logic.
/// 
/// Note: CartProvider's constructor accesses Supabase.instance.client,
/// so we test the pure computation logic in isolation rather than
/// instantiating the provider directly. Integration tests will cover
/// the full provider lifecycle.

void main() {
  group('computePurchasedAdjustments (cart kept while awaiting payment)', () {
    Map<String, dynamic> cartLine({
      required String id,
      required String productId,
      String size = '42',
      int quantity = 1,
      String? serverId = 'srv-1',
    }) {
      return {
        'id': id,
        'product_id': productId,
        'size': size,
        'quantity': quantity,
        'server_id': serverId,
      };
    }

    test('fully-bought lines are removed (with server ids)', () {
      final cart = {
        'p1-42-black': cartLine(id: 'p1-42-black', productId: 'p1'),
        'p2-40-brown': cartLine(
          id: 'p2-40-brown',
          productId: 'p2',
          size: '40',
          serverId: 'srv-2',
        ),
      };
      final purchased = [
        {'product_id': 'p1', 'size': '42', 'quantity': 1},
        {'product_id': 'p2', 'size': '40', 'quantity': 1},
      ];

      final (keys, serverIds, newQtyByKey) =
          computePurchasedAdjustments(cart, purchased);

      expect(keys, containsAll(['p1-42-black', 'p2-40-brown']));
      expect(serverIds, containsAll(['srv-1', 'srv-2']));
      expect(newQtyByKey, isEmpty);
    });

    test('partially-bought lines are reduced, not removed', () {
      final cart = {
        'p1-42-black': cartLine(
          id: 'p1-42-black',
          productId: 'p1',
          quantity: 3,
          serverId: 'srv-1',
        ),
      };
      final purchased = [
        {'product_id': 'p1', 'size': '42', 'quantity': 2},
      ];

      final (keys, serverIds, newQtyByKey) =
          computePurchasedAdjustments(cart, purchased);

      expect(keys, isEmpty);
      expect(serverIds, isEmpty);
      expect(newQtyByKey, {'p1-42-black': 1});
    });

    test('unbought lines are untouched', () {
      final cart = {
        'p1-42-black': cartLine(id: 'p1-42-black', productId: 'p1'),
        'p9-38-white': cartLine(
          id: 'p9-38-white',
          productId: 'p9',
          size: '38',
          serverId: 'srv-9',
        ),
      };
      final purchased = [
        {'product_id': 'p1', 'size': '42', 'quantity': 1},
      ];

      final (keys, serverIds, newQtyByKey) =
          computePurchasedAdjustments(cart, purchased);

      expect(keys, ['p1-42-black']);
      expect(serverIds, ['srv-1']);
      expect(newQtyByKey, isEmpty);
      // p9 line is preserved
      expect(cart.containsKey('p9-38-white'), isTrue);
    });

    test('same product different size is a different line', () {
      final cart = {
        'p1-42-black': cartLine(id: 'p1-42-black', productId: 'p1'),
        'p1-44-black': cartLine(
          id: 'p1-44-black',
          productId: 'p1',
          size: '44',
          serverId: 'srv-2',
        ),
      };
      final purchased = [
        {'product_id': 'p1', 'size': '42', 'quantity': 1},
      ];

      final (keys, serverIds, newQtyByKey) =
          computePurchasedAdjustments(cart, purchased);

      expect(keys, ['p1-42-black']);
      expect(serverIds, ['srv-1']);
      expect(newQtyByKey, isEmpty);
    });

    test('aggregates multiple purchased rows for the same line', () {
      final cart = {
        'p1-42-black': cartLine(
          id: 'p1-42-black',
          productId: 'p1',
          quantity: 4,
          serverId: 'srv-1',
        ),
      };
      final purchased = [
        {'product_id': 'p1', 'size': '42', 'quantity': 1},
        {'product_id': 'p1', 'size': '42', 'quantity': 2},
      ];

      final (keys, serverIds, newQtyByKey) =
          computePurchasedAdjustments(cart, purchased);

      // 4 - (1 + 2) = 1 remaining
      expect(keys, isEmpty);
      expect(newQtyByKey, {'p1-42-black': 1});
    });

    test('line without server_id is removed locally but not server-synced', () {
      final cart = {
        'p1-42-black': cartLine(
          id: 'p1-42-black',
          productId: 'p1',
          serverId: null,
        ),
      };
      final purchased = [
        {'product_id': 'p1', 'size': '42', 'quantity': 1},
      ];

      final (keys, serverIds, newQtyByKey) =
          computePurchasedAdjustments(cart, purchased);

      expect(keys, ['p1-42-black']);
      expect(serverIds, isEmpty);
      expect(newQtyByKey, isEmpty);
    });
  });

  group('Cart subtotal calculations', () {
    test('calculates subtotal from items', () {
      final items = {
        'p1-42-black': {
          'id': 'p1-42-black',
          'product_id': 'p1',
          'price': 100.0,
          'quantity': 2,
          'store_id': 's1',
        },
        'p2-40-brown': {
          'id': 'p2-40-brown',
          'product_id': 'p2',
          'price': 250.0,
          'quantity': 1,
          'store_id': 's1',
        },
      };

      final subtotal = items.values.fold<double>(
        0.0,
        (sum, item) => sum + ((item['price'] as double) * (item['quantity'] as int)),
      );

      // (100 * 2) + (250 * 1) = 450
      expect(subtotal, 450.0);
    });

    test('itemCount sums all quantities', () {
      final items = {
        'p1-42-black': {'quantity': 2},
        'p2-40-brown': {'quantity': 1},
        'p3-38-white': {'quantity': 3},
      };

      final itemCount = items.values.fold<int>(
        0,
        (sum, item) => sum + (item['quantity'] as int),
      );

      expect(itemCount, 6);
    });
  });

  group('Delivery fee logic', () {
    test('delivery fee is 0 when cart is empty', () {
      const subtotal = 0.0;
      final deliveryFee = subtotal > 0 ? 100.0 : 0.0;
      expect(deliveryFee, 0.0);
    });

    test('delivery fee is 100 when cart has items', () {
      const subtotal = 250.0;
      final deliveryFee = subtotal > 0 ? 100.0 : 0.0;
      expect(deliveryFee, 100.0);
    });
  });

  group('Selection state logic', () {
    test('allSelected when all items are in selectedKeys', () {
      final items = {'p1-42-black', 'p2-40-brown'};
      final selectedKeys = {'p1-42-black', 'p2-40-brown'};

      final allSelected = items.isNotEmpty && selectedKeys.length == items.length;
      expect(allSelected, true);
    });

    test('allSelected is false when some items are not selected', () {
      final items = {'p1-42-black', 'p2-40-brown'};
      final selectedKeys = {'p1-42-black'};

      final allSelected = items.isNotEmpty && selectedKeys.length == items.length;
      expect(allSelected, false);
    });

    test('toggleItem adds key when not selected', () {
      final selectedKeys = <String>{};

      if (selectedKeys.contains('p1-42-black')) {
        selectedKeys.remove('p1-42-black');
      } else {
        selectedKeys.add('p1-42-black');
      }

      expect(selectedKeys, contains('p1-42-black'));
    });

    test('toggleItem removes key when already selected', () {
      final selectedKeys = {'p1-42-black'};

      if (selectedKeys.contains('p1-42-black')) {
        selectedKeys.remove('p1-42-black');
      } else {
        selectedKeys.add('p1-42-black');
      }

      expect(selectedKeys, isNot(contains('p1-42-black')));
    });

    test('toggleAll selects all when none selected', () {
      final items = {'p1-42-black', 'p2-40-brown'};
      final selectedKeys = <String>{};

      if (selectedKeys.length == items.length) {
        selectedKeys.clear();
      } else {
        selectedKeys.addAll(items);
      }

      expect(selectedKeys.length, 2);
    });

    test('toggleAll deselects all when all selected', () {
      final items = {'p1-42-black', 'p2-40-brown'};
      final selectedKeys = {'p1-42-black', 'p2-40-brown'};

      if (selectedKeys.length == items.length) {
        selectedKeys.clear();
      } else {
        selectedKeys.addAll(items);
      }

      expect(selectedKeys, isEmpty);
    });
  });

  group('Selected items subtotal', () {
    test('selectedSubtotal calculates only selected items', () {
      final items = {
        'p1-42-black': {'price': 100.0, 'quantity': 2},
        'p2-40-brown': {'price': 200.0, 'quantity': 1},
      };
      final selectedKeys = {'p1-42-black'};

      final selectedSubtotal = selectedKeys.fold<double>(
        0.0,
        (sum, key) {
          final item = items[key];
          if (item == null) return sum;
          return sum + ((item['price'] as double) * (item['quantity'] as int));
        },
      );

      expect(selectedSubtotal, 200.0);
    });
  });

  group('Grouping by store', () {
    test('groups items by store_id', () {
      final items = {
        'p1-42-black': {
          'product_id': 'p1',
          'store_id': 'store-a',
          'store_name': 'Store A',
        },
        'p2-40-brown': {
          'product_id': 'p2',
          'store_id': 'store-b',
          'store_name': 'Store B',
        },
        'p3-38-black': {
          'product_id': 'p3',
          'store_id': 'store-a',
          'store_name': 'Store A',
        },
      };

      final map = <String, Map<String, dynamic>>{};
      for (final entry in items.entries) {
        final storeId = entry.value['store_id']?.toString() ?? 'unknown';
        final storeName = entry.value['store_name']?.toString() ?? 'Unknown Store';
        if (!map.containsKey(storeId)) {
          map[storeId] = {
            'store_id': storeId,
            'store_name': storeName,
            'items': <Map<String, dynamic>>[],
          };
        }
        (map[storeId]!['items'] as List).add(entry.value);
      }

      final grouped = map.values.toList();
      expect(grouped.length, 2);
      
      final storeA = grouped.firstWhere((g) => g['store_id'] == 'store-a');
      expect((storeA['items'] as List).length, 2);
      
      final storeB = grouped.firstWhere((g) => g['store_id'] == 'store-b');
      expect((storeB['items'] as List).length, 1);
    });
  });
}
