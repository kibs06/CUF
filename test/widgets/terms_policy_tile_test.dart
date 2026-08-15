import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/shared/terms_privacy_screen.dart';
import 'package:app/widgets/auth/terms_policy_tile.dart';

/// The policy link is the underlined RichText span. Tapping the RICH TEXT's
/// box center lands on that span for a single-line sentence (the link covers
/// the middle of "I agree to the Terms & Privacy Policy of CUFMAI.").
final Finder _linkText =
    find.textContaining('Terms & Privacy Policy', findRichText: true);

/// Drags the policy scroll view to its very bottom so the agree button
/// unlocks (the gating we're testing).
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
  Widget harness({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TermsPolicyTile(value: value, onChanged: onChanged),
        ),
      ),
    );
  }

  testWidgets('renders the consent sentence and a checkbox', (tester) async {
    await tester.pumpWidget(harness(value: false, onChanged: (_) {}));

    expect(_linkText, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TermsPolicyTile),
        matching: find.byType(AnimatedContainer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the checkbox when unchecked opens the read-and-agree '
      'policy instead of toggling', (tester) async {
    var changed = false;
    await tester.pumpWidget(
      harness(value: false, onChanged: (_) => changed = true),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(TermsPolicyTile),
        matching: find.byType(AnimatedContainer),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TermsPrivacyScreen), findsOneWidget,
        reason: 'the policy must open for reading');
    expect(changed, isFalse,
        reason: 'opening the policy alone must not check the box');
  });

  testWidgets('tapping the policy link opens the screen without toggling',
      (tester) async {
    var changed = false;
    await tester.pumpWidget(
      harness(value: false, onChanged: (_) => changed = true),
    );

    await tester.tap(_linkText);
    await tester.pumpAndSettle();

    expect(find.byType(TermsPrivacyScreen), findsOneWidget);
    expect(changed, isFalse,
        reason: 'reading the policy must not toggle the checkbox');
  });

  testWidgets('reading to the bottom and agreeing checks the box',
      (tester) async {
    var value = false;
    await tester.pumpWidget(
      harness(value: value, onChanged: (v) => value = v),
    );

    await tester.tap(_linkText);
    await tester.pumpAndSettle();

    // Locked until the user scrolls to the end.
    expect(
      find.text('Scroll to the end of the policy to agree'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'I have read and I agree'),
      findsNothing,
    );

    await _scrollPolicyToBottom(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'I have read and I agree'),
    );
    await tester.pumpAndSettle();

    expect(value, isTrue, reason: 'agreeing should check the box');
    expect(find.byType(TermsPrivacyScreen), findsNothing,
        reason: 'the policy should pop back to the form');
  });

  testWidgets('tapping when already checked unchecks directly',
      (tester) async {
    var value = true;
    await tester.pumpWidget(
      harness(value: value, onChanged: (v) => value = v),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(TermsPolicyTile),
        matching: find.byType(AnimatedContainer),
      ),
    );
    await tester.pumpAndSettle();

    expect(value, isFalse, reason: 'unchecking needs no re-read');
    expect(find.byType(TermsPrivacyScreen), findsNothing);
  });

  testWidgets('exposes the consent as a checkbox with checked state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(harness(value: true, onChanged: (_) {}));

    final match = find.bySemanticsLabel(
      // The tile defaults to the customer policy, so the consent label
      // carries the role prefix.
      'I agree to the Customer Terms & Privacy Policy of CUFMAI.',
    );
    expect(match, findsAtLeastNWidgets(1));
    final node = tester.getSemantics(match.first);
    expect(node.flagsCollection.isChecked, CheckedState.isTrue);
    handle.dispose();
  });
}
