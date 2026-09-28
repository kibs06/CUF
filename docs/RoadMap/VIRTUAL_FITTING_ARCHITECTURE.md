# Virtual Fitting — Architecture

**Version:** 1.4.10
**Created:** September 27, 2026
**Updated:** September 28, 2026 — **§2.5.1's contract now has an ingest step, because the first real partner asset proved that a file can be *correct* and still fail the checks (V2.7).** The file was a marketplace/AI-generated shoe: 31.5 MiB, 49,954 triangles, three 4096² PBR maps, one material called `Material.001`, 1160.8 × 480.3 × 433.1 mm — and 7 of the 11 rows red for reasons that are all coordinate arithmetic: the scene's Z-up→Y-up rotation was left **on the node** (a distinction §2.5.1's checks cannot see, because they read accessor bounds, while the renderer honours the node — the file was simultaneously "failing" and "rendering upright"), the length ran along **X**, the scale was **4.30× life size**, the origin was mid-shoe, the textures were 4096², and one material cannot be repainted per part. `lib/utils/glb_normalizer.dart` + `tool/prepare_shoe_model.dart` are that repair: bake the node transform into the vertices and normals, yaw the length onto +Z, scale to the **declared** length (never invented), ground and centre at the heel-bottom, re-bake textures to ≤1024², rename parts, and — for a scan with a single material — cut a `sole` band geometrically with its area share reported. Two refusals are design, not gaps: Draco/meshopt geometry and KTX2 textures cannot be undone offline, so the tool declines and states the re-export instead of writing a file it cannot verify. What it cannot do is §2.5.1's whole undecidable list plus one more: it does not know which end is the toe (`--toe`, enforced as an explicit answer or a stated assumption) and it does not know the declared length. Measured on the real bytes: **31.48 MiB → 1.66 MiB, 270.0 × 111.7 × 100.7 mm, 11/11 PASS**; the bundled placeholder still passes all 11 after a pass over it (idempotence test). §2.5.1's contract is unchanged by any of this — the fixer serves the contract, it does not relax it
**Prev. update:** September 28, 2026 — **§2.5.4's "later phase" arrived, and it is enforced by the database rather than by the app (V2.4).** Three pieces. **The mirror:** an Edge Function runs on Deno and cannot import Dart, so the rule set is repeated in `supabase/functions/_shared/glb_validator.ts` — and because two implementations of one contract are a drift hazard, `tool/check_glb_validator_parity.mjs` runs the Dart CLI and the TypeScript mirror over 22 fixtures and diffs check names, order, statuses, detail text, notes and measured numbers (all 22 agree). **The function:** `validate-shoe-model` takes the row id, resolves ownership explicitly (`products → stores.owner_id`, or `is_admin()` through the caller's own client — an `active` row is world-readable, so visibility must never imply authority), downloads the object with the service role, hashes it against `row.sha256`, runs the contract, and writes the verdict; a refusal is 422 with the report, so "the server said no" and "the call broke" stay distinguishable. **The enforcement:** the `product_models` policies let a seller write `status='active'` directly, which would have made the validator advisory — so `20260928120000_gate_product_model_active.sql` adds one trigger refusing that transition from any JWT role but `service_role`. The seller path now inserts **draft** and lets the server publish. **Honest state:** that migration is written and **not applied** (publishing works in both states — the client no longer writes `active`); its nine branches were verified in a rolled-back transaction against the live schema; and the four things bytes cannot decide (toe-vs-heel, de-lit albedo, likeness, on-device fps) are returned with every response instead of being implied away
**Prev. update:** September 28, 2026 — **§2.2's D2 is decided: drive Filament/gltfio directly, because the measurement said so (findings §5.5).** **§2.3's Flutter layer exists for V3's renderer-independent half: the phase machine, the session controller, the capability gate and the Dart half of §2.8's channel.** Three things are worth reading the code for. *(1) A phase is not a mode:* `TryOnPhase` describes the AR session and `TryOnMode` describes the surface, so "this product has no model" is `idle` with a stated reason rather than an error — the distinction that keeps a missing asset out of §2.7.4's error telemetry. *(2) §2.3's mode snippet is now a file* (`lib/providers/try_on/try_on_mode.dart`): the four-combination table, the published `resolveTryOnMode` kept as a one-line delegate so it cannot drift from the decision form, and every ARCore refusal code mapped — **including codes a newer native build may invent**, which fall back rather than throw. *(3) §2.9's lifecycle invariants are enforced in Dart, not merely written down:* **F17** is `startAr({required bool arViewReady})`, which refuses to start the session without a mounted view; **F18** is an early `setModel` handover, because the native side parks it; **F19** is the switch gating side effects, so a build that did not ask for try-on makes no channel calls at all. §2.8's **Dart** side is written (8 methods, 4 payload types, a fail-closed event parser) and now so is its **native** side: `com.solevision.app.tryon.ArTryOnPlugin` + `ArTryOnView` (findings §5.6) implement the same names on the Filament-direct route D2 chose, with §2.9's invariants honoured on the native end too — F18 parking for an early `setModel`, and F17 answered as `timeout` after 15 s rather than a hang. **Two limits are explicit rather than implied.** *(1)* The camera background and the plane visual are **not implemented**: F20 measured that the Filament artifacts ship zero assets, so the two `.filamat` files those draws need are ours to supply (~85 KB vendored, version-checked, or built with `matc`), and hand-building geometry against the ubershader is the measured SIGABRT of F16 — until then the model renders over a flat clear colour. *(2)* **Nothing has run on a device**: the view compiles, and fps/load/tracking belong to V0.6. `product_models` is still 0 rows. V3.5 then closed the reachability gap: the try-on screen builds the platform view and falls back on every non-real state, and a default-off QA seam points the **production** read service at the repo's bundled block-out, so the whole path can be exercised with no `product_models` row — substituting one boundary (`ShoeModelDataSource`), never the logic under test. Analyzer clean; **1,990 pass / 6 skipped**, identical in both switch configurations
**Prev. update:** September 28, 2026 — **the pipeline this document specified is live: §2.7.1's migration was already on the hosted project, and both switches now ship ON.** A `supabase db query --linked` check returned `product_models` at its 17 columns with 4 indexes, 4 policies and **0 rows**, and `shoe-models` as a public 8,388,608-byte `model/gltf-binary` bucket — so `AppConstants.shoeModelUploadEnabled` (§2.13) and `AppConstants.tryOnPrefetchEnabled` (§2.7's first reader) both default to **`true`**, each rolling back alone with `--dart-define=…=false`. **What this changes about the design: nothing.** The only wrong claim in this document was the §2.7.1 row's "written but not applied", and it was wrong in a way now recorded twice (§2.7.1 here and the V1.3 columns on 2026-09-27): **a migration is finished when a `--linked` query says so, not when the SQL Editor says "Success".** **What it does not change:** the table is empty, so V3's controller is still the first consumer that can render anything; V2.4's `validate-shoe-model` is still unwritten; and §2.5.4's rule that client-side validation is **not** a security boundary is entirely unaffected by a switch. Analyzer clean; **1,920 pass / 6 skipped** in the new default, **1,913 / 13** with both switches off
**Prev. update:** September 28, 2026 — **§2.7's read service has its first caller, and §2.13's upload exists — so the pipeline is now connected end to end at both ends** (V2.6 + V2.2/V2.3). `lib/services/try_on_prefetch.dart` is the class that makes a *prefetch* survivable while `ShoeModelService` stays strict: every failure becomes one of four returned outcomes (disabled / no model / cached / failed), so a warm cache can never degrade the page it is warming, and the product page fires it once on mount behind `AppConstants.tryOnPrefetchEnabled` (**off when this was written; it defaults to on since the update above** — only V3 can consume a warm cache). One harness boundary this phase pinned, and it matters for V3's tests: `testWidgets`' fake-async zone cannot complete real file I/O, so `ensureLocal`'s download stage is unreachable from a widget test and `runAsync` is not the escape (it surfaces the unbundled runtime font fetch as a test error) — the seam is injecting the file work. **Prev. update (same day) — §2.13's seller upload is built** (V2.2/V2.3), and §2.5.4's client half is now a real caller of the validator rather than a plan: the form's "3D Model (Optional)" section fetches the handover link, runs the contract, shows the failing rows as sentences, and publishes on Save. Three §2.13 items are deferred with reasons recorded in the roadmap's V2 status note — the **file picker** (`image_picker` cannot select a `.glb`, and no picker is a dependency), the **per-colour override** (§2.7.2's `variant_id` is a *variant* id, and the app's variants are colour **and** size, so one colour's model would render on one size), and the **material-part → colour mapping** (the product's colours are free-text names with no paint value, and `lib/utils/variant_swatch_color.dart` is a UI swatch whose synthetic unknown-name fallback must not become albedo). §2.5.4 also gained the two typed report fields the row stores (`triangleCount`, `meshExternalLengthMm`). Ships behind `AppConstants.shoeModelUploadEnabled` — **off when this was written, on since the update above**, because §2.7.1's migration **is** applied (the "not applied" this sentence used to end on was simply wrong), so the flip it was waiting for was a flip, not an apply
**Prev. update:** September 27, 2026 — **§2.5.4 is executable now** (V2.7): `lib/utils/glb_validator.dart` implements the contract's checks as a pure library (**22 tests**) behind the `tool/validate_glb.dart` CLI, so the client upload and the Edge Function repeat one rule set instead of three; §2.16 gained the file, and its `validate-shoe-model` entry was relabelled V2.4
**Prev. update:** September 27, 2026 — **§2.6.2 added: shadow mode** (V1.7) — the `[FIT]` record, the two off-by-default switches, and the single sink that is repointed when the temporary diag scaffolding is retired
**Prev. update:** September 27, 2026 — **§2.6.1 added: the fit verdict card** (V1.5/V1.6) — the pure fallback rules, the two visible non-verdict states, and the reason the card must read the saved scan itself; §2.6's "Built" line and the engine's surface list updated
**Prev. update:** September 27, 2026 — lifecycle invariants added to §2.9 (view-before-session, parked handover, flag gates side effects) after the V0 spike hit all three; §2.11's size budget measured and failed, D2 re-opened; earlier: Blender appendix (§2.5.5); external vs internal length split corrected in §2.5.1/§2.5.2/§2.7.2
**Status:** Planning / pre-implementation — nothing in this doc is built unless §1 says it is
**Platform target:** Android first (matches the shipped ARCore stack), iOS deferred
**Rendering decision:** Native **glTF on our own ARCore plugin** — no third-party try-on SDK
**Companion:** `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` (the phased build plan for this design)
**Related:** `docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md` (**the partner-facing how-to for §2.5.1**) · `docs/RoadMap/SOLEVISION_ROADMAP.md` (Phase 8 umbrella) · `docs/AI/FOOT_SIZING_ARCHITECTURE.md` (the shipped scan paths) · `docs/AI/AR_TRY_ON_ARCHITECTURE.md` (**partly stale** — it predates v2 and lists try-on entry points that no longer exist; use §1 of this doc instead) · `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` (P3/P4 are still open; the fit engine in §2.6 is the data source they were waiting for)

---

## 0. The feature in one page

Virtual fitting has **two pillars**, and the app has only finished one of them:

| Pillar | Question it answers | Status |
|---|---|---|
| **Fit** — know your size | "What size am I, in this brand?" | ✅ **Shipped and real.** Live ARCore foot scan (v1 + Foot Size 2.0), on-device ML Kit detection, statistical measurement pipeline, saved foot profile |
| **Try-on** — see it on your foot | "What does *this shoe* look like on *me*?" | 🟡 **Simulated.** A polished placeholder screen with a fake camera feed, animated scan line and particle effects. No camera, no 3D shoe, no foot tracking |

This document specifies how pillar two becomes real **on top of pillar one**, because pillar one already contains the three hardest pieces: a working ARCore session bridge, an on-device foot detector, and a calibrated millimetre measurement of the customer's actual foot.

The single most important architectural statement in this doc:

> **The try-on does not need a new AR stack. It needs a renderer added to the AR stack that already ships, fed a pose that the detector that already ships can produce.**

### 0.1 Why now

| Asset that already exists | Why it matters for try-on |
|---|---|
| `ArFootSizingView.kt` — a custom `GLSurfaceView` + `GLSurfaceView.Renderer` that already draws the live ARCore camera feed | The camera-feed problem is solved. The try-on adds a mesh draw pass, not a camera pipeline |
| `ArCoreChannel` — session lifecycle, `hitTestBatch`, `acquireCameraFrame`, structured start failures (`unsupported_device`, `needs_install`, `user_opted_out`, …) | Device gating, error taxonomy and frame acquisition for ML Kit are already written and field-tested |
| `MlKitSegmentationFootDetector` + `TemporalFootGate` + `ar_foot_measurement_pipeline.dart` | Per-frame heel/toe/width points, foot side gating, quality scoring, temporal stabilisation, median+IQR statistics — the pose inputs a renderer needs |
| `foot_measurements` table + `profiles.foot_size_ph` snapshot | The customer's real foot length and width in mm, already persisted, already used by browse surfaces |
| `size_key.dart` / `size_match.dart` / `inventory` | One canonical size vocabulary, so the model's scale and the product's stock can never disagree with the tag |

---

## 1. What exists today (verified against code, Sept 27 2026)

### 1.1 AR capture stack (native, Android)

| File | Lines | Role |
|---|---|---|
| `android/app/src/main/kotlin/com/solevision/app/arfoot/ArFootSizingPlugin.kt` | 304 | Registers platform view type `ar_foot_scan`; owns MethodChannel `com.solevision/ar_foot_sizing` and EventChannel `…/events` |
| `android/app/src/main/kotlin/com/solevision/app/arfoot/ArFootSizingView.kt` | 1005 | PlatformView: ARCore session lifecycle, `setCameraTextureName()`, `ArGLSurfaceView` + `ArRenderer` (draws the live camera feed via `transformDisplayUvCoords`), CPU image acquisition, `hitTest`, floor plane, events |
| `android/app/src/main/kotlin/com/solevision/app/arfoot/DiagRelay.kt` | 97 | Temporary diagnostics relay — **delete-on-sight** debt, do not build on it |
| `android/app/src/main/kotlin/com/solevision/app/MainActivity.kt` | — | Registers `ArFootSizingPlugin` in `configureFlutterEngine`; this is where a sibling try-on plugin gets registered |
| `android/app/build.gradle` | — | `minSdk 24`, `targetSdk 36`, ARCore `com.google.ar:core:1.54.0`, ML Kit pose detection, CameraX 1.3.4. **No 3D renderer dependency yet** |
| `lib/services/ar_core_channel.dart` | 494 | Dart wrapper: `startSession`, `stopSession`, `hitTest`, `hitTestBatch`, `acquireCameraFrame`, `getTrackingState`, `getFloorPlane`; data classes `ArWorldPoint` (metres), `ArCameraFrame` (NV21 + rotation), `ArPlane`, `ArSessionEvent`, `ArTrackingState`, `ArSessionStartResult` |

**iOS has no AR implementation** — `grep` finds no ARCore/try-on code under `ios/`. This is why the roadmap is Android-first.

### 1.2 Foot detection, pose and measurement

| File | Lines | Role |
|---|---|---|
| `lib/utils/foot_detector.dart` | 43 KB | `FootDetector` interface + `FootDetectionResult` { `footDetected`, `confidence`, `footSide`, `rejectedFootSide`, `heelPoint`, `toePoint`, `widthPoints`, `qualityScore`, sub-scores }. Weighted acceptance (segmentation 25% / shape 35% / containment 40%, threshold ≥ 0.7) instead of an AND-chain of gates |
| `lib/utils/mlkit_segmentation_foot_detector.dart` | — | Primary detector: ML Kit selfie segmentation → per-pixel mask → PCA → heel/toe/width points |
| `lib/utils/mlkit_pose_foot_detector.dart` | — | Legacy pose-landmark detector (fallback) |
| `lib/utils/ar_foot_measurement_pipeline.dart` | 22 KB | Samples every 200 ms over a 4 s arc → quality filter → IQR outlier removal → median; `TemporalFootGate` needs 3 consecutive positive frames; `combineGuidedSamples()` (side capture owns length, front owns width) |
| `lib/utils/foot_measurement_utils.dart` | 27 KB | mm→EU/US/UK conversion, `mapViewToNormalized` / `mapNormalizedToView` (centre-crop + rotation aware) |
| `lib/providers/v2/scan_phase.dart` | 144 | `CaptureStep { leftTop, leftSide, rightTop, rightSide }`, `ScanPhase { needsPermission, starting, startFailed, positioning, ready, capturing, stepComplete, processing, … }`, `CoachHint` |
| `lib/providers/v2/scan_session_controller.dart` | 1096 | **The loop to copy.** Typed state machine; per-pass fresh sample buffer merged only on success (stale-sample bug fix); frozen per-foot results; 5 s v2 pass; `kW2MinSampleConfidence = 0.50`; width/length sanity ratio 0.20–0.60 |
| `test/providers/v2/scan_session_controller_test.dart`, `test/providers/auto_scan_controller_test.dart` | — | Existing precedent: the controller is testable with `fake_async` + injected `ArCoreChannel`/detector factory |

**How a measurement is actually produced today** (this is the exact pose pipeline the try-on will reuse):

```
NV21 frame (native, cached, throttled)
  → FootDetector.detect(...)                normalized image points + quality
  → TemporalFootGate.update(rawValid)       3-frame confirmation, kills flicker
  → detection.{heel,toe,width} → hitTestBatch  2D screen → 3D world points (metres)
  → distances in mm → quality filter → IQR outliers → median per dimension
  → larger foot wins → mm → EU → persisted
```

### 1.3 Foot Size 2.0 (the shipped session UI)

| File | Lines | Role |
|---|---|---|
| `lib/screens/customer/foot_size_v2/foot_scan_setup_screen_v2.dart` | 428 | Entry: shopping category (men/women/kids), foot condition (bare/socks), camera pre-flight, `embedded` mode for the `SizeYourFootScreen` panel |
| `lib/screens/customer/foot_size_v2/foot_scan_session_screen_v2.dart` | 977 | One screen hosts all four captures — no route transitions mid-session. PlatformView `ar_foot_scan` → `PlatformViewLink`; guide frame; stepper; coach card; capture ring |
| `lib/screens/customer/foot_size_v2/foot_scan_results_screen_v2.dart` | 1154 | Confidence ring + per-factor breakdown; ±0.5 EU adjustment capped at ±2; saves `foot_measurements` row, then `saveFootProfile` snapshot |
| `lib/widgets/foot_size_v2/*` | — | `foot_trace_overlay`, `scan_instruction_overlay`, `scan_stepper`, `glass_card` |

The v1 flow (`foot_ar_scan_screen.dart` 1122 lines, `foot_manual_measure_screen.dart`, paper capture, etc.) still exists for guided-tap and paper modes.

### 1.4 Try-on today (simulated)

| File | Lines | Role |
|---|---|---|
| `lib/screens/customer/ar_fitting_screen.dart` | 800 | `ARVirtualFitScreen`: dark scaffold, `ARViewPlaceholder` fake feed, `_ARParticlePainter`, top/bottom glass panels, product carousel, size chips, availability sheet, add-to-cart with `FlyToOrderAnimation`, first-run tutorial — **plus V3.5's swap (built 2026-09-28):** it builds the real platform view into the feed slot when the gate allows, calls `startAr` from `onPlatformViewCreated` (F17), hands the model over in `initState` (F18), and falls back to the simulated feed on every non-real state. The swap is *derived* from the gate and the controller's degradation, never toggled |
| `lib/services/try_on_placeholder_model.dart` | 190 | `BundledPlaceholderModelDataSource`: a `ShoeModelDataSource` that serves a **bundled** `.glb` as a one-row product, so V3.5's path runs the **production** read service — resolve, digest verify, `.part`-then-rename write, LRU budget, native handover — with no `product_models` row. Two assets are bundled and chosen at build time (`--dart-define=TRY_ON_QA_MODEL=…`, default the block-out): the 29,340 B V0 block-out, and `assets/models/qa_partner_shoe_v1.glb`, the first real partner file to pass the contract (1.66 MiB, 49,954 triangles, three 1024² maps — findings F21), because an untextured 1,536-triangle fixture cannot exercise texture decoding or fill rate. Row numbers are per-asset (a 49,954-triangle asset reporting 1,536 would make the QA comparison meaningless) and an unknown override falls back *and* is reportable (`qaModelOverrideUnknown`) rather than silently serving the wrong file. Behind `AppConstants.tryOnPlaceholderModelEnabled` (**off**); a QA seam, not a shipping path, and the partner asset must be deleted with it (findings §9) |
| `lib/widgets/ar_view_placeholder.dart` | — | Fake camera: corner brackets, 3 s scan line, "Place Foot Inside Box". **Already accepts an optional `arView` widget** — the seam the real renderer plugs into |
| `lib/widgets/sole_ar_pill.dart` | — | "Try On in AR" CTA |

**Entry point reality check:** the only remaining launch site is `lib/screens/customer/product_detail_screen.dart:2000` (`SoleARPill`). `docs/AI/AR_TRY_ON_ARCHITECTURE.md` §2 claims home/store cards also launch it via `SoleProductCard.onTryOnTap` — that is **no longer true** in this codebase. Treat this section as canonical.

### 1.5 Fit data and size-aware surfaces

| Surface | File | Notes |
|---|---|---|
| Foot profile snapshot | `profiles.foot_size_ph` + `foot_size_category`; written by `AuthProvider.saveFootProfile()` (`lib/providers/auth_provider.dart:955`) | Read by `lib/utils/size_match.dart:174` and `lib/utils/customer_profile_fields.dart:146` |
| Full measurements | `foot_measurements` table (migration `20260730100000`, + v2 fields `20260821000000`, + reason `20260821100000`, + size category `20260917130000`) | `FootMeasurementProvider` / `FootMeasurementService`; `effectiveEuSize` = `user_adjusted_eu_size ?? recommended_eu_size` |
| Size vocabularies | `lib/utils/size_key.dart`, `lib/utils/size_match.dart` | Pure Dart, unit-tested; `kPlausibleEuMin/Max = 22/48`, near-size tolerance; `StockedSize` from `inventory` only |
| Size-aware browse | `lib/widgets/in_your_size_section.dart`, `lib/screens/customer/size_listing_screen.dart`, `ProductProvider.productsInSize()` | "Based on your size" shelf, shipped; badge/filter/product-page preselect (P3–P5 of the size-aware plan) **not started** |

### 1.6 Product / inventory data the try-on must respect

```
products              id TEXT PK, store_id, seller_id, name, description, price,
                      category, tags[], is_active, sale_price…            ← new fit columns land here
product_variants      id, product_id, size TEXT, color, stock, additional_price, sku
inventory             (product_id, size) PK, stock        ← the authoritative size+stock relation
product_images        id, product_id, image_url, display_order, is_primary
storage buckets       product-images, store-assets, message-attachments, review-images,
                      payment-proofs, seller-verification-docs        ← no model bucket yet
```

### 1.7 The gap table (what is actually missing for a real try-on)

| # | Missing piece | Smallest thing that closes it |
|---|---|---|
| G1 | No 3D renderer in the app | Add SceneView (Filament) to the Android module; one prototype model on screen |
| G2 | No 3D shoe assets and nowhere to put them | A `shoe-models` bucket + `product_models` table + seller upload |
| G3 | No foot *pose* (position/orientation over time) — only scalar length/width | Emit `heel/toe/width` points over a channel; native projects to world and smooths |
| G4 | No shoe-side dimensions to compare feet against | Nullable last-dimension columns on `products` + a seller form section |
| G5 | No fit verdict | `lib/utils/fit_engine.dart` (pure Dart, like `size_match.dart`) |
| G6 | No telemetry on try-on usage/quality | `try_on_events` table + a small event client |
| G7 | No occlusion strategy (shoe would draw *over* the foot) | Mask-stencil occlusion in v1 (§2.10), Depth API later |
| G8 | No try-on session UI states (loading model, tracking lost, unsupported device) | A `TryOnSessionController` cloned from the v2 scan controller's phase pattern |

---

## 2. Target architecture

### 2.1 Layer diagram

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ FLUTTER — feature layer (all of §2.3)                                        │
│                                                                               │
│  product_detail_screen ──► ArTryOnScreen  (evolved from ARVirtualFitScreen)   │
│         SoleARPill            │  chrome: size chips, colour, fit verdict,     │
│                               │          add-to-cart + fly animation, share   │
│                    ┌──────────┴───────────┐                                   │
│                    │ TryOnSessionController│  typed ScanPhase-style states    │
│                    │ (lib/providers/try_on)│  + one-shot events (modelLoaded, │
│                    └──────────┬───────────┘              footLocked, error)    │
│                               │                                               │
│      ┌────────────────────────┼────────────────────────┐                       │
│      │                        │                        │                      │
│  ShoeModelService       ArTryOnChannel            FootDetector                │
│  (resolve/download/     (pose out, model in,      (reused as-is, run           │
│   cache/evict GLB)       screenshot, events)      off acquireCameraFrame)      │
│      │                        │                        │                      │
└──────┼────────────────────────┼────────────────────────┼──────────────────────┘
       │ HTTPS (signed/public)  │ MethodChannel+EventChannel │  (native side owns ARCore)
       ▼                        ▼                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ ANDROID NATIVE — new package com.solevision.app.artryon                        │
│                                                                               │
│  ArTryOnPlugin  ── registers view type "ar_try_on" + channels                 │
│                                                                               │
│  ArTryOnView (PlatformView)                                                    │
│   ├── ARCore Session  (same lifecycle contract + ArSessionStartResult reasons) │
│   ├── SceneView ArSceneView (Filament)  ← camera feed + scene + lighting       │
│   │     └── AnchorNode                                                        │
│   │           └── ModelNode(glTF)  ← scale = f(size), material swaps, stencil │
│   ├── ModelCache (files dir, key = modelId + version + sha256)                 │
│   ├── FootPoseTracker  ← pose frames from Dart → hitTestBatch → world basis,   │
│   │                       one-euro smoothing, anchor refresh, lock hysteresis  │
│   └── PerfProbe → events (fps, load ms, tris)                                  │
│                                                                               │
│  (existing, frozen)  arfoot/ArFootSizingView ── the shipped scan; untouched    │
└───────────────────────────────────────────────────────────────────────────────┘
       ▲                        ▲
       │ public read            │ write (seller), read (app)
┌──────┴────────────────────────┴───────────────────────────────────────────────┐
│ SUPABASE                                                                       │
│  storage: shoe-models/…          product_models table      products.last_*_mm   │
│  try_on_events table (analytics)                          (fit spec columns)    │
│  Edge Function (built 2026-09-28): validate-shoe-model  ← only writer of        │
│  `product_models.status='active'`, enforced by a trigger, not by convention    │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Decisions (with the alternative each one rejects)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| **D1** | **Native glTF on our ARCore plugin**, Android-first | The ARCore session, camera-feed GL renderer, device-gating errors and ML Kit pipeline already ship. Marginal cost of try-on is a renderer + pose, not a platform | Third-party SDK (DeepAR/Wannaby/Banuba): recurring licence, per-MAU pricing, model format lock-in, camera frames leave the app — revisit only if delivery speed becomes worth the cost |
| **D2** | ✅ **DECIDED 2026-09-28 — Filament/gltfio driven directly, in the new package `tryon`** (the V0 spike's throwaway code stays in `artryon`, so retiring the spike cannot delete the production renderer). The original choice (SceneView + Compose) was **re-opened by its own packaged cost** (findings §5.3: +27.7 MB all-ABI, ≈+15.7 MB/device, against the §2.11 budget) and then **settled by measuring the alternative** (§5.5): `filament-android` + `gltfio-android` alone is **10,580,933 B (10.09 MiB) cheaper all-ABI** and **≈+6.4 MB per arm64 device — inside the budget**, with zero Compose dex and none of SceneView's `.filamat`/`.ktx` assets. `ArTryOnView` therefore hosts Filament directly in a `SurfaceView` inside the `PlatformView`; the shipped `ar_foot_scan` view stays **frozen**, and ARCore stays 1.54.0 | **Trade accepted:** the camera background, plane rendering and lighting setup SceneView supplied are now ours to write, along with its glTF conveniences (`rememberModelInstance`, `FileLoader`, `FileCache`) and its ARCore extension functions (findings F5 — the plain ARCore calls in that table are what the spike already uses). **Rejected:** a hand-rolled GLSL pass (weeks, worse lighting); Sceneform (archived); SceneView + Compose as shipped (viable, but it does not fit the budget without R8 shrinking Compose, which nobody has measured — findings §5.4 item 1) |
| **D3** | **Detection stays in Dart**; the try-on sends compact pose frames to native at ≥5 Hz | The detector is 43 KB of tuned, tested logic. Channel cost for 5 tiny messages/s is negligible; native gets world projection + smoothing | Porting detection to Kotlin (duplication + two places to tune); or running AT_DETECTION off Dart entirely |
| **D4** | **Uniform scale from the size chart**, never non-uniform mesh scaling | EU step is a known length grade (6.67 mm). Non-uniform scale shears normals and looks wrong on any curved last | Per-size models (asset explosion); per-axis stretch (artefacts) |
| **D5** | **Mask-stencil occlusion in v1**, Depth API later | We already produce a per-pixel foot mask to detect feet. Using it as a stencil (foot pixels drawn in front of the shoe) is nearly free and correct for the dominant top-down view | Full Depth API occlusion in v1 (device coverage + cost); ignoring occlusion (shoe visibly covers the foot — unacceptable) |
| **D6** | **New platform view + new channels**, not an extension of `ar_foot_scan` | The scan flow is shipped, tuned and load-bearing for sizing. A separate `ar_try_on` view can be deleted or feature-flagged without touching it | Bolting a second mode onto `ArFootSizingView` (couples two shipped features, risks measurement regressions) |
| **D7** | **No schema change to `products` beyond nullable columns**; fit specs live on the product row | Matches how `sale_price`/`sale_*_at` were added; nullable ⇒ old rows are valid, no backfill, no RLS work | A `product_fit_specs` table (justified only when per-size specs arrive — see §2.7.3) |
| **D8** | **Graceful degradation everywhere**: no model → existing simulated screen; no spec sheet → no fit verdict; unsupported device → simulated screen + size guide | The feature must never be a dead end, and the current screen is already a decent fallback | A hard "3D only" requirement, which would strand most of the catalog on day one |

### 2.3 Flutter layer

**New / changed Dart files**

| File | Role |
|---|---|
| `lib/providers/try_on/try_on_phase.dart` | `TryOnPhase { idle, loadingModel, modelReady, arStarting, arFailed, searching, locked, lost, capturing, error }` + one-shot events, mirroring the v2 `scan_phase.dart` style (typed states, no English strings in the controller) — **built 2026-09-28**. Two clarifications the implementation adds: `locked`/`lost`/`capturing` are **V4's** foot-tracking states (declared here because this document fixes the set, so V4 fills them rather than renaming the machine under a screen that already renders it), and the phase describes the **session** while the mode describes the **surface** — which is why "no model" is `idle`, not `error` |
| `lib/providers/try_on/try_on_session_controller.dart` | The brain, cloned structurally from `ScanSessionController`: starts AR, resolves the model, drives the detection loop at ≥5 Hz, publishes pose and lock state, owns retry/backoff, disposes timers. Injected `ArTryOnChannel` + detector factory for tests — **built 2026-09-28 for the part above the loop**: `prepareModel()` (resolve → verify → hand over) and `startAr({required bool arViewReady})` (the F17 guard), 19 tests, no device and no native view. **The detection loop, pose publishing, lock state and retry/backoff are V4** and are not built, because they belong with foot tracking rather than with a floor-placed shoe |
| `lib/services/ar_try_on_channel.dart` | Sibling of `ArCoreChannel`: method/event wrappers + typed payloads (`TryOnModelSpec`, `FootPoseFrame`, `TryOnPerf`, `TryOnStartResult`) — **the Dart half is built 2026-09-28** (23 contract tests: `TryOnModelSpec`, `TryOnPerf`, `TryOnStartResult`, 8 method wrappers — `startSession`, `stopSession`, `setModel`, `setSize`, `setColor`, `placeShoe`, `captureScreenshot`, `setTryOnMode` — and a fail-closed event parser). It is a **subset of §2.8 on purpose**: `setFootPose`/`setFootMask` and the `footLock` event are V4, and a wrapper for a conversation neither side can have yet is a guess, not a contract. The native half is **built 2026-09-28** in `com.solevision.app.tryon` (`ArTryOnPlugin` + `ArTryOnView`, findings §5.6), so both ends of this table are now implemented and the failure vocabulary is enforced rather than described. On a build without the plugin every call still throws `MissingPluginException`, which the gate treats as an ordinary AR failure — the simulated screen, not a bug. V4's `setFootPose`/`setFootMask` and the `footLock` event remain absent on both ends, deliberately |
| `lib/services/shoe_model_service.dart` | Resolve product → model row (per-variant override → product default → none); download to app files dir; cache keyed by `modelId + version + sha256`; evict LRU above a byte budget — **built 2026-09-27** (V2.5, with the strict-throws-on-mismatch contract the renderer needs) |
| `lib/services/try_on_prefetch.dart` | The **prefetch policy** — the two seams above plus the rule that no failure may reach the page. V2.6, **built 2026-09-28**: resolve for one selection, ensure it is local, and answer with one of four outcomes (`disabled` / `noModel` / `alreadyCached` / `downloaded` / `failed`) instead of throwing; concurrent calls for one selection share a read. Mounted by `product_detail_screen.dart` behind `AppConstants.tryOnPrefetchEnabled` (**on since 2026-09-28** — nothing can consume a warm cache until V3, but the table read is live, so this path is exercised in production). **Known gap, now open rather than covered:** no metered-connection guard yet |
| `lib/utils/fit_engine.dart` | Pure Dart fit math (§2.6) — unit-testable with zero Flutter deps, the `size_match.dart` precedent |
| `lib/utils/shoe_model_resolver.dart` | Pure mapping: `(product, variant/color, selected size) → {modelId?, materialOverrides, scale}` |
| `lib/screens/customer/ar_try_on_screen.dart` | `ARVirtualFitScreen` evolved: keeps every piece of chrome that works (carousel, size chips, availability sheet, fly-to-cart, tutorial) and swaps the placeholder for the platform view when capability says so |
| `lib/widgets/try_on/fit_verdict_card.dart` | "Your fit: true to size · 9 mm toe room" card, reused on product detail, cart and the try-on screen |
| `lib/widgets/try_on/try_on_coach_card.dart` | Lock/lost/light coaching, same visual language as the scan's coach card |

**Mode selection (the seam that keeps the fallback alive)**

```dart
enum TryOnMode { real, simulated }

TryOnMode resolveTryOnMode({required bool arSupported, required bool modelAvailable}) =>
    (arSupported && modelAvailable) ? TryOnMode.real : TryOnMode.simulated;
```

`ArTryOnScreen` renders the real platform view for `real`, and the existing `ARViewPlaceholder` for `simulated`. Same route, same constructor (`preselectedProduct`), so `product_detail_screen.dart` does not change its call site. **Built 2026-09-28 (V3.5):** `ARVirtualFitScreen` threads `arView: _tryOnArView()` into the placeholder's existing seam, and the reason the call sites did not change is that the availability answer was threaded a phase earlier. The two things worth reading the code for are the *ordering* (`startAr` is called from `onPlatformViewCreated`, so the view exists before the session is asked for — F17 by construction) and the *failure direction* (a degraded session replaces the view rather than leaving it blank, which is asserted by a widget test that degrades one mid-flight)

### 2.4 Native layer (`com.solevision.app.artryon`)

| Class | Responsibility |
|---|---|
| `ArTryOnPlugin` | `registerViewFactory("ar_try_on", …)`; MethodChannel `com.solevision/ar_try_on`; EventChannel `com.solevision/ar_try_on/events`. Registered in `MainActivity.configureFlutterEngine` next to the existing plugin |
| `ArTryOnView` | PlatformView hosting **Filament directly** (D2, decided 2026-09-28) — no SceneView and no Compose, so this class also owns the camera background, plane rendering and lighting that SceneView used to supply; ARCore session lifecycle; honours the existing `ArSessionStartResult` contract (`unsupported_device`, `needs_install`, `user_opted_out`, `timeout`, `error`) so Flutter handles failures identically to the scan. **Built 2026-09-28** (`android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt`, findings §5.6): one render thread owns the engine, renderer, swapchain, scene, view and camera; ARCore's pose and projection drive the Filament camera; key/fill lights with the key from ARCore's ambient estimate; model swap is destroy-then-create with the measured flush-and-retry; floor placement is ARCore's `hitTest` with an analytic floor-ray fallback. **Not built, for a measured reason (F20):** the camera feed and the plane visual — the Filament artifacts ship no `.filamat` assets at all. Compiles; **unrun on any device** |
| `ModelCache` | Downloads (Dart hands over an already-downloaded file path in v1 — native does no HTTP), validates sha256, keeps files in `filesDir/shoe_models/`, exposes eviction |
| `ShoeModelNode` | Wraps the loaded `ModelNode`: applies uniform scale from the size chart, applies material overrides for the chosen colour, exposes `setScaleForSize(euSize)`, `setMaterialOverrides(map)`, `setStencilMask(texture)` |
| `FootPoseTracker` | Consumes pose frames via `setFootPose`; `hitTestBatch` → world points; builds basis `{forward = toe − heel, up = floor normal, lateral = forward × up}`; one-euro filter per component; anchors on the floor plane; lock hysteresis (enter at quality ≥ 0.7, leave below 0.45); re-anchors on drift |
| `PerfProbe` | Rolling fps/frame-time and model-load timing, emitted on the event channel |

**Why a new package rather than editing `arfoot/`:** the scan view is shipped, tuned, and the only thing that produces measurements customers rely on. D6 isolates that risk. Shared code is *copied deliberately* (session lifecycle + frame acquisition) and marked as debt; if a third AR screen ever appears, extract a shared `ArSessionController` then — not now.

### 2.5 Model asset pipeline

**§2.5.1 Authoring contract (the most important spec in this doc)** — the step-by-step partner version of this table is `docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md`; if the two disagree, this table wins.

| Property | Requirement |
|---|---|
| Format | Single-file **`.glb`** (glTF 2.0 binary). Textures embedded. No external `.bin`/image references |
| Units / up-axis | Metres, Y-up (Filament/ARCore world units are metres — an asset authored in mm must ship a 0.001 scale, validated by bbox) |
| Origin | Heel-bottom-centre at the world origin, resting on the ground plane |
| Forward | Toe along **+Z** in the asset's own frame |
| Reference size | Authored at **EU 42** (or explicitly declared in `product_models.authored_size_eu`), and the **physical sample that was scanned must be that size** |
| Dimensions | **True measurements** — and this is where two different lengths live. **(a) External length** (`product_models.authored_length_mm`): the shoe's outside heel-to-toe length, the mesh's Z-bbox target (±5 mm). It drives **rendering scale**. **(b) Internal last length** (`products.last_length_mm`, §2.7.3): how long the inside is, what a foot actually sits in. It drives the **fit verdict**. For a leather shoe the internal last is typically **8–15 mm shorter** than the external length; never substitute one for the other |
| Side | **One shoe per asset**, declared in `product_models.shoe_side` (default `right`); the renderer mirrors it for the other foot. Visibly asymmetric designs (a single outer strap) get a second asset per product |
| Materials | PBR metallic-roughness, part-named (`upper`, `sole`, `laces`, `lining`, `heel`) so colour swaps can target parts |
| Budget | ≤ 60 k triangles, ≤ 2 texture sets at ≤ 1024², ≤ 5 MB total file |
| Compression | **Draco / meshopt geometry compression and KTX2 textures are not approved until roadmap V0.7 proves the renderer decodes them.** Ship uncompressed until then |
| Alignment escape hatch | Optional `alignment_json` per model (heel offset mm, yaw offset deg) for exports that fight the contract |

**§2.5.2 Scale math (why one model serves the whole size run)**

```
externalLength(size) = authoredLength + (size − authoredSize) * EU_LENGTH_STEP_MM   // 6.67 mm/step
externalScale        = externalLength(selectedSize) / authoredLength                 // Y and X/Z equally
worldSizeMetres      = authoredModelMetres * externalScale
```

`authoredLength` is the **external** length of the physical sample (§2.5.1); the same 6.67 mm/EU step applies to the internal last in §2.6, but the two numbers never mix. No per-size assets, no non-uniform stretching, one download per product. The size chart is the *only* place scale comes from, which is what keeps the rendered shoe honest about what is in stock.

**§2.5.3 Resolution order**

```
selected variant_id → product_models row (per-colour override)   ← optional per-colour assets
        else         → product_models row (product default)
        else         → no model → TryOnMode.simulated
```

**§2.5.4 Validation** — client-side on upload (bbox vs declared dims, poly count, file size, GLB magic bytes, required material names) and, ~~in a later phase,~~ **since 2026-09-28 (V2.4)**, the same checks repeated in an Edge Function so a bad asset cannot reach the catalog via the API. Client validation alone is *not* a security boundary; it exists to give sellers fast feedback. **Repeated is not enough either, and that is the part 2026-09-28 added:** a rule set the caller may skip is advice, so the transition into `status='active'` is now refused by a database trigger to every role but the service role — the function is the only door, and the door is in Postgres, where the client cannot argue with it.

**Built 2026-09-27 (V2.7).** The rule set above now exists as code, not prose: `lib/utils/glb_validator.dart` is pure Dart (`dart:io`-free, so no Flutter dep either) and `tool/validate_glb.dart` is the CLI around it — 11 checks, a pass/fail table, `--json`, and exit codes 0/1/2. That library is the **executable form of this contract**: V2.3's client validation calls it directly, and V2.4's Edge Function runs on Deno/TypeScript and therefore **mirrors** it — the check names in the report are the interface the two sides share. A file that passes the CLI and fails upload is a bug in one of the two, not a reviewer's judgement call. The tool also states its own limits: toe-vs-heel is not decidable from a bounding box, and appearance (de-lit albedo, likeness, on-device fps) is not decidable from bytes at all, so those stay reviewer rows in the guide's §5.2 checklist.

**The ingest step arrived 2026-09-28 (V2.7), and it is the point where this section's contract meets a real file.** A partner's export failed 7 of the 11 rows without a single modelling defect: the rotation that makes a Blender scene Y-up had been left **on the root node** rather than applied, the length ran along X, the mesh was 4.30× life size, the origin was mid-shoe, three textures were 4096², and the mesh carried one material the colour swap cannot address. `lib/utils/glb_normalizer.dart` (pure Dart, `tool/prepare_shoe_model.dart` as its CLI) performs that arithmetic — bake the node transform into the vertices *and* the normals, yaw the long axis onto +Z so the toe can be named, scale to the declared external length, translate to heel-bottom-centre, re-bake every image to ≤1024², rename the parts and optionally cut a sole band. Two properties keep it honest. **It refuses what it cannot verify:** Draco/meshopt geometry cannot be decompressed here and KTX2 cannot be decoded, so both produce the re-export instruction rather than a file with an unverifiable claim behind it. **It never invents a number the handover owns:** without `--external-length-mm` the mesh is re-axed and re-grounded at its authored scale and the scale row keeps failing, on purpose. The node-transform detail is the one worth remembering: because the validator and the server read **accessor bounds** while the renderer obeys the **node tree**, a file can be `orientation: FAIL` and render correctly at the same time — the normaliser makes those two agree by baking, which is also what §2.5.5's units row assumes is true. **The client caller arrived 2026-09-28 (V2.3):** the seller form's model section runs this library over the fetched bytes and renders the report, with the seller-facing copy and the publish gate in `lib/utils/shoe_model_upload.dart`, so a file that passes the CLI and then fails upload is now a bug rather than a judgement call — as this paragraph promised.

**Built 2026-09-28 (V2.4).** The layer this section described as "later" now exists, and the interesting decisions are three.

*Mirroring, and how the mirror is kept honest.* `supabase/functions/validate-shoe-model/index.ts` is the boundary and `supabase/functions/_shared/glb_validator.ts` is the rule set it runs — the same constants, the same 11 checks in the same order, the same detail sentences as `lib/utils/glb_validator.dart`. Two implementations of one contract drift by default, so `tool/check_glb_validator_parity.mjs` runs the Dart CLI and the TypeScript mirror over **22 fixtures** (the repo's bundled models, the `androidTest` draco/meshopt pair, and synthetic GLBs for the millimetre, Z-up, off-origin, external-reference, oversized-texture, triangle-cap, no-materials, unreferenced-mesh and missing-declaration branches) and diffs check names, order, statuses, detail strings, notes and the two measured numbers. All 22 agree; a divergence is a failing command, which is what §2.16's "the check names are the interface" needed in order to be a claim rather than a hope.

*What the server checks that nothing offline can.* The function re-reads the **row** first (with the service role, but with an explicit ownership test: `products → stores.owner_id` for the caller, or `is_admin()` evaluated through the caller's own client — an `active` row is world-readable, and "I can see it" must not become "I can re-validate it into rejection"), then downloads the object the row points at and hashes it against `product_models.sha256`. That digest is the device cache key V2.5 verifies every hit against, so a row whose bytes do not hash to it is a row that would fail on every customer's phone — nothing the CLI can see, and nothing the app can lie about without also lying to itself. The measured `triangle_count` and `file_size_bytes` are written back, so the two sides stay comparable.

*Why the function alone would still have been advisory, and what fixed it.* The `product_models` policies from §2.7.1 let a seller insert or update their own rows with **any** status, so `status='active'` was one curl away with a seller token, and the validator would have been a courtesy the app performs. `20260928120000_gate_product_model_active.sql` (one function, one `BEFORE INSERT OR UPDATE` trigger, no column and no policy change) refuses that transition from every JWT role except `service_role` — the role only the function has. Its nine branches were measured against the live schema inside `BEGIN … ROLLBACK` with RLS disabled in-transaction, so the trigger was the only thing that could refuse: authenticated is blocked on UPDATE *and* INSERT (42501), `draft`/`rejected` remain the seller's own work items, an already-active row can still be edited but not re-pointed at different bytes or re-hashed, `service_role` publishes freely, and taking a model down is never gated. `count(*)` afterwards still returned 0 and the trigger was gone — nothing persisted. **The migration is written and NOT applied** (see `supabase/MIGRATIONS_LIVE_STATUS.md`): the client-side half ships without it, because the app now writes `draft` and lets the server publish, so publishing works in both states and only the apply removes the bypass.

*What it has not done yet, stated plainly.* Nothing here has executed the function. There is no Deno runtime in this environment and no deploy was made, so what is verified is the rule set it runs (22-fixture parity against the Dart reference), the parser the app uses on its three answers (11 tests), its syntax, and the database gate it depends on (nine branches, rolled back). The first real request is a partner's first real upload (V2.9) — and until then `validate-shoe-model` is a boundary that exists and has never been leaned on.

*What it will not claim.* The response names the four reviewer rows on every call — toe-vs-heel direction (a bounding box is symmetric about that question), de-lit albedo, likeness, and on-device frame rate — so `ok: true` reads as "the bytes satisfy the contract", never as "this shoe is approved".

**§2.5.5 Blender appendix — axis mapping, export settings, master vs shipped files**

Blender is the authoring and finishing tool for this pipeline (no licence cost, built-in glTF 2.0 exporter, full control of origin/units/axes). The full working checklist is `SHOE_MODEL_AUTHORING_GUIDE.md`; this appendix records only the parts that are contract, not preference.

**Axis mapping.** Blender is Z-up with the front view facing −Y; glTF is Y-up. Export with the default "+Y Up" option, which maps `(x, y, z)_blender → (x, z, −y)_gltf`:

| Concept | In Blender (author like this) | In the shipped `.glb` |
|---|---|---|
| Toe direction | **−Y** (pointing at the front view) | **+Z** |
| Up | **+Z** | **+Y** |
| Origin | Heel-bottom-centre at **(0, 0, 0)**, sole resting on `z = 0` | Heel-bottom-centre at origin, sole on `y = 0` |
| Scene units | Metric, Unit Scale 1.0, Length: Metres | Metres |

The orientation must be fixed **in the Blender scene** and applied (**Ctrl+A → All Transforms**) before export. Rotating in the export dialog, or "fixing" the file afterwards, is how backwards or upright shoes reach production. Front view (Numpad 1) must show the toe; every object must read 0° rotation and 1.0 scale at export.

**Export settings (`File → Export → glTF 2.0`):**

| Setting | Value | Why |
|---|---|---|
| Format | **glTF Binary (.glb)** | Single file, textures embedded, one cache entry |
| Include | Selected/Visible only — the shoe, nothing else | Stray cameras, lights and the capture stand must not ship |
| Transform → +Y Up | **On** (default) | The mapping above |
| Apply Modifiers | On | Decimation/retopo modifiers must be baked in |
| Data → Materials / UVs / Normals / Tangents | On | Part names and PBR maps are load-bearing |
| Cameras / Lights / Punctual Lights | **Off** | The AR scene supplies its own lighting |
| Animation | Off | Nothing in this pipeline is animated (v1) |
| Compression (Draco) | **Off until V0.7 approves it** | See §2.5.1 Compression row |

**Master vs shipped files.** Two different artifacts with two different homes:

| Artifact | Contents | Stored where | Ships to device? |
|---|---|---|---|
| **Master** | `.blend` + raw capture frames + the reconstruction export + `declaration.txt` + validator output | The content store (partner handover drive / project asset storage), versioned by product + colourway + version | **No** — never in the app repo, never in the app bundle |
| **Shipped** | The single `.glb` | Supabase bucket `shoe-models`, referenced by a `product_models` row | Yes, on demand, then cached (§2.3 `ShoeModelService`) |

The `.glb` is a build product of the master, regenerable at any time (`<partner>_<product>_<colour>_v<version>.glb`); the master is the thing that must never be lost. `product_models.version` + `sha256` are the link between the two, and the cache key on device.

### 2.6 Fit engine (`lib/utils/fit_engine.dart`, pure Dart)

The fit engine turns two sets of millimetres into a verdict, and it ships **before** any 3D work — it is the piece customers feel even when rendering is off.

```
inputs   foot:  lengthMm, widthMm            (from FootMeasurementProvider; compensated values)
         shoe:  lastLengthMm(size), lastWidthMm(size), sizeStepMm = 6.67, widthGradeMm
                // INTERNAL last length (§2.7.3) — not the mesh's external length (§2.5.1)
output   FitVerdict { size, verdict: tooSmall | snug | true | roomy | tooBig,
                      toeAllowanceMm, widthAllowanceMm, confidence, reasons[] }
```

| Verdict band (defaults — **tune with artisan partners before trusting**) | Rule |
|---|---|
| `tooSmall` | `toeAllowance < 3 mm` or `widthAllowance < −1 mm` |
| `snug` | `3 ≤ toeAllowance < 8 mm` |
| `true` | `8 ≤ toeAllowance ≤ 14 mm` and `−1 ≤ widthAllowance ≤ 6 mm` |
| `roomy` | `toeAllowance > 14 mm` or `widthAllowance > 6 mm` |
| `tooBig` | `toeAllowance > 22 mm` |

**Bands are checked in table order, first match wins** — that ordering is the rule for the two cases the table does not spell out: a last 1 mm narrower than the foot reads `tooSmall` however much toe room there is (a foot that cannot enter the shoe is not a fit question), and a last 6 mm wider reads `roomy` even when the length is snug, because the size that fixes the length makes the width worse. The second case adds a reason naming the conflict — a different *last shape*, not a different size.

Confidence = scan confidence × spec completeness × how far the size is from the sample that was measured:

| Factor | Value | Why |
|---|---|---|
| scan quality | `overallConfidenceScore`, else `high/medium/low` → 0.9/0.7/0.5, else 0.75 | A 0.5-quality scan is a 0.5-quality verdict however complete the spec is |
| completeness | 0.85 with both widths, 0.60 length-only | A width comparison proves the last's shape as well as its length |
| extrapolation | 1.0 within ±2 sizes of `fit_ref_size_eu`, then −0.05 per size, floor 0.70 | The 6.67 mm/step grade is exact near the measured sample and an approximation further out |

No last specs ⇒ verdict suppressed entirely, not guessed. Past ±8 sizes the linear grade says nothing, so the engine returns no verdict at all. `isConfident` is the 0.45 floor (a hint, not an answer). Socks are already compensated in v2 payloads (`ScanResultsPayloadV2` carries compensated mm), so the engine does not re-apply a sock allowance. Width grading uses 2.0 mm per EU size until partners measure their own. Implausible numbers (a 40 mm "foot", a 4200 mm last) are refused rather than graded, and an out-of-range width on either side costs the width comparison but not the verdict.

**Built:** `lib/utils/fit_engine.dart` (V1.1/V1.2, pure Dart, 45 table-driven tests) + the four nullable columns of §2.7.3 (`supabase/migrations/20260927120000_add_product_fit_specs.sql`) + the write path (V1.4): the seller form's "3D & Fit" section, whose rules live in `lib/utils/fit_spec_form.dart` and whose column mapping lives only in `ProductService._fitSpecColumns` + the read surface (V1.5/V1.6, §2.6.1). `FitSpecs.fromProduct(row)` is the only reader of those columns, so a caller that gets specs has already passed validation; the seller-side rules are the same bounds, so a saved spec is one the engine will accept.

**§2.6.1 Where it surfaces — the product-detail card (V1.5/V1.6, built)**

`lib/widgets/fit_verdict_card.dart` mounts on product detail under the size grid, behind `AppConstants.virtualFitEnabled` (default **off**). It is two widgets on purpose: **`FitVerdictPanel`** draws a decided state — no providers, no flag, no network — which is what the tests drive and what the cart reuses (it takes a `products` row and the selected size string, so nothing about it is product-page-specific), while **`FitVerdictCard`** does the wiring: the kill switch, the customer's saved scan, and the one read it takes to have one.

The decision itself is pure and lives in `lib/utils/fit_verdict_state.dart` (`fitVerdictCardStateFor`, 21 tests). Every input it cannot answer with a verdict is a *different* reason to render nothing, and the visible non-verdict states are deliberately only two:

| Input | Card |
|---|---|
| flag off | nothing — and no query either |
| no usable last spec (`FitSpecs.fromProduct` null: unset, half-filled, implausible) | nothing (roadmap V1.6: "no specs ⇒ hide the card") |
| no size selected, or a size string with no number | nothing — a verdict is *about* a size |
| a size past ±8 EU steps from the measured sample | nothing (the engine declines to grade it) |
| no scan on hand | the **invitation** — the one thing this card may say without a scan, and a fact about the customer, not a claim about the shoe |
| a saved profile whose measurement is still being read | a quiet "checking" beat — never the invitation, so a scanned customer is not told to scan for a frame |
| the read failed | nothing: an unreadable scan cannot be told from an absent one, and inviting a scan the customer already did reads as a bug |
| a scan and a gradeable size | **the verdict**: phrase, the size it is about, every reason the engine wrote, and where the millimetres came from |

**The read is not optional, and this is the trap in the provider's shape:** `FootMeasurementProvider` holds a measurement in memory only after a scan *in the same session* (`loadLatest` is called nowhere else in the app), so a returning customer arrives with nothing and would be invited to scan feet they already scanned. The card therefore performs exactly one `loadLatest` per mount, and only when a spec-complete product could be answered by it.

**§2.6.2 Shadow mode (V1.7, built)**

The V1 exit criterion is that the verdict matches an artisan's opinion on 10 real products — a sample that has to exist **before** a customer reads a verdict. Shadow mode collects it: with `AppConstants.virtualFitShadowEnabled` on, every product page writes one `[FIT]` line recording what the card *would* say, and shows nothing.

- **The record is built from the same decision as the card**, with the switch forced on — so it can collect while `virtualFitEnabled` is off, and the log can never disagree with what the screen would have drawn. `lib/utils/fit_shadow.dart` is the pure formatter (13 tests); the card is its only caller.
- **The line is for a human.** `[FIT] product=… size=EU 42 band=trueToSize toe=10 width=3 conf=0.64 foot=265 last=275 why="…"` — the identity, the band and the millimetres behind it, the confidence, the customer's foot, the seller's last, and the engine's own reasons. A page with no verdict records **which rule** produced nothing (`would=noSpecs`, `would=needsScan`, `would=ungradeable`…), because "how often does this surface have nothing to say" is part of judging the flip. Two rules keep it honest: an in-flight read is not a record (a loading beat is not an outcome), and a record is written once per distinct line per mount, not once per rebuild.
- **One sink, and it is the seam.** `lib/services/fit_shadow_log.dart` has a single `logFitShadow`, which today writes through the temporary on-device diag channel (`nav_diag.log`, exportable from the foot-instructions screen (`FootInstructionsScreen`) — the same channel `PerfTrace` uses, for the same reason: no adb on the test device). When that scaffolding is retired, one function repoints at whatever replaces it — a `try_on_events` insert (§2.7.4) or Sentry breadcrumbs.
- **Two off-by-default switches, and a note on the data.** `virtualFitShadowEnabled` decides whether a record is built (and therefore whether the page reads the saved scan); `kNavDiagEnabled` decides whether the channel stores it. Both are off in a shipped build. While they are on, foot millimetres live in a local file the app can share only by explicit user action.

Later surfaces: try-on screen, cart, and — once P3/P4 of the size-aware plan land — checkout. The engine replaces nothing; it is the missing input those phases needed.

### 2.7 Backend & data

**§2.7.1 Storage**

| Bucket | Public read | Write | Limits |
|---|---|---|---|
| `shoe-models` | ✅ | authenticated seller owning the product (RLS policy mirroring `product-images`) | `file_size_limit: 8 MB`, `allowed_mime_types: ['model/gltf-binary']` |

**§2.7.2 New table**

```sql
CREATE TABLE public.product_models (
  id                    BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  product_id            UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE, -- products.id is UUID
  variant_id            TEXT,                   -- nullable per-colour override; NO FK — see the Built note (the hosted project's id is UUID, this repo's migration lineage is BIGINT)
  storage_path          TEXT NOT NULL,          -- shoe-models/<store>/<product>/<sha>.glb
  sha256                TEXT NOT NULL,          -- cache key + integrity check
  version               INT  NOT NULL DEFAULT 1,
  authored_size_eu      NUMERIC,                -- e.g. 42
  authored_length_mm    NUMERIC,                -- EXTERNAL heel-to-toe length of the physical sample (scale math, §2.5.2)
  shoe_side             TEXT NOT NULL DEFAULT 'right' CHECK (shoe_side IN ('left','right')), -- renderer mirrors for the other foot
  bbox_json             JSONB,                  -- {x:..,y:..,z:..} metres, for validation
  alignment_json        JSONB,                  -- optional {heelOffsetMm, yawOffsetDeg}
  material_map          JSONB,                  -- colour name → {part: {baseColorHex, metallic, roughness}}
  triangle_count        INT,
  file_size_bytes       INT,
  status                TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','rejected')),
  created_at, updated_at timestamptz DEFAULT now() NOT NULL
);
-- RLS: SELECT status='active' for everyone; seller ALL where owns the product; admin ALL.
```

**Built (2026-09-27):** the storage half is code — `supabase/migrations/20260927180000_add_try_on_models.sql` (the table above, its two unique indexes per version, the `updated_at` trigger, the RLS shape, and the public `shoe-models` bucket with 8 MB / `model/gltf-binary` limits and folder-scoped seller write policies; **applied 2026-09-28 and verified by object** — `product_models`: 17 columns, 4 indexes, 4 policies, **0 rows**; bucket `public = true`, `file_size_limit = 8388608` — `supabase/MIGRATIONS_LIVE_STATUS.md`) and `lib/services/shoe_model_service.dart` (V2.5: resolve → download → sha256 verify → cache → mtime-LRU evict at 50 MB, behind an injectable data source, with the pure rules in `lib/utils/shoe_model_resolver.dart`). **Its first caller arrived 2026-09-28 (V2.6):** the product page's prefetch, via `lib/services/try_on_prefetch.dart` — which is a separate class precisely because this service throws on an integrity mismatch (correct for a renderer with a screen to fall back to, wrong for a download nobody asked for) and the prefetch must never let that reach the page. V3's controller will still be the first *renderer* consumer, and no real asset exists to serve. **The write half exists too (2026-09-28, V2.2/V2.3):** `lib/services/shoe_model_upload_service.dart` fetches the handover link (byte cap enforced mid-download), runs the contract, and publishes through two injectable seams — storage first, then the row, because a row whose object is missing is a failed download on every launch while an object with no row is invisible. The digest is the storage filename, which makes an upload idempotent: re-publishing a file finds the existing row (`shoeModelReuseMatch`) and flips its status instead of writing a second row that would give this section's resolver two candidates for one asset. **The write path changed shape on 2026-09-28 (V2.4), and the change is the point of the phase:** `publish` no longer writes `status='active'` at all. It inserts every row as a **draft**, then hands that row to `validate-shoe-model` by id (`lib/services/shoe_model_server_validator.dart`); the function hashes the stored bytes against the row's `sha256`, runs the mirrored contract, and writes the verdict — `active`, or `rejected` with the failing rows. Three answers are kept distinct in the app: published, refused (the failing rows, surfaced as an error the seller can act on), and *no verdict* (a transport or 4xx/5xx failure — the row stays a draft and the seller is told to publish again). That third case is why this is not a silent degradation: a validator that throws would have turned "not judged" into "upload failed" and hidden a draft nobody is looking for. The database side — a trigger refusing `status='active'` to every role but `service_role` — is written and **not yet applied**; until it is, this is the app's discipline rather than the database's rule.

**One measured correction to the sketch above:** the hosted project's `product_variants.id` is **UUID** — the first apply of the migration was rejected with `42804: foreign key constraint "product_models_variant_id_fkey" cannot be implemented … bigint and uuid` — while a database rebuilt from this repo's migrations creates it as BIGINT (`20260601000000_base_schema.sql`, the drift `PROJECT_HANDOFF.md` already records, and CI's `supabase db reset` runs that lineage). No foreign key can be valid on both, so `variant_id` ships as **TEXT without an FK**: the app carries variant ids as strings (`resolveVariant` → `String?`), and a value that matches no variant simply loses the resolver, so the product-level default model applies — the degradation path, not an error. Converting the migration lineage's variant ids to UUID is the alignment that would let an FK exist; it is its own migration.

**§2.7.3 Fit spec columns (nullable, no backfill needed)**

```sql
ALTER TABLE public.products
  ADD COLUMN last_length_mm  NUMERIC,   -- internal shoe length at the reference size
  ADD COLUMN last_width_mm   NUMERIC,   -- internal width at the reference size
  ADD COLUMN heel_height_mm  NUMERIC,   -- for future silhouette/verdict nuance
  ADD COLUMN fit_ref_size_eu NUMERIC;   -- which size last_*_mm refer to
-- Shipped as 20260927120000_add_product_fit_specs.sql, with three additions to
-- this sketch: plausibility CHECKs mirroring the engine's bounds, a constraint
-- that a length without a reference size cannot exist, and NO default on
-- fit_ref_size_eu — the reference size is a fact about the measured sample, not
-- a convention, so a default would grade every size from a number nobody read.
```

Move these into a `product_fit_specs` table only when per-size specs (lasts that don't grade linearly) become a real need — that is a deliberate later migration, not a day-one table.

**§2.7.4 Analytics**

```sql
CREATE TABLE public.try_on_events (
  id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
  event TEXT NOT NULL,           -- 'session_start' | 'model_loaded' | 'foot_locked' | 'add_to_cart' | 'share' | 'error'
  size TEXT, color TEXT,
  model_id BIGINT, load_ms INT, avg_fps NUMERIC, duration_ms INT,
  error_reason TEXT,
  created_at timestamptz DEFAULT now() NOT NULL
);
-- RLS: INSERT own, SELECT admin. Retention: 90 days, pruned by a scheduled job (later phase).
```

### 2.8 Platform channel contracts (`com.solevision/ar_try_on`)

| Direction | Method / event | Payload | Notes |
|---|---|---|---|
| Dart → native | `startSession()` | → `{started, reason, message}` | Same shape as `ArSessionStartResult.fromNative` so failure UI is shared |
| | `stopSession()` | → `true` | |
| | `setModel(path, modelId, sha256, authoredLengthMm, alignmentJson)` | → `true` | Dart downloads; native never does HTTP in v1. `authoredLengthMm` is the **external** length (§2.5.1) |
| | `setSize(sizeEu, refSizeEu, lastLengthMm)` | → `true` | Recomputes uniform scale (§2.5.2) |
| | `setColor(materialOverrides)` | → `true` | GLB material part → colour |
| | `setFootPose({heelUv, toeUv, widthUv[2], confidence, footSide})` | → `true` | ≥5 Hz while searching/locked; drives `FootPoseTracker` |
| | `setFootMask({bytes32x32, confidence})` | → `true` | Downsampled mask for stencil occlusion; ~1 KB per frame |
| | `placeShoe(x, y)` | → `true` | Manual placement fallback when no foot is found |
| | `captureScreenshot()` | → `Uint8List` PNG | For the share sheet only; never auto-uploaded |
| | `setTryOnMode('foot'|'floor')` | → `true` | Capability/QA switch |
| native → Dart | `modelLoaded` | `{loadMs, triangles}` | |
| | `footLock` | `{locked, quality, side}` | Drives the coach card, not the render (render is native-resident) |
| | `perf` | `{avgFps, frameMs}` | Sampled every 5 s |
| | `error` | `{reason, message}` | e.g. `renderer_init_failed`, `model_parse_failed` |
| | `screenshot` | `{bytes}` | Optional async completion channel |

> **Lifecycle invariants are now enforced, not just recorded (2026-09-28).** F17 lives in `TryOnSessionController.startAr({required bool arViewReady})`: the caller must state that the platform view is mounted, and a `false` is refused outright, so the 15 s deadlock becomes `TryOnDegradeReason.arViewNotReady` on the fallback screen. F18 is `prepareModel()`'s early `setModel` call — legal before the view exists, because the plugin parks it. F19 is the `enabled` flag gating the model read, the download *and* every channel call, asserted by a test rather than trusted.

**Design rule:** the tight loop (pose → transform → render) never crosses the channel. Dart publishes ~5 Hz observations; native interpolates at 30–60 fps. Flutter is for chrome, choices and commerce — not for frame timing.

### 2.9 Coordinate systems and calibration

| Space | Units | Where it is produced | Where it is consumed |
|---|---|---|---|
| Sensor image | pixels, NV21, rotation in degrees | `acquireCameraFrame` | ML Kit via `MlKitInputHelper` |
| Normalised image UV | 0–1 | `FootDetector` (`FootPoint`) | Pose frames → native |
| Display view | logical pixels | `mapNormalizedToView` (centre-crop aware) | Guide boxes, overlays (unchanged) |
| ARCore world | **metres**, Y-up, session-relative | `hitTestBatch` | Distance math (mm), renderer anchors |
| Asset | metres, Y-up, heel at origin, toe +Z | §2.5.1 contract | `ModelNode` after uniform scale |

Calibration invariants:
1. Every mm the user sees comes from the **same compensated number** the sizing math used (the v2 E8 rule) — no second conversion path.
2. The rendered shoe's length must equal `lastLength(selectedSize)` in *world metres*, verifiable by a debug ruler overlay.
3. Foot pose is expressed as **[heel world point, forward axis, up axis]** — the renderer never re-derives orientation from the 2D mask.
4. Room for growth: measurement accuracy improves → try-on accuracy improves with no renderer change, because the renderer consumes millimetres, not pixels.

**Lifecycle invariants (learned the hard way in V0 — findings F17–F19, and they bind V3's production plugin):**
1. **The native view must exist before the AR session can start**, and the session starting is what answers `startSession`. So Dart renders the platform view *before* awaiting the session: showing the view only after the session resolves is a self-deadlock that ends in the 15 s timeout, on every device.
2. **A handover that arrives before the view exists is legal, not an error.** The native plugin parks `setModel` / `setSize` / `setColor` and applies them on view creation, so the Dart side is free to call them as soon as it has the data and must never depend on the view already being there. (The V0 plugin applied them through `currentView?.` and silently discarded the model.)
3. **The enable flag gates side effects, not just rendering** — permission prompt, channel traffic and model staging all sit behind it, so a build that did not ask for try-on does nothing at all.

### 2.10 Occlusion (v1 and later)

**The problem:** a live camera feed + a rendered shoe means the shoe draws on top of the customer's actual foot unless something hides it. Without occlusion, a shoe placed over a real foot looks like a sticker.

**v1 — mask stencil (nearly free):** the detector already produces a per-pixel foot mask. Downsample it to ~32×32, send ~1 KB per frame, and discard shoe fragments where the mask (dilated slightly) is set. For the dominant top-down "look down at my feet" pose — where the foot is between the camera and the shoe's interior — this is visually correct and costs one texture lookup.

**Later — Depth API:** ARCore's Depth API on supported devices gives a real depth buffer for proper intersection (foot in front of the *toe* of the shoe, laces over the instep). That is a V6-phase upgrade, not a requirement for launch.

**Honest limitation to document for stakeholders:** this is a *visual fitting aid*, not a physics-accurate simulation. No cloth deformation, no walking animation, no sock geometry. Accuracy is bounded by what the scan measures (length/width), so the fit verdict — not the render — remains the load-bearing claim.

### 2.11 Performance budgets

| Metric | Budget | Why |
|---|---|---|
| Sustained render fps (mid device: Snapdragon 6xx/7xx class) | ≥ 30 | Below 30 the tracking feels broken |
| Frame time (ARCore + Filament) | ≤ 33 ms | 30 fps floor |
| Model parse + first frame | ≤ 1.5 s warm cache / ≤ 4 s cold (network) | Prefetch on product detail hides most of it |
| GLB file | ≤ 5 MB (8 MB hard bucket limit) | Mobile data in Cebu |
| Triangles on screen | ≤ 60 k | Filament mid-tier budget |
| APK size delta (Filament + SceneView + loader) | ≤ 8 MB | **MEASURED AND FAILED (2026-09-27):** +27,716,757 B (+26.4 MiB) all-ABI, ≈+15.7 MB per device — same commit built with and without the dependency (`AR_TRY_ON_SPIKE_FINDINGS.md` §5.3). Composition: native libs 19.1 MB, Compose dex 15.8 MB uncompressed, SceneView Filament assets 11.8 MB uncompressed. The budget must be re-decided or the renderer route changed (findings D3/D4) |
| Session memory | ≤ 250 MB, no leak across 20 open/close cycles | Device QA matrix |
| Detector cadence | 5 Hz (200 ms) during try-on | Same as the scan; no battery regression |
| Cache budget | ≤ 50 MB, LRU eviction | Keep install lean |

### 2.12 Failure modes and degradation

| Failure | User-visible behaviour |
|---|---|
| Device unsupported / Play Services for AR missing (`unsupported_device`, `needs_install`) | Fall back to the simulated screen + size guide + fit verdict; never a dead end |
| No model for the product | Simulated screen; product detail hides the 3D badge |
| Model download fails | Try again silently once; then simulated screen with a subtle "3D preview unavailable" line |
| Model parses badly | `error{model_parse_failed}` → simulated screen + telemetry event (this is how bad assets get found) |
| No floor plane / poor light | Coach card ("move to a brighter spot, keep the floor in view"); after 15 s offer **manual placement** (`placeShoe`) |
| Foot not detected / lost mid-session | Shoe stays anchored with the last known pose for 1 s, then fades to search state; never snaps to a random pose |
| Tracking drift after a long session | `FootPoseTracker` re-anchors on the next confident pose (hysteresis in §2.4) |
| App backgrounded | Session paused (same ownership rule as the scan: PlatformView disposal owns teardown) |

### 2.13 Seller & admin tooling

| Surface | Change |
|---|---|
| `lib/screens/seller/add_edit_product_screen.dart` | **"3D & fit" — built (V1.4).** Fit spec fields (`last_length_mm`, `last_width_mm`, `heel_height_mm`, `fit_ref_size_eu`) |
| `lib/screens/customer/product_detail_screen.dart` | **Model prefetch — built 2026-09-28 (V2.6), behind `tryOnPrefetchEnabled` (on since the same day).** One fire-and-forget call on mount for the selection the page opens on (resolved through `resolveVariant`), ignored on every outcome, never awaited — a prefetch that could delay the first frame would be worse than none |
| `lib/screens/seller/add_edit_product_screen.dart` | **"3D Model (Optional)" — built 2026-09-28 (V2.2/V2.3), behind `shoeModelUploadEnabled` (on since the same day).** Handover **link** + declared external length + authored EU size + modelled foot; fetch with a mid-download byte cap (`dio`, https except loopback); the contract's pass/fail table rendered as the failing rows' own sentences plus declared-vs-mesh millimetres; publish-or-draft on Save. Rules: `lib/utils/shoe_model_upload.dart`. Writes: `lib/services/shoe_model_upload_service.dart`, storage **before** the row. **Deferred with reasons:** the file picker, the per-colour override (§2.7.2's `variant_id` is a variant, not a colour), and the material-part → colour map (no paint value exists on a product's colours) |
| Model preview | **Not built.** A static thumbnail rendered from the GLB (server or client) so sellers see what customers will see before publishing; a "preview try-on" button that opens `ArTryOnScreen` in a dev/seller flow is a later nicety. V2.2 shipped without it: the report tells a seller the file is *buildable*, and only a render can tell them it looks right |
| Admin | Existing admin portal product views gain model status (`draft/active/rejected`) and a re-validate action; no new admin screen in v1 |
| Education | One page of guidance ("how to get a model made") — the practical bottleneck is asset production, not code (see the roadmap's content plan) |

### 2.14 Security & privacy

| Concern | Position |
|---|---|
| Camera frames | Processed **on-device only** (ARCore + ML Kit); never uploaded, never persisted. Existing behaviour — the try-on does not change it |
| Foot masks | Ephemeral in-memory textures; not stored |
| Measurements | Existing `foot_measurements` rows; personal but already protected by existing RLS |
| Screenshots | User-initiated, shared through the OS share sheet, never auto-uploaded |
| Model assets | Public read (they are catalog content). Writes restricted by RLS to the owning seller |
| Analytics | `try_on_events` carries no images and no mm values; product_id + coarse performance only |
| Permissions | Camera only (already granted by the scan flow); no new permissions |

### 2.15 Testing strategy

| Layer | Approach | Precedent in repo |
|---|---|---|
| Fit engine | Pure Dart unit tests, table-driven over length/width allowance bands | `test/utils/cart_helpers_test.dart` style |
| Model resolver | Unit tests for override → default → none, and for colour→part mapping | `test/utils/*` |
| `TryOnSessionController` | `fake_async` + injected fake channel/detector; phase transitions, lock hysteresis, retry/backoff, disposal | `test/providers/v2/scan_session_controller_test.dart` |
| `ShoeModelService` | Cache key/eviction tests with a temp dir + mocked storage client | `test/services/*` |
| Native pose math (Kotlin) | JVM unit tests for basis construction, raycast null-handling, one-euro filter, scale math | new (`android/app/src/test/…`) |
| Renderer | Instrumented smoke test: load a 2-triangle fixture GLB, assert first frame and no GL error | new |
| Widgets | Chrome tests for the try-on screen's simulated mode (no native view needed in tests) | `test/widgets/foot_size_v2/*` |
| Device matrix | Low/mid/flagship, Android 9→15, portrait/landscape, bright/dark rooms | manual, per roadmap V3/V5 gates |
| Regression guard | The scan flows must keep passing untouched — `flutter analyze lib test && flutter test` before every phase | repo convention |

### 2.16 File map — reuse vs new

**Reused unchanged:** `ar_core_channel.dart` (as a pattern), `foot_detector.dart`, `mlkit_segmentation_foot_detector.dart`, `ar_foot_measurement_pipeline.dart` (`TemporalFootGate`, sample stats), `foot_measurement_utils.dart`, `cart_helpers.dart`, `size_key.dart`, `size_match.dart`, `foot_measurement_provider.dart`, `AuthProvider.saveFootProfile`, `FlyToOrderAnimation`, `ARViewPlaceholder` (fallback), `ProductProvider`, `CartProvider`.

**New files:** §2.3 (Dart) and §2.4 (Kotlin) tables, plus:

```
supabase/migrations/<ts>_add_try_on_models.sql   -- bucket + product_models + products columns
supabase/migrations/<ts>_add_try_on_events.sql   -- analytics table
supabase/functions/validate-shoe-model/          -- (V2.4, built 2026-09-28) server-side GLB validation: reads the row, hashes the stored bytes, runs the contract, writes the verdict
supabase/functions/_shared/glb_validator.ts       -- (V2.4) the mirrored rule set (Deno/TypeScript, no enum/parameter-property syntax so Node can run it too)
tool/check_glb_validator_parity.mjs               -- (V2.4) diffs the Dart reference against the TypeScript mirror over 22 fixtures; exit 1 on divergence
supabase/migrations/<ts>_gate_product_model_active.sql  -- (V2.4) the trigger: 'active' is service-role only, i.e. only validate-shoe-model may publish
lib/utils/glb_validator.dart                      -- the authoring contract as code (V2.7, built): pure, dart:io-free
lib/utils/glb_normalizer.dart                     -- (V2.7, built 2026-09-28) the contract's ingest step: bake the node transform, re-axis, rescale to the declared length, ground, re-bake textures, rename parts; pure, dart:io-free
tool/prepare_shoe_model.dart                      -- (V2.7, built) the CLI around it; refuses Draco/meshopt and KTX2 rather than mishandling them
test/utils/glb_normalizer_test.dart               -- (V2.7) 16 tests, incl. a round-trip over the bundled placeholder
lib/services/shoe_model_server_validator.dart     -- (V2.4) the Dart seam to the function + the three-way verdict (validated / refused / no verdict)
lib/utils/shoe_model_resolver.dart                -- pure resolution rules (V2.5, built)
tool/validate_glb.dart                            -- offline validator CLI (V2.7, built) used by the asset pipeline
test/utils/fit_engine_test.dart
test/utils/glb_validator_test.dart
test/utils/shoe_model_resolver_test.dart
test/providers/try_on/try_on_session_controller_test.dart
test/services/shoe_model_service_test.dart
```

**Do not touch:** `android/.../arfoot/*` (the shipped scan), `foot_size_v2/*` screens, `foot_measurements` schema.

---

## 3. Rejected alternatives (and when to revisit)

| Alternative | Why not now | Revisit if |
|---|---|---|
| Third-party try-on SDK | Recurring licence cost, per-MAU pricing, asset lock-in, camera frames processed by a vendor. The app already owns an AR stack | Timeline pressure makes 8–11 weeks of native work unacceptable, and budget exists for a licence |
| WebAR / WebView try-on | Throws away the ARCore + ML Kit investment; WebView camera performance and glTF fidelity are worse than native Filament; offline/caching story is worse | The try-on must also ship on iOS without writing ARKit code |
| Hand-written GL glTF renderer in `arfoot/` | Weeks of shader work for lighting/normals/shadows that Filament gives for free; risks regressions in the shipped scan view | Never, unless SceneView's licence/size becomes a blocker |
| Flat 2D overlay compositing (scaled shoe photos) | Cheap, but the app's headline feature would look flat; also fails for colour/angle variety | As a per-product fallback for catalog items that will never have 3D assets (worth considering as a V6 enhancement) |
| Photogrammetry in-app (customer scans their own shoe) | Completely different pipeline (multi-view capture + reconstruction); heavy on device | Out of scope; would be its own project |
| Sceneform | Archived by Google | Never; SceneView is the maintained Filament path |

---

## 4. Open questions

| # | Question | Who decides / how it gets answered |
|---|---|---|
| Q1 | How do artisan partners produce 20–50 launch models? (photogrammetry service, CAD conversion, manual modelling) | Product + partner workshop; feeds the roadmap's content plan |
| Q2 | Do we need per-colour assets or is a material map enough? | V2 pilot with 3 real products |
| Q3 | Is the mask-stencil composite good enough on real feet, or does depth occlusion need to be pulled forward? | V4 on-device review with 10 real products |
| Q4 | Do sellers understand "last length" well enough to fill the field, or should we derive it from a size-chart upload? | Seller interviews; may add a "measure your sample" flow |
| Q5 | Does the fit verdict or the 3D render move the needle more? | V1 (fit) vs V3 (render) telemetry comparison — this is why V1 ships first |
| Q6 | Minimum viable model count for the feature to feel real? | Product call; the roadmap assumes "hero set first" |
| Q7 | **Ship SceneView + Compose and accept a +27.7 MB APK, or drive Filament/gltfio directly (≈+6.7 MB/device, but we build the camera/plane/lighting plumbing ourselves)?** | Engineering + product. Inputs are measured, not estimated: `AR_TRY_ON_SPIKE_FINDINGS.md` §5.3–§5.4. Blocks roadmap V0 exit (V0.7) and the re-decision of §2.11's budget |

---

## 5. Glossary

| Term | Meaning here |
|---|---|
| **Fit pillar** | Knowing the customer's true size (AR scan, mm measurements, size verdict) |
| **Try-on pillar** | Showing a specific product on the customer's foot |
| **Last** | The foot-shaped form a shoe is built around; "last length" is the shoe's internal length, always longer than the foot (toe allowance) |
| **Mask stencil occlusion** | Using the segmentation mask to hide rendered shoe pixels behind the real foot — the v1 occlusion trick |
| **Pose frame** | `{heel, toe, width points, confidence, side}` at ~5 Hz — everything the renderer needs to place a shoe |
| **Uniform scale** | One scale factor for the whole model, derived from the size chart; never per-axis stretching |
| **Degradation path** | Falling back to the simulated screen (or to nothing on the product page) instead of failing |

---

*SoleVision / CUFMAI — Virtual Fitting Architecture v1.2.0 — September 27, 2026.*
*Update this document whenever a decision in §2.2 changes, not just when phases finish.*
