import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/models/product_models.dart';
import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';
import 'package:app/utils/fit_engine.dart';

/// A [ProductService] that records the barcode the form saves instead of
/// talking to Supabase. Anything else fails loudly.
class _RecordingProductService implements ProductService {
  bool updateProductCalled = false;
  String? savedBarcode;

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
    savedBarcode = barcode;
  }

  @override
  Future<void> syncProductActiveStatus(String productId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('unexpected ProductService call: ${invocation.memberName}');
}

Map<String, dynamic> _productMap({String? barcode}) {
  final map = <String, dynamic>{
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
        {
          'id': 'variant-0',
          'size': 'EU 42',
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
  if (barcode case final code?) map['barcode'] = code;
  return map;
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required _RecordingProductService service,
  required Map<String, dynamic> product,
}) async {
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
  testWidgets('a coded product shows its system label and keeps it on save',
      (tester) async {
    const code = '2001234567893';
    final service = _RecordingProductService();
    await _pumpForm(
      tester,
      service: service,
      product: _productMap(barcode: code),
    );

    // The seller sees the code and its scannable preview — no typing.
    expect(find.text(code), findsWidgets);
    expect(find.text('IN-STORE USE ONLY'), findsOneWidget);
    expect(find.text('Generate in-store barcode'), findsNothing);

    await _save(tester);

    expect(service.updateProductCalled, isTrue);
    expect(service.savedBarcode, code);
  });

  testWidgets('a codeless product is saved with null so the system assigns it',
      (tester) async {
    final service = _RecordingProductService();
    await _pumpForm(
      tester,
      service: service,
      product: _productMap(),
    );

    // No field to type into — the form says the system handles it.
    expect(find.textContaining('assigns one automatically'), findsOneWidget);
    expect(find.text('Generate in-store barcode'), findsNothing);

    await _save(tester);

    expect(service.updateProductCalled, isTrue);
    // Null reaches the service, which generates the in-store EAN-13.
    expect(service.savedBarcode, isNull);
  });
}
