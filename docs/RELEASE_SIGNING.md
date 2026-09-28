# Release signing — one stable key, or no updates at all

**Dated:** 2026-09-28
**Symptom it explains:** tapping **Install update** in *What's New* opens Android's
package installer, which then answers **"CUFMAI — App not installed."** with a
single DONE button and no reason.

> **How to read this.** *Proven* = a command ran and said so. *Measured* = read
> from the running system. *Believed* = reviewed, not executed.

---

## 1. What the user sees

Tap **Download v1.0.32** → the progress bar fills → the button becomes
**Install update** → tap it → the system installer appears → **App not installed.**

Nothing in the app reports it, because Android's installer never tells the caller
what happened: the app hands over a content URI, the installer runs in its own
process, and the outcome is a dialog the app cannot observe. That is why the
failure looks like a dead end — the app's part of the job (download + handoff)
actually succeeded.

## 2. The cause (proven from this repo)

`android/app/build.gradle` signed release builds with the **debug** config:

```gradle
buildTypes {
    release {
        signingConfig signingConfigs.debug   // ← the bug
```

A debug keystore is not a project asset — it belongs to **one machine**. Android's
own documentation: *"The first time you run or debug your project in Android
Studio, the IDE automatically creates the debug keystore and certificate in
`$HOME/.android/debug.keystore`."* A GitHub runner is a fresh VM with no
`~/.android/debug.keystore`, so AGP generates a **new** one while building — with
new key material, every run.

Measured: every release APK in this repo was built by the `Release APK` workflow
(GitHub-hosted `ubuntu-latest`), from `v1.0.20` through `v1.0.32` — 13 releases,
13 ephemeral runners, 13 different signing keys.

Android will not replace an installed package whose signing certificate differs:

```
INSTALL_FAILED_UPDATE_INCOMPATIBLE  →  "App not installed."
```

So the v1.0.32 APK could never be installed over the v1.0.31 build on the phone,
and neither could any earlier one have been. Two consequences worth stating
plainly:

- **The in-app updater was never the problem.** The downloader streamed the
  right bytes and handed the right file to the installer. The *signature* was
  wrong, and "Download via browser instead" (the same asset, the same key) would
  have failed identically. A browser download only ever worked as a **fresh
  install** — e.g. after uninstalling the previous copy.
- **Each release made the situation no better.** Every new tag meant a new
  throwaway key, so the failure was permanent, not a one-off.

## 3. The second bug fixed alongside it

`ApkInstallerService` promoted a download to `cufmai-<version>.apk` when the byte
stream *ended*, not when it was *complete*. A dropped connection ends the stream
without raising, so a truncated ~220 MB APK could take the final name — and
`_existingApkPath()` then reused it for every later Install tap. The user would
be stuck forever on a file that cannot install.

Now:

- the file is promoted only when its byte count matches `Content-Length`;
  otherwise the `.part` is kept and the UI says *"Download stopped early (x of y
  MB) — tap Download to resume"* instead of falling back to a 220 MB browser
  download;
- a file under `_minPlausibleApkBytes` (5 MB) found under the final name is
  deleted rather than reused.

This is a different failure mode with the same dialog, which is exactly why it
was worth closing before telling anyone "it was only the signature".

## 4. The fix

Every release is now signed with **one project key** that lives in
`android/app/cufmai-release.jks` plus `android/key.properties` (both git-ignored).

| File | Change |
|---|---|
| `android/app/build.gradle` | `signingConfigs.release` read from `android/key.properties`; falls back to the debug config only when that file is absent (fresh clone, fork) |
| `.gitignore` (+ `android/.gitignore`, which already covered it) | `key.properties`, `*.jks`, `*.keystore` stay out of git |
| `tool/setup_release_signing.sh` | creates the keystore, writes `key.properties`, prints the GitHub secret values |
| `.github/workflows/release.yml` | decodes the key from secrets, **refuses to build without it**, then verifies the built APK's signer certificate against the keystore |
| `releases/publish.sh` | refuses to publish when the release key is missing (it would be a debug-signed release) |

The failure that started this is now unrepresentable in CI: a release either
carries the project key, or the job stops.

## 5. Set it up once

```bash
tool/setup_release_signing.sh --yes
```

It prints exactly what to paste into **GitHub → Settings → Secrets and variables
→ Actions → Repository secrets**:

```
ANDROID_KEYSTORE_BASE64      # base64 -w0 android/app/cufmai-release.jks
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS            # cufmai
ANDROID_KEY_PASSWORD         # optional; defaults to the keystore password
```

Then **back the keystore up** (plus both passwords) somewhere you will still have
it in five years — a password manager or an encrypted vault. The keystore *is*
the app's identity:

- **Lose it** → no installed copy of CUFMAI can ever be updated again; every
  device must uninstall and reinstall by hand.
- **Leak it** → whoever holds it can sign an APK Android will happily install
  over your app.

Do not rotate this key once devices are on it. Rotation means the one-time
uninstall, on every device, again.

## 6. The one-time reinstall (each device, once)

Android cannot replace a debug-signed install with a release-signed one, so the
first hop is manual and it costs app data:

1. Cut the next release (`pubspec.yaml` bump → tag → workflow, or
   `releases/publish.sh`) now that CI signs with the project key.
2. On each test device: **uninstall CUFMAI** (this clears app data — the
   Supabase session included; you will sign in again).
3. Install that release **from the browser**, once.
4. From the next release onward, **Install update** in *What's New* works
   normally, for every device, forever.

The *What's New* screen carries a short note under **Install update** explaining
step 2, because the installer's failure dialog cannot. It is marked transitional
in `whats_new_screen.dart` and can be deleted once no device is on an
old-key build.

## 7. Checking a build by hand

```bash
# What key is this APK signed with?
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk

# What key does the keystore hold?
keytool -list -v -keystore android/app/cufmai-release.jks -alias cufmai
```

The two SHA-256 fingerprints must match. The release workflow does this
comparison for every tag and fails the run if they differ, so an update that
cannot install cannot be published — the guarantee that was missing here.

## 8. Alternatives considered, and rejected

- **Ship the developer machine's debug keystore to CI.** It works, and it is
  worse: releases become coupled to one laptop's `~/.android` directory, the key
  is shared with every local `flutter run`, and nothing about it is a release
  identity.
- **Ask testers to uninstall on every update.** The original behaviour, with a
  support cost that scales with releases and hides real updater bugs.
- **Publish to Play Store and use its in-app updates.** The right long-term
  answer, and a different project: this self-hosted updater exists so a test
  build can be updated without a cable, until then.
