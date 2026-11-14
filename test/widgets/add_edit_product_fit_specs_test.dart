import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/models/product_models.dart';
import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';
import 'package:app/utils/fit_engine.dart';
import 'package:app/widgets/sole_primary_button.dart';

/// The "3D & fit" section was removed from the product form. These tests lock
/// that removal in — the fields must not render — while proving the important
/// half: an existing product's stored spec is still carried through untouched
/// on save, so removing the form section never wipes fit advice customers
/// already see.

class _RecordingProductService implements ProductService {
  FitSpecs? capturedFitSpecs;
  bool updateProductCalled = false;
  bool syncCalled = false;

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
    capturedFitSpecs = fitSpecs;
  }

  @override
  Future<String> createProduct({
    required String storeId,
    required String name,
    required String description,
    required double price,
    required String category,
    required List<String> tags,
    required List<XFile> images,
    required List<ProductVariant> variants,
    required List<ProductCustomization> customizations,
    List<ProductColor> colors = const [],
    bool isActive = true,
    bool isFeatured = false,
    String? barcode,
    double? salePrice,
    DateTime? saleStartsAt,
    DateTime? saleEndsAt,
    String? audience,
    FitSpecs? fitSpecs,
  }) async {
    updateProductCalled = true;
    capturedFitSpecs = fitSpecs;
    return 'product-1';
  }

  @override
  Future<void> syncProductActiveStatus(String productId) async {
    syncCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('unexpected ProductService call: ${invocation.memberName}');
}

Map<String, dynamic> _productMap({
  double? lastLengthMm,
  double? lastWidthMm,
  double? heelHeightMm,
  double? refSizeEu,
}) =>
    {
      'id': 'product-1',
      'name': 'Artisan Penny Loafer',
      'description': 'Handmade in Carcar.',
      'price': 1099.0,
      'category': 'Casual',
      'tags': const ['handmade'],
      'is_active': true,
      'is_featured': false,
      'last_length_mm': ?lastLengthMm,
      'last_width_mm': ?lastWidthMm,
      'heel_height_mm': ?heelHeightMm,
      'fit_ref_size_eu': ?refSizeEu,
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

Future<void> _pumpFrames(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -6000),
  );
  await _pumpFrames(tester, 2);
}

Future<void> _save(WidgetTester tester) async {
  await _scrollToBottom(tester);
  final button = find.byType(SolePrimaryButton);
  expect(button, findsOneWidget);
  final save = tester.widget<SolePrimaryButton>(button);
  expect(save.onPressed, isNotNull, reason: 'save must be enabled');
  save.onPressed!();
  await _pumpFrames(tester);
}

void main() {
  group('removed 3D & fit section', () {
    for (final label in const [
      'Last length (mm)',
      'Measured at (EU size)',
      'Last width (mm, optional)',
      'Heel height (mm, optional)',
      'How to measure your last',
    ]) {
      testWidgets('"$label" is not shown', (tester) async {
        await _pumpForm(
          tester,
          service: _RecordingProductService(),
          product: _productMap(
            lastLengthMm: 275,
            lastWidthMm: 98.5,
            heelHeightMm: 25,
            refSizeEu: 42,
          ),
        );
        await _scrollToBottom(tester);
        expect(find.text(label), findsNothing);
      });
    }

    testWidgets('an existing spec survives a save untouched', (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(
          lastLengthMm: 275,
          lastWidthMm: 98,
          heelHeightMm: 25,
          refSizeEu: 42,
        ),
      );

      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(service.capturedFitSpecs, isNotNull);
      expect(service.capturedFitSpecs!.lastLengthMm, 275);
      expect(service.capturedFitSpecs!.lastWidthMm, 98);
      expect(service.capturedFitSpecs!.heelHeightMm, 25);
      expect(service.capturedFitSpecs!.refSizeEu, 42);
    });

    testWidgets('a product with no spec still saves a null spec',
        (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
      );

      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(service.capturedFitSpecs, isNull);
    });
  });
}
