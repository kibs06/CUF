#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# verify_apk_version.sh — the APK must wear the version being published
#
#   ./releases/verify_apk_version.sh <apk> <versionName> <versionCode>
#
# Why this exists (the bug it was written for): `publish.sh` used to build the
# APK *before* bumping pubspec.yaml, and `flutter build` writes
# `android/local.properties` — the file `android/app/build.gradle` reads
# versionName/versionCode from — out of pubspec.yaml at build time. So every
# local release shipped an APK carrying the PREVIOUS version's name: the
# v1.0.49 download installed as v1.0.48, and the in-app updater, which
# compares its own version to releases/version.json, kept offering the update
# forever. Android reads that same stamp, so nothing in the pipeline noticed.
#
# Reads the stamp from the APK's own manifest with `aapt`/`aapt2` when the
# Android SDK has one (it always does on a machine that can build an APK).
# Without it, falls back to `android/local.properties` — the values the build
# actually read — and says so. Fails when neither is available rather than
# passing unverified.
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail

APK="${1:-}"
EXPECTED_NAME="${2:-}"
EXPECTED_CODE="${3:-}"

if [[ -z "$APK" || -z "$EXPECTED_NAME" || -z "$EXPECTED_CODE" ]]; then
  echo "Usage: ./releases/verify_apk_version.sh <apk> <versionName> <versionCode>" >&2
  exit 2
fi

if [[ ! -f "$APK" ]]; then
  echo "✖ APK not found at $APK — nothing to verify." >&2
  exit 1
fi

# ── Where is the Android SDK? ───────────────────────────────────────────
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$SDK" && -n "${LOCALAPPDATA:-}" ]]; then
  SDK="$LOCALAPPDATA/Android/Sdk"          # Git Bash on Windows
fi
if [[ -z "$SDK" ]]; then
  SDK="$HOME/Android/Sdk"
fi

# Newest build-tools wins, same rule the release workflow uses for apksigner.
AAPT=""
if [[ -d "$SDK/build-tools" ]]; then
  AAPT="$(find "$SDK/build-tools" -maxdepth 2 -type f \
    \( -name aapt -o -name aapt.exe -o -name aapt2 -o -name aapt2.exe \) \
    2>/dev/null | sort -V | tail -1)"
fi

SOURCE=""
if [[ -n "$AAPT" ]]; then
  BADGING="$("$AAPT" dump badging "$APK" 2>/dev/null | head -1)"
  ACTUAL_NAME="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$BADGING")"
  ACTUAL_CODE="$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$BADGING")"
  SOURCE="$AAPT dump badging"
else
  # No aapt in the SDK — the values Gradle read at build time are the next
  # best evidence, and they are exactly what the bug left stale.
  LOCAL_PROPS="android/local.properties"
  if [[ -f "$LOCAL_PROPS" ]]; then
    ACTUAL_NAME="$(sed -n 's/^flutter\.versionName=//p' "$LOCAL_PROPS" | tr -d '\r' | head -1)"
    ACTUAL_CODE="$(sed -n 's/^flutter\.versionCode=//p' "$LOCAL_PROPS" | tr -d '\r' | head -1)"
    SOURCE="$LOCAL_PROPS (no aapt found under $SDK/build-tools)"
    echo "  note: verifying against $SOURCE" >&2
  fi
fi

if [[ -z "${SOURCE:-}" ]]; then
  echo "✖ Cannot read the APK's version — no aapt/aapt2 under $SDK/build-tools and no android/local.properties." >&2
  echo "  Refusing to publish an unverified APK." >&2
  exit 1
fi

# ── The verdict ─────────────────────────────────────────────────────────
if [[ "$ACTUAL_NAME" != "$EXPECTED_NAME" || "$ACTUAL_CODE" != "$EXPECTED_CODE" ]]; then
  echo "✖ The APK is stamped ${ACTUAL_NAME:-?} (versionCode ${ACTUAL_CODE:-?}) but this release is" >&2
  echo "  v$EXPECTED_NAME (versionCode $EXPECTED_CODE) — published as-is it installs as the previous" >&2
  echo "  version and the in-app updater never stops offering the update." >&2
  echo "  Read from: $SOURCE" >&2
  echo "  Bump pubspec.yaml BEFORE \`flutter build apk\` (publish.sh does this for you)." >&2
  exit 1
fi

echo "✔ APK is stamped v$ACTUAL_NAME (versionCode $ACTUAL_CODE) — read from $SOURCE"
