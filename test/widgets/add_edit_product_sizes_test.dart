import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/models/product_models.dart';
import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';
import 'package:app/utils/fit_engine.dart';

/// A [ProductService] that records whether a write happened instead of talking
/// to Supabase. Only the calls the form actually makes are implemented; anything
/// else fails loudly, so a test can never pass by exercising a path it did not
/// mean to.
class _RecordingProductService implements ProductService {
  bool updateProductCalled = false;

  @override
  Future<String?> getSellerStoreId() async => 'store-1';

  @override
  Future<void> updateProduct({
    required String productId,
    required String name,
    required String description,
    required double price,
    required String category,
    required List<String> tags,
    required List<XFile> newImages,
    required List<String> existingImageUrls,
    required List<ProductVariant> variants,
    required List<ProductCustomization> customizations,
    List<ProductColor> colors = const [],
    required bool isActive,
    required bool isFeatured,
    String? barcode,
    double? salePrice,
    DateTime? saleStartsAt,
    DateTime? saleEndsAt,
    String? audience,
    FitSpecs? fitSpecs,
  }) async {
    updateProductCalled = true;
  }

  @override
  Future<void> syncProductActiveStatus(String productId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('unexpected ProductService call: ${invocation.memberName}');
}

/// A stored product shaped like `getSellerProduct` returns one, carrying the
/// minimum the edit form needs to prefill and pass its earlier checks — one
/// product image, one colour with a photo — so the ONLY thing left to refuse is
/// the variant set under test.
///
/// `sizes` empty is not "a product with no sizes yet": hydration builds colours
/// from `product_variants`, and an empty list leaves `_colors` empty, which the
/// form refuses earlier with "Please add at least 1 color." A colour with photos
/// and a size-less variant — which is what a colour card opened and given photos
/// but never a size produces — is the shape this guard exists for, so that is
/// what a blank size models here.
Map<String, dynamic> _productMap({required List<String> sizes}) => {
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
        for (var i = 0; i < sizes.length; i++)
          {
            'id': 'variant-$i',
            'size': sizes[i],
            'stock': 2,
            'color': 'Black',
          },
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

/// Pumps the form as a pushed route, mirroring how Manage Products opens it, so
/// the save path's `Navigator.pop` has somewhere to go.
Future<void> _pumpForm(
  WidgetTester tester, {
  required _RecordingProductService service,
  required Map<String, dynamic> product,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddEditProductScreen(
                  product: product,
                  productService: service,
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
}

Future<void> _save(WidgetTester tester) async {
  final save = find.text('Update Product');
  await tester.ensureVisible(save);
  await tester.pump();
  await tester.tap(save);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  const refusal =
      'Please add at least 1 size. A product with no sizes cannot be sold.';

  testWidgets('refuses to save a product with no sizes', (tester) async {
    /*
      The product-level version of the size sheet's own rule. A product with no
      sizes has nothing in `inventory`, and every customer surface drops a
      product whose total stock is zero — so without this it saves, publishes
      itself and appears to nobody. The web portal's `productProblems` holds the
      same rule, so the two clients refuse the same invisible product.
    */
    final service = _RecordingProductService();
    await _pumpForm(
      tester,
      service: service,
      product: _productMap(sizes: const ['']),
    );

    await _save(tester);

    expect(find.text(refusal), findsOneWidget);
    expect(service.updateProductCalled, isFalse,
        reason: 'nothing should have been written');
    // The form is still open — the save returned, it did not pop.
    expect(find.text('Update Product'), findsOneWidget);
  });

  testWidgets('saves a product that has at least one size', (tester) async {
    final service = _RecordingProductService();
    await _pumpForm(
      tester,
      service: service,
      product: _productMap(sizes: const ['EU 42']),
    );

    await _save(tester);

    expect(service.updateProductCalled, isTrue);
    expect(find.text(refusal), findsNothing);
  });

  testWidgets('a size beside a blank one still saves', (tester) async {
    // The guard is "at least one real size", not "no blank sizes anywhere" — a
    // product with one size and one empty row is a product that can be sold.
    final service = _RecordingProductService();
    await _pumpForm(
      tester,
      service: service,
      product: _productMap(sizes: const ['EU 42', '']),
    );

    await _save(tester);

    expect(service.updateProductCalled, isTrue);
    expect(find.text(refusal), findsNothing);
  });
}
