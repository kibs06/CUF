import 'package:app/services/shoe_model_request_service.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:app/widgets/shoe_model_request_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seller's row in the product action sheet (roadmap V2.10).
///
/// What is worth asserting here is the SENTENCE the seller reads, because the
/// row is the whole interface: there is no screen behind it that says what a
/// state means. The four labels are pinned, and so is the one thing that would
/// be expensive to get wrong — that the form refuses a centimetre figure before
/// anything is sent.
void main() {
  testWidgets('with the switch off the row is not there at all', (tester) async {
    await _pump(tester, enabled: false);
    expect(find.text('Request a 3D model'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('no request: the plain ask, and it opens the form', (tester) async {
    await _pump(tester);
    expect(find.text('Request a 3D model'), findsOneWidget);

    await tester.tap(find.text('Request a 3D model'));
    await tester.pumpAndSettle();

    expect(find.text('Ask for a 3D model'), findsOneWidget);
    // The length is the required field, and the copy says which measurement it
    // wants — outside the shoe, heel to toe.
    expect(find.textContaining('outside the shoe'), findsOneWidget);
  });

  testWidgets('an open request says the team is on it, and shows what was sent',
      (tester) async {
    await _pump(
      tester,
      request: _record(
        status: 'in_progress',
        externalLengthMm: 272,
        externalWidthMm: 105,
        measuredSizeEu: 42,
      ),
    );

    expect(find.text('3D model requested'), findsOneWidget);
    expect(find.text(ShoeModelRequestStatus.inProgress.sellerSentence),
        findsOneWidget);

    await tester.tap(find.text('3D model requested'));
    await tester.pumpAndSettle();

    // The seller can check the numbers they sent.
    expect(find.textContaining('Outside length: 272 mm'), findsOneWidget);
    expect(find.textContaining('Outside width: 105 mm'), findsOneWidget);
    // …and cannot withdraw a request the team has already taken on.
    expect(find.text('Withdraw the request'), findsNothing);
  });

  testWidgets('a request nobody has taken yet can be withdrawn', (tester) async {
    await _pump(tester, request: _record(status: 'requested'));
    await tester.tap(find.text('3D model requested'));
    await tester.pumpAndSettle();
    expect(find.text('Withdraw the request'), findsOneWidget);
  });

  testWidgets('a declined request shows why, and offers the ask again',
      (tester) async {
    await _pump(
      tester,
      request: _record(
        status: 'declined',
        adminNote: 'We could not get the pair to measure.',
      ),
    );

    expect(find.text('3D model request declined'), findsOneWidget);

    await tester.tap(find.text('3D model request declined'));
    await tester.pumpAndSettle();

    expect(find.text('Ask for a 3D model'), findsOneWidget);
    // The previous answer is shown INSIDE the form, so the seller is not asked
    // to remember it while retyping the numbers.
    expect(
      find.textContaining('We could not get the pair to measure.'),
      findsOneWidget,
    );
  });

  testWidgets('a product with a live model says the model is ready',
      (tester) async {
    await _pump(tester, hasLiveModel: true);

    expect(find.text('3D model ready'), findsOneWidget);
    expect(find.text('Customers can try this pair on'), findsOneWidget);

    await tester.tap(find.text('3D model ready'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This product has a model'), findsOneWidget);
  });

  testWidgets('the form refuses centimetres before it sends anything',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service: service);

    await tester.tap(find.text('Request a 3D model'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      '27', // centimetres, and the most likely way a seller gets this wrong
    );
    await tester.tap(find.text('Send the request'));
    await tester.pump();

    expect(find.textContaining('millimetres, not centimetres'), findsOneWidget);
    expect(service.requestCalls, 0);
  });

  testWidgets('a complete form sends once, with the numbers that were typed',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service: service, product: const {
      'heel_height_mm': 25.0,
      'fit_ref_size_eu': 42.0,
    });

    await tester.tap(find.text('Request a 3D model'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '272');
    await tester.tap(find.text('Send the request'));
    await tester.pump();

    expect(service.requestCalls, 1);
    expect(service.lastMeasurements!.externalLengthMm, 272);
    // The heel and the size came from the product's fit spec.
    expect(service.lastMeasurements!.heelHeightMm, 25);
    expect(service.lastMeasurements!.measuredSizeEu, 42);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool hasLiveModel = false,
  ShoeModelRequestRecord? request,
  ShoeModelRequestService? service,
  Map<String, dynamic>? product,
}) async {
  // Built as its own local so the setters below resolve against the fake's
  // type rather than the service supertype `service ?? fake` would infer.
  final fake = _FakeService();
  fake.latestRequest = request;
  fake.liveModel = hasLiveModel;
  final resolved = service ?? fake;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ShoeModelRequestTile(
          productId: 'p-1',
          product: product,
          service: resolved,
          enabled: enabled,
        ),
      ),
    ),
  );
  // Two frames: one for the availability future, one to rebuild with it. Not
  // pumpAndSettle, because the loading state's spinner never settles.
  await tester.pump();
  await tester.pump();
}

ShoeModelRequestRecord _record({
  required String status,
  double? externalLengthMm,
  double? externalWidthMm,
  double? measuredSizeEu,
  String? adminNote,
}) =>
    ShoeModelRequestRecord(
      id: 'r-1',
      productId: 'p-1',
      storeId: 's-1',
      statusWire: status,
      status: ShoeModelRequestStatus.parse(status),
      externalLengthMm: externalLengthMm,
      externalWidthMm: externalWidthMm,
      measuredSizeEu: measuredSizeEu,
      adminNote: adminNote,
    );

class _FakeService extends ShoeModelRequestService {
  _FakeService() : super(_FakeData());

  ShoeModelRequestRecord? latestRequest;
  bool liveModel = false;
  int requestCalls = 0;
  ShoeModelRequestMeasurements? lastMeasurements;

  @override
  Future<ShoeModelRequestAvailability> availability(String productId) async =>
      ShoeModelRequestAvailability(
        request: latestRequest,
        hasLiveModel: liveModel,
      );

  @override
  Future<ShoeModelRequestOutcome> request({
    required String productId,
    required ShoeModelRequestMeasurements measurements,
    String? note,
  }) async {
    requestCalls++;
    lastMeasurements = measurements;
    return const ShoeModelRequestOutcome(
      success: true,
      message: 'Request sent.',
    );
  }
}

class _FakeData implements ShoeModelRequestDataSource {
  @override
  Future<ShoeModelRequestRecord?> latestForProduct(String productId) async => null;

  @override
  Future<bool> productHasLiveModel(String productId) async => false;

  @override
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId) async =>
      const [];

  @override
  Future<List<ShoeModelRequestRecord>> forStore(String storeId) async => const [];

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
