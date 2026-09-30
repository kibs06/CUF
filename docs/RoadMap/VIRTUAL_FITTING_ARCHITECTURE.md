# Virtual Fitting — Architecture

**Version:** 1.4.15
**Created:** September 27, 2026
**Updated:** September 28, 2026 — **§2.5.6's notices now take the seller somewhere, and the deep link found a delivery bug two phases deep (V2.14).** Two halves. **The tap:** a notice has carried `metadata.product_id` since V2.12 — pinned by an assertion written precisely because nothing read it — and now routes to the product with its **actions sheet already up**, which is where the request row and the model both live. The rule is pure (`lib/utils/model_notice.dart`) and refuses more than it accepts: only the `models` category, only a non-blank id, and only a product still in the seller's own catalog (silently doing nothing is bad, opening someone else's product is worse). **And the finding:** those notices were written to `public.notifications`, keyed to the seller's USER, a table the seller app **never renders** — that feed belongs to the customer shell, while a seller's session lands in `SellerShell`, whose bell reads `seller_notifications`, store-scoped. So two phases of careful recipient work (the `profiles` join, the audit entry, eleven assertions that the right person was told) told the right person on a channel they cannot open. Both closing RPCs now write **both** rows in the same transaction, and the bell's `type` CHECK had to widen — which is how the phase found a second, older bug: the constraint never admitted `'new_message'`, the client has always inserted it, the failure is swallowed as a `debugPrint`, and the live project confirms it (39 `new_order` rows, 1 `low_stock`, **zero** message notices), so sellers have never been told about a message. The bell row is written **unguarded** (`store_id` comes from the request row and that column is `NOT NULL`) and the claim is machine-checked against the DDL rather than asserted in prose. 21 new Dart tests, 8 new pgTAP assertions (plan 52 → 60), analyzer clean, **2,135 pass / 8 skipped** — and and both SQL files have since reached the live project — the flow file in an older revision, and green in CI — so the flow is complete in code and every database path in it has now executed.
**Prev. update:** September 28, 2026 — **§2.5.6 tells the seller on the other ending too (V2.13), and it needed no new machinery at all.** V2.12 made a *fulfilled* ask audible; the ending that is not good news was still wordless, and it is the one a seller needs earliest — "the team could not make one" sat in the row for whoever happened to open the product's action sheet, so a week could pass with the seller waiting on something that had already stopped. `decline_shoe_model_request` now writes the same notice, in the same transaction, under the same `'models'` category: **the subject is the seller's request and the title carries the direction**, because §2.5.6's feed filters by subject rather than by polarity. Two details are the design. *(1) The reason travels with it* — the admin screen already refuses to send a decline without one (§2.5.6, P2), and a notice that dropped it would make that a cosmetic rule, so the seller reads the admin's own sentence and a blank reason degrades to one that stands alone. The RPC's blind `UPDATE` also gained a `RETURNING requested_by, product_id`, which is where the recipient becomes known; `FOUND` is unaffected by the `INTO` clause, so the not-found guard still means exactly what it did. *(2) A decline that changed nothing tells nobody* — an already-closed ask is refused and the suite pins that **no** notice is written, since "declined" about a live model is the worst thing this feature could say. **6 new pgTAP assertions** (plan 46 → 52), **no Dart change and no migration** — the category, its label/icon/colour and the enum contract test all already existed, which is exactly what a correct V2.12 buys — analyzer clean, **2,114 pass / 8 skipped**. Both SQL files have since reached the live project and the flow file is green in CI, so the flow is complete in code and every database path in it has now executed
**Prev. update:** September 28, 2026 — **§2.5.6 now ends the way it started: the seller is told (V2.12, P3), inside the transaction that closes the ask.** V2.10 gave a seller a way to *ask* and V2.11 gave the team a way to *answer*, and across both of those the answer told nobody — the stateful row in the product action sheet speaks only to a seller who opens it, which for a week of somebody else's work is silence. So `fulfil_shoe_model_request` writes the seller's notification **in the same transaction as the status change**: `fulfilled` and `told` cannot disagree, because either both land or neither does. Three things are worth reading. *(1) **The writer is the database, not the app, and that is the V2.4 rule again:*** an app-side send after the RPC would be skippable, and a notice a client may decline to send is a courtesy rather than a fact — the same reasoning that put the model gate in a trigger and the request rules in RPCs. *(2) **The recipient is the person who asked** (`requested_by`), not the store owner — for this table the same person, and the filer stays right if that ever stops being true — and the insert **joins `profiles`** so a missing recipient row inserts nothing rather than raising `23503` and taking the close down with it (the §2.14 audit's rule, reached by a join; a third shape, recorded there because no mechanical pattern covers it). *(3) **The category had to be its own migration** (`20260928130000_add_models_notification_category.sql`, sorting before `20260928140000`), because `ALTER TYPE … ADD VALUE` cannot be *used* in the transaction that adds it. **And the Dart mirror is where a silent bug was living:** `AppNotification._parseCategory` falls back to `unpaid`, so a label the database can produce with no Dart case does not error — it files "your 3D model is ready" under **Unpaid**, in the wrong filter, with the wrong icon and the wrong count. Nothing tested that list on either side; `test/services/notification_category_contract_test.dart` now pins the two enums in both directions and through the real parse path. 5 new pgTAP assertions (plan 41 → 46) and 4 new Dart tests; analyzer clean, **2,114 pass / 8 skipped**. **Unchanged:** both SQL files are written and not applied, so none of it has run — and a **decline** still tells a seller nothing, which §2.5.6 records as its own piece of work rather than smuggling it into this one
**Prev. update:** September 28, 2026 — **§2.5.6's second half is built: the team models the pair (V2.11, P2), and it needed a screen rather than a schema.** V2.10 gave the sellers who cannot produce a `.glb` a way to *ask*; the ask was then answerable only by someone with a terminal, a handover link and `tool/prepare_shoe_model.dart`, because §2.5.6's *Close as done* can only point at a model that already exists. So the queue gained **Upload a 3D model** — link → fetch → contract → publish → close, one sheet — and three properties are worth reading the code for. *(1) **It reuses §2.5.4's write path rather than a second one:*** `ShoeModelUploadService.publish` is still the only writer (bytes → **draft** row → `validate-shoe-model` decides), so nothing here writes `status='active'` and V2.4's trigger needs **no admin-shaped hole** — the admin's authority to *insert* was already in §2.7.1's policies (`is_admin()`), which is why this phase shipped without a migration at all. *(2) The seller's external measurement is **prefilled**, which is the exact opposite of §2.5.6's seller-side prefill and for the same reason:* the seller's form refuses the length because its only number was `products.last_length_mm` (the internal last, §2.7.3), while the admin is answering a measurement taken across the outside of the pair — the figure §2.5.2 scales to — so retyping it would only add a way to mistype it. *(3) A declaration more than ±5 mm from that measurement earns a **note, not a gate**,* and **"live but open" is its own ending:** the publish and the close are two writes, so a model that went live while the ask stayed open is named, reported in both halves and coloured amber — the one state that must not be rounded to "done" while the seller still reads "somebody is on it". §2.5.6's report also moved into **one** widget (`lib/widgets/shoe_model_report_card.dart`), because two surfaces now show it and "within tolerance" must not mean two things; the seller's form passes its publish switch in as the card's footer, and its ten existing widget tests pass unchanged. 23 new tests, analyzer clean, **2,110 pass / 8 skipped**. Behind a new switch, `AppConstants.adminModelUploadEnabled` (**off**), read through `adminModelUploadAllowed` = that flag **and** the pipeline's `shoeModelUploadEnabled`. **Unchanged:** the ask is still unanswerable on the live project, because the *close* is §2.5.6's RPC and the live copy of `20260928140000` is an older revision that has to be re-applied
**Prev. update:** September 28, 2026 — **§2.5.6 added: the request flow (V2.10) — the pipeline's second door, for the sellers the first one assumes away.** §2.5.4's upload path presumes a seller who can hand over a contract-compliant `.glb`, and the evidence against that presumption is this section's own history: the first real partner asset was a marketplace/AI export that failed 7 of the 11 rows and only passed after the normaliser ran on it. So the seller can now **ask** — a *Request a 3D model* row in the product action sheet, a four-field form, and an admin queue. Three things are worth reading the code for. *(1) The form asks in the seller's language, not in 3D's:* four fields measured with a ruler **outside** the shoe, and the one required number is the **external** length (§2.5.1 (a), the renderer's scale input, §2.5.2) — never `products.last_length_mm` (§2.7.3, the fit verdict's, 8–15 mm shorter). That is why the form prefills the heel and the size from the product's fit spec and **refuses to prefill the length**: a plausible wrong number in the one field that scales every mesh is worse than an empty box. *(2) `27` earns a message about centimetres,* not a range error — a centimetre figure parses fine and would size the shoe at four-tenths of life size, which is the most expensive mistake this feature could make. *(3) "Done" is a model, not a status:* `fulfil_shoe_model_request` requires the `model_id` to belong to *this* product **and** be `active`, and the table's own CHECK refuses `fulfilled` with a null `model_id`, so an admin cannot close an ask by typing a word. The database half is one table, five `SECURITY DEFINER` RPCs (file, withdraw, claim, fulfil, decline) and **zero seller write policies** — the rules (one open ask per product, only the store's owner may ask, not for a product that already has a live model) are multi-row invariants a policy cannot express — restated where a crafted client cannot skip them as a partial unique index and that CHECK. **Honest state as of this date: `20260928140000_add_shoe_model_requests.sql` was written and not applied, and — unlike V2.4's gate — it had not been measured inside a rolled-back transaction either**, because this time the deliberate choice was to let CI's `Supabase Migrations` job (`db reset` + 41 pgTAP assertions) be the first thing that applies it; the switch is off for the same reason a row whose RPC answers "function does not exist" is worse than no row. 59 new Dart tests, analyzer clean, **2,087 pass / 6 skipped**
**Prev. update:** September 28, 2026 — **§2.5.1's contract now has an ingest step, because the first real partner asset proved that a file can be *correct* and still fail the checks (V2.7).** The file was a marketplace/AI-generated shoe: 31.5 MiB, 49,954 triangles, three 4096² PBR maps, one material called `Material.001`, 1160.8 × 480.3 × 433.1 mm — and 7 of the 11 rows red for reasons that are all coordinate arithmetic: the scene's Z-up→Y-up rotation was left **on the node** (a distinction §2.5.1's checks cannot see, because they read accessor bounds, while the renderer honours the node — the file was simultaneously "failing" and "rendering upright"), the length ran along **X**, the scale was **4.30× life size**, the origin was mid-shoe, the textures were 4096², and one material cannot be repainted per part. `lib/utils/glb_normalizer.dart` + `tool/prepare_shoe_model.dart` are that repair: bake the node transform into the vertices and normals, yaw the length onto +Z, scale to the **declared** length (never invented), ground and centre at the heel-bottom, re-bake textures to ≤1024², rename parts, and — for a scan with a single material — cut a `sole` band geometrically with its area share reported. Two refusals are design, not gaps: Draco/meshopt geometry and KTX2 textures cannot be undone offline, so the tool declines and states the re-export instead of writing a file it cannot verify. What it cannot do is §2.5.1's whole undecidable list plus one more: it does not know which end is the toe (`--toe`, enforced as an explicit answer or a stated assumption) and it does not know the declared length. Measured on the real bytes: **31.48 MiB → 1.66 MiB, 270.0 × 111.7 × 100.7 mm, 11/11 PASS**; the bundled placeholder still passes all 11 after a pass over it (idempotence test). §2.5.1's contract is unchanged by any of this — the fixer serves the contract, it does not relax it
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
| `lib/screens/shared/shoe_preview_screen.dart` | — | `ShoePreviewScreen`: the full-screen 3D viewer, both doors. `new` takes a resolved model (the product page); `forProduct` resolves one (the seller's "3D fitting ready" row, `shoe_model_request_tile.dart`), with `showTryOn: false` so the AR flow stays the customer's. Mounts `ShoePreviewSection` (box + refusal handling + the AR pill) and owns the AR push and the pause flag |
| `lib/widgets/shoe_preview_3d.dart` | — | `ShoePreview3D` / `ShoePreviewSection` (the renderer box, its idle face, its honest refusal line, the QA banner) and `Sole3DIconButton`, the 3D icon on the product photograph |

**Entry point reality check (rewritten 2026-10-01):** the product page's only 3D entry is the **icon on the product photograph** (`Sole3DIconButton` in `product_detail_screen.dart`), which pushes `ShoePreviewScreen`; the "Try On in AR" pill lives inside that viewer's section, so **AR is two taps from a product page** and the pinned pill that used to sit above the buy bar is gone. The seller has a second door to the same viewer — the product action sheet's **"3D fitting ready"** row (`ShoeModelRequestTile`, V2.10), which resolves the model on the seller's device and draws it, so a seller can see what the shop is actually selling rather than reading that a row exists. `docs/AI/AR_TRY_ON_ARCHITECTURE.md` §2 claims home/store cards also launch it via `SoleProductCard.onTryOnTap` — that is **no longer true** in this codebase. Treat this section as canonical.

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

*Why the function alone would still have been advisory, and what fixed it.* The `product_models` policies from §2.7.1 let a seller insert or update their own rows with **any** status, so `status='active'` was one curl away with a seller token, and the validator would have been a courtesy the app performs. `20260928120000_gate_product_model_active.sql` (one function, one `BEFORE INSERT OR UPDATE` trigger, no column and no policy change) refuses that transition from every JWT role except `service_role` — the role only the function has. Its nine branches were measured against the live schema inside `BEGIN … ROLLBACK` with RLS disabled in-transaction, so the trigger was the only thing that could refuse: authenticated is blocked on UPDATE *and* INSERT (42501), `draft`/`rejected` remain the seller's own work items, an already-active row can still be edited but not re-pointed at different bytes or re-hashed, `service_role` publishes freely, and taking a model down is never gated. `count(*)` afterwards still returned 0 and the trigger was gone — nothing persisted. **The migration is applied on the live project** — its `trg_product_models_server_validation` trigger is present on `public.product_models` (checked 2026-09-28, see `supabase/MIGRATIONS_LIVE_STATUS.md`): the client-side half ships without it, because the app now writes `draft` and lets the server publish, so publishing works in both states and only the apply removes the bypass.

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

**§2.5.6 The request flow — when the seller cannot make the file (V2.10, built 2026-09-28)**

§2.5.1 and §2.5.2 both assume a seller who can hand over a contract-compliant `.glb`, and this market's sellers are local artisans. A pipeline with one door is a pipeline for sellers who do not exist yet, so the seller can now **ask** — and the ask is measured with a ruler rather than authored in Blender.

**The one number that matters is the external length, and the form refuses to guess it.** The seller is asked for the shoe's **outside** heel-to-toe length (§2.5.1 (a)) because that is what the renderer scales to (§2.5.2). `products.last_length_mm` (§2.7.3) is the *internal* last, 8–15 mm shorter, and substituting it would make every rendered shoe oversize. The form therefore prefills the heel height and the reference size from the product's own fit spec and **deliberately leaves the length empty even though that spec holds a length too** — one is a fact about the shoe's skin, the other about its inside, and they are not interchangeable. A typed `27` returns a sentence about **centimetres** (`write 270, not 27`) rather than a range error, because a centimetre figure is plausible to a parser while being off by 10×; the same hint is **not** applied to the heel, because a 2 mm heel is real.

**The state machine, and why it lives in the database.** `public.shoe_model_requests` holds one row per ask: `requested → in_progress → fulfilled | declined`, plus `cancelled` (the seller withdraws, and only while the ask is still `requested`). Five `SECURITY DEFINER` RPCs are the **only** write path — `request_shoe_model`, `cancel_shoe_model_request`, `claim_shoe_model_request`, `fulfil_shoe_model_request`, `decline_shoe_model_request` — and the table carries **no seller write policy at all**, because the rules are multi-row invariants a row-level policy cannot express: *one open ask per product*, *only the store's owner may ask*, and *a product that already has a live model needs no ask*. The first is restated where a crafted client cannot skip it, as the partial unique index `uq_shoe_model_requests_open ON (product_id) WHERE status IN ('requested','in_progress')`. The seller keeps a SELECT policy for their own store's rows; `UPDATE` is admin-only, which is what makes "whose desk is it on" (`assigned_to`) and the decline reason (`admin_note`) server facts rather than client claims.

**"Fulfilled" names a live model of the same product, enforced twice.** `fulfil_shoe_model_request(p_request_id, p_model_id, p_note)` refuses unless the model belongs to *this* product **and** its status is `active`, and the table's own `CHECK (status <> 'fulfilled' OR model_id IS NOT NULL)` refuses a fulfilled row with no model. An admin cannot close an ask by typing a status: the queue's "close as done" control is a **picker over the product's own live models**, with a plain answer when there are none instead of an empty picker. That is also the P1/P2 boundary stated in the schema — **P1 can only close against models published by the seller portal or the CLI, because the admin's own upload (P2) is not built.**

`model_id` is **BIGINT**, matching `product_models.id` (`GENERATED BY DEFAULT AS IDENTITY`) and *not* the uuid that `products.id` and most of the app's ids use. This is the type trap that already broke §2.7.2's `variant_id` once (`42804`), so it is written down here rather than left to a reviewer.

**The table is device-gated, and that is the deliberate side of the line.** The file ends with `install_device_gate_policies()` (§2.14), so a request row sits behind a trusted device like `orders` — it is store-private and carries a seller's own note about their stock. `product_models` is the opposite call and stays **exempt** (§2.7.1): an `active` row is world-readable catalog content holding a storage path, a digest and a triangle count, with no customer data at all. Two tables in one pipeline, two answers, each one written into the exemption list rather than implied.

**The second half: the team models the pair (P2, built 2026-09-28 as V2.11).** A door a seller can knock on and nobody can answer is not a feature, and *Close as done* can only point at a model that already exists — so the queue gained **Upload a 3D model**: paste a link, fetch, run the contract, publish, close. Four decisions are worth reading, and the first is the whole phase.

**It reuses §2.5.4's write path rather than adding one, and that is why it needed no migration.** `ShoeModelUploadService.publish` is still the only writer — bytes first, then a **draft** row, then `validate-shoe-model` decides — so the admin's upload passes the same server gate the seller's does and **nothing here writes `status='active'`**. The consequence is the inverse of what one expects from a new admin surface: there is no admin-shaped hole in V2.4's trigger, because there is no need for one. The authorisation was already there too — §2.7.1's `product_models` policies and the `shoe-models` storage policies both read `public.is_admin()`, and the function resolves an admin caller the same way — so this phase shipped with a switch and a screen and no DDL, which a reader of `MIGRATIONS_LIVE_STATUS.md` would be right to find surprising.

**The seller's measurement is prefilled — the opposite of §2.5.6's seller-side rule, reached from the same principle.** There, the length was deliberately left empty because the only number on hand was `products.last_length_mm`, the *internal* last, 8–15 mm short of the outside of the same shoe. Here the number on hand is the seller's own **external** measurement, taken with a ruler across the outside of the pair and sent for exactly this purpose: it is the figure §2.5.2 scales the mesh to, so retyping it would only add a way to mistype it. The heel and the size are the same quantity on both sides, so they travel too.

**And a declaration that drifts from it earns a note, not a gate.** The renderer scales every size to the **declared** length, so a declaration 20 mm out sizes every shoe wrong on every customer's foot — the failure guide §5 warns about, arriving through the one door this feature opened. It is still a warning rather than a refusal, because the admin may know the seller measured the wrong pair, and a rule that blocked a *correct* model would be the worse rule. The sentence names which number is bigger and what to check.

**"Live but open" is its own ending, and it is the one that had to be written down.** The publish and the close are two writes and they can disagree; the state in between — model live for customers, ask still open, seller still reading "somebody is on it" — is neither a success nor a failure, so it has a name (§2.5.6's `ShoeModelRequestModellingEnding.liveButOpen`), its copy states both halves, the toast is amber, and the queue re-reads itself. Collapsing it into either neighbour is how a seller ends up waiting forever for a model that already exists.

**One report, two surfaces.** `lib/widgets/shoe_model_report_card.dart` is §2.5.4's report extracted, because the seller's form and the admin's sheet now render the same bytes through the same library and "within tolerance" must not come to mean two things. The seller keeps its publish switch by passing it into the card as a footer, and the extraction is proven behaviour-preserving by its ten existing widget tests passing untouched.

**The third leg: the seller is told (P3, built 2026-09-28 as V2.12).** A flow where the asking party has to poll for the answer is a flow with one silent step in it, and this one had exactly that: `fulfil_shoe_model_request` set `fulfilled` and the seller's row changed colour — for a seller who opened the sheet. So the RPC now writes the notification itself, in the same transaction, and the design is three decisions.

**The database writes it, not the app.** An app-side send after the RPC would be skippable, and a notice a client may decline to send is a courtesy rather than a fact. This is V2.4's rule applied to a message instead of a status: the thing that must be true goes where the client cannot argue with it. The cost is stated plainly — the notice and the close are now one atomic act, so a notification that *cannot* be written takes the close with it. That direction is the right one: an ask that reads "closed" with nobody told is the failure this phase exists to remove.

**The recipient is the filer, and the insert joins `profiles`.** `requested_by` rather than the store's owner, because the person who asked is the person to answer, and for this table they are the same user (`request_shoe_model` refuses anyone who does not own the store). `notifications.user_id` is `NOT NULL REFERENCES profiles(id)` while `requested_by` references `auth.users(id)`, so the difference matters: a missing profile row would raise `23503` and abort the whole fulfil. Selecting `FROM public.profiles p … WHERE p.id = v_request.requested_by` makes that case insert **nothing** and lets the close stand. It is the §2.14 recipient rule (`docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md`), reached by a join rather than an `IS NOT NULL` test — a third shape, which is why the audit records it in prose: there is no nullable column and no local variable for a mechanical ratchet to name.

**The category is a migration of its own, and the Dart mirror is the part that was quietly broken.** `'models'` is added by `20260928130000_add_models_notification_category.sql`, which **must sort before** this section's flow file: `ALTER TYPE … ADD VALUE` may not be *used* in the transaction that adds it, and each migration is one transaction — the identical reason `20260913110000` exists for the reservation RPCs. Reusing `approval` was the alternative and it is wrong twice over, because the feed maps a category to a filter, an icon and a colour: it would put a 3D asset beside an application review in every filter a seller uses, and make the two indistinguishable in their unread badges. And on the Dart side `AppNotification._parseCategory` **defaults to `unpaid`**, so a label the database can produce with no Dart `case` does not fail loudly — it files "your 3D model is ready" under Unpaid, with a credit-card icon, in the wrong filter and the wrong count. Nothing checked that list, on either side, until this phase: `test/services/notification_category_contract_test.dart` reads the labels out of the migrations (`CREATE TYPE` plus every `ALTER TYPE … ADD VALUE`, so it cannot be fooled by a category added the newer way), asserts set equality with the Dart enum in both directions, and then pushes every label through `AppNotification.fromMap` — the code the feed actually runs.

**The other ending tells them too (V2.13, built the same day).** A fulfilled ask was the *good* news, and it was the only one that spoke — so the larger silence belonged to "the team could not make one", which a seller needs earliest of all. `decline_shoe_model_request` now writes the same notice, in the same transaction, under the same category, and the whole difference is in the title and the sentence: **the feed filters by subject, not by polarity**, so "3D model" holds both endings and the words say which one it is. *(1) The reason travels with it,* because the admin screen refuses to send a decline without one (§2.5.6, P2) and a notice that dropped it would make that requirement cosmetic — the seller reads the admin's own sentence, and a blank reason (an older client, a direct RPC call) degrades to one that stands on its own rather than to a dangling colon. The RPC's `UPDATE` also gained `RETURNING requested_by, product_id INTO …`: the update is where the recipient becomes known, and reading it off the row just written keeps the two in step by construction — `FOUND` is unaffected by the `INTO` clause, so the not-found guard still means exactly what it did. *(2) A decline that changed nothing tells nobody,* and that is asserted rather than assumed: an already-closed ask returns `success:false` and writes no notice, because the worst version of this feature is a seller told "declined" about a model that is live on their product. **No new machinery:** the category, its label, its icon, its colour and the enum contract test were all built for P3 — which is the useful shape of a phase like this, and the reason its diff is one RPC and six assertions.

**The tap works, and finding out where the notice went was worth more than the tap (V2.14, built the same day).** Two halves, and the second one is a correction of a mistake the first two phases made between them.

**The link itself.** A notice has carried `metadata.product_id` since V2.12 — pinned by an assertion that existed precisely because nothing read it — and now it routes: the seller's product opens with its **actions sheet already up**, which is where the request row and the model both live. The rule is pure (`lib/utils/model_notice.dart`) and it **refuses more than it accepts**: only the `models` category (metadata is one shared jsonb column, so a `product_id` on some other notice must not become this link), only a non-blank product id (a blank one must fail rather than match the first row whose id is also empty), and the sheet opens **only if the product is still in the seller's catalog**, because a link that fails silently is worse than one that says so and a link that opens *somebody else's* product is worse than both. The landing is `ManageProductsScreen.initialProductId` — the same screen the low-stock notification already deep-links to (§2.5.6's existing pattern), with the ids compared as strings and the lookup deferred rather than dropped while the shared catalog is still cold (it listens to the provider instead of polling it). A product deleted since the notice was written gets one sentence, not an empty sheet.

**⚠️ And the correction: the notice was being delivered to a table nobody in the seller app reads.** `public.notifications` is keyed to the seller's **user** and rendered only by the **customer shell's** feed (§2.16); a seller's session lands in `SellerShell`, whose bell reads `public.seller_notifications` — store-scoped rows with a `type` and a `reference_id`. So two phases of careful recipient work (the `profiles` join, the audit entry, eleven pgTAP assertions proving the right person was told) told exactly the right person on a channel they cannot open. **Both closing RPCs now write both rows, in the same transaction.** The per-user notice stays — it is the app's generic per-user channel, and deleting tested work to fix a *delivery* problem would trade a small duplication for a real regression — and a store-scoped `seller_notifications` row lands beside it (`type = 'model_request'`, `reference_id` = the product, `metadata` carrying the request id), which is what the bell renders and what the tap routes on. Same transaction, deliberately: *closed* and *told* still cannot disagree, and that property is what the first two phases got right.

**The bell insert is written unguarded, and that claim is machine-checked.** Its recipient is `shoe_model_requests.store_id`, a `NOT NULL` column of the row each function has just read or updated, so a guard would be unreachable code — and "no guard needed" is exactly the sort of assertion §2.14's audit exists to distrust. `test/services/notification_recipient_contract_test.dart` therefore accepts this shape only while it parses the `CREATE TABLE` for `shoe_model_requests`, finds `store_id uuid NOT NULL`, and confirms `orders.store_id` is still nullable (so the guard the other sites need is still needed). Make the column nullable later and the exemption expires on its own.

**The widened constraint found an older bug on the way past.** The bell's `type` is CHECKed, so `seller_notifications_type_check` had to admit `'model_request'` — and the same statement now admits `'new_message'`, which `SellerNotificationService.createNewMessage` has been inserting since the messaging work while the live project's constraint has never allowed it (checked 2026-09-28: 39 `new_order` rows, 1 `low_stock`, **zero** `new_message`). The violation is swallowed by that method's `catch` as a `debugPrint`, so **sellers have never been told about a message** — a silent failure of exactly the kind this section's tests exist to catch.

**Not built, deliberately.** Neither notice carries a tap into the *request* itself (the sheet is per product, and the product is enough), the metadata's `request_id` is parsed and unused for that reason, and a notice's row is not removed when the seller acts on it — the bell's own mark-read is the whole lifecycle.

**Honest state.** `supabase/migrations/20260928140000_add_shoe_model_requests.sql` is **✅ proven by CI**: `Supabase Migrations` applied it from scratch and ran `supabase/tests/shoe_model_requests.test.sql` at `plan(60)` **green on 2026-09-28 (60/60)** — and that run is also how three defects in the *suite* were found rather than in the schema (a 3-argument `throws_ok` reading the description as the errmsg pattern; an unfiltered `where product_id = …` that went multi-row once the suite refiled a withdrawn ask, whose `21000` aborted the run so that 33–60 had never executed; and three admin guards raising `P0001` where the file's own seller guards say `42501`). **The live project is a different question, and its answer is worse than "unapplied":** the file was hand-applied there in an **older revision** — the table, its five RPCs and its three policies exist and it holds 0 rows, but the applied `request_shoe_model`'s live-model probe is still declared `uuid` over a `bigint` column (the `42804` mismatch `variant_id` already paid for), and the applied bell CHECK still admits four types. **Re-applying this file is therefore the one step between the feature and a working flow**, and `AppConstants.shoeModelRequestEnabled` stays **off** until it is done. **P2 does not change that, and it is worth being precise about why:** the upload half is live-capable on today's schema, but the *close* half is that file's RPC, so with only the older revision applied the flow can publish a model and still cannot mark the ask answered. **P3, P4 and the deep link are built on top of it** — the seller is told on both endings, on both channels, and the tap lands on the product — and every one of those database paths is now covered by the 60 assertions that pass; what has still never run against a real database is the client side of them. The file picker the seller's side deferred is still unbuilt, which is why a link remains the only source.

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
| `lib/screens/admin/manage_shoe_model_requests_screen.dart` | **The 3D Model Requests queue — built 2026-09-28 (V2.10), behind `shoeModelRequestEnabled` (off).** Opened from the dashboard's tools beside Deletion Requests (§2.5.6): three tabs (waiting / fulfilled / closed), a claim, a **decline that cannot be sent without a reason** (the button stays disabled), and "close as done" as a picker over the product's own `active` models — or an explanation when the product has none |
| Admin | Existing admin portal product views gain model status (`draft/active/rejected`) and a re-validate action. **The one new admin screen in v1 is §2.5.6's request queue**, and **P2 (V2.11) now lets it *make* the model** — `Upload a 3D model` fetches, publishes through §2.5.4's service and closes the ask, behind `adminModelUploadAllowed` (**off**) |
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
lib/utils/shoe_model_request.dart                 -- (V2.10, built 2026-09-28) the request flow's pure rules: five states, four measurements, the four sentences the seller's row says, the centimetres hint, the prefill that refuses the length
lib/services/shoe_model_request_service.dart      -- (V2.10) the row/queue seam + service, behind `ShoeModelRequestDataSource`; nothing in it throws at a caller
lib/widgets/shoe_model_request_tile.dart          -- (V2.10) the seller's self-loading stateful row + its form / progress / ready sheets
lib/screens/admin/manage_shoe_model_requests_screen.dart -- (V2.10) the admin queue; V2.11 adds its `Upload a 3D model` action
lib/widgets/shoe_model_request_upload_sheet.dart      -- (V2.11) the admin's modelling sheet: link → check → report → publish-and-close, with the seller's own measurement prefilled
lib/widgets/shoe_model_report_card.dart           -- (V2.11) the authoring-contract report as ONE widget, shared by the seller's form and the admin's sheet (extracted from `add_edit_product_screen.dart`, which keeps its publish switch as the card's footer)
lib/utils/model_notice.dart                       -- (V2.14) where a model notice takes the seller: the metadata rule (per-user row), the `type`/`reference_id` rule (bell row), and the catalog lookup both land on
lib/screens/seller/seller_notification_center_screen.dart -- (V2.14) the bell the notice actually lands on; one new `case` routes it into the product's actions sheet, `initialProductId` being what makes that possible
lib/screens/notifications_screen.dart             -- (V2.14) the same landing for the per-user row, in the only feed that renders `public.notifications` at all (the customer shell's — the reason V2.14 exists)
lib/screens/seller/manage_products_screen.dart    -- (V2.14 gains `initialProductId`) the landing itself: the catalog every seller screen shares, opening one product's ACTION SHEET once that catalog can see it — deferred, not dropped, while the list is still loading, and a single sentence when the product is gone
supabase/migrations/<ts>_add_shoe_model_requests.sql -- (V2.10, written 2026-09-28; applied live as an OLDER revision — the current file still has to be re-applied, and CI proves it: 60/60) one table + 5 SECURITY DEFINER RPCs + a partial unique index + a `fulfilled`-needs-a-model CHECK; **no seller write policy at all**. Both closing RPCs also write the seller's notification (V2.12/V2.13), and since V2.14 a second, store-scoped row for the bell — which is why the same file widens `seller_notifications_type_check`
supabase/migrations/<ts>_add_models_notification_category.sql -- (V2.12, written 2026-09-28; applied — the enum value is live) ONE enum value, in a file of its own because `ALTER TYPE … ADD VALUE` cannot be used in the transaction that adds it — so this must apply before the flow file
supabase/tests/shoe_model_requests.test.sql         -- (V2.10) 41 pgTAP assertions, + 5 for the notification (V2.12), + 6 for the decline (V2.13), + 8 for the two rows on the seller's bell (V2.14) = 60
test/utils/model_notice_test.dart                  -- (V2.14) 15 tests over the two rules and the catalog lookup
test/services/model_notice_contract_test.dart      -- (V2.14) 5 tests that read the migration: the metadata keys the rules read vs the keys the SQL writes, and the type the bell routes on vs the value the CHECK admits
lib/constants/app_constants.dart                  -- the switches, incl. `shoeModelRequestEnabled` (off)
tool/validate_glb.dart                            -- offline validator CLI (V2.7, built) used by the asset pipeline
test/utils/fit_engine_test.dart
test/utils/glb_validator_test.dart
test/utils/shoe_model_resolver_test.dart
test/providers/try_on/try_on_session_controller_test.dart
test/services/shoe_model_service_test.dart
test/utils/shoe_model_request_test.dart             -- (V2.10) 29 tests
test/services/shoe_model_request_service_test.dart  -- (V2.10) 15 tests
test/widgets/shoe_model_request_tile_test.dart      -- (V2.10) 8 tests
test/screens/manage_shoe_model_requests_screen_test.dart -- (V2.10) 7 tests + (V2.11) 1 rollback + 2 flag-gated for the upload action
test/widgets/shoe_model_request_upload_sheet_test.dart  -- (V2.11) 9 tests: gating, the prefilled measurement, the link refusal, the report, publish-and-close, and the live-but-open ending
test/services/notification_category_contract_test.dart -- (V2.12) 4 tests pinning the Dart category enum against the SQL enum, both directions, through the real parse path
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
