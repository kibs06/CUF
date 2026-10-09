#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# publish.sh — one-command release for SoleVision
#
#   ./releases/publish.sh <new-version> ["note1|note2"]
#   e.g. ./releases/publish.sh 1.0.1 "Fixed login crash|Improved startup time"
#
# Automates the manual release checklist end-to-end:
#   1. Bumps `version:` in pubspec.yaml (build number +1) and rewrites
#      releases/version.json + releases/changelog.json via
#      releases/update_release_files.dart — BEFORE the build, because the APK
#      is stamped with whatever version pubspec.yaml holds at build time
#   2. Builds the release APK (`flutter build apk --release`, reusing
#      dart_defines.json if present)
#   3. Verifies the built APK is stamped with the version being published
#      (releases/verify_apk_version.sh) — a mismatch stops the release
#   4. Commits the release files and pushes to origin/main
#   5. Creates the GitHub Release `v<version>` and uploads the APK (renamed
#      `app-release-<version>.apk`) via the `gh` CLI; a release that already
#      exists for that tag gets its APK replaced instead
#
# The apk_url written to version.json matches the GitHub Release download URL,
# so the in-app "Download" button works end-to-end.
#
# Requires: Flutter on PATH and the GitHub CLI (`gh`) installed + authenticated
# (`gh auth login`). Install gh: `winget install GitHub.cli` (Windows) or
# `brew install gh` (macOS).
#
# Also requires the project's release signing key (`android/key.properties` +
# `android/app/cufmai-release.jks`, created once by
# `tool/setup_release_signing.sh`). The APK published here is the one the app's
# self-updater installs over the previous release, and Android only accepts an
# update whose signer matches — a debug-signed build gets "App not installed."
# on every device. The script refuses to publish without the key; see
# docs/RELEASE_SIGNING.md.
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

# ── 0b. Release signing key present? ────────────────────────────────────
# android/app/build.gradle falls back to signingConfigs.debug when
# android/key.properties is absent, which builds fine and publishes an APK no
# installed copy of the app can accept. Fail before the 5-minute build.
if [[ ! -f android/key.properties ]]; then
  echo "✖ android/key.properties is missing — this release would be debug-signed," >&2
  echo "  and Android refuses to install it over any previous release." >&2
  echo "  Run once: tool/setup_release_signing.sh --yes (see docs/RELEASE_SIGNING.md)." >&2
  exit 1
fi
STORE_FILE="$(sed -n 's/^storeFile=//p' android/key.properties | tr -d '\r' | head -1)"
if [[ -z "$STORE_FILE" || ! -f "android/app/$STORE_FILE" ]]; then
  echo "✖ android/key.properties names a keystore that is not there (${STORE_FILE:-<unset>})." >&2
  echo "  Expected: android/app/$STORE_FILE — restore it from your backup" >&2
  echo "  (the keystore cannot be regenerated without locking out every install)." >&2
  exit 1
fi

# ── 1. Compute release metadata ─────────────────────────────────────────
TAG="v$NEW_VERSION"
ASSET="app-release-$NEW_VERSION.apk"
RELEASED_AT="$(date +%Y-%m-%d)"

# Derive the repo slug from the git remote so this doesn't drift if the repo
# moves (falls back to kibs06/CUF if parsing fails). Strip a trailing `.git`
# FIRST — a greedy capture would otherwise swallow it into the slug and
# produce broken apk_urls like `kibs06/CUF.git/releases/...`.
REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo 'https://github.com/kibs06/CUF.git')"
REMOTE_URL="${REMOTE_URL%.git}"
REPO_SLUG="$(echo "$REMOTE_URL" | sed -E 's#.*github.com[:/]##')"
if [[ -z "$REPO_SLUG" || "$REPO_SLUG" == "$REMOTE_URL" ]]; then
  REPO_SLUG="kibs06/CUF"
fi
APK_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$ASSET"

# ── 2. Bump pubspec.yaml + rewrite releases/*.json — BEFORE the build ───
# The order is the whole point: `flutter build apk` stamps the APK with the
# version it reads out of pubspec.yaml (through android/local.properties), so
# bumping after the build names the APK with the PREVIOUS version. That is how
# v1.0.49's download came to install as v1.0.48.
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

# ── 3. Build the release APK ────────────────────────────────────────────
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

# ── 3b. The APK must wear the version being published ───────────────────
# Nothing above proves the build used the bumped pubspec.yaml. This does, and
# it stops before the commit, the push and the Release when it does not.
BUILD_NUMBER="$(sed -n 's/^version: *[^+]*+//p' pubspec.yaml | tr -d '\r' | head -1)"
if [[ -z "$BUILD_NUMBER" ]]; then
  echo "✖ Could not read the build number from pubspec.yaml (expected 'version: X.Y.Z+N')." >&2
  exit 1
fi
bash releases/verify_apk_version.sh "$APK" "$NEW_VERSION" "$BUILD_NUMBER"

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

# ── 5. Tag, create the GitHub Release, upload the APK ──────────────────────
echo "→ Tagging $TAG, creating the GitHub Release and uploading $ASSET …"
# Tag it here, annotated, with the notes. Pushing the tag also fires
# .github/workflows/release.yml, and that run reads the notes out of the tag
# message — while `gh release create` makes a lightweight tag with no message,
# so the workflow would rewrite version.json/changelog.json with the
# "Release vX.Y.Z" placeholder. That is exactly how v1.0.49 lost its notes.
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [[ -n "$NOTES" ]]; then
    git tag -a "$TAG" -m "${NOTES//|/$'\n'}"
  else
    git tag -a "$TAG" -m "Release $TAG"
  fi
  git push origin "$TAG"
fi
# Upload the APK under the versioned name FIRST (gh's `path#displayname`
# rename syntax is unreliable and silently uploads the asset under its
# original name — which breaks the apk_url in version.json with a 404).
# Copy to a temp file so the build output stays untouched, then upload.
cp "$APK" "$(dirname "$APK")/$ASSET"
ASSET_PATH="$(dirname "$APK")/$ASSET"
if gh release view "$TAG" >/dev/null 2>&1; then
  # Re-run friendly, and the repair path for a release whose APK was wrong:
  # replace the asset in place, leaving the tag and the notes untouched.
  echo "  Release $TAG already exists — replacing its APK."
  gh release upload "$TAG" "$ASSET_PATH" --clobber
elif [[ -n "$NOTES" ]]; then
  gh release create "$TAG" "$ASSET_PATH" --title "$TAG" --notes "${NOTES//|/$'\n'}"
else
  gh release create "$TAG" "$ASSET_PATH" --title "$TAG" --generate-notes
fi
rm -f "$ASSET_PATH"

echo "✔ Done — testers can update from the app."
echo "  Download URL: $APK_URL"
