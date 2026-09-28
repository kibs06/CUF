import 'package:app/constants/app_constants.dart';
import 'package:app/screens/admin/manage_shoe_model_requests_screen.dart';
import 'package:app/services/shoe_model_request_service.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The admin queue for 3D model requests (roadmap V2.10).
///
/// Two rules are worth more than the rest of this file, and both are about not
/// letting "done" become a claim rather than a fact:
///
///  * **"Close as done" cannot be pressed into success.** With no live model to
///    attach, it explains instead of calling the RPC — and the RPC would refuse
///    anyway, which is the belt to this braces.
///  * **A decline carries a reason**, because the seller reads that sentence in
///    their own sheet; the button is disabled until there is one.
///
/// The **upload** action (roadmap V2.11, P2) is the third rule, and it is the
/// only part of this screen behind a switch. Its flag-dependent tests need
/// `--dart-define=ADMIN_MODEL_UPLOAD=true`; the flag-off test runs in a plain
/// test run, because that is the rollback guarantee.
void main() {
  // Two switches have to be on for the action to exist (its own, and the
  // pipeline's write flag), and `testWidgets`'s `skip` is a bool only — so the
  // reason for each skip lives in the description above.
  final bool uploadOn = AppConstants.adminModelUploadAllowed;
  testWidgets('the queue is partitioned into the three tabs that matter',
      (tester) async {
    await _pump(tester, requests: [
      _record(id: 'r-1', status: 'requested'),
      _record(id: 'r-2', status: 'in_progress'),
      _record(id: 'r-3', status: 'fulfilled', modelId: 9),
      _record(id: 'r-4', status: 'declined', adminNote: 'no pair'),
    ]);

    expect(find.text('Waiting (2)'), findsOneWidget);
    expect(find.text('Fulfilled (1)'), findsOneWidget);
    // Declined and withdrawn are one tab: both are closed and neither is work.
    expect(find.text('Closed (1)'), findsOneWidget);
  });

  testWidgets('a waiting request shows the seller\'s numbers and the actions',
      (tester) async {
    await _pump(tester, requests: [
      _record(
        id: 'r-1',
        status: 'requested',
        externalLengthMm: 272,
        externalWidthMm: 105,
        heelHeightMm: 25,
        measuredSizeEu: 42,
        note: 'Samples with the team.',
      ),
    ]);

    expect(
      find.text('Outside: 272 mm long · 105 mm wide · 25 mm heel · measured at EU 42'),
      findsOneWidget,
    );
    expect(find.text('Seller: Samples with the team.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Close as done'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
    // Nobody has claimed it, so it can be taken.
    expect(find.text("I'll do it"), findsOneWidget);
  });

  testWidgets('a claimed request is not offered to a second admin',
      (tester) async {
    await _pump(tester, requests: [
      _record(id: 'r-1', status: 'in_progress', assignedTo: 'admin-1'),
    ]);
    expect(find.text("I'll do it"), findsNothing);
    expect(find.text('Taken'), findsOneWidget);
  });

  testWidgets('⚠️ a decline needs a reason before it can be sent',
      (tester) async {
    final service = _FakeService(requests: [_record(id: 'r-1')]);
    await _pump(tester, service: service);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Decline this request?'), findsOneWidget);

    // Disabled with an empty box — the seller gets nothing from a bare no.
    var button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Decline'));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'We could not get the pair.');
    await tester.pump();
    button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Decline'));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(service.declinedRequestId, 'r-1');
    expect(service.declineReason, 'We could not get the pair.');
  });

  testWidgets('⚠️ close as done with no live model explains, and calls nothing',
      (tester) async {
    final service = _FakeService(
      requests: [_record(id: 'r-1')],
      models: [
        // A draft is not a model a customer can render, so it must not be
        // offered — and must not be silently accepted either.
        {'id': 3, 'status': 'draft', 'version': 1, 'authored_length_mm': 270},
      ],
    );
    await _pump(tester, service: service);

    await tester.tap(find.widgetWithText(FilledButton, 'Close as done'));
    await tester.pumpAndSettle();

    expect(find.text('No live model to attach'), findsOneWidget);
    expect(find.textContaining('still a draft'), findsOneWidget);
    expect(service.fulfilledRequestId, isNull);
  });

  testWidgets('the picker offers a live model and closes against the one chosen',
      (tester) async {
    final service = _FakeService(
      requests: [_record(id: 'r-1')],
      models: [
        {'id': 7, 'status': 'active', 'version': 2, 'authored_length_mm': 272, 'authored_size_eu': 42},
        {'id': 3, 'status': 'draft', 'version': 1, 'authored_length_mm': 270},
      ],
    );
    await _pump(tester, service: service);

    await tester.tap(find.widgetWithText(FilledButton, 'Close as done'));
    await tester.pumpAndSettle();

    expect(find.text('Which model fulfils this request?'), findsOneWidget);
    // Only the live one is offered, and it says what it is.
    expect(find.text('v2 · 272 mm · EU 42'), findsOneWidget);
    expect(find.text('v1 · 270 mm'), findsNothing);

    await tester.tap(find.text('v2 · 272 mm · EU 42'));
    await tester.pumpAndSettle();

    expect(service.fulfilledRequestId, 'r-1');
    expect(service.fulfilledModelId, 7);
  });

  testWidgets('an empty queue says so rather than showing nothing',
      (tester) async {
    await _pump(tester, requests: const []);
    expect(find.text('Nobody is waiting for a model'), findsOneWidget);
  });

  // ── The upload action (roadmap V2.11, P2) ────────────────────────────────

  testWidgets(
      'with its switch off the queue is exactly what it was before the phase',
      (tester) async {
    await _pump(tester, requests: [_record(id: 'r-1', externalLengthMm: 272)]);

    expect(find.text('Upload a 3D model'), findsNothing);
    // …and the three actions that were always here still are. "Off" has to mean
    // "today's screen", not "a screen with a hole in it".
    expect(find.widgetWithText(FilledButton, 'Close as done'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
    expect(find.text("I'll do it"), findsOneWidget);
  }, skip: uploadOn);

  testWidgets('with its switch on, the action opens the upload sheet with the '
      'seller\'s measurement already in it', (tester) async {
    await _pump(tester, requests: [
      _record(id: 'r-1', externalLengthMm: 272, measuredSizeEu: 42),
    ]);

    expect(find.text('Upload a 3D model'), findsOneWidget);

    await tester.tap(find.text('Upload a 3D model'));
    await tester.pumpAndSettle();

    expect(find.text('Upload the model'), findsOneWidget);
    // The number the mesh will be scaled to, carried over from the person who
    // measured it rather than retyped by the person modelling it.
    expect(find.textContaining('The seller measured 272 mm outside'),
        findsOneWidget);
  }, skip: !uploadOn);

  testWidgets(
      'with its switch on, the "no live model" dialog points at the action that '
      'can now fix that', (tester) async {
    final service = _FakeService(
      requests: [_record(id: 'r-1')],
      models: [
        {'id': 3, 'status': 'draft', 'version': 1, 'authored_length_mm': 270},
      ],
    );
    await _pump(tester, service: service);

    await tester.tap(find.widgetWithText(FilledButton, 'Close as done'));
    await tester.pumpAndSettle();

    // Before this phase the only way to fill the picker was a terminal, and the
    // dialog had to say so.
    expect(find.textContaining('Upload a 3D model'), findsOneWidget);
    expect(service.fulfilledRequestId, isNull);
  }, skip: !uploadOn);
}

Future<void> _pump(
  WidgetTester tester, {
  List<ShoeModelRequestRecord>? requests,
  ShoeModelRequestService? service,
}) async {
  final fake = _FakeService(requests: requests ?? const []);
  await tester.pumpWidget(
    MaterialApp(home: ManageShoeModelRequestsScreen(service: service ?? fake)),
  );
  await tester.pump();
  await tester.pump();
}

ShoeModelRequestRecord _record({
  required String id,
  String status = 'requested',
  double? externalLengthMm,
  double? externalWidthMm,
  double? heelHeightMm,
  double? measuredSizeEu,
  String? note,
  String? adminNote,
  String? assignedTo,
  int? modelId,
}) =>
    ShoeModelRequestRecord(
      id: id,
      productId: 'p-$id',
      storeId: 's-1',
      statusWire: status,
      status: ShoeModelRequestStatus.parse(status),
      externalLengthMm: externalLengthMm,
      externalWidthMm: externalWidthMm,
      heelHeightMm: heelHeightMm,
      measuredSizeEu: measuredSizeEu,
      note: note,
      adminNote: adminNote,
      assignedTo: assignedTo,
      modelId: modelId,
      productName: 'Chelsea Boot',
      storeName: 'Carcar Leather',
      createdAt: DateTime.utc(2026, 9, 28, 9),
    );

class _FakeService extends ShoeModelRequestService {
  _FakeService({required this.requests, this.models = const []})
      : super(_FakeData());

  List<ShoeModelRequestRecord> requests;
  List<Map<String, dynamic>> models;

  String? declinedRequestId;
  String? declineReason;
  String? fulfilledRequestId;
  int? fulfilledModelId;

  @override
  Future<List<ShoeModelRequestRecord>> queue() async => requests;

  @override
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId) async =>
      models;

  @override
  Future<ShoeModelRequestOutcome> decline({
    required String requestId,
    String? reason,
  }) async {
    declinedRequestId = requestId;
    declineReason = reason;
    return const ShoeModelRequestOutcome(success: true, message: 'Declined.');
  }

  @override
  Future<ShoeModelRequestOutcome> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  }) async {
    fulfilledRequestId = requestId;
    fulfilledModelId = modelId;
    return const ShoeModelRequestOutcome(success: true, message: 'Fulfilled.');
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
