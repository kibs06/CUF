import 'package:app/models/update_info.dart';
import 'package:app/widgets/update_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The update overlay is the app's most intrusive update surface — a modal at
/// launch with a single loud button. In a development build that button used to
/// open a ~220 MB APK download that Android was never going to install: the
/// running copy is signed with the machine-local debug key, so no release APK
/// can replace it, and the installer reports the refusal as a bare "App not
/// installed." with no reason attached.
///
/// `flutter test` compiles in debug mode, so this file *is* a development build
/// and the assertions below are the shipped behaviour of `flutter run`.
void main() {
  const update = UpdateInfo(
    version: '1.0.54',
    apkUrl: 'https://example.com/app-release-1.0.54.apk',
    notes: ['A newer build is out'],
  );

  Widget harness() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => UpdateOverlay.show(context, update: update),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

  Future<void> showOverlay(WidgetTester tester) async {
    await tester.tap(find.text('Trigger'));
    await tester.pump();
    // The header's glow repeats forever, so the entrance is pumped explicitly —
    // `pumpAndSettle` would never settle on a looping animation.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a development build is told why, not handed a doomed download',
      (tester) async {
    await tester.pumpWidget(harness());
    await showOverlay(tester);

    // The download is gone entirely — no button, and no browser link either,
    // since that fetches the same signed APK and fails the same way.
    expect(find.text('Update Now'), findsNothing);

    // In its place, the reason: that a release APK cannot be installed over
    // this copy, why (the debug key), and what to do instead.
    expect(find.textContaining('cannot install a release APK'), findsOneWidget);
    expect(find.textContaining('debug key'), findsOneWidget);
    expect(find.textContaining('flutter run --release'), findsOneWidget);
  });

  testWidgets('the news still arrives — only the impossible action is withheld',
      (tester) async {
    await tester.pumpWidget(harness());
    await showOverlay(tester);

    // A guard that hid the release itself would be a different bug: the user
    // still has to learn that a newer version exists.
    expect(find.text('New Update Available'), findsOneWidget);
    expect(find.text('Version 1.0.54'), findsOneWidget);
    expect(find.textContaining('A newer build is out'), findsOneWidget);

    // And the dialog is still dismissible.
    expect(find.text('Maybe Later'), findsOneWidget);
    // The card is taller than the test viewport, so the dismiss button has to
    // be scrolled into view before a tap can land on it.
    await tester.ensureVisible(find.text('Maybe Later'));
    await tester.pump();
    await tester.tap(find.text('Maybe Later'));
    await tester.pump(); // begin the pop
    await tester.pump(const Duration(milliseconds: 500)); // 400ms reverse
    await tester.pump(); // and the rebuild that removes the route
    expect(find.text('New Update Available'), findsNothing);
  });
}
