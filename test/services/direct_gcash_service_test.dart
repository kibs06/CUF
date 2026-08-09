import 'package:app/services/direct_gcash_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingGcashItem.fromJson', () {
    test('extracts the first product image by display_order', () {
      final item = PendingGcashItem.fromJson({
        'product_id': 'p1',
        'size': '42',
        'quantity': 2,
        'unit_price': 195.0,
        'products': {
          'name': 'Classic Leather Loafers',
          'product_images': [
            {'image_url': 'second.jpg', 'display_order': 2},
            {'image_url': 'first.jpg', 'display_order': 1},
          ],
        },
      });

      expect(item.productId, 'p1');
      expect(item.productName, 'Classic Leather Loafers');
      expect(item.imageUrl, 'first.jpg'); // lowest display_order wins
      expect(item.size, '42');
      expect(item.quantity, 2);
      expect(item.unitPrice, 195.0);
      expect(item.lineTotal, 390.0);
    });

    test('falls back when the product or its images are missing', () {
      final noImages = PendingGcashItem.fromJson({
        'product_id': 'p1',
        'quantity': 1,
        'unit_price': 50,
        'products': {'name': 'No Pic Boot', 'product_images': []},
      });
      expect(noImages.imageUrl, isNull);
      expect(noImages.productName, 'No Pic Boot');

      final noProduct = PendingGcashItem.fromJson({
        'product_id': 'p1',
        'quantity': 1,
        'unit_price': 50,
      });
      expect(noProduct.imageUrl, isNull);
      expect(noProduct.productName, isEmpty);
      expect(noProduct.size, isEmpty);
    });
  });

  group('PendingGcashOrder.fromJson', () {
    test('parses order fields and nested order_items', () {
      final order = PendingGcashOrder.fromJson(
        {
          'id': 'order-64fabc26',
          'store_id': 'store-1',
          'total_amount': 490.0,
          'payment_confirmation_deadline': '2026-08-08T10:00:00.000Z',
          'created_at': '2026-08-08T09:30:00.000Z',
          'status': 'awaiting_payment_confirmation',
          'order_items': [
            {
              'product_id': 'p1',
              'size': '42',
              'quantity': 1,
              'unit_price': 390.0,
              'products': {
                'name': 'Classic Leather Loafers',
                'product_images': [
                  {'image_url': 'hero.jpg', 'display_order': 0},
                ],
              },
            },
            {
              'product_id': 'p2',
              'size': '43',
              'quantity': 2,
              'unit_price': 50.0,
              'products': {
                'name': 'Suede Chelsea Boots',
                'product_images': [],
              },
            },
          ],
        },
        proofSubmitted: true,
      );

      expect(order.id, 'order-64fabc26');
      expect(order.storeId, 'store-1');
      expect(order.totalAmount, 490.0);
      expect(order.deadline, isNotNull);
      expect(order.createdAt, isNotNull);
      expect(order.proofSubmitted, isTrue);
      expect(order.items, hasLength(2));
      expect(order.itemCount, 3); // 1 + 2
      expect(order.items.first.imageUrl, 'hero.jpg');
      expect(order.items.last.imageUrl, isNull);
      expect(order.items.last.lineTotal, 100.0);
    });

    test('handles missing order_items and unknown values defensively', () {
      final order = PendingGcashOrder.fromJson(
        {
          'id': 'o1',
          'store_id': 's1',
          'order_items': null,
        },
        proofSubmitted: false,
      );

      expect(order.id, 'o1');
      expect(order.storeId, 's1');
      expect(order.totalAmount, 0);
      expect(order.deadline, isNull);
      expect(order.createdAt, isNull);
      expect(order.items, isEmpty);
      expect(order.itemCount, 0);
    });
  });
}
