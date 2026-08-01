import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../models/update_info.dart';

/// Lightweight, self-hosted update checker for the development/testing phase.
///
/// This is **not** Play Store's in-app update API — it is a DIY solution so a
/// test build can be updated without plugging the phone into a laptop.
///
/// # Hosting
/// Two JSON files live in the `releases/` folder of the public GitHub repo
/// `kibs06/CUF` (served over HTTPS via raw.githubusercontent — no server
/// needed). Any static HTTPS host (Supabase Storage, GitHub Pages, Netlify,
/// etc.) works; change the two URLs in [AppConstants] to point at it:
///
/// 1. `version.json` — the current release manifest:
///    ```json
///    {
///      "latest_version": "1.4.0",
///      "apk_url": "https://example.com/releases/app-release-1.4.0.apk",
///      "released_at": "2026-08-01",
///      "notes": ["Fixed login crash on Android 14", "Improved startup time"]
///    }
///    ```
/// 2. `changelog.json` — an array of past releases, newest first, in the
///    exact same shape:
///    ```json
///    [
///      { "latest_version": "1.4.0", "apk_url": "...", "released_at": "2026-08-01", "notes": [...] },
///      { "latest_version": "1.3.2", "apk_url": "...", "released_at": "2026-07-20", "notes": [...] }
///    ]
///    ```
///
/// Both URLs live in [AppConstants.updateManifestUrl] and
/// [AppConstants.updateChangelogUrl] — change them in one place.
///
/// # Release checklist (manual)
/// 1. Bump `version:` in `pubspec.yaml` (e.g. `1.4.0+8`).
/// 2. Build the release APK: `flutter build apk --release`.
/// 3. Upload the APK (e.g. to Supabase Storage or a host) and copy its URL.
/// 4. Update `version.json` with the new version + APK URL + notes.
/// 5. Prepend the same entry to `changelog.json`.
///
/// # Android "install unknown apps"
/// Sideloading requires the downloader app (browser, file manager, etc.) to
/// have "Install unknown apps" enabled in Android Settings → Apps → Special
/// access. This is a per-app user setting, not something the app can request.
class UpdateCheckerService {
  UpdateCheckerService({
    http.Client? client,
    Future<String?> Function()? installedVersionReader,
  })  : _client = client ?? http.Client(),
        _installedVersionReader = installedVersionReader ?? _defaultInstalledVersionReader;

  /// Shared app-wide instance.
  static final UpdateCheckerService instance = UpdateCheckerService();

  final http.Client _client;
  final Future<String?> Function() _installedVersionReader;

  static const Duration _timeout = Duration(seconds: 10);

  // ── Changelog cache ──────────────────────────────────────────────
  // The changelog is cached locally so the What's New screen loads instantly
  // (no network wait) and still works offline. Only refetches when stale.
  static const String changelogCacheKey = 'update_changelog_cache';
  static const String changelogCacheTimeKey = 'update_changelog_cache_time';

  /// How long a cached changelog is considered fresh before refetching.
  /// Exposed for tests.
  @visibleForTesting
  static const Duration changelogCacheTtl = Duration(hours: 24);

  /// Default reader: the installed app's version (e.g. "1.3.2") via
  /// `package_info_plus`. Returns null if it can't be determined.
  static Future<String?> _defaultInstalledVersionReader() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      debugPrint('[UpdateChecker] Failed to read installed version: $e');
      return null;
    }
  }

  /// Reads the installed app's version. Never throws — returns null on error.
  Future<String?> installedVersion() => _installedVersionReader();

  /// Fetches the hosted `version.json` and returns the latest release.
  ///
  /// Returns `null` if the fetch fails, the JSON is malformed, or the host
  /// doesn't report a version — it never throws, so callers can treat this as
  /// "no update information available" and keep the UI unblocked. Used by the
  /// silent startup check in [UpdateProvider.checkForUpdate].
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      return await fetchLatestUpdate();
    } catch (e) {
      debugPrint('[UpdateChecker] checkForUpdate failed silently: $e');
      return null;
    }
  }

  /// Like [checkForUpdate] but **throws** on network/parse failures so callers
  /// (e.g. the What's New screen) can show a distinct error state + retry.
  /// Returns `null` only when the installed version is already current.
  ///
  /// Pass [knownInstalledVersion] if the caller already read it (avoids a
  /// second `PackageInfo.fromPlatform()` call).
  Future<UpdateInfo?> fetchLatestUpdate({String? knownInstalledVersion}) async {
    final installed = knownInstalledVersion ?? await installedVersion();
    if (installed == null) return null;

    final response =
        await _client.get(Uri.parse(AppConstants.updateManifestUrl)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Manifest fetch failed: HTTP ${response.statusCode}');
    }

    // Decode from raw bytes as UTF-8: raw.githubusercontent.com serves JSON as
    // text/plain without a charset, and response.body would fall back to
    // latin-1 and garble non-ASCII characters in release notes.
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manifest is not a JSON object');
    }

    final latest = UpdateInfo.fromJson(decoded);
    final latestVersion = latest.version.trim();
    if (latestVersion.isEmpty) return null;

    // Semantic comparison: "1.10.0" is correctly newer than "1.9.0".
    if (compareVersions(latestVersion, installed.trim()) <= 0) return null;
    return latest;
  }

  /// Fetches the changelog (an array of past releases, newest first), served
  /// through a local SharedPreferences cache so the What's New screen loads
  /// instantly and works offline.
  ///
  /// Behavior:
  /// - Fresh cache (written within [changelogCacheTtl]) → returned immediately,
  ///   no network call.
  /// - Stale or missing cache → fetches `changelog.json`, then rewrites the
  ///   cache. Pass [forceRefresh] to skip the freshness check (e.g. pull-to-
  ///   refresh).
  /// - Network failure with an existing cache → falls back to the stale cache
  ///   so the screen still works offline.
  /// - Network failure with **no** cache → throws so the UI can show a
  ///   friendly error + retry instead of an ambiguous blank screen.
  Future<List<UpdateInfo>> fetchChangelog({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _readChangelogCache();
      if (cached != null) return cached;
    }

    try {
      final changelog = await _fetchChangelogFromNetwork();
      await _writeChangelogCache(changelog);
      return changelog;
    } catch (e) {
      // Offline fallback: prefer stale cache over an error if we have one.
      final cached = await _readChangelogCache(ignoreFreshness: true);
      if (cached != null) {
        debugPrint('[UpdateChecker] Changelog fetch failed — using cached copy: $e');
        return cached;
      }
      rethrow;
    }
  }

  Future<List<UpdateInfo>> _fetchChangelogFromNetwork() async {
    final response = await _client
        .get(Uri.parse(AppConstants.updateChangelogUrl))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Changelog fetch failed: HTTP ${response.statusCode}');
    }

    // Decode as UTF-8 — same reasoning as fetchLatestUpdate: release notes may
    // contain non-ASCII characters and the host may omit a charset header.
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException('Changelog is not a JSON array');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(UpdateInfo.fromJson)
        .toList();
  }

  /// Returns the cached changelog if it's still fresh, otherwise null.
  /// Set [ignoreFreshness] to return stale cache too (offline fallback).
  Future<List<UpdateInfo>?> _readChangelogCache({bool ignoreFreshness = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(changelogCacheKey);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      if (!ignoreFreshness) {
        final cachedAt = DateTime.tryParse(
          prefs.getString(changelogCacheTimeKey) ?? '',
        );
        if (cachedAt == null) return null;
        if (DateTime.now().difference(cachedAt) > changelogCacheTtl) {
          return null;
        }
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(UpdateInfo.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[UpdateChecker] Failed to read changelog cache: $e');
      return null;
    }
  }

  Future<void> _writeChangelogCache(List<UpdateInfo> changelog) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        changelogCacheKey,
        jsonEncode(changelog.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        changelogCacheTimeKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('[UpdateChecker] Failed to write changelog cache: $e');
    }
  }
}
