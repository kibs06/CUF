# AR Foot Scan ("Get Your Foot Size") — Test & Error Analysis

**Date:** 2026-08-23
**Scope:** The full AR foot-measurement feature — Dart scan screen, platform channel, native
ARCore plugin (Kotlin), ML Kit segmentation detection, and the statistical measurement pipeline.
**Verdict:** The pure-Dart logic is healthy (all 84 unit tests pass, `flutter analyze` clean),
but the **integration layer (native plugin ↔ Flutter) contains several real defects**, including
one confirmed ANR in the captured logcat, one dead fallback path, and two measurement-correctness
bugs that can silently produce wrong sizes.

> **Fix status update — 2026-08-25.** As part of the "Get Your Foot Size 2.0" rewrite
> (`lib/screens/customer/foot_size_v2/`, `lib/providers/v2/`), the following were fixed:
> **E5** + **E10** natively in `ArFootSizingView.kt` (shared by v1 and v2), and **E7**, **E8**,
> **E13** in the new v2 controller/pipeline (`scan_session_controller.dart`,
> `ar_foot_measurement_pipeline.dart`). Details in each defect section below. Remaining open:
> **E6**, **E9**, **E11**, **E14** (all low-risk), plus on-device re-verification of **E1**.

---

## 1. What was tested

| Layer | File(s) | Method | Result |
|---|---|---|---|
| Statistical pipeline | `lib/utils/ar_foot_measurement_pipeline.dart` | `flutter test` (84 tests) | ✅ All pass |
| Foot detection logic | `lib/utils/foot_detector.dart`, `test/utils/foot_detector_test.dart` | `flutter test` | ✅ All pass |
| Sizing math | `lib/utils/foot_measurement_utils.dart`, `test/utils/foot_sizing_v3_test.dart` | `flutter test` | ✅ All pass |
| Static analysis | all 7 AR-related files | `flutter analyze` | ✅ No issues |
| Native bridge | `android/.../arfoot/ArFootSizingView.kt`, `ArFootSizingPlugin.kt` | Code review + logcat | ❌ Defects found |
| Scan screen | `lib/screens/customer/foot_ar_scan_screen.dart` | Code review | ❌ Defects found |

Because every pure function passes its tests, any error a user sees on-device comes from the
native/integration code below — exactly where the historical "Foot detected but 0 samples" and
the ANR in `ar_logcat_capture.txt` lived.

## 2. Architecture recap (one paragraph)

`FootArScanScreen` opens a native `GLSurfaceView` via `PlatformViewLink` (`ar_foot_scan`),
which runs an ARCore session (`ArFootSizingView.kt`). Every 200 ms during a 4-second capture,
Dart pulls a cached NV21 CPU frame over the method channel, runs ML Kit Selfie Segmentation
(`MlKitSegmentationFootDetector` → `evaluateFootMask` PCA heel/toe/width extraction), then
raycasts those normalized points through ARCore `hitTest` to get 3D world positions.
Samples go through IQR outlier filtering + medians (`combineGuidedSamples`) → sock compensation
→ EU/US/UK size lookup. Two captures per foot (TOP view for width, SIDE view for length).

---

## 3. Confirmed errors & defects

Severity: 🔴 high · 🟠 medium · 🟡 low.

### 🔴 E1 — App Not Responding (ANR) on entering the scan screen — *confirmed in logcat*

`ar_logcat_capture.txt:3` records:

```
08-01 12:00:10.999 ANR in Window{... com.solevision.app.MainActivity}.
Reason: Input dispatching timed out ... Waited 5005ms for MotionEvent.
```

This fired ~72 s after `ArFootSizingPlugin: registerWith called`. Root cause chain:
ARCore session creation (`checkAvailability` → remote lookup, `requestInstall`, `Session()` +
`configure()` + `resume()`) previously ran synchronously inside `getView()` on the **platform
thread** — the same thread that services every method-channel call — freezing input dispatch.

The current code has an async fix (`ArFootSizingView.kt:71-78,145-161`: session creation moved to
a background `sessionExecutor`). **However the log predates or overlaps that fix, so this must be
re-verified on device with a fresh build.** If an ANR still reproduces, look at
`ArFootSizingPlugin.sendEvent` posting to the UI thread while the platform thread is busy.

### 🔴 E2 — The §8 stall fallback can never fire (dead code)

`foot_ar_scan_screen.dart:71` defines `_stallTimeout = Duration(seconds: 12)`, but the scan
itself always ends at **4 s** (`scanDuration` in `ar_foot_measurement_pipeline.dart:516`,
timer armed at `foot_ar_scan_screen.dart:413`). By the time the 12 s stall timer fires
(`foot_ar_scan_screen.dart:421-429`) `_scanActive` is already `false`, so the guard
`if (mounted && _scanActive && _validDetectionsThisPass == 0)` never passes.

Consequence: users who can't get their foot detected wait through a failed 4-second pass and see
"We couldn't detect a foot…" instead of ever being offered the promised **"Switch to Guided Tap"**
fallback prompt mid-scan. (The fallback button does still appear afterwards via
`_validDetectionsThisPass == 0` in the error UI — but the stall coaching text path is dead.)
**Fix:** set `_stallTimeout` to something < `scanDuration` (e.g. 2–3 s), or drive it off sample count.

### 🔴 E3 — `startSession` is a stub that always returns `true`

`ArFootSizingPlugin.kt:63-66`:

```kotlin
"startSession" -> {
    result.success(true)
    sendEvent("session_started", emptyMap())
}
```

No session exists yet at this point — the real session is created asynchronously by the
PlatformView factory. Consequences:

1. `ArCoreChannel._sessionActive` becomes `true` even when ARCore is **unsupported / not
   installed / still initializing**. The screen's error handling for `started == false`
   (`foot_ar_scan_screen.dart:250-259`) is unreachable on Android.
2. Every subsequent `hitTest` / `acquireCameraFrame` call silently returns `null`
   (`currentView?...` when `currentView == null`), which manifests as the classic
   *"tracking green but 0 samples"* symptom instead of a clear error.
3. Real failures only surface later via `error` events — if the EventChannel listener isn't
   attached yet they're dropped entirely (see 🟡 E12).
4. The `session_started` event sent here duplicates the one from `createSession()`
   (`ArFootSizingView.kt:345`) and races the listener subscription.

**Fix:** make `startSession` return the actual session state (or have it trigger/await
`createSession()`), and surface unsupported-device reasons as a return value.

### 🔴 E4 — hitTest accepts hits on ANY plane, including vertical ones

`ArFootSizingView.kt:667-683` loops `frame.hitTest(px, py)` results and accepts the first trackable
that `is Plane && isPoseInPolygon(...)` — with no check for
`trackable.type == Plane.Type.HORIZONTAL_UPWARD_FACING`. The session configures
`PlaneFindingMode.HORIZONTAL_AND_VERTICAL` (`ArFootSizingView.kt:314`), so a ray that clips a wall
or a box side returns a point on a **vertical surface**. A heel/toe pair straddling floor + vertical
plane yields an inflated 3D distance → wrong length sample that can still pass the sanity bounds
(≤500 mm) and pollute the median. **Fix:** filter to horizontal-upward-facing planes in the loop.

### 🟠 E5 — ARCore availability retry loop has no delay

`ArFootSizingView.kt:248-268`: when `checkAvailability` returns `UNKNOWN_CHECKING`, the code
re-dispatches `createSession()` **immediately**, up to 5 times. The result is cached after the
first call, so all five retries complete within milliseconds on a slow connection and then emit
*"ARCore availability check timed out"* — a false failure. **Fix:** back off ~500 ms between
retries (e.g. `Handler.postDelayed` or `Thread.sleep` on the executor).

> **FIXED 2026-08-25** — the `UNKNOWN_CHECKING` branch now sleeps `AVAILABILITY_RETRY_DELAY_MS`
> (500 ms) on the session executor between retries, with `disposed` re-checks after the sleep.
> Shared by v1 and v2; needs on-device confirmation with a throttled connection.

### 🟠 E6 — `requestInstall` called off the main thread

`ArFootSizingView.kt:287` invokes `ArCoreApk.requestInstall(activity, true)` from the background
session executor. It launches a Play Store activity and is documented to require the calling
`Activity` context on the UI thread; behavior off-thread is undefined and can crash. With the
manifest already declaring `com.google.ar.core` = `required` (`AndroidManifest.xml:87`), Play
auto-installs anyway, making this call both risky and redundant.

### 🟠 E7 — Proportional width estimate recorded as if measured

`foot_ar_scan_screen.dart:562-568`: when the detector supplies no width points, width falls back
to `len * 0.38` and that fabricated number enters the sample set like a real measurement. The
0.38 ratio bakes in an average foot; for narrow/wide feet it skews the width median and therefore
the fit category ('narrow'/'standard'/'wide'). **Fix:** tag such samples and exclude them from the
width statistics (or record `captureWidthMeasured: false`).

> **FIXED 2026-08-25** — `MeasurementSample.widthMeasured` (default `true`) added to
> `ar_foot_measurement_pipeline.dart`; `combineGuidedSamples` computes width statistics from
> measured-only samples, falling back to all when too few measured widths exist. The v2
> controller tags estimate samples `widthMeasured: false`. Covered by pipeline + controller tests.
> The **v1** scan screen still records estimates untagged (v1 is frozen; use 2.0 for the fix).

### 🟠 E8 — Results screen mixes compensated and uncompensated values

`foot_ar_scan_screen.dart:884-913`: sizing uses **compensated** lengths (`leftLengthComp`, etc.)
to pick `euSize`/`usSize`, but the screen receives **raw uncompensated**
`leftResult?.lengthMm ?? 0` as `footLengthMm`/`footWidthMm`. For socks scans the displayed mm
values won't match the size recommendation math. Also:

- `lightingQuality: 0.9` is hardcoded (no lighting metric exists in this pipeline);
- `paperConfidence: overallConf` reuses the scan confidence under a paper-flow parameter name;
- if only one foot succeeded, `sizingLengthComp` of the failed foot contributes `0` via
  `applySockCompensation(0, …)` — harmless today because the longer-foot comparison still picks
  the valid foot, but fragile.

> **FIXED 2026-08-25** in v2 — `ScanResultsPayloadV2` exposes compensated values only; the
> results screen (`foot_scan_results_screen_v2.dart`) displays exactly what the sizing math
> consumed, no fake `lightingQuality`/`paperConfidence` fields. Raw lengths are retained solely
> as `leftRawLengthMm`/`rightRawLengthMm` for provenance. Covered by the E8 controller test.
> The **v1** screen still mixes compensated/uncompensated (v1 is frozen).

### 🟠 E9 — `distanceFromCamera` is actually distance-from-world-origin

`ArFootSizingView.kt:673-675` computes `sqrt(tx²+ty²+tz²)` of the **hit pose translation** —
distance from the AR world origin, not from the camera. Currently only informational, but any
future filtering "by camera distance" using this field would be wrong. Use
`camera.pose` subtraction or `hit.distanceCm()` equivalents.

### 🟡 E10 — Fabricated fallback plane masks real tracking failures

`ArFootSizingView.kt:600-614`: if iterating updated planes throws, the code invents a 3 m × 3 m
plane at the origin and reports `plane` detected, letting the UI show "ready". Real hitTests will
still fail against the nonexistent polygon, so the user sees "ready" + "0 samples" simultaneously —
the exact confusing state this pipeline spent several fix iterations on. Prefer surfacing the error.

> **FIXED 2026-08-25** — the catch block now only logs (`Plane detection failed: …`) and leaves
> `planeDetected = false`; no synthetic plane is fabricated. Shared by v1 and v2.

### 🟡 E11 — Side gating is not actually enforced by the runtime detector

`evaluateFootMask` documents (`foot_detector.dart:630-633`) that a segmentation mask cannot tell
left from right, and reports `footSide: preferSide` unconditionally. So `preferSide: 'left'`
gating in `_collectSample` is cosmetic: if both feet are visible, right-foot pixels can be
recorded into the left-foot sample set. Acceptable given the guided framing, but worth a UX guard
(one foot only) rather than trusting the gate.

### 🟡 E12 — Event delivery race on startup

`plugin.sendEvent` posts to the UI thread immediately (`ArFootSizingPlugin.kt:102-110`), while
Dart attaches the EventChannel listener only after `startSession()` returns
(`ar_core_channel.dart:236-238`). Early events (e.g. `session_started`, fast `error`s) can be
dropped before the broadcast stream has a subscriber. Low impact today; matters once E3 is fixed
and errors are expected through this channel.

### 🟡 E13 — Retry accumulates stale samples

`_retryScan` (`foot_ar_scan_screen.dart:698-705`) doesn't clear `_leftSamples`/`_rightSamples`;
a failed pass's partial samples blend into the next pass's statistics. Also, after the left-foot
side capture completes, `combineGuidedSamples(_leftSamples)` requires ≥ 5 quality samples
(`minValidSamples`) — a short second pass can retroactively fail an otherwise-good left scan.

> **FIXED 2026-08-25** in v2 — `ScanSessionController` collects each pass into a fresh
> `_passSamples` buffer merged into the foot's cumulative set only after the pass succeeds
> (`_mergePassIntoCurrentFoot`), and freezes each foot's result immediately upon combine
> (`_leftResult`/`_rightResult`), so a later failure can't retroactively invalidate a completed
> foot. Covered by dedicated E13/cancelCapture controller tests. The **v1** `_retryScan`
> still accumulates stale samples (v1 is frozen).

### 🟡 E14 — Misc small issues

- `assessTracking` is always called with a hardcoded `sessionDuration: const Duration(seconds: 3)`
  (`foot_ar_scan_screen.dart:352-355`), so the `< 5 s` message branch is dead and users always see
  the long-form "move your phone slowly" copy after 5+ seconds of searching. Cosmetic.
- `ArWorldPoint._sqrt` hand-rolls Newton's method to avoid a `dart:math` import
  (`ar_core_channel.dart:85-93`) — works, but `dart:math.sqrt` is simpler and exact.
- Double-dispose: screen `dispose()` calls `stopSession()` which calls
  `currentView?.dispose()`, and Flutter independently disposes the PlatformView. Guarded by null
  checks today, but order-dependent.
- `capture_ar_timing.sh` emits a literal `MARKER_START_$(date +%H%M%S)` marker (single quotes)
  and greps for `AR_TIMING` lines that the current auto-scan screen no longer prints (they moved
  to `[SAMPLE-DEBUG]` / `[SegDiag]` debugPrint tags), so the tool captures almost nothing useful
  for the auto-scan flow.
- Manifest `<uses-feature android:name="android.hardware.camera.ar" android:required="true"/>`
  hides the entire app on Play for non-ARCore devices. Intentional per AR docs, but consider
  `required="false"` + runtime gating since Guided Tap is a viable fallback.

### 🟠 E15 — Side guide rect extends past the visible crop band *(found on device, 2026-08-26)*

`kSideCaptureGuideRect` spans normalized x **0.15–0.85**, but the camera preview is drawn with a
center-crop fill (`scale = max(viewW/frameW, viewH/frameH)`), and a 4:3 ARCore frame on a
~19.5:9 phone leaves only x ≈ **0.19–0.81** of the frame visible. Consequences on the side
capture steps (both versions):

- The drawn guide box lands mostly **off-screen** (mapped to ≈ −90…1170 px on a 1080-wide
  display) — on v2 only the clipped `'SIDE VIEW'` label ("VIEW") poked in at the screen edge,
  looking like "the box disappeared".
- The 5-point area probes at the rect corners raycast through off-screen pixels, which can
  never reliably hit a plane polygon → area-lock stalls → capture blocked or the user aims
  blind and the pass fails with zero detections.
- It stayed invisible in v1/v2 tests because the fake ARCore returned hits for *any* probe
  coordinate — no crop geometry was simulated.

**v2 FIXED 2026-08-26** — `ScanSessionController.effectiveGuideRect` clamps the step's guide
rect into the computed visible band (from the reported view aspect + upright frame aspect);
area probes and the drawn frame both use it. The test fake now rejects out-of-band probes,
mirroring the native hitTest. **v1 still affected** (frozen): its side-step box/probes share
the same constants — v1 users on tall phones should use 2.0 for side captures.

---

## 4. Known-fixed items verified in code (do not regress)

- **ANR async session creation** (`ArFootSizingView.kt:145-161`) — verify against E1 on device.
- **hitTest normalized→viewport center-crop mapping** (`ArFootSizingView.kt:629-667`) mirrors the
  Dart overlay helper `mapNormalizedToView` (`foot_measurement_utils.dart:553-587`) — consistent.
- **NV21 conversion** handles arbitrary row/pixel strides and closes images properly
  (`ArFootSizingView.kt:377-437,541`).
- **ML Kit rotation** uses `(sensorOrientation(90°) − displayDegrees) % 360`, correctly yielding
  90° in portrait (`ArFootSizingView.kt:453-465`) — hardcoded sensor orientation is flagged for
  device verification.
- **Temporal gate + weighted quality score + guide-box clipping** in `evaluateFootMask` behave
  per spec and are covered by tests.

## 5. Recommended fix order

1. **E4** (vertical-plane hitTest) — silent measurement corruption; one-line type filter.
2. **E2** (stall timeout > scan duration) — dead fallback path; constant fix.
3. **E3 + E12** (honest `startSession`, reliable error events) — turns silent "0 samples" states
   into actionable errors.
4. **E1** — rebuild, rerun `adb logcat`, confirm the ANR is gone on a current build.
5. **E5/E6** (availability retry backoff, requestInstall threading) — robustness on first-run devices.
6. **E7/E8** (statistics hygiene, compensated values end-to-end) — accuracy polish.
7. **E10–E14** as follow-ups.

## 6. Reproduction & diagnostics cheat-sheet

```bash
# Device logs while scanning (auto-scan debug traces):
adb logcat -v threadtime | grep -E "SAMPLE-DEBUG|SegDiag|ArScan|ArFootSizing|ArCore"

# Key stage markers emitted by _collectSample():
#   frame=WxH rot=R → detect=OK/FAIL conf=…      (detection)
#   score=… (seg=…, shape=…, cont=…)             (weighted quality)
#   raycast=OK len=…mm wid=…mm                   (hitTest success)
#   raycast=REJECT (n/m points hit the floor)    ← E3/E4/E10 typically show here
#   sample=RECORDED total=N
```

Interpretation: detection OK + raycast REJECT ⇒ plane/hitTest-side problem (not ML); detection
FAIL with chip green ⇒ temporal-gate/score mismatch; app freeze on entry ⇒ revisit E1.
