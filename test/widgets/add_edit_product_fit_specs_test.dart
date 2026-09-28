import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/models/product_models.dart';
import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';
import 'package:app/utils/fit_engine.dart';
import 'package:app/widgets/sole_primary_button.dart';
import 'package:app/widgets/sole_text_field.dart';

/// The "3D & fit" section of the product form: the four numbers a fit verdict
/// is computed from, and the one place in the form where a plausible-looking
/// typo is worse than a missing value.
///
/// The point of these tests is the seam the screen cannot show: what the form
/// hands the service. `null` and "no spec" have to stay distinguishable from
/// "a spec was entered" all the way to `ProductService`, and a rejected entry
/// has to stop the save rather than be dropped on the floor.

/// A [ProductService] that records what the form sends instead of talking to
/// Supabase. Anything the form does not call fails loudly, so a test can never
/// pass by exercising a path it did not mean to.
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

/// A product map shaped like the ones the edit form is opened with, carrying
/// the minimum relations it needs to prefill and to pass its own save-time
/// validation (one image; every colour needs at least one photo).
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

Finder _fieldFor(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(SoleTextField),
    );

String _textIn(WidgetTester tester, String label) =>
    tester.widget<SoleTextField>(_fieldFor(label)).controller!.text;

Future<void> _type(WidgetTester tester, String label, String value) async {
  final field = _fieldFor(label);
  expect(field, findsOneWidget, reason: 'field "$label" should exist');
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextFormField)),
    value,
  );
}

/// Scrolls the form to its bottom, the way a seller does, then taps save.
///
/// The form is far taller than the 600 px test surface, and this section sits
/// near its end — tapping a widget that is below the fold misses silently
/// (`tap` warns and does nothing), which is exactly how a test ends up
/// asserting that nothing was saved while never having pressed save.
/// Pumps a few fixed frames.
///
/// `pumpAndSettle` is not usable on this screen: something in it animates
/// forever, so settling never completes and the helper times out instead.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  // `drag` releases with no fling velocity, so there is no ballistic phase to
  // wait out — a few frames are enough.
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -6000),
  );
  await _pumpFrames(tester, 2);
}

/// Presses save.
///
/// Invokes the callback the button is wired to rather than synthesising a tap.
/// The button sits at the very bottom of a 5,200-line form, and on the 600 px
/// test surface its render box reports one position while the hit test resolves
/// to the enclosing scrollable — a geometry puzzle that has nothing to do with
/// what these tests are about. What they *are* about is the argument the form
/// hands `ProductService`, and `onPressed` is the path that produces it; that
/// `onPressed` is non-null is asserted below, so a disabled button cannot make
/// a test pass by doing nothing.
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
  group('prefill', () {
    testWidgets('shows the stored spec, whole numbers without a decimal point',
        (tester) async {
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

      expect(_textIn(tester, 'Last length (mm)'), '275');
      expect(_textIn(tester, 'Measured at (EU size)'), '42');
      expect(_textIn(tester, 'Last width (mm, optional)'), '98.5');
      expect(_textIn(tester, 'Heel height (mm, optional)'), '25');
    });

    testWidgets('a product with no spec prefills blank', (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
      );

      expect(_textIn(tester, 'Last length (mm)'), '');
      expect(_textIn(tester, 'Measured at (EU size)'), '');
      expect(_textIn(tester, 'Last width (mm, optional)'), '');
      expect(_textIn(tester, 'Heel height (mm, optional)'), '');
    });

    testWidgets('a stored spec the engine would refuse prefills blank',
        (tester) async {
      // A length whose reference size was never recorded cannot be graded.
      // Showing it would invite the seller to save a number the app ignores.
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(lastLengthMm: 275),
      );

      expect(_textIn(tester, 'Last length (mm)'), '');
      expect(_textIn(tester, 'Measured at (EU size)'), '');
    });
  });

  group('saving', () {
    testWidgets('sends the entered spec to the service', (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
      );

      await _type(tester, 'Last length (mm)', '275');
      await _type(tester, 'Measured at (EU size)', '42');
      await _type(tester, 'Last width (mm, optional)', '98');
      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(service.capturedFitSpecs, isNotNull);
      expect(service.capturedFitSpecs!.lastLengthMm, 275);
      expect(service.capturedFitSpecs!.lastWidthMm, 98);
      expect(service.capturedFitSpecs!.refSizeEu, 42);
      // Not measured, so it must arrive as absent rather than as a number.
      expect(service.capturedFitSpecs!.heelHeightMm, isNull);
    });

    testWidgets('a length with its size is enough', (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(tester, service: service, product: _productMap());

      await _type(tester, 'Last length (mm)', '275');
      await _type(tester, 'Measured at (EU size)', '42.5');
      await _save(tester);

      expect(service.capturedFitSpecs!.lastLengthMm, 275);
      expect(service.capturedFitSpecs!.refSizeEu, 42.5);
      expect(service.capturedFitSpecs!.lastWidthMm, isNull);
    });

    testWidgets('clearing all four fields sends a null spec, clearing the row',
        (tester) async {
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

      for (final label in const [
        'Last length (mm)',
        'Last width (mm, optional)',
        'Heel height (mm, optional)',
        'Measured at (EU size)',
      ]) {
        await _type(tester, label, '');
      }
      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(service.capturedFitSpecs, isNull);
    });
  });

  group('refusals stop the save', () {
    testWidgets('a centimetre slip is refused inline, and nothing is sent',
        (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(tester, service: service, product: _productMap());

      await _type(tester, 'Last length (mm)', '27.5');
      await _type(tester, 'Measured at (EU size)', '42');
      await _save(tester);

      expect(
        find.textContaining('not centimetres'),
        findsOneWidget,
        reason: 'the units mistake should be named under the field',
      );
      expect(service.updateProductCalled, isFalse);
    });

    testWidgets('a length with no reference size is refused', (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(tester, service: service, product: _productMap());

      await _type(tester, 'Last length (mm)', '275');
      await _save(tester);

      expect(find.textContaining('Say which EU size'), findsOneWidget);
      expect(service.updateProductCalled, isFalse);
    });

    testWidgets('a width with no length is refused', (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(tester, service: service, product: _productMap());

      await _type(tester, 'Measured at (EU size)', '42');
      await _type(tester, 'Last width (mm, optional)', '98');
      await _save(tester);

      expect(find.textContaining('Add the last length'), findsOneWidget);
      expect(service.updateProductCalled, isFalse);
    });

    testWidgets('a US size is refused by name', (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(tester, service: service, product: _productMap());

      await _type(tester, 'Last length (mm)', '275');
      await _type(tester, 'Measured at (EU size)', 'US 9');
      await _save(tester);

      expect(find.textContaining('looks like a US size'), findsOneWidget);
      expect(service.updateProductCalled, isFalse);
    });
  });

  group('the measuring guide', () {
    testWidgets('opens from the section and says to measure inside the shoe',
        (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
      );

      final guide = find.text('How to measure your last');
      await tester.ensureVisible(guide);
      await _pumpFrames(tester, 2);
      await tester.tap(guide);
      await _pumpFrames(tester);

      // The single most load-bearing instruction: the outside of a sole is
      // 8–15 mm longer, which is half a size.
      expect(find.textContaining('inside the shoe'), findsWidgets);
      expect(find.textContaining('millimetres'), findsWidgets);
      // And the honest exit for a seller who has not measured yet.
      expect(find.textContaining('Leave all four fields empty'), findsOneWidget);
    });
  });
}
