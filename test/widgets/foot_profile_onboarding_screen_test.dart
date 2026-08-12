import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/auth/foot_profile_onboarding_screen.dart';

/// Harness that injects all three persistence/navigation hooks so the screen
/// can be exercised without a Supabase-backed AuthProvider.
Future<void> _pump(WidgetTester tester, {
  VoidCallback? onLaunchScan,
  Future<bool> Function({
    double? sizeEu,
    String? widthLabel,
    required String source,
  })? onPersist,
  VoidCallback? onFinished,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FootProfileOnboardingScreen(
        onLaunchScan: onLaunchScan,
        onPersist: onPersist,
        onFinished: onFinished,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders all three paths with the AR option visually primary',
      (tester) async {
    await _pump(tester);

    expect(find.text('Scan your feet with AR'), findsOneWidget);
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.text('Enter your size manually'), findsOneWidget);
    expect(find.textContaining('Skip for now'), findsOneWidget);

    // The AR card (accent-filled) must be the FIRST child in the column,
    // above the manual card — structural dominance, not just styling.
    final arY = tester.getTopLeft(find.text('Scan your feet with AR')).dy;
    final manualY = tester.getTopLeft(find.text('Enter your size manually')).dy;
    expect(arY, lessThan(manualY));
  });

  testWidgets('tapping the AR card launches the scan flow (and does not finish)',
      (tester) async {
    var launched = false;
    var finished = false;
    await _pump(
      tester,
      onLaunchScan: () => launched = true,
      onFinished: () => finished = true,
    );

    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();

    expect(launched, isTrue);
    expect(finished, isFalse, reason: 'scan launch must not complete onboarding');
  });

  testWidgets('manual entry persists size + width and finishes', (tester) async {
    double? persistedSize;
    String? persistedWidth;
    String? persistedSource;
    var finished = false;

    await _pump(
      tester,
      onPersist: ({double? sizeEu, String? widthLabel, required String source}) async {
        persistedSize = sizeEu;
        persistedWidth = widthLabel;
        persistedSource = source;
        return true;
      },
      onFinished: () => finished = true,
    );

    // Pick an EU size. '36' sits near the front of the lazy horizontal
    // ListView (later sizes like '40.5' are off-window and untappable);
    // the size row itself sits below the 600px fold, so scroll first.
    await tester.ensureVisible(find.text('36'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('36'));
    await tester.pumpAndSettle();
    // Pick a width (defaults to Regular — choose Wide to prove the binding).
    await tester.ensureVisible(find.text('Wide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wide'));
    await tester.pumpAndSettle();

    // Save sits below the 600px fold — scroll it into view first.
    await tester.ensureVisible(find.text('Save my size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save my size'));
    await tester.pumpAndSettle();

    expect(persistedSource, 'manual');
    expect(persistedSize, 36.0);
    expect(persistedWidth, 'Wide');
    expect(finished, isTrue);
  });

  testWidgets('manual entry without a size shows an inline error', (tester) async {
    var persistCalled = false;
    await _pump(
      tester,
      onPersist: ({double? sizeEu, String? widthLabel, required String source}) async {
        persistCalled = true;
        return true;
      },
    );

    await tester.ensureVisible(find.text('Save my size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save my size'));
    await tester.pumpAndSettle();

    expect(find.text('Please pick your shoe size first.'), findsOneWidget);
    expect(persistCalled, isFalse);
  });

  testWidgets('manual entry persists skipped source and finishes', (tester) async {
    String? persistedSource;
    var finished = false;

    await _pump(
      tester,
      onPersist: ({double? sizeEu, String? widthLabel, required String source}) async {
        persistedSource = source;
        return true;
      },
      onFinished: () => finished = true,
    );

    await tester.ensureVisible(find.textContaining('Skip for now'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Skip for now'));
    await tester.pumpAndSettle();

    expect(persistedSource, 'skipped');
    expect(finished, isTrue);
  });
}
