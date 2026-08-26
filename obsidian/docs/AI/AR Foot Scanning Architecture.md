# AR Foot Measuring / Scanning — Architecture

> Context doc for AI assistants. Everything needed to understand, debug, or extend the AR foot sizing feature. Verified against code as of 2026-08-23.

## What it is

An in-app feature that measures the user's feet using the phone camera + ARCore, then recommends EU/US/UK shoe sizes. Results persist to Supabase (`foot_measurements` table) and drive size recommendations when shopping. Android-only (ARCore required, `com.google.ar.core` meta-data is `required` in the manifest).

Three measurement modes exist:
1. **AR Auto Scan** (`ar_auto_scan`) — live guided AR capture, the primary mode (this doc's focus)
2. **AR Guided Tap** (`ar_guided_tap`) — user taps heel/toe on the AR preview (fallback; also the manual-measure screen with `smartAssistEnabled`)
3. **Paper trace** (`paper`) — photo of the foot on A4/Letter paper, scale derived from known paper dimensions

## End-to-end flow

```
Entry points:
  • Foot Profile onboarding (foot_profile_onboarding_screen.dart)
  • Settings → foot profile (settings_screen.dart:73)
  • Customer home banner (widgets/customer_foot_profile_banner.dart)
        │
        ▼
FootInstructionsScreen ──(paper mode)──► FootCaptureScreen ──► FootProcessingScreen ──┐
        │ (AR modes)                                                                  │
        ▼                                                                             ▼
FootFloorDetectionScreen ───┬─(guidedTap)──► FootManualMeasureScreen ──► FootResultsScreen
                            └─(autoScan)───► FootArScanScreen ────────► FootResultsScreen
                                                                              │
                                                    FootMeasurementProvider.saveScan()
                                                                              ▼
                                                     Supabase `foot_measurements`
```

- `FootFloorDetectionScreen` (`foot_floor_detection_screen.dart`, replaces the old wall-calibration step): user just points the phone at the floor; once ARCore reports `TRACKING` **and** a horizontal-upward-facing plane has held continuously for an 800 ms debounce, the screen auto-captures a `FloorReference` (floor-plane normal + confirmed floor point from screen-center hitTest probes — guaranteed floor-only since the E4 fix) and **auto-advances** into the chosen AR mode with no user action. No confirm tap, no skip button. If no stable floor appears within 15 s, it fails gracefully with a retry action. Both AR modes accept the reference as an optional anchor param, but note: neither currently reads it (all measurement math anchors on live per-frame hitTests) — the parameter is plumbing for a future drift-correction layer.
- `FootArScanScreen` on success does `pushReplacement` to `FootResultsScreen`; stall/failure offers "Switch to Guided Tap" (`pushReplacement` to `FootManualMeasureScreen`, options carried over).
- `FootResultsScreen` shows measurements, recommended sizes + reasoning text, lets the user override the size (`user_adjusted_eu_size`), and saves via the provider.

## Native layer (Android, Kotlin)

Files: `android/app/src/main/kotlin/com/solevision/app/arfoot/ArFootSizingPlugin.kt`, `ArFootSizingView.kt`

- **Plugin** registers a PlatformView factory (viewType `ar_foot_scan`) plus:
  - MethodChannel `com.solevision/ar_foot_sizing` — methods: `startSession`, `stopSession`, `hitTest`, `hitTestBatch`, `acquireCameraFrame`, `getTrackingState`, `getFloorPlane`, `getFloorDistance`
  - EventChannel `com.solevision/ar_foot_sizing/events` — events: `session_started`, `tracking` (`state`), `plane`, `error` (`message`, `reason`)
- **ArFootSizingView** (PlatformView):
  - ARCore `Session` with `HORIZONTAL_AND_VERTICAL` plane finding, `LATEST_CAMERA_IMAGE` update mode, auto focus. Session creation runs on a background executor (ANR fix); GL renderer tolerates a null session.
  - Renders the camera feed via `GL_TEXTURE_EXTERNAL_OES` + shader pipeline. Correctness details: `setDisplayGeometry` on every layout change, `frame.transformDisplayUvCoords()` per frame, center-crop (fill) mapping — the Dart overlay math (`mapNormalizedToView` in `foot_measurement_utils.dart`) mirrors the native `hitTest` mapping exactly. **These two must stay in sync.**
  - Caches a CPU camera frame (ARCore's separate YUV_420_888 stream) throttled to 150ms, converted to **NV21** for ML Kit, with rotation computed as `(sensorOrientation(90) - displayRotation) % 360`. Frame is read on demand by Dart via `acquireCameraFrame`.
  - `hitTest(x, y)` takes normalized upright-frame coords, converts through the center-crop transform to viewport pixels, raycasts onto the floor plane, returns world-space point (meters) + distance. (Passing raw normalized coords here was the root cause of a past "foot detected but 0 samples" bug.)
  - Availability polling (up to 5 retries on `UNKNOWN_CHECKING`), `requestInstall` handling, error events with `reason`: `unsupported_device`, `user_opted_out`, `needs_install`, `timeout`.

## Dart bridge

`lib/services/ar_core_channel.dart` — singleton `ArCoreChannel` wrapping the channels. Key types: `ArTrackingState` (paused/limited/tracking), `ArWorldPoint` (x/y/z meters + distance), `ArCameraFrame` (NV21 bytes, width, height, rotationDegrees), `ArPlane`, `ArSessionEvent`. `hitTestBatch` exists to avoid per-point channel round-trips.

## Detection layer (on-device ML)

- `lib/utils/foot_detector.dart` — interface `FootDetector` + `FootDetectionResult` (heelPoint, toePoint, widthPoints, footSide, confidence, quality sub-scores) + `evaluateFootMask()` (the real detector math) + `TemporalFootGate`.
- Active detector: `lib/utils/mlkit_segmentation_foot_detector.dart` — **ML Kit Selfie Segmentation** (`google_mlkit_selfie_segmentation`, `SegmenterMode.single`, raw-size mask ~256×256). Chosen because ML Kit Pose is unreliable on tight foot-only crops. Point extraction is geometric, not landmark-based: PCA principal axis → heel/toe extremes, max perpendicular extent → widest pair.
- Legacy `mlkit_pose_foot_detector.dart` kept only for diagnostics; not instantiated.
- **Quality scoring** (replaced an older binary-gate chain): weighted sub-scores
  - segmentation confidence × 0.25
  - shape/elongation score × 0.35 (plateau 2.5–4.9 aspect ratio; hard bounds 1.8–6.0)
  - guide-box containment × 0.40 (≥50% overlap reference)
  - combined score ≥ `kSampleAcceptScore` (0.7) = foot detected
- **Mask sanity gates**: ≥200 foreground px, 1%–60% foreground fraction (rejects whole-frame blobs), elongation 1.8–6.0.
- **Guide boxes** (normalized upright-frame rects): front/top-down `Rect.fromLTRB(0.30, 0.15, 0.70, 0.70)`, side/profile `Rect.fromLTRB(0.15, 0.35, 0.85, 0.65)`.
- `TemporalFootGate`: requires several consecutive positive frames before "confirmed" (anti-flicker, prevents single lucky frames recording samples).

## Scan loop (`FootArScanScreen`, 1768 lines)

Guided two-angle capture per foot: **FRONT (top-down → width)** then **SIDE (profile → length)**; left foot then right. State machine `_guidanceState`: initializing → searching → ready → scanning → done/error.

Readiness = ARCore `TRACKING` **and** the guide-box region itself on a tracked plane (`_areaTracked`, verified by hit-testing box center + ≥2 corners every 500ms — no whole-room mapping needed).

Per sample (every `sampleIntervalMs = 200ms`, scan window `scanDuration = 4s`, guarded against overlapping runs by `_sampleInProgress`):
1. `acquireCameraFrame()` → NV21 frame
2. `detector.detect(...)` with `preferSide` (left/right) + `guideRect`
3. Combined quality score vs 0.7, gated through the temporal gate
4. `hitTestBatch` heel/toe/width points → 3D world points; length = heel↔toe distance ×1000 (mm); width = width-point pair distance, or `len × 0.38` proportional fallback
5. Sanity bounds (length 0–500mm, width 0–200mm) → append `MeasurementSample` with `captureAngle: 'front'|'side'`

Failure handling: zero confirmed detections in a pass → explicit "couldn't detect a foot" + retry; an attempts-based stall check (~10 attempted frames with zero confirmations, ≈2 s) coaches "Try Guided Tap" mid-pass. Live cm readout + debug overlay (heel/toe/width markers, toggleable bug icon) are built in; a verbose `_kSampleDebugLogging` flag emits `[SAMPLE-DEBUG]` stage traces (marked TEMP-DEBUG, to be removed).

## Statistical pipeline

`lib/utils/ar_foot_measurement_pipeline.dart`:

1. Quality filter: tracking quality ≥ 0.7 AND segmentation confidence ≥ 0.5
2. Split by capture angle — length from `side` samples, width from `front` samples (falls back to all samples if an angle has < 5)
3. IQR outlier filter (k = 1.5)
4. Median of filtered samples = final measurement
5. Confidence score = weighted: IQR spread 0.50 (IQR/12mm normalized, length-weighted 0.6/0.4) + sample count 0.25 (5→15+ samples) + relative spread 0.25 (IQR/length, 5% = 0)
6. Labels: ≥0.75 high, ≥0.45 medium, else low. Need ≥ `minValidSamples` (5) survivors or the pass fails.

`combineGuidedSamples()` is the two-angle version used by the AR screen; `combineSamples()` is the legacy/both-angle version.

## Sizing math

`lib/utils/foot_measurement_utils.dart` (pure functions):

- **EU size**: ISO Mondopoint chart (1 EU = 6.67mm), `footLengthMmToEuSize()` adds **+8mm comfort allowance** before lookup; chart spans EU 22–48 (133–313mm)
- **EU→US**: men/kids `EU − 33`, women `EU − 31.5` (TODO(human-review) on these offsets). **EU→UK**: `EU − 33.5`
- **Sock compensation**: if `foot_condition == 'socks'`, subtract 3.0mm length / 2.0mm width
- **Width category**: width/length ratio — <0.36 narrow, >0.42 wide, else standard (TODO(human-review) thresholds)
- **Sizing foot** = longer (compensated) foot; its length AND width are used together (never mixed across feet)
- **Recommendation reason**: human-readable text; near-boundary (<2mm) mentions the adjacent size
- **Plausibility tiers** (used by manual flow): hard reject length 12–34cm / width 4.5–15cm; soft-warn 15–30cm / 6–13.5cm
- **Coordinate mapping**: `mapNormalizedToView` / `mapViewToNormalized` — the single shared center-crop transform between normalized frame coords and the preview; mirrored natively in `ArFootSizingView.hitTest`

## Data model & persistence

- `lib/models/foot_measurement.dart` — `FootMeasurement`: raw mm per foot (length/width, left/right), compensated mm, EU/US/UK recommendations, `sizingFootSide`, `recommendedWidthCategory`, `measurementSource` (`ar_guided_tap | ar_auto_scan | paper`), `algorithmVersion` (currently `'v2'` — bump manually when formulas change), `sizeRecommendationReason`, `paperSizeUsed` (`ar | a4 | letter`), `footCondition`, `shoeCategory`, `userAdjustedEuSize`, confidence fields (IQR-based `lengthConfidenceLeft/Right`, `overallConfidenceScore`, `confidenceLevel`, sample counts). `effectiveEuSize` = user-adjusted ?? recommended.
- `lib/services/foot_measurement_service.dart` — Supabase CRUD on table **`foot_measurements`** (snake_case columns matching `toInsertMap()`); `getLatestMeasurement` orders by `scan_date desc limit 1`.
- `lib/providers/foot_measurement_provider.dart` — `ChangeNotifier` registered in `main.dart`; `loadLatest`, `saveScan`, `updateAdjustedSize`, `deleteMeasurement`. Consumed by the results screen; `recommendedEuSize`/`effectiveEuSize` are the app-facing values.

## Adjacent but separate

- `ar_fitting_screen.dart` (`ARVirtualFitScreen`) — AR virtual try-on of a product (uses `widgets/ar_view_placeholder.dart`), not part of the measuring pipeline.
- `foot_manual_measure_screen.dart` (1967 lines) — Guided Tap / smart-assist manual flow: tap heel/toe on the AR preview (`mapViewToNormalized` → `hitTest`), plausibility soft-warn confirmation, pushes `FootResultsScreen` with `measurementSource: 'ar_guided_tap'`.
- `foot_processing_screen.dart` / `foot_capture_screen.dart` — paper-trace path: camera capture gated on paper-confidence ≥ 0.8, then processing screen computes measurements via paper scale factor.

## Known fragile points / TODOs (from code comments)

- `sensorOrientation = 90` hardcoded in Kotlin — flagged for per-device verification
- EU→US women offset and width-ratio thresholds have `TODO(human-review)` markers
- `_kSampleDebugLogging = true` and the `[SAMPLE-DEBUG]` trace are TEMP-DEBUG, meant for removal after the 0-samples diagnosis
- The overlay↔native center-crop mapping is duplicated (Dart `mapNormalizedToView` vs Kotlin `hitTest`) — must be changed together
- Confidence thresholds (0.7 accept score, IQR/12mm, etc.) are explicitly "tunable once real ground-truth data comes in"
- `ar_core_channel.dart` has a hand-rolled Newton's-method `_sqrt` ("avoids dart:math import") — odd but intentional
