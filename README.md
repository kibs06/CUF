# app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## In-app update checker

During development/testing the app checks a **self-hosted** JSON file for a
newer build and lets testers download the new APK without plugging the phone
into a laptop. This is **not** Play Store's in-app update API (that comes
later once published).

### Where the files live

The URLs are configured in **one place**: `lib/constants/app_constants.dart`
(`updateManifestUrl` and `updateChangelogUrl`). They currently point at the
public GitHub repo `kibs06/CUF` via raw.githubusercontent:

- `https://raw.githubusercontent.com/kibs06/CUF/main/releases/version.json`
- `https://raw.githubusercontent.com/kibs06/CUF/main/releases/changelog.json`

So publishing a build is simply: **commit the updated files to the `releases/`
folder in that repo's `main` branch.** (Any static HTTPS host — Supabase
Storage, GitHub Pages, Netlify — works too; just update the two constants.)

### Expected JSON shape

**`version.json`** (the current release manifest):

```json
{
  "latest_version": "1.4.0",
  "apk_url": "https://example.com/releases/app-release-1.4.0.apk",
  "released_at": "2026-08-01",
  "notes": ["Fixed login crash on Android 14", "Improved startup time"]
}
```

**`changelog.json`** (historical patch notes, newest first — same shape per
entry, an array of release objects):

```json
[
  { "latest_version": "1.4.0", "apk_url": "...", "released_at": "2026-08-01", "notes": [...] },
  { "latest_version": "1.3.2", "apk_url": "...", "released_at": "2026-07-20", "notes": [...] }
]
```

Versions are compared semantically, so `1.10.0` is correctly detected as newer
than `1.9.0`. If the fetch fails (no internet, host down, malformed JSON) the
app stays silent — no crash, no blocking, no popup.

The changelog is cached locally (SharedPreferences, 24h TTL) so the What's New
screen loads instantly and still shows the last known release notes offline. A
pull-to-refresh on that screen forces a fresh fetch.

### Auto-release via GitHub Actions (recommended)

The repo ships `.github/workflows/release.yml`, which does the whole release
whenever you push a `vX.Y.Z` tag:

1. Builds the release APK (debug-signed, same as local builds).
2. Rewrites `releases/version.json` + prepends `releases/changelog.json` on
   `main` (version taken from the tag, notes read from the annotated tag
   message — one bullet per line).
3. Creates a GitHub Release `vX.Y.Z` with the APK attached as
   `app-release-<version>.apk`, and commits the JSON updates to `main` so the
   in-app update checker resolves immediately.

```bash
# 1. Bump version: in pubspec.yaml, commit, push to main
# 2. Create an annotated tag with the release notes (one bullet per line)
git tag -a v1.0.1 -m "Fixed login crash
Improved startup time"
# 3. Push it — the workflow takes it from here
git push origin v1.0.1
```

No secrets are needed: release builds use the debug signing config and the
app reads its Supabase/MapTiler values from `app_constants.dart`, not
dart-defines.

### One-command release script (local alternative)

The `releases/` folder ships a small local release toolchain you can run from
your machine instead of pushing a tag:

- **`releases/publish.sh`** (or **`releases/publish.bat`** on Windows) — one
  command that does everything below: bumps `pubspec.yaml`, builds the APK,
  rewrites `version.json`, prepends `changelog.json`, commits + pushes, then
  creates a GitHub Release with the APK attached.
- **`releases/update_release_files.dart`** — the file-surgery helper the script
  calls (pure Dart, no extra deps).

```bash
# Example: ship v1.0.1
./releases/publish.sh 1.0.1 "Fixed login crash|Improved startup time"
# Windows:
releases\publish.bat 1.0.1 "Fixed login crash|Improved startup time"
```

Requirements: Flutter on PATH and the GitHub CLI (`gh`) installed +
authenticated (`gh auth login`). Install gh with `winget install GitHub.cli`
(Windows) or `brew install gh` (macOS).

### Manual release checklist

If you'd rather publish by hand:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.4.0+8`).
2. Build the release APK: `flutter build apk --release`.
3. Create a GitHub Release tagged `v1.4.0` and attach the APK **renamed** to
   `app-release-1.4.0.apk` (the in-app Download button uses that exact URL).
4. Update `releases/version.json` with the new version + APK URL + notes.
5. Prepend the same entry to `releases/changelog.json`.
6. Commit and push `pubspec.yaml` + both JSONs to `main`.

### Android "install unknown apps"

Sideloading requires the downloader app (browser, file manager) to have
**Install unknown apps** enabled: Android Settings → Apps → Special app access
→ Install unknown apps. This is a per-app user setting — the app can't request
it itself.
