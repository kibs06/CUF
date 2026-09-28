import 'dart:io';
import 'dart:typed_data';

import 'package:app/constants/app_constants.dart';
import 'package:app/exceptions/shoe_model_upload_exception.dart';
import 'package:app/models/product_models.dart';
import 'package:app/screens/seller/add_edit_product_screen.dart';
import 'package:app/services/product_service.dart';
import 'package:app/services/shoe_model_server_validator.dart';
import 'package:app/services/shoe_model_upload_service.dart';
import 'package:app/utils/fit_engine.dart';
import 'package:app/utils/shoe_model_upload.dart';
import 'package:app/widgets/sole_primary_button.dart';
import 'package:app/widgets/sole_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// The "3D Model" section of the product form: the seller fetches the handover
/// `.glb`, the app runs the authoring contract over it, and Save publishes it.
///
/// These tests run against the **real** service wired to fake sources, so the
/// digest, the version arithmetic and the row payload are production code with
/// only the socket and the table stubbed — a fake service would have let a
/// mistake in any of those through.
///
/// The flag-dependent tests need `--dart-define=SHOE_MODEL_UPLOAD=true`; the
/// flag-off test runs in a plain test run (it is the rollback guarantee).
void main() {
  // `testWidgets`'s `skip` is a bool only, so the reason for the skip lives in
  // the descriptions: flag-dependent tests need the dart-define above.
  final bool flagOn = AppConstants.shoeModelUploadEnabled;
  const url = 'https://example.test/handover/model.glb';

  late Uint8List fixture;

  setUpAll(() {
    fixture = File('assets/models/placeholder_shoe.glb').readAsBytesSync();
  });

  _ShoeModelHarness harness({
    List<Map<String, dynamic>>? existingRows,
    ShoeModelServerVerdict? verdict,
  }) {
    final bytes = _FakeBytesSource()..files[url] = fixture;
    final data = _FakeUploadDataSource(rows: existingRows);
    final validator = _FakeServerValidator(verdict: verdict);
    return _ShoeModelHarness(
      bytes: bytes,
      data: data,
      validator: validator,
      service: ShoeModelUploadService(
        bytesSource: bytes,
        dataSource: data,
        serverValidator: validator,
      ),
    );
  }

  group('the rollback guarantee', () {
    testWidgets('with the flag off the section is absent and nothing is fetched',
        (tester) async {
      final h = harness();
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
        shoeModelService: h.service,
      );

      expect(find.text('3D Model (Optional)'), findsNothing);
      expect(find.text('Check the file'), findsNothing);
      expect(find.text('Link to the .glb'), findsNothing);
      expect(h.bytes.requested, isEmpty);
    }, skip: flagOn);
  });

  group('the section', () {
    testWidgets('renders its fields with the flag on', (tester) async {
      final h = harness();
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
        shoeModelService: h.service,
      );
      await _scrollToBottom(tester);

      expect(find.text('3D Model (Optional)'), findsOneWidget);
      expect(_fieldFor('Link to the .glb'), findsOneWidget);
      expect(_fieldFor('Declared length (mm, outside)'), findsOneWidget);
      expect(_fieldFor('Authored at (EU size, optional)'), findsOneWidget);
      expect(find.text('Check the file'), findsOneWidget);
      expect(find.text('Right shoe'), findsOneWidget);
      expect(find.text('Left shoe'), findsOneWidget);
    }, skip: !flagOn);

    testWidgets('a compliant file reports a pass and offers to publish',
        (tester) async {
      final h = harness();
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '270');
      await _tapCheck(tester);

      expect(find.textContaining('All 11 checks passed'), findsOneWidget);
      // The numbers come from the validator's own report, not from prose.
      expect(find.textContaining('1536 triangles'), findsOneWidget);
      // The declared number and the mesh's own length are shown side by side,
      // with the delta already judged.
      expect(find.textContaining('Declared 270 mm'), findsOneWidget);
      expect(find.textContaining('within tolerance'), findsOneWidget);
      // A passing run states what it cannot see.
      expect(
        find.textContaining('not that it looks right'),
        findsOneWidget,
      );
      // And the publish decision is offered, because the file could ship.
      expect(find.textContaining('Publish it now'), findsOneWidget);
    }, skip: !flagOn);

    testWidgets('a declaration that disagrees names the failing check and '
        'withholds publishing', (tester) async {
      final h = harness();
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '285');
      await _tapCheck(tester);

      expect(find.textContaining('1 of 11 checks failed'), findsOneWidget);
      expect(find.textContaining('scale'), findsOneWidget);
      // Nothing may be published on the strength of a file that failed, and the
      // publish switch is absent rather than merely disabled.
      expect(find.textContaining('Publish it now'), findsNothing);
      expect(find.textContaining('Keep it as a draft'), findsNothing);
    }, skip: !flagOn);

    testWidgets('a link that is not https is refused in words', (tester) async {
      final h = harness();
      await _pumpForm(
        tester,
        service: _RecordingProductService(),
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', 'http://example.test/model.glb');
      await _type(tester, 'Declared length (mm, outside)', '270');
      await _tapCheck(tester);

      expect(find.textContaining('direct https link'), findsOneWidget);
      expect(h.bytes.requested, isEmpty,
          reason: 'a refused scheme must not reach the network');
    }, skip: !flagOn);
  });

  group('saving', () {
    testWidgets('publishes the checked model once the product is saved',
        (tester) async {
      final h = harness();
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '270');
      await _tapCheck(tester);
      await _save(tester);

      expect(service.updateProductCalled, isTrue);

      final digest = shoeModelSha256Hex(fixture);
      expect(h.data.putPaths.single, 'store-1/product-1/$digest.glb');
      expect(h.data.uploadedBytes.single, fixture);
      expect(h.data.order, ['put', 'insert']);

      final row = h.data.inserts.single;
      expect(row['product_id'], 'product-1');
      expect(row['sha256'], digest);
      expect(row['version'], 1);
      expect(
        row['status'],
        'draft',
        reason: 'the form may not write active — the server validator does '
            '(V2.4), and the database refuses it from here',
      );
      expect(row['authored_length_mm'], 270);
      expect(row['triangle_count'], 1536);

      // And the model is not published until the server has judged it: the row
      // the form just wrote is handed over by its id.
      expect(h.validator.askedModelIds, [1]);
    }, skip: !flagOn);

    testWidgets('a server refusal is reported as an error, and the model stays '
        'hidden', (tester) async {
      final h = harness(
        verdict: const ShoeModelServerVerdict(
          outcome: ShoeModelServerOutcome.rejected,
          status: 'rejected',
          failedChecks: ['materials'],
        ),
      );
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '270');
      await _tapCheck(tester);
      await _save(tester);

      // The product still saves (D8: a model never rolls a product back), but
      // the seller is told the server refused it and why.
      expect(service.updateProductCalled, isTrue);
      expect(find.textContaining('refused it'), findsOneWidget);
      expect(h.data.inserts.single['status'], 'draft');
    }, skip: !flagOn);

    testWidgets('no verdict leaves the model a draft and says so',
        (tester) async {
      final h = harness(
        verdict: const ShoeModelServerVerdict.undetermined(
          'could not reach the server',
        ),
      );
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '270');
      await _tapCheck(tester);
      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(find.textContaining('could not check it'), findsOneWidget);
      expect(h.data.inserts.single['status'], 'draft');
    }, skip: !flagOn);

    testWidgets('a file that failed the contract is never uploaded, and the '
        'product still saves', (tester) async {
      final h = harness();
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '285');
      await _tapCheck(tester);
      await _save(tester);

      // The product is the seller's work and must not be lost to a bad model.
      expect(service.updateProductCalled, isTrue);
      expect(h.data.order, isEmpty);
      expect(h.data.inserts, isEmpty);
    }, skip: !flagOn);

    testWidgets('a model upload failure still saves the product and says so',
        (tester) async {
      final h = harness();
      h.data.throwOnPut = ShoeModelUploadException('Bucket refused it.');
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _type(tester, 'Link to the .glb', url);
      await _type(tester, 'Declared length (mm, outside)', '270');
      await _tapCheck(tester);
      await _save(tester);

      expect(service.updateProductCalled, isTrue,
          reason: 'the product save must complete regardless of the model');
      expect(h.data.inserts, isEmpty);
      expect(find.textContaining('did not upload'), findsOneWidget);
    }, skip: !flagOn);

    testWidgets('no model staged means save never touches the model tables',
        (tester) async {
      final h = harness();
      final service = _RecordingProductService();
      await _pumpForm(
        tester,
        service: service,
        product: _productMap(),
        shoeModelService: h.service,
      );

      await _save(tester);

      expect(service.updateProductCalled, isTrue);
      expect(h.data.putPaths, isEmpty);
      expect(h.data.inserts, isEmpty);
    }, skip: !flagOn);
  });
}

/// Everything one test needs to watch the two fakes and drive the screen.
class _ShoeModelHarness {
  final _FakeBytesSource bytes;
  final _FakeUploadDataSource data;
  final _FakeServerValidator validator;
  final ShoeModelUploadService service;

  _ShoeModelHarness({
    required this.bytes,
    required this.data,
    required this.validator,
    required this.service,
  });
}

/// The server validator (V2.4), in memory: it records which rows it was asked
/// about and answers with the verdict the test wants.
class _FakeServerValidator implements ShoeModelServerValidator {
  final ShoeModelServerVerdict verdict;
  final List<int> askedModelIds = [];

  _FakeServerValidator({ShoeModelServerVerdict? verdict})
      : verdict = verdict ??
            const ShoeModelServerVerdict(
              outcome: ShoeModelServerOutcome.validated,
              status: 'active',
            );

  @override
  Future<ShoeModelServerVerdict> validate({
    required int modelId,
    bool activate = true,
  }) async {
    askedModelIds.add(modelId);
    return verdict;
  }
}

/// A [ProductService] that records what the form sends instead of talking to
/// Supabase. Anything the form does not call fails loudly.
class _RecordingProductService implements ProductService {
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

/// The socket, in memory.
class _FakeBytesSource implements ShoeModelBytesSource {
  final Map<String, Uint8List> files = {};
  final List<String> requested = [];

  @override
  Future<Uint8List> fetch(String url) async {
    requested.add(url);
    final bytes = files[url];
    if (bytes == null) throw Exception('no fake file for $url');
    return bytes;
  }
}

/// The bucket and the table, in memory — including the order of the writes.
class _FakeUploadDataSource implements ShoeModelUploadDataSource {
  final List<Map<String, dynamic>> rows;
  final List<String> order = [];
  final List<String> putPaths = [];
  final List<Uint8List> uploadedBytes = [];
  final List<Map<String, dynamic>> inserts = [];
  Object? throwOnPut;

  _FakeUploadDataSource({List<Map<String, dynamic>>? rows})
      : rows = rows ?? <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> rowsFor(String productId) async => rows;

  @override
  Future<void> putBytes({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    final failure = throwOnPut;
    if (failure != null) throw failure;
    order.add('put');
    putPaths.add(storagePath);
    uploadedBytes.add(bytes);
  }

  @override
  Future<Map<String, dynamic>> insertRow(Map<String, dynamic> row) async {
    order.add('insert');
    inserts.add(row);
    // What `insert ... select()` returns: the row the database stored, id and
    // all. The publisher needs that id to hand the row to the server.
    return {...row, 'id': 1};
  }

  @override
  Future<void> updateStatus({required int id, required String status}) async {}
}

/// A product map shaped like the ones the edit form is opened with, carrying
/// the minimum relations it needs to prefill and to pass its own save-time
/// validation (one image; every colour needs at least one photo).
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

Future<void> _pumpForm(
  WidgetTester tester, {
  required _RecordingProductService service,
  required Map<String, dynamic> product,
  required ShoeModelUploadService shoeModelService,
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
                  shoeModelUploadService: shoeModelService,
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

/// Scrolls to the section and presses "Check the file".
///
/// `pumpAndSettle` is not usable on this screen — something in it animates
/// forever, so settling never completes — hence fixed frames.
Future<void> _tapCheck(WidgetTester tester) async {
  await _scrollToBottom(tester);
  final button = find.text('Check the file');
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button, warnIfMissed: false);
  await _pumpFrames(tester, 6);
}

/// Presses save by invoking the callback the button is wired to: the button sits
/// at the bottom of a 5,500-line form, and on the 600 px test surface its hit
/// test resolves to the enclosing scrollable — a geometry puzzle unrelated to
/// what these tests assert. That `onPressed` is non-null is asserted, so a
/// disabled button cannot make a test pass by doing nothing.
///
/// The section's own action is an `OutlinedButton`, deliberately not a
/// `SolePrimaryButton`, so the single primary button here is Save.
Future<void> _save(WidgetTester tester) async {
  await _scrollToBottom(tester);
  final button = find.byType(SolePrimaryButton);
  expect(button, findsOneWidget,
      reason: 'the section\'s own action must not be a primary button');
  final save = tester.widget<SolePrimaryButton>(button);
  expect(save.onPressed, isNotNull, reason: 'save must be enabled');
  save.onPressed!();
  await _pumpFrames(tester, 6);
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
