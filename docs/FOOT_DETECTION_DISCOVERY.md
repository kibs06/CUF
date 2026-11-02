# FOOT_DETECTION_DISCOVERY — Phase 0 (desk read, no behaviour change)

Date: 2026-10-30
Scope: answer MISSION Phase 0 questions from the repo as-found. No code changed.
Read with: `FOOT_DETECTION_MISSION.md`, `WEB_3D_FITTING_PROBLEM_BRIEF.md` (web analysis), `docs/AI/AR_TRY_ON_ARCHITECTURE.md`, `docs/AI/PRODUCT_3D_VIEW_ARCHITECTURE.md`.

## 0. TL;DR

- Flutter detection today is **ML Kit Selfie Segmentation (primary)** + **ML Kit Pose (legacy/diagnostics-only)**. No TFLite / ONNX / MediaPipe in the Flutter build. Mission §0 claim is correct.
- `FootDetector` interface **already exists** (`lib/utils/foot_detector.dart`, ~1032 lines) — do not recreate it in Phase 1. Build the TFLite adapter behind it later.
- There is **no `foot_lock.dart`** in the repo. Its jobs are already split between `TemporalFootGate` (Dart) + `FootPoseTracker` (native, one-euro + 0.7/0.45 hysteresis + 700 ms decay + 60 ms ease). Do not add a second lock authority.
- Rendering is **native Filament via `ArTryOnView`**, not widgets. Two modes, one class: `Mode.PREVIEW` (orbit, no camera) and `Mode.AR` (ARCore, floor/foot). Simulated `ARViewPlaceholder` is legacy fallback only.
- Camera frames for detection come from **ARCore sessions**, not the `camera` plugin. Try-on owns its camera; scan owns a different one. `acquireCameraFrame` duplication is recorded debt.
- Per-model `forwardAxis` / `defaultScale` are **web-proposal only** (`customer-portal/docs/BUILD_LENS.md`, `model-orientation-seed.sql`). Live `product_models` has `authored_length_mm` + `alignment_json.{yawOffsetDeg,heelOffsetMm}` — no axis/scale columns. Schema coordination needed before Phase 1 §7.
- Web extension constants (heel −16% / toe +28%, `f76c201`) are **not** in Flutter. Flutter uses `kProportionalFootWidthRatio = 0.38` + `authoredLengthMm` ratio scaling + `FootScaleCorrection` clamp 0.70–1.30. Do not port blindly.

---

## 1. Where the camera frame is received (package / format / rotation)

- **Try-on path (the one Phase 1 touches):**
  - `android/.../tryon/ArTryOnView.kt:625` — `footTracker = FootPoseTracker()`, render-loop cached CPU frame (`acquireCameraImage`, throttled **150 ms**), **copied** NV21 conversion with the scan's stride-safe code.
  - Served over `com.solevision/ar_try_on` as `acquireCameraFrame` (`lib/services/ar_try_on_channel.dart:~653`, `ArTryOnPlugin.kt:505+`). Payload shape reuses the scan's `ArCameraFrame` so only one frame vocabulary exists (explicit debt note in channel header).
  - `TryOnSessionController` loop: `kFootTrackInterval = 100 ms` (10 Hz) `Timer.periodic`, **overlap guard drops ticks** the detector can't keep up with, **stops after `kFootTrackFailureLimit = 5`** consecutive failures (`lib/providers/try_on/try_on_session_controller.dart`). Older roadmap notes say 200 ms — code today is 100 ms. No background isolate yet; detection runs on the main isolate.
- **Scan path (reference implementation):**
  - `lib/services/ar_core_channel.dart` (`com.solevision/ar_foot_sizing`): `ArCameraFrame` = NV21 bytes + sensor `width/height` + `rotationDegrees`.
  - `lib/utils/mlkit_input_helper.dart:19` — `buildNv21InputImage(nv21Bytes,width,height,rotationDegrees)` → `InputImage.fromBytes(format: NV21, bytesPerRow: width, rotation: rotationFromDegrees)`.
- **What is NOT used:** `camera: ^0.12.0+2` is in `pubspec.yaml` but not the detection source. No YUV/BGRA ImageReader plumbing in Dart; NV21 only. Rotation is degrees → `InputImageRotation` (0/90/180/270).

## 2. Where ML Kit Segmentation and Pose are called, how results reach the overlay

- **Active:** `lib/utils/mlkit_segmentation_foot_detector.dart:30` — `MlKitSegmentationFootDetector implements FootDetector`, `SelfieSegmenter(mode: single, enableRawSizeMask: true)` (~256×256 raw mask, ~65K confidences vs 307K rescaled). Called with NV21 `InputImage`, returns via `evaluateFootMask()` (PCA principal axis → heel/toe extremes, max perpendicular → widest pair).
- **Gates inside `lib/utils/foot_detector.dart`:** `minFootDetectionConfidence = 0.5`, `minFootMaskPixels = 200`, foreground fraction 1%–60% (rejects whole-frame walls/carpets), elongation 1.8–6.0 (rejects hands/blobs/cables), `TemporalFootGate(confirmAfter/clearAfter)` consecutive-positive logic.
- **Legacy:** `lib/utils/mlkit_pose_foot_detector.dart:34` — `MlKitPoseFootDetector` (`PoseDetectorOptions(base, single)`, `leftHeel/rightHeel + leftFootIndex/rightFootIndex`). Header says tight foot-only crops fail; kept for diagnostics, **not instantiated** by `scan_session_controller`, `auto_scan_controller`, `guided_tap_controller`, or `try_on_session_controller` (all import the segmentation detector).
- **Mapping:** `lib/utils/foot_pose.dart:~40` — `footPoseFromDetection()` pure function. Requires `footDetected + heel + toe`; width optional with `kProportionalFootWidthRatio = 0.38` fallback; `confidence = qualityScore` (the number native lock compares against 0.7/0.45).
- **Crossing:** `FootPoseFrame{heelUv,toeUv,widthUv[2],confidence,footSide}` → `setFootPose` + `setFootMask` (32×32 box-averaged from `lib/utils/foot_mask.dart`, own try/catch, null = no occlusion this frame) → `FootPoseTracker.Observation` (`ArTryOnPlugin.kt:597`, `ArTryOnView.kt:1202`). `footLock` events return; Dart mirrors `locked/lost`, never re-derives hysteresis.

## 3. How the shoe is rendered over the camera preview

- **Native, Filament — not Flutter widgets.** `ArTryOnView.kt` (~2100+ lines, `com.solevision.app.tryon`):
  - `Mode.PREVIEW`: Filament 1.72.1 Engine/Renderer/Scene/View + glTF `AssetLoader` + `UbershaderProvider` + Choreographer orbit/idle spin. No camera, no ARCore session.
  - `Mode.AR`: ARCore session + sun + ambient estimate, floor placement, `placeShoe(x,y)` hitTest vs horizontal-upward planes only, centre-crop UV→viewport mapping.
  - Dart mount: `ShoePreview3D` (`lib/widgets/shoe_preview_3d.dart`, 1727 lines) → `AndroidView(viewType: com.solevision/shoe_preview/view)`; full-screen viewer `ShoePreviewScreen` (`lib/screens/shared/shoe_preview_screen.dart`); AR push `ARVirtualFitScreen` (`lib/screens/customer/ar_fitting_screen.dart`, 1346 lines) with `paused` flag stopping preview engine while AR is on top (two live Filament engines = frame-rate loss).
- **Placement math:** heel-anchored, yaw along foot, **yaw-only** (sole stays flat, V3 rule). World basis `{heel, forward, up}` from two floor hitTests; `up = +Y`. `authoredLengthMm` ratio-corrects asset bounding box (mm vs m models render same size); `yawOffsetDeg` from `alignment_json` (mirrored sign when shoe mirrored). Native `setModel` parked/replayed (F18) — model sent before view exists.
- **Simulated AR** (`ARViewPlaceholder` scan line / corner brackets / pulse / particles) is legacy fallback when `tryOnEnabled=false` or no native plugin (`MissingPluginException` → `TryOnMode.simulated`).
- **Web (for contrast):** `customer-portal/` draws same `product_models.active` row via `<model-viewer>`, YOLO `foot-v1.onnx` + Pose-Landmarker fallback, `footTryOn.js` coast + EMA smoothing. Not Flutter.

## 4. Existing smoothing, coasting, manual placement

- **Native smoothing (`FootPoseTracker.kt:66-525`, pure Kotlin, JVM-tested):** one-euro filter per channel (heel x/y/z, forward x/z, quality, measuredLength); 30 cm drift re-anchor (filters reset, lock kept); lock hysteresis **enter 0.7 / leave 0.45** with `footLock` edges; **700 ms staleness decay** (stopped publisher loses lock, never freezes shoe); **60 ms eased interpolation** at display rate (5 Hz observations drawn at 30–60 fps).
- **Dart gating (no second smoother):** `TemporalFootGate` consecutive positives; `ar_try_on_channel.dart:227` states "Dart publishes observations, not decisions — no smoothing". Deliberate: second hysteresis would disagree and flicker.
- **Coasting:** tracker keeps drawing + measured length after lock drops (shoe that detaches/resizes at 0.44 is worse than slightly stale foot). Mask shares `STALE_MS = 700 ms`. Web `footTryOn.js:28` has parallel coast timeout.
- **Manual fallback:** `placeShoe(x,y)` tap → floor hitTest; `autoPlaceIfNeeded` yields to live anchor once present; `try_on_coach.dart` offer after 15 s without lock (`kFootManualOfferAfter`) or loop stopped after 5 failures → `Place it myself` button (`try_on_coach_card.dart`) → `dismissManualOffer`, next tap is V3.4 native path; `setTryOnMode('floor')` escape hatch. Rotation locked portrait in `initState`; backgrounding resumes via `pausedForSurfaceDetach` + `setAppForeground` (`WidgetsBindingObserver`).

## 5. Per-model data (forwardAxis / defaultScale / anchors?)

- **Live `product_models` (Supabase `CUF`, 4 rows):** `id, storage_path, sha256, status (draft/active/rejected), version, triangle_count, authored_length_mm (EXTERNAL heel-toe, drives render scale), alignment_json.{yawOffsetDeg, heelOffsetMm}`. See `ArTryOnView.kt:193-202`, `ArTryOnPlugin.kt:769-770`, `shoe_model_resolver_test.dart`, `admin-portal/.../modelPublish.js:389-467`.
- **Internal vs external length split (do not mix):** `product_models.authored_length_mm` (external, render) vs `products.last_length_mm` (internal last, fit verdict). Leather external is 8–15 mm longer; mixing hands every customer a size too generous (`CHANGELOG:287`).
- **Web proposal, NOT in mobile schema:** `customer-portal/docs/BUILD_LENS.md:33` + `model-orientation-seed.sql` propose `product_models(forward_axis, default_scale, storage_path)` as source of truth, one Lens per model. Mobile has no `forward_axis` / `default_scale` columns today. Coordinate with web team before shared migration.
- **QA seam:** `TRY_ON_QA_MODEL=assets/models/qa_partner_shoe_v1.glb` (1.66 MB, 49,954 tris, 11/11 contract) + `TRY_ON_PLACEHOLDER_MODEL`; per-asset row numbers carried so QA comparison is like-for-like. Production path is `SupabaseShoeModelDataSource` (prefetch + sha verify to disk, gate `resolveShoePreview` requires bytes on disk).

## 6. Android / iOS minimums, Flutter / Dart

- **Dart:** `pubspec.yaml: environment.sdk ^3.12.1` (Flutter stable pinned to that Dart line; run `flutter --version` on build machine to record exact Flutter revision — not captured from desk).
- **Android:** `android/app/build.gradle`: `minSdkVersion 24` (ARCore floor) / `compileSdk 36` / `targetSdk 36`, `ndkVersion flutter.ndkVersion`, Java 21 + Kotlin `jvmTarget 21`, `multiDex`, ARCore requires GLES 3.0+. Filament refuses below `FEATURE_LEVEL_2` (SIGSEGV class, F22/F24); `SHOE_PREVIEW_ALLOW_LEVEL1` + `LOWER_ENGINE_TO_LEVEL1` double-locked to debuggable builds only.
- **iOS:** no `ios/Podfile` in repo (generated on `flutter build`). `ios/Runner/GeneratedPluginRegistrant.m` lists 28 plugins incl `google_mlkit_{commons,pose_detection,selfie_segmentation,text_recognition}` — iOS support present via pods, but version resolution + privacy labels (`NSCameraUsageDescription`, ML Kit) unresolved until first `pod install` / App Store readiness pass (`docs/RoadMap/IOS_APP_STORE_READINESS.md:B3,B7`). AR try-on renderer is **Android-only** (ARCore); iOS degrades to simulated screen by design.
- **TFLite plugin constraint for Phase 2:** must support Android API 24+ and iOS (with privacy manifest), maintained `tflite_flutter` or equivalent; verify before adding. Keep ML Kit Pose fallback if model fails to load.

## 7. Conflicts with MISSION as-written (trust repo)

1. "Add `FootDetector` interface" — already exists. Phase 1 should **extend, not create** (add TFLite adapter + rate/isolate changes only).
2. "`foot_lock.dart` (permissive, sticky)" — no such file in repo. Native `FootPoseTracker` + `TemporalFootGate` already implement acquire/coast/reset/jump-reject/guide-gating. Importing a second lock risks disagreement; adapt `try_on_coach` thresholds instead if more permissive lock wanted.
3. Extension constants 16%/28% — Flutter has no such constants. Equivalent knobs are `kProportionalFootWidthRatio`, `authoredLengthMm`, `FootScaleCorrection` clamp. Measure toe-tip error on-device before adopting web numbers.
4. "Detection at 5–10 Hz on background isolate" — current 10 Hz `Timer.periodic` on main isolate with overlap-drop. Isolate + zero-copy frame handoff is the real Phase 1 work (frame conversion cost is the lag risk).
5. "Per-model `forwardAxis`/`defaultScale`" — web-side proposal; mobile migration not written. Do not assume columns exist.
6. Doc location: MISSION asks `docs/FOOT_DETECTION_DISCOVERY.md`; earlier thread asked `docs/AI/`. This file lives at `docs/FOOT_DETECTION_DISCOVERY.md` per MISSION §6. Consider a stub link in `docs/AI/` if needed.

## 8. Recommended Phase 1 order (no commitment)

1. Record `flutter --version` + `pod install` result (fills §6 gaps).
2. Isolate + rate-limit detection (100 ms → 100–200 ms tunable, drop-not-queue, no full-frame copy).
3. Guide-rect overlay + optional shoe seeding at outline (uses existing `guideRect` + `autoPlaceIfNeeded`).
4. Named extension/width constants review vs on-device toe error (don't hardcode web numbers).
5. `FootLock` behaviour via existing tracker thresholds (tune 0.7/0.45, 700 ms, 60 ms only with V4.9 numbers), unit tests for acquire/coast/reset/jump/guide.
6. Re-measure FPS on mid-range Android; keep manual place/drag + Beta disclaimer.

---
*Generated from desk read only. No device run, no FPS/latency numbers. Next step per MISSION: confirm labeling spec before any Phase 2 training.*
