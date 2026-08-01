// ────────────────────────────────────────────────────────────────────────
// update_release_files.dart
//
// Helper used by `releases/publish.sh` to do all the file surgery for a new
// release in one cross-platform step (Dart ships with the Flutter SDK, so it
// always exists — no jq/python needed):
//
//   1. Bumps the `version:` line in pubspec.yaml to the new version
//      (incrementing the build number).
//   2. Rewrites releases/version.json with the new release.
//   3. Prepends the new release to releases/changelog.json (newest first).
//
// Usage (from the repo root):
//   dart run releases/update_release_files.dart \
//     --version 1.0.1 \
//     --apk-url https://github.com/kibs06/CUF/releases/download/v1.0.1/app-release-1.0.1.apk \
//     --released-at 2026-08-01 \
//     --notes "Fixed login crash|Improved startup time"
//
// `--notes` is optional (defaults to "Release v<version>"); use `|` to
// separate bullet points.
//
// `--skip-pubspec` skips the pubspec.yaml bump — used by the GitHub Actions
// release workflow (.github/workflows/release.yml), where the version comes
// from the git tag and pubspec.yaml was already committed by the developer.
// ────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:io';

const _indent = '  ';

void main(List<String> args) {
  String? version;
  String? apkUrl;
  String? releasedAt;
  String? notes;
  var skipPubspec = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--version':
        version = _value(args, ++i);
        break;
      case '--apk-url':
        apkUrl = _value(args, ++i);
        break;
      case '--released-at':
        releasedAt = _value(args, ++i);
        break;
      case '--notes':
        notes = _value(args, ++i);
        break;
      case '--skip-pubspec':
        skipPubspec = true;
        break;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }

  if (version == null || apkUrl == null || releasedAt == null) {
    stderr.writeln('Missing required args: --version, --apk-url, --released-at');
    exit(2);
  }

  final noteList = _splitNotes(notes, version);
  final today = releasedAt.isEmpty ? _today() : releasedAt;

  if (!skipPubspec) {
    _bumpPubspec(version);
  } else {
    stdout.writeln('  pubspec.yaml: skipped (--skip-pubspec)');
  }
  _writeManifest(version, apkUrl, today, noteList);
  _prependChangelog(version, apkUrl, today, noteList);

  stdout.writeln('✔ pubspec.yaml, releases/version.json, releases/changelog.json updated for v$version');
}

String _value(List<String> args, int index) {
  if (index >= args.length) {
    stderr.writeln('Missing value for argument at position $index');
    exit(2);
  }
  return args[index];
}

List<String> _splitNotes(String? notes, String version) {
  if (notes == null || notes.trim().isEmpty) {
    return ['Release v$version'];
  }
  return notes
      .split('|')
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList();
}

String _today() {
  // YYYY-MM-DD (same shape as the hosted released_at values).
  return DateTime.now().toIso8601String().substring(0, 10);
}

/// Updates the `version:` line in pubspec.yaml (e.g. `1.0.0+1` → `1.0.1+2`).
///
/// Only the version line is replaced — the rest of the file is left untouched
/// byte-for-byte so line endings (CRLF on Windows) are preserved and the git
/// diff stays tiny.
void _bumpPubspec(String newVersion) {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('pubspec.yaml not found — run from the repo root.');
    exit(1);
  }

  final original = file.readAsStringSync();
  final match = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(original);
  if (match == null) {
    stderr.writeln('No "version:" line found in pubspec.yaml');
    exit(1);
  }

  final current = match.group(1)!.trim();
  final buildPart = current.split('+');
  final currentBuild = buildPart.length > 1 ? int.tryParse(buildPart[1]) ?? 0 : 0;
  final newBuild = currentBuild + 1;
  final replacement = 'version: $newVersion+$newBuild';

  if (replacement != match.group(0)) {
    file.writeAsStringSync(
      original.replaceRange(match.start, match.end, replacement),
    );
  }
  stdout.writeln('  pubspec.yaml: version: $current → version: $newVersion+$newBuild');
}

void _writeManifest(String version, String apkUrl, String releasedAt, List<String> notes) {
  final file = File('releases/version.json');
  if (!file.existsSync()) {
    stderr.writeln('releases/version.json not found — run from the repo root.');
    exit(1);
  }
  file.writeAsStringSync(_prettyJson(_entry(version, apkUrl, releasedAt, notes)));
  stdout.writeln('  releases/version.json rewritten');
}

void _prependChangelog(String version, String apkUrl, String releasedAt, List<String> notes) {
  final file = File('releases/changelog.json');
  if (!file.existsSync()) {
    stderr.writeln('releases/changelog.json not found — run from the repo root.');
    exit(1);
  }

  List<dynamic> existing = [];
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is List) existing = decoded;
  } catch (_) {
    // Corrupt/empty changelog — start fresh.
  }

  // Drop any entry with the same version (idempotent re-runs), then prepend.
  existing = existing
      .where((e) =>
          (e is Map && e['latest_version']?.toString() != version))
      .toList();

  final updated = [_entry(version, apkUrl, releasedAt, notes), ...existing];
  file.writeAsStringSync(_prettyJson(updated));
  stdout.writeln('  releases/changelog.json updated (${updated.length} entries)');
}

Map<String, dynamic> _entry(String version, String apkUrl, String releasedAt, List<String> notes) {
  return {
    'latest_version': version,
    'apk_url': apkUrl,
    'released_at': releasedAt,
    'notes': notes,
  };
}

String _prettyJson(Object value) {
  return '${const JsonEncoder.withIndent(_indent).convert(value)}\n';
}
