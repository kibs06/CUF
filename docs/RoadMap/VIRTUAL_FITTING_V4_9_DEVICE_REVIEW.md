# V4.9 — On-device review: 10 real products, real feet

**Version:** 1.0 (protocol) · **Status:** ready to run — the build switches, the readout seam and the capture tooling
exist; the numbers do not yet.
**First run (2026-10-05, while §1 was being prepared):** the opening AR load crashed inside Filament's
`setTransform` — the write passed the model's *entity* where a component *instance* belongs — and the fix
(`modelRootTransformInstance` / `writeModelTransform` in `ArTryOnView`) replaced the build mid-session.
Every number below is read from the fixed build; the crashed run's file channel is kept in
`build/qa/nav_diag_pre_crashfix.log`.
**Sits at:** `VIRTUAL_FITTING_ROADMAP.md` row V4.9 (the last V4 phase).
**Companion docs:** `VIRTUAL_FITTING_ROADMAP.md` (V4 rows, §7 metrics), `VIRTUAL_FITTING_ARCHITECTURE.md`
(§2.11 budgets, §2.15 device QA), `AR_TRY_ON_SPIKE_FINDINGS.md` §8 (the V0.6 recipe this mirrors).

---

## 0. Why this exists and why a desk cannot do it

Every V4 phase was built and desk-verified (V4.1–V4.8: Dart loop, native tracker, frame-scale correction, mask
occlusion, coach card, live verdict, saved-size suggestion, perf/stability pass). What none of them can settle from
a desk:

| Question | Phase | Why only a device answers it |
| --- | --- | --- |
| Does a backgrounded session really come back? | V4.8 | The native resume is compile-checked, never run |
| Do the numbers survive 20 open/close cycles? | V4.8 | ≤ 250 MB budget is a runtime measurement |
| What does a throttling phone's `thermal=` read? | V4.8 | `PowerManager` on real hardware |
| Is the live length *right*? | V4.3/V4.6 | Toe UV landing, foreshortening, occlusion |
| Does the shoe read as *worn*? | V4.4 | The occlusion's blind review |
| Does a real customer lock in 10 s? | V4.1–V4.7 | The whole loop, on real feet, in real light |

The V4 exit criteria (roadmap):

> ≥85% of good-light sessions lock within 10 s; shoe stays visually attached through normal foot movement;
> occlusion reads as "foot inside shoe" in a blind review by 5 people; no regressions in the scan flow's tests.

This document turns each sentence into a procedure and a number.

---

## 1. Build the QA APK

The try-on switches are **compile-time Dart defines**, so the artifact decides what it can do. The QA APK workflow
(`.github/workflows/qa-apk.yml`) now carries the try-on inputs beside the renderer ones:

```bash
# The full V4 session build: renderer + foot loop + bundled partner asset + on-screen readout.
gh workflow run qa-apk.yml -f try_on=true -f foot_track=true -f qa_model=true
```

Always pass `-f diagnostics=true` (the default) — the on-screen heartbeat is this session's primary evidence.

| Input | Define | What it does |
| --- | --- | --- |
| `try_on=true` | `TRY_ON_V3=true` | The product path may render a real shoe |
| `foot_track=true` | `TRY_ON_FOOT_TRACK=true` | The V4 detection loop runs (needs `try_on`) |
| `qa_model=true` | `TRY_ON_PLACEHOLDER_MODEL=true` + `TRY_ON_QA_MODEL=assets/models/qa_partner_shoe_v1.glb` | Serves the bundled partner asset as every product's model — needed while `product_models` holds 0 rows |
| `diagnostics=true` | `SHOE_PREVIEW_DIAGNOSTICS=true` | The on-screen heartbeat, and (V4.9) the switch the try-on session now honours |

> **⚠️ `SHOE_PREVIEW=true` is not optional for this session.** The **Try On in AR** pill lives inside the
> 3D viewer section the `SHOE_PREVIEW` switch mounts; a build without it has no 3D icon, no viewer and
> therefore no AR entry at all — it looks like the feature was deleted. (This was hit for real on
> 2026-10-05: a local QA build with every try-on define passed but no `SHOE_PREVIEW` could not reach the
> try-on screen.) The CI workflow always passes it; a local build has to repeat it.

A local build of the same thing (debuggable is the point; the QA seams are honoured only in a debuggable APK):

```bash
flutter build apk --debug \
  --dart-define=SHOE_PREVIEW=true \
  --dart-define=SHOE_PREVIEW_DIAGNOSTICS=true \
  --dart-define=SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1=true \
  --dart-define=SHOE_PREVIEW_ALLOW_LEVEL1=true \
  --dart-define=SHOE_PREVIEW_WEBVIEW=true \
  --dart-define=TRY_ON_V3=true \
  --dart-define=TRY_ON_FOOT_TRACK=true \
  --dart-define=TRY_ON_PLACEHOLDER_MODEL=true \
  --dart-define=TRY_ON_QA_MODEL=assets/models/qa_partner_shoe_v1.glb
```

The three `SHOE_PREVIEW_*` QA locks match the CI artifact's defaults. `LOWER_ENGINE_TO_LEVEL1` and
`ALLOW_LEVEL1` are what let a feature-level-1 phone (the class of device F14 says cannot load a model at
all) attempt the render instead of refusing — for the **AR** session they arrive through the model
handover (`parseModelSpec`), so a phone whose GLES resolves `FEATURE_LEVEL_1` still gets a shot.

**V4.9 update (2026-10-06) — the placeholder defines have a successor.** `product_models` is no longer
empty: rows 5 (*JBC Crown Leather Sandals*) and 6 (*HABÍ — Woven Slides*) went live through the
admin portal's compress pipeline, and their storage objects verify byte-identical to the two bundled
QA assets (`6819ab8d…` = `qa_partner_shoe_v1.glb`, `cae9b866…` = the 40,500-triangle HABÍ file).
With the two `TRY_ON_PLACEHOLDER_MODEL` / `TRY_ON_QA_MODEL` defines **dropped**, the production path
(`SupabaseShoeModelDataSource`) serves each product its **own** real model through the same
resolve → digest-verify → cache pipeline — which is also the fix for the "both products show the
same 3D model" observation, since the bundled seam serves one asset to every product by design.
The per-product QA build is therefore:

```bash
flutter build apk --debug \
  --dart-define=SHOE_PREVIEW=true \
  --dart-define=SHOE_PREVIEW_DIAGNOSTICS=true \
  --dart-define=SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1=true \
  --dart-define=SHOE_PREVIEW_ALLOW_LEVEL1=true \
  --dart-define=SHOE_PREVIEW_WEBVIEW=true \
  --dart-define=TRY_ON_V3=true \
  --dart-define=TRY_ON_FOOT_TRACK=true
```

Keep the placeholder variant above for runs P1–P8 (deterministic, no network) and use this one when a
run needs the catalogue's real per-product models (P10, partner demos, anything that asserts
two products render two different shoes). A product without an active row degrades exactly as the
capability gate promises.

**Also build the control:** the same command with `-f try_on=false -f foot_track=false -f qa_model=false`. P9 checks
that the try-on entry degrades to the simulated screen on every product — a fallback is a success case, never a dead
end.

> **None of these switches may ever appear in a customer build.** The CI artifact is flagged "not a release" for
> exactly this reason; delete the switches (and this doc's build block) when V4 closes.

---

## 2. Prerequisites

1. **A QA APK** (§1) and the control build.
2. **Test device(s).** ARCore-capable phone. The project's known test phone (Huawei P30 Pro) has developer options
   locked — no `adb logcat` will ever be read from it, which is why the app exports its own logs (§3). A second phone
   or emulator with adb makes capture mechanical; the protocol works on the locked phone alone.
3. **10 real products.** Anything the shop actually sells, each with a real size chart (the fit verdict needs a
   `LastSpec` — without one the card is hidden by design). Fill §6.1 before starting. The bundled partner model
   renders for all of them; what is real is the product row, the sizes and the feet. **The page gate is part of
   the seam since 2026-10-05** (`try_on_prefetch` takes `placeholderModelService()` behind
   `app_constants.dart`'s `TRY_ON_PLACEHOLDER_MODEL`, so the 3D icon and the viewer's "Try On in AR" button
   appear in a `qa_model` build even though `product_models` holds 0 rows) — before that fix, a build with every
   try-on define still had **no way to open the try-on screen from the page at all**.
4. **Real feet + a tape measure.** At least two people, one barefoot measurement each per product run; note socks.
5. **5 blind reviewers** for §5 P3 — people who have not read this document's occlusion section.
6. **A room** with good light (door/window daylight or a well-lit room, no strong backlight) for P1; a dim room for
   the failure-mode note.
7. **`tool/qa_capture.sh`** for adb-attached devices:

   ```bash
   bash tool/qa_capture.sh --tryon --seconds 90        # → build/qa/capture-<timestamp>/
   ```

   Read the `digest.txt` first: `tryon_sessions`, `tryon_locks_within_10s`, `tryon_lock_edges`, `foot_last`,
   `len_last`, `scale_last`, `thermal_last`, `meminfo_max_pss_kb`, and the freeze/loop lines the script already
   computed.

---

## 3. Evidence channels

The V4.9 session reads the same facts through three doors, depending on the phone:

| Channel | What it carries | How to read it |
| --- | --- | --- |
| **On-page heartbeat** | One line: `loop=`, `iter=`, `present=` (the fps proxy), `beginFail=`, `chain=`, `surface=`, `asset=`, `feed=`, `foot=`, `len=`, `scale=`, `frame=`, `mask=`, `thermal=` | Screenshot. It is on the screen only when the build passed `SHOE_PREVIEW_DIAGNOSTICS=true`, and (V4.9's fix) the try-on session now asks for it over its own channel |
| **Device file** | The same line, at most once a second, written to `files/qa_preview_status.txt` | `adb exec-out run-as com.solevision.app cat files/qa_preview_status.txt` (a QA APK is debuggable); `qa_capture.sh` pulls it |
| **`nav_diag` export** | `[preview]` lines: `session resumed (startSession)`, `footLock locked=… quality=… side=…`, `setDiagnostics(…)`, engine/teardown lines | On the locked-down phone: **Settings → Developer → App logs → Send the whole file** (dev mode on: swipe 2 up, 2 down, 2 right, 2 left on the Create-account screen), or the bug icon in Foot Sizing's app bar. The lines carry wall-clock timestamps, so the P1 metric can be re-derived from an exported file alone |

⚠️ **Measured 2026-10-05, before this session's first capture: `nav_diag` is written by two writers — the Dart logger and the
native relay — and they can overwrite each other's bytes.** The signature is a line that is a *tail* of a native line with
a Dart line's text where its beginning should be (`review] camera feed: EGL context prepared…`, byte offset 12109 of the
file), plus native lines that exist in `adb logcat` but not in the file (the whole first engine mount at 20:11:25). Both
writers hold the file open; the Dart side's offset is evidently not an `O_APPEND` position, so a longer native line moves
the end past it and the next Dart write lands mid-line. **Consequence for reading:** a missing line is not proof an event
did not happen — cross-check against `adb logcat -v threadtime | grep NavDiag` when a cable is available (every relay line
is also logged to logcat under tag `NavDiag`), and treat line counts as unreliable. **Follow-up (V4.10 candidate):** the
Dart logger must write with `FileMode.append` per line (or track the file's true length), because on the locked-down phone
this file is the only channel.

### 3.1 The camera that never started (found and fixed 2026-10-05)

**The first capture's most useful lines were the ones that were not there.** Across 20:09–21:06 the try-on session
produced no `setDiagnostics`, no `startSession` and no `session resumed (startSession)`, while the camera device was
opened exactly once — by the **foot scan** (`ArFootSizingView`, 20:11:43.7). The AR view was mounted for **48 minutes**
(`presented=173,660` in its own teardown line) drawing its clear colour: the black camera this review exists to measure.

**What it was: a race, and one the code already had a seam for.** `ar_fitting_screen.dart` called
`startAr(arViewReady: true)` once, from `onPlatformViewCreated`, and `TryOnSessionController.startAr` returns at its
`_phase != TryOnPhase.modelReady` gate. On a device the view is created a frame or two after the screen builds, while the
model still has to be resolved, verified and handed over — so *view first, modelReady later* is the **usual** ordering,
the call was dropped (leaving `_arStarted` false), and nothing ever called back. `needsArStart` (`phase == modelReady`)
had existed since V3 for exactly this and was never wired. The screen now records the platform view's creation and both
call sites funnel into `_startArIfReady()`: the phase landing on `modelReady` retries the start, and `arViewReady: true`
is only ever passed once the view provably exists (a guess would be F17's 15 s parking timeout and the `arViewNotReady`
fallback rather than a session). The dropped call now logs `[TryOn] startAr dropped: phase=…` to logcat, because the
silence is what let this live for 48 minutes.

**What a working start looks like — the four markers to grep for, in order:**

```
setDiagnostics(true) — applied             ← startAr ran; `parked` would mean it arrived before the view
session resumed (startSession)             ← the ARCore session is up (P1's marker; also in nav_diag)
[preview] camera feed: ready (texture=1)   ← the room is bound to the feed's texture
CameraManager: Open camera / ArCameraFeed  ← the camera device itself (a start without this is a session that never resumed)
```

**Second finding, unexplained — watch for it.** 21:00:19.86, `SIGSEGV, SEGV_MAPERR, fault addr 0x4` inside
`libfilament-jni.so` (`Java_com_google_android_filament_Renderer_nRender+24`) ← `Renderer.render` ←
`ArTryOnView.renderFrame`, on the `solevision-tryo` render thread, 1.3 s after a mount whose model load had completed and
with no session started (`beginFrame` had not refused; no `footLock`). In AR mode with `session == null` neither the AR
camera branch nor the preview branch of `renderFrame` runs, so the room quad was bound to a texture nothing updated —
whether that is the cause is **not** known. Tombstone: `build/qa/crash_renderloop_21h00.log`. Every capture that opens
the AR screen should check for a repeat (`logcat | grep "F DEBUG"`, or the crash buffer), and a repeat is V4.10's
reproduction rather than a re-run.

`qa_capture.sh --tryon` computes P1's metric from these two markers:

```
session resumed (startSession)   ← one per try-on screen open
ArTryOnView: footLock locked=true ← the first one after a start is that session's time-to-lock
```

---

## 4. The session's own numbers

Know what each heartbeat field can and cannot say before reading it:

| Field | Meaning for this run |
| --- | --- |
| `foot=idle/locked/lost q` | The tracker's own state; `locked` is the authority (native hysteresis, 0.7 in / 0.45 out) |
| `len=` | The eased heel→toe length in mm — the number the shoe is scaled with, and the one P7 tapes against |
| `scale=` | The ×N frame-scale correction; `1.000` means "the size chart's answer stands" |
| `mask=` | `off` (never attached) / `ready` (no mask yet) / a mask with quads — the three answers a "not occluded" report needs |
| `thermal=` | `none`…`shutdown` (`n/a` below Android 10) |
| `present=` | Frames presented in the last second ≈ fps; watch it, not `iter=` |

---

## 5. The checks

### P1 — Lock rate (the ≥85% criterion)

**Setup.** P1 is 20 sessions in good light: the 10 products twice (or 10 products + 10 second runs). One session:

1. Open the product → **Try On in AR**.
2. Point at the floor, put one foot in frame, hold still. Do not tap for manual placement.
3. Stop when the shoe locks (or at 30 s, whichever first). Standing in the frame with a locked shoe, wait 2 s.
4. Back out. That is one session.
5. `qa_capture.sh --tryon` (or one continuous capture over a batch) records each start and its first lock.

**Pass:** `tryon_locks_within_10s / tryon_sessions ≥ 0.85` over the 20 good-light sessions. Sessions in bad light
are recorded separately and never counted toward the bar (the criterion says good light).

**Also record:** the manual-placement offer firing (15 s without a lock) — each one is a failed session for P1 and
a V4.5 data point.

### P2 — Attachment through movement (the "stays visually attached" criterion)

10 sessions (one per product; the P1 runs can be reused if you then move):

hold still 5 s → lift the heel 3–5 cm → turn the foot 30° left, then right → small side steps → step out of frame,
step back in. Rate each session:

- **2** attached — no visible slip, no snap, no resize pop
- **1** attached with a transient slip that recovers by itself
- **0** detaches, slides, or pops in scale and does not recover

**Pass:** ≥ 9 of 10 sessions rated 2, none rated 0. A 1 is recorded with the movement that caused it.

### P3 — Occlusion blind review (the "foot inside shoe" criterion)

Capture 10 short clips during normal use (screen recording or a second phone):

- **5 occlusion clips:** the shoe worn, foot visible where it should cover the shoe (side and heel angles).
- **5 control clips:** shoe alone on the floor, or foot deliberately *beside* the shoe.

Shuffle them so no reviewer can order them, and ask each of the 5 reviewers one question per clip: **"Is the foot
inside the shoe?"** (yes / no / can't tell). Do not explain the mask or which clips are which.

**Pass:** every reviewer answers "yes" on ≥ 4 of the 5 occlusion clips, **and** no more than 1 "yes" across the 5
control clips (a false positive is the failure mode — occlusion that swallows the shoe). "Can't tell" counts as a
miss on occlusion clips and as correct on controls. Record the sheet in §6.2; a disagreement is a V4.4 finding,
not a tie to break.

### P4 — Backgrounding (V4.8's device half)

5 repetitions:

1. Lock a shoe (wait for `foot=locked`).
2. Home → wait 30 s → return.

**Pass per repetition:** the shoe is still attached within 2 s of return, `loop=on` and `iter=` climbing in the
heartbeat, and the `nav_diag` export shows `session resumed after the surface returned`. **Fail:** a frozen picture,
a heartbeat that never returns, or a new `session resumed (startSession)` line (that would mean the screen
restarted instead of resumed).

### P5 — Twenty cycles and the memory budget

20 × (open try-on → 20 s including a lock → back). Capture with `--tryon` so `meminfo.txt` samples TOTAL PSS every
5 s.

**Pass:** peak `meminfo_max_pss_kb` inside the architecture's ≤ 250 MB budget — `dumpsys` reports KiB, so the
comparison is 256,000 (record the raw number either way) — and no monotonic climb: operationally, the max of the
last five samples is not more than **20,480 kB above** the max of the first five (this margin is the protocol's
leak detector, not a spec; if it trips, the numbers go in the report and V4.10 decides).

### P6 — Thermal

One continuous 5-minute session with the shoe locked and the phone in normal use. Read `thermal=` every 30 s from
the heartbeat (or `adb shell dumpsys thermalservice` on an adb device).

**Pass:** the session completes with no `critical` / `emergency` / `shutdown` reading, and `present=` (the fps
proxy) never collapses to single digits. Record the highest word, the ambient condition, and whether the shoe
visibly lagged under it. A `severe` reading is recorded, not failed — the number is what V4.10 tunes against.

### P7 — Live length vs a tape measure (tuning data, not a pass/fail)

For 10 feet: tape the foot (heel to longest toe, mm), then hold the lock for 5 s and read `len=` from the
heartbeat. Record both and the error. These are the numbers that tune the toe UV landing, `kPlausibleFootLengthMm`
(110–360), the ×N clamp (0.70–1.30) and the 11 mm toe room. **Flag |error| > 15 mm** as "needs investigation
before V4 closes" — that bar is the protocol's, not a spec; every error is reported either way.

### P8 — Coaching and framing (V4.5's workshop numbers)

While running P1/P2, note every time the coach card says "move closer" / "move back" / "hold still" and what
actually happened next (locked / not locked). These tune `kFootFramingTooFar` (0.30) and `kFootFramingTooClose`
(0.92). Record mismatches — a "move closer" on a foot that then locks immediately is a band that is too tight.

### P9 — Fallbacks and regressions

1. Install the **control build** (`try_on=false`): every one of the 10 products opens the try-on entry into the
   simulated screen — no dead end, no crash.
2. On the full QA build, visit one product with **no size chart** and one with no stock: the verdict card is hidden
   (not guessed), the entry still works.
3. Scan-flow smoke on the device: run one foot scan end-to-end (the V4 work must not have touched it; prove it).
4. Desk check on the reviewed commit: `flutter analyze lib test && flutter test` green.

### P10 — Verdict sanity (observation, no threshold)

For each of the 10 products, compare the live verdict card (V4.6) against the owner's/artisan's judgement of that
foot in that size. Record agree / disagree / nudged. This is the same artisan-opinion method V1's exit criterion
asks for; it feeds the §7 metrics log rather than a pass/fail here.

---

## 6. Recording sheets

### 6.1 Product run sheet (fill before the session)

| # | Product | Size tested | Size-chart spec (mm) | Foot (person) | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | | | | | |
| … | | | | | |
| 10 | | | | | |

### 6.2 Occlusion blind review

| Reviewer | Occlusion clips "yes" (of 5) | Control "yes" (of 5) | Comments |
| --- | --- | --- | --- |
| R1 | | | |
| … | | | |
| R5 | | | |

### 6.3 Run results

| Check | Result | Evidence |
| --- | --- | --- |
| P1 lock rate | `__/20 = __%` | `tryon_lock_times.txt` / export |
| P2 attachment | `__/10 rated 2`, `__ rated 0` | notes |
| P3 occlusion | pass / fail | §6.2 |
| P4 backgrounding | `__/5` | export lines |
| P5 memory | peak `__ MB`, drift `__ MB` | `meminfo.txt` |
| P6 thermal | max `__`, fps floor `__` | heartbeat samples |
| P7 length | `__/10 flagged > 15 mm` | tape sheet |
| P8 framing | `__` mismatches | notes |
| P9 fallbacks/regressions | pass / fail | control build + scan smoke |
| P10 verdict sanity | `__/10 agree` | notes |

---

## 7. Closing V4.9

- File each capture folder (`build/qa/capture-*`, exports, screenshots, §6 sheets) beside this document's commit.
- Write the results into `VIRTUAL_FITTING_ROADMAP.md` §7's metrics log (the row already exists for V4.9).
- **V4 closes when** P1–P6 and P9 pass on the QA build, P3's blind review passes, and the P7/P8/P10 numbers are
  recorded with their follow-ups named. Anything that fails becomes V4.10's fix list with the capture folder as
  the reproduction — never a re-run "to see if it happens again".
- **Retire the seams when V4 closes:** delete this file's build block's switches from the QA workflow defaults,
  and treat `TRY_ON_*` as V5's problem only if V5 keeps them.
