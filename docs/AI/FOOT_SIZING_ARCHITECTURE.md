# Foot Sizing Architecture

> **Purpose**: AR-based and paper-based foot measurement system that recommends EU/US/UK shoe sizes.
> **Stack**: Flutter + ARCore (Android) + ML Kit (segmentation & pose) + Supabase (persistence).

---

## 1. High-Level Flow

```
User taps "Get Your Foot Size" (Settings → Account)
  → FootInstructionsScreen (choose scan mode + options)
    → ┌─ Live AR Scan ─────────────────────────────────────────────┐
      │  FootManualMeasureScreen                                    │
      │  (tap-to-place points, ARCore raycasting, smart-assist)     │
      │    → FootResultsScreen (show size, save to profile)         │
      └─────────────────────────────────────────────────────────────┘
    → ┌─ Paper Scan ───────────────────────────────────────────────┐
      │  FootCaptureScreen (camera + paper detection)               │
      │    → FootProcessingScreen (CV pipeline)                     │
      │      → FootResultsScreen (show size, save to profile)       │
      └─────────────────────────────────────────────────────────────┘
```

### Post-Signup Onboarding Variant

`FootProfileOnboardingScreen` is shown **once** after customer sign-up. Three paths:
1. **Scan with AR** (primary, accent card) → pushes `FootInstructionsScreen`
2. **Enter size manually** (secondary, outline card) → EU size + width picker, no scan
3. **Skip for now** (tertiary text button) → persists `foot_profile_source = 'skipped'`

---

## 2. Entry Points & Screens

| Screen | Path | Purpose |
|--------|------|---------|
| `FootProfileOnboardingScreen` | `lib/screens/auth/foot_profile_onboarding_screen.dart` | Post-signup one-time onboarding |
| `FootInstructionsScreen` | `lib/screens/customer/foot_instructions_screen.dart` | Mode selection (Live AR vs Paper), options (paper size, foot condition, smart assist) |
| `FootManualMeasureScreen` | `lib/screens/customer/foot_manual_measure_screen.dart` | **Primary flow**: live AR tap-to-measure with ARCore |
| `FootCaptureScreen` | `lib/screens/customer/foot_capture_screen.dart` | Paper-based camera capture (alternative flow) |
| `FootProcessingScreen` | `lib/screens/customer/foot_processing_screen.dart` | Processes paper-captured image (CV pipeline) |
| `FootResultsScreen` | `lib/screens/customer/foot_results_screen.dart` | Displays results, size adjustment, save to profile |
| `CustomerFootProfileBanner` | `lib/widgets/customer_foot_profile_banner.dart` | Reminder banner when no foot profile exists |

---

## 3. Two Scan Modes

### 3.1 Live AR Scan (Primary) — `FootManualMeasureScreen`

**No paper needed.** Uses ARCore world tracking for real-world measurements.

**User flow per foot:**
1. **FRONT view** (top-down): Tap two widest points → measures **width**
2. **SIDE view** (profile): Tap heel, then tip of longest toe → measures **length**
3. Repeat for the other foot

**Key interaction:**
- Tap to place point A → line draws from A to center crosshair with **live cm readout**
- Tap again to place point B → distance locks
- **Drag** either point to adjust after placement
- **Trash icon** clears the current pair; **Confirm** advances the flow

**Technical details:**
- ARCore `hitTest` raycasts 2D screen taps → 3D world coordinates (meters)
- Coordinates are **normalized** (0.0–1.0) to match ARCore's API
- Plausibility guards: length 10–40 cm, width 4–18 cm
- Uses the **larger foot** for final size recommendation (standard convention)

### 3.2 Paper Scan (Alternative) — `FootCaptureScreen` → `FootProcessingScreen`

**Uses paper as scale reference.** A4 (210×297mm) or US Letter (215.9×279.4mm).

1. Camera captures image with foot on paper
2. Paper corner detection (classical CV) computes scale factor
3. Foot segmentation isolates the foot outline
4. Measurements computed from scale × pixel dimensions

> **Note**: Currently uses simulated measurements in the processing screen. The paper detection uses a simulated timer-based progression (searching → detected → ready).

---

## 4. Core Architecture Layers

### 4.1 AR Platform Channel — `ArCoreChannel`
**File**: `lib/services/ar_core_channel.dart`

Singleton wrapper over native ARCore Kotlin plugin via `MethodChannel`/`EventChannel`.

| Method | Purpose |
|--------|---------|
| `startSession()` | Initialize ARCore with plane detection |
| `stopSession()` | Release resources |
| `hitTest(x, y)` | Raycast 2D → 3D world point (single) |
| `hitTestBatch(screenPoints)` | Batch raycast (single channel round-trip) |
| `acquireCameraFrame()` | Get NV21 bytes for ML processing |
| `getTrackingState()` | Current tracking quality |
| `getFloorPlane()` | Best detected horizontal plane |

**Events stream**: `tracking` (state changes), `plane` (new planes), `error`.

**Data classes**: `ArWorldPoint` (x, y, z, distance), `ArCameraFrame` (NV21 + dims), `ArPlane`, `ArSessionEvent`.

### 4.2 Foot Detection & Segmentation — `FootDetector`
**File**: `lib/utils/foot_detector.dart`

**Interface** with two implementations:

| Implementation | File | Method |
|---------------|------|--------|
| `MlKitSegmentationFootDetector` | `lib/utils/mlkit_segmentation_foot_detector.dart` | ML Kit Selfie Segmentation → per-pixel mask → PCA → points |
| `MlKitPoseFootDetector` | `lib/utils/mlkit_pose_foot_detector.dart` | ML Kit Pose → heel/toe landmarks |

**`FootDetectionResult`** contains:
- `footDetected` (bool), `confidence` (0–1)
- `heelPoint`, `toePoint` (normalized FootPoint)
- `widthPoints` (list of 2 widest points)
- `qualityScore` (combined weighted score)
- Sub-scores: `segmentationScore`, `shapeScore`, `containmentScore`

**Quality scoring** (weighted combination, replaces binary gates):
- Segmentation confidence: 25% weight
- Shape/elongation: 35% weight (ideal aspect ratio 2.5–4.9×)
- Guide-box containment: 40% weight
- Acceptance threshold: `qualityScore >= 0.7`

**Temporal consistency**: `TemporalFootGate` requires 3 consecutive positive frames before confirming a detection (prevents flicker).

### 4.3 Measurement Pipeline — `ar_foot_measurement_pipeline.dart`
**File**: `lib/utils/ar_foot_measurement_pipeline.dart`

Statistical pipeline for multi-sample AR scanning:

1. **Collect** samples every 200ms during a 4-second scan arc
2. **Filter** low-quality samples (tracking < 0.7, segmentation < 0.5)
3. **Outlier removal** via IQR method (k=1.5)
4. **Median** of filtered samples → final measurement
5. **Confidence** from IQR spread + sample count

**Key thresholds:**
- `minValidSamples`: 5
- `idealSampleCount`: 15
- Confidence: ≥0.75 high, ≥0.45 medium, <0.45 low

**Guided two-angle variant**: `combineGuidedSamples()` trusts the **side capture** for length and **front capture** for width (each angle is best suited to one dimension).

### 4.4 Size Conversion Utilities
**File**: `lib/utils/foot_measurement_utils.dart`

Key functions:
- `footLengthMmToEuSize(lengthMm)` — mm → EU size lookup
- `euToUs(euSize)` — EU → US Men's (approx EU - 33)
- `euToUk(euSize)` — EU → UK (approx EU - 33.5)
- `mapViewToNormalized()` / `mapNormalizedToView()` — coordinate transforms between view pixels and normalized frame space (accounts for center-crop preview + rotation)

### 4.5 Smart Assist (§6)

Optional auto-suggestion layer over the manual tap flow:
- While user waits to place the first point, a background segmentation detector proposes initial positions
- User can **accept** (then drag-adjust) or **ignore** and tap manually
- Throttled to 600ms intervals, self-gating (only when guidance is ready and no pair is in progress)
- Controlled by `smartAssistEnabled` flag on `FootInstructionsScreen`

---

## 5. Data Layer

### 5.1 Model — `FootMeasurement`
**File**: `lib/models/foot_measurement.dart`

```dart
class FootMeasurement {
  int? id;
  String userId;
  double? footLengthLeftMm, footWidthLeftMm;
  double? footLengthRightMm, footWidthRightMm;
  String? recommendedEuSize, recommendedUsSize, recommendedUkSize;
  String paperSizeUsed;       // 'ar', 'a4', 'letter'
  String? footCondition;      // 'bare', 'socks'
  String? userAdjustedEuSize; // null = user accepted recommendation
  double? overallConfidenceScore; // 0.0–1.0
  String? confidenceLevel;        // 'high', 'medium', 'low'
  int? rawSampleCount, finalSampleCount;
  DateTime scanDate;
}
```

**Computed properties:**
- `effectiveEuSize` → `userAdjustedEuSize ?? recommendedEuSize`
- `effectiveUsSize` / `effectiveUkSize` → derived from effective EU
- `maxFootLength` → larger of left/right length

**Size conversion**: `FootMeasurement.euToUs()`, `FootMeasurement.euToUk()`, `FootMeasurement.formatMm()`, `FootMeasurement.formatCm()`.

### 5.2 Provider — `FootMeasurementProvider`
**File**: `lib/providers/foot_measurement_provider.dart`

| Method | Purpose |
|--------|---------|
| `loadLatest(userId)` | Fetch latest + all measurements from Supabase |
| `saveScan(measurement)` | Insert new measurement, update local state |
| `updateAdjustedSize(id, euSize)` | Update user's manual size adjustment |
| `deleteMeasurement(id, userId)` | Remove a measurement |

**Key getters**: `latestMeasurement`, `allMeasurements`, `hasMeasurement`, `recommendedEuSize`.

### 5.3 Service — `FootMeasurementService`
**File**: `lib/services/foot_measurement_service.dart`

Supabase CRUD for the `foot_measurements` table:
- `getLatestMeasurement(userId)` — ORDER BY scan_date DESC LIMIT 1
- `getAllMeasurements(userId)` — all, newest first
- `saveMeasurement(measurement)` — INSERT returning the row
- `updateUserAdjustedSize(id, size)` — UPDATE user_adjusted_eu_size
- `deleteMeasurement(id)` — DELETE

### 5.4 Supabase Table: `foot_measurements`

| Column | Type | Notes |
|--------|------|-------|
| `id` | int (auto) | Primary key |
| `user_id` | uuid | FK to auth.users |
| `foot_length_left_mm` | float | |
| `foot_width_left_mm` | float | |
| `foot_length_right_mm` | float | |
| `foot_width_right_mm` | float | |
| `recommended_eu_size` | text | |
| `recommended_us_size` | text | |
| `recommended_uk_size` | text | |
| `paper_size_used` | text | 'ar', 'a4', or 'letter' |
| `foot_condition` | text | 'bare' or 'socks' |
| `user_adjusted_eu_size` | text | nullable |
| `paper_detection_confidence` | float | 0.0–1.0 |
| `lighting_quality` | float | 0.0–1.0 |
| `overall_confidence_score` | float | 0.0–1.0 |
| `confidence_level` | text | 'high', 'medium', 'low' |
| `raw_sample_count` | int | |
| `final_sample_count` | int | |
| `scan_date` | timestamptz | |

---

## 6. Guide Boxes (Normalized Coordinates)

Used for the two-angle capture and smart-assist positioning:

| Guide | Rect (left, top, right, bottom) | Purpose |
|-------|--------------------------------|---------|
| Front (top-down) | `(0.30, 0.15, 0.70, 0.70)` | Width measurement — phone held ~30cm above |
| Side (profile) | `(0.15, 0.35, 0.85, 0.65)` | Length measurement — phone held to the side |

---

## 7. Dependencies

| Package | Purpose |
|---------|---------|
| `arcore_flutter_plugin` / native Kotlin | ARCore session, tracking, hitTest, camera frames |
| `google_mlkit_selfie_segmentation` | Per-pixel foreground mask (primary detector) |
| `google_mlkit_pose_detection` | Skeleton landmarks (legacy/fallback detector) |
| `camera` | Camera access for paper scan mode |
| `permission_handler` | Camera permission requests |
| `supabase_flutter` | Backend persistence |

---

## 8. Key Files Quick Reference

```
lib/
├── models/
│   └── foot_measurement.dart           # Data model + size conversions
├── providers/
│   └── foot_measurement_provider.dart   # State management
├── services/
│   ├── ar_core_channel.dart            # ARCore platform channel wrapper
│   └── foot_measurement_service.dart    # Supabase CRUD
├── screens/
│   ├── auth/
│   │   └── foot_profile_onboarding_screen.dart  # Post-signup onboarding
│   └── customer/
│       ├── foot_instructions_screen.dart         # Mode selection + options
│       ├── foot_manual_measure_screen.dart       # Live AR tap-to-measure
│       ├── foot_capture_screen.dart              # Paper scan capture
│       ├── foot_processing_screen.dart           # Paper scan CV pipeline
│       ├── foot_results_screen.dart              # Results + save
│       └── foot_ar_scan_screen.dart              # (Alternate AR scan entry)
├── utils/
│   ├── ar_foot_measurement_pipeline.dart  # Statistical sample combining
│   ├── foot_detector.dart                 # Detection interface + mask evaluation
│   ├── foot_measurement_utils.dart        # Size conversion + coord transforms
│   ├── mlkit_segmentation_foot_detector.dart  # ML Kit segmentation impl
│   ├── mlkit_pose_foot_detector.dart      # ML Kit pose impl (legacy)
│   └── mlkit_input_helper.dart           # NV21 → InputImage helper
└── widgets/
    └── customer_foot_profile_banner.dart  # Reminder banner
```

---

## 9. Important Design Decisions

1. **Manual tap-to-measure is primary** — the automatic detection/segmentation was pivoted to an optional "smart assist" suggestion layer. The user places points directly for maximum control.

2. **Larger foot wins** — shoe size is always based on the larger foot (standard retail convention).

3. **No hard floor-scan gate** — taps are validated per-tap via hitTest rather than requiring a floor-area coverage gate first. This makes the UI responsive immediately.

4. **Strict side gating** — a left-foot scan never silently accepts right-foot samples (§4 of the detection brief).

5. **User-adjusted sizes** — the results screen allows manual half-size override. The `effectiveEuSize` getter transparently returns the adjusted size if set.

6. **Profile snapshot** — `AuthProvider.saveFootProfile()` stamps a lightweight snapshot (`foot_profile_source`, `foot_size_eu`) for quick access by other parts of the app (checkout recommendations, banner visibility).
