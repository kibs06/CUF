import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/auth/seller_application_flow.dart';
import 'package:app/utils/dev_mode.dart';

/// Regression coverage for the Community step (Step 3) segmented toggle.
///
/// Bug: `isCufmaiMember` was a plain controller field, so tapping "Not a
/// member" changed the internal state but never notified listeners — the
/// segmented button never repainted (stayed stuck on "CUFMAI member") and
/// the barangay-proof section never appeared. The fix is a notifying
/// setter; this test pins the visible behavior.
void main() {
  tearDown(() {
    if (DevMode.instance.isEnabled) DevMode.instance.toggle();
  });

  // Dev-skip through Steps 1 and 2 (their Continues hit Supabase), then
  // turn dev mode off so Step 3 is fully interactive.
  Future<void> pumpToCommunityStep(WidgetTester tester) async {
    DevMode.instance.toggle(); // ON
    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));
    expect(find.text('Create your seller account'), findsOneWidget);

    for (var i = 0; i < 2; i++) {
      final continueBtn = find.widgetWithText(FilledButton, 'Continue');
      await tester.ensureVisible(continueBtn);
      await tester.pumpAndSettle();
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
    }

    DevMode.instance.toggle(); // OFF
    await tester.pumpAndSettle();
    expect(find.text('Prove your community link'), findsOneWidget);
  }

  testWidgets('tapping "Not a member" repaints the toggle and reveals the '
      'barangay proof section', (tester) async {
    await pumpToCommunityStep(tester);

    // Default state: member — member-ID field visible, no barangay tile.
    expect(find.text('CUFMAI Member ID (optional)'), findsOneWidget);
    expect(find.text('Barangay certificate / proof'), findsNothing);

    // Tap "Not a member" → the whole step must repaint: member-ID field
    // disappears, barangay proof tile appears, toggle shows the new state.
    await tester.ensureVisible(find.text('Not a member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a member'));
    await tester.pumpAndSettle();

    expect(find.text('CUFMAI Member ID (optional)'), findsNothing);
    expect(find.text('Barangay certificate / proof'), findsOneWidget);

    // And switching back to member works symmetrically.
    await tester.ensureVisible(find.text('CUFMAI member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUFMAI member'));
    await tester.pumpAndSettle();

    expect(find.text('CUFMAI Member ID (optional)'), findsOneWidget);
    expect(find.text('Barangay certificate / proof'), findsNothing);
  });

  testWidgets('Continue without a store location is blocked',
      (tester) async {
    await pumpToCommunityStep(tester);

    // Birthday/gender live on Step 1 (application v2); the first required
    // gate on Step 3 is the map-picked store location.
    final continueBtn = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('Please set your store location on the map to continue.'),
      findsOneWidget,
    );
    expect(find.text('Prove your community link'), findsOneWidget);
  });

  testWidgets('Step 1 collects birthday and gender before the flow can '
      'advance', (tester) async {
    // Dev mode OFF — real Step 1 validation runs (empty form fails
    // validation before the Continue handler ever touches Supabase).
    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));
    expect(find.text('Create your seller account'), findsOneWidget);

    // The birthday + gender fields render on Step 1.
    expect(find.text('Birthday *'), findsOneWidget);
    expect(find.text('Gender (optional)'), findsOneWidget);

    // Without a birthday, Continue refuses (inline form error).
    final continueBtn = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(find.text('Please select your birthday'), findsOneWidget);
    expect(find.text('Create your seller account'), findsOneWidget);
  });
}
