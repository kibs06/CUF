import 'dart:math' as math;

/// A single release entry shared by the hosted `version.json` manifest and the
/// `changelog.json` history file.
///
/// JSON shape (see README → "In-app update checker" for details):
/// ```json
/// {
///   "latest_version": "1.4.0",
///   "apk_url": "https://example.com/releases/app-release-1.4.0.apk",
///   "released_at": "2026-08-01",
///   "notes": ["Fixed login crash", "Added dark mode toggle"]
/// }
/// ```
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    this.releasedAt,
    this.notes = const [],
  });

  /// The release version, e.g. `"1.4.0"`.
  final String version;

  /// Direct download URL for the Android APK.
  final String apkUrl;

  /// Optional release date, e.g. `2026-08-01`.
  final DateTime? releasedAt;

  /// Bullet-style release notes, newest first.
  final List<String> notes;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['notes'];
    return UpdateInfo(
      version: (json['latest_version'] ?? json['version'] ?? '').toString(),
      apkUrl: (json['apk_url'] ?? '').toString(),
      releasedAt: DateTime.tryParse(json['released_at']?.toString() ?? ''),
      notes: rawNotes is List
          ? rawNotes.map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// Serializes back to the hosted JSON shape (used for the local changelog
  /// cache). Round-trips through [UpdateInfo.fromJson] losslessly.
  Map<String, dynamic> toJson() {
    return {
      'latest_version': version,
      'apk_url': apkUrl,
      'released_at': releasedAt?.toIso8601String(),
      'notes': notes,
    };
  }
}

/// Compares two dot-separated version strings such as `"1.9.0"` vs
/// `"1.10.0"` using proper numeric (semantic) comparison — not string order.
///
/// Returns a negative number if [a] < [b], `0` if equal, and a positive
/// number if [a] > [b]. Build metadata (`"1.4.0+3"`) and pre-release labels
/// (`"1.4.0-beta"`) are stripped before comparing.
int compareVersions(String a, String b) {
  final aParts = _numericParts(a);
  final bParts = _numericParts(b);
  final length = math.max(aParts.length, bParts.length);
  for (var i = 0; i < length; i++) {
    final aNum = i < aParts.length ? aParts[i] : 0;
    final bNum = i < bParts.length ? bParts[i] : 0;
    if (aNum != bNum) return aNum - bNum;
  }
  return 0;
}

/// Splits a version string into numeric dot-separated segments.
/// `"1.4.0+3"` → `[1, 4, 0]`, `"1.4.0-beta"` → `[1, 4, 0]`.
List<int> _numericParts(String version) {
  final core = version.split('+').first.split('-').first.trim();
  return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
}
