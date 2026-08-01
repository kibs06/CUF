#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# publish.sh — one-command release for SoleVision
#
#   ./releases/publish.sh <new-version> ["note1|note2"]
#   e.g. ./releases/publish.sh 1.0.1 "Fixed login crash|Improved startup time"
#
# Automates the manual release checklist end-to-end:
#   1. Bumps `version:` in pubspec.yaml (build number +1) via
#      releases/update_release_files.dart
#   2. Builds the release APK (`flutter build apk --release`, reusing
#      dart_defines.json if present)
#   3. Rewrites releases/version.json + prepends releases/changelog.json with
#      the new release (same Dart helper)
#   4. Commits those files and pushes to origin/main
#   5. Creates a GitHub Release `v<version>` and uploads the APK (renamed
#      `app-release-<version>.apk`) via the `gh` CLI
#
# The apk_url written to version.json matches the GitHub Release download URL,
# so the in-app "Download" button works end-to-end.
#
# Requires: Flutter on PATH and the GitHub CLI (`gh`) installed + authenticated
# (`gh auth login`). Install gh: `winget install GitHub.cli` (Windows) or
# `brew install gh` (macOS).
#
# Android testers still need "Install unknown apps" enabled for the browser
# that downloads the APK — see README.
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail

NEW_VERSION="${1:-}"
NOTES="${2:-}"

if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: ./releases/publish.sh <new-version> [\"note1|note2\"]" >&2
  exit 1
fi

# ── Validate X.Y.Z ──────────────────────────────────────────────────────
if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be X.Y.Z (e.g. 1.0.1)" >&2
  exit 1
fi

# ── cd to repo root (this script lives in <root>/releases/) ─────────────
cd "$(dirname "$0")/.."

# ── 0. gh CLI present? ──────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "✖ The GitHub CLI (\`gh\`) is not installed or not on PATH." >&2
  echo "  Install it and authenticate first:" >&2
  echo "    winget install GitHub.cli   # or: brew install gh" >&2
  echo "    gh auth login" >&2
  echo "  Without it the Release can't be created." >&2
  exit 1
fi

# ── 1. Build the release APK ────────────────────────────────────────────
echo "→ Building release APK for v$NEW_VERSION …"
BUILD_ARGS=(--release)
if [[ -f dart_defines.json ]]; then
  BUILD_ARGS+=(--dart-define-from-file=dart_defines.json)
fi
flutter build apk "${BUILD_ARGS[@]}"

APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK" ]]; then
  echo "✖ APK not found at $APK — build failed?" >&2
  exit 1
fi

# ── 2. Compute release metadata ─────────────────────────────────────────
TAG="v$NEW_VERSION"
ASSET="app-release-$NEW_VERSION.apk"
RELEASED_AT="$(date +%Y-%m-%d)"

# Derive the repo slug from the git remote so this doesn't drift if the repo
# moves (falls back to kibs06/CUF if parsing fails).
REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo 'https://github.com/kibs06/CUF.git')"
REPO_SLUG="$(echo "$REMOTE_URL" | sed -E 's#.*github.com[:/]([^/]+/[^/]+)(\.git)?$#\1#')"
if [[ -z "$REPO_SLUG" || "$REPO_SLUG" == "$REMOTE_URL" ]]; then
  REPO_SLUG="kibs06/CUF"
fi
APK_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$ASSET"

# ── 3. Update pubspec.yaml + releases/*.json ────────────────────────────
echo "→ Updating pubspec.yaml + releases/version.json + releases/changelog.json …"
NOTES_FLAG=()
if [[ -n "$NOTES" ]]; then
  NOTES_FLAG=(--notes "$NOTES")
fi
dart run releases/update_release_files.dart \
  --version "$NEW_VERSION" \
  --apk-url "$APK_URL" \
  --released-at "$RELEASED_AT" \
  "${NOTES_FLAG[@]}"

# ── 4. Commit + push ────────────────────────────────────────────────────
echo "→ Committing and pushing to origin/main …"
# Scope the commit to the release files only, so unrelated pre-staged work
# isn't swept into the release commit.
RELEASE_FILES="pubspec.yaml releases/version.json releases/changelog.json"
git add $RELEASE_FILES
# Compare staged vs HEAD (not working tree vs index) so pre-staged files
# from an interrupted run still get committed.
if ! git diff --cached --quiet -- $RELEASE_FILES; then
  git commit -m "release v$NEW_VERSION" -- $RELEASE_FILES
else
  echo "  (nothing changed to commit)"
fi
git push origin main

# ── 5. Create GitHub Release + upload APK ───────────────────────────────
echo "→ Creating GitHub Release $TAG and uploading $ASSET …"
if [[ -n "$NOTES" ]]; then
  gh release create "$TAG" "$APK#$ASSET" --title "$TAG" --notes "${NOTES//|/$'\n'}"
else
  gh release create "$TAG" "$APK#$ASSET" --title "$TAG" --generate-notes
fi

echo "✔ Done — testers can update from the app."
echo "  Download URL: $APK_URL"
