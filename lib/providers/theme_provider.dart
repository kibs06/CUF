import 'package:flutter/material.dart';

import '../services/theme_service.dart';

/// Owns the user's appearance choice — System / Light / Dark.
///
/// It stores the *choice*, never the resolved brightness: the resolution
/// (which also consults the platform) happens once in `_ThemedApp`, which
/// publishes it to [AppBrightness] for the token layer. Keeping resolution in
/// one place is what stops the palette and `ThemeMode` from disagreeing.
///
/// Writes are optimistic (notify first, persist in the background) so the
/// whole app repaints on the tap, exactly like `SaleTagProvider`'s reveals.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({ThemeMode initialMode = ThemeMode.system}) : _mode = initialMode;

  final ThemeService _service = ThemeService.instance;

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Whether the user has pinned a mode, i.e. the OS no longer decides.
  bool get isPinned => _mode != ThemeMode.system;

  /// Apply and persist a choice. A no-op when unchanged, so re-tapping the
  /// current option cannot cause a needless repaint.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _service.save(mode);
  }

  /// Human label for a mode, used by the Settings row.
  static String label(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }
}
