# Session Log — September 30, 2026

**Date:** September 30, 2026
**Focus:** v1.0.34 shipped with the 3D box on for customers · a customer-device failure report (P30 Pro, pill-only) · the shipped APK proven byte-correct · the on-screen diagnostic built and shipped as v1.0.35 · a real prefetch bug found by re-reading the gate · v1.0.36's catalogue-fact silence rule · **the P30 Pro's screenshot confirming F22 on real hardware, and v1.0.37's AR-entry fix** · the release-notes clobber repaired four times

> **How to read this.** Written from the work itself, in the repo's session-log shape: no
> wall-clock timestamps, and every claim labelled as *proven* (a command ran and said so),
> *measured* (a query or an artifact inspection read the thing itself), or *believed*
> (reviewed, not executed). It is a reconstruction from the session's own record, not a
> verbatim transcript — the raw turns live in the client.

---

## Executive Summary

The session in eight steps, in the order they happened:

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

7. **v1.0.36: the owner tested v1.0.35 — still pill-only, with no words.** On a build where
   every intended-hidden state has words, that meant the page sat in a state the rule did not
   cover: a resolve-phase failure computes reason `noModel` and was excluded by design, and a
   never-completed prefetch left the result null behind a "transient" `modelNotReady`. The
   fix keys the silence rule on a **measured catalogue fact** (`_productHasLiveModelRow`)
   rather than on prefetch luck, and gives a still-null prefetch words after a 12-second
   grace period. Published, notes repaired (third clobber).

8. **v1.0.37: the owner's screenshot showed the JBC page saying *"3D preview isn't supported
   on this phone."*** — F22's renderer refusal confirmed on real hardware, the root cause
   after three releases of silence. The same report caught the all-or-nothing rule eating the
   AR pill mid-visit (tap pill → AR → back → both entries gone). The section now loses its
   box and **keeps its button** (the owner's decision; the AR screen degrades to its
   simulated mode with an honest notice), and the refusal maps to its own degrade reason,
   `rendererUnsupported`. Published, notes repaired (fourth clobber).

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

### 7. v1.0.36 — the report came back unchanged, and that was the finding

The owner tested v1.0.35 on the P30 Pro (Wi-Fi, the JBC sandal, after waiting): **still
pill-only, with no words.** On a build where every intended-hidden state has words, silent
pill-only means the page sat in a state the v1.0.35 rule did not cover. Before asking anything,
the artifact was re-proven: the GitHub asset hashes identical to the local build
(`6991aa6f…a7fc28`), the phone's Settings says 1.0.35, the JBC page is the one product with a
live model. One scare dissolved on inspection: `"Checking for 3D" => MISSING` in the AOT
snapshot was a **string-encoding artifact** — that message ends in `…` (U+2026), forcing the
whole string into UTF-16, invisible to an ASCII grep. Trusting the byte check would have sent
the hunt the wrong way.

Re-reading the rule just written found the two states it still silenced:

1. **A resolve-phase failure** (network hiccup, timeout) returns outcome `failed` with no
   spec — so the gate computes reason `noModel`, which the v1.0.35 hint **excluded by design**
   (no-model products must stay quiet). A resolve failure hid behind the catalogue's honesty.
2. **A prefetch that never completed** leaves the result null (`modelNotReady`), silent
   because it was presumed transient — but if inventory never loaded a size, "open the page
   again" never helps.

The fix is a **different question, not a looser rule**: the page now measures the catalogue
fact directly (`_productHasLiveModelRow`, one indexed read of `product_models`, independent
of the prefetch whose failure it diagnoses; a failed read leaves null and the page silent —
never a wolf). With a live row, **every hidden state gets words**: a failed prefetch
immediately, a still-null one after a **12-second grace period** (`_previewWaitTimer`,
cancelled in `dispose`). A product with genuinely no model row stays silent. The contract
test's hint guard was rewritten to pin the new shape, plus a guard for the timer.

One build-hygiene lesson worth keeping: the first commit of this fix churned **2,593
insertions** — the working file had been silently converted to CRLF while the parent blob was
LF, and my first repair attempt (forcing CRLF) made it worse before inspection of the actual
blobs (`git cat-file -p | od -c`) settled it. Normalized to LF, amended, and the diff came
down to **100 insertions, 10 deletions**. Check what the parent blob stores before guessing
at line endings under `core.autocrlf=true`.

Published as **v1.0.36** (`versionCode 41`), notes repaired after the CI clobber (third
occurrence).

### 8. v1.0.37 — the screenshot that closed the case

The owner's report arrived **as a screenshot of the JBC page showing the exact line
*"3D preview isn't supported on this phone."*** — the `renderer_feature_level_unsupported`
state, F22's guard working on real hardware. **Root cause confirmed:** the P30 Pro's Filament
context lands below the glTF floor despite GLES 3.2 on paper. The prefetch was never the
fault; it was the renderer all along, masked by three releases of silence — and it could only
be *reported* because the page had learned to speak. The catalogue fact and grace period of
v1.0.36 did their job getting the diagnosis here; none of them fired because the fault was
not theirs.

The screenshot also caught a **design decision that was wrong, with the perfect repro**: the
owner tapped the pinned "Try On in AR" pill while the model was still downloading, went to
AR, came back — and the pill was gone. Sequence: download finishes mid-visit → gate flips to
*shown* → the section mounts → the renderer refuses → the section removed **itself, taking
the AR button inside it** — and the page's fallback pill only renders while the gate says
*hidden*. Both AR entries gone, mid-visit. The all-or-nothing rule was written when the
simulated AR screen was a bare placeholder; with a stated degradation available, the owner
decided the AR entry **stays**.

So v1.0.37 changed two things:

- **The section loses its box and keeps its button.** The unsupported state renders the
  not-supported line *plus* the AR pill. The contract test's order guard was updated (the
  customer sees the shoe before the camera — in the normal composition; the unsupported
  branch's pill precedes the box reference because there is no box), and the widget test now
  pins the pill's survival with the full history of why the old assertion ("offering a
  camera would be a promise we cannot keep") was wrong.
- **The AR session names the real reason.** The renderer-refusal event mapped to generic
  `arFailed` inside a session; it now has its own degrade reason, `rendererUnsupported`
  (`try_on_mode.dart` — the literal spelled like its siblings, import-free, pinned to
  `kRendererUnsupportedReason` by the contract test), so the simulated screen can say "this
  phone can't render 3D" rather than "AR failed". The owner also reported the AR screen
  itself looked **broken/empty** on the phone — whether the simulated mode now renders
  sensibly on it is still awaiting one more look.

Full suite **2,211 pass / 7 skipped**; analyze clean. Published as **v1.0.37**
(`versionCode 43`), notes repaired after the CI clobber (**fourth** occurrence).

---

## What is still open

1. **The simulated AR screen on the refused phone.** v1.0.37 keeps the pill and names the
   reason — but whether the simulated mode actually *renders* something usable on the P30 Pro
   is unverified; the owner's last AR run was "broken/empty". One visit answers it.
2. **Migration `20260929120000` is still not applied to the hosted project**, and the live
   bundle generator refuses to build for it (its markers are hardcoded to the earlier
   migration). Until either lands, a seller filling the new request-sheet fields errors.
3. **The release-notes clobber** (`Release APK` overwrites `version.json`/`changelog.json`
   notes on every tag) — **four times now** (v1.0.34 through v1.0.37). Fix in the workflow,
   not by hand a fifth time.
4. **The commercial F22 gap, now measured on a real phone:** a flagship-class P30 Pro cannot
   render the 3D shoe — this is not only a low-end-device problem. Until the material path
   uses precompiled `.filamat` files, 3D preview is a feature of the phones Filament happens
   to come up at level 2+ on, and the page says so where it does not.
5. **The framing/spin/lighting tuning** (F23) still awaits a render on a phone that *can*
   draw it; framing math is verified, aesthetics are not.
