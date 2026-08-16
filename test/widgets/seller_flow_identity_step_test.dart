import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/auth/seller_application_flow.dart';
import 'package:app/utils/dev_mode.dart';

/// Regression coverage for the government-ID type picker added to Step 2
/// (Identity). The flow must now require the applicant to pick WHICH valid
/// PH government ID they're uploading before Continue passes.
///
/// DevMode is used ONLY to skip Step 1 (whose Continue hits the Supabase
/// duplicate-email check) — it is turned back off before the identity-step
/// assertions, so the real validation runs.
void main() {
  // Reach Step 2 via the dev skip, then turn dev mode off so the identity
  // step's real Continue validation applies.
  Future<void> pumpToIdentityStep(WidgetTester tester) async {
    DevMode.instance.toggle(); // ON
    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));
    expect(find.text('Create your seller account'), findsOneWidget);

    final continueBtn = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();

    DevMode.instance.toggle(); // OFF — real validation from here on
    await tester.pumpAndSettle();
    expect(find.text('Verify your identity'), findsOneWidget);
  }

  tearDown(() {
    if (DevMode.instance.isEnabled) DevMode.instance.toggle();
  });

  testWidgets('identity step blocks Continue until an ID type is chosen',
      (tester) async {
    await pumpToIdentityStep(tester);

    // The ID photo upload is gated behind the type choice: the tile must
    // NOT exist yet, and the lock hint explains why.
    expect(
      find.text('Government ID photo'),
      findsNothing,
      reason: 'photo upload must stay hidden until an ID type is chosen',
    );
    expect(
      find.text('The ID photo step appears once you choose your ID type '
          'above.'),
      findsOneWidget,
    );

    // No ID type selected yet → Continue must refuse and stay on Step 2.
    final continueBtn = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('Please select your government ID type.'),
      findsOneWidget,
      reason: 'ID type is required before the identity step can advance',
    );
    expect(find.text('Verify your identity'), findsOneWidget);

    // Pick a type from the bottom-sheet list. The step-2 body keeps step
    // 1's scroll offset, so bring the picker card into view first.
    await tester.ensureVisible(find.text('Government ID type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Government ID type'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose your government ID type'),
      findsOneWidget,
      reason: 'tapping the picker card must open the ID-type sheet',
    );
    await tester.tap(find.text('PhilSys National ID (PhilID / ePhilID)'));
    await tester.pumpAndSettle();

    // The card now shows the chosen type, the lock hint is gone, and the
    // photo upload tile has appeared.
    expect(find.text('PhilSys National ID (PhilID / ePhilID)'), findsOneWidget);
    expect(
      find.text('The ID photo step appears once you choose your ID type '
          'above.'),
      findsNothing,
    );
    expect(
      find.text('Government ID photo'),
      findsOneWidget,
      reason: 'choosing the ID type must unlock the photo upload',
    );
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('Please add your government ID photo.'),
      findsOneWidget,
      reason: 'type selected but no photo yet — must still be blocked',
    );
    expect(find.text('Verify your identity'), findsOneWidget);
  });

  testWidgets('ID-type sheet lists the valid Philippine government IDs',
      (tester) async {
    await pumpToIdentityStep(tester);

    await tester.ensureVisible(find.text('Government ID type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Government ID type'));
    await tester.pumpAndSettle();

    // Spot-check the researched list — the picker must enumerate the
    // accepted PH government IDs, not free text. The sheet's list is lazy,
    // so scroll it to reveal the lower half before asserting on it.
    final firstHalf = [
      'PhilSys National ID (PhilID / ePhilID)',
      'Philippine Passport',
      "Driver's License (LTO)",
      'UMID / SSS Digitized ID',
      'GSIS eCard',
      'PRC ID',
    ];
    final secondHalf = [
      'Postal ID (PhilPost)',
      "Voter's ID (COMELEC)",
      'Senior Citizen ID (OSCA)',
      'PWD ID',
      'TIN ID (BIR)',
      'NBI Clearance',
    ];

    // skipOffstage: false — the lazy ListView keeps off-screen rows built
    // (cache extent) but they're marked offstage until scrolled into view.
    for (final label in firstHalf) {
      expect(
        find.text(label, skipOffstage: false),
        findsOneWidget,
        reason: 'missing: $label',
      );
    }
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    for (final label in secondHalf) {
      expect(
        find.text(label, skipOffstage: false),
        findsOneWidget,
        reason: 'missing: $label',
      );
    }
  });
}
