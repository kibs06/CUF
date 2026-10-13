import 'package:flutter/foundation.dart';

/// Why an APK this app downloads could not be installed over the copy that is
/// running — or `null` when the in-app update path is viable.
///
/// Both reasons end at the same wall, and the wall is invisible from inside the
/// app: Android refuses to replace an installed package whose signing
/// certificate differs, and the system installer reports nothing back to the
/// caller. All the user gets is one line — **"App not installed."** — with a
/// DONE button and no reason on it. So the app either says why in advance or
/// says nothing and eats a ~220 MB download that was never going to install.
/// `docs/RELEASE_SIGNING.md` is the long version of the same subject.
enum InAppUpdateBlocker {
  /// This process is **not** a release build, so it was installed by
  /// `flutter run` (or from a `--debug` / `--profile` APK) and carries the
  /// machine-local debug keystore — never the release key every published APK
  /// is signed with. Android will not install a release APK over it, no matter
  /// how that APK is fetched: the in-app stream and the browser download are
  /// the same bytes with the same signature, and both end in the same dialog.
  ///
  /// Flutter makes this a certainty rather than a guess. The Gradle plugin
  /// creates the `profile` build type with `initWith(debugBuildType)`
  /// (`FlutterPlugin.kt`), so debug **and** profile inherit
  /// `signingConfigs.debug`; only a release build can carry the release key.
  developmentBuild,

  /// An emulator — a dev/test target rather than somebody's phone. This one is
  /// a product decision, not a signing one: an emulator can hold a release
  /// build and be updated like anything else. The download is withheld anyway
  /// because the usual way to run there is `flutter run`.
  emulator,
}

/// The reason a downloaded release APK cannot be installed over this build, or
/// `null` when the in-app update should be offered.
///
/// [isReleaseBuild] defaults to [kReleaseMode]. It is a parameter at all so
/// tests can reach the release branch — `flutter test` runs in debug mode, so a
/// process-wide constant would leave half this function unreachable from a
/// test.
InAppUpdateBlocker? inAppUpdateBlocker({
  bool isReleaseBuild = kReleaseMode,
  required bool isEmulator,
}) {
  // A development build is checked first because it is the *cause* rather than
  // a proxy for it: the debug keystore is what Android refuses, and that is
  // just as true on an emulator as on a phone. Reporting the emulator instead
  // would name the wrong reason for a failure the signing key already decided.
  if (!isReleaseBuild) return InAppUpdateBlocker.developmentBuild;
  if (isEmulator) return InAppUpdateBlocker.emulator;
  return null;
}

/// The sentence the update UI shows **in place of** its download actions.
///
/// It has to do three things, and the third is the one worth stating: name the
/// consequence (the download fails), name the cause (a `flutter run` build is
/// signed with the debug key), and give the way out. It must *not* offer the
/// browser fallback as an escape — that downloads the same signed APK and fails
/// identically, so a message that suggested it would send someone through the
/// same 220 MB twice.
String inAppUpdateBlockerMessage(InAppUpdateBlocker blocker) {
  switch (blocker) {
    case InAppUpdateBlocker.developmentBuild:
      return 'Development build — Android cannot install a release APK over '
          "this copy, so the ~220 MB download would fail. A flutter run build "
          "carries your machine's debug key, not the release key. On this "
          'device, use flutter run --release instead.';
    case InAppUpdateBlocker.emulator:
      return 'Emulator detected — update via flutter run. No download needed.';
  }
}
