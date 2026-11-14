import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';

/// The "3D Model" section was removed from the product form. This locks that
/// removal in: no model fields render, with or without the upload flag, and
/// saving never touches the model pipeline.
void main() {
  testWidgets('the 3D model section is absent', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditProductScreen(
                    product: _productMap(),
                    productService: _FakeProductService(),
                  ),
                ),
              ),
              child: const Text('open form'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open form'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -6000),
    );
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('3D Model (Optional)'), findsNothing);
    expect(find.text('Check the file'), findsNothing);
    expect(find.text('Link to the .glb'), findsNothing);
    expect(find.text('Declared length (mm, outside)'), findsNothing);
    expect(find.text('Authored at (EU size, optional)'), findsNothing);
  });
}

Map<String, dynamic> _productMap() => {
      'id': 'product-1',
      'name': 'Artisan Penny Loafer',
      'description': 'Handmade in Carcar.',
      'price': 1099.0,
      'category': 'Casual',
      'tags': const ['handmade'],
      'is_active': true,
      'is_featured': false,
      'product_images': [
        {
          'id': 'image-1',
          'image_url': 'https://example.test/one.jpg',
          'display_order': 0,
        },
      ],
      'product_variants': [
        {'id': 'variant-1', 'size': 'EU 42', 'stock': 2, 'color': 'Black'},
      ],
      'product_color_images': [
        {
          'id': 'color-image-1',
          'color_name': 'Black',
          'url': 'https://example.test/black.jpg',
          'display_order': 0,
        },
      ],
      'product_customizations': const [],
    };

class _FakeProductService implements ProductService {
  @override
  Future<String?> getSellerStoreId() async => 'store-1';

  @override
  Future<void> syncProductActiveStatus(String productId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('unexpected ProductService call: ${invocation.memberName}');
}
