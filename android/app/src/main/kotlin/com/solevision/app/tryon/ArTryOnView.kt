package com.solevision.app.tryon

import android.app.ActivityManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.graphics.SurfaceTexture
import android.opengl.Matrix
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.widget.FrameLayout
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.LightManager
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.solevision.app.arfoot.DiagRelay
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * **V3.2 — the real try-on renderer, on the Filament-direct route.**
 *
 * This is the platform view behind `AndroidView(viewType = "com.solevision/ar_try_on/view")`.
 * It is not SceneView: V0.7 measured SceneView + Compose at +27.7 MB on the release APK against an
 * ≤8 MB budget, and variant C measured the same commit with `filament-android` + `gltfio-android`
 * alone at ≈+6.4 MB per arm64 device. So this file drives Filament's own Java API and owns the
 * three things SceneView used to supply (`docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md` §5.5).
 *
 * ## What is real here
 *
 *  • **The engine lifecycle.** `Filament.init()` + `Gltfio.init()` are mandatory and nothing else
 *    calls them (finding 1 of `GltfioDecodeTest`); the engine and everything derived from it live
 *    on one render thread and are destroyed there, because Filament objects are neither thread-safe
 *    nor safely destroyed from another thread's sync.
 *  • **The camera is ARCore's, not a made-up eye position.** Every frame takes
 *    `Frame.camera.pose.toMatrix()` as the Filament camera's model matrix and ARCore's own
 *    `getProjectionMatrix(near, far)` as a custom projection. The shoe is therefore world-anchored
 *    and correctly placed *before* the camera feed exists — which is the point of doing it now:
 *    when the feed lands, the geometry does not move.
 *  • **Lighting** is a key + fill directional pair, with the key's intensity and colour driven by
 *    ARCore's ambient light estimate (`Config.LightEstimationMode.AMBIENT_INTENSITY`) so the shoe
 *    sits in the room's light rather than one hard-coded value. **There is no image-based
 *    lighting** — see the "not built" list; without an environment map the upper has no
 *    reflections and reads slightly flat. That is a look problem, not a correctness one, and it is
 *    the first thing to fix after the camera feed.
 *  • **Placement is real AR placement.** `placeShoe(x, y)` runs ARCore's `hitTest` against detected
 *    horizontal planes and takes the hit pose. The analytic floor ray is only the window before a
 *    plane is found.
 *  • **Model handover, scale, colour, perf sampling and the screenshot** — the five other methods
 *    the Dart controller speaks (`lib/services/ar_try_on_channel.dart`).
 *
 * ## What is deliberately not built, and why
 *
 *  1. **The camera feed is not composited.** Every route to drawing it needs a Filament material
 *     sampling ARCore's external OES texture, and **no `.filamat` ships in the artifacts this route
 *     uses** — measured: `filament-android`, `gltfio-android` and `filament-utils-android` contain
 *     zero assets. SceneView carried `camera_stream_flat.filamat` (42,544 B) inside its own package.
 *     So the shoe is drawn over a flat clear colour today. This is V3's largest visible gap and it
 *     is recorded as a gap rather than faked with a placeholder background.
 *  2. **Planes are not visualized** — same missing asset (SceneView's `plane_renderer.filamat`,
 *     40,976 B). They are still *used*: hit-testing needs plane detection, so placement on a real
 *     floor works while the floor stays invisible.
 *  3. **Hand-rolling geometry against the ubershader is not attempted.** Finding 3 of
 *     `GltfioDecodeTest` is a measured SIGABRT: a material/mesh mismatch (wrong parameters, missing
 *     vertex attributes) trips `utils::PreconditionPanic` inside `createAsset`. Building a
 *     full-screen quad or plane mesh against an ubershader whose exact attribute set is unverified
 *     is exactly that crash, on a screen a customer is holding. The two asset routes to close 1 and
 *     2 are in the roadmap: vendor the two Apache-2.0 `.filamat` files (with a version check — a
 *     `.filamat` is version-locked to the Filament that compiled it), or compile our own with
 *     `matc` in CI.
 *
 * ## Threading
 *
 * Everything Filament *and* ARCore touches happens on one `HandlerThread`. The `Session` is created
 * and updated there too, so the pose read for a frame and the frame rendered from it are always the
 * same `Frame` — pose on one thread and render on another is a one-frame smear that is invisible on
 * a desk and obvious in a moving hand. Fields below are only ever touched on the render thread;
 * callers post, which is what makes that safe.
 */
class ArTryOnView(
    context: Context,
    private val listener: Listener,
    private val mode: Mode = Mode.AR,
) : FrameLayout(context), SurfaceHolder.Callback {

    /**
     * **What this instance is for**, and the reason one renderer class has two surfaces.
     *
     * [AR] is everything V3.2 was written for: an ARCore session, a camera pose per frame, plane
     * hit-tests for placement, an opaque `SurfaceView`.
     *
     * [PREVIEW] is the product page's inline box — "view in 3D" ahead of "try on in AR": **no
     * ARCore session is ever created**, so it runs on phones that cannot install ARCore (a
     * strictly larger audience than the AR button has), and the camera is one the customer turns
     * with a finger. Same engine, same asset loader, same lights, same authored-length scale
     * correction, same per-size grading: at try-on distance the mesh and its materials have to be
     * the same object, and a second renderer would eventually disagree with this one about one of
     * them.
     *
     * ⚠️ This is a flag rather than a subclass because the frame loop **already tolerated a null
     * session** before this mode existed — it skips the pose and the light estimate — so the
     * preview is a *camera and a surface*, not a second render loop. Everything else here is
     * shared by construction.
     */
    enum class Mode { AR, PREVIEW }

    /**
     * How the view reports back. The plugin turns these into the EventChannel payloads the Dart
     * parser already understands (`modelLoaded`, `perf`, `error`) and never invents a type Dart
     * would only log as unknown.
     */
    interface Listener {
        fun onEvent(type: String, data: Map<String, Any?>)
        fun onError(reason: String, message: String?)
    }

    /** Outcome of asking for a session; the plugin forwards it to Dart's `startSession`. */
    data class StartOutcome(
        val started: Boolean,
        val reason: String? = null,
        val message: String? = null,
    )

    /**
     * The `setModel` payload, parsed by the plugin.
     *
     * [authoredLengthMm] is the **external** heel-to-toe length of the physical sample
     * (architecture §2.5.1) and is the anchor every initial scale correction is a ratio against.
     * [yawOffsetDeg] comes from `alignment_json.yawOffsetDeg` when the row carries one.
     */
    data class ModelSpec(
        val path: String,
        val modelId: Long,
        val sha256: String,
        val authoredLengthMm: Double?,
        val yawOffsetDeg: Double?,
        /**
         * **The first of the two QA overrides on the model handover**: attempt the load even when
         * the renderer is below [Engine.FeatureLevel.FEATURE_LEVEL_2].
         *
         * Sent by the preview channel alone, from `AppConstants.shoePreviewAllowLevel1` — the AR
         * session hands over the same payload shape and must not be able to ask a crashing load
         * into existence. Default `false`, and a `true` is only honoured in a debuggable build:
         * see [allowsUnsupportedRenderer].
         */
        val allowUnsupportedRenderer: Boolean = false,

        /**
         * **The other QA override: bring the engine itself down to
         * [Engine.FeatureLevel.FEATURE_LEVEL_1]** — the phone class this feature's guard was
         * written for (D10), manufactured on whatever hardware is at hand instead.
         *
         * It *lowers* and can never raise: the ceiling is what `OpenGLContext` resolved from the
         * driver, so on a device already at level 1 or 0 this does nothing at all. The engine may
         * not exist yet when it arrives — the model is handed over the moment the page builds the
         * box, which is usually before the surface is ready — so it is applied in one of two
         * places: on the builder in [createEngineIfNeeded], or, if the renderer is already
         * running, through [Engine.setActiveFeatureLevel] in [applyEngineLevelRequest]. Both are
         * double-locked: see [shouldLowerEngineToLevel1].
         *
         * ⚠️ **On its own this produces the refusal rather than lifting it**: a level-1 engine
         * fails the same [canLoadModels] the owner's phone failed. Paired with
         * [allowUnsupportedRenderer] it is the experiment — can a level-1 renderer draw a shoe?
         */
        val lowerEngineToLevel1: Boolean = false,
    )

    /** `setSize` input, mirroring `lastLengthMm(size)` in `lib/utils/fit_engine.dart`. */
    data class SizeSpec(
        val sizeEu: Double?,
        val refSizeEu: Double?,
        val lastLengthMm: Double?,
    )

    /**
     * The AR surface. Null in [Mode.PREVIEW].
     *
     * ⚠️ A `SurfaceView` is what the AR path has always had, and it stays: it is the cheapest
     * surface and nothing scrolls under it there.
     */
    private val surfaceView: SurfaceView? = if (mode == Mode.AR) {
        SurfaceView(context).apply {
            holder.addCallback(this@ArTryOnView)
            // ARCore owns the camera and nothing is drawn behind this surface yet, so opaque is
            // correct until the feed becomes a Filament draw call (class header, gap 1).
            holder.setFormat(PixelFormat.OPAQUE)
            holder.setKeepScreenOn(true)
        }
    } else {
        null
    }

    /**
     * ⚠️ **The preview gets a `TextureView`, and that is not a style choice.**
     *
     * Android composites a `SurfaceView` in a **separate window layer** — which is exactly what an
     * AR screen wants and exactly what an inline box in the middle of a product page cannot have:
     * it does not clip to its layout box and it does not move with the content, so scrolling the
     * page slides the rest of the UI over and under a stationary shoe. `TextureView` composes into
     * the ordinary view hierarchy, so the preview scrolls like everything around it.
     */
    private val previewSurfaceListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
            surface = Surface(texture)
            surfaceWidth = width
            surfaceHeight = height
            renderHandler.post {
                createEngineIfNeeded()
                createSwapChain()
                view?.setViewport(Viewport(0, 0, width, height))
                startFrameLoop()
            }
        }

        override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
            surfaceWidth = width
            surfaceHeight = height
            renderHandler.post {
                view?.setViewport(Viewport(0, 0, width, height))
                // A resized `TextureView` hands back a new buffer queue, so the swap chain built
                // against the old one is stale — same reasoning as the AR path's `surfaceChanged`.
                createSwapChain()
            }
        }

        override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
            // ⚠️ **The surface is gone the moment this returns `true`.** `TextureView` calls
            // `nDestroyNativeWindow()` and releases the `SurfaceTexture` immediately after this
            // listener returns (`TextureView.releaseSurfaceTexture`), so a swap chain still bound
            // to that surface is left holding a dead buffer queue. That is the shape of the
            // teardown aborts in Filament's own tracker (`google/filament#6933` — a native
            // `SIGABRT` when a connected view is detached quickly; `#4724` — the same lifecycle
            // reaching a destroyed engine). So the swap chain is destroyed and the engine is
            // flushed **before** the surface goes away, and only then is `true` returned. That is
            // exactly `UiHelper.RendererCallback.onDetachedFromSurface` ("Required to ensure we
            // don't return before Filament is done executing the destroySwapChain command,
            // otherwise Android might destroy the Surface too early"), made bounded so a wedged
            // renderer cannot hold the UI thread.
            detachSurfaceAndWait()
            // `true`: this view has no other consumer of the texture, so the texture itself may be
            // released with it. The `Surface` wrapper above is ours to drop, and it is dropped.
            surface = null
            return true
        }

        override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
    }

    /** The preview's surface. Null in [Mode.AR]. */
    private val textureView: TextureView? = if (mode == Mode.PREVIEW) {
        TextureView(context).apply { surfaceTextureListener = previewSurfaceListener }
    } else {
        null
    }

    private val renderThread = HandlerThread("solevision-tryon-render").apply { start() }
    private val renderHandler = Handler(renderThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val choreographer: Choreographer by lazy { Choreographer.getInstance() }

    // ── Render-thread state. Never touched from another thread. ──────────────────────────────
    private var engine: Engine? = null
    private var renderer: Renderer? = null
    private var swapChain: SwapChain? = null
    private var scene: Scene? = null
    private var view: View? = null
    private var camera: Camera? = null
    private var cameraEntity = 0
    private var assetLoader: AssetLoader? = null
    private var materialProvider: UbershaderProvider? = null
    private var keyLight = 0
    private var fillLight = 0

    private var session: Session? = null

    /**
     * ⚠️ **Whether this renderer can load a glTF asset at all — measured, not assumed.**
     *
     * F14 (`docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`, measured on the Pixel_4 emulator API 37):
     * at `FEATURE_LEVEL_1` — i.e. any device whose ceiling is OpenGL ES 3.0, which is the class of
     * phone this market is most likely to hold — **every** asset load fails on the ubershader
     * material provider (`No material with the specified requirements exists`). And the failure is
     * not always catchable: F16 records a material/mesh mismatch as a *process abort*, and the
     * 2026-09-29 emulator run reproduced exactly that — a **SIGSEGV inside `libfilament-jni.so` on
     * this very thread, 126 ms after `Engine.create()`**, while loading the first real model.
     *
     * So the load is **refused before it is attempted**, and Dart is told
     * (`renderer_feature_level_unsupported`) instead of the customer's app dying on a product page.
     * The real fix for this device class is a material provider built on precompiled `.filamat`
     * files — the pattern SceneView uses for its own rendering, and the mitigation D10 records;
     * until that exists this flag is the difference between "no 3D here" and "it crashed".
     */
    private var modelLoadingSupported = true

    /**
     * **The measured facts behind a refusal, in one line, for the page rather than for logcat.**
     *
     * Two sources, because they answer different halves of one question. The device's advertised
     * GLES version and whether it advertises cube-map arrays come from `ActivityManager` (no EGL
     * context of our own is needed); the backend and Filament's two feature levels come from the
     * engine we just created. Together they decide whether `FEATURE_LEVEL_2` was reachable at all:
     * on GLES, Filament asks for an **ES2 context** and takes whatever the driver hands back, and
     * `resolveFeatureLevel` only promotes to level 2 for ES ≥ 3.1 *with* `GL_EXT_/OES_texture_cube_
     * map_array` — so "device says 3.2 but the engine says level 1" is itself the answer.
     *
     * ⚠️ It is carried in the **error messages** rather than only logged, and that is the whole
     * point: the phone this was written for (Huawei P30 Pro) has locked developer options, so no
     * `adb logcat` will ever be read from it. `SHOE_PREVIEW_DIAGNOSTICS` puts this line on the
     * product page.
     */
    private var rendererDiagnostic = "renderer not probed"

    private var sessionResumed = false
    private var surface: Surface? = null
    private var surfaceWidth = 0
    private var surfaceHeight = 0

    private var asset: FilamentAsset? = null
    private var modelRoot = 0
    private var pendingModel: ModelSpec? = null
    private var pendingAuthoredLengthMm: Double? = null
    private var yawOffsetDeg = 0.0

    /** Uniform scale from `setSize`; 1.0 until a size is selected. */
    private var sizeScale = 1.0f

    /** Placement as a 4×4 column-major matrix (translation in 12..14); identity until placed. */
    private val placement = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    private var placed = false
    private var placedYawDeg = 0f

    private var frames = 0
    private var frameWindowStartNanos = 0L
    private var lastLightSampleMs = 0L
    private var frameLoopRunning = false
    private var lastFrameNanos = 0L

    /**
     * Whether [teardown] has begun, and whether it has completed.
     *
     * `tearingDown` is the frame loop's stop sign and is set *before* anything is destroyed, so a
     * vsync already queued on this thread can never touch a dead engine; it also stops a surface
     * callback that arrives late from resurrecting a renderer. `tornDown` makes teardown
     * idempotent — both the surface callback and the plugin's `dispose` can arrive, in either
     * order, and the plugin's `unregister` can dispose the same view twice.
     */
    @Volatile private var tearingDown = false
    private var tornDown = false

    // ── QA self-report (`SHOE_PREVIEW_DIAGNOSTICS`) ──────────────────────────────────────────
    //
    // Added 2026-10-01, after the first real-device render: the box drew the sandal at
    // `FEATURE_LEVEL_1` — which falsifies F14/D10's "nothing loads at level 1" on real hardware —
    // then **froze after about a second** (the loop runs: the idle spin starts, so the shoe turns,
    // and then presents stop) and the app **died when the same box was opened a second time**
    // (leave the viewer, open it again, crash).
    //
    // Neither is diagnosable from the phone normally: it has no reachable logcat (its developer
    // options are locked behind a password its previous owner set), and every fact that would
    // distinguish "the loop stopped" from "the loop runs and nothing presents" was written to
    // `Log` alone. So the renderer describes itself on the page instead, once a second:
    //
    //  • `loop=` is the frame loop's own flag — the difference between a dead loop and a live one
    //    that is being asked for frames it cannot present;
    //  • `frames=` counts the presents in the last second, so "running but presenting nothing"
    //    has a number rather than an argument;
    //  • `chain=`/`creates=`/`lastSwapChainError` cover the leading hypothesis for the freeze:
    //    a `TextureView` size change recreates the swap chain, and a recreation that fails leaves
    //    `swapChain` null, at which point `renderFrame` returns early on every frame forever;
    //  • `engine=`/`touch=` answer the other two questions a finger cannot: whether the second
    //    open really is a *second* engine, and whether a touch ever reached this view at all.
    //
    // The last line is also **written to a file**, because the failure being chased kills the
    // process: a readout that dies with the app explains nothing, while the previous run's last
    // line survives to be read at the next launch (hence `fromLastRun`).

    /** On when Dart asked for the readout ([setDiagnostics]); never on in a customer build. */
    @Volatile private var diagnosticsEnabled = false

    /** Loop iterations since the last heartbeat — **not** the same as `presentedFrames`. */
    private var loopFrames = 0

    /** Frames that actually began and were presented since the last heartbeat. */
    private var presentedFrames = 0

    private var beginFrameFails = 0
    private var beginFrameFailStreak = 0
    private var swapChainRebuilds = 0
    private var lastStatusNanos = 0L
    private var statusSentOnce = false
    private var previousStatus: String? = null

    private var engineCreates = 0
    private var engineDestroys = 0
    private var swapChainCreates = 0
    private var swapChainRetryCount = 0
    private var lastSwapChainError: String? = null
    private var lastFrameError: String? = null

    /**
     * Touch events this view has received, split by action.
     *
     * `down` alone proves Flutter handed the arena over; `move` is the one that matters for
     * turning the shoe, because the orbit is advanced from `ACTION_MOVE` deltas — and a run whose
     * `down` climbs while `move` stays at zero is an input fault, not a renderer one.
     */
    @Volatile private var touchDowns = 0
    @Volatile private var touchMoves = 0
    @Volatile private var touchUps = 0

    /** Where the QA heartbeat is parked so a crash still leaves the last one readable. */
    private val statusFile: File? =
        runCatching { File(context.filesDir, STATUS_FILE_NAME) }.getOrNull()

    // ── Preview orbit state ──────────────────────────────────────────────────────────────────
    //
    // Written by the UI thread (touch) and read by the render thread (every frame), so the
    // scalars are `@Volatile` rather than posted: a drag posts a value per motion event, and
    // queueing those onto the render thread would put a touch backlog between the finger and the
    // shoe. A torn read of a single float is not a thing, and a frame that uses last frame's yaw
    // is invisible.

    /** Where the camera looks: the model's own bounding box centre, in world space. */
    private val previewCentre = FloatArray(3)

    /** Radius of the model's bounding sphere, in metres — the framing input. */
    private var previewRadiusM = 0.0

    @Volatile private var orbitYawDeg = INITIAL_YAW_DEG
    @Volatile private var orbitPitchDeg = INITIAL_PITCH_DEG
    @Volatile private var orbitZoom = 1.0f
    @Volatile private var interacting = false
    @Volatile private var lastInteractionMs = 0L

    private var lastTouchX = 0f
    private var lastTouchY = 0f

    /** Pinch → distance. Divides, so pushing the fingers apart brings the shoe closer. */
    private val scaleDetector = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                orbitZoom = (orbitZoom / detector.scaleFactor).coerceIn(MIN_ZOOM, MAX_ZOOM)
                lastInteractionMs = System.currentTimeMillis()
                return true
            }
        },
    )

    init {
        // The `?:` is the whole surface story in one line: AR has a `SurfaceView`, preview has a
        // `TextureView`, and there is never both.
        val content = surfaceView ?: textureView
        if (content != null) {
            addView(content, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }
        // The preview is turned with a finger; the AR view takes its taps through Flutter's
        // gesture arena (`EagerGestureRecognizer` on the Dart side), which is the same handover.
        isClickable = mode == Mode.PREVIEW
    }

    /**
     * Drag to turn, pinch to zoom, in [Mode.PREVIEW] only.
     *
     * Nothing here talks to the render thread directly — it writes the volatile orbit state the
     * next frame reads — so a fast drag cannot queue up behind a slow frame.
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (mode != Mode.PREVIEW) return super.onTouchEvent(event)
        scaleDetector.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchDowns++
                // ⚠️ **The only proof a finger reached this view.** "It loads but it won't turn"
                // is two different faults — a gesture that never arrives (the Dart-side handover)
                // and a camera that cannot move (the fit radius relayed after the load) — and with
                // nothing here they read as the same silence. One line per gesture, never per
                // move: a drag is a flood of MOVE events and the relay fsyncs every line.
                relay("touch: down #$touchDowns")
                lastTouchX = event.x
                lastTouchY = event.y
                interacting = true
                lastInteractionMs = System.currentTimeMillis()
            }
            MotionEvent.ACTION_MOVE -> {
                touchMoves++
                // A two-finger move belongs to the pinch, not to the orbit: without this the shoe
                // spins away while the customer is trying to zoom.
                if (!scaleDetector.isInProgress) {
                    val dx = event.x - lastTouchX
                    val dy = event.y - lastTouchY
                    orbitYawDeg = (orbitYawDeg - dx * DRAG_DEG_PER_PX) % 360f
                    orbitPitchDeg =
                        (orbitPitchDeg + dy * DRAG_DEG_PER_PX).coerceIn(MIN_PITCH_DEG, MAX_PITCH_DEG)
                    lastTouchX = event.x
                    lastTouchY = event.y
                }
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                lastInteractionMs = System.currentTimeMillis()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                touchUps++
                interacting = false
                lastInteractionMs = System.currentTimeMillis()
            }
        }
        return true
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // PUBLIC API — called by ArTryOnPlugin. Every entry posts to the render thread.
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * Parks the model (F18) or applies it.
     *
     * Legal before the view exists — that is the point: Dart hands the model over the moment it is
     * verified, because waiting for a view is a race it can lose on a cold page. V0's plugin
     * *dropped* a parked model, which is why the parking is explicit here and replayed on engine
     * creation.
     */
    /**
     * **The file channel — and on the phone this was written for, the only one there is.**
     *
     * ⚠️ Both faults being chased happened on a Huawei P30 Pro whose developer options are locked
     * behind a password its previous owner set, so `adb logcat` will *never* be read from it. The
     * on-page heartbeat ([emitStatus]) answers "what is the renderer doing right now"; this answers
     * "what happened on the way there" — the engine's level, the refusal, the load, the swap chain,
     * the teardown — through [DiagRelay], the Phase-1b channel that already mirrors Kotlin events
     * into the app's own `nav_diag.log`, which the app can hand out with a share sheet
     * (Foot Sizing → the bug icon). No adb, no logcat, no cable.
     *
     * Keep the call sites **discrete**. The relay holds one `O_APPEND` descriptor and `fsync`s every
     * line — that is what makes it survive a process death, and it is also why a per-frame call site
     * is wrong: the frame loop would push out the very lines being looked for.
     */
    private fun relay(message: String) = DiagRelay.log("preview", message)

    /**
     * Turns the QA self-report on for this view.
     *
     * `SHOE_PREVIEW_DIAGNOSTICS` is a Dart define, so the native side cannot read it — this is the
     * seam that carries it across. It is a *method* rather than a field on the model payload on
     * purpose: the readout has to work on a product whose model never arrives, and on a view whose
     * engine never came up, which is exactly the state a failed load or a refused renderer leaves
     * behind (and the state the second-open crash leaves behind is "no view at all").
     */
    fun setDiagnostics(enabled: Boolean) {
        diagnosticsEnabled = enabled
        if (!enabled) return
        // The previous run's last heartbeat, if there is one: the only way a status line survives
        // the crash it was describing. Read once, so it cannot be shown as if it were this run's.
        previousStatus = runCatching {
            statusFile?.takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
        }.getOrNull()
        emitStatus(lastFrameNanos, force = true)
    }

    fun setModel(spec: ModelSpec) {
        renderHandler.post {
            pendingModel = spec
            // Before the load, and before the engine exists if it does not yet: the QA request to
            // come up at level 1 is a property of the *renderer*, so it has to be in place by the
            // time the guard in [applyPendingModel] reads the level — otherwise the same run would
            // measure a level-2 engine and look like a failed experiment.
            applyEngineLevelRequest(spec)
            if (engine != null) applyPendingModel()
        }
    }

    /**
     * Recomputes the model's uniform scale for a selected EU size (§2.5.2).
     *
     * The rule is the shipped fit engine's, not a new one: a last grades at **6.67 mm per EU size**
     * (`sizeStepMm` in `lib/utils/fit_engine.dart`, architecture §2.6), so the render scale is
     * `lastLength(size) / lastLength(refSize)`. It is a *ratio of two sizing facts* rather than a
     * comparison against [ModelSpec.authoredLengthMm] deliberately: the authored length is
     * external, the last length is internal, and the offset between them is not knowable here.
     *
     * Two guards, because a bad number here inflates a model on a customer's screen: the step
     * delta is clamped to ±3 EU (the spirit of `kMaxExtrapolationSteps`), and any missing input
     * leaves the scale untouched rather than guessing.
     */
    fun setSize(spec: SizeSpec) {
        renderHandler.post {
            val size = spec.sizeEu
            val ref = spec.refSizeEu
            val last = spec.lastLengthMm
            if (size == null || ref == null || last == null || last <= 0.0) return@post
            var steps = size - ref
            if (steps.isNaN() || steps.isInfinite()) return@post
            if (abs(steps) > MAX_SIZE_STEPS) steps = MAX_SIZE_STEPS * Math.signum(steps)
            val graded = last + steps * SIZE_STEP_MM
            if (graded <= 0.0) return@post
            sizeScale = (graded / last).toFloat()
            applyTransform()
        }
    }

    /**
     * Applies a colour's material overrides to every material instance in the loaded asset.
     *
     * The payload is opaque on purpose: seller colour names are free text, so the Dart side owns
     * the name→paint decision and sends `{baseColorFactor: [r,g,b(,a)]}`. Anything else is
     * ignored — a key this build has not heard of is a newer Dart build, not an error.
     */
    fun setColor(overrides: Map<String, Any?>) {
        renderHandler.post {
            val values = when (val raw = overrides["baseColorFactor"]) {
                is List<*> -> raw.mapNotNull { (it as? Number)?.toFloat() }.toFloatArray()
                is FloatArray -> raw
                else -> FloatArray(0)
            }
            if (values.size != 3 && values.size != 4) return@post
            val rgba =
                if (values.size == 3) floatArrayOf(values[0], values[1], values[2], 1f) else values
            // `FilamentAsset` exposes no material-instance list on this gltfio version
            // (checked against the AAR), so the instances are reached the way Filament itself
            // exposes them: per renderable, per primitive.
            val created = engine ?: return@post
            val loaded = asset ?: return@post
            val manager = created.renderableManager
            val seen = linkedSetOf<MaterialInstance>()
            var applied = 0
            for (entity in loaded.renderableEntities) {
                val instance = manager.getInstance(entity)
                for (primitive in 0 until manager.getPrimitiveCount(instance)) {
                    val material = manager.getMaterialInstanceAt(instance, primitive)
                    if (!seen.add(material)) continue
                    // `setParameter` is void, so success is "it did not throw": a material with no
                    // `baseColorFactor` logs inside Filament and is simply not counted.
                    val ok = runCatching {
                        material.setParameter(
                            "baseColorFactor",
                            rgba[0],
                            rgba[1],
                            rgba[2],
                            rgba[3],
                        )
                    }.isSuccess
                    if (ok) applied++
                }
            }
            Log.i(TAG, "setColor applied to $applied/${seen.size} distinct material instances")
        }
    }

    /**
     * Places the shoe at a screen point, in **logical (Flutter) pixels of this view**.
     *
     * Real AR placement first: ARCore's `hitTest` against detected horizontal planes. Before a
     * plane is in view — normal for the first second or two, and the case every cold session starts
     * in — it falls back to the analytic floor ray built from ARCore's own projection matrix, so a
     * tap still does something sensible instead of silently doing nothing (D8's rule, applied to
     * input).
     */
    fun placeShoe(x: Double, y: Double) {
        // Nothing to place: the preview's camera moves and the shoe stays where the contract put
        // it (grounded at the origin, long axis +Z). A tap there is a drag, handled by
        // `onTouchEvent`.
        if (mode == Mode.PREVIEW) return
        renderHandler.post {
            val activeSession = session ?: return@post
            val density = resources.displayMetrics.density.toDouble()
            val px = (x * density).toFloat()
            val py = (y * density).toFloat()
            val frame = runCatching { activeSession.update() }.getOrNull() ?: return@post
            val pose = firstFloorHit(frame, px, py) ?: rayToFloor(frame, px.toDouble(), py.toDouble())
            if (pose != null) applyPlacement(pose, yawFromQuaternion(frame.camera.pose.rotationQuaternion))
        }
    }

    /** A PNG of the current frame, or null when there is nothing to copy. */
    fun captureScreenshot(onResult: (ByteArray?) -> Unit) {
        // The share-sheet image belongs to the AR screen (it is also the only place that offers
        // it). Answering null rather than building a second PixelCopy path over a `TextureView`
        // keeps this file to one surface contract per mode.
        val target = surfaceView
        if (target == null) {
            Log.i(TAG, "captureScreenshot: preview mode has no screenshot path")
            onResult(null)
            return
        }
        val width = target.width
        val height = target.height
        if (width <= 0 || height <= 0) {
            onResult(null)
            return
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        // PixelCopy rather than Filament's readPixels: it copies the *composited* surface, so the
        // day the camera feed is a real layer in this view the screenshot picks it up for free —
        // §2.8's share-sheet image is "what the customer saw", not "what Filament drew".
        PixelCopy.request(
            target,
            bitmap,
            { result ->
                if (result != PixelCopy.SUCCESS) {
                    Log.w(TAG, "captureScreenshot: PixelCopy result=$result")
                    onResult(null)
                    return@request
                }
                onResult(
                    runCatching {
                        ByteArrayOutputStream().use { out ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                            out.toByteArray()
                        }
                    }.getOrNull(),
                )
            },
            mainHandler,
        )
    }

    /**
     * The QA/capability switch (§2.8's `setTryOnMode`).
     *
     * `floor` is what V3 ships; `foot` is V4's tracked mode, which needs the detection loop and so
     * currently behaves like `floor`. Recorded rather than rejected, so a device session sees the
     * wrong mode in the log instead of a silent no-op.
     */
    fun setTryOnMode(mode: String) {
        Log.i(TAG, "setTryOnMode: $mode (V3 implements floor placement; foot arrives with V4)")
    }

    /**
     * Creates and resumes the ARCore session on the render thread.
     *
     * Permission and ARCore install are already handled by the plugin on the UI thread — those two
     * need an `Activity` and a main thread; this needs neither.
     */
    fun startSession(onResult: (StartOutcome) -> Unit) {
        // ⚠️ Answered without touching ARCore, not merely refused later: constructing a `Session`
        // here would put ARCore's install prompt and camera permission in front of a customer who
        // only scrolled past a product page.
        if (mode == Mode.PREVIEW) {
            postToMain {
                onResult(
                    StartOutcome(
                        started = false,
                        reason = "preview_mode",
                        message = "the inline 3D preview runs no AR session",
                    ),
                )
            }
            return
        }
        renderHandler.post {
            if (session != null && sessionResumed) {
                postToMain { onResult(StartOutcome(started = true)) }
                return@post
            }
            try {
                val created = session ?: Session(context).also { session = it }
                created.configure(
                    Config(created).apply {
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        // Ambient intensity, not ENVIRONMENTAL_HDR: HDR light estimation needs the
                        // camera texture, which this route cannot draw yet.
                        lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                        updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                        focusMode = Config.FocusMode.AUTO
                    },
                )
                created.resume()
                sessionResumed = true
                Log.i(TAG, "session resumed")
                postToMain { onResult(StartOutcome(started = true)) }
            } catch (t: Throwable) {
                val outcome = sessionFailure(t)
                Log.w(TAG, "startSession failed: ${outcome.reason} — ${outcome.message}", t)
                relay("startSession failed: ${outcome.reason} — ${outcome.message}")
                postToMain { onResult(outcome) }
            }
        }
    }

    /** Pauses the session. QA and tests only — teardown is owned by [dispose] (rule D1). */
    fun pauseSession() {
        renderHandler.post {
            runCatching { session?.pause() }.onFailure { Log.w(TAG, "pause failed", it) }
            sessionResumed = false
        }
    }

    /**
     * Full teardown on the render thread, in destroy order, idempotent because both
     * `surfaceDestroyed` and the plugin's `dispose` can arrive, in either order.
     */
    fun dispose() {
        // The latch is how the *next* view knows this teardown finished: see
        // `createEngineIfNeeded` and the second-open crash it answers. Counted down in a `finally`
        // so a throwing teardown cannot leave the next engine creation waiting for it.
        val finished = CountDownLatch(1)
        pendingTeardown = finished
        relay("dispose(): teardown posted — the next engine creation waits on the latch")
        val posted = renderHandler.post {
            try {
                teardown()
            } finally {
                renderThread.quitSafely()
                finished.countDown()
                if (pendingTeardown === finished) pendingTeardown = null
                relay("dispose(): finished — latch down, a new engine may be created")
            }
        }
        if (!posted) {
            // A second `dispose()` after this view's render thread already quit: nothing is left
            // to tear down, and a latch left un-counted-down would make the next view's
            // `createEngineIfNeeded` wait out its full timeout for nothing.
            finished.countDown()
            if (pendingTeardown === finished) pendingTeardown = null
            relay("dispose(): render thread already quit — latch dropped")
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Surface lifecycle
    // ════════════════════════════════════════════════════════════════════════════════════════

    override fun surfaceCreated(holder: SurfaceHolder) {
        surface = holder.surface
        renderHandler.post {
            createEngineIfNeeded()
            createSwapChain()
            startFrameLoop()
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        surfaceWidth = width
        surfaceHeight = height
        val rotation = runCatching { display?.rotation }.getOrNull()
        renderHandler.post {
            // `setViewport` takes a `Viewport`, not four ints (Filament 1.72's Java API).
            view?.setViewport(Viewport(0, 0, width, height))
            createSwapChain()
            if (rotation != null) {
                runCatching { session?.setDisplayGeometry(rotation, width, height) }
                    .onFailure { t -> Log.w(TAG, "setDisplayGeometry failed", t) }
            }
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        // ⚠️ The `SurfaceHolder.Callback` contract: "If you have a rendering thread that directly
        // accesses the surface, you must ensure that thread is no longer touching the Surface
        // before returning from this function." Posting the teardown and returning was exactly
        // that violation; the preview's bounded helper now does the work here too (this is shared
        // with AR mode and is the one line of AR's surface path this change touches).
        detachSurfaceAndWait(pauseSession = true)
        surface = null
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Engine / renderer
    // ════════════════════════════════════════════════════════════════════════════════════════

    private fun createEngineIfNeeded() {
        // A surface callback that arrives after dispose must not resurrect a renderer on a view
        // whose teardown is already running (or done): everything it would build would be
        // destroyed underneath it. Same thread as teardown, so the flag is a reliable barrier.
        if (tearingDown) return
        if (engine != null) return
        // ⚠️ One engine at a time, and the reason is a real-device crash (2026-10-01): opening the
        // viewer, leaving it and opening it again kills the app. `dispose()` tears the previous
        // view down *asynchronously on its own render thread*, so a second open used to build a
        // new engine while the old one was still being destroyed underneath it. The wait is
        // bounded: a wedged teardown must not become a hang on a customer's phone.
        val pending = pendingTeardown
        if (pending != null) {
            val settled = runCatching { pending.await(TEARDOWN_WAIT_SECONDS, TimeUnit.SECONDS) }
                .getOrDefault(false)
            relay(
                if (settled) "waited on the previous teardown: it finished"
                else "the previous teardown was still running after ${TEARDOWN_WAIT_SECONDS}s " +
                    "— creating an engine anyway",
            )
        }
        // Findings: these two are not optional and nothing else calls them. Without them the first
        // Engine.create() dies with UnsatisfiedLinkError (GltfioDecodeTest, finding 1).
        Filament.init()
        Gltfio.init()

        // OpenGL, deliberately, and **not** a probe for a better backend: asking Filament for Vulkan
        // on a device whose Vulkan cannot build an instance aborts the process from its own render
        // thread (`Fatal signal 6`, measured on the Pixel_4 emulator — see F24). The backend cannot
        // be chosen by trying; it can only be chosen by refusing, which is what [canLoadModels] is
        // for.
        //
        // The QA level request belongs **here** when it can be honoured here, rather than always
        // after the fact: a renderer that is never allowed to reach level 2 does not have to be
        // talked down from it, and the builder is the only place that exists before a single frame
        // is drawn. See [shouldLowerEngineToLevel1].
        //
        // ⚠️ **Asking for the level is not optional, and not asking was the fault.** Filament's
        // `BuilderDetails::mFeatureLevel` defaults to `FEATURE_LEVEL_1`
        // (`filament/src/details/Engine.cpp`, v1.72.1) and `FEngine::init()` then takes
        // `std::min(requested, driverApi.getFeatureLevel())` — the level can only be clamped
        // *down*, never raised. So an engine built without a request comes up at level 1 on a
        // device whose driver reports 2: measured on a GLES 3.2 PowerVR phone (2026-10-01), the
        // device log read `Feature level: 2` → `Backend feature level: 2` → `FEngine feature
        // level: 1`, and [canLoadModels] then refused every model with a sentence about the phone
        // when the phone was never the problem. Asking for level 2 is the honest request — it is
        // what the glTF material path needs — and a device whose ceiling is level 1 or 0 is
        // unaffected, because the answer is the driver's clamp, not ours.
        // ⚠️ The pair of lines a crash is read from, and the reason they are relays rather than
        // Log calls: on the phone with no adb this file is the only record of a fault, and the new
        // P30 Pro crash (opening the viewer, 2026-10-01) arrives without a stack. Between the
        // platform view's creation and the engine-ready line further down sits the whole native
        // setup, so without a line at each end of the builder an exported log cannot say whether
        // the process died inside `Engine.Builder.build()` or in the scene/renderer/view/loader
        // construction after it. The device's own claim travels on the first line, so a run that
        // never reaches the post-engine facts still says what the phone said it could do.
        val requestedLevel = if (shouldLowerEngineToLevel1(pendingModel)) {
            "FEATURE_LEVEL_1 (QA)"
        } else {
            "FEATURE_LEVEL_2"
        }
        relay("engine creation BEGIN: requested=$requestedLevel · ${deviceFacts()}")
        val engineBuilder = Engine.Builder()
        if (shouldLowerEngineToLevel1(pendingModel)) {
            engineBuilder.featureLevel(Engine.FeatureLevel.FEATURE_LEVEL_1)
            Log.w(
                TAG,
                "QA: building the engine at FEATURE_LEVEL_1 (SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1)",
            )
        } else {
            engineBuilder.featureLevel(Engine.FeatureLevel.FEATURE_LEVEL_2)
        }
        val created = engineBuilder.build()
        engine = created
        engineCreates++
        relay(
            "engine built: backend=${created.backend} supported=${created.supportedFeatureLevel} " +
                "active=${created.activeFeatureLevel} · scene/renderer/view/loader next",
        )
        val createdScene = created.createScene()
        scene = createdScene
        renderer = created.createRenderer()
        view = created.createView().apply { setScene(createdScene) }
        cameraEntity = EntityManager.get().create()
        camera = created.createCamera(cameraEntity).apply {
            setProjection(FOV_DEGREES, 1.0, NEAR_METERS, FAR_METERS, Camera.Fov.VERTICAL)
        }
        view?.camera = camera
        val provider = UbershaderProvider(created)
        materialProvider = provider
        assetLoader = AssetLoader(created, provider, EntityManager.get())
        createLights(created)
        renderer?.setClearOptions(
            Renderer.ClearOptions().apply {
                clear = true
                // A flat, dark backdrop where the camera feed will be (class header, gap 1).
                // `ClearOptions.clearColor` is a `double[]` on this API, not a `float[]`.
                clearColor = doubleArrayOf(0.055, 0.06, 0.07, 1.0)
            },
        )
        Log.i(
            TAG,
            "engine ready: backend=${created.backend} supportedFeatureLevel=" +
                "${created.supportedFeatureLevel} activeFeatureLevel=${created.activeFeatureLevel}",
        )
        relay(
            "engine ready: backend=${created.backend} supported=${created.supportedFeatureLevel} " +
                "active=${created.activeFeatureLevel}",
        )

        // The material path below `FEATURE_LEVEL_2` cannot resolve a glTF's materials and can take
        // the process down with it — see [modelLoadingSupported]. Read from the *active* level
        // rather than the supported one: a build that asks for a lower level (a power saving, a QA
        // switch) is just as unable to load as a device that cannot go higher.
        modelLoadingSupported = canLoadModels(created)
        if (!modelLoadingSupported) {
            Log.w(
                TAG,
                "renderer is ${created.activeFeatureLevel}: glTF/ubershader materials cannot load " +
                    "here (F14) — refusing every model rather than aborting the process (F16)",
            )
            relay(
                "renderer ${created.activeFeatureLevel}: will refuse every model (F14/F16) — " +
                    "$rendererDiagnostic",
            )
        }
        // Read once, after the engine is up, whatever the answer: the refusal's message and a
        // failed load both carry it, and the page is where it is read.
        rendererDiagnostic = describeRenderer(created)
        Log.i(TAG, "renderer facts: $rendererDiagnostic")
        relay("renderer facts: $rendererDiagnostic")

        // F18: the model may have arrived before the engine existed.
        applyPendingModel()
    }

    /**
     * Whether this engine can load a glTF at all.
     *
     * Read from the **active** feature level rather than the supported one: a build that asks for a
     * lower level (a power saving, a QA switch) is just as unable to load as a device that cannot go
     * higher.
     */
    private fun canLoadModels(candidate: Engine): Boolean =
        candidate.activeFeatureLevel.ordinal >= Engine.FeatureLevel.FEATURE_LEVEL_2.ordinal

    /**
     * **The engine's half of [rendererDiagnostic]**: what Filament came up on, at which levels, on
     * what the device says it can do.
     *
     * ⚠️ **The pair is the point, and it is why both halves are printed.**
     * `ConfigurationInfo.getGlEsVersion()` is the *device's* ceiling ("3.2") — a different
     * question from the context Filament was handed — and `getSupportedFeatureLevel()` is what the
     * context it actually got was worth. So:
     *
     *  • **device 3.2 + supported 1** — the context came back below what the phone can do.
     *    Filament requests an **ES2 context** and takes what the driver returns
     *    (`PlatformEGL.createDriver`), so this is the shape of "the driver honoured the request".
     *  • **device 3.0** — D10's phone class, where level 2 is out of reach under *any*
     *    configuration and only a level-1-compatible material path could draw.
     *
     * What this line deliberately does **not** claim is which of the two level-2 preconditions
     * failed when it reads `supported 1` on a 3.2 device: the other one is
     * `GL_EXT_/OES_texture_cube_map_array`, whose extension string lives on
     * `ActivityManager.DeviceConfigurationInfo` — **not in the public SDK**, so a probe would mean
     * a second EGL context purely for a diagnostic. The QA override answers that question the
     * honest way instead: by trying the load.
     *
     * Wrapped because a diagnostic must never be the reason a product page fails: a context with no
     * `ActivityManager` (a test harness, a detached view) answers "?" rather than throwing inside
     * engine creation.
     */
    private fun describeRenderer(created: Engine): String {
        val device = deviceGlesClaim()
        return "${created.backend} supported=${created.supportedFeatureLevel} " +
            "active=${created.activeFeatureLevel} · $device"
    }

    /**
     * **What the device claims, read before any engine exists** — its model, API level and the GLES
     * version `ActivityManager` advertises.
     *
     * It rides on [createEngineIfNeeded]'s opening relay so a run that dies inside
     * `Engine.Builder.build()` still says which phone died and what that phone promised. Set beside
     * [describeRenderer]'s post-engine facts it is the pair that reads honestly: a GLES 3.2 claim
     * next to a level-1 context is the miss no amount of trying can fix, and that comparison only
     * exists if both halves were written down.
     *
     * Wrapped for the same reason [describeRenderer] is: a diagnostic must never be the reason a
     * viewer fails, and a detached view has no `ActivityManager` to ask.
     */
    private fun deviceFacts(): String =
        "device ${Build.MODEL} · SDK ${Build.VERSION.SDK_INT} · ${deviceGlesClaim()}"

    /** The device's advertised GLES version, or the `?` a context-less harness gets. */
    private fun deviceGlesClaim(): String = runCatching {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        manager?.deviceConfigurationInfo?.glEsVersion?.let { "device GLES $it" } ?: "device GLES ?"
    }.getOrElse { "device GLES ?" }

    /**
     * **Whether a load below `FEATURE_LEVEL_2` may proceed, and the two locks on it.**
     *
     * The refusal this relaxes is a crash guard rather than a policy: on a `FEATURE_LEVEL_1`
     * renderer the production loader took the process down with a `SIGSEGV` 126 ms after
     * `Engine.create()` (F22), and the attempt is not catchable. The other half of the same finding
     * is that level 1 has **never been tried on real hardware** — F14's "nothing loads" was one
     * emulator, whose GLES is a translator (F24), and D10 still reads "unverified on real
     * hardware". Nothing in the ubershader materials marks them level-2-only: they are
     * built with `matc -a opengl -a vulkan -p mobile` from the `mat.in` templates under
     * `libs/gltfio/materials`, none of which declares a feature level, so they carry filamat's
     * default — `FeatureLevel::FEATURE_LEVEL_1`, the exact level this override asks the engine to
     * accept. What is *known* to be out of reach is a feature-level-0 engine: matc emits the ESSL1
     * permutation only for materials that declare level 0, and a level-1 package fails
     * `hasFeatureLevel()` on a level-0 engine. So the question "can the cheapest phones in this
     * market draw a shoe?" can only be answered by letting one try, somewhere it is allowed to die.
     *
     *  • **Lock 1 — the caller asks.** [ModelSpec.allowUnsupportedRenderer], which only the preview
     *    channel sets, from `SHOE_PREVIEW_ALLOW_LEVEL1`.
     *  • **Lock 2 — the build cannot ship.** A published release APK is not `FLAG_DEBUGGABLE`, so a
     *    customer build ignores the request even if the define leaks into it. (`BuildConfig.DEBUG`
     *    is the obvious spelling; `ApplicationInfo` is used instead because AGP 8 does not generate
     *    `BuildConfig` unless a module opts in, and this file must not depend on a Gradle switch.)
     */
    private fun allowsUnsupportedRenderer(spec: ModelSpec?): Boolean {
        if (spec?.allowUnsupportedRenderer != true) return false
        if (!debuggableBuild()) {
            Log.w(TAG, "level-1 override requested in a non-debuggable build — ignored")
            return false
        }
        Log.w(
            TAG,
            "QA level-1 override ACTIVE: attempting the glTF load below FEATURE_LEVEL_2 — this may " +
                "kill the process (F22); $rendererDiagnostic",
        )
        relay(
            "QA load override ACTIVE: a glTF load below ${Engine.FeatureLevel.FEATURE_LEVEL_2} on " +
                "this renderer may kill the process (F22); $rendererDiagnostic",
        )
        return true
    }

    /**
     * **Whether the engine may be brought down to `FEATURE_LEVEL_1`, and the two locks on it.**
     *
     * This is the other half of the question [allowsUnsupportedRenderer] answers: that one lets a
     * load happen on an engine that is *already* low, which measures nothing at all on a phone whose
     * renderer is level 2 — the guard was never going to fire there and the box simply draws. This
     * one manufactures the phone class instead, so the level-1 path can be exercised on hardware
     * that is sitting in the room, rather than on the one device that cannot be read (D10 still
     * reads "unverified on real hardware").
     *
     *  • **Lock 1 — the caller asks.** [ModelSpec.lowerEngineToLevel1], which only the preview
     *    channel sets, from `SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1`.
     *  • **Lock 2 — the build cannot ship.** The same [debuggableBuild] check as the load override,
     *    for a stronger reason than that one had: lowering the renderer on purpose is not a crash
     *    that a customer might hit, it is a permanently worse product on their phone.
     *
     * It cannot raise anything: it only ever *requests* the lower level, and Filament keeps
     * `min(requested, driver)` (`FEngine::init`), so a device already at level 1 or 0 is unaffected
     * by its own ceiling being asked for. The mirror of this call — the plain `FEATURE_LEVEL_2`
     * request [createEngineIfNeeded] now makes on every other path — is what a level-2 device
     * needs; this switch exists only to ask for the level *below* its ceiling.
     */
    private fun shouldLowerEngineToLevel1(spec: ModelSpec?): Boolean {
        if (spec?.lowerEngineToLevel1 != true) return false
        if (!debuggableBuild()) {
            Log.w(TAG, "level-1 engine request in a non-debuggable build — ignored")
            return false
        }
        return true
    }

    /**
     * Whether this APK is a debug build, which is **lock 2** on both QA switches.
     *
     * `BuildConfig.DEBUG` is the obvious spelling; `ApplicationInfo` is used instead because AGP 8
     * does not generate `BuildConfig` unless a module opts in, and this file must not depend on a
     * Gradle switch. A published release APK is not `FLAG_DEBUGGABLE`, so a customer build ignores
     * either request even if a define leaks into one.
     */
    private fun debuggableBuild(): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /**
     * **Applies [ModelSpec.lowerEngineToLevel1] to an engine that is already running.**
     *
     * The builder path in [createEngineIfNeeded] covers the usual order — the model is handed over
     * the moment the box is built, which is normally before the surface, and so before the engine.
     * This covers the other one, because a QA switch that silently does nothing when the surface
     * happens to win the race would be worse than no switch at all: the run would look like the
     * experiment had failed.
     *
     * [Engine.setActiveFeatureLevel] is the only route here, and it can only lower — the builder owns
     * the ceiling. Deliberately, both `modelLoadingSupported` and [rendererDiagnostic] are re-read
     * afterwards: the refusal message and the page's readout must never claim the level the engine
     * used to have, or a screenshot of a lowered run would be indistinguishable from a capped one.
     */
    private fun applyEngineLevelRequest(spec: ModelSpec) {
        if (!shouldLowerEngineToLevel1(spec)) return
        val created = engine
        if (created == null) {
            // Not a miss: [createEngineIfNeeded] reads `pendingModel` and builds at level 1.
            Log.i(TAG, "QA: level-1 engine request parked until the engine is built")
            return
        }
        if (created.activeFeatureLevel.ordinal <= Engine.FeatureLevel.FEATURE_LEVEL_1.ordinal) {
            Log.i(TAG, "QA: engine is already ${created.activeFeatureLevel} — nothing to lower")
            return
        }
        val applied = created.setActiveFeatureLevel(Engine.FeatureLevel.FEATURE_LEVEL_1)
        modelLoadingSupported = canLoadModels(created)
        rendererDiagnostic = describeRenderer(created)
        Log.w(
            TAG,
            "QA: engine lowered to $applied — glTF loading is now refused unless the load override " +
                "is on too; $rendererDiagnostic",
        )
    }

    /**
     * Key + fill directional lights.
     *
     * Two lights and no IBL is a deliberate floor: the pair gives the shoe a lit and a shaded side
     * so its form reads, and the ambient level and colour come from ARCore's light estimate (see
     * [sampleArLighting]). It is *not* a substitute for an environment map — no reflections, which
     * on a leather or patent upper is the first thing a customer notices. The intensities are
     * starting values: nobody has looked at a render yet (V0.6), and tuning them is a device-session
     * task, not a desk one.
     *
     * The directions here are the *yaw=0* ones. In AR the camera barely moves and ARCore supplies
     * the ambient term, so a world-fixed rig is right; the preview orbits a full 360°, where a
     * world-fixed rig would put the unlit side towards the customer for half the turn — the shoe
     * would visibly go dark as it spun. `applyPreviewLightRig` re-aims the pair at the camera.
     */
    private fun createLights(created: Engine) {
        keyLight = EntityManager.get().create()
        // `Builder` is a nested class, so it is `LightManager.Builder(...)` — not a member of the
        // manager *instance*.
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f)
            .intensity(KEY_LUX)
            .direction(PREVIEW_KEY_DIR[0], PREVIEW_KEY_DIR[1], PREVIEW_KEY_DIR[2])
            .castShadows(false)
            .build(created, keyLight)
        fillLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.85f, 0.9f, 1.0f)
            .intensity(FILL_LUX)
            .direction(PREVIEW_FILL_DIR[0], PREVIEW_FILL_DIR[1], PREVIEW_FILL_DIR[2])
            .castShadows(false)
            .build(created, fillLight)
        scene?.addEntity(keyLight)
        scene?.addEntity(fillLight)
    }

    private fun createSwapChain() {
        val created = engine ?: return
        val target = surface ?: return
        destroySwapChain()
        swapChainCreates++
        lastSwapChainError = null
        swapChain = runCatching { created.createSwapChain(target) }
            .onFailure {
                lastSwapChainError = "${it::class.java.simpleName}: ${it.message}"
                Log.w(TAG, "createSwapChain failed", it)
                relay("createSwapChain failed: $lastSwapChainError")
            }
            .getOrNull()
        if (swapChain == null) {
            scheduleSwapChainRetry()
        } else {
            swapChainRetryCount = 0
            relay("swap chain built (creates=$swapChainCreates, ${surfaceWidth}x$surfaceHeight)")
        }
    }

    /**
     * **A retry, because the alternative is a box that never presents again.**
     *
     * A null swap chain is exactly the shape of the first device report's freeze — "it moves for a
     * second then it stops": `renderFrame` returns early while the loop keeps running, so the
     * customer gets a still picture that no finger can move, and nothing on the page says so. The
     * likeliest trigger is the preview's `TextureView` reporting a size change (which destroys and
     * rebuilds the chain) landing at a moment the surface is not ready for a new one. Bounded, so
     * a chain that cannot be built at all reports rather than spins.
     */
    private fun scheduleSwapChainRetry() {
        if (swapChainRetryCount >= MAX_SWAP_CHAIN_RETRIES) return
        swapChainRetryCount++
        relay(
            "swap chain NULL — retry $swapChainRetryCount/$MAX_SWAP_CHAIN_RETRIES in " +
                "${SWAP_CHAIN_RETRY_MS}ms",
        )
        renderHandler.postDelayed({ createSwapChain() }, SWAP_CHAIN_RETRY_MS)
    }

    private fun destroySwapChain() {
        swapChain?.let { engine?.destroySwapChain(it) }
        swapChain = null
    }

    /**
     * **Stops the loop, destroys the swap chain and flushes the engine — while the surface is
     * still valid.**
     *
     * Both Android surface contracts forbid touching the surface from the rendering thread after
     * the callback returns (`SurfaceHolder.Callback.surfaceDestroyed` says so explicitly, and
     * `TextureView` destroys its native window and releases its `SurfaceTexture` the moment the
     * listener says it may). Filament's own Android lifecycle pattern does this synchronously in
     * [`UiHelper.RendererCallback.onDetachedFromSurface`](https://github.com/google/filament/blob/v1.72.1/android/filament-android/src/main/java/com/google/android/filament/android/UiHelper.java)
     * and documents why: returning before the destroy finishes lets Android destroy the Surface
     * too early. This file keeps every Filament call on the render thread, so the work is posted
     * there and the caller waits — **bounded**, because the main thread must never block
     * indefinitely on a renderer; a timed-out wait returns to the framework rather than becoming an
     * ANR, and the next surface arrival rebuilds.
     */
    private fun detachSurfaceAndWait(pauseSession: Boolean = false) {
        val done = CountDownLatch(1)
        val posted = renderHandler.post {
            try {
                if (pauseSession) {
                    runCatching { session?.pause() }
                    sessionResumed = false
                }
                frameLoopRunning = false
                destroySwapChain()
                relay("surface detached: loop stopped, swap chain destroyed")
                val created = engine
                if (created != null) {
                    val flushed = runCatching { created.flushAndWait(SURFACE_FLUSH_TIMEOUT_NANOS) }
                        .getOrDefault(false)
                    relay("surface detached: flushAndWait=${if (flushed) "ok" else "timeout"}")
                }
            } finally {
                done.countDown()
            }
        }
        // A quit render thread has already torn everything down (dispose); there is nothing to
        // wait for, and posting would return false rather than enqueue.
        if (!posted) return
        runCatching { done.await(SURFACE_TEARDOWN_WAIT_MS, TimeUnit.MILLISECONDS) }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Frame loop
    // ════════════════════════════════════════════════════════════════════════════════════════

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!frameLoopRunning || tearingDown) return
            try {
                renderFrame(frameTimeNanos)
            } catch (t: Throwable) {
                // ⚠️ An exception escaping a `Choreographer` callback on this thread takes the whole
                // process down (Android's default uncaught-exception handler is process-wide), so a
                // failure here used to be a crash with no report anywhere. It becomes one line, a
                // stopped loop and a frozen box instead: a frozen box is a bug report, a dead app is
                // a lost customer.
                lastFrameError = "${t::class.java.simpleName}: ${t.message}"
                Log.w(TAG, "renderFrame threw; stopping the loop", t)
                relay("renderFrame threw, loop STOPPED: $lastFrameError")
                frameLoopRunning = false
                listener.onError("preview_frame_failed", lastFrameError)
                emitStatus(frameTimeNanos, force = true)
                return
            }
            if (frameLoopRunning) choreographer.postFrameCallback(this)
            loopFrames++
            emitStatus(frameTimeNanos, force = false)
        }
    }

    /**
     * The QA heartbeat: at most once a second, and only when Dart asked for it.
     *
     * One string rather than a dozen named fields, because the consumer is a screenshot on a phone
     * with no logcat: whoever reads it needs the whole state in one line, not a payload to parse.
     * `STATUS_FILE_NAME` also gets the same line, which is what makes the readout survive the crash
     * it is describing.
     */
    private fun emitStatus(frameTimeNanos: Long, force: Boolean) {
        if (!diagnosticsEnabled) return
        if (!force && lastStatusNanos != 0L &&
            frameTimeNanos - lastStatusNanos < STATUS_PERIOD_NANOS
        ) {
            return
        }
        val shownLoop = loopFrames
        val shownPresented = presentedFrames
        loopFrames = 0
        presentedFrames = 0
        lastStatusNanos = frameTimeNanos
        val line = buildString {
            append("loop=").append(if (frameLoopRunning) "on" else "STOPPED")
            // ⚠️ `loop=` and `present=` are different numbers on purpose. The first readout from a
            // real device showed `loop=on frames=61` on a box whose picture had not changed since
            // it opened: 61 was *loop iterations*, and the original counter hid the fact that
            // `beginFrame` was refusing every one of them.
            append(" iter=").append(shownLoop)
            append(" present=").append(shownPresented)
            append(" beginFail=").append(beginFrameFails)
            append(" rebuild=").append(swapChainRebuilds)
            // The one "why" Filament tells us from Java: an engine that hit an unrecoverable
            // backend error (`Engine.hasUnrecoverableFailure`) explains a `beginFail` no chain
            // rebuild can clear. There is no per-frame refusal reason on this API, and none is
            // invented here — this is the only flag the engine exposes.
            append(" unrec=").append(if (engine?.hasUnrecoverableFailure() == true) "1" else "0")
            append(" engine=").append(engineCreates).append('/').append(engineDestroys)
            append(" chain=").append(if (swapChain != null) "ok" else "NULL")
            append(" creates=").append(swapChainCreates)
            append(" surface=").append(if (surface != null) "ok" else "NULL")
            append(" asset=").append(if (asset != null) "ok" else "NULL")
            append(" r=").append((previewRadiusM * 1000.0).roundToInt()).append("mm")
            append(" yaw=").append(orbitYawDeg.roundToInt())
            append(" touch=").append(touchDowns).append('/').append(touchMoves)
                .append('/').append(touchUps)
            append(" interacting=").append(if (interacting) "1" else "0")
            append(" size=").append(surfaceWidth).append('x').append(surfaceHeight)
        }
        runCatching { statusFile?.writeText(line) }
        val payload = mutableMapOf<String, Any?>("line" to line, "loopRunning" to frameLoopRunning)
        lastFrameError?.let { payload["lastFrameError"] = it }
        lastSwapChainError?.let { payload["lastSwapChainError"] = it }
        if (!statusSentOnce) {
            statusSentOnce = true
            // Only the first heartbeat of a run carries it, so a line from a process that has since
            // died can never be mistaken for a live one.
            previousStatus?.let { payload["fromLastRun"] = it }
        }
        listener.onEvent("status", payload)
    }

    private fun startFrameLoop() {
        if (frameLoopRunning || tearingDown) return
        frameLoopRunning = true
        // A fresh loop has no previous frame: without this the first delta after a pause is the
        // whole pause, and the idle spin jumps on resume.
        lastFrameNanos = 0L
        choreographer.postFrameCallback(frameCallback)
    }

    /**
     * The preview camera: the model's own bounding sphere, seen from an orbit the customer drives.
     *
     * Filament's `lookAt`/`setProjection` rather than a hand-built matrix, because the AR path's
     * matrix work exists only because ARCore hands out out-params — there is no reason to repeat it
     * where we choose the eye ourselves.
     *
     * The framing law is "fit the bounding **sphere** vertically": `d = r / sin(fov/2)`. A sphere
     * rather than a box because the shoe rotates — a box that fits at 0° has a corner out of frame
     * at 45°, and a preview that clips the toe mid-turn is worse than one with margin. Scale comes
     * from the same transform the AR path uses ([applyTransform]), so the authored-length
     * correction and the selected size both apply here for free.
     */
    private fun applyPreviewCamera(deltaSeconds: Float) {
        val activeCamera = camera ?: return
        if (asset == null || previewRadiusM <= 0.0) return
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        val now = System.currentTimeMillis()
        if (!interacting && now - lastInteractionMs >= AUTO_ROTATE_DELAY_MS) {
            orbitYawDeg = (orbitYawDeg + AUTO_ROTATE_DEG_PER_SEC * deltaSeconds) % 360f
        }

        val aspect = surfaceWidth.toDouble() / surfaceHeight.toDouble()
        activeCamera.setProjection(
            PREVIEW_FOV_DEGREES,
            aspect,
            NEAR_METERS,
            FAR_METERS,
            Camera.Fov.VERTICAL,
        )

        val yaw = Math.toRadians(orbitYawDeg.toDouble())
        val pitch = Math.toRadians(orbitPitchDeg.toDouble())
        val halfFov = Math.toRadians(PREVIEW_FOV_DEGREES * 0.5)
        val distance = previewRadiusM / sin(halfFov) * PREVIEW_FIT_MARGIN * orbitZoom

        // +Z is the shoe's toe direction (the authoring contract puts the long axis on +Z), so a
        // yaw of zero looks at the shoe from the toe end — the initial yaw is off to one side on
        // purpose, because a three-quarter view is what reads as a shoe rather than a shape.
        val eyeX = previewCentre[0] + distance * cos(pitch) * sin(yaw)
        val eyeY = previewCentre[1] + distance * sin(pitch)
        val eyeZ = previewCentre[2] + distance * cos(pitch) * cos(yaw)
        activeCamera.lookAt(
            eyeX,
            eyeY,
            eyeZ,
            previewCentre[0].toDouble(),
            previewCentre[1].toDouble(),
            previewCentre[2].toDouble(),
            0.0,
            1.0,
            0.0,
        )

        applyPreviewLightRig(yaw)
    }

    /**
     * Keeps the key/fill pair where the customer is looking from, rather than where the world is.
     *
     * The orbit moves the camera, so a fixed rig would sweep the shoe through its own shadow: for
     * half of each revolution the customer would be looking at the side the key light does not
     * reach. Rotating the two directions by the orbit yaw holds the lit/shaded split steady, which
     * is also what a studio shot does — the lighting is a property of the frame, not of the room.
     *
     * Rotation is about Y only: pitch is clamped to a shallow range, and a rig that tilted with it
     * would just trade a dark side for a badly-lit top.
     */
    private fun applyPreviewLightRig(yawRadians: Double) {
        val created = engine ?: return
        val manager = created.lightManager
        val c = cos(yawRadians).toFloat()
        val s = sin(yawRadians).toFloat()

        fun aim(entity: Int, base: FloatArray) {
            // R_y(yaw): (x, y, z) -> (x·cos + z·sin, y, -x·sin + z·cos).
            manager.setDirection(entity, base[0] * c + base[2] * s, base[1], -base[0] * s + base[2] * c)
        }

        aim(keyLight, PREVIEW_KEY_DIR)
        aim(fillLight, PREVIEW_FILL_DIR)
    }

    /**
     * One frame: ARCore first, then Filament.
     *
     * `Session.update()` is here rather than on another thread on purpose (class header): the pose
     * read and the frame drawn from it must be the same [Frame].
     */
    private fun renderFrame(frameTimeNanos: Long) {
        if (tearingDown) return
        val created = engine ?: return
        val activeRenderer = renderer ?: return
        val activeView = view ?: return
        val chain = swapChain ?: return

        // Frame delta, clamped: the frame after a stall would otherwise fling the idle spin.
        val deltaSeconds =
            if (lastFrameNanos == 0L) 0f
            else ((frameTimeNanos - lastFrameNanos) / 1_000_000_000.0)
                .toFloat()
                .coerceIn(0f, MAX_FRAME_DELTA_SECONDS)
        lastFrameNanos = frameTimeNanos

        val activeSession = session
        if (activeSession != null && sessionResumed) {
            try {
                val frame = activeSession.update()
                applyArCamera(frame)
                sampleArLighting(frame)
                autoPlaceIfNeeded(frame)
            } catch (t: Throwable) {
                Log.w(TAG, "session.update threw; keeping the last pose", t)
            }
        } else if (mode == Mode.PREVIEW) {
            // No session is the *normal* case here rather than a degraded one: this branch is what
            // "a preview is a camera" means, and it is the only difference from the AR path.
            applyPreviewCamera(deltaSeconds)
        }

        if (!activeRenderer.beginFrame(chain, frameTimeNanos)) {
            // ⚠️ **The frozen box, as measured on a real P30 Pro (2026-10-01).** The QA readout
            // from that run is the whole diagnosis: `loop=on`, 61 iterations a second, `chain=ok`
            // (non-null, built once), `surface=ok`, `asset=ok`, touches arriving, the orbit state
            // moving — and a picture that never changes. That is this branch: `beginFrame` is
            // refused on every iteration, so the loop spins and reports while the screen keeps
            // showing the last frame that presented. It is also the original report, "it moves for
            // a second then it stops": the first second presents, then the chain stops being able
            // to begin a frame and nothing ever rebuilds it.
            //
            // So a streak of refusals rebuilds the chain — the same repair a `TextureView` size
            // change gets — because a swap chain that exists but cannot present is a state nothing
            // else in this file recovers from (`createSwapChain`'s retry only fires when the build
            // *returns null*). Bounded: a surface that truly cannot present must report, not spin.
            beginFrameFails++
            beginFrameFailStreak++
            // ⚠️ This branch runs *per frame* and the relay fsyncs every line it is given, so only
            // the start of a streak, the repair, and a slow milestone reach the file: a flood here
            // would push out the lifecycle lines that say what led to it.
            if (beginFrameFailStreak == 1) {
                relay(
                    "beginFrame refused the frame — chain=" +
                        (if (swapChain != null) "ok" else "NULL") + ", rebuilds=$swapChainRebuilds",
                )
            }
            if (beginFrameFailStreak >= MAX_BEGIN_FRAME_FAILURES &&
                swapChainRebuilds < MAX_SWAP_CHAIN_REBUILDS
            ) {
                beginFrameFailStreak = 0
                swapChainRebuilds++
                relay(
                    "beginFrame refused $MAX_BEGIN_FRAME_FAILURES frames in a row — rebuilding the " +
                        "swap chain ($swapChainRebuilds/$MAX_SWAP_CHAIN_REBUILDS)",
                )
                runCatching { createSwapChain() }
            } else if (beginFrameFailStreak != 0 &&
                beginFrameFailStreak % REFUSAL_MILESTONE_FRAMES == 0
            ) {
                relay(
                    "still refusing frames: $beginFrameFailStreak in a row, " +
                        "$swapChainRebuilds/$MAX_SWAP_CHAIN_REBUILDS rebuilds used",
                )
            }
            // Sleeping a millisecond beats spinning a core at vsync when this repeats.
            Thread.sleep(1L)
            return
        }
        beginFrameFailStreak = 0
        activeRenderer.render(activeView)
        activeRenderer.endFrame()
        presentedFrames++
        countFrame(frameTimeNanos)
        // Bound so the unused-variable warning cannot bite if the flow above changes.
        created.hashCode()
    }

    /**
     * The AR camera. ARCore's pose is the camera's **world** matrix, and its projection is already
     * OpenGL-style, which is what `setCustomProjection` expects.
     */
    private fun applyArCamera(frame: Frame) {
        val activeCamera = camera ?: return
        if (surfaceWidth > 0 && surfaceHeight > 0) {
            // ARCore offers **only** the out-param form (`getProjectionMatrix(dest, offset, near,
            // far)`) — there is no float[]-returning convenience to call. Requires
            // `setDisplayGeometry` to have run, hence the guard above and the call in surfaceChanged.
            val projection = FloatArray(16)
            runCatching {
                frame.camera.getProjectionMatrix(
                    projection,
                    0,
                    NEAR_METERS.toFloat(),
                    FAR_METERS.toFloat(),
                )
            }.onFailure { t -> Log.w(TAG, "getProjectionMatrix failed", t) }
            activeCamera.setCustomProjection(toDoubleArray(projection), NEAR_METERS, FAR_METERS)
        }
        // `Pose.toMatrix` is out-param only too, and produces the camera→world matrix in
        // column-major order with the translation in 12..14 — exactly what `setModelMatrix` wants.
        val cameraMatrix = FloatArray(16)
        frame.camera.pose.toMatrix(cameraMatrix, 0)
        activeCamera.setModelMatrix(cameraMatrix)
    }

    /**
     * ARCore's ambient light estimate → the key light.
     *
     * `pixelIntensity` is a 0..1-ish luminance proxy mapped onto a range rather than used raw, so
     * an underexposed room does not turn the shoe black. Sampled at ~1 Hz: ARCore's estimate is
     * already a rolling average and re-reading it at 60 Hz would only churn the uniform.
     */
    private fun sampleArLighting(frame: Frame) {
        val now = System.currentTimeMillis()
        if (now - lastLightSampleMs < LIGHT_SAMPLE_MS) return
        lastLightSampleMs = now
        val estimate = frame.lightEstimate
        val intensity = estimate.pixelIntensity.takeIf { it.isFinite() } ?: return
        val clamped = intensity.coerceIn(0f, 3f)
        // Also out-param only: `getColorCorrection(dest, offset)`. White when the estimate has no
        // colour correction to offer, so the light never goes to black on a partial estimate.
        val colour = FloatArray(4) { 1f }
        runCatching { estimate.getColorCorrection(colour, 0) }
            .onFailure { t -> Log.w(TAG, "getColorCorrection failed", t) }
        val created = engine ?: return
        val manager = created.lightManager
        manager.setIntensity(keyLight, (KEY_LUX * (0.35f + 0.65f * clamped)).coerceIn(2_000f, 90_000f))
        manager.setColor(keyLight, colour[0], colour[1], colour[2])
    }

    /**
     * Puts the shoe in front of the viewer the first frame after it loads.
     *
     * Without this the model sits at ARCore's world origin — where the device started, i.e. behind
     * or under the camera — and the screen looks empty until the customer taps. A tap still
     * re-places it ([placeShoe]); this is only the initial answer.
     */
    private fun autoPlaceIfNeeded(frame: Frame) {
        if (placed || asset == null) return
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        val pose = firstFloorHit(frame, surfaceWidth * 0.5f, surfaceHeight * 0.62f)
            ?: rayToFloor(frame, surfaceWidth * 0.5, surfaceHeight * 0.62)
            ?: return
        applyPlacement(pose, yawFromQuaternion(frame.camera.pose.rotationQuaternion))
        Log.i(TAG, "model auto-placed ${pose.tx()}, ${pose.ty()}, ${pose.tz()}")
    }

    private fun countFrame(frameTimeNanos: Long) {
        if (frameWindowStartNanos == 0L) {
            frameWindowStartNanos = frameTimeNanos
            frames = 0
            return
        }
        frames++
        val elapsed = frameTimeNanos - frameWindowStartNanos
        if (elapsed < PERF_WINDOW_NANOS) return
        val seconds = elapsed / 1_000_000_000.0
        val fps = if (seconds > 0) frames / seconds else 0.0
        val frameMs = if (frames > 0) elapsed / 1_000_000.0 / frames else 0.0
        frames = 0
        frameWindowStartNanos = frameTimeNanos
        // The type Dart parses is `perf`; anything else would arrive as an unknown event and only
        // add log noise.
        listener.onEvent("perf", mapOf("avgFps" to fps, "frameMs" to frameMs))
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Model
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * Loads the parked model, replacing any previous one.
     *
     * Three things here are contract rather than preference:
     *  • **The previous asset is destroyed first.** Measured: leaving one alive makes the *next*
     *    `createAsset` fail, so a swap is destroy-then-create or it breaks the swap after it.
     *  • **`flushAndWait()` and a retry.** The driver comes up on its own thread and `Engine.create()`
     *    returns before it is ready; a load attempted too early fails material resolution with
     *    "No material with the specified requirements exists.", which is indistinguishable from a
     *    corrupt file unless you retry.
     *  • **A local file path, never HTTP** (§2.8). Dart downloads and verifies; this side reads bytes.
     *
     * Triangles are reported as `-1` ("native did not say", which the Dart type explicitly allows):
     * the parse-time verified count already exists from V2.3's validator and the
     * `product_models.triangle_count` column, and re-deriving it here would create a second source
     * of truth for a number the seller's upload report already prints.
     */
    private fun applyPendingModel() {
        val created = engine ?: return

        // ⚠️ Before anything is parsed. `AssetLoader.createAsset` is what aborts the process on a
        // feature-level-1 renderer, so this is not a "try it and see" — see
        // [modelLoadingSupported]. The payload is dropped rather than kept: retrying it on this
        // device can only repeat the crash. The one way past this is the double-locked QA override
        // ([allowsUnsupportedRenderer]), which exists to measure level 1 on hardware that is
        // allowed to die.
        // `pendingModel`, not the parsed `spec`: the guard runs before the payload is read out of
        // the park on purpose (it has to precede the parse), so this is the only copy in scope.
        if (!modelLoadingSupported && !allowsUnsupportedRenderer(pendingModel)) {
            pendingModel = null
            // The line this channel exists for: on a phone whose renderer came up below
            // `FEATURE_LEVEL_2`, this records *why* there is no shoe — a refusal, not a failure.
            relay(
                "REFUSED the load: renderer ${created.activeFeatureLevel} is below " +
                    "${Engine.FeatureLevel.FEATURE_LEVEL_2} — nothing was parsed",
            )
            listener.onError(
                REASON_RENDERER_UNSUPPORTED,
                "glTF loading needs ${Engine.FeatureLevel.FEATURE_LEVEL_2}; this renderer is " +
                    "${created.activeFeatureLevel} ($rendererDiagnostic)",
            )
            return
        }

        val loader = assetLoader ?: return
        val spec = pendingModel ?: return
        pendingModel = null

        val file = File(spec.path)
        if (!file.isFile) {
            listener.onError("model_parse_failed", "local model missing at ${spec.path}")
            return
        }
        // ⚠️ **The load window is where the P30 Pro dies, and these lines are how a driver abort gets
        // a name.** Measured on 1.0.40 (2026-10-01): its log reaches the renderer facts and stops —
        // with neither the swap-chain line nor the loaded line after it — so the process dies inside
        // this function, and *which* native call did it cannot be caught: an abort in a driver is not
        // an exception. Each call below is therefore announced before it runs and confirmed after it
        // returns, and the last line with no successor is the call to look at. The Java-level
        // failures are wrapped where they were not, because an uncaught throwable on the render
        // thread kills the process exactly like an abort does — a wrapped one leaves a line instead.
        relay(
            "load: model ${spec.modelId} — ${file.length()} bytes, renderer " +
                "${created.activeFeatureLevel}",
        )
        val startedAt = System.currentTimeMillis()
        asset?.let { previous -> runCatching { loader.destroyAsset(previous) } }
        asset = null

        var loaded: FilamentAsset? = null
        var lastFailure: String? = null
        // ⚠️ **A `for` with a `break`, not `repeat` with `return@repeat` — and that distinction is a
        // crash, measured on hardware.** `return@repeat` returns from the *lambda*, which is a
        // `continue`: a first attempt that already succeeded still ran the rest of the budget, and
        // every extra `createAsset` built a whole second asset whose material instances were never
        // destroyed (nothing holds it, and `asset` only ever keeps the last one). Teardown's
        // `destroyMaterials()` then aborts the process — uncatchably, in native code:
        //
        //     utils::PreconditionPanic: reason: destroying material "base_lit_opaque" but 4
        //     instances still alive.                     (Redmi 24094RAD4G, 2026-10-01)
        //
        // That was the crash on **leaving** the viewer, on a phone whose render was fine. The fix is
        // to stop loading once something loaded.
        for (attempt in 0 until LOAD_ATTEMPTS) {
            relay("load attempt ${attempt + 1}/$LOAD_ATTEMPTS: flushAndWait")
            runCatching { created.flushAndWait() }.onFailure { t ->
                relay("load attempt ${attempt + 1}: flushAndWait threw — ${t.message}")
            }
            val bytes = runCatching { file.readBytes() }.getOrElse { t ->
                relay("load attempt ${attempt + 1}: reading the file failed — ${t.message}")
                listener.onError("model_parse_failed", "cannot read ${spec.path}: ${t.message}")
                return
            }
            relay("load attempt ${attempt + 1}: ${bytes.size} bytes — createAsset")
            loaded = runCatching { loader.createAsset(directBuffer(bytes)) }.getOrElse { t ->
                // An undecodable required extension surfaces here. Finding 3's PreconditionPanic
                // (material/mesh mismatch) is a process abort and is *not* catchable — which is
                // why the authoring checklist is a rule and not advice.
                lastFailure = t.message
                null
            }
            relay(
                "load attempt ${attempt + 1}: createAsset " +
                    (if (loaded != null) "returned an asset" else "returned null — $lastFailure"),
            )
            if (loaded != null) break
            lastFailure = lastFailure ?: "loader returned null (unsupported required extension?)"
            Thread.sleep(200L * (attempt + 1))
        }

        val createdAsset = loaded
        if (createdAsset == null) {
            Log.w(TAG, "createAsset failed after $LOAD_ATTEMPTS attempts: $lastFailure")
            relay("load FAILED after $LOAD_ATTEMPTS attempts: $lastFailure")
            // The facts travel with the failure too: on a QA build running the level-1 override,
            // this line is the measurement — the load that used to be refused instead failed
            // gracefully here rather than aborting.
            listener.onError("model_parse_failed", "$lastFailure · $rendererDiagnostic")
            return
        }
        asset = createdAsset
        // The loader is destroyed after it has done its one job, which is the sequence
        // `AssetLoader`'s own javadoc shows (`loadResources` … `resourceLoader.destroy()`): the
        // object was previously created inline and dropped, leaving its native staging buffers
        // behind on every open of the box.
        relay("load: asset built — ResourceLoader.loadResources")
        val resources = ResourceLoader(created)
        runCatching { resources.loadResources(createdAsset) }
            .onFailure { t ->
                Log.w(TAG, "loadResources failed", t)
                relay("load: loadResources threw — ${t.message}")
            }
        relay("load: resources loaded — freeing the staging loader")
        runCatching { resources.destroy() }
            .onFailure { t -> Log.w(TAG, "ResourceLoader.destroy failed", t) }
        relay("load: staging loader freed — adding the entities")
        runCatching { scene?.addEntities(createdAsset.renderableEntities) }
            .onFailure { t -> relay("load: addEntities threw — ${t.message}") }
        modelRoot = createdAsset.root
        runCatching { created.transformManager.create(modelRoot) }
        relay("load: entities added — applying the transform")

        pendingAuthoredLengthMm = spec.authoredLengthMm
        yawOffsetDeg = spec.yawOffsetDeg ?: 0.0
        sizeScale = 1.0f
        placed = false
        Matrix.setIdentityM(placement, 0)
        applyTransform()

        // ⚠️ **The one number that decides whether the preview can move at all.**
        // `applyPreviewCamera` returns before it writes a single camera transform — and before the
        // idle spin advances — while this radius is zero, so a screen that presents frames but
        // never turns (the owner's "I cannot touch it") is this value. Zero means `applyTransform`
        // found no bounding box to frame: the read that produces it sits between the two lines
        // above, so a log that ends on this one with a zero radius names a load that framed
        // nothing rather than a camera that failed.
        relay("load: preview fit — radius=${(previewRadiusM * 1000.0).roundToInt()}mm")

        val loadMs = (System.currentTimeMillis() - startedAt).toInt()
        val halfExtent = createdAsset.boundingBox.halfExtent
        Log.i(
            TAG,
            "model ${spec.modelId} loaded in ${loadMs}ms: renderables=" +
                "${createdAsset.renderableEntities.size}, bbox(m)=${halfExtent.joinToString()}, " +
                "authoredLengthMm=${spec.authoredLengthMm}",
        )
        relay(
            "model ${spec.modelId} loaded in ${loadMs}ms: " +
                "renderables=${createdAsset.renderableEntities.size}",
        )
        listener.onEvent("modelLoaded", mapOf("loadMs" to loadMs, "triangles" to -1))
    }

    /**
     * Writes the transform: placement (rotation + world position) × uniform scale.
     *
     * The scale also corrects against the authored length when one is known, so a model authored at
     * 278 mm renders as 278 mm rather than "some size in metres" — the `authored_length_mm`
     * column's entire purpose (§2.5.1). The correction is a *ratio* against the asset's own
     * bounding box, not an assumption about units: a glTF is metres by spec, but V0's block-out was
     * authored in millimetres, and both must render at the right size.
     */
    private fun applyTransform() {
        val created = engine ?: return
        if (modelRoot == 0) return

        val authoredExtent = asset?.boundingBox?.halfExtent?.get(2)?.times(2f) ?: 0f
        val declaredMm = pendingAuthoredLengthMm
        var authoredCorrection = 1.0f
        if (declaredMm != null && declaredMm > 0 && authoredExtent > 1e-6f) {
            authoredCorrection = (declaredMm / 1000.0).toFloat() / authoredExtent
        }

        val scale = sizeScale * authoredCorrection
        val matrix = FloatArray(16)
        Matrix.setIdentityM(matrix, 0)
        Matrix.translateM(matrix, 0, placement[12], placement[13], placement[14])
        if (placed) Matrix.rotateM(matrix, 0, placedYawDeg + yawOffsetDeg.toFloat(), 0f, 1f, 0f)
        Matrix.scaleM(matrix, 0, scale, scale, scale)
        runCatching { created.transformManager.setTransform(modelRoot, matrix) }
            .onFailure { t -> Log.w(TAG, "setTransform failed", t) }
        // ⚠️ **The load's last window, split at its midpoint (measured, 2026-10-02).** Twice on the
        // P30 Pro the log ended one line *above* this one — after `entities added — applying the
        // transform` — with half a second of silence before the activity finished, so the render
        // thread was inside `setTransform` or inside the bounding-box read below it. Which of the
        // two it was is this line: a log that never reaches it died in `setTransform`, and one that
        // ends on it died in the box. (`applyTransform` is shared with the AR placement path; a
        // placement pays one line for the same call, which has the same stall surface.)
        relay("load: transform written — reading the bounding box")

        // What the preview camera frames, derived from the transform just written rather than from
        // the asset's raw box: the mesh is authored in metres, but a V0-era block-out is authored in
        // millimetres and the authored-length correction above is what makes either one real. The
        // camera must orbit what is actually on screen.
        val box = asset?.boundingBox
        if (box != null) {
            val centre = box.center
            val half = box.halfExtent
            previewCentre[0] = placement[12] + centre[0] * scale
            previewCentre[1] = placement[13] + centre[1] * scale
            previewCentre[2] = placement[14] + centre[2] * scale
            // The sphere that CONTAINS the box: `hypot` of the half-extents, not the largest of
            // them. The largest half-extent sits inside the box's own corners (67.5 mm here
            // against a true 101 mm), so fitting it leaves the toe and the far corner outside the
            // frustum as soon as the customer turns the shoe — which is the one thing the margin
            // exists to prevent. With the containing radius, no point can leave the frame at any
            // orientation, at any margin above 1.
            previewRadiusM = sqrt(
                half[0].toDouble() * half[0] +
                    half[1].toDouble() * half[1] +
                    half[2].toDouble() * half[2],
            ) * scale
            Log.i(TAG, "preview fit: radius ${fmt(previewRadiusM)} m, centre ${fmt(previewCentre[0])}, " +
                "${fmt(previewCentre[1])}, ${fmt(previewCentre[2])}")
        }
    }

    /** Three decimals for the log, since the fit input is millimetres and this is the line read
     * during a device session. */
    private fun fmt(value: Float): String = String.format(java.util.Locale.US, "%.3f", value)

    private fun fmt(value: Double): String = String.format(java.util.Locale.US, "%.3f", value)

    private fun applyPlacement(pose: Pose, yawDeg: Float) {
        Matrix.setIdentityM(placement, 0)
        Matrix.translateM(placement, 0, pose.tx(), pose.ty(), pose.tz())
        placedYawDeg = yawDeg
        placed = true
        applyTransform()
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Placement math
    // ════════════════════════════════════════════════════════════════════════════════════════

    /** The first ARCore hit on a tracked, horizontal, upward-facing plane, or null. */
    private fun firstFloorHit(frame: Frame, px: Float, py: Float): Pose? {
        val hits = runCatching { frame.hitTest(px, py) }.getOrNull() ?: return null
        for (hit in hits) {
            val plane = hit.trackable as? Plane ?: continue
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            if (plane.trackingState != TrackingState.TRACKING) continue
            return hit.hitPose
        }
        return null
    }

    /**
     * The fallback floor intersection: the tap ray through ARCore's own projection, met with the
     * estimated floor height.
     *
     * The floor height is the lowest horizontal plane seen so far, or 0 — ARCore's session origin
     * sits at the device's start position, so 0 is "roughly floor level". Good enough to place a
     * shoe for the second before a plane is detected, and never reached once one is.
     */
    private fun rayToFloor(frame: Frame, px: Double, py: Double): Pose? {
        val width = surfaceWidth.toDouble()
        val height = surfaceHeight.toDouble()
        if (width <= 0 || height <= 0) return null
        val ndcX = (px / width) * 2.0 - 1.0
        val ndcY = 1.0 - (py / height) * 2.0

        val projection = FloatArray(16)
        try {
            frame.camera.getProjectionMatrix(
                projection,
                0,
                NEAR_METERS.toFloat(),
                FAR_METERS.toFloat(),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "rayToFloor: no projection matrix yet", t)
            return null
        }
        // For a standard GL perspective matrix the first and sixth entries are 1/tanHalfFov.
        val p00 = projection[0].toDouble()
        val p11 = projection[5].toDouble()
        if (p00 == 0.0 || p11 == 0.0) return null

        // Camera space: x right, y up, looking down -Z — the same convention as Filament and GL.
        val direction = rotateByQuaternion(
            frame.camera.pose.rotationQuaternion,
            doubleArrayOf(ndcX / p00, ndcY / p11, -1.0),
        )
        if (direction[1] >= -1e-4) return null // at or above the horizon: no floor hit

        val pose = frame.camera.pose
        val floorY = estimatedFloorY(frame)
        val distance = (floorY - pose.ty()) / direction[1]
        if (distance <= 0.0 || distance > MAX_PLACEMENT_METERS) return null
        return Pose.makeTranslation(
            (pose.tx() + direction[0] * distance).toFloat(),
            (pose.ty() + direction[1] * distance).toFloat(),
            (pose.tz() + direction[2] * distance).toFloat(),
        )
    }

    private fun estimatedFloorY(frame: Frame): Double {
        var lowest = 0.0
        var found = false
        val planes = runCatching { frame.getUpdatedTrackables(Plane::class.java) }.getOrNull()
            ?: return lowest
        for (plane in planes) {
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            val y = plane.centerPose.ty().toDouble()
            if (!found || y < lowest) {
                lowest = y
                found = true
            }
        }
        return lowest
    }

    /**
     * Yaw that points the model's **+Z** (the toe, per §2.5.1 and V0's fixture) along the camera's
     * forward direction.
     *
     * Yaw is taken from the **camera**, not from the hit pose: a plane's rotation about the vertical
     * axis is arbitrary (ARCore only guarantees it is gravity-aligned), so a shoe inheriting it
     * would face a random direction. Only yaw is applied at all — a shoe tipped by the plane's full
     * rotation reads as broken, because the sole is what must stay flat.
     */
    private fun yawFromQuaternion(q: FloatArray): Float {
        val x = q[0].toDouble()
        val y = q[1].toDouble()
        val z = q[2].toDouble()
        val w = q[3].toDouble()
        // (0,0,1) rotated by q, then the heading of that vector.
        val forwardX = 2.0 * (y * w + z * x)
        val forwardZ = 1.0 - 2.0 * (x * x + y * y)
        return Math.toDegrees(atan2(forwardX, forwardZ)).toFloat()
    }

    private fun rotateByQuaternion(q: FloatArray, v: DoubleArray): DoubleArray {
        val qx = q[0].toDouble(); val qy = q[1].toDouble()
        val qz = q[2].toDouble(); val qw = q[3].toDouble()
        // v' = v + 2w(q × v) + 2(q × (q × v))
        val tx = 2.0 * (qy * v[2] - qz * v[1])
        val ty = 2.0 * (qz * v[0] - qx * v[2])
        val tz = 2.0 * (qx * v[1] - qy * v[0])
        val rx = v[0] + qw * tx + (qy * tz - qz * ty)
        val ry = v[1] + qw * ty + (qz * tx - qx * tz)
        val rz = v[2] + qw * tz + (qx * ty - qy * tx)
        val length = sqrt(rx * rx + ry * ry + rz * rz)
        return if (length < 1e-9) {
            doubleArrayOf(0.0, -1.0, 0.0)
        } else {
            doubleArrayOf(rx / length, ry / length, rz / length)
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Session failure taxonomy
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * Maps an ARCore exception onto the vocabulary the Dart gate already maps
     * (`tryOnDegradeReasonForArFailure` in `lib/providers/try_on/try_on_mode.dart`).
     *
     * The set is closed: `unsupported_device`, `unsupported`, `needs_install`, `user_opted_out`,
     * `timeout`, `error`. Anything unrecognised is `error` — never a new string, because a code Dart
     * has not heard of degrades to the same place anyway and only makes the log harder to read.
     * Install-related codes are normally answered by the plugin first; they are repeated here so the
     * mapping is complete in one file.
     */
    private fun sessionFailure(t: Throwable): StartOutcome {
        val message = t.message ?: t::class.java.simpleName
        // `is` checks, not class-name matching: a release build that turns on R8 renames classes,
        // and a taxonomy that silently collapses to `error` under minification is worse than no
        // taxonomy at all. Same shape as the spike's `reasonFor` and the shipped scan's.
        return when (t) {
            is UnavailableDeviceNotCompatibleException ->
                StartOutcome(false, "unsupported_device", message)
            is UnavailableApkTooOldException,
            is UnavailableSdkTooOldException,
            -> StartOutcome(false, "unsupported", message)
            is UnavailableArcoreNotInstalledException ->
                StartOutcome(false, "needs_install", message)
            is UnavailableUserDeclinedInstallationException ->
                StartOutcome(false, "user_opted_out", message)
            is CameraNotAvailableException ->
                StartOutcome(false, "error", "camera_unavailable: $message")
            is SecurityException ->
                StartOutcome(false, "error", "camera_permission_denied: $message")
            else -> StartOutcome(false, "error", message)
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Teardown
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * Full teardown on the render thread, in destroy order, idempotent because both
     * `surfaceDestroyed` and the plugin's `dispose` can arrive, in either order.
     *
     * ⚠️ **The order and the flush are contract, not style.** Filament 1.72.1's own Android sample
     * destroys the swap chain and then calls `Engine.flushAndWait()` *while the surface is still
     * valid*, because "Android might destroy the Surface too early" otherwise
     * (`UiHelper.RendererCallback.onDetachedFromSurface`), and it destroys the engine **last**,
     * after everything that references it (`Engine.destroy()`: "should be called last and after
     * all other resources have been destroyed"). The frame callback is removed before anything is
     * destroyed, so no queued vsync can touch a dead engine
     * (`Choreographer.removeFrameCallback`, invoked from the looper it belongs to), and the gltfio
     * objects go in their documented order — asset, then loader, then the provider's cached
     * materials, then the provider (`MaterialProvider.destroyMaterials` / `destroy`;
     * `AssetLoader.destroy` explicitly does *not* free the material cache). Entity ids are freed
     * only after their components (`Engine.destroyEntity` destroys components only;
     * `EntityManager.destroy` frees the id).
     *
     * Every phase is written to the file channel as it completes, so a crash inside teardown leaves
     * the last completed step readable at the next launch — the only post-mortem this phone can
     * produce.
     */
    private fun teardown() {
        if (tornDown) {
            relay("teardown SKIPPED: already torn down")
            return
        }
        tornDown = true
        tearingDown = true
        frameLoopRunning = false
        // The callback belongs to this thread's Choreographer. Removing it here (never from
        // another thread) is what guarantees the next vsync cannot re-enter a destroyed engine.
        choreographer.removeFrameCallback(frameCallback)
        engineDestroys++
        // The touch totals ride the one teardown line every completed leave writes: a session whose
        // `presented` is in the hundreds with `touches=0/0/0` is a preview whose gestures never
        // arrived, which is a different fault from one whose camera never framed the shoe.
        relay(
            "teardown BEGIN (engines ${engineCreates}/${engineDestroys}, presented=$presentedFrames, " +
                "touches=$touchDowns/$touchMoves/$touchUps)",
        )
        relay("teardown: loop stopped, frame callback removed")
        // ⚠️ **The line a re-opened preview's teardown never came back from (measured, 2026-10-02).**
        // Both times the P30 Pro opened the preview, left it, opened it again and left again, the
        // log ended at `loop stopped, frame callback removed` and the process lived about a second
        // longer — long enough for the activity to write `onPause isFinishing=true` — so the stall
        // is in the call these two lines bracket. The *first* teardown in the same process destroys
        // the same asset in about a millisecond, and `destroyAsset` cannot be wrapped in a timeout,
        // so this line is what separates "died before the destroy" from "died inside it".
        relay("teardown: destroying the asset")
        asset?.let { loaded -> assetLoader?.let { runCatching { it.destroyAsset(loaded) } } }
        asset = null
        relay("teardown: asset destroyed")
        pendingModel = null
        modelRoot = 0
        runCatching { session?.close() }
        session = null
        sessionResumed = false
        destroySwapChain()
        engine?.let { created ->
            val flushed = runCatching { created.flushAndWait(TEARDOWN_FLUSH_TIMEOUT_NANOS) }
                .getOrDefault(false)
            relay("teardown: swap chain destroyed, flushAndWait=${if (flushed) "ok" else "timeout"}")
        }
        view?.let { engine?.destroyView(it) }
        scene?.let { engine?.destroyScene(it) }
        renderer?.let { engine?.destroyRenderer(it) }
        if (cameraEntity != 0) {
            engine?.destroyCameraComponent(cameraEntity)
            runCatching { EntityManager.get().destroy(cameraEntity) }
        }
        if (keyLight != 0) {
            engine?.destroyEntity(keyLight)
            runCatching { EntityManager.get().destroy(keyLight) }
        }
        if (fillLight != 0) {
            engine?.destroyEntity(fillLight)
            runCatching { EntityManager.get().destroy(fillLight) }
        }
        assetLoader?.destroy()
        // `destroy()` does not free the materials it created (its own javadoc), and the asset that
        // used them is already gone, so the cache is drained explicitly first.
        materialProvider?.destroyMaterials()
        materialProvider?.destroy()
        relay("teardown: view/scene/renderer/entities/loader/materials destroyed")
        engine?.destroy()
        view = null
        scene = null
        renderer = null
        camera = null
        assetLoader = null
        materialProvider = null
        engine = null
        cameraEntity = 0
        keyLight = 0
        fillLight = 0
        relay("teardown END (engines ${engineCreates}/${engineDestroys})")
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Small helpers
    // ════════════════════════════════════════════════════════════════════════════════════════

    private fun postToMain(block: () -> Unit) {
        mainHandler.post(block)
    }

    private fun directBuffer(bytes: ByteArray): ByteBuffer =
        ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply { put(bytes); rewind() }

    private fun toDoubleArray(values: FloatArray): DoubleArray =
        DoubleArray(values.size) { values[it].toDouble() }

    private companion object {
        const val TAG = "ArTryOnView"

        /**
         * The reason Dart degrades the whole 3D surface on, spelled here and in
         * `shoe_preview_channel.dart` and pinned by `product_detail_shoe_preview_contract_test`.
         */
        const val REASON_RENDERER_UNSUPPORTED = "renderer_feature_level_unsupported"

        /** The flush-and-retry budget from `GltfioDecodeTest`, for the same measured reason. */
        const val LOAD_ATTEMPTS = 3

        const val NEAR_METERS = 0.1
        const val FAR_METERS = 30.0
        const val FOV_DEGREES = 60.0

        /** §2.6's grading step, mirrored from `fit_engine.dart`'s `sizeStepMm`. */
        const val SIZE_STEP_MM = 6.67
        const val MAX_SIZE_STEPS = 3.0

        const val KEY_LUX = 45_000f
        const val FILL_LUX = 9_000f

        const val PERF_WINDOW_NANOS = 5_000_000_000L
        const val LIGHT_SAMPLE_MS = 1_000L
        const val MAX_PLACEMENT_METERS = 12.0

        /** A stall must not turn into a jump: the idle spin takes at most this much per frame. */
        const val MAX_FRAME_DELTA_SECONDS = 0.1f

        // ── QA self-report ──────────────────────────────────────────────────────────────────

        /** How often the heartbeat speaks, and the file its last line is parked in. */
        const val STATUS_PERIOD_NANOS = 1_000_000_000L
        const val STATUS_FILE_NAME = "qa_preview_status.txt"

        /** The swap-chain retry's budget: enough to survive a settle, not enough to spin. */
        const val SWAP_CHAIN_RETRY_MS = 120L

        /**
         * How long the UI thread may wait for a surface's swap chain to be destroyed and the
         * engine flushed before the framework is allowed to release the surface.
         *
         * ⚠️ Must be **larger** than [SURFACE_FLUSH_TIMEOUT_NANOS], or the wait would return
         * before the flush it exists for. Both are bounded: Filament's own sample waits forever
         * here, which is allowed in a sample and is an ANR on a customer's phone.
         */
        const val SURFACE_TEARDOWN_WAIT_MS = 1_000L

        /** The bound on that flush, handed to `Engine.flushAndWait(timeout)` in nanoseconds. */
        const val SURFACE_FLUSH_TIMEOUT_NANOS = 750_000_000L

        /** The bound on the final flush in [teardown], before the engine itself is destroyed. */
        const val TEARDOWN_FLUSH_TIMEOUT_NANOS = 1_000_000_000L

        /**
         * How often a refusal streak that has nothing left to rebuild logs one line.
         *
         * The failure branch sleeps 1 ms, so 1,200 frames is about a second and a half — often
         * enough to date a stall, rare enough that the shared diag file stays readable.
         */
        const val REFUSAL_MILESTONE_FRAMES = 1200
        const val MAX_SWAP_CHAIN_RETRIES = 3

        /**
         * How many refused `beginFrame` calls in a row mean the chain is alive but dead, and how
         * many times that may be repaired. Measured on a real phone: this is the state whose
         * picture freezes while the loop keeps running at ~60 a second.
         */
        const val MAX_BEGIN_FRAME_FAILURES = 3
        const val MAX_SWAP_CHAIN_REBUILDS = 5

        /** How long a new engine waits for the previous view's teardown (see its call site). */
        const val TEARDOWN_WAIT_SECONDS = 2L

        /**
         * The previous view's teardown, while it is still running — the second-open crash.
         *
         * Process-wide rather than per-view because the race it closes is *between* two views:
         * `Engine.create()` on the new one against `engine.destroy()` on the old one. Filament's
         * driver, its EGL context and `Filament.init()`'s globals are process-wide too, so the
         * ordering has to be as well.
         */
        @Volatile var pendingTeardown: CountDownLatch? = null

        // ── Preview framing and orbit ────────────────────────────────────────────────────────

        /** A touch narrower than the AR path's 60°, so an inline box is not fisheye. */
        const val PREVIEW_FOV_DEGREES = 45.0

        /**
         * Air around the bounding sphere. Any value above 1 leaves a margin by construction (the
         * sphere does not change size as the model turns), so this is a composition choice, not a
         * safety one: the shoe fills about `1 / margin` of the box height at worst, and ~65-70%
         * across the angles the orbit actually reaches. It came down from 1.15 with the radius fix
         * above, which on its own had shrunk the shoe by a third.
         */
        const val PREVIEW_FIT_MARGIN = 1.05

        /**
         * A three-quarter view of the toe. +Z is the toe by the authoring contract, so yaw 0 looks
         * down the toe and 180° would be the heel; 60° opens on the front outer side, which is how
         * a product photo is framed. (The first value here was 145° — the heel, from behind.)
         */
        const val INITIAL_YAW_DEG = 60f

        /** Slightly above the shoe's own axis, the usual looking-down product angle. */
        const val INITIAL_PITCH_DEG = 18f

        /**
         * Key and fill directions, in the same space as the yaw=0 camera (looking down -Z, at the
         * shoe from +Z). The preview rotates the pair with the orbit so the lit side always faces
         * the customer — see [applyPreviewLightRig].
         */
        private val PREVIEW_KEY_DIR = floatArrayOf(-0.35f, -1.0f, -0.45f)
        private val PREVIEW_FILL_DIR = floatArrayOf(0.5f, -0.35f, 0.55f)

        /** Looking from below the ground plane is not a view of a shoe; straight down is not one either. */
        const val MIN_PITCH_DEG = -10f
        const val MAX_PITCH_DEG = 75f

        /** 0.75° per logical pixel: a 400 px drag is a full turn and a bit, which feels about right. */
        const val DRAG_DEG_PER_PX = 0.75f

        const val MIN_ZOOM = 0.6f
        const val MAX_ZOOM = 2.5f

        /**
         * Idle spin, after the customer has stopped touching the box. A full turn in 18 s: at 14°/s
         * the shoe crossed its own silhouette at about 6 px/s in a 240 px box, which reads as
         * stalled rather than as a turntable.
         */
        const val AUTO_ROTATE_DELAY_MS = 2_500L
        const val AUTO_ROTATE_DEG_PER_SEC = 20f
    }
}
