import 'package:app/screens/auth/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The redesigned onboarding sells each slide with an eyebrow, proof bullets
/// and a segmented progress readout — this pins the content contract so a
/// later edit cannot silently drop a slide's story or the counter.
void main() {
  testWidgets('each slide shows its eyebrow, headline and bullets',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(onFinished: () {}),
      ),
    );
    await tester.pumpAndSettle();

    // Slide 1.
    expect(find.text('HANDCRAFTED IN CEBU'), findsOneWidget);
    expect(find.text('Welcome to CUFMAI'), findsOneWidget);
    expect(
        find.text('Hand-stitched by Cebu craftsmen'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    // Skip jumps to the last slide, whose CTA finishes the flow.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('TRUE-TO-SIZE FIT'), findsOneWidget);
    expect(find.text('See It On Your Feet'), findsOneWidget);
    expect(
        find.text('One scan remembers your size'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('swiping reaches the middle slide', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(onFinished: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PageView),
      const Offset(-400, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text('THE MARKETPLACE'), findsOneWidget);
    expect(find.text('Explore Artisan Stores'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
