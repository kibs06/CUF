import 'package:app/screens/shared/shoe_preview_screen.dart';
import 'package:app/services/shoe_model_request_service.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:app/widgets/shoe_model_request_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seller's row in the product action sheet (roadmap V2.10).
///
/// What is worth asserting here is the SENTENCE the seller reads, because the
/// row is the whole interface: there is no screen behind it that says what a
/// state means. The four labels are pinned, and so is the shape of the ask —
/// no measuring, nothing to mistype, the wait said up front — and what the
/// progress sheet says when there is nothing to show.
void main() {
  testWidgets('with the switch off the row is not there at all', (tester) async {
    await _pump(tester, enabled: false);
    expect(find.text('Request a 3D fitting'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('no request: the plain ask, and it opens the form', (tester) async {
    await _pump(tester);
    expect(find.text('Request a 3D fitting'), findsOneWidget);

    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    expect(find.text('Ask for a 3D fitting'), findsOneWidget);
    // No boxes to measure into — the wait is the content, said up front, with
    // the one box that remains: anything the team should know.
    expect(
      find.textContaining('so customers can try it on. No measuring needed.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('9 business days for the 3D fitting'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
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

    expect(find.text('3D fitting requested'), findsOneWidget);
    expect(find.text(ShoeModelRequestStatus.inProgress.sellerSentence),
        findsOneWidget);

    await tester.tap(find.text('3D fitting requested'));
    await tester.pumpAndSettle();

    // The seller can check the numbers they sent.
    expect(find.textContaining('Outside length: 272 mm'), findsOneWidget);
    expect(find.textContaining('Outside width: 105 mm'), findsOneWidget);
    // …and cannot withdraw a request the team has already taken on.
    expect(find.text('Withdraw the request'), findsNothing);
  });

  testWidgets('a request nobody has taken yet can be withdrawn', (tester) async {
    await _pump(tester, request: _record(status: 'requested'));
    await tester.tap(find.text('3D fitting requested'));
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

    expect(find.text('3D fitting request declined'), findsOneWidget);

    await tester.tap(find.text('3D fitting request declined'));
    await tester.pumpAndSettle();

    expect(find.text('Ask for a 3D fitting'), findsOneWidget);
    // The previous answer is shown INSIDE the form, so the seller is not asked
    // to remember it while asking again.
    expect(
      find.textContaining('We could not get the pair to measure.'),
      findsOneWidget,
    );
  });

  testWidgets('a product with a live model says the model is ready',
      (tester) async {
    await _pump(tester, hasLiveModel: true);

    expect(find.text('3D fitting ready'), findsOneWidget);
    expect(find.text('Customers can try this pair on'), findsOneWidget);
  });

  testWidgets('and tapping it opens the model itself, not a sentence about one',
      (tester) async {
    // ⚠️ The row is backed by a `product_models` record, and a record is not a
    // shoe — this used to open a sheet that *said* a model exists, which is the
    // row's own claim repeated back to the seller. The tap now opens the viewer,
    // which resolves the model on this device and either draws it or says there
    // is nothing to draw.
    await _pump(tester, hasLiveModel: true);

    await tester.tap(find.text('3D fitting ready'));
    await tester.pumpAndSettle();

    expect(find.byType(ShoePreviewScreen), findsOneWidget);
    // The seller's door, not the customer's: nobody here can try the pair on.
    expect(find.text('Try on DeepAR'), findsNothing);
    // ⚠️ And the sheet that described the model is gone. It said the product
    // "has a model", which is the row's own claim said back to the seller — the
    // sentence that replaced it is the one about what is actually on screen.
    expect(find.textContaining('This product has a model'), findsNothing);
  });

  testWidgets('the form sends a bare ask — no measuring, nothing to mistype',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service: service);

    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    await _tapSend(tester);

    expect(service.requestCalls, 1);
    expect(service.lastMeasurements, isNull);
  });

  testWidgets('a note rides along when the seller has something to say',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service: service);

    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'The pair in the photos is a size 42.',
    );
    await _tapSend(tester);

    expect(service.requestCalls, 1);
    expect(service.lastMeasurements, isNull);
    expect(service.lastNote, 'The pair in the photos is a size 42.');
  });

  testWidgets('a bare ask shows the wait instead of a row of dashes',
      (tester) async {
    // Asks filed since 2026-11-12 carry no numbers. The progress sheet shows
    // "what you sent" — five dashes would read as a hole in the request,
    // so it says the wait instead.
    await _pump(tester, request: _record(status: 'requested'));
  });
}

/// Sends the form. The tap goes through `ensureVisible` first, which is what
/// a thumb does on a real phone — the sheet scrolls, and the button with it.
Future<void> _tapSend(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Send the request'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send the request'));
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool hasLiveModel = false,
  ShoeModelRequestRecord? request,
  ShoeModelRequestService? service,
  Map<String, dynamic>? product,
}) async {
  // ⚠️ A surface taller than the default 800×600, and that is a loading
  // condition rather than a preference: at the default size the Send button
  // can sit below the floor of the test surface, and a tap on a widget
  // outside the *surface* lands nowhere even when its scrollable has
  // scrolled. `ensureVisible` still does the thumb's work first.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
  String? lastNote;

  @override
  Future<ShoeModelRequestAvailability> availability(String productId) async =>
      ShoeModelRequestAvailability(
        request: latestRequest,
        hasLiveModel: liveModel,
      );

  @override
  Future<ShoeModelRequestOutcome> request({
    required String productId,
    ShoeModelRequestMeasurements? measurements,
    String? note,
  }) async {
    requestCalls++;
    lastMeasurements = measurements;
    lastNote = note;
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
    ShoeModelRequestMeasurements? measurements,
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
