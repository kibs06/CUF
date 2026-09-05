import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detects whether the app is running on an emulator — used to suppress the
/// intrusive update prompt (download overlay / "UPDATE AVAILABLE" download
/// CTA) on emulators while keeping it on real devices.
///
/// Why: emulators are dev/test environments where the user typically runs the
/// app straight from `flutter run` and does not want to sideload APKs. Real
/// devices keep the full update prompt.
///
/// Fail-safe: any error reading device info resolves to `false` (treated as a
/// physical device), so the standard prompt is never silently lost.
class EmulatorDetector {
  EmulatorDetector._();

  static bool? _cached;

  /// True when running on an emulator. Android is the only platform where the
  /// APK sideload flow applies; other platforms report `false`.
  ///
  /// The result is cached after the first call (device type cannot change
  /// within a process lifetime).
  static Future<bool> isEmulator() async {
    if (!Platform.isAndroid) return false;
    if (_cached != null) return _cached!;
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      _cached = !android.isPhysicalDevice;
    } catch (e) {
      debugPrint('[EmulatorDetector] device info read failed: $e');
      _cached = false;
    }
    return _cached!;
  }

  /// Test-only: resets the cache so a test can exercise both branches.
  @visibleForTesting
  static void resetForTesting() => _cached = null;
}
