import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/update_info.dart';
import '../services/update_checker.dart';

/// Holds the app-wide update state: whether a newer version exists and whether
/// the user has already viewed it (so the Settings badge dot can clear).
///
/// Follows the app's existing Provider/ChangeNotifier pattern — created once
/// in `main.dart` and consumed by the Settings screen.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider({UpdateCheckerService? service})
      : _service = service ?? UpdateCheckerService.instance;

  final UpdateCheckerService _service;

  static const String _viewedVersionKey = 'viewed_update_version';

  UpdateInfo? _latestUpdate;
  String? _installedVersion;
  bool _isChecking = false;
  bool _checkFailed = false;
  bool _updateOverlayShown = false;

  /// The newest available release, or null if up to date / unknown.
  UpdateInfo? get latestUpdate => _latestUpdate;

  /// The currently installed version (e.g. "1.3.2"), or null while loading.
  String? get installedVersion => _installedVersion;

  /// True while a network check is in flight.
  bool get isChecking => _isChecking;

  /// True if the last check could not reach the update host (network error,
  /// malformed manifest, etc.) — distinct from "up to date".
  bool get checkFailed => _checkFailed;

  /// True if a newer release exists and the overlay hasn't been shown yet
  /// this session. Shell screens watch this to trigger the premium overlay.
  bool get shouldShowUpdateOverlay =>
      _latestUpdate != null && !_updateOverlayShown;

  /// Marks the update overlay as shown so it doesn't reappear until the
  /// next app restart.
  void markUpdateOverlayShown() {
    _updateOverlayShown = true;
    notifyListeners();
  }

  /// True if a newer release exists that the user hasn't viewed yet.
  bool get hasUnviewedUpdate =>
      _latestUpdate != null && _latestUpdate!.version != _viewedVersion;

  /// The last version the user explicitly viewed, or null.
  String? _viewedVersion;

  /// Kicks off a silent, non-blocking check. Safe to call from app launch —
  /// never throws and never shows UI. On failure sets [checkFailed] so the UI
  /// can show a distinct "couldn't check" state instead of a false "up to
  /// date".
  Future<void> checkForUpdate() async {
    if (_isChecking) return;
    _isChecking = true;
    notifyListeners();

    try {
      _installedVersion ??= await _service.installedVersion();
      // Pass the already-read version so fetchLatestUpdate doesn't read it
      // again via PackageInfo.
      _latestUpdate = await _service.fetchLatestUpdate(
        knownInstalledVersion: _installedVersion,
      );
      _checkFailed = false;

      // Load the previously-viewed version so the badge dot logic works.
      final prefs = await SharedPreferences.getInstance();
      _viewedVersion = prefs.getString(_viewedVersionKey);
    } catch (e) {
      _latestUpdate = null;
      _checkFailed = true;
      debugPrint('[UpdateProvider] checkForUpdate failed silently: $e');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// Marks the latest release as viewed (clears the Settings badge dot).
  Future<void> markUpdateViewed() async {
    final latest = _latestUpdate;
    if (latest == null) return;
    _viewedVersion = latest.version;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewedVersionKey, latest.version);
    } catch (e) {
      debugPrint('[UpdateProvider] markUpdateViewed failed: $e');
    }
  }
}
