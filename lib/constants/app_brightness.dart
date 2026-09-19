import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The brightness the palette resolves against — the single piece of global
/// state this app's colour system needs.
///
/// **Why this exists.** The app paints from `AppConstants` tokens rather than
/// `Theme.of(context)`, so a widget's colours cannot come from its own
/// position in the tree. Instead one value is published here by the app root
/// (`_ThemedApp` in `lib/main.dart`) whenever the resolved brightness changes,
/// and the token getters read it.
///
/// **Discipline.** Exactly one writer, and it is the app root. Widgets read
/// `AppConstants.*` as they always have and must never publish — if a second
/// writer appears, colours and `ThemeMode` can silently disagree. The
/// invariant is pinned by `test/utils/dark_mode_test.dart`.
///
/// Defaults to light, so every existing test and any code path that runs
/// before the root publishes a value keeps painting the light palette.
class AppBrightness {
  AppBrightness._();

  static Brightness _current = Brightness.light;

  /// Whether the app root has published a value yet. False during the very
  /// first frame (and in tests), which is what tells [publish] that no
  /// repaint is needed — nothing has been painted with the old palette.
  static bool _resolved = false;

  static Brightness get current => _current;

  static bool get isDark => _current == Brightness.dark;

  static bool get isResolved => _resolved;

  /// Publishes the brightness the theme resolved to, and reports whether
  /// anything already painted needs to be repainted.
  ///
  /// Returns `true` only when the palette actually changed *after* a value was
  /// already in effect. On the first frame this returns `false`: the tree is
  /// being built now, so it will read the new palette anyway — and rebuilding
  /// is not just unnecessary there, it would cost dark-mode users a light
  /// first frame at launch.
  static bool publish(Brightness brightness) {
    final changed = _resolved && brightness != _current;
    _current = brightness;
    _resolved = true;
    return changed;
  }

  /// Restores the default. `test/flutter_test_config.dart` calls this before
  /// every test so no test can leak a dark palette into the next one.
  static void reset() {
    _current = Brightness.light;
    _resolved = false;
  }

  /// Test-only direct setter, for asserting how a widget resolves tokens
  /// without mounting the app root.
  @visibleForTesting
  static void set(Brightness brightness) {
    _current = brightness;
    _resolved = true;
  }
}
