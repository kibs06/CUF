import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/shared/terms_privacy_screen.dart';

void main() {
  testWidgets('renders the CUFMAI Terms & Privacy sections',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TermsPrivacyScreen()));

    // Part labels.
    expect(find.textContaining('TERMS OF SERVICE'), findsOneWidget);
    expect(find.textContaining('PRIVACY POLICY'), findsOneWidget);

    // Part I section titles (customer policy — the default document).
    expect(find.text('Your Account & Eligibility'), findsOneWidget);
    expect(find.text('Orders & Payment'), findsOneWidget);
    expect(find.text('Returns & Refunds'), findsOneWidget);
    expect(find.text('Prohibited Conduct'), findsOneWidget);
    expect(find.text('Account Suspension & Termination'), findsOneWidget);
    expect(find.text('Disclaimer & Limitation of Liability'), findsOneWidget);

    // Part II section titles.
    expect(find.text('Information We Collect'), findsOneWidget);
    expect(find.text('Your Foot Measurements'), findsOneWidget);
    expect(find.text('Storage & Security'), findsOneWidget);
    expect(find.text('Retention & Deletion'), findsOneWidget);
    expect(find.text('Children’s Privacy'), findsOneWidget);
    expect(find.text('Contact Us'), findsOneWidget);

    // Key app-specific copy.
    expect(find.textContaining('support@cufmai.ph'), findsWidgets);
    expect(find.textContaining('Carcar'), findsWidgets);
    expect(find.textContaining('GCash'), findsWidgets);
    expect(find.text('Last updated: August 2026'), findsOneWidget);

    // Default (read-only) mode: no agree bar.
    expect(
      find.text('Scroll to the end of the policy to agree'),
      findsNothing,
    );
  });

  testWidgets('read-and-agree mode gates the agree button behind '
      'scroll-to-bottom', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TermsPrivacyScreen(readAndAgree: true)),
    );

    // Locked: hint shown, no agree button yet.
    expect(
      find.text('Scroll to the end of the policy to agree'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'I have read and I agree'),
      findsNothing,
    );

    // Scroll to the very bottom of the policy.
    final scrollable = find.byType(SingleChildScrollView);
    for (var i = 0; i < 20; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump();
      if (find.text('I have read and I agree').evaluate().isNotEmpty) break;
    }

    expect(
      find.text('Scroll to the end of the policy to agree'),
      findsNothing,
      reason: 'the hint should be replaced once the end is reached',
    );
    final agree = find.widgetWithText(FilledButton, 'I have read and I agree');
    expect(agree, findsOneWidget);
    expect(tester.widget<FilledButton>(agree).onPressed, isNotNull,
        reason: 'agree must unlock only after reaching the bottom');
  });
}
