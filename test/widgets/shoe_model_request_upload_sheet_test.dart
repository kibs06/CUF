import 'dart:io';
import 'dart:typed_data';

import 'package:app/services/shoe_model_request_service.dart';
import 'package:app/services/shoe_model_server_validator.dart';
import 'package:app/services/shoe_model_upload_service.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:app/utils/shoe_model_upload.dart';
import 'package:app/widgets/shoe_model_request_upload_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The admin's model upload — P2 of the request flow (roadmap V2.11).
///
/// Four things are worth more than the rest of this file, and they are the four
/// ways this sheet could quietly lie:
///
///  * **The seller's measurement is prefilled, and it is the external one** —
///    the figure the renderer scales to. The admin starts from the number
///    somebody measured with a ruler rather than from an empty box.
///  * **A declaration that drifts from it earns a note, not a refusal** — the
///    admin may know the seller measured the wrong pair.
///  * **Nothing here writes `active`.** The sheet calls the same
///    `ShoeModelUploadService.publish` the seller's form does, so the server
///    still decides; a fake validator proves the model only goes live when the
///    server says so.
///  * **A live model whose ask would not close is reported as BOTH** — the one
///    ending that must not be rounded to \"done\". The seller reads the request
///    row, so a silent success here would leave them waiting forever.
void main() {
  late Uint8List fixture;

  setUpAll(() {
    fixture = File('assets/models/placeholder_shoe.glb').readAsBytesSync();
  });

  testWidgets('off means the sheet renders nothing at all', (tester) async {
    await _openSheet(tester, enabled: false);
    expect(find.text('Upload the model'), findsNothing);
    expect(find.text('Check the file'), findsNothing);
  });

  testWidgets('⚠️ the seller\'s own measurement arrives prefilled',
      (tester) async {
    await _openSheet(tester, externalLengthMm: 272, measuredSizeEu: 42);

    expect(_fieldText(tester, 1), '272');
    expect(_fieldText(tester, 2), '42');
    // And it says where the number came from, so the admin knows it is a
    // measurement rather than an assumption.
    expect(find.textContaining('The seller measured 272 mm outside'),
        findsOneWidget);
  });

  testWidgets('a link that is not https is refused in words, and nothing is '
      'fetched', (tester) async {
    final bytes = _FakeBytes(fixture);
    await _openSheet(tester, bytes: bytes);

    await tester.enterText(_fieldOrNull(tester, 'Link to the .glb')!,
        'http://drive.example.com/shoe.glb');
    await tester.tap(find.text('Check the file'));
    await tester.pumpAndSettle();

    expect(find.textContaining('direct https link'), findsOneWidget);
    expect(bytes.requested, isEmpty,
        reason: 'a refused link must not reach the network');
  });

  testWidgets('a compliant file reports a pass and offers to publish',
      (tester) async {
    await _openSheet(tester, bytes: _FakeBytes(fixture));

    await _check(tester);

    expect(find.textContaining('All 11 checks passed'), findsOneWidget);
    final publish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Publish and close the request'),
    );
    expect(publish.onPressed, isNotNull);
  });

  testWidgets('publishing closes the ask, and the close names the model it made',
      (tester) async {
    final data = _FakeData();
    final requests = _FakeRequests();
    final result = await _openSheet(
      tester,
      bytes: _FakeBytes(fixture),
      data: data,
      requests: requests,
    );

    await _check(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Publish and close the request'),
    );
    await tester.pumpAndSettle();

    // The same write order the seller's form uses: bytes, then a draft row, then
    // the server's verdict. Nothing here writes `active` itself.
    expect(data.order, ['put', 'insert']);
    expect(data.putPaths.single, 'store-1/product-p-1/${_digest(fixture)}.glb');
    expect(data.inserts.single['status'], 'draft');
    expect(data.inserts.single['authored_length_mm'], 272);

    expect(requests.fulfilledRequestId, 'r-1');
    expect(requests.fulfilledModelId, 1);
    expect((await result)!.ending, ShoeModelRequestModellingEnding.closed);
    expect((await result)!.closed, isTrue);
  });

  testWidgets('⚠️ a live model that could not be closed is reported as both',
      (tester) async {
    final requests = _FakeRequests()..fulfilSucceeds = false;
    final result = await _openSheet(
      tester,
      bytes: _FakeBytes(fixture),
      requests: requests,
    );

    await _check(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Publish and close the request'),
    );
    await tester.pumpAndSettle();

    final outcome = (await result)!;
    expect(outcome.ending, ShoeModelRequestModellingEnding.liveButOpen);
    expect(outcome.modelIsLive, isTrue,
        reason: 'the model IS live — reporting a bare failure would be wrong');
    expect(outcome.requestStaysOpen, isTrue);
    expect(outcome.message, contains('could not be closed'));
    expect(outcome.modelId, 1);
  });

  testWidgets('a server refusal stays in the sheet and leaves the ask open',
      (tester) async {
    final requests = _FakeRequests();
    // The returned future is deliberately not awaited to a value: this attempt
    // has no ending, and the assertions below are about the sheet staying up.
    await _openSheet(
      tester,
      bytes: _FakeBytes(fixture),
      requests: requests,
      validator: _FakeValidator(
        shoeModelServerVerdictFrom(
          statusCode: 422,
          body: {
            'ok': false,
            'status': 'rejected',
            'report': {
              'checks': [
                {'name': 'scale', 'status': 'fail'},
              ],
            },
          },
        ),
      ),
    );

    await _check(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Publish and close the request'),
    );
    await tester.pumpAndSettle();

    // The file and the fields are still on screen, because the fix is usually in
    // one of them; and the close was never attempted against a non-live model.
    expect(find.textContaining('did not go live'), findsOneWidget);
    expect(find.textContaining('scale'), findsOneWidget);
    expect(requests.fulfilCalls, 0);
    // Still open, with the report and the fields the admin needs to fix it.
    expect(find.text('Upload the model'), findsOneWidget);
  });

  testWidgets('⚠️ the declared length is checked against the seller\'s ruler',
      (tester) async {
    await _openSheet(tester, externalLengthMm: 272, bytes: _FakeBytes(fixture));

    // The most expensive mistake this feature can make, arriving through the one
    // door it opened: a mesh scaled to a figure nobody measured.
    await tester.enterText(_fieldOrNull(tester, 'Declared length (mm, outside)')!,
        '292');
    await tester.pump();

    expect(find.textContaining('20 mm longer'), findsOneWidget);
    expect(find.textContaining('scales every size'), findsOneWidget);
  });

  testWidgets('a centimetre length is refused in the same words as the seller\'s '
      'form', (tester) async {
    await _openSheet(tester, externalLengthMm: 272, bytes: _FakeBytes(fixture));

    await tester.enterText(
        _fieldOrNull(tester, 'Declared length (mm, outside)')!, '27');
    await tester.pump();

    expect(find.textContaining('millimetres, not centimetres'), findsOneWidget);
  });
}

/// The sheet inside a route, opened the way the queue opens it, so the result it
/// pops can be captured. Returns the future that resolves with that result.
Future<Future<ShoeModelRequestModellingResult?>> _openSheet(
  WidgetTester tester, {
  double? externalLengthMm = 272,
  double? measuredSizeEu,
  _FakeBytes? bytes,
  _FakeData? data,
  _FakeRequests? requests,
  ShoeModelServerValidator? validator,
  bool enabled = true,
}) async {
  // A tall surface: the sheet is a form plus a report, and a tap on a control
  // that happens to be off-screen would test nothing.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late Future<ShoeModelRequestModellingResult?> result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                result = showModalBottomSheet<ShoeModelRequestModellingResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ShoeModelRequestUploadSheet(
                    request: _request(
                      externalLengthMm: externalLengthMm,
                      measuredSizeEu: measuredSizeEu,
                    ),
                    requestService: requests ?? _FakeRequests(),
                    uploadService: ShoeModelUploadService(
                      bytesSource: bytes ?? _FakeBytes(null),
                      dataSource: data ?? _FakeData(),
                      serverValidator: validator ?? _FakeValidator(null),
                    ),
                    enabled: enabled,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _check(WidgetTester tester) async {
  await tester.enterText(
      _fieldOrNull(tester, 'Link to the .glb')!, 'https://cdn.example.com/a.glb');
  await tester.tap(find.text('Check the file'));
  await tester.pumpAndSettle();
}

/// The `TextEditingController` text of the n-th field on screen. The sheet's
/// fields are link, length, size — in that order — and the note is only there
/// once a file has been checked.
String _fieldText(WidgetTester tester, int index) => tester
    .widget<TextField>(find.byType(TextField).at(index))
    .controller!
    .text;

Finder? _fieldOrNull(WidgetTester tester, String label) {
  final fields = find.byType(TextField);
  for (var i = 0; i < fields.evaluate().length; i++) {
    final widget = tester.widget<TextField>(fields.at(i));
    if (widget.decoration?.labelText == label) return fields.at(i);
  }
  return null;
}

ShoeModelRequestRecord _request({
  double? externalLengthMm = 272,
  double? measuredSizeEu,
}) =>
    ShoeModelRequestRecord(
      id: 'r-1',
      productId: 'product-p-1',
      storeId: 'store-1',
      statusWire: 'requested',
      status: ShoeModelRequestStatus.requested,
      externalLengthMm: externalLengthMm,
      measuredSizeEu: measuredSizeEu,
      productName: 'Chelsea Boot',
      storeName: 'Carcar Leather',
    );

/// The digest that is simultaneously the storage filename, the row's `sha256`
/// and the device cache key — so the object path asserted below is not a guess.
String _digest(Uint8List bytes) => shoeModelSha256Hex(bytes);

class _FakeBytes implements ShoeModelBytesSource {
  _FakeBytes(this.bytes);

  /// Null means "this test never gets as far as fetching".
  final Uint8List? bytes;

  final List<String> requested = [];

  @override
  Future<Uint8List> fetch(String url) async {
    requested.add(url);
    final data = bytes;
    if (data == null) {
      throw StateError('no bytes were staged for this test');
    }
    return data;
  }
}

class _FakeData implements ShoeModelUploadDataSource {
  final List<String> putPaths = [];
  final List<Map<String, dynamic>> inserts = [];
  final List<String> order = [];

  int _nextId = 0;

  @override
  Future<List<Map<String, dynamic>>> rowsFor(String productId) async => const [];

  @override
  Future<void> putBytes({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    order.add('put');
    putPaths.add(storagePath);
  }

  @override
  Future<Map<String, dynamic>> insertRow(Map<String, dynamic> row) async {
    order.add('insert');
    inserts.add(row);
    return {...row, 'id': ++_nextId};
  }

  @override
  Future<void> updateStatus({required int id, required String status}) async {
    order.add('status:$status');
  }
}

/// The server's answer, staged. Null means "the happy path" — the row is
/// published, which is what `validate-shoe-model` returning 200 means.
class _FakeValidator implements ShoeModelServerValidator {
  _FakeValidator(this.verdict);

  final ShoeModelServerVerdict? verdict;
  final List<int> askedModelIds = [];

  @override
  Future<ShoeModelServerVerdict> validate({
    required int modelId,
    bool activate = true,
  }) async {
    askedModelIds.add(modelId);
    return verdict ??
        shoeModelServerVerdictFrom(
          statusCode: 200,
          body: {'ok': true, 'status': 'active'},
        );
  }
}

class _FakeRequests extends ShoeModelRequestService {
  _FakeRequests() : super(_FakeRequestData());

  bool fulfilSucceeds = true;
  int fulfilCalls = 0;
  String? fulfilledRequestId;
  int? fulfilledModelId;

  @override
  Future<ShoeModelRequestOutcome> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  }) async {
    fulfilCalls++;
    fulfilledRequestId = requestId;
    fulfilledModelId = modelId;
    return ShoeModelRequestOutcome(
      success: fulfilSucceeds,
      message: fulfilSucceeds ? 'Fulfilled.' : 'That did not go through.',
    );
  }
}

class _FakeRequestData implements ShoeModelRequestDataSource {
  @override
  Future<ShoeModelRequestRecord?> latestForProduct(String productId) async =>
      null;

  @override
  Future<bool> productHasLiveModel(String productId) async => false;

  @override
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId) async =>
      const [];

  @override
  Future<List<ShoeModelRequestRecord>> forStore(String storeId) async =>
      const [];

  @override
  Future<List<ShoeModelRequestRecord>> queue() async => const [];

  @override
  Future<Object?> request({
    required String productId,
    required ShoeModelRequestMeasurements measurements,
    String? note,
  }) async =>
      null;

  @override
  Future<Object?> cancel(String requestId) async => null;

  @override
  Future<Object?> claim(String requestId) async => null;

  @override
  Future<Object?> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  }) async =>
      null;

  @override
  Future<Object?> decline({required String requestId, String? reason}) async =>
      null;
}
