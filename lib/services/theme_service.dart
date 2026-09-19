import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for the app's appearance preference.
///
/// Stores the user's `ThemeMode` as a short string under one key, locally
/// (SharedPreferences) — same shape as `SaleTagService`: a singleton with
/// best-effort reads/writes, because a storage failure must never stop the app
/// from painting. An unreadable or unknown value falls back to
/// [ThemeMode.system], which is also the default for a fresh install.
///
/// The preference is per-device, not per-account: appearance is a property of
/// the phone, like brightness or text size, so signing out does not reset it.
class ThemeService {
  ThemeService._();

  static final ThemeService instance = ThemeService._();

  static const String _key = 'app_theme_mode';

  /// The stored mode, or [ThemeMode.system] when unset/corrupt.
  Future<ThemeMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(_key));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// Persist the mode. Best-effort: a failed write leaves the in-memory
  /// choice in effect for this session.
  Future<void> save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encode(mode));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Stored string → mode. Unknown values are treated as [ThemeMode.system]
  /// rather than throwing, so a future enum addition or a hand-edited pref
  /// cannot brick the app's appearance.
  static ThemeMode decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Mode → stored string. Stable values: never rename these without a
  /// migration, or every existing install silently reverts to system.
  static String encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
