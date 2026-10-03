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
  **neither**: the viewer the icon opens mounts the box *and* draws the button.
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
              ├── ShoePreviewSection     ← the box, and what it says when refused
              │     └── ShoePreview3D    ← AndroidView(SHOE_PREVIEW_VIEW_TYPE)
              │           └── ArTryOnView(Mode.PREVIEW)   [Kotlin]
              │                 ├── Filament Engine / Renderer / Scene / View
              │                 ├── gltfio AssetLoader + UbershaderProvider
              │                 └── Choreographer frame loop (orbit, idle spin)
              └── [Try On in AR]         ← pinned to the page's bottom edge
                    └──► the AR screen (Mode.AR, same view class)
```

The seller reaches the same viewer through a different door: the "3D fitting ready"
row in `lib/widgets/shoe_model_request_tile.dart` calls
`ShoePreviewScreen.forProduct`, which resolves the product's model itself and mounts
with `showTryOn: false` — nobody on the seller's side is going to try the pair on.

The "Try On in AR" pill is the **viewer's own bottom action** (since 2026-10-03):
full width, pinned above the system bar, outside the scroll area. It sat in the flow
directly under the box until the owner asked for it to move — a box that fills the
page left a dead half-page beneath the button. The reason it used to be the
section's own child still holds and is now structural: the viewer mounts the box and
draws the pill in the same build, so a product that resolves no model gets neither,
and a renderer refusal (which happens *inside* the section) cannot take the entry
off the page.

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
| `SHOE_PREVIEW_WEBVIEW` | `:1077` | which engine draws the box: `false` = native Filament (default), `true` = WebView `<model-viewer>`. Additive — see §8a | — |

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
| `lib/widgets/shoe_preview_3d.dart` | `ShoePreview3D` (the box; `diagnostics` + `useWebViewEngine` params, `hintAfterIdle` = 10 s), `ShoePreviewIdle` (paints `AppConstants.stage`, the tone the renderer clears to), `ShoePreviewGestureHint` (the gesture tutorial: sweeping hand + both gestures, `IgnorePointer` + `ExcludeSemantics`, honours reduced motion), `_handOverStage` (the stage colour, sent at mount **and** on a theme flip), `Sole3DIconButton`, `ShoePreviewHint`, `ShoePreviewQaBanner`, `ShoePreviewSection{model, channel, viewBuilder, height, bleed, paused, events, showDiagnostics, useWebViewEngine}`, `kShoePreviewGutter` (the page's one gutter number), `_QaStatusLine` |
| `lib/widgets/shoe_preview_webview.dart` | **the second engine** (§8a): `ShoePreviewWebView` — `ModelViewer` against `file://`, the `javascriptChannel` bridge that keeps a failed load visible, and the `gl:`/`box=` measurements that separate a broken renderer from a broken layout |
| `android/app/src/main/res/xml/network_security_config.xml` | the loopback-only cleartext exception the WebView engine needs (§8a). Do not widen it |
| `lib/screens/shared/shoe_preview_screen.dart` | the viewer. `new` (customer, model already resolved) / `forProduct` (seller). Owns the AR push, the `paused` flag that stops the box while AR is on top, the `SoleARPill` pinned to the bottom edge (`showTryOn` decides whether the door gets one), and the stage's geometry — the box is handed the full width (`bleed: true`) and the room left above the pill (`_notTheStage`, `_stageCeiling`) |
| `lib/services/shoe_preview_channel.dart` | `kShoePreviewMethodChannel` `com.solevision/shoe_preview` (`:37`), `kShoePreviewEventChannel` `…/events` (`:45`), `kShoePreviewViewType` `…/view` (`:49`), `kRendererUnsupportedReason` (`:67`), `setModel/setSize/setColor/setBackground/setDiagnostics`, `events` |
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

⚠️ **The gesture tutorial lives here, and it is Dart on purpose** (`ShoePreviewGestureHint`,
`ShoePreview3D.hintAfterIdle` = 10 s). The box shipped with one line of instruction —
"Drag to rotate", in the section's header — over a shoe that **spins on its own**, so a
customer who read it as a picture tapped the pill below and never learned it
turns (owner's report, 2026-10-03). After ten seconds of stillness the box performs the
gesture itself: a hand sweeps across a dark-glass pill, both gestures named (drag *and*
pinch — nothing else on the surface mentions the pinch, and both engines answer one).
Three properties make it safe, and all three are pinned in
`product_detail_shoe_preview_contract_test.dart`:

  • **It observes, it does not compete.** The touch reaches it through a raw
    `Listener` (`HitTestBehavior.translucent`) rather than a `GestureDetector`: both
    engines hand the gesture arena to their platform view (`EagerGestureRecognizer`),
    so a competing recognizer could never win a drag — it would only stop the shoe from
    turning. The pill itself is an `IgnorePointer`, so the drag it teaches lands on the
    same finger-down that dismisses it.
  • **It is silent to a screen reader** (`ExcludeSemantics`). The header already carries
    the instruction as text, and the surface under the pill is a platform view a screen
    reader cannot turn — announcing a gesture with no accessible equivalent would be a
    promise this feature cannot keep.
  • **It is one overlay for both engines**, which is a *finding* rather than tidiness:
    `AndroidView` and `webview_flutter_android` both compose through **Texture Layer
    Hybrid Composition** (`displayWithHybridComposition` defaults to `false`), the mode
    that lets Flutter paint over a platform view. So there is no Kotlin overlay and no
    CSS/JS injected into the `<model-viewer>` page — and no second visual language to
    keep in step. `<model-viewer>`'s own prompt stays off for the same reason
    (`interactionPrompt: none`, 3 s, WebView engine only).

The countdown starts with the box (not with the model), restarts from *full* after
every touch that ends, and does not run while the box is `paused` (AR on top) — coming
back from AR starts a fresh wait rather than showing a hand instantly. It is not drawn
over the one state where the box paints a sentence instead of a shoe
(`_engineDraws` → `shoePreviewModelOnDisk`).

**The stage's geometry (2026-10-03).** The box is the page's **full width** and takes
the room above the pinned AR pill: the viewer's scroll view carries no horizontal
padding any more, `ShoePreviewSection.bleed` carries that down to
`ShoePreview3D.bleed`, and the height is `maxHeight − 160` (the pill, the header row
and the page's own breathing room) clamped `240…900`. What gets wider and longer is
the **window**: the renderer is handed the same asset and frames it itself, so the
shoe turns in a bigger stage rather than being stretched by one. Everything that is
*text* — the header row (drawn inside the box widget, so it insets itself), the
section's banner, its refusal sentence, its QA readout, the viewer's note and its
failure hint — keeps the page's 20 px gutter, which is one constant
(`kShoePreviewGutter`) precisely so those two numbers cannot drift apart.

1. `initState` calls `setModel` (**before** the native view exists — it is parked,
   §4.4) and, when `diagnostics` is on, `setDiagnostics(true)`. The first `build`
   hands over the **stage colour** (`setBackground` — the customer's brightness,
   §4.4), which is parked the same way, and sends it again on every theme change:
   it lives in `build` rather than in `initState` because a brightness change
   repaints the tree element by element (`AppThemeRefresh.rebuildAll`) without
   re-creating or updating any widget — so `initState` and `didUpdateWidget` never
   run, and a renderer that is already alive would keep the tone the customer left.
2. The widget builds `AndroidView(viewType: kShoePreviewViewType)`; Flutter creates
   `ArTryOnView(context, previewListener, Mode.PREVIEW)` on the next frame.
3. The view's `surfaceCreated` posts to its own render thread:
   `createEngineIfNeeded()` → `createSwapChain()` → `startFrameLoop()`.
4. `paused` (set while the AR screen is on top) stops the loop without changing the
   widget's size — it must not resize the idle face.

### 4.3 The handover (F18 parking) and why there are two channel sets

The box is created by the framework, so a model sent the moment the widget mounts
has nowhere to land. The plugin therefore **parks** `model`, `size`, `color`, the
stage colour (`background`) and the QA diagnostics request per slot, and replays them
in `onPreviewViewAvailable`.
V0's bug (a *dropped* parked model) is why this is explicit and test-pinned.

```
Dart                          Flutter platform view            Native
ShoePreview3D.initState  ──►  (view not created yet)  ──►  parkedPreviewModel = spec
                                   │  next frame
                                   └──────────────────►  ArTryOnView created
                                                          onPreviewViewAvailable:
                                                            replay model/size/color/background/diagnostics
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
- **The stage.** `Renderer.ClearOptions.clearColor`, and the only thing here that
  follows the *customer's* appearance: the preview clears to `AppConstants.stage`
  (light neutral on light, the `#0E0F12` this view has always used on dark), sent by
  Dart and applied by `applyClearColor()` — on a live renderer for a theme flip, and
  at engine creation for a colour that arrived first (`setBackground` parks it). AR
  is never sent one and keeps `DEFAULT_CLEAR_COLOR`: the camera feed is dark in both
  brightnesses, which is why this travels on the **preview** channel rather than as
  a field of the shared model payload.

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

## 8a. The second engine: a WebView, and why it exists

```
SHOE_PREVIEW_WEBVIEW=true (SHIPPED)        SHOE_PREVIEW_WEBVIEW=false (rollback)
ShoePreview3D                              ShoePreview3D
  └── ShoePreviewWebView                     └── AndroidView(viewType: …)
        └── ModelViewer (<model-viewer>)            └── ArTryOnView(Mode.PREVIEW)
              └── WebView (Chromium, its own               └── Filament (JNI, in-process)
                  process) on 127.0.0.1 → the same .glb
```

⚠️ **The default is the WebView engine, and the flip is a measurement.** `Mode.AR`
is *not* covered by the WebView engine — it needs a GL surface and ARCore, so
`ar_fitting_screen.dart` still mounts the native view through `kArTryOnViewType`
regardless of this switch. Both engines therefore stay compiled in permanently; the
switch picks the *preview* only.

**The measurement that asked for it.** Six releases narrowed the P30 Pro's fault to
two native calls that *stop returning*: `TransformManager.setTransform` on the load
tail (2 of 5 launches) and `AssetLoader.destroyAsset` on a **second** teardown in one
process (2 of 2 re-opens). 1.0.43 removed both call sites — the correct fix for those
two, and not a fix for the class. A stall in our own process kills the app, and the
next one will be elsewhere.

**What changes is the blast radius, not the picture.** The WebView engine renders in
Chromium's process: if it stalls or dies, the app survives and the box is blank — a
state this feature already handles honestly (`ShoePreviewHint`, and the widget's own
failure line). It also needs no ARCore and no `FEATURE_LEVEL_2`, so it draws on the
ES 3.0 phones `canLoadModels()` provably cannot (D10).

**⚠️ Four things about the WebView path that are load-bearing.**

1. **The loopback server.** `model_viewer_plus` binds an `HttpServer` to
   `InternetAddress.loopbackIPv4` on an ephemeral port and serves the page and the
   model over it, reading the bytes from the local file. Nothing leaves the device,
   but Android 9+ blocks cleartext by default — hence
   `android/app/src/main/res/xml/network_security_config.xml`, which permits it to
   `localhost` and `127.0.0.1` **only** while leaving the base config at `false`. Do
   not widen it and do not replace it with `usesCleartextTraffic="true"`.
2. **`ar: false` is not a preference.** `<model-viewer>` can hand a model to the
   Google app over an `intent://` URL. The app has its own AR path with the fit logic
   (`Mode.AR`, the page's own AR path); a second, unmanaged AR door out of a product
   page is not something this widget may open.
4. **The page's events are the only witness.** The native engine reports through its
   channel; the WebView engine has no native side, so `load`/`error`/`progress` are
   bridged back over a `javascriptChannel` and land on the same QA readout the native
   heartbeat feeds (`ShoePreviewSection._recordEngineLine`). Without them a WebView
   that never draws looks exactly like one still loading — the "blank box with no
   explanation" this feature exists to avoid. The two races are closed explicitly:
   `customElements.whenDefined` (the deferred module script has not run when
   `relatedJs` executes) and an `mv.loaded` read (a loopback model can finish before
   any listener attaches).

**It is additive, and the native engine is not being deleted.** Both are compiled in;
`AppConstants.shoePreviewWebViewEnabled` picks one, and `ShoePreview3D.useWebViewEngine`
forwards it as a parameter (defaulting to the switch) so both branches stay testable.
The shipped default is **the WebView engine**: the switch is
`bool.fromEnvironment('SHOE_PREVIEW_WEBVIEW', defaultValue: true)`, so a release gets
`<model-viewer>` with no `--dart-define` at all. The rollback is one define
(`SHOE_PREVIEW_WEBVIEW=false`), and the QA workflow passes the define on **both**
branches — omitting it is no longer the same as asking for native, and a QA run that
silently built the wrong engine would report the result as evidence.

**✅ Measured on a real device, 2026-10-02 (vivo V2022, Android 12 / SDK 31, Adreno,
WebView 154 — a *different vendor* from the P30 Pro's Mali).** The native engine
crashed four times in its first thirty seconds there, with tombstones naming
`TransformManager_nSetTransform` (SIGSEGV) and `destroyMaterials`
(`PreconditionPanic: destroying material "base_lit_opaque" but 2 instances still
alive`, SIGABRT). The WebView engine, same model, same device:

| | result |
|---|---|
| open/close cycles | **5, all in one process** (`pid` unchanged throughout) |
| loads | 5 of 5, ~0.9–1.2 s each |
| errors | **0** (`error — :loadfailure` appeared in the first build and does not now) |
| tombstones | **0** |
| renderer | `gl:webgl2` on every load |
| element box | `box=396x520 body=520 win=520`, identical every load |
| drag | turns the shoe (verified by before/after screenshot) |

And the shipped default on that device, for contrast — same model, same taps:
**2 of 3 opens killed the app** at `load: entities added — applying the transform`
(`SIGSEGV` in `TransformManager_nSetTransform+64`), and the one that survived reported
the frozen-frame burst (`beginFrame refused the frame — chain=ok, rebuilds=5`) — the
P30 Pro's "it loads but I cannot touch it" symptom, on a second GPU vendor. The count
is from a debug QA build; the *fault* is not diagnostic-specific, because the 1.0.43
**release** build tombstoned on the same frame.

**And the teardown abort is fixed, verified on that device.** The screenshot of the
fault was `PreconditionPanic: destroying material "base_lit_opaque" but 2 instances
still alive` — SIGABRT, on **every** teardown — caused by a build that skipped
`AssetLoader.destroyAsset` on the theory that `engine.destroy()` frees the same
resources. It frees the engine, not the asset's material instances. Restoring the call
in the documented order at the tail of `teardown()` (asset → loader → provider's
materials) makes the block complete: `teardown: destroying the asset — …` followed 15 ms
later by `…materials destroyed`, across five cycles in one process, zero tombstones.
⚠️ **But `teardown END` never prints** — the teardown now stops inside
`engine.destroy()`, the statement the skip was avoiding, and the process **survives** via
the process-wide teardown latch (§4.7), which times out and lets the next open proceed
with a ~3 s hiccup. Two consequences, both accepted: **each open leaks a Filament
engine**, and this is deliberately not "fixed" by removing another call, because removal
is what turned a stall into an abort. Nothing customer-facing depends on it any more
(native is the opt-in path and `Engine.destroy()` accepts no timeout).

**One clue worth keeping, explicitly not a diagnosis.** The fault is
`SEGV_ACCERR` at `0x74f5b3f610`, while every live pointer in the dump is a tagged heap
pointer `0xb4_0000_0074_xxxx_xxxx` whose **untagged** value is exactly that address;
`x22`/`x2` hold `0x3ec00000` (`0.375f`) and `x23` holds `12`, the shape of a `mat4f` copy
walking a column index. **Four tombstones fault at four different addresses with *two
fault codes*** — `0x74f5b3f610` and `0x73ff6ae400` as `SEGV_ACCERR`, `0x724dc83fe0` and
`0xb3fa8a3a10` as `SEGV_MAPERR` — where a fixed bad access would be one address and one
code. That spread is what a stale or garbage pointer dereference looks like, so the
reading is an out-of-bounds or use-after-free in the transform write; it is **not
proven**, and naming it needs a symbolized `libfilament-jni.so`, which a stripped release
`.so` does not give. The call site is clean: a correctly sized `FloatArray(16)` for a
valid entity.

**Two failures found by that run, both fixed, both worth not re-introducing.**

1. **The blank box was a reload.** `ModelViewer` creates its loopback server and its
   `WebViewController` in `initState`, so re-inflating the element discards the load
   in flight and starts a second one. The first build drew its own QA overlay by
   switching its root between `ModelViewer` and a `Stack`, which reloaded the model
   every time a status line appeared — the log showed `error — :loadfailure` and a
   full re-fetch. The parent (`ShoePreviewSection`) draws the only QA line; this
   widget must never rebuild itself to say anything. Pinned by the `_report`-has-no-
   `setState` assertion in `product_detail_shoe_preview_contract_test.dart`.
2. **The template has no root height.** `body, model-viewer { height: 100% }` with no
   height on `html` means neither percentage has a definite containing block. The
   element still measured a correct `396x520`, so this was **not** the blank box —
   `relatedCss: 'html { height: 100%; }'` is a guard, not the repair. Do not remove it
   on the grounds that it did not fix anything.
3. **The stage is baked into the served page, so a theme flip re-keys the element.**
   `backgroundColor` is an attribute of the HTML the loopback server serves, and the
   package builds that document in `initState` (it has no `didUpdateWidget`), so a
   live box cannot be recoloured in place. The key therefore carries the brightness
   (`'${model.path}#${AppBrightness.current.name}'`), and a theme change with the
   viewer open re-inflates the element — one reload from the local file, which is the
   deliberate exception to point 1 above: that rule is about rebuilding the box *to
   say something*, while this changes what is drawn. The alternative is a light-mode
   viewer framing a `#0E0F12` rectangle until the customer leaves and comes back.

**And the page reports two measurements, because a colour cannot.** A missing WebGL
context and a `model-viewer` element with no box to draw in are the same picture and
raise the *same* `load` event. `gl:<kind>` is probed once per page and `box=` rides
along with every event, relayed through the same bridge — which is how the two
failures above were separated from "the renderer is broken" on a device whose ROM
suppresses app-level `Log.i` entirely.

**Not chosen, and why** (so this is not re-litigated): `flutter_scene` needs Flutter
3.47+ and Impeller, and this app pins `EnableImpeller=false` in its manifest;
`three_dart`/`flutter_gl` are unmaintained WebGL shims; a pre-rendered 360° turntable
is the always-works fallback if both engines disappoint, at the cost of zoom and the
"the mesh you turn is the mesh we track" story.

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
