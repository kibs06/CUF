import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/models/product_models.dart';
import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';

/// A [ProductService] that records what the form sends instead of talking to
/// Supabase.
///
/// Only the calls the form actually makes are implemented; anything else fails
/// loudly, so a test can never pass by silently exercising a path it did not
/// mean to. The point of recording the raw `audience` argument is that it is
/// the only place the difference between "Not set" (`null`) and `''` is visible
/// — an empty string would be rejected by the column's CHECK constraint, and a
/// `null` is what clears it.
class _RecordingProductService implements ProductService {
  String? capturedAudience;
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
  }) async {
    updateProductCalled = true;
    capturedAudience = audience;
  }

  @override
  Future<void> syncProductActiveStatus(String productId) async {
    syncCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('unexpected ProductService call: ${invocation.memberName}');
}

/// A product map shaped like the ones `getSellerProduct`/`getProduct` return,
/// with the minimum relations the edit form needs to prefill and to pass its
/// own save-time validation (at least one product image; every color needs at
/// least one photo).
Map<String, dynamic> _productMap({
  String? audience,
  List<String> sizes = const ['EU 42'],
  String category = 'Casual',
}) =>
    {
      'id': 'product-1',
      'name': 'Artisan Penny Loafer',
      'description': 'Handmade in Carcar.',
      'price': 1099.0,
      'category': category,
      'tags': const ['handmade'],
      'is_active': true,
      'is_featured': false,
      'audience': audience,
      'product_images': [
        {
          'id': 'image-1',
          'image_url': 'https://example.test/one.jpg',
          'display_order': 0,
        },
      ],
      'product_variants': [
        for (final size in sizes)
          {'id': 'variant-$size', 'size': size, 'stock': 2, 'color': 'Black'},
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

/// Pumps the form as a pushed route (mirroring how Manage Products opens it, so
/// the save path's `Navigator.pop` has somewhere to go).
///
/// Tears the tree down first: a bare re-`pumpWidget` of the same widget types
/// REUSES the existing `Navigator` state, so a test that pumps a second form
/// (e.g. "reopen the saved product") would otherwise leave the first one on top
/// of the stack and tap the wrong thing.
Future<void> _pumpForm(
  WidgetTester tester, {
  required _RecordingProductService service,
  Map<String, dynamic>? product,
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

Future<void> _tapChip(WidgetTester tester, String key) async {
  final chip = find.byKey(ValueKey(key));
  expect(chip, findsOneWidget, reason: 'chip $key should exist');
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  // Chip selection animates (the shared _TagChip pop), so settle past it.
  await tester.pump(const Duration(milliseconds: 400));
}

/// Reads the chip's own selected state straight off the Semantics node the
/// shared `_TagChip` publishes — the same signal a screen reader uses.
bool _chipSelected(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return semantics.properties.selected ?? false;
}

Future<void> _save(WidgetTester tester) async {
  final save = find.text('Update Product');
  await tester.ensureVisible(save);
  await tester.pump();
  await tester.tap(save);
  // The save is async (service call → snackbar → pop) and the pop runs a route
  // transition whose cleanup lands in a post-frame callback, so give it several
  // frames rather than one long duration pump.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('audience chip group', () {
    testWidgets('offers the closed set plus an explicit "Not set"',
        (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
      );

      // Scoped to this group: the category and tag selectors in the same form
      // own "+ Other" chips of their own, so an unscoped assertion would be
      // asserting something about them instead.
      final group = find.byKey(const ValueKey('audience-chip-group'));
      expect(group, findsOneWidget);

      for (final label in ["Men's", "Women's", "Kids'", 'Unisex', 'Not set']) {
        expect(
          find.descendant(of: group, matching: find.text(label)),
          findsOneWidget,
          reason: '$label chip should be in the audience group',
        );
      }

      // Closed set: no "+ Other" chip and no free-text input for this field,
      // unlike the category/tag selectors above it.
      expect(
        find.descendant(of: group, matching: find.text('Other')),
        findsNothing,
      );
      expect(
        find.descendant(of: group, matching: find.byType(TextField)),
        findsNothing,
      );
      // Clearing is a deliberate act, not an absence.
      expect(
        find.descendant(of: group, matching: find.text('Not set')),
        findsOneWidget,
      );
    });

    testWidgets('a product with no audience selects "Not set"', (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
      );

      expect(_chipSelected(tester, 'audience-chip-not-set'), isTrue);
      for (final value in ['men', 'women', 'kids', 'unisex']) {
        expect(_chipSelected(tester, 'audience-chip-$value'), isFalse);
      }
    });

    testWidgets('a stored audience is preselected on edit — and only it',
        (tester) async {
      // Prefill, for every real value: the chip the product already has is the
      // chip that is shown selected.
      for (final value in ['men', 'women', 'kids', 'unisex']) {
        await _pumpForm(
          tester,
          service: _RecordingProductService(),
          product: _productMap(audience: value),
        );

        expect(
          _chipSelected(tester, 'audience-chip-$value'),
          isTrue,
          reason: 'stored "$value" should be preselected',
        );
        expect(_chipSelected(tester, 'audience-chip-not-set'), isFalse,
            reason: 'stored "$value" is not "Not set"');
        for (final other in ['men', 'women', 'kids', 'unisex']) {
          if (other == value) continue;
          expect(_chipSelected(tester, 'audience-chip-$other'), isFalse,
              reason: 'only one chip may be selected');
        }
      }
    });

    testWidgets('an unrecognised stored value falls back to "Not set"',
        (tester) async {
      // The vocabulary never guesses, so a value we don't recognise must not
      // silently preselect the nearest audience.
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(audience: 'Men'),
      );

      expect(_chipSelected(tester, 'audience-chip-not-set'), isTrue);
      expect(_chipSelected(tester, 'audience-chip-men'), isFalse);
    });
  });

  group('saving the audience', () {
    testWidgets('round-trips all four values through the service',
        (tester) async {
      for (final value in ['men', 'women', 'kids', 'unisex']) {
        final service = _RecordingProductService();
        await _pumpForm(
          tester,
          service: service,
          product: _productMap(),
        );

        await _tapChip(tester, 'audience-chip-$value');
        expect(_chipSelected(tester, 'audience-chip-$value'), isTrue);

        await _save(tester);
        expect(service.updateProductCalled, isTrue);
        expect(service.capturedAudience, value);

        // Reopening the saved product shows the same value selected — what the
        // seller sees after a save is what they picked.
        await _pumpForm(
          tester,
          service: _RecordingProductService(),
          product: _productMap(audience: service.capturedAudience),
        );
        expect(_chipSelected(tester, 'audience-chip-$value'), isTrue);
      }
    });

    testWidgets('"Not set" clears to null, never to an empty string',
        (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(audience: 'women'),
      );

      expect(_chipSelected(tester, 'audience-chip-women'), isTrue);

      await _tapChip(tester, 'audience-chip-not-set');
      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      // `''` would be rejected by the column's CHECK constraint; only `null`
      // clears a stored audience.
      expect(service.capturedAudience, isNull);
    });

    testWidgets('leaving an unset audience alone writes null, not a guess',
        (tester) async {
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
      );

      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(service.capturedAudience, isNull);
    });
  });

  group("Kids' audience vs adult sizes", () {
    const warning = '⚠ These sizes look like adult sizing — check the '
        'audience is right.';

    testWidgets('warns when every stocked size is an adult size',
        (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(
          audience: 'kids',
          sizes: const ['EU 40', 'EU 42', 'EU 44'],
        ),
      );

      expect(find.text(warning), findsOneWidget);
    });

    testWidgets('stays quiet for a kids-sized product', (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(audience: 'kids', sizes: const ['EU 28']),
      );

      expect(find.text(warning), findsNothing);
    });

    testWidgets('is one-directional: adult audiences are never checked',
        (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(
          audience: 'men',
          sizes: const ['EU 42', 'EU 43'],
        ),
      );

      expect(find.text(warning), findsNothing);
    });

    testWidgets('appears and disappears as the audience chip changes',
        (tester) async {
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(sizes: const ['EU 42']),
      );
      expect(find.text(warning), findsNothing);

      await _tapChip(tester, 'audience-chip-kids');
      expect(find.text(warning), findsOneWidget);

      // Never blocking: the warning is a note, not a validator.
      await _save(tester);
      expect(find.text(warning), findsNothing,
          reason: 'the form should have saved and closed');

      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(audience: 'kids', sizes: const ['EU 42']),
      );
      await _tapChip(tester, 'audience-chip-unisex');
      expect(find.text(warning), findsNothing);
    });
  });
}
