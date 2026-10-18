# AR Shoe Try-On — changes since Day 4 (V4.13 → V4.21)

**Scope:** everything after the committed `98e7f6b` (Oct 13, "keep the shoe on the foot
between detector frames", which closed the Day-4 work). Covers one committed follow-up
era plus the current uncommitted batch. Status of each item is marked
**[committed]** or **[uncommitted]** as of Oct 16, 2026.

**How to read the V-tags:** the code marks each generation `V4.13` … `V4.21` in KDoc.
The tags are chronological — each version is a layer on the previous one, not a rewrite.

---

## 1. Committed baseline: `98e7f6b` (Oct 13) [committed]

"Keep the AR try-on's shoe on the foot between detector frames, and reject foot reads
that are not a foot." 5 files, +800/−25.

- **New `FootFlow.kt`** — optical-flow carry of heel/toe through the camera image between
  detector results (~5 Hz), so the shoe moves with the foot instead of waiting for the
  next detection. Pinned by `FootFlowTest.kt` (97 lines, new).
- **Foot-plausibility gates** in `ArTryOnView` — samples outside a plausible foot length
  or with a large heel jump are dropped, so one bad depth read cannot mis-size the shoe.
- **Camera permission first** — the try-on asks for camera permission before starting.
- Touched: `ArCameraFeed.kt`, `ArTryOnView.kt`, `FootFlow.kt` (+ test),
  `lib/screens/customer/ar_fitting_screen.dart`.

---

## 2. Detection dots — "is it seeing my foot" (V4.13) [uncommitted]

**New `DetectionDots.kt`** (pure Kotlin, no Android imports — projection math pinned on the
JVM) + **`DetectionDotsTest.kt`** (new). ~540 lines of new logic inside `ArTryOnView`
(`updateDetectionDots`, `placeDetectionDots`, `makeDetectionDot`).

- Two small white heel/toe anchor overlays, **AR mode only**, drawn on **every accepted
  detector observation — before any lock, floor plane, or shoe**. The answer to "is it
  detecting my foot" is no longer the shoe.
- Plain Android overlay views, deliberately **not** Filament geometry: a dot needs no
  material, so it cannot trip the ubershader-mismatch abort (F16).
- **Depth-first 3D position, floor never consulted:** `depthWorldPoint` measures the
  foot's own surface, with a camera-ray fallback at `FALLBACK_DISTANCE_M = 0.6 m`
  (`rayPointAtDistance` — direction exact from shared intrinsics/texture mapping, only
  distance assumed). Dots therefore show exactly where the shoe does not: foot on a bed,
  no tracked plane yet, young session.
- Re-projection throttled to `RECOMPUTE_MS = 100 ms` (depth images are ~30 Hz; faster is
  waste). Held-while-dimmed at `HELD_ALPHA = 0.45` so a remembered anchor cannot be read
  as a live measurement.
- The fix is kept in **upright-image UV**, refreshed by every observation, so dots persist
  across the ~200 ms between detections.

## 3. Presence ring — "a foot is here" (V4.15) [uncommitted]

For gate-confirmed but unmeasurable detections (foot at an angle, sock, occluded toe):
a ring at the mask centroid, visually distinct from the solid anchor dots.

- Native: `setFootPresence(u, v, confidence)` / `clearFootPresence()` posted to the render
  thread like `setFootPose` (latest only); `updatePresenceDot` draws via the same
  depth-then-ray path with the same no-floor guarantee. Hidden whenever pose dots are
  visible (a measurement supersedes a sighting); never feeds tracker, scale, or snapshot.
- Plugin (`ArTryOnPlugin`): new `setFootPresence` channel branch.
- Channel (`ar_try_on_channel.dart`): new **`FootPresenceFrame`** (`focusUv`, `confidence`).
- Dart detector (`foot_mask.dart`): `kFocusThreshold = 128`, `kFocusMinPixels = 10` focus
  computation behind presence.
- Session controller: presence refresh on every ~10th 100 ms tick
  (`kFootTrackInterval`, `kPresenceRefreshTicks`).
- Timing: `PRESENCE_STALE_MS = 1500 ms` (past Dart's ~1 Hz refresh with margin — a live
  ring never flickers, a stalled loop lets go).
- Tests: new `V4.15: presence without measurement` group in
  `test/providers/try_on_foot_track_test.dart` (+~120 lines); `foot_mask_test.dart` +61.

## 4. Detection-driven shoe — a shoe with no floor or lock (V4.16) [uncommitted]

`DetectionDots.detectionPlacement` + `updateDetectionDrivenShoe` in the view: when the
tracker has no anchor, the last dots fix (same depth-first worlds the dots draw) becomes
the shoe's heel position and yaw, sized through **`effectiveScaleFor` — the same pipeline
the tracked anchor uses**, so the shoe does not change size at tracker handover. A
tracked anchor always wins (early return). Foot-length trust band shared with the gates.

## 5. One hold rule for dots and shoe (V4.17) [uncommitted]

A gap in the pose stream is not the foot leaving (detector runs a few times a second;
its gate needs consecutive frames to change its mind).

- `DetectionDots.holdState(nowMs, lastPoseMs, lastPresenceMs, hasFix)` → `LIVE` / `COAST`
  / `LOST`. Pure, total, per-frame on two monotonic timestamps; both bounds inclusive;
  liveness is the ring's own expiry. **One rule decides for dots *and* detection-placed
  shoe**, so a hold cannot begin for one and end for the other.
- Windows: `STALE_MS = 1000` (live), `COAST_MS = 3000` (still seen), `SILENT_COAST_MS =
  1500` (nothing arriving — deliberately the ring's own window, so held anchors and ring
  let go together).
- **A hold without a track does not re-read depth** (a UV the foot has left measures
  whatever is behind it — usually the floor). Without carry, held world points stay fixed
  (camera still followed correctly); with carry (§7), the tracked UVs are re-read.

## 6. Which shoe — side-aware mirroring (V4.18) [uncommitted]

The customer's detected foot is the authority; a product usually ships one side's asset.

- `FootPoseTracker.observeSide` / `applySide`: first side taken at once, a **change needs
  `SIDE_CHANGE_CONFIRM = 3` agreeing frames**; unsure frames are not an opinion; `reset`
  forgets the side with everything else; the lock event carries the confirmed side.
- View: `updateMirroring` — equal side draws as authored, different side mirrors via
  `mirrorSign()` in the scale matrix; **null (unknown) is never rendered as a mirror**.
  `TryOnModelSpec` gains the authored side (`'left'`/`'right'`).
- Tests: 6 new side cases in `FootPoseTrackerTest.kt` (+115 lines).

## 7. Held-carry clock (V4.19) [uncommitted]

`DetectionDots.heldCarryDue` — only `COAST` fixes may be moved by the flow carry, throttled
by the same `RECOMPUTE_MS` (each refresh is two depth-image acquires). `lastHeldCarryMs`
throttles the depth re-read that moves held anchors; one relay latch keeps
"carrying held anchors" to one line per episode. Neither touches the detection clock —
a tracked patch can move the shoe but never extend its life.

## 8. Still capture — "Capture to fit" (snapshot path) [uncommitted]

The live mode is yaw-only (no reliable toe height). A still capture measures both
endpoints from depth, so tilt is readable.

- **New `FootSnapshot.kt`** (pure, JVM-pinned) + **`FootSnapshotTest.kt`** (new):
  `pose()` reads yaw (`atan2(dx, dz)`, matching `FootPoseTracker`), pitch (positive =
  toe higher), and full-3D heel→toe length (what the shoe is sized to — floor-plane
  distance would undersize a tilted foot by `cos(pitch)`). Null = "do not capture",
  never clamped. Length gate `0.20–0.34 m` mirrors the live gate. Streak acceptance:
  `REQUIRED_SAMPLES = 5` consecutive samples within `YAW_TOLERANCE_DEG = 8°` and
  `LENGTH_TOLERANCE_M = 10 mm` (also catches heel/toe label flips).
- Channel: new **`TryOnFootSnapshotEvent`** (once per AR session).
- **New `lib/utils/shoe_fit_view.dart`** (+ `shoe_fit_view_test.dart`): the one place
  turning the native pose into `<model-viewer>` attributes — yaw onto floor-plane
  direction, top-down camera (`theta = yaw + 180`, 2° off-pole so up is never
  degenerate), scale from measured vs authored length (pitch read but not applied — a top
  view hides it). Pure Dart, no Flutter imports.
- UI: `ar_fitting_screen.dart` gains capture mode (screen closes itself once the viewer
  has the snapshot); `shoe_preview_screen.dart` + `sole_ar_pill.dart` surface it.
- Tests: snapshot groups in `try_on_foot_track_test.dart` (+47), channel tests +69.

## 9. Supporting changes [uncommitted]

- `DepthMath.kt`: new **`planarFootAxisMeters`** (+10) with `DepthMathTest` coverage (+8).
- `ArCameraFeed.kt`: reveal-report cap (`MAX_REVEAL_REPORTS = 10`), post-resume texture
  bind hardening.
- `auto_scan_controller.dart` (+12), `diag_logger.dart` (+29): logging/coordination for
  the new paths.
- `product_detail_shoe_preview_contract_test.dart` (+15): contract kept green through the
  preview-screen changes.

## 10. On-device probe diagnostics (V4.20 → V4.21) [uncommitted, TEMP-DIAG — remove before release]

The projection check was failing ~1,400 px on-device every session while both sides
looked right individually, so the view carries a temporary `dots-probe` log line:

- **V4.20:** raw detector UV → `transformCoordinates2d` texture coords. Hand-verified
  against 7 samples: a perfect uniform rotate-crop (`tex.u = y/2340` to 3 decimals) —
  the transform is geometrically principled, exonerated as "garbage".
- **V4.21:** adds the CPU-image side — raw `uv` plus ARCore's `IMAGE_PIXELS` answer for
  the same point, with image intrinsics (focal, principal, dimensions), camera pose
  translation, tracking state, and hit counts. No intrinsics/pose/projection in the
  comparison path.
- **Pending read (needs the 30-second on-device retest):** convert logged `uv` to sensor
  pixels under both rotation hypotheses and match against `imgpx`. A match = small
  mapping-direction fix; a miss = session-geometry fault → default-config A/B.
- **Do not ship:** both probe blocks are marked `TEMP-DIAG` in source; delete them (and
  the four QA dart-defines used to build the probe APK) as part of whichever fix lands.

---

## 11. Known issues & watch list (persistent bugs needing an eye)

- **🟡 Projection fix awaiting device proof (V4.23, §13).** Cause found by code-space analysis (texture-space coords paired with CPU-image intrinsics — mapping-direction fault, confirmed); QA APK 1.0.56 carries the IMAGE_PIXELS fix. Closes only when a device session shows `projection-ok` + tape-true lengths.
- **🔴 TEMP-DIAG probes still in source (OPEN).** Both `dots-probe` blocks + the four QA dart-defines must be deleted as part of the fix — the release checklist greps for them.
- **🟡 Snapshot length gate is a copy, not a reference.** `FootSnapshot.MIN/MAX_LENGTH_M` duplicates the live gate's `0.20–0.34 m` by hand; nothing enforces they stay equal — a change to either must be made to both.
- **🟡 Capture ignores pitch and toe allowance.** `shoe_fit_view.dart` reads pitch but never applies it (top view hides it, viewer has no tilt control), and the shoe is scaled heel-to-toe with no toe allowance modelled — expect slightly short-looking fits on tilted feet.
- **🟡 Ray fallback is an assumed depth.** Direction exact, distance fixed at 0.6 m — fine for an indicator, never a measurement; it must stay out of tracker/scale/snapshot (it does today).
- **🟡 Holds don't track the foot's own movement.** During a COAST gap without carry, world points sit still — correct per the hold contract, but fast foot motion in the gap reads as lag on catch-up.
- **🟢 Floor hit-test still gates the shoe.** Dots and ring show without a plane; the tracked shoe does not. Beds, boxes and plane-less sessions get indicators but no shoe — known, accepted, documented in §2/§4.
- **🟢 Ubershader abort (F16) constrains all overlays.** Anything drawn as Filament geometry needs a matching material; keep future indicators as views or budget a material audit.

---

## 12. Camera zoom slider (V4.22) [uncommitted]

The feed arrives looking ~2x (ARCore centre-crops the wide sensor into the tall screen),
and a blurry crop at 1x reads as a broken camera next to the camera app at 0.9x. The
fitting screen gains a zoom bar (0.7x–2.0x slider + readout, reset to 1x whenever the view
goes away); the coaching column lifts above it.

- **View-only by construction:** the background quad and the render projection narrow by
  the same factor (`DetectionDots.applyZoomToProjection` on the Filament custom projection,
  every dots/ring/readout projection, and tap/auto-place rays), while detection, tracking,
  hit-tests and depth stay in unzoomed world space — the shoe, dots, ring and mask stay
  glued at any zoom. Pure zoom math (`coerceCameraZoom`, UV crop, letterbox band, screen
  mapping) lives in `DetectionDots` and is JVM-pinned in `DetectionDotsTest`.
- **Two paths, one factor:** `>= 1x` crops the sampled texture region toward the centre
  (quad fullscreen); below 1x only u widens about the centre by `1/zoom` while v keeps the
  full texture height (`applyZoomOutToUvs`) — the 1x crop already spans the full height, so
  a uniform expansion would overflow (the first build sampled the same width × a shorter
  height; the second hardcoded the u axis and stretched under rotation — both fixed after
  on-device reports; the axis is now chosen by span, never assumed). The quad shrinks to a centred
  band with thin dark bars (`updateZoomGeometry` from `zoomBandRect`). The probe
  self-check maps its reference into zoomed space, so it stays meaningful off 1x.
- Channel: `setCameraZoom` (Dart → plugin → view, torch-pattern, dropped before the view
  exists, garbage coerced to 1x); status line carries `zoom=` for screenshot diagnosis.
- **Not yet run:** full JVM + Flutter suites after this batch; on-device zoom + lock agreement
  (dots/ring/shoe at 0.7x and 2.0x) still owed alongside the §10 retest.

---

## File inventory

| File | Change |
|---|---|
| `android/…/tryon/ArTryOnView.kt` | +961 — dots, ring, detection shoe, hold, mirror, carry, snapshot wiring, probes, camera zoom (V4.22) |
| `android/…/tryon/DetectionDots.kt` | **new** (270) — hold rule, carry rule, placement, projection helpers, zoom math (V4.22) |
| `android/…/tryon/FootSnapshot.kt` | **new** (190) — still-capture pose + streak acceptance |
| `android/…/tryon/FootPoseTracker.kt` | +68 — side observation/confirmation |
| `android/…/tryon/ArTryOnPlugin.kt` | +28 — presence channel branch, `setCameraZoom` (V4.22) |
| `android/…/tryon/ArCameraFeed.kt` | +22/− — reveal cap, texture-bind hardening, zoom crop/letterbox (V4.22) |
| `android/…/arfoot/DepthMath.kt` | +10 — `planarFootAxisMeters` |
| `android/…/tryon/DetectionDotsTest.kt` | **new** — projection/matrix/placement/zoom pins |
| `android/…/tryon/FootSnapshotTest.kt` | **new** — pose + streak pins |
| `android/…/tryon/FootPoseTrackerTest.kt` | +115 — side-confirmation cases |
| `android/…/arfoot/DepthMathTest.kt` | +8 |
| `lib/services/ar_try_on_channel.dart` | +77 — `FootPresenceFrame`, `TryOnFootSnapshotEvent`, model side, `setCameraZoom` (V4.22) |
| `lib/providers/try_on/try_on_session_controller.dart` | +122 — presence ticks, snapshot handling |
| `lib/utils/foot_mask.dart` | +46 — focus/presence computation |
| `lib/utils/shoe_fit_view.dart` | **new** — native pose → `<model-viewer>` mapping |
| `lib/screens/customer/ar_fitting_screen.dart` | +19 — capture mode, zoom bar (V4.22) |
| `lib/screens/shared/shoe_preview_screen.dart` | +48 — capture surfacing |
| `lib/widgets/sole_ar_pill.dart` | +42 |
| `test/providers/try_on_foot_track_test.dart` | +211 — presence + snapshot groups |
| `test/services/ar_try_on_channel_test.dart` | +69 |
| `test/utils/foot_mask_test.dart` | +61 |
| `test/utils/shoe_fit_view_test.dart` | **new** |

## 13. V4.23 — rays unproject IMAGE_PIXELS, not texture × dims [uncommitted]

The §10 probe read is answered — by code-space analysis, not a retest. The V4.20 probe
proved TEXTURE_NORMALIZED is *rotated* vs the view (`tex.u` tracks view-y); the intrinsics
(`focalLength`, `principalPoint`, `imageDimensions`) describe the CPU image
(IMAGE_PIXELS space). Both ray paths paired texture-space coords with CPU-image
intrinsics:

- `ArTryOnView.rayPointAtDistance`: `texturePoint × dims` → `rayDirection`.
- `ArTryOnView.depthWorldPoint`: `texturePoint × dims` → `unprojectToCameraSpace`.
- `ArFootSizingView.depthHitTest` (scan path): same `texturePoint × dims` → unproject.

Every ray was therefore rotated ~90° — the 400–2100 px dots-check mismatch, the inflated
246–338 mm lengths, the misplaced shoe. The V4.20 comment's "ruled out by construction"
conclusion was wrong: both check pixels derived from the same (u, v), but the ray side
translated it through the wrong space.

Fix: VIEW → IMAGE_PIXELS via `transformCoordinates2d` (ARCore's own "which sensor pixel
sits under this view pixel"), fed straight to the intrinsics. Depth-image *sampling* keeps
texture space (both textures span the same sensor frame — same space, no rotation). The
self-check stays a genuine cross-validation (independent transform vs projection matrix),
not a tautology. Stale comments (probe conclusion, self-check meaning, ray docstring)
corrected. TEMP-DIAG probes kept for the verification run; the release checklist still
greps them out.

- **Passed:** `:app:compileDebugKotlin` clean (`--rerun-tasks`, no new warnings);
  `:app:testDebugUnitTest` **135 pass / 0 fail** (JDK 21 — the default JDK 17 fails
  `compileDebugJavaWithJavac` with `invalid source release: 21`, pre-existing env issue);
  QA APK 1.0.56+64 built (`BUILD_EXIT=0`) and installed (`Success`, `versionName=1.0.56`).
- **Blocked on device:** one HABÍ session — dots-check `projection-ok` (was 400–2100 px),
  `len=` near tape measure (was 246–338 mm), lock holds past 10 s.
- **Before release:** remove both `TEMP-DIAG` probe blocks; re-run the full JVM + Flutter
  suites after the fix; confirm dots/ring/shoe agree on one hold (§5) on-device.

## Verification status

- **Passed:** probe-APK debug build (`BUILD_EXIT=0`, zero error lines); reinstall
  (`Success`); transform hand-check (7 samples, exact rotate-crop); Dart publish-path
  read (points pass through unrotated, documented upright space); V4.23 fix compile +
  135 JVM tests green + QA APK 1.0.56 installed.
- **Blocked on device:** the HABÍ verification session (§13), which decides whether the
  rotation fix also settles lock stability and the render-loop crash theory.
- **Before release:** remove both `TEMP-DIAG` probe blocks; re-run the full JVM + Flutter
  suites after the fix; confirm dots/ring/shoe agree on one hold (§5) on-device.
