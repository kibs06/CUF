import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/providers/v2/scan_session_controller.dart';
import 'package:app/screens/customer/foot_size_v2/foot_scan_results_screen_v2.dart';

ScanResultsPayloadV2 _payload({
  String? euSize = '42',
  List<ConfidenceFactorV2> factors = const [],
}) {
  return ScanResultsPayloadV2(
    leftLengthMm: 250.0,
    leftWidthMm: 95.0,
    rightLengthMm: 248.0,
    rightWidthMm: 94.0,
    // Bare feet → compensated == raw.
    leftRawLengthMm: 250.0,
    rightRawLengthMm: 248.0,
    euSize: euSize,
    usSize: euSize != null ? '9' : null,
    ukSize: euSize != null ? '9' : null,
    sizingFootSide: 'left',
    widthCategory: 'standard',
    footCondition: 'barefoot',
    shoeCategory: 'men',
    confidenceLevel: 'high',
    confidenceScore: 0.87,
    leftSampleCount: 16,
    rightSampleCount: 15,
    sizeRecommendationReason:
        'Sized on your longer left foot with a comfort allowance.',
    confidenceFactors: factors,
  );
}

Future<void> _pump(WidgetTester tester, ScanResultsPayloadV2 payload) async {
  await tester.pumpWidget(
    MaterialApp(home: FootScanResultsScreenV2(payload: payload)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders hero size, count-up confidence % and factor rows', (
    tester,
  ) async {
    await _pump(
      tester,
      _payload(
        factors: [
          const ConfidenceFactorV2(
            positive: true,
            title: 'Plenty of clean readings',
            detail: '31 samples kept across both feet.',
          ),
          const ConfidenceFactorV2(
            positive: false,
            title: 'Width was estimated, not measured',
            detail: 'The side view never caught your foot’s edges.',
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('hero-eu')), findsOneWidget);
    expect(find.byKey(const Key('confidence-pct')), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('Plenty of clean readings'), findsOneWidget);
    expect(find.text('Width was estimated, not measured'), findsOneWidget);
    // SIZING badge on the larger (left) foot card only.
    expect(find.text('SIZING'), findsOneWidget);
  });

  testWidgets('+ steps the EU size up half a size and re-derives US/UK', (
    tester,
  ) async {
    await _pump(tester, _payload());

    Text heroBefore = tester.widget<Text>(find.byKey(const Key('hero-eu')));
    expect(heroBefore.data, '42');

    await tester.tap(find.byKey(const Key('adjust-plus')));
    await tester.pumpAndSettle();

    heroBefore = tester.widget<Text>(find.byKey(const Key('hero-eu')));
    expect(heroBefore.data, '42.5');
    final stepper = tester.widget<Text>(find.byKey(const Key('adjust-eu')));
    expect(stepper.data, '42.5');
    // EU 42.5 men → US round(9.5) = 10, UK round(9) = 9.
    expect(find.text('US 10'), findsOneWidget);
    expect(find.text('UK 9'), findsOneWidget);
    // Adjustment badge + save label follow the adjusted size.
    expect(find.text('Adjusted by you from EU 42'), findsOneWidget);
    expect(find.text('Save EU 42.5 to my profile'), findsOneWidget);

    // Reset restores the recommendation everywhere.
    await tester.tap(find.byKey(const Key('adjust-reset')));
    await tester.pumpAndSettle();

    heroBefore = tester.widget<Text>(find.byKey(const Key('hero-eu')));
    expect(heroBefore.data, '42');
    expect(find.text('US 9'), findsOneWidget);
    expect(find.text('Save EU 42 to my profile'), findsOneWidget);
  });

  testWidgets('− clamps at two sizes below the recommendation', (
    tester,
  ) async {
    await _pump(tester, _payload());

    // Five taps: 42 → 40 is allowed, the 6th would go past −2.0.
    for (int i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('adjust-minus')));
      await tester.pumpAndSettle();
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('hero-eu'))).data,
      '40',
    );

    // Button is disabled at the clamp → further taps change nothing.
    await tester.tap(find.byKey(const Key('adjust-minus')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('hero-eu'))).data,
      '40',
    );
  });

  testWidgets('no adjustment card when no EU recommendation exists', (
    tester,
  ) async {
    await _pump(tester, _payload(euSize: null));

    expect(find.byKey(const Key('adjust-plus')), findsNothing);
    expect(find.byKey(const Key('confidence-pct')), findsOneWidget);
  });
}
