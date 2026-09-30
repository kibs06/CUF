# Session Log — September 30, 2026

**Date:** September 30, 2026
**Focus:** v1.0.34 shipped with the 3D box on for customers · a customer-device failure report (P30 Pro, pill-only) · the shipped APK proven byte-correct · the on-screen diagnostic built and shipped as v1.0.35 · a real prefetch bug found by re-reading the gate · the release-notes clobber hit again and was repaired again

> **How to read this.** Written from the work itself, in the repo's session-log shape: no
> wall-clock timestamps, and every claim labelled as *proven* (a command ran and said so),
> *measured* (a query or an artifact inspection read the thing itself), or *believed*
> (reviewed, not executed). It is a reconstruction from the session's own record, not a
> verbatim transcript — the raw turns live in the client.

---

## Executive Summary

The session in six steps, in the order they happened:

1. **v1.0.34 was published with `SHOE_PREVIEW=true` baked in** — the 3D box on for every
   customer, per the owner's explicit decision. Release path: commit the session's work in
   three commits, pre-bump pubspec to `1.0.34+37` (avoiding the `publish.sh`
   build-before-bump trap found the day before), run `releases/publish.sh`, and repair the
   release notes the tag-triggered CI run overwrote.

2. **The owner reported the 3D box still did not appear** on the device that matters — the
   seller/customer phone. The first diagnostic move was to prove the artifact was not the
   problem: the APK on the GitHub release is **byte-identical** to the box-on build
   (SHA-256 `af8661c6…59e9a2` on both), and the shipped `libapp.so` and dex carry the
   feature markers (`shoe-preview`, `renderer_feature_level_unsupported`, `preview fit`,
   `PREVIEW_FIT_MARGIN`).

3. **The device's constraints were established.** No phone was ever attached to this machine:
   the owner's phone is a **Huawei P30 Pro whose developer-options menu is locked behind a
   password the phone's previous owner set and forgot.** No logcat can ever be read from it,
   and bypassing that lock was correctly ruled out as a security boundary. Diagnosis had to
   work without the phone saying anything.

4. **Re-reading the gate to word the on-screen diagnostic correctly found a real bug.**
   `_prefetchTryOnModel()` returns while no size is selected — correct in itself — but a
   product payload that arrives without inventory only gets a size *after* `_fetchInventory()`
   picks one, and **nothing re-ran the prefetch afterwards**. No model bytes, ever; the page
   is indistinguishable from a product with no model. Fast Wi-Fi with inventory in the payload
   never triggers it (which is why the emulator never saw it); mobile data does.

5. **v1.0.35 shipped the fix plus the diagnostic:** the `_fetchInventory` re-entry, a visible
   Retry hint for a failed prefetch, and a visible "not supported on this phone" line for the
   renderer-refused state. Analyze clean, **2,208 tests pass / 7 skipped**.

6. **The release-notes clobber is now a confirmed pattern, not a one-off:** the tag-triggered
   `Release APK` workflow rewrote `version.json`/`changelog.json` with its default note again,
   and the notes were restored again (`081d1c5`).

---

## Timeline

### 1. "Publish v1.0.34 with the 3D box on for customers" — done the day before, confirmed live

The release itself (commits `50dfe40`, `a9aa572`, `61e9e95`, `3e467af`) had been completed at
the end of the previous working stretch; this session opened with it already live and
verified: release `v1.0.34`, asset `app-release-1.0.34.apk` (227,209,884 bytes), not a draft,
manifest carrying the four customer-facing notes, `Supabase Migrations` CI green.

One live risk was left open from that work and remains open: **the seller request sheet's new
fields (`p_upper_height_mm`, `p_sizes_eu`) require migration `20260929120000`, which is not
applied to the hosted project.** A seller who fills those fields gets an error; a blank
request still works. The repo's bundle generator (`tool/build_live_bundle.mjs`) correctly
refused to generate a bundle for that migration — its pre-flight and verification markers are
written for `20260928140000` only. Fixing the generator is deliberate future work, not a
hand-patch at release time.

### 2. "The 3D viewing still didn't appear" — proving the artifact innocent first

The report arrived with no device attached and no log reachable. The cheapest decisive check
was the artifact itself, because two release paths existed (local `publish.sh` with
`dart_defines.json` → box on; tag-triggered CI with `vars.RELEASE_DART_DEFINES` → box off)
and CI had already overwritten release files once:

- **The APK on the release is the box-on build.** Local `build/app/outputs/flutter-apk/app-release.apk`
  and the downloaded release asset hash to the same `af8661c67ea5092ff4280ea9f310a8d8dcd83d5042df8ccefdedd3999359e9a2`.
- **The feature is in the shipped binary.** After extraction: `shoe-preview` and
  `renderer_feature_level_unsupported` in `libapp.so` (Dart AOT); `preview fit`,
  `PREVIEW_FIT_MARGIN`, `renderer_feature_level_unsupported` in `classes6.dex` (Kotlin).

(One measurement along the way was a false alarm worth recording: a first grep over the APK
found nothing because the `unzip` pattern hadn't extracted `lib/` or `classes*.dex`. Checking
*what got extracted* before believing a negative result is the same discipline the framing
script demanded two days ago.)

With the build proven correct, the failure had to be runtime. The questions that narrowed it:

| Question | Answer | What it ruled out |
|---|---|---|
| Version on the phone? | **1.0.34** | The update landed; `featureOff` is impossible in this build |
| Which phone? | **Huawei P30 Pro** | F22's ES-3.0 class — the P30 Pro's Mali-G76 reports **OpenGL ES 3.2**, far above the renderer's floor |
| Which product? | **The JBC sandal, after waiting** | `noModel` and `modelNotReady` as *timing* explanations are gone |

Every default explanation eliminated at once. And the pill's own existence was evidence: the
"Try On in AR" pill renders only when the gate says hidden, and the renderer-refused path
removes the pill *with* the box (it lives inside the section). **Pill visible + GLES 3.2 +
model live in the database ⇒ the gate's `hasLocalModel` never became true — the prefetch's
bytes never arrived or never finished on that phone.**

### 3. The device that cannot speak: developer options locked

The owner could not enable USB debugging: **the developer-options password was set by the
phone's previous owner and forgotten.** This was accepted as a hard boundary, not worked
around — it is a security feature of the phone.

Consequences, now permanent facts about this product's testing:

- No `adb logcat` will *ever* be readable from this device.
- The `[shoe-preview] hidden: …` log line added in v1.0.34 — built precisely for this
  diagnosis — is unreachable on it.
- The app has to explain itself **on screen**, or the failure class stays undiagnosable.

### 4. Re-reading the gate found the bug

The owner approved shipping the on-screen diagnostic. Wordings were written from the gate's
source rather than paraphrased, which is what surfaced it:

- `resolveShoePreview`'s four reasons (`featureOff`, `notAndroid`, `noModel`, `modelNotReady`)
  were all silent on the page, and the fifth state — `TryOnPrefetchOutcome.failed` — didn't
  even reach the gate's reasons: a failed prefetch leaves `_tryOnPrefetchResult` without
  `spec`/`path`, so it *looks like* `noModel`.
- **The structural bug:** `_prefetchTryOnModel()` bails at `if (size == null) return;`. A
  payload without inventory takes the `_fetchInventory()` path, which auto-selects a size
  *after* `initState` — and nothing called the prefetch again. `_fetchInventory` now re-enters
  it (`if (_selectedSize != null) _prefetchTryOnModel();`), contract-pinned so it cannot
  regress.
- Retry reuses the same method; `TryOnPrefetch._inFlight` makes a concurrent double-call
  harmless. A `_retryingPrefetch` flag shows *"Checking for 3D preview…"* while it runs.

**Honesty note:** the prefetch bug is a strong *candidate* for the P30 Pro report, not a
proven cause — nothing from that phone can prove anything. The on-screen states are what make
the *next* report conclusive either way.

### 5. What shipped in v1.0.35

All Dart; no Kotlin, no migration.

| Change | Where | Behaviour |
|---|---|---|
| Prefetch re-entry after a late size | `product_detail_screen.dart` (`_fetchInventory`) | The box can appear on pages whose sizes arrive over the network |
| `ShoePreviewHint` widget | `shoe_preview_3d.dart` | A quiet line with an optional action; no action where none applies |
| Failed-prefetch hint with **Retry** | `_shoePreviewSection` | *"3D preview couldn't load just now."* — only when the product has a model and the prefetch failed; `noModel` stays silent (that is the catalogue being honest, not a fault) |
| Renderer-unsupported line | `ShoePreviewSection` (replaces `SizedBox.shrink()`) | *"3D preview isn't supported on this phone."* — no button, because there is nothing that phone can do; the AR pill still goes with the box (the AR path cannot draw either) |

Tests: `shoe_preview_3d_test.dart` gained the words-stay assertion on the unsupported path and
a direct `ShoePreviewHint` test; the contract test gained two guards — the failed-prefetch
hint wiring (including the `noModel` exclusion) and the `_fetchInventory` re-entry. The
contract test's `between()` window for `_shoePreviewSection` was repointed from `'\n  }'` to
`'\n  /// Fetch inventory'` because the helper grew a second exit path. `flutter analyze lib
test tool` clean; `flutter test` **2,208 pass / 7 skipped**.

### 6. The release, and the clobber pattern confirmed

Version pre-bumped to `1.0.35+39` **before** the build (the `publish.sh`
build-before-bump trap found during v1.0.34 — the script's `update_release_files.dart`
increments the build number from whatever pubspec says, so the pre-bump composes correctly).

- Commit `cc37c9e` — the fix, the hints, the tests, the CHANGELOG entry.
- `publish.sh 1.0.35` with three customer-facing notes → release `v1.0.35`, asset
  `app-release-1.0.35.apk` (227,226,268 bytes), `versionCode 39`, `versionName 1.0.35`, same
  release signer, all four feature markers in the AOT snapshot.
- The tag fired `Release APK` again; it again **overwrote the notes** with
  `"Release v1.0.35"` (commit `a0c1a5e` on origin). Fast-forwarded, restored the three notes
  verbatim in both JSON files with a minimal `str_replace` (a first attempt rewrote both
  files wholesale and churned line endings — reverted, redone surgically), committed `081d1c5`,
  pushed. This is the **second consecutive release** with the same failure; the fix belongs
  in `release.yml`/`publish.sh`, not in another manual repair.

Verified end to end: `raw.githubusercontent.com/.../releases/version.json` serves
`latest_version: 1.0.35` with the three notes and the correct `apk_url`; the release is
public (not a draft).

---

## What is still open

1. **The P30 Pro verdict.** Update to 1.0.35 via the in-app updater, open the JBC sandal, and
   one of three things appears: the **box** (prefetch bug confirmed as the cause), the
   **Retry hint** (a real runtime failure, now visible and actionable), or the
   **"not supported" line** (that specific unit caps below the renderer's floor — unusual
   for a P30 Pro, would warrant a check in phone info). Until one of these is reported back,
   the root cause is unconfirmed.
2. **Migration `20260929120000` is still not applied to the hosted project**, and the live
   bundle generator refuses to build for it (its markers are hardcoded to the earlier
   migration). Until either lands, a seller filling the new request-sheet fields errors.
3. **The release-notes clobber** (`Release APK` overwrites `version.json`/`changelog.json`
   notes on every tag) — twice now. Fix in the workflow, not by hand a third time.
4. **The commercial F22 gap** is unchanged: phones capped at OpenGL ES 3.0 render no 3D shoe
   at all until the material path uses precompiled `.filamat` files. They now at least *say
   so* on screen.
5. **Nothing committed for it yet:** the framing/spin/lighting tuning from the prior session
   (F23) still awaits a real device render for judgement; framing math is verified, aesthetics
   are not.
