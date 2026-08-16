import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/auth/seller_application_flow.dart';
import 'package:app/utils/dev_mode.dart';

/// Regression test for: "back brings the user back to the landing screen
/// instead of to the previous step."
///
/// DevMode is enabled so Continue skips step validation and the Supabase
/// duplicate-email check — the test walks steps without a backend. (The
/// flow also autosaves drafts, which degrades silently in tests.)
void main() {
  testWidgets('top-bar back button moves to the previous step, not out of '
      'the flow', (tester) async {
    DevMode.instance.toggle();
    addTearDown(DevMode.instance.toggle);

    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));

    // Step 1 — Account.
    expect(find.text('Create your seller account'), findsOneWidget);

    // Step 1 → Step 2. The Continue button sits below the fold in the
    // 600px test viewport, so scroll it into view first.
    final continueBtn = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(find.text('Verify your identity'), findsOneWidget);

    // Step 2 → Step 1. Before the fix this popped the whole flow back to
    // the landing screen.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Create your seller account'), findsOneWidget);
  });

  testWidgets('system back gesture also steps back instead of leaving the '
      'flow', (tester) async {
    DevMode.instance.toggle();
    addTearDown(DevMode.instance.toggle);

    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));

    expect(find.text('Create your seller account'), findsOneWidget);

    final continueBtn = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(find.text('Verify your identity'), findsOneWidget);

    // Android hardware back → previous step.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Create your seller account'), findsOneWidget);
  });
}
