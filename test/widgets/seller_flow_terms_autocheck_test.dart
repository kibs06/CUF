import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/auth/seller_application_flow.dart';
import 'package:app/screens/shared/terms_privacy_screen.dart';
import 'package:app/widgets/auth/terms_policy_tile.dart';

/// The consent tile on Step 1. On the seller flow the tile sits below the
/// password fields, so the test scrolls the form's scroll view until the
/// tile is visible before interacting with it.
Finder _tile() => find.byType(TermsPolicyTile);

Future<void> _scrollToTile(WidgetTester tester) async {
  final tile = _tile();
  for (var i = 0; i < 10 && tile.evaluate().isNotEmpty; i++) {
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    if (tester.getRect(tile).bottom <=
        tester.getSize(find.byType(MaterialApp)).height) {
      return;
    }
    await tester.drag(find.byType(SingleChildScrollView).first,
        const Offset(0, -200));
    await tester.pumpAndSettle();
  }
}

/// Drags the policy scroll view to its very bottom so the agree button
/// unlocks (the gating under test).
Future<void> _scrollPolicyToBottom(WidgetTester tester) async {
  final scrollable = find.byType(SingleChildScrollView);
  for (var i = 0; i < 20; i++) {
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump();
    final agree = find.widgetWithText(FilledButton, 'I have read and I agree');
    if (agree.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(agree).onPressed != null) {
      return;
    }
  }
  fail('agree button never enabled after scrolling to the bottom');
}

void main() {
  testWidgets('seller Step 1: agreeing inside the read-and-agree flow checks '
      'the terms checkbox visually', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));

    // Step 1 ("Create your seller account") is showing the consent tile,
    // initially unchecked. The tile sits below the password fields, so
    // scroll it into the viewport first.
    expect(find.text('Create your seller account'), findsOneWidget);
    await _scrollToTile(tester);
    expect(
      find.descendant(of: _tile(), matching: find.byIcon(Icons.check_rounded)),
      findsNothing,
      reason: 'box must start unchecked',
    );

    // Open the policy through the tile's link.
    await tester.tap(
      find.textContaining('Terms & Privacy Policy', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TermsPrivacyScreen), findsOneWidget);

    // Read to the bottom and agree.
    await _scrollPolicyToBottom(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'I have read and I agree'),
    );
    await tester.pumpAndSettle();

    // Back on Step 1: the checkbox must now show its checkmark WITHOUT any
    // extra tap — this is the regression the fix targets.
    expect(find.byType(TermsPrivacyScreen), findsNothing);
    await _scrollToTile(tester);
    expect(
      find.descendant(of: _tile(), matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
      reason: 'agreeing must immediately check the box on Step 1',
    );

    // And the controller state is true, so Continue will pass validation.
    final tileWidget = tester.widget<TermsPolicyTile>(_tile());
    expect(tileWidget.value, isTrue);
  });
}
