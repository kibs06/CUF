# SoleVision / CUFMAI — Product 3D Viewing

> **What this covers.** The **3D icon in the corner of the product photograph**, the
> **full-screen 3D viewer** behind it, the **Filament renderer** that draws the shoe,
> and the **QA machinery** that exists because the phone this was measured on cannot
> be logged into.
>
> **What this is not.** `docs/AI/AR_TRY_ON_ARCHITECTURE.md` describes the *simulated*
> AR of the pre-renderer era (`ARVirtualFitScreen`, `ARViewPlaceholder`). The real
> AR session (`Mode.AR`, ARCore, floor placement) is a sibling of everything here and
> shares the same view class; the roadmap and history live in
> `docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md`, and the measurement log is
> `docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md` (findings **F13–F24**).
>
> **Where do I start?**
> The gate → `lib/utils/shoe_preview_visibility.dart` + the icon wiring in
> `lib/screens/customer/product_detail_screen.dart` (`_showPreviewIcon`, `_openShoePreview`).
> The box and the viewer → `lib/widgets/shoe_preview_3d.dart`,
> `lib/screens/shared/shoe_preview_screen.dart`.
> The wire → `lib/services/shoe_preview_channel.dart` ↔
> `android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnPlugin.kt`.
> The renderer → `…/tryon/ArTryOnView.kt` (≈2,100 lines; start at `Mode.PREVIEW`).
>
> ⚠️ **Read this before touching the renderer.** As of 2026-10-01 exactly **one**
> real device has ever drawn a shoe, and it did so at `FEATURE_LEVEL_1` *with the
> double-locked QA override switched on*. The emulator this project owns can never
> draw it at all (F14/F24, §8). Anything you "verify" about the render path on an
> emulator is not evidence.

---

## Quick Facts

- **Two rendering modes, one class.** `ArTryOnView.Mode.PREVIEW` (no camera, no
  ARCore session, an orbit the customer drags) and `Mode.AR` (ARCore, floor
  placement). The preview is the default experience; AR is the escalation inside it.
- **The gate is pure and reported.** `resolveShoePreview` asks four questions in
  order and returns *the first thing that stopped it* as an enum value, which the
  page logs as `[shoe-preview] hidden: <reason> — <product>`.
- **The icon and the AR button are all-or-nothing.** A product with no model shows
  **neither**; the button is part of the section the icon opens.
- **Two channel sets, deliberately.** `com.solevision/shoe_preview*` for the box and
  `com.solevision/ar_try_on*` for AR, with separate native slots, so the AR screen
  (which is pushed on top of a still-mounted product page) can never receive the
  box's model or its `modelLoaded` events.
- **The native side never does HTTP.** It is handed a local file path and never a
  URL; bytes on disk are the Dart side's problem (§5).
- **The renderer refuses rather than tries** below Filament's `FEATURE_LEVEL_2`,
  because the alternative was a `SIGSEGV` in `libfilament-jni.so` (F22, §8).
- **There is no logcat on the owner's phone.** Its developer options are locked
  behind a password its previous owner set, so the app carries its own diagnostics
  (§6, §7). This single constraint explains most of the code that looks like
  over-engineering.

---

## 1. The shape of the feature

```
product photo (hero)
  └── [3D icon, bottom-right]            ← gated, see §2
        └── ShoePreviewScreen            ← full-screen viewer, two doors
              ├── ShoePreviewSection     ← the box + the "Try On in AR" pill
              │     └── ShoePreview3D    ← AndroidView(SHOE_PREVIEW_VIEW_TYPE)
              │           └── ArTryOnView(Mode.PREVIEW)   [Kotlin]
              │                 ├── Filament Engine / Renderer / Scene / View
              │                 ├── gltfio AssetLoader + UbershaderProvider
              │                 └── Choreographer frame loop (orbit, idle spin)
              └── [Try On in AR] ──► the AR screen (Mode.AR, same view class)
```

The seller reaches the same viewer through a different door: the "3D fitting ready"
row in `lib/widgets/shoe_model_request_tile.dart` calls
`ShoePreviewScreen.forProduct`, which resolves the product's model itself and mounts
with `showTryOn: false` — nobody on the seller's side is going to try the pair on.

## 2. The four switches (and what a build actually contains)

All four are `bool.fromEnvironment` constants in `lib/constants/app_constants.dart`
— **compile-time**, default **off**. A release APK compiled without them cannot
turn them on later; one compiled *with* them cannot turn them off.

| switch | line | what it does | locks |
|---|---|---|---|
| `SHOE_PREVIEW` | `:931` | the whole surface: icon, viewer, box. Off ⇒ `featureOff`, nothing else is even asked (a release build passes it on: `RELEASE_DART_DEFINES`) | — |
| `SHOE_PREVIEW_DIAGNOSTICS` | `:938` | the QA banner + the heartbeat + the measured-facts line under a failure | — |
| `SHOE_PREVIEW_ALLOW_LEVEL1` | `:970` | ⚠️ lets the glTF load proceed below `FEATURE_LEVEL_2` where it has always refused — the load that was a `SIGSEGV` on an emulator (F22) | the define **and** a debuggable APK |
| `SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1` | `:1012` | ⚠️ brings the engine up at `FEATURE_LEVEL_1` (or lowers a live one), to manufacture the cheap-phone case on hardware that is allowed to die | the define **and** a debuggable APK |

**What a shipped build has.** The release pipeline passes `RELEASE_DART_DEFINES`,
which is a **repository variable** (`.github/workflows/release.yml:130`), not
something in the tree — so "does the shipped APK have the 3D icon?" is answered by
that variable, not by this file. The 1.0.38 build installed on the owner's phone
*does* have it (the icon is there, and the renderer refuses behind it).

A QA/debug APK built with all four is the measurement build; its banner says so on
the page (`ShoePreviewQaBanner.textFor`, `lib/widgets/shoe_preview_3d.dart:450`):
`QA build` · `engine pinned to level 1` · `level-1 load override on — may abort the
process`. The banner text is how a screenshot identifies which switches produced it.

## 3. File map

| file | role |
|---|---|
| `lib/utils/shoe_preview_visibility.dart` | the gate: `resolveShoePreview` + `ShoePreviewReason{none, featureOff, notAndroid, noModel, modelNotReady}` + `ShoePreviewDecision`. Pure — no Flutter, no Supabase |
| `lib/screens/customer/product_detail_screen.dart` | `_showPreviewIcon` (adds "bytes verified on disk" to the gate), `_openShoePreview`, the `[shoe-preview] …` log (`:1022`), the icon's `Positioned(right: 12, bottom: 50)` over the hero |
| `lib/widgets/shoe_preview_3d.dart` | `ShoePreview3D` (the box; `diagnostics` param), `ShoePreviewIdle` (its `#0E0F12` matches the renderer's clear colour), `Sole3DIconButton`, `ShoePreviewHint`, `ShoePreviewQaBanner`, `ShoePreviewSection{model, onTryOnInAr, showTryOn, channel, viewBuilder, height, paused, events, showDiagnostics}`, `_QaStatusLine` |
| `lib/screens/shared/shoe_preview_screen.dart` | the viewer. `new` (customer, model already resolved) / `forProduct` (seller). Owns the AR push and the `paused` flag that stops the box while AR is on top |
| `lib/services/shoe_preview_channel.dart` | `kShoePreviewMethodChannel` `com.solevision/shoe_preview` (`:37`), `kShoePreviewEventChannel` `…/events` (`:45`), `kShoePreviewViewType` `…/view` (`:49`), `kRendererUnsupportedReason` (`:67`), `setModel/setSize/setColor/setDiagnostics`, `events` |
| `lib/providers/try_on/try_on_mode.dart` | `TryOnDegradeReason.rendererUnsupported` — how a refusal reaches the AR flow's vocabulary |
| `android/.../tryon/ArTryOnPlugin.kt` | the two channel sets, two slots, the parking/replay contract, `setPreviewDiagnostics` |
| `android/.../tryon/ArTryOnView.kt` | the renderer (both modes), the QA heartbeat, the swap-chain repair, the teardown latch |
| `android/.../arfoot/DiagRelay.kt` | the file bridge that makes diagnostics reachable without adb |
| `tool/qa_capture.sh` | one-command capture off an adb-reachable device (§7) |
| `.github/workflows/qa-apk.yml` | the QA APK as a workflow artifact, `abi`-aware (§7) |
| `.github/workflows/qa-logcat.yml` | publishes a capture as an artifact (device or `log_url`) |

Tests that pin all of the above: `test/utils/shoe_preview_visibility_test.dart`,
`test/widgets/shoe_preview_3d_test.dart`,
`test/widgets/product_detail_shoe_preview_contract_test.dart` (reads the Kotlin as
source, so a drifted string fails here rather than as a blank box),
`test/screens/shoe_preview_screen_test.dart`,
`test/services/ar_try_on_channel_test.dart`,
`test/tooling/qa_diagnostics_contract_test.dart`.

## 4. Flow

### 4.1 The gate — four questions, first failure wins

`resolveShoePreview(enabled, isAndroid, hasModel, hasLocalModel)`, in that order:

1. `featureOff` — the build switch is off. Nothing is read.
2. `notAndroid` — there is no iOS renderer at all, so the section must not exist.
3. `noModel` — the product has no **live** (`active`) `product_models` row. Most of
   the catalogue is here.
4. `modelNotReady` — a live row exists but its bytes are not verified on disk yet
   (the prefetch is running or failed). A spinner over a box the customer can
   already see is a worse lie than a beat of no box.

…otherwise `shown`. The page adds one fact of its own before drawing the icon — the
bytes are verified on disk — and logs the decision, which is the first thing to read
when the icon is missing:

```
adb logcat -d | grep shoe-preview        # [shoe-preview] hidden: featureOff — JBC Crown Leather Sandals
```

### 4.2 Mounting the box (`ShoePreview3D`)

1. `initState` calls `setModel` (**before** the native view exists — it is parked,
   §4.4) and, when `diagnostics` is on, `setDiagnostics(true)`.
2. The widget builds `AndroidView(viewType: kShoePreviewViewType)`; Flutter creates
   `ArTryOnView(context, previewListener, Mode.PREVIEW)` on the next frame.
3. The view's `surfaceCreated` posts to its own render thread:
   `createEngineIfNeeded()` → `createSwapChain()` → `startFrameLoop()`.
4. `paused` (set while the AR screen is on top) stops the loop without changing the
   widget's size — it must not resize the idle face.

### 4.3 The handover (F18 parking) and why there are two channel sets

The box is created by the framework, so a model sent the moment the widget mounts
has nowhere to land. The plugin therefore **parks** `model`, `size`, `color` and the
QA diagnostics request per slot, and replays them in `onPreviewViewAvailable`.
V0's bug (a *dropped* parked model) is why this is explicit and test-pinned.

```
Dart                          Flutter platform view            Native
ShoePreview3D.initState  ──►  (view not created yet)  ──►  parkedPreviewModel = spec
                                   │  next frame
                                   └──────────────────►  ArTryOnView created
                                                          onPreviewViewAvailable:
                                                            replay model/size/color/diagnostics
                                                          surfaceCreated → engine → chain → loop
modelLoaded / error      ◄──  EventChannel ◄──────────  listener.onEvent/onError
status (heartbeat)       ◄──  EventChannel ◄──────────  emitStatus (1 Hz, diagnostics only)
```

The AR screen is pushed **on top of** a still-mounted product page, so on one
channel the plugin would hold two live views and the last one created would silently
receive the other's model. Hence two names for everything (F18).

### 4.4 Renderer contract

- **Engine.** Filament 1.72.1, OpenGL, `UbershaderProvider` + `AssetLoader` for
  glTF. `Filament.init()` / `Gltfio.init()` are mandatory before the first
  `Engine.create()` (without them the first create dies with `UnsatisfiedLinkError`).
- **The level rule.** `canLoadModels()` reads the **active** feature level and
  requires `≥ FEATURE_LEVEL_2`. Below it the loader is never called: the view
  reports `renderer_feature_level_unsupported` (`REASON_RENDERER_UNSUPPORTED`), the
  payload is dropped, and the page removes the section. ⚠️ Read the *active* level, not
  the supported one — a build that asks for a lower level is just as unable to load.
- **Why refuse instead of try.** At level 1 on a real load the process died with
  `SIGSEGV` inside `libfilament-jni.so`, on the render thread, 126 ms after
  `Engine.create()` — and that class of failure is not catchable (F16/F22).
- **No backend probing.** Asking for Vulkan on a device that advertises it but
  cannot build an instance aborts the process from Filament's own render thread
  (`Fatal signal 6`, F24). The backend is chosen by refusing, never by trying.
- **Lighting.** A key/fill pair (`KEY_LUX`/`FILL_LUX`) in the preview; in AR the sun
  and ARCore's ambient estimate. The preview's rig **rotates with the orbit** — a
  world-fixed pair shows the customer the unlit side for half of every revolution.

### 4.5 The camera law (F23)

"Fit the bounding **sphere**" vertically: `d = r / sin(fov/2) × PREVIEW_FIT_MARGIN`,
with `PREVIEW_FOV_DEGREES = 45`, `PREVIEW_FIT_MARGIN = 1.05`, and `r` = the radius of
the sphere **containing the bounding box** (half-diagonal), not the largest
half-extent. Using the half-extent put everything outside an inscribed sphere — the
toe, the far corner — outside the frame (96% of the height at the opening view,
124% clipped while dragging). The sphere rather than a box because a sphere does not
change size as the model turns, so the idle spin can never pump the zoom.

Opening pose: `INITIAL_YAW_DEG = 60` (the model contract has +Z as the toe; the front
three-quarter a product shot uses), `INITIAL_PITCH_DEG = 18`, pitch clamped to
`−10…75`, `DRAG_DEG_PER_PX = 0.75`, zoom `0.6…2.5`, idle spin starts after
`AUTO_ROTATE_DELAY_MS = 2500` at `AUTO_ROTATE_DEG_PER_SEC = 20`.

### 4.6 The frame loop and what "presented" means

A `Choreographer.FrameCallback` on the render thread:

```
renderFrame(frameTimeNanos):
  if session != null && resumed → session.update() → AR camera/lighting/placement
  else if Mode.PREVIEW          → applyPreviewCamera(deltaSeconds)   (orbit + idle spin)
  if !renderer.beginFrame(chain, frameTimeNanos):
      beginFrameFails++; beginFrameFailStreak++
      … repair (§6) … Thread.sleep(1) ; return
  beginFrameFailStreak = 0
  renderer.render(view); renderer.endFrame(); presentedFrames++
  countFrame(); emitStatus()
```

⚠️ **`loop=` and `present=` are different numbers on purpose.** The first device
readout said `loop=on frames=61` on a box whose picture had not changed: 61 was
*loop iterations*. A frozen picture with a live loop is the signature this whole
instrument exists to separate from "the loop died".

### 4.7 Teardown, and one engine at a time

`dispose()` posts `teardown()` to the render thread and publishes a process-wide
`CountDownLatch` (`pendingTeardown`). The **next** `createEngineIfNeeded()` waits on
it for at most `TEARDOWN_WAIT_SECONDS = 2` before calling `Engine.create()`. This is
the repair for the second-open crash: teardown is asynchronous, so a second open
used to build a new engine while the old one was still being destroyed underneath
it. The wait is bounded — a wedged teardown must not become a hang on a customer's
phone.

## 5. Where the model comes from

```
seller uploads a glTF   →  product_models row (draft → active)   [SHOE_MODEL_REQUEST / ADMIN_MODEL_UPLOAD]
customer opens a product → prefetch downloads the row's bytes, verifies the sha   [TRY_ON_PREFETCH]
                          → verified file on disk
product page             → gate question 4 ("bytes verified on disk") passes
Dart                     → setModel({path, modelId, authoredLengthMm, yawOffsetDeg,
                                     allowUnsupportedRenderer, lowerEngineToLevel1})
native                   → reads that local file; never HTTP
```

⚠️ The **seller door does not consult `TRY_ON_PREFETCH`** (`ShoePreviewScreen.forProduct`,
`lib/screens/shared/shoe_preview_screen.dart:77`): a seller who taps "3D fitting
ready" is asking for the file by name, which is a different question from spending a
shopper's data on a warm cache they never asked for.

`authoredLengthMm` is a *ratio* correction against the asset's own bounding box, so
a model authored in millimetres and one authored in metres both render at the right
size. The native side reports triangles as `-1` ("native did not say") because the
parse-time verified count already exists on the row; re-deriving it would create a
second source of truth.

## 6. The QA instrument

All of it is off unless `SHOE_PREVIEW_DIAGNOSTICS` is on (`setDiagnostics` is the seam
that carries the Dart define across, because Kotlin cannot read Dart defines).

**The heartbeat**: one line, written to `files/qa_preview_status.txt`
(`STATUS_FILE_NAME`) and sent as a `status` event at most once a second
(`STATUS_PERIOD_NANOS = 1s`):

```
loop=on iter=61 present=0 beginFail=184 rebuild=1 engine=1/0 chain=ok creates=2
surface=ok asset=ok r=155mm yaw=198 touch=3/1/2 interacting=1 size=976x1326
```

| field | means |
|---|---|
| `loop=` | the frame callback is alive (`on`) — the loop dying is `STOPPED` |
| `iter=` / `present=` | loop iterations vs frames that actually began **and** presented |
| `beginFail=` / `rebuild=` | refused `beginFrame` calls; swap-chain rebuilds attempted |
| `unrec=` | `Engine.hasUnrecoverableFailure()` — the one "why" Filament exposes from Java when a refusal streak no chain rebuild can clear is really a backend error |
| `engine=` | engine creates/destroys in this process |
| `chain=` / `creates=` / `surface=` | swap chain present?, how many built, surface present? |
| `asset=` | a glTF asset is loaded |
| `r=` / `yaw=` | the framing radius in mm; the orbit angle |
| `touch=` | down/move/up counts that reached the native view |
| `size=` | surface size — a size change destroys and rebuilds the chain |

The event payload also carries `lastFrameError`, `lastSwapChainError`, and — on the
**first** heartbeat of a run only — `fromLastRun`, the previous process's final line.
That is what makes the readout survive the crash it describes.

**The repairs the instrument was built alongside** (both ⚠️ *unverified on a real
device* as of this writing):

1. **A swap chain that cannot begin a frame is rebuilt.** After
   `MAX_BEGIN_FRAME_FAILURES = 3` consecutive refusals, `createSwapChain()` runs
   again, up to `MAX_SWAP_CHAIN_REBUILDS = 5`. The existing retry only fired when the
   build *returned null*, and a chain that exists but cannot present was a state
   nothing recovered from.
2. **The teardown latch** (§4.7).

**The file channel.** `ArTryOnView` and `ArTryOnPlugin` relay discrete events
through `DiagRelay.log("preview", …)` into `nav_diag.log`, the in-app diagnostics
file built for the adb-less phone. ⚠️ Keep the call sites discrete: the relay holds
one `O_APPEND` descriptor and `fsync`s every line, which is what survives a process
death and also what makes a per-frame call site wrong. The refusal streak logs only
its first frame, its repair, and every `REFUSAL_MILESTONE_FRAMES = 1200` (~1.5 s).

**Teardown breadcrumbs.** `teardown()` writes one line per completed phase — start,
loop stopped + frame callback removed, asset destroyed, swap chain destroyed with the
`flushAndWait` result, the view/scene/renderer/entity/loader/material batch destroyed,
engine destroyed, done — so a crash *inside* teardown leaves the last completed step
readable at the next launch (and the absence of "teardown END" localises it). The two
surface callbacks write their own pair (`surface detached: …`) when a surface goes
away: an event that is rare by construction, so two lines are cheap.

## 7. Getting diagnostics off a device

| route | who it is for |
|---|---|
| the QA banner + `_QaStatusLine` on the page | a screenshot, when there is no other channel |
| `nav_diag.log` → **Foot Sizing → the bug icon → share sheet** | the owner's P30 Pro: **locked developer options, so `adb logcat` will never be read from it**. The `[preview]` lines carry the engine level, the refusal, the load, the chain, the streaks and the teardown |
| `bash tool/qa_capture.sh [--seconds N]` | any device adb *can* reach (emulator, another phone, a machine with one plugged in). Writes full logcat, a filtered log, the heartbeat history sampled every 5 s, device facts and a `digest.txt` (`present_max`, `beginFail_max`, `rebuild_max`, `loop_stopped`, `crash_signatures`, identical-snapshot count). `--check` answers "is a device here?" without capturing |
| `qa-logcat.yml` | publishes a capture as `solevision-qa-logcat-{device,shared}`; the `shared` door takes a `log_url` for a log produced on a device with no adb |
| `qa-apk.yml` | the QA APK itself, as an artifact. `abi` decides **which `libflutter.so` the APK can run** — `arm64` (phone), `x86_64` (emulator), `both`. The APK is *not* ABI-filtered: Filament's AAR and the plugins ship every ABI, so it stays ~250 MB either way and installs anywhere, but an `arm64`-built one dies loading the engine on an x86_64 emulator |

⚠️ **An emulator is not a small phone.** Its GLES is a translator
(`libGLESv2_emulation.so`, `ro.opengles.version = 196608` → ES 3.0), so it resolves
`FEATURE_LEVEL_1`, cannot load the model (F14) and cannot be probed via Vulkan (F24)
— and with the box mounted, Filament's per-frame GL traffic is translated on the
guest CPU, which is why the whole AVD can become unresponsive. Use it for the Dart
path, the refusal, the banner and the plumbing. Never for a picture.

## 8. Findings index

| id | what was measured | still true? |
|---|---|---|
| F14 | at `FEATURE_LEVEL_1` **nothing loads**: the ubershader material provider fails (`No material with the specified requirements exists`) | ⚠️ **emulator-only**. On 2026-10-01 a P30 Pro at level 1 loaded **and drew** the sandal with the QA override → this finding and D10's "ES 3.0 phones can draw no shoe" are falsified for that unit |
| F16 | that class of material/mesh failure **aborts** the process rather than throwing | yes — it is why the guard exists |
| F22 | loading a real model at level 1 = `SIGSEGV` in `libfilament-jni.so` 126 ms after `Engine.create()`; the renderer now refuses instead | yes (as measured); the refusal is the fix |
| F23 | the framing law was fit to an inscribed sphere, not the containing one → up to 124% of the box clipped while dragging | fixed (`PREVIEW_FIT_MARGIN = 1.05`) |
| F24 | an emulator that *advertises* Vulkan aborts when asked to use it; the fallback was reverted | yes |

**Open device faults** (both reported from a P30 Pro, both repaired, ⚠️ neither
repair confirmed on hardware yet):

1. *"It moves for a second then it stops"* — live loop, frozen picture. Diagnosed
   from a screenshot of the heartbeat (`loop=on frames=61 … chain=ok asset=ok
   touch=3`) as `beginFrame` refusing **every** frame. Repair: the present/beginFail
   counters and the bounded chain rebuild (§6).
2. *"I open the 3D model, then I leave, then I open it again and it crashes"* —
   diagnosed as the teardown race. Repair: the process-wide latch (§4.7).

## 9. Rules for changing this

- **Do not relax the level guard** without both locks, and do not replace the refusal
  with a probe: the failure mode being avoided is an uncatchable abort on a
  customer's product page.
- **Do not add per-frame work to the diagnostics** (the relay `fsync`s; the burst
  guard is deliberate).
- **Do not judge the renderer on an emulator** (§7). If a render must be judged, it
  needs a real GPU — the owner's phone, or hardware in a device farm.
- **Keep the two channel sets and the parking contract.** A "tidy-up" that merges
  them re-creates the bug where the AR screen silently receives the box's events.
- **Keep the icon and the AR button together** (all-or-nothing).
- **The native side never fetches.** It gets a local path or nothing.
- **Compile-time switches stay compile-time.** Every `SHOE_PREVIEW*` flag is a
  `bool.fromEnvironment`; nothing here can be enabled by a remote config.
- **Open product question (undecided):** should the 3D icon be hidden on a device
  whose renderer has already refused, so a customer cannot land in an empty viewer?
  Today it is *not* hidden — the box shows the honest sentence instead.

## 10. How to reproduce / verify

```bash
flutter analyze lib test          # must be clean
flutter test                      # 2,256 pass / 7 skipped at the time of writing
cd android && ./gradlew :app:compileDebugKotlin

# QA APK (GitHub): pick the engine for the machine you will install it on
gh workflow run qa-apk.yml -f abi=arm64  -f diagnostics=true -f lower_engine=true -f allow_level1=true
gh workflow run qa-apk.yml -f abi=x86_64 -f diagnostics=true -f lower_engine=true -f allow_level1=true

# A capture from any adb-reachable device
bash tool/qa_capture.sh --seconds 60      # → build/qa/capture-<timestamp>/digest.txt
bash tool/qa_capture.sh --check           # is a device attached?

# What the page decided about the icon, on any build
adb logcat -d | grep shoe-preview
```

To read a run: `digest.txt` first, then `heartbeats.txt` (consecutive identical
lines under a live `loop=on` **are** the freeze), then the `[preview]` lines in
`nav_diag.log` for the path that led there.
