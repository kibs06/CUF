import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/services/shoe_model_request_service.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:app/widgets/shoe_model_request_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    expect(find.text('Request a 3D fitting'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('no request: the plain ask, and it opens the form', (tester) async {
    await _pump(tester);
    expect(find.text('Request a 3D fitting'), findsOneWidget);

    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    expect(find.text('Ask for a 3D fitting'), findsOneWidget);
    // The length is the required field, and the sheet says which measurement it
    // wants twice: in the lead line, and again in the guide's own legend, which
    // is where the sentence moved when the drawing arrived (2026-09-29).
    expect(find.textContaining('Measure the pair'), findsOneWidget);
    expect(find.textContaining('Outside length — heel to toe'), findsOneWidget);
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
    // to remember it while retyping the numbers.
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

    await tester.tap(find.text('3D fitting ready'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This product has a model'), findsOneWidget);
  });

  testWidgets('the form refuses centimetres before it sends anything',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service: service);

    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      '27', // centimetres, and the most likely way a seller gets this wrong
    );
    await _tapSend(tester);

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

    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '272');
    await _tapSend(tester);

    expect(service.requestCalls, 1);
    expect(service.lastMeasurements!.externalLengthMm, 272);
    // The heel and the size came from the product's fit spec.
    expect(service.lastMeasurements!.heelHeightMm, 25);
    expect(service.lastMeasurements!.measuredSizeEu, 42);
  });

  testWidgets('the guide is drawn, and its legend names the arrows it draws',
      (tester) async {
    // ⚠️ The pairing is the test. The SVG carries no <text> — flutter_svg drops
    // it, so a numeral written there would look correct in a browser and be
    // missing on the device — which leaves colour as the only thing tying a
    // legend line to an arrow. A legend pointing at the wrong arrow is worse
    // than no legend, because it is confidently wrong.
    final svg = File('assets/images/measure_shoe.svg').readAsStringSync();

    for (final color in const [
      kMeasureGuideLengthColor,
      kMeasureGuideWidthColor,
      kMeasureGuideHeelColor,
      kMeasureGuideUpperColor,
    ]) {
      expect(
        svg.toUpperCase(),
        contains(_hex(color)),
        reason: 'the SVG draws no arrow in ${_hex(color)}',
      );
    }

    // Comments stripped first: this file's own header explains the no-<text>
    // rule, and the literal string in that explanation would otherwise be the
    // thing the assertion trips over.
    final drawing = svg.replaceAll(
      RegExp(r'<!--.*?-->', dotAll: true),
      '',
    );
    expect(
      drawing,
      isNot(contains('<text')),
      reason: 'flutter_svg drops <text>, so anything written there is invisible '
          'on the device — the labels belong in the legend',
    );

    // And it is actually on screen, above the boxes it explains.
    await _pump(tester);
    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.textContaining('Outside length — heel to toe'), findsOneWidget);
  });

  testWidgets('a chosen chip is readable: white ink on the brand fill',
      (tester) async {
    // ⚠️ This is the regression that made the unit toggle look broken. Material
    // 3 fills a selected chip from `colorScheme.secondaryContainer` and inks it
    // `onSecondaryContainer`; the app's hand-built ColorScheme sets neither, so
    // the fill and the label both came from Flutter's baseline while the sheet's
    // own `labelStyle` pinned the ink dark — a black pill with black text, i.e.
    // a seller who cannot see which unit they picked. Pin the pair that is
    // legible so a future chip cannot quietly go back to the theme's defaults.
    await _pump(tester);
    await tester.tap(find.text('Request a 3D fitting'));
    await tester.pumpAndSettle();

    final mm = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'mm'));
    expect(mm.selected, isTrue);
    expect(mm.selectedColor, AppConstants.primary);
    expect(mm.labelStyle?.color, Colors.white);
    // A checkmark next to a fill that already means "chosen" is width the chip
    // does not have, and it was the unreadable half of the screenshot.
    expect(mm.showCheckmark, isFalse);

    final cm = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'cm'));
    expect(cm.selected, isFalse);
    expect(cm.labelStyle?.color, isNot(Colors.white));

    // The same widget draws the sizes, so the picker is the same bug's second
    // home — opening it is what proves the fix reached both.
    await tester.tap(find.text('Tap to choose').last);
    await tester.pumpAndSettle();

    final forty = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '40'),
    );
    expect(forty.selectedColor, AppConstants.primary);

    await tester.tap(find.widgetWithText(ChoiceChip, '40'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '40'))
          .labelStyle
          ?.color,
      Colors.white,
    );
  });
}

/// Sends the form. The sheet is taller than the 800×600 test window since it
/// gained the measuring guide, so the tap has to bring the button into view
/// first — which is exactly what a thumb does on a real phone.
Future<void> _tapSend(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Send the request'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send the request'));
  await tester.pump();
}

/// `Color(0xFF8B5A2B)` → `#8B5A2B`, for comparing against the authored SVG.
String _hex(Color color) {
  int channel(double value) => (value * 255).round().clamp(0, 255);
  final rgb = [color.r, color.g, color.b]
      .map((v) => channel(v).toRadixString(16).padLeft(2, '0'))
      .join();
  return '#${rgb.toUpperCase()}';
}

Future<void> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool hasLiveModel = false,
  ShoeModelRequestRecord? request,
  ShoeModelRequestService? service,
  Map<String, dynamic>? product,
}) async {
  // ⚠️ A surface tall enough for the whole sheet, and that is a loading
  // condition rather than a preference: the form grew a measuring guide, a unit
  // toggle, two pickers and a fifth box, so at the default 800×600 the Send
  // button sits below the floor of the test surface and a tap on it lands
  // nowhere. `ensureVisible` alone does not save it — a widget outside the
  // *surface* cannot be hit even when its scrollable has scrolled.
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
