#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# setup_release_signing.sh — create the project's Android release identity
#
#   tool/setup_release_signing.sh --yes
#
# Why this exists: every release APK used to be signed with the *debug* key
# (`signingConfig signingConfigs.debug`). A debug keystore is generated per
# machine, and a GitHub runner starts without one — so every CI-built release
# was signed with a brand-new throwaway key, and Android refuses to replace an
# installed app whose signer differs. Testers saw "App not installed." when the
# in-app updater handed the APK to the package installer.
#
# This script creates the one key every future release is signed with:
#
#   1. android/app/cufmai-release.jks        (git-ignored, never overwrite)
#   2. android/key.properties                (git-ignored, credentials)
#   3. the four GitHub secret values, printed for you to paste
#
# ⚠ THE KEYSTORE IS THE APP'S IDENTITY.
#   Back it up (password manager / encrypted vault) together with its
#   passwords. If you lose it, no installed copy of CUFMAI can ever be updated
#   again — every device has to uninstall and reinstall by hand.
#   If it leaks, anyone can publish an "update" that Android will accept.
#
# Requires: keytool (any JDK — Android Studio and the Flutter SDK both ship
# one). Run from anywhere; paths resolve against the repo root.
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail

KEYSTORE_REL="android/app/cufmai-release.jks"
KEY_ALIAS="cufmai"
VALIDITY_DAYS=10000
DN="CN=CUFMAI, OU=Mobile, O=SoleVision, L=Manila, C=PH"

CONFIRMED=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) CONFIRMED=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

cd "$(dirname "$0")/.."

if [[ ! -f pubspec.yaml || ! -f android/app/build.gradle ]]; then
  echo "✖ Run this from the CUFMAI repo (pubspec.yaml + android/app/build.gradle not found)." >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "✖ keytool was not found on PATH." >&2
  echo "  Install a JDK (Android Studio bundles one), e.g. 'winget install Microsoft.OpenJDK.21'" >&2
  echo "  or make sure the JDK's bin folder is on PATH." >&2
  exit 1
fi

if [[ -f "$KEYSTORE_REL" ]]; then
  echo "✖ $KEYSTORE_REL already exists — refusing to overwrite it." >&2
  echo "" >&2
  echo "  That file is the app's release identity. Replacing it would make every" >&2
  echo "  installed copy of CUFMAI permanently un-updatable." >&2
  echo "" >&2
  echo "  • To (re)write android/key.properties from the existing keystore, use" >&2
  echo "    the same password you set when it was created:" >&2
  echo "      cd android && cat > key.properties <<'EOF'" >&2
  echo "      storePassword=<your keystore password>" >&2
  echo "      keyPassword=<your key password>" >&2
  echo "      keyAlias=$KEY_ALIAS" >&2
  echo "      storeFile=cufmai-release.jks" >&2
  echo "      EOF" >&2
  echo "  • To print the secrets CI needs, run:" >&2
  echo "      base64 -w0 $KEYSTORE_REL" >&2
  exit 1
fi

if [[ "$CONFIRMED" -ne 1 ]]; then
  cat >&2 <<EOF
This will create a new Android release signing identity:

  keystore : $KEYSTORE_REL
  alias    : $KEY_ALIAS
  valid    : $VALIDITY_DAYS days

It becomes the only key Android will accept as an update to CUFMAI, so:

  • back up the .jks file AND its passwords somewhere you will still have
    them in five years (password manager, encrypted vault, safe);
  • never commit it — .gitignore already excludes it;
  • treat it as a secret: whoever holds it can sign an APK Android will
    install over your app.

Re-run with --yes to continue.
EOF
  exit 1
fi

# ── Password: use your own, or generate a strong one ────────────────────
random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-28
  elif [[ -r /dev/urandom ]]; then
    head -c 64 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-28
  else
    printf '%s' "$(date +%s%N)-$$-cufmai" | sha256sum | cut -c1-28
  fi
}

STORE_PASSWORD="${RELEASE_STORE_PASSWORD:-$(random_secret)}"
KEY_PASSWORD="${RELEASE_KEY_PASSWORD:-$STORE_PASSWORD}"

if [[ ${#STORE_PASSWORD} -lt 6 ]]; then
  echo "✖ RELEASE_STORE_PASSWORD must be at least 6 characters (keytool's minimum)." >&2
  exit 1
fi

mkdir -p "$(dirname "$KEYSTORE_REL")"

echo "→ Generating $KEYSTORE_REL …"
keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_REL" \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -storetype PKCS12 \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "$DN" >/dev/null

# ── android/key.properties — what android/app/build.gradle reads ────────
# storeFile is resolved relative to the app module (android/app/).
cat > android/key.properties <<EOF
# Local Android release signing. GIT-IGNORED — never commit this file.
# Regenerate/rotate instructions: docs/RELEASE_SIGNING.md
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=cufmai-release.jks
EOF

FINGERPRINT="$(keytool -list -v -keystore "$KEYSTORE_REL" -alias "$KEY_ALIAS" \
  -storepass "$STORE_PASSWORD" \
  | grep -i 'SHA256:' | head -1 | sed 's/.*SHA256: *//' | tr -d '\r')"

BASE64_KEYSTORE="$(base64 -w0 "$KEYSTORE_REL" 2>/dev/null || base64 "$KEYSTORE_REL" | tr -d '\n')"

cat <<EOF

✔ Release signing is set up.

  keystore     : $KEYSTORE_REL
  key.properties: android/key.properties  (git-ignored)
  alias        : $KEY_ALIAS
  SHA-256      : $FINGERPRINT

━━━ DO THIS NOW ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. BACK UP the keystore and its passwords (they are printed below exactly
   once). Losing them means every installed copy of CUFMAI has to be
   uninstalled and reinstalled by hand, for every user, forever.

     keystore password : $STORE_PASSWORD
     key password      : $KEY_PASSWORD
     alias             : $KEY_ALIAS

2. Add these to the GitHub repo → Settings → Secrets and variables →
   Actions (Repository secrets), so the Release APK workflow signs with the
   SAME key instead of a fresh throwaway one:

     ANDROID_KEYSTORE_BASE64=$BASE64_KEYSTORE

     ANDROID_KEYSTORE_PASSWORD=$STORE_PASSWORD
     ANDROID_KEY_PASSWORD=$KEY_PASSWORD
     ANDROID_KEY_ALIAS=$KEY_ALIAS

3. Local releases (releases/publish.sh) now use this key automatically —
   nothing else to configure.

4. Each tester device must uninstall CUFMAI ONCE (the installed build is
   debug-signed, so Android will not replace it in place), then install the
   next release from the browser. After that the in-app updater works.
   See docs/RELEASE_SIGNING.md for the full sequence.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Confirm any release carries this key (SHA-256 must match the one above):
  apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk

The release workflow does exactly this comparison for every tag, so an
uninstallable update cannot be published. See docs/RELEASE_SIGNING.md.
EOF
