import 'package:app/utils/in_app_update_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// The decision that keeps a doomed ~220 MB download off the screen.
///
/// The failure this guards is invisible when it happens: Android's installer
/// answers a signature mismatch with "App not installed." and reports nothing
/// back, so a build that offers the download anyway spends the user's data to
/// arrive at a dialog that explains nothing. These tests pin the decision and
/// the sentences the UI shows instead.
void main() {
  group('inAppUpdateBlocker', () {
    test('release build on a real device: nothing blocks the in-app update', () {
      expect(
        inAppUpdateBlocker(isReleaseBuild: true, isEmulator: false),
        isNull,
      );
    });

    test('a development build is blocked even on a real phone', () {
      // This is the case that shipped the bug: `flutter run` on a physical
      // device is a debug build, so the APK it installs is signed with the
      // machine-local debug keystore and no release APK can replace it.
      expect(
        inAppUpdateBlocker(isReleaseBuild: false, isEmulator: false),
        InAppUpdateBlocker.developmentBuild,
      );
    });

    test('a development build on an emulator reports the signing cause', () {
      // Both apply, and the development build is the one that actually decides
      // the outcome — the debug keystore is what Android refuses. Reporting the
      // emulator here would name a proxy instead of the cause.
      expect(
        inAppUpdateBlocker(isReleaseBuild: false, isEmulator: true),
        InAppUpdateBlocker.developmentBuild,
      );
    });

    test('release build on an emulator: the emulator is the only reason', () {
      // An emulator can hold a release build and be updated like any device —
      // withholding the download there is a product choice, not a signing one.
      expect(
        inAppUpdateBlocker(isReleaseBuild: true, isEmulator: true),
        InAppUpdateBlocker.emulator,
      );
    });

    test('the default build mode is the real one, kReleaseMode', () {
      // `flutter test` runs in debug mode, so this asserts the wiring rather
      // than the value: if the default were hard-coded to true, the app under
      // test would claim to be a release build and the guard would never fire.
      expect(
        inAppUpdateBlocker(isEmulator: false),
        InAppUpdateBlocker.developmentBuild,
      );
    });
  });

  group('inAppUpdateBlockerMessage', () {
    test('the development-build copy names the cause and the way out', () {
      final message =
          inAppUpdateBlockerMessage(InAppUpdateBlocker.developmentBuild);

      // Why it cannot work: the signing key, not the network or the file.
      expect(message, contains('debug key'));
      expect(message, contains('release key'));
      // That means "cannot be installed over this copy", said plainly.
      expect(message, contains('cannot install a release APK'));
      // And what a developer should do on that device instead of downloading.
      expect(message, contains('flutter run --release'));
    });

    test('no blocker copy offers the browser download as an escape hatch', () {
      // The whole point of the guard. The browser fetches the same bytes with
      // the same signature and fails identically, so a message that pointed
      // there would send someone through the same download twice.
      for (final blocker in InAppUpdateBlocker.values) {
        expect(
          inAppUpdateBlockerMessage(blocker).toLowerCase(),
          isNot(contains('browser')),
          reason: '$blocker must not suggest the browser download',
        );
      }
    });

    test('the emulator copy is the one that already shipped', () {
      // Pinned so the existing emulator behaviour cannot be reworded by a
      // change to this guard.
      expect(
        inAppUpdateBlockerMessage(InAppUpdateBlocker.emulator),
        'Emulator detected — update via flutter run. No download needed.',
      );
    });

    test('every blocker has its own non-empty sentence', () {
      final messages = InAppUpdateBlocker.values
          .map(inAppUpdateBlockerMessage)
          .toList();

      for (final message in messages) {
        expect(message.trim(), isNotEmpty);
      }
      expect(messages.toSet().length, messages.length);
    });
  });
}
