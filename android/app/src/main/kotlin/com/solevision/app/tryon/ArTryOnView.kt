package com.solevision.app.tryon

import android.app.ActivityManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.graphics.SurfaceTexture
import android.media.Image
import android.opengl.Matrix
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.ViewConfiguration
import android.widget.FrameLayout
import com.google.android.filament.Camera
import com.google.android.filament.ColorGrading
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.LightManager
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.ToneMapper
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.ar.core.CameraConfig
import com.google.ar.core.CameraConfigFilter
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
 * four things SceneView used to supply: the engine lifecycle, the glTF material path, the
 * camera-feed draw, and the plane visuals still to come
 * (`docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md` §5.5).
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
 *    and correctly placed *before* the feed is composited — which is the point of that ordering:
 *    when the room appears behind it, the geometry does not move.
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
 *  • **The camera feed is composited — F20's first half, and the reason `feed=` exists in the QA
 *    heartbeat.** [ArCameraFeed] creates the external OES texture ARCore writes frames into, inside
 *    an EGL context shared with the engine, and draws it as a full-screen quad with a vendored
 *    `camera_stream_flat.filamat` (SceneView 4.34.0, Apache-2.0, 42,544 B). The material is
 *    version-locked to the Filament that compiled it, so [ArCameraFeed.attach] checks its
 *    parameters and attributes against the live engine and reports a mismatch instead of drawing a
 *    black backdrop; a missing asset reports the same way.
 *
 * ## What is deliberately not built, and why
 *
 *  1. **Planes are not visualized** — the camera feed's sibling gap. SceneView's
 *     `plane_renderer.filamat` (40,976 B) has no counterpart vendored yet, and the IBL (~2.1 MB)
 *     has none either, so the shoe has no reflections. Planes are still *used*: hit-testing needs
 *     plane detection, so placement on a real floor works while the floor stays invisible.
 *  2. **Planes are not visualized** — same missing asset (SceneView's `plane_renderer.filamat`,
 *     40,976 B). They are still *used*: hit-testing needs plane detection, so placement on a real
 *     floor works while the floor stays invisible.
 *  2. **Hand-rolling geometry against the ubershader is not attempted.** Finding 3 of
 *     `GltfioDecodeTest` is a measured SIGABRT: a material/mesh mismatch (wrong parameters, missing
 *     vertex attributes) trips `utils::PreconditionPanic` inside `createAsset`. Building a plane
 *     mesh against an ubershader whose exact attribute set is unverified is exactly that crash, on
 *     a screen a customer is holding. The feed took the vendoring route — an Apache-2.0 `.filamat`
 *     with the version check [ArCameraFeed.attach] performs — and the plane material can take that
 *     route or `matc` in CI.
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
            // ARCore owns the camera and the feed is a Filament draw call on this surface, so
            // opaque is correct: nothing composited behind the view is meant to show through.
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

    /**
     * **V4.9 night-feed grading — the exposure/tone-mapping the AR view grades every frame with.**
     *
     * The camera feed is an unlit quad drawn into the same view as the shoe, so it rides
     * Filament's colour-grading post-process. With no grading set, the view's default
     * (filmic/ACES-style) tone mapping crushes the already dark low-light feed — the device's
     * HAL logs show ARCore's auto-exposure pinned at its ceiling in a dark room
     * (`u4Eposuretime:33332` = the 30 fps cap, `u4AfeGain`/`u4ISO` at max), so the extra
     * compression made a starved feed look worse than the sensor delivered. `Linear`
     * tone mapping passes the feed through as the sensor saw it, and [FEED_EXPOSURE_EV]
     * adds software gain on top. Built in [createEngineIfNeeded], destroyed in [teardown].
     */
    private var colorGrading: ColorGrading? = null

    /** V4.9: the torch wish. Written from any thread ([setTorch]), read on the render
     * thread by [startSession]'s config and the live reconfigure. Volatile because the
     * writer is the channel thread and the reader is the render thread. */
    @Volatile private var torchEnabled = false
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
     * **The camera feed — F20's first half, AR mode only.** It owns the OES texture ARCore writes
     * into, the vendored `camera_stream_flat.filamat` that samples it, and the full-screen quad that
     * draws the room behind the shoe ([ArCameraFeed]). Created by [createEngineIfNeeded], because
     * the engine has to be built against its EGL context, and destroyed by [teardown] before the
     * engine it was built against. Null in [Mode.PREVIEW], which has no camera to show.
     */
    private var cameraFeed: ArCameraFeed? = null

    /**
     * **V4.4's occlusion draw** — mask-shaped geometry with the camera feed's own material, painted
     * over the shoe so the foot reads as inside it ([FootMaskOverlay]). Built in
     * [createEngineIfNeeded] against the feed's texture, driven per frame by [applyFootMask], and
     * destroyed by [teardown] before the feed whose texture it samples.
     */
    private var footMaskOverlay: FootMaskOverlay? = null

    /** The latest mask Dart sent, awaiting the next AR frame ([setFootMask]). */
    private var pendingFootMask: FootMaskFrame? = null

    /**
     * One accepted frame's occlusion mask: the 32×32 bytes `lib/utils/foot_mask.dart` built, plus
     * the sample's quality. Held as one object so a posted mask can never be half-read.
     */
    private class FootMaskFrame(val bytes: ByteArray, val confidence: Double)

    /**
     * Two pixels of scratch for [uprightImageUvToPixels], reused by the pose hit tests and the
     * mask's corners alike: a full mask is up to 16 K corners at ≥5 Hz, and this runs on the
     * render thread, where per-corner garbage is the one cost that shows up as jank.
     */
    private val uvScratch = FloatArray(2)

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

    /**
     * **V4.8: whether the session is paused because its surface went away, and only that.**
     *
     * Backgrounding an app destroys the `SurfaceView`'s surface; `surfaceDestroyed` pauses the
     * ARCore session — and until this flag existed nothing resumed it: the customer returned to a
     * screen whose session stayed paused for the rest of the visit, because Dart's [startSession]
     * is one-shot per screen open. `surfaceCreated` may undo the pause only when the surface is
     * what applied it: an explicit [pauseSession] (the QA `stopSession`) and a torn-down session
     * must not be revived by a surface event.
     *
     * Render-thread state, like [sessionResumed] beside it.
     */
    private var pausedForSurfaceDetach = false
    private var surface: Surface? = null
    private var surfaceWidth = 0
    private var surfaceHeight = 0

    /**
     * **The stage the shoe stands on: `Renderer.ClearOptions.clearColor`, as RGBA.**
     *
     * ⚠️ It follows the *customer's* appearance, not the renderer's, and the mode decides which of
     * the three faces of this feature it is: the **preview** is a page surface, so Dart sends a
     * light neutral in light mode and the `#0E0F12` this view has always cleared to in dark mode
     * (`AppConstants.stage` → `setPreviewBackground` → [setBackground]); **AR** is a camera feed and
     * stays dark in both modes, which is why nothing on the AR channel ever sends one.
     *
     * `null` means "nothing sent yet": [DEFAULT_CLEAR_COLOR] stays in place, which is the same tone
     * the Dart-side idle face paints, so the box does not flash between tones as the engine starts
     * (or, on a theme flip, between the two the customer chose).
     *
     * Render-thread state like everything else around it — [setBackground] posts.
     */
    private var stageColor: DoubleArray? = null

    private var asset: FilamentAsset? = null
    private var modelRoot = 0

    /**
     * Whether the last model transform write was refused because the root entity has no transform
     * component ([modelRootTransformInstance] answers `0`). Read by [applyTransform] to decide
     * whether its `transform written` line is true — the line is the load's probe for where a
     * native stall sits, and it must not be printed for a write that never happened.
     */
    private var transformWriteRefused = false

    /**
     * Whether a refusal has already been logged for the current asset. The per-frame path attempts
     * the write at display rate, so the log is an edge rather than a rate: at 60 Hz an unthrottled
     * line would push the rest of the session out of logcat's ring. Reset by every load, which is
     * also when the component state resets.
     */
    private var transformRefusalNoted = false

    /**
     * **Whether a failing `session.update()` has already been relayed (V4.9, 2026-10-05).** The AR
     * loop calls it at display rate, and the failure this was added for — ARCore refusing every
     * frame with `MissingGlContextException` because no GL context was current on this thread —
     * wrote a stack trace per frame into logcat and **nothing** into `nav_diag`, which is the file
     * the locked-down phone can actually export. One line per session is what a reader needs;
     * reset by every [startSession].
     */
    private var arUpdateFailureNoted = false
    private var pendingModel: ModelSpec? = null
    private var pendingAuthoredLengthMm: Double? = null
    private var yawOffsetDeg = 0.0

    /** Uniform scale from `setSize`; 1.0 until a size is selected. */
    private var sizeScale = 1.0f

    /**
     * **V4.3's baseline:** the internal last (mm) [sizeScale] grades to — `lastLengthMm + (size −
     * refSize) × 6.67`, the graded number itself rather than the ratio it becomes, because the
     * frame-scale correction compares the measured foot against it and re-deriving the grade here
     * would be a second place the same arithmetic lives. Null until `setSize` (or after a model
     * swap), which is exactly when the chart's answer is unknown and the correction must not
     * apply.
     */
    private var renderedLastMm: Double? = null

    /** Placement as a 4×4 column-major matrix (translation in 12..14); identity until placed. */
    private val placement = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    private var placed = false
    private var placedYawDeg = 0f

    // ── V4.2: the CPU frame source and the foot tracker ─────────────────────────────────────
    //
    // Dart's detection loop (V4.1) asks for one throttled NV21 frame per tick over
    // `acquireCameraFrame` and answers with one `setFootPose` observation per accepted detection.
    // The cache below is the frame half; [footTracker] is the world half — Dart's normalized UV
    // points are hit-tested onto the floor and filtered into an anchor. Both are render-thread
    // state, like everything else this renderer owns; the getters are read from the UI thread by
    // the plugin, hence `@Volatile` on the four fields it touches.

    /** Latest throttled CPU frame (NV21 + geometry), or null before the first acquire. */
    @Volatile private var cachedFrameBytes: ByteArray? = null
    @Volatile private var cachedFrameWidth = 0
    @Volatile private var cachedFrameHeight = 0
    @Volatile private var cachedFrameRotationDegrees = 0
    private var lastFrameAcquireMs = 0L

    /** V4.2's tracker: observations in, a world anchor and a lock state out. */
    private val footTracker = FootPoseTracker()

    /** The last observation from Dart, waiting for the next render frame to hit-test it. */
    private var pendingFootPose: FootPoseTracker.Observation? = null

    // V4.9: pose-rejection telemetry. The 2026-10-06 device run had 254 detections and 0
    // locks, and nothing in the log said why: [sampleFoot] answers null for four different
    // reasons (no plane, non-tracking plane, polygon miss, degenerate axis) and all of them
    // were silent. Counted per rejection, logged at most once a second, and the running
    // totals ride the heartbeat so a phone with no adb still shows them.
    private var poseRejects = 0
    private var poseRejectsAccepted = 0
    private var lastPoseRejectLogMs = 0L
    private var lastPoseRejectReason = "-"

    // V4.9: how the accepted samples were accepted — inside the plane's polygon (the strict
    // read) or past its edge (the fallback). An edge-heavy ratio says the plane is tracking
    // but its extent estimate lags the foot, which is session-youngness, not a bad floor.
    private var hitTestsInPolygon = 0
    private var hitTestsOnEdge = 0

    /** Whether poses drive placement: true by default, false while QA forces `floor` mode. */
    private var footModeRequested = true

    /** When the last `footMeasure` went out — V4.6's throttle (see [FOOT_MEASURE_INTERVAL_MS]). */
    private var lastFootMeasureMs = 0L

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

    private val tapGesture by lazy {
        TapGesture(slopPx = ViewConfiguration.get(context).scaledTouchSlop.toFloat())
    }

    /**
     * AR mode's touch path (V3.4): a tap places the shoe where the finger landed, unless the foot
     * tracker already owns the placement. A drag is not a tap and does nothing here.
     */
    private fun onArTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> tapGesture.onDown(event.x, event.y, SystemClock.uptimeMillis())
            MotionEvent.ACTION_POINTER_DOWN -> tapGesture.onPointerDown()
            MotionEvent.ACTION_MOVE -> tapGesture.onMove(event.x, event.y)
            MotionEvent.ACTION_CANCEL -> tapGesture.cancel()
            MotionEvent.ACTION_UP -> {
                val tapped = tapGesture.onUp(event.x, event.y, SystemClock.uptimeMillis())
                if (tapped && !footTracker.hasAnchor) {
                    Log.i(TAG, "tap placed the shoe at ${event.x.toInt()}, ${event.y.toInt()}")
                    placeShoe(event.x.toDouble(), event.y.toDouble())
                }
            }
        }
        return super.onTouchEvent(event)
    }

    /**
     * Drag to turn, pinch to zoom, in [Mode.PREVIEW] only.
     *
     * Nothing here talks to the render thread directly — it writes the volatile orbit state the
     * next frame reads — so a fast drag cannot queue up behind a slow frame.
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (mode != Mode.PREVIEW) return onArTouch(event)
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
    /**
     * **V4.9: the night-aid torch.** ARCore's auto-exposure is already at its ceiling in a
     * dark room (the HAL logs cap exposure at the 30 fps frame time with maxed analogue
     * gain), so past a point the feed can only get brighter with more light. The torch is
     * the honest fix: `Config.FlashMode.TORCH` drives the phone's own flash through the
     * session, no second camera client, no Camera2 fight.
     *
     * Stored before the session starts (read by [startSession]'s config) and reconfigured
     * live when a session is already running: `Session.configure` replaces the *whole*
     * config, so the live path sends `session.config` — the config in effect, which already
     * carries plane finding, focus and the rest — with only the flash mode changed. A call
     * with no live session is a no-op that only parks the value.
     */
    fun setTorch(enabled: Boolean) {
        torchEnabled = enabled
        relay("setTorch($enabled)")
        renderHandler.post {
            val target = session
            if (target == null || !sessionResumed) {
                relay("torch: $enabled stored (applies at next session start)")
                return@post
            }
            val outcome = runCatching {
                target.configure(
                    target.getConfig().apply {
                        flashMode = if (enabled) Config.FlashMode.TORCH else Config.FlashMode.OFF
                    },
                )
            }
            if (outcome.isSuccess) {
                relay("torch: $enabled applied live")
            } else {
                relay("torch: $enabled FAILED: ${outcome.exceptionOrNull()?.message}")
                Log.w(TAG, "torch reconfigure failed", outcome.exceptionOrNull())
            }
        }
    }

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

    /**
     * **Sets the stage behind the shoe — the colour the renderer clears to.**
     *
     * ARGB, as Flutter spells a colour; the four bytes become the RGBA `double[]`
     * `Renderer.ClearOptions.clearColor` wants. Sent by the preview alone, at mount and again
     * whenever the customer's appearance changes (see [stageColor]).
     *
     * ⚠️ **Legal before the engine exists** — the same parking contract the model follows, and for
     * the same reason: Dart hands this over the moment the box is built, while the platform view
     * (and therefore the renderer) is created a frame later. The value is kept and written by
     * [createEngineIfNeeded] when the renderer appears, so an early brightness is not lost.
     */
    fun setBackground(argb: Int) {
        renderHandler.post {
            stageColor = doubleArrayOf(
                ((argb shr 16) and 0xFF) / 255.0,
                ((argb shr 8) and 0xFF) / 255.0,
                (argb and 0xFF) / 255.0,
                ((argb shr 24) and 0xFF) / 255.0,
            )
            applyClearColor()
        }
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
     *
     * **The graded last is kept, not just the ratio (V4.3).** `renderedLastMm` is the number
     * [FootScaleCorrection] weighs the live measured foot against; storing it here is what keeps
     * one grade in the app — the same one this method just applied.
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
            renderedLastMm = graded
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

    /**
     * **V4.1's loop calls this** (§2.8's `acquireCameraFrame`): the most recent throttled CPU
     * frame, or null when none is ready yet.
     *
     * Read from the UI thread by the plugin while the render thread writes, hence the `@Volatile`
     * fields. A frame that lands a millisecond after this check is *next* tick's frame, which is
     * exactly what the Dart loop's 200 ms cadence assumes — and null is a skip there, not a
     * failure.
     */
    fun hasCachedCameraFrame(): Boolean = cachedFrameBytes != null
    fun getCachedCameraFrameBytes(): ByteArray? = cachedFrameBytes
    fun getCachedCameraFrameWidth(): Int = cachedFrameWidth
    fun getCachedCameraFrameHeight(): Int = cachedFrameHeight
    fun getCachedCameraFrameRotationDegrees(): Int = cachedFrameRotationDegrees

    /**
     * One observation from Dart's detection loop (§2.8's `setFootPose`), in normalized
     * upright-image UV.
     *
     * Posted to the render thread rather than processed here: the hit tests need the render
     * thread's current `Frame`, and this call arrives on the UI thread mid-frame. Only the latest
     * observation is kept — a backlog of 2D poses is stale by definition, and the Dart side already
     * drops ticks it could not keep up with (`kFootTrackInterval`'s overlap guard).
     */
    internal fun setFootPose(observation: FootPoseTracker.Observation) {
        if (mode != Mode.AR) return
        renderHandler.post { pendingFootPose = observation }
    }

    /**
     * **V4.4: one accepted frame's occlusion mask** — 32×32 bytes plus the sample's quality.
     *
     * Posted like [setFootPose] and for the same reason (the draw needs the render thread's
     * current `Frame`, and this call arrives on the UI thread); only the latest is kept, because a
     * mask belongs to the frame that produced it and a backlog would occlude a foot that has
     * already moved. The bytes are row-major, top-down, in the detection's own normalized space
     * (`lib/utils/foot_mask.dart`), which is what lets [applyFootMask] map a quad through the same
     * function the heel and toe rays are cast through.
     */
    internal fun setFootMask(bytes: ByteArray, confidence: Double) {
        if (mode != Mode.AR) return
        renderHandler.post { pendingFootMask = FootMaskFrame(bytes, confidence) }
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
        // PixelCopy rather than Filament's readPixels: it copies the *composited* surface, and the
        // feed is a real layer in this view, so the screenshot picks it up for free —
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
     * `foot` (the default) is V4's tracked mode: pose observations drive placement and the tracker
     * owns the lock. `floor` is the V3 behaviour and the QA escape hatch — the tracker is reset
     * and ignored, so a device session can compare the two modes on the same product. Recorded
     * rather than rejected, so a session sees the mode in the log instead of a silent no-op.
     */
    fun setTryOnMode(mode: String) {
        // V4.2: `foot` is now real — poses drive placement — and `floor` is the QA escape hatch
        // that disables the tracker (the shoe keeps its last placement; taps still place it).
        renderHandler.post {
            val wasRequested = footModeRequested
            footModeRequested = mode != "floor"
            if (wasRequested && !footModeRequested) {
                pendingFootPose = null
                // V4.4: the mask goes with the tracker. Leaving it up would draw a foot-shaped
                // hole over a shoe that has stopped following anything.
                pendingFootMask = null
                engine?.let { created -> footMaskOverlay?.hide(created) }
                val wasLocked = footTracker.reset()
                if (wasLocked) {
                    listener.onEvent(
                        "footLock",
                        mapOf("locked" to false, "quality" to 0.0, "side" to null),
                    )
                }
            }
        }
        Log.i(TAG, "setTryOnMode: $mode (V4.2: `foot` runs the tracker; `floor` disables it)")
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
            // V4.9: ARCore binds the session to the GL context that is current **here**, and
            // demands that same context current on the thread calling `update()`. The feed's
            // context is the one the camera texture lives in, so it is the one both ends must see
            // (`ArCameraFeed.makeArContextCurrent`). Without this the session starts, then refuses
            // every frame: `MissingGlContextException`, camera black, pose frozen.
            val feed = cameraFeed
            val contextBound = feed?.makeArContextCurrent() ?: false
            arUpdateFailureNoted = false
            try {
                val created = session ?: Session(context).also { session = it }
                created.configure(
                    Config(created).apply {
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        // Ambient intensity, not ENVIRONMENTAL_HDR: the HDR estimate needs the
                        // camera texture, which the feed now binds — but switching the estimate
                        // mode is a separately measured change, not a side effect of the feed.
                        lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                        updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                        focusMode = Config.FocusMode.AUTO
                        // V4.9: the night-aid torch, requested before the session existed
                        // (see [setTorch]). Every `configure` call must carry the current
                        // wish, because configure replaces the whole config.
                        flashMode =
                            if (torchEnabled) Config.FlashMode.TORCH else Config.FlashMode.OFF
                    },
                )
                // V4.9: **ARCore's viewport.** The surface callbacks above ran before this session
                // existed, so this is the first — and on a cold screen the only — moment ARCore can
                // be told what it is rendering into. See [applyDisplayGeometry] for what its absence
                // cost on the device.
                applyDisplayGeometry(created, "startSession")
                // V4.9: the feed looked zoomed because ARCore fills this tall screen from a
                // wide camera stream, cropping the sides. Pick the supported config that
                // wastes the least of the display — must land before `resume()`.
                selectCameraConfig(created)
                // F20: hand ARCore the feed's OES texture BEFORE resuming. ARCore starts writing
                // frames the moment the session is live, so a texture bound afterwards leaves the
                // first frames — and every frame after a session restart — undrawn.
                cameraFeed?.bindToSession(created)
                created.resume()
                sessionResumed = true
                // V4.8: an explicit start supersedes any surface-detach pause that was pending.
                pausedForSurfaceDetach = false
                Log.i(TAG, "session resumed")
                // V4.9: the same start marked through the in-app relay, so a phone with no adb
                // carries a timestamp to measure "how long until the first lock" against
                // (`tool/qa_capture.sh --tryon` reads both ends from one log).
                relay("session resumed (startSession)")
                relay(
                    "AR session GL context: " +
                        if (contextBound) {
                            "the camera feed's context is current"
                        } else {
                            "NOT current — ARCore will refuse every frame"
                        },
                )
                postToMain { onResult(StartOutcome(started = true)) }
            } catch (t: Throwable) {
                val outcome = sessionFailure(t)
                Log.w(TAG, "startSession failed: ${outcome.reason} — ${outcome.message}", t)
                relay("startSession failed: ${outcome.reason} — ${outcome.message}")
                postToMain { onResult(outcome) }
            } finally {
                if (contextBound) feed.releaseArContext()
            }
        }
    }

    /** Pauses the session. QA and tests only — teardown is owned by [dispose] (rule D1). */
    fun pauseSession() {
        renderHandler.post {
            runCatching { session?.pause() }.onFailure { Log.w(TAG, "pause failed", it) }
            sessionResumed = false
            // V4.8: a stop someone asked for is not the surface's pause, so the surface's return
            // must not undo it. (`stopSession` is the only caller.)
            pausedForSurfaceDetach = false
        }
    }

    /**
     * **V4.8: undo the pause [detachSurfaceAndWait] applied, once the surface is back.**
     *
     * The recovery for a backgrounded-then-returned session, and deliberately narrow: it resumes
     * only the pause the surface itself made — an explicit [pauseSession], a session a failure
     * already dropped, and a torn-down view all leave the flag false or [session] null, and the
     * early returns say so. The flag is cleared even when `Session.resume` throws, because retrying
     * a resume the framework refused on every surface callback turns one failure into a loop; the
     * next [startSession] (a fresh screen open) is the recovery path.
     */
    private fun resumeAfterSurfaceDetach() {
        if (!pausedForSurfaceDetach) return
        pausedForSurfaceDetach = false
        val existing = session ?: return
        // V4.9: the resume runs in the session's own context, like every other ARCore call here.
        val feed = cameraFeed
        val contextBound = feed?.makeArContextCurrent() ?: false
        runCatching { existing.resume() }
            .onSuccess {
                sessionResumed = true
                // V4.9: view data does not survive the pause/resume, and the surface that came back
                // may be a different size or rotation than the one ARCore was last told about.
                applyDisplayGeometry(existing, "surface returned")
                relay("session resumed after the surface returned")
            }
            .onFailure {
                Log.w(TAG, "session resume after surface return failed", it)
                relay("session resume after surface return FAILED: ${it.message}")
            }
        if (contextBound) feed.releaseArContext()
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
            // V4.8: and if the surface's own disappearance is what paused the ARCore session (the
            // app was backgrounded), undo that pause. Without this the backgrounding is permanent:
            // nothing else in the app ever asks for this session to start again.
            resumeAfterSurfaceDetach()
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        surfaceWidth = width
        surfaceHeight = height
        renderHandler.post {
            // `setViewport` takes a `Viewport`, not four ints (Filament 1.72's Java API).
            view?.setViewport(Viewport(0, 0, width, height))
            createSwapChain()
            // V4.9: the session usually does not exist yet here — on a first session it never does
            // (the surface callbacks run when the view mounts; the session is created later, when
            // Dart asks for it). This call is what catches a resize or rotation once it does.
            session?.let { applyDisplayGeometry(it, "surfaceChanged") }
        }
    }

    /**
     * **Tells ARCore the viewport it is rendering into. One call site cannot do this.**
     *
     * ⚠️ **The device measurement behind this method (V4.9, 2026-10-05).** This view's lifecycle puts
     * the surface callbacks first and the session second: `surfaceCreated`/`surfaceChanged` run when
     * the platform view mounts, while the session is created in [startSession], after the model
     * handover reaches Dart. So the call that used to live only in `surfaceChanged` was a silent
     * no-op on the first session — its `session?.` was null — and ARCore ran with **no display
     * geometry at all**. Its own logs said so: `view_manager_utils.cc: Display geometry has an
     * invalid width: 0`, on every frame. Three costs followed, all measured on the device:
     *
     *  - `Frame.transformCoordinates2d` cannot convert the quad's view-normalized corners into
     *    texture coordinates, so the camera quad samples the wrong texels — coloured static that
     *    changes as the camera moves instead of the room;
     *  - every `Frame.hitTest` logs `session.cc: Invalid ray produced by view data!` and returns
     *    nothing (498 times in one 84-second session), which is tap-to-place broken;
     *  - `Camera.getProjectionMatrix` is computed from the same empty view data, so the shoe would
     *    be projected with a matrix that has nothing to do with this surface.
     *
     * Called from [startSession] (the first and, on a cold screen, the only moment the session
     * exists), from [resumeAfterSurfaceDetach] (a returning surface may have a new size or rotation)
     * and from [surfaceChanged] (a resize or rotation while the session is running).
     */
    private fun applyDisplayGeometry(session: Session, reason: String) {
        val width = surfaceWidth
        val height = surfaceHeight
        if (width <= 0 || height <= 0) return
        val rotation = runCatching { display?.rotation }.getOrNull() ?: 0
        runCatching { session.setDisplayGeometry(rotation, width, height) }
            .onSuccess {
                relay("display geometry applied ($reason): ${width}x$height rot=$rotation")
            }
            .onFailure { t -> Log.w(TAG, "setDisplayGeometry failed ($reason)", t) }
    }

    /**
     * **V4.9: picks the ARCore camera config that shows the widest view on this display.**
     *
     * Why this exists (the "zoomed-in" feed): ARCore fills the view with the camera image,
     * cropping whatever does not fit. This phone's screen is 1080x2400 (aspect ~0.45) while
     * the camera's usual stream is 16:9 (aspect 1.78) — filling the tall screen from the wide
     * image shows only ~25% of the image's width, which reads as a ~2x zoom next to the
     * camera app. ARCore usually offers a 4:3 stream too (1440x1080 here): the same texel
     * density on screen but ~34% of the width visible — a measurably wider view for the same
     * sharpness, because the crop, not the resolution, sets the zoom.
     *
     * Called from [startSession] before `resume()`, the documented safe point for
     * `setCameraConfig`. Enumerates every supported config, relays them all (so a phone with
     * no adb still records what it chose from), and picks the config whose texture aspect
     * wastes the least of the display: the visible fraction of the cropped axis is
     * `displayAspect / textureAspect` (width, on a portrait screen) or its inverse —
     * maximize it, tie-break on texture area for sharpness. Any failure keeps ARCore's own
     * default: a wider feed is not worth a session that never starts.
     */
    private fun selectCameraConfig(session: Session) {
        val width = surfaceWidth
        val height = surfaceHeight
        if (width <= 0 || height <= 0) return
        val displayAspect = width.toDouble() / height
        // The filter overload is the non-deprecated path; no restrictions, so it lists
        // every config the device offers — the same set the deprecated getter returned.
        val candidates =
            runCatching { session.getSupportedCameraConfigs(CameraConfigFilter(session)) }
            .onFailure { t -> Log.w(TAG, "getSupportedCameraConfigs failed", t) }
            .getOrDefault(emptyList())
        if (candidates.isEmpty()) {
            relay("camera config: none listed — keeping ARCore's default")
            return
        }
        val scored = candidates.map { cfg ->
            val tex = cfg.textureSize
            Triple(cfg, tex.width, tex.height)
        }
        scored.forEach { (cfg, tw, th) ->
            relay(
                "camera config candidate: texture ${tw}x${th} " +
                    "image ${cfg.imageSize.width}x${cfg.imageSize.height} " +
                    "fps ${cfg.fpsRange.lower}..${cfg.fpsRange.upper}",
            )
        }
        fun visibleFraction(texW: Int, texH: Int): Double {
            val texAspect = texW.toDouble() / texH
            return if (texAspect > displayAspect) displayAspect / texAspect
            else texAspect / displayAspect
        }
        val chosen = scored.maxWith(
            compareBy({ visibleFraction(it.second, it.third) }, { it.second.toLong() * it.third }),
        )
        val pct = (visibleFraction(chosen.second, chosen.third) * 100).toInt()
        runCatching { session.cameraConfig = chosen.first }
            .onSuccess {
                relay(
                    "camera config: chosen ${chosen.second}x${chosen.third} — $pct% of the " +
                        "cropped axis visible (widest of ${candidates.size})",
                )
            }
            .onFailure { t -> Log.w(TAG, "setCameraConfig failed — keeping default", t) }
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
        // ── F20: the feed's OES texture needs a share group ────────────────────────────────
        // Filament can only sample a GL texture that lives in a context sharing with its own, so
        // the feed creates an EGL context and the engine is built against it (the Filament API
        // requires exactly this: an `android.opengl.EGLContext`, not a handle). AR-only, because
        // the preview has no camera. A context that cannot be created is reported and the engine
        // still comes up: the shoe must render even when the room cannot.
        if (mode == Mode.AR) {
            val feed = cameraFeed ?: ArCameraFeed(context).also { cameraFeed = it }
            val shared = feed.prepareSharedContext()
            if (shared != null) {
                engineBuilder.sharedContext(shared)
                relay("camera feed: EGL context prepared and shared with the engine")
            } else {
                relay("camera feed: no shared EGL context — ${feed.describe()}")
            }
        }
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
        view = created.createView().apply {
            setScene(createdScene)
            // V4.9 night-feed grading — see [colorGrading]. Applied to the whole view, so the
            // shoe gains the same exposure as the feed; in a dark room that is the intent.
            colorGrading = ColorGrading.Builder()
                .toneMapper(ToneMapper.Linear())
                .exposure(FEED_EXPOSURE_EV)
                .build(created)
                .also { colorGrading = it }
        }
        cameraEntity = EntityManager.get().create()
        camera = created.createCamera(cameraEntity).apply {
            setProjection(FOV_DEGREES, 1.0, NEAR_METERS, FAR_METERS, Camera.Fov.VERTICAL)
        }
        view?.camera = camera
        val provider = UbershaderProvider(created)
        materialProvider = provider
        assetLoader = AssetLoader(created, provider, EntityManager.get())
        createLights(created)
        // F20: the feed's quad, material and texture, built against the live engine. AR-only, and
        // after the scene exists because the feed adds one entity to it. A failure here (missing
        // asset, material mismatch) is carried in [ArCameraFeed.describe] rather than thrown: the
        // shoe is the point of this screen, and it must render with or without the room.
        if (mode == Mode.AR) {
            cameraFeed?.attach(created, createdScene)
            relay("camera feed: ${cameraFeed?.describe() ?: "off"}")
            // V4.4: the overlay draws with the feed's own texture (see [FootMaskOverlay.attach]),
            // so it attaches *after* the feed — and only when the feed is ready, because an
            // unbound external texture samples black, and painting black over the shoe would look
            // worse than not occluding it. Both attach failures are one line in the log rather
            // than an exception: the shoe is the point of this screen.
            val feed = cameraFeed
            if (feed != null && feed.isReady) {
                val overlay =
                    footMaskOverlay ?: FootMaskOverlay(context).also { footMaskOverlay = it }
                overlay.attach(created, createdScene, feed.cameraTexture)
                relay("foot mask overlay: ${overlay.describe()}")
            } else {
                relay("foot mask overlay: off (camera feed not ready)")
            }
        }
        // The stage. ⚠️ **Called rather than written inline**, because this is the one place a
        // colour sent *before* the renderer existed must not be lost: `setBackground` parks the
        // value on the render thread (Dart sends it the moment the box is built, a frame before
        // this engine), and the application point is here. AR keeps [DEFAULT_CLEAR_COLOR] forever
        // — see [stageColor].
        applyClearColor()
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
     * **Writes [stageColor] to the renderer — the stage the box clears to.**
     *
     * Called from two places, and both are needed. From [setBackground] on every colour that
     * arrives while an engine is alive: a theme flip has to repaint a renderer that already
     * exists, and there is no surface or swap-chain event to hang it off. From
     * [createEngineIfNeeded], so a colour that arrived *first* (the common case — Dart sends it as
     * the box is built) is applied to the engine that was built after it.
     *
     * A no-op before the renderer exists: the value is already parked in the field, and engine
     * creation is what reads it.
     */
    private fun applyClearColor() {
        val target = renderer ?: return
        target.setClearOptions(
            Renderer.ClearOptions().apply {
                clear = true
                // The stage ARCore's first frame replaces — the light
                // stage in a light-mode preview, [DEFAULT_CLEAR_COLOR] otherwise.
                // `ClearOptions.clearColor` is a `double[]` on this API, not a `float[]`.
                clearColor = stageColor ?: DEFAULT_CLEAR_COLOR
            },
        )
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
                    // V4.8: remember that the surface is what paused, so its return may resume; and
                    // drop the cached detection frame, so a resumed Dart loop finds null — a skipped
                    // tick, its normal case — instead of a frozen frame from before the backgrounding.
                    pausedForSurfaceDetach = session != null
                    cachedFrameBytes = null
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
            // F20: whether the room is being drawn, and — when it is not — the reason, on the line
            // a phone with no logcat is read from. `off` in preview mode, which has no feed.
            append(" feed=").append(cameraFeed?.describe() ?: "off")
            // V4.2: where the tracker is (idle/search/locked), and whether Dart's next frame
            // request will find a CPU image — the two facts a foot-tracking bug report needs and
            // a phone with no logcat cannot otherwise give.
            append(" foot=").append(footTracker.describe())
            // V4.9: pose pipeline health at a glance — accepted/rejected and how many of the
            // accepted came from the polygon-edge fallback (the `e` number). A rising edge
            // count with accepted>0 means ARCore's planes are tracking but still growing —
            // give it a second pointing at the floor rather than concluding the feature is
            // broken.
            append(" pose=").append(poseRejectsAccepted).append('/')
                .append(poseRejects).append('e').append(hitTestsOnEdge)
            // V4.3: the two numbers the frame-scale correction is made of. `len` is the measured
            // foot, `-` before the first accepted pose; `scale` is the ×N it produced, so 1.000
            // reads as "the size chart's answer stands" — no anchor, a refused measurement, or a
            // foot that matches the size exactly. A device session tunes [FootScaleCorrection]'s
            // constants from this pair on real feet.
            val statusFoot = footTracker.anchor()
            append(" len=").append(
                statusFoot?.lengthMeters?.let { "${(it * 1000.0).roundToInt()}mm" } ?: "-",
            )
            append(" scale=").append(
                fmt(FootScaleCorrection.factor(statusFoot?.lengthMeters, renderedLastMm)),
            )
            append(" frame=").append(
                cachedFrameBytes?.let {
                    "${cachedFrameWidth}x${cachedFrameHeight}@${cachedFrameRotationDegrees}"
                } ?: "none",
            )
            // V4.4: whether the foot is being cut out of the shoe, the last mask's quad count and
            // its confidence. `off` when the overlay never attached (no camera feed, no texture),
            // `ready (no mask yet)` when it did and Dart has not sent one — the distinction a
            // "the shoe is not occluded" report turns on.
            append(" mask=").append(footMaskOverlay?.describe() ?: "off")
            append(" r=").append((previewRadiusM * 1000.0).roundToInt()).append("mm")
            append(" yaw=").append(orbitYawDeg.roundToInt())
            append(" touch=").append(touchDowns).append('/').append(touchMoves)
                .append('/').append(touchUps)
            append(" interacting=").append(if (interacting) "1" else "0")
            append(" size=").append(surfaceWidth).append('x').append(surfaceHeight)
            // V4.8: the device's thermal state, the one fact of the thermal check a screenshot
            // cannot otherwise carry. `n/a` below Android 10, where the getter does not exist.
            append(" thermal=").append(thermalLabel())
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

    /**
     * The thermal readout for [emitStatus] — V4.8's check, one word.
     *
     * Read on the render thread with the rest of the heartbeat; `getCurrentThermalStatus` is a
     * cheap getter, and the API guard is the whole reason [ThermalReport] takes a nullable: below
     * Android 10 the platform cannot answer, and "n/a" says that instead of inventing `none`.
     */
    private fun thermalLabel(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return ThermalReport.label(null)
        val manager = runCatching { context.getSystemService(PowerManager::class.java) }.getOrNull()
        val status = runCatching { manager?.currentThermalStatus }.getOrNull()
        return ThermalReport.label(status)
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
            // V4.9: the context the session was built in, current for the whole AR block —
            // `update()` refuses to run without it (`MissingGlContextException`).
            val feed = cameraFeed
            val contextBound = feed?.makeArContextCurrent() ?: false
            try {
                val frame = activeSession.update()
                applyArCamera(frame)
                sampleArLighting(frame)
                // V4.2: the CPU frame the Dart loop will ask for next tick, then the tracker —
                // poses before the frame so the anchor is current when it is drawn.
                captureFrameForDetection(frame)
                applyFootTracking(frame)
                // V4.4: the mask over the shoe, from the same frame the pose above was sampled
                // from, and before the auto-placement fallback so the draw sees this frame's
                // viewport state rather than the next frame's.
                applyFootMask(frame)
                autoPlaceIfNeeded(frame)
                // F20: the room. `update` binds the texture ARCore wrote this frame into the feed's
                // material and re-derives the quad's UVs when the display geometry changed.
                // Wrapped so a feed failure costs the backdrop rather than the frame: the pose
                // above is already applied, and a black room must not become a stopped loop.
                runCatching { cameraFeed?.update(created, activeSession, frame) }
                    .onFailure { Log.w(TAG, "camera feed update failed", it) }
            } catch (t: Throwable) {
                Log.w(TAG, "session.update threw; keeping the last pose", t)
                if (!arUpdateFailureNoted) {
                    arUpdateFailureNoted = true
                    relay("session.update threw ${t.javaClass.simpleName}: ${t.message}")
                }
            } finally {
                if (contextBound) feed.releaseArContext()
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
            // `setDisplayGeometry` to have run, hence the guard above and [applyDisplayGeometry].
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
        // A tracked shoe is already placed where it belongs: auto-placement is the answer for the
        // seconds *before* the tracker has seen a foot, and fighting it afterwards would teleport
        // the shoe back to the screen centre on every frame.
        if (footTracker.hasAnchor) return
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
        // V4.4: the shoe draws after the camera feed and before the occlusion mask. Filament draws
        // higher priorities first, so this is the ordering half of the mask's contract (the mask's
        // near-depth write is the other half); the feed's own `priority(7)` is the same rule from
        // SceneView, and the mask's 0 is FootMaskOverlay's default.
        runCatching {
            val renderables = created.renderableManager
            for (entity in createdAsset.renderableEntities) {
                renderables.setPriority(entity, FootMaskOverlay.SHOE_PRIORITY)
            }
        }.onFailure { t -> Log.w(TAG, "shoe priority write failed", t) }
        modelRoot = createdAsset.root
        // ⚠️ **The entity is the handle this side keeps; the transform *instance* is what
        // `setTransform` takes, and the two are different packed ints — passing the entity where
        // an instance belongs is the crash of 2026-10-05.** The first real load died inside
        // native `nSetTransform` (`Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR)` in
        // `libfilament-jni`, the frame directly under `applyTransform`; `runCatching` cannot see
        // a native fault) because this line stored the entity and the write handed it straight
        // to `setTransform`. [modelRootTransformInstance] resolves the instance for every write,
        // and the relay below puts both handles in the file channel for the load — the refusal
        // case has to be readable on a phone with no logcat.
        transformWriteRefused = false
        transformRefusalNoted = false
        val rootInstance = modelRootTransformInstance(created)
        relay(
            "load: root transform — entity=$modelRoot instance=$rootInstance" +
                if (rootInstance == 0) " (no component — nothing can be written to it)" else "",
        )
        // ⚠️ **The bounded drain the load's failed launches needed (measured, 2026-10-02).** Twice
        // the P30 Pro's log ended at the line below this block and the process lived on: the natives
        // that follow it are `setTransform` and the asset's bounding-box read, and neither can be
        // given a timeout. If the driver is still finishing the work `loadResources` queued, the
        // stall lands in one of those — so the wait happens here instead, in the one call on this
        // path that *can* time out and report whether it drained. Every device pays a flush it does
        // not need; only the device that stalls notices.
        val drained = runCatching { created.flushAndWait(LOAD_TAIL_FLUSH_TIMEOUT_NANOS) }
            .getOrDefault(false)
        relay("load: drained before the transform — flushAndWait=${if (drained) "ok" else "timeout"}")
        relay("load: entities added — applying the transform")

        pendingAuthoredLengthMm = spec.authoredLengthMm
        yawOffsetDeg = spec.yawOffsetDeg ?: 0.0
        sizeScale = 1.0f
        // A new asset invalidates the grade with it: the next `setSize` re-establishes both, and
        // until then the frame-scale correction has no baseline and must answer ×1 (V4.3).
        renderedLastMm = null
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
     * authored in millimetres, and both must render at the right size. **Since V4.3 there is a
     * third factor** — the foot measured in the frame — and it is read from [effectiveScale] here
     * *and* by the tracker's per-frame path, for the same reason [authoredLengthCorrection] is one
     * function: two places that compute a scale eventually disagree about the shoe's size.
     */
    private fun applyTransform() {
        val created = engine ?: return
        if (modelRoot == 0) return

        val scale = effectiveScale(footTracker.anchor())
        val matrix = FloatArray(16)
        Matrix.setIdentityM(matrix, 0)
        Matrix.translateM(matrix, 0, placement[12], placement[13], placement[14])
        if (placed) Matrix.rotateM(matrix, 0, placedYawDeg + yawOffsetDeg.toFloat(), 0f, 1f, 0f)
        Matrix.scaleM(matrix, 0, scale, scale, scale)
        runCatching { writeModelTransform(created, matrix) }
            .onFailure { t -> Log.w(TAG, "setTransform failed", t) }
        // ⚠️ **The load's last window, split at its midpoint (measured, 2026-10-02).** Twice on the
        // P30 Pro the log ended one line *above* this one — after `entities added — applying the
        // transform` — with half a second of silence before the activity finished, so the render
        // thread was inside `setTransform` or inside the bounding-box read below it. Which of the
        // two it was is this line: a log that never reaches it died in `setTransform`, and one that
        // ends on it died in the box. (`applyTransform` is shared with the AR placement path; a
        // placement pays one line for the same call, which has the same stall surface.)
        //
        // Since 2026-10-05 this line is also skipped, deliberately, when the write was refused
        // for a missing transform component ([transformWriteRefused]): a load whose log has no
        // `transform written` line is then either the native stall described above *or* a
        // refusal — and a refusal leaves its own lines before this point (`root transform …
        // instance=0` at the load, plus the `transform write refused` warning).
        if (!transformWriteRefused) relay("load: transform written — reading the bounding box")

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

    /**
     * The root's **transform component instance** — the handle every `setTransform` takes — or `0`
     * when the entity has no component and one could not be created.
     *
     * ⚠️ **Entity ≠ instance, and passing the wrong one is the crash of 2026-10-05.** Filament
     * hands out two different packed `int` handles and this file keeps the *entity* ([modelRoot],
     * from `FilamentAsset.getRoot()`): `hasComponent` / `create` / `getInstance` take the entity,
     * `setTransform` takes the *instance* those return. Both are `int`s and both read `0` as
     * "nothing", so the mistake compiles — and then the write indexes the transform store with a
     * number from another handle space. Measured on the Redmi 24094RAD4G (Android 16), inside the
     * first real load: a native fault in
     * `Java_com_google_android_filament_TransformManager_nSetTransform`, with the file channel
     * stopping at `entities added — applying the transform`. `SceneView`'s own `Node` resolves
     * `getInstance(entity)` before every write for exactly this reason; this function is that
     * resolution.
     *
     * The component is created on demand, guarded the way `SceneView`'s `Node.init` guards it
     * (`if (!hasComponent) create`): the root is documented only as "the transform root for the
     * asset", and `FilamentAsset`'s "all of these have a transform component" note covers the
     * glTF nodes, not the root it returns. Creating when a component already exists is at best
     * redundant and at worst a destroy-and-recreate that reindexes the store mid-session, so the
     * guard stays.
     *
     * Re-read on every write, never cached: the store is a packed array that compacts when any
     * component is destroyed (every asset swap destroys one), so a handle cached across a swap can
     * name another entity's slot — `SceneView` generation-checks its cached copy for the same
     * reason. The entity is the stable half of the pair, which is why [modelRoot] keeps it.
     */
    private fun modelRootTransformInstance(created: Engine): Int {
        if (modelRoot == 0) return 0
        val transformManager = created.transformManager
        return runCatching {
            if (!transformManager.hasComponent(modelRoot)) transformManager.create(modelRoot)
            transformManager.getInstance(modelRoot)
        }.getOrElse { t ->
            Log.w(TAG, "transform component lookup failed for entity $modelRoot", t)
            0
        }
    }

    /**
     * The one write of the model's matrix — both the load's [applyTransform] and the tracker's
     * [applyFootTransform] go through here, so the instance resolution cannot be right in one
     * place and wrong in the other (the 2026-10-05 crash was exactly a write line shared by both
     * sites, both passing the entity).
     *
     * A refusal (no component) is recorded in [transformWriteRefused] and logged once per load:
     * the per-frame caller runs at display rate and must not refill logcat with one line. A Java
     * throwable from the native call is left to the caller — both call sites already wrap this in
     * `runCatching` and log with their own message.
     */
    private fun writeModelTransform(created: Engine, matrix: FloatArray) {
        val instance = modelRootTransformInstance(created)
        if (instance == 0) {
            transformWriteRefused = true
            if (!transformRefusalNoted) {
                transformRefusalNoted = true
                Log.w(TAG, "transform write refused — entity $modelRoot has no transform component")
            }
            return
        }
        transformWriteRefused = false
        created.transformManager.setTransform(instance, matrix)
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

    // ════════════════════════════════════════════════════════════════════════════════════════
    // V4.2 — CPU frame source and foot tracking
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * **The frame half of V4.2** — the CPU image Dart's detector runs on.
     *
     * ARCore hands out the camera image as a separate CPU stream (`acquireCameraImage`) that
     * coexists with the GPU texture the feed draws, and this render loop is the only place it can
     * be read: a `Frame` is valid for one `Session.update()` cycle, on the thread that made it.
     * Throttled at [CAMERA_FRAME_INTERVAL_MS] — the scan plugin's own value — so a 5 Hz reader
     * always finds something fresh without paying a YUV conversion per render frame.
     *
     * ⚠️ **A deliberate copy of `ArFootSizingView`'s acquisition**, recorded as debt alongside the
     * rest of the renderer duplication (architecture §2.4): the try-on session owns the camera
     * while the scan's plugin owns *its* session, so neither can borrow the other's frames. The
     * result shape is identical on purpose — `ArCameraFrame.fromMap` reads this exact map, so the
     * app keeps one frame vocabulary rather than two.
     */
    private fun captureFrameForDetection(frame: Frame) {
        if (mode != Mode.AR) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastFrameAcquireMs < CAMERA_FRAME_INTERVAL_MS) return
        lastFrameAcquireMs = now
        try {
            val image: Image? = frame.acquireCameraImage()
            if (image != null) {
                try {
                    cachedFrameBytes = yuv420ToNv21(image)
                    cachedFrameWidth = image.width
                    cachedFrameHeight = image.height
                    cachedFrameRotationDegrees = currentDisplayRotationDegrees()
                } finally {
                    // ⚠️ Must always close, or the buffer pool exhausts and every later frame
                    // throws — the scan found this the hard way.
                    image.close()
                }
            }
        } catch (t: Throwable) {
            // `NotYetAvailableException` for the first frames after resume, or intermittently.
            // Debug level: this can fire until the first frame is ready and is not a fault.
            Log.d(TAG, "camera image not available: ${t.message}")
        }
    }

    /**
     * **The world half of V4.2.** At most one observation per render frame: hit-test both
     * endpoints onto the floor, hand the tracker a world sample, then draw from its anchor.
     *
     * Every rejection below is a *frame*, not a failure: no cached frame yet (the UV mapping
     * needs the image's upright dimensions), no floor under the heel or the toe (normal for the
     * first second of a session, and for a foot at the edge of a plane), or an axis too short to
     * orient a shoe. Dart's loop keeps publishing through all of them, and the tracker's staleness
     * decay is what turns a long run into `footLock {locked=false}` rather than a silent freeze.
     */
    private fun applyFootTracking(frame: Frame) {
        if (mode != Mode.AR || !footModeRequested) return

        val observation = pendingFootPose
        if (observation != null) {
            pendingFootPose = null
            sampleFoot(frame, observation)?.let { emitFootLock(it) }
        }
        footTracker.onFrame(SystemClock.elapsedRealtime())?.let { emitFootLock(it) }

        // Draw from the eased anchor. Note what is *not* checked: the lock. The lock is a
        // coaching state (§2.9), and a shoe that stops following the moment the score dips below
        // 0.45 would visibly detach from a foot the tracker can still see.
        val anchor = footTracker.anchor() ?: return
        applyFootTransform(anchor)

        // V4.6: the fit verdict's live measurement. The anchor exists here or we returned above,
        // and the throttle is why this is not a 60 Hz event stream for a value that eases.
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lastFootMeasureMs >= FOOT_MEASURE_INTERVAL_MS) {
            lastFootMeasureMs = nowMs
            footTracker.measure()?.let { emitFootMeasure(it) }
        }
    }

    /**
     * **V4.4's draw: the mask, over the shoe.**
     *
     * Two things happen here, in order. A newly arrived mask becomes geometry and is uploaded
     * ([FootMaskOverlay.submit]); a mask that has stopped arriving is hidden by the overlay's own
     * staleness rule, so an old foot is never painted over a shoe the tracker has since moved.
     *
     * The quads are mapped with [uprightImageUvToPixels] — the same function [hitTestFloorPoint]
     * casts its rays through. That sharing is the whole reason the mask rides the pose's
     * coordinate space (`lib/utils/foot_mask.dart`): one mapping, so the occlusion cannot sit
     * somewhere the pose did not.
     */
    private fun applyFootMask(frame: Frame) {
        val overlay = footMaskOverlay ?: return
        if (mode != Mode.AR || !footModeRequested) return
        val created = engine ?: return

        val pending = pendingFootMask
        val now = SystemClock.elapsedRealtime()
        if (pending != null) {
            pendingFootMask = null
            val quads = FootMaskMesh.build(pending.bytes)
            val drawn = overlay.submit(
                engine = created,
                frame = frame,
                quads = quads,
                viewportWidth = surfaceWidth,
                viewportHeight = surfaceHeight,
                confidence = pending.confidence,
                nowMs = now,
                mapUv = ::uprightImageUvToPixels,
            )
            if (drawn == 0 && !quads.isEmpty) {
                // Worth one line: the mask crossed the channel and built quads, but nothing was
                // drawn — a viewport or frame geometry that is not ready yet. Distinguishes a
                // coordinate problem from "Dart sent nothing" in a log with no logcat.
                Log.w(
                    TAG,
                    "foot mask: ${quads.count} quads could not be drawn this frame " +
                        "(surface=${surfaceWidth}x$surfaceHeight, conf=${pending.confidence})",
                )
            }
        }
        overlay.update(created, now)
    }

    /**
     * **V4.9: counts one rejected observation and, at most once a second, says why.**
     *
     * The throttle matters: the detection loop publishes at ~5 Hz and a dark floor rejects
     * every one of them, so per-rejection logging would be the loudest line in the log for
     * information the previous second already carried. The one-second line is what turns
     * "foot detected, no lock" (254 detections, 0 locks, nothing else on 2026-10-06) into a
     * readable cause — `no heel plane` means ARCore has no TRACKING horizontal floor, which is
     * a light/texture problem, not a detection one.
     */
    private fun rejectPose(reason: String) {
        poseRejects++
        lastPoseRejectReason = reason
        val now = SystemClock.elapsedRealtime()
        if (now - lastPoseRejectLogMs >= 1_000L) {
            lastPoseRejectLogMs = now
            Log.i(
                TAG,
                "foot pose: rejected x$poseRejects (accepted $poseRejectsAccepted) — last: $reason",
            )
        }
    }

    /**
     * Two floor hit tests and one world sample, or null when this observation cannot be placed.
     *
     * [forward] is `toe − heel` in the floor plane; its length is passed through as
     * [FootPoseTracker.Sample.lengthMeters] — **V4.3's measurement**, the number the frame-scale
     * correction is made of. It is the same axis this method already checks for degeneracy, so no
     * extra arithmetic runs for it.
     */
    private fun sampleFoot(
        frame: Frame,
        observation: FootPoseTracker.Observation,
    ): FootPoseTracker.LockChange? {
        val heel =
            hitTestFloorPoint(frame, observation.heelU, observation.heelV)
                ?: run { rejectPose("no heel plane") ; return null }
        val toe =
            hitTestFloorPoint(frame, observation.toeU, observation.toeV)
                ?: run { rejectPose("no toe plane") ; return null }
        val forward = doubleArrayOf(
            (toe.tx() - heel.tx()).toDouble(),
            0.0,
            (toe.tz() - heel.tz()).toDouble(),
        )
        val axis = sqrt(forward[0] * forward[0] + forward[2] * forward[2])
        if (axis < MIN_FOOT_AXIS_METERS) {
            rejectPose("axis %.0fmm < min".format(axis * 1000))
            return null
        }
        poseRejectsAccepted++
        return footTracker.observe(
            FootPoseTracker.Sample(
                heel = doubleArrayOf(
                    heel.tx().toDouble(),
                    heel.ty().toDouble(),
                    heel.tz().toDouble(),
                ),
                forward = forward,
                lengthMeters = axis,
                quality = observation.confidence,
                side = observation.side,
            ),
            SystemClock.elapsedRealtime(),
        )
    }

    /**
     * A normalized upright-image point → a world point on a tracked horizontal plane.
     *
     * Two conversions, both copied from the scan for measured reasons:
     *
     *  1. **UV → viewport pixels is a centre-crop (fill) mapping**, not a stretch — see
     *     [uprightImageUvToPixels], which V4.4's mask overlay draws through as well, so a pose and
     *     its occlusion can never land in different places. The scan shipped without this once,
     *     and its symptom was "foot detected but 0 samples".
     *  2. **Only `HORIZONTAL_UPWARD_FACING` planes count.** A toe ray that clips the side of a
     *     box is still a hit, and a shoe anchored to a wall reads as broken.
     */
    private fun hitTestFloorPoint(frame: Frame, u: Double, v: Double): Pose? {
        if (!uprightImageUvToPixels(u, v, uvScratch)) return null
        val hits = runCatching { frame.hitTest(uvScratch[0], uvScratch[1]) }.getOrNull()
            ?: return null
        // V4.9: **two-tier acceptance.** A TRACKING horizontal plane whose polygon does not
        // yet reach the sample point was a silent rejection before — the device run of
        // 2026-10-06 answered 20 `no heel/toe plane` rejections to 1 accept with the foot in
        // frame, which is the "sometimes it does not display" report. The polygon is only
        // ARCore's conservative *extent estimate*: it grows as the camera sees more floor, so
        // early in a session — or right after a move — it has not reached under the foot even
        // though the plane's pose is valid there. An in-polygon hit still wins; a hit on a
        // TRACKING plane past its edge is the fallback, counted so the heartbeat can show how
        // much of the acceptance is edge. What still fails outright is a ray with no TRACKING
        // horizontal plane at all — no plane exists yet, and extrapolating one would put the
        // shoe above nothing.
        var edgeHit: Pose? = null
        for (hit in hits) {
            val plane = hit.trackable as? Plane ?: continue
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            if (plane.trackingState != TrackingState.TRACKING) continue
            if (plane.isPoseInPolygon(hit.hitPose)) {
                hitTestsInPolygon++
                return hit.hitPose
            }
            if (edgeHit == null) edgeHit = hit.hitPose
        }
        if (edgeHit != null) {
            hitTestsOnEdge++
            return edgeHit
        }
        return null
    }

    /**
     * **A normalized upright-image point → viewport pixels, centre-crop (fill).**
     *
     * The camera preview fills the view by `max(scaleX, scaleY)` and crops the excess, so this is
     * the mapping that turns a point the detector named into the pixel ARCore's `hitTest` expects
     * — and the mapping V4.4's mask quads are drawn through, which is why it is a function instead
     * of a block inside [hitTestFloorPoint]: a pose and the occlusion over it share one convention
     * or they drift apart.
     *
     * Answers false and leaves [out] untouched while the frame geometry is unknown (no cached
     * frame yet, or a viewport that has not been measured) — every caller skips the frame instead
     * of guessing a mapping.
     *
     * Doubles through the mapping and floats at the end: ARCore takes float pixels, and rounding
     * the intermediate would move a corner by up to half a pixel for nothing.
     */
    private fun uprightImageUvToPixels(u: Double, v: Double, out: FloatArray): Boolean {
        if (out.size < 2) return false
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return false
        val uprightW =
            if (cachedFrameRotationDegrees % 180 == 90) cachedFrameHeight else cachedFrameWidth
        val uprightH =
            if (cachedFrameRotationDegrees % 180 == 90) cachedFrameWidth else cachedFrameHeight
        if (uprightW <= 0 || uprightH <= 0) return false

        val viewW = surfaceWidth.toFloat()
        val viewH = surfaceHeight.toFloat()
        val scale = Math.max(viewW / uprightW, viewH / uprightH)
        val drawnW = viewW / scale
        val drawnH = viewH / scale
        val offsetX = (uprightW - drawnW) / 2f
        val offsetY = (uprightH - drawnH) / 2f
        out[0] = ((u * uprightW - offsetX) * scale).toFloat()
        out[1] = ((v * uprightH - offsetY) * scale).toFloat()
        return true
    }

    /**
     * The per-frame transform write for the foot anchor.
     *
     * **Deliberately lighter than [applyTransform]:** that one also does the preview's
     * bounding-box fit and writes diag lines for the load's tail, and both are load-time work.
     * This path runs at display rate, so it writes the transform and nothing else — the same
     * placement × scale math, because the tracker drives the same shoe.
     */
    private fun applyFootTransform(anchor: FootPoseTracker.Anchor) {
        val created = engine ?: return
        if (modelRoot == 0) return
        Matrix.setIdentityM(placement, 0)
        Matrix.translateM(placement, 0, anchor.x.toFloat(), anchor.y.toFloat(), anchor.z.toFloat())
        placedYawDeg = anchor.yawDeg.toFloat()
        placed = true
        val scale = effectiveScale(anchor)
        val matrix = FloatArray(16)
        Matrix.setIdentityM(matrix, 0)
        Matrix.translateM(matrix, 0, placement[12], placement[13], placement[14])
        Matrix.rotateM(matrix, 0, placedYawDeg + yawOffsetDeg.toFloat(), 0f, 1f, 0f)
        Matrix.scaleM(matrix, 0, scale, scale, scale)
        runCatching { writeModelTransform(created, matrix) }
            .onFailure { t -> Log.w(TAG, "foot setTransform failed", t) }
    }

    /**
     * **V4.3's ×N, in one place for both transform paths.**
     *
     * Two factors already existed here — the selected size and the authored length — and the foot
     * measurement is the third. The multiplication lives in this function rather than at each
     * call site for the reason [authoredLengthCorrection] is a function: the load's transform and
     * the tracker's per-frame transform must agree, and a shoe that changes size the first time
     * the tracker takes over is the one thing an anchor swap must not do.
     *
     * The anchor is passed in rather than read from the tracker so the per-frame path pays one
     * lookup and cannot be scaled for an anchor other than the one it is drawing. A null anchor —
     * preview mode, or the seconds before the first accepted pose — is the size chart's answer,
     * untouched ([FootScaleCorrection.factor] answers ×1).
     */
    private fun effectiveScale(footAnchor: FootPoseTracker.Anchor?): Float {
        val frame = FootScaleCorrection.factor(footAnchor?.lengthMeters, renderedLastMm)
        return (sizeScale * authoredLengthCorrection() * frame).toFloat()
    }

    /**
     * The authored-length correction, extracted so the load's transform and the tracker's
     * per-frame transform cannot disagree about it: if they did, the shoe would change size the
     * first time the tracker took over — the one thing an anchor swap must not do.
     */
    private fun authoredLengthCorrection(): Float {
        val authoredExtent = asset?.boundingBox?.halfExtent?.get(2)?.times(2f) ?: 0f
        val declaredMm = pendingAuthoredLengthMm
        if (declaredMm != null && declaredMm > 0 && authoredExtent > 1e-6f) {
            return (declaredMm / 1000.0).toFloat() / authoredExtent
        }
        return 1.0f
    }

    /**
     * One `footMeasure` event (V4.6) — the eased heel→toe length in mm and the smoothed quality.
     *
     * Throttled by the caller ([FOOT_MEASURE_INTERVAL_MS]); this is the first thing to cross the
     * channel that is a *number* rather than a state, and it exists so Dart's fit engine can grade
     * the foot the camera can actually see instead of the saved scan from some earlier day.
     */
    private fun emitFootMeasure(measure: FootPoseTracker.Measure) {
        listener.onEvent(
            "footMeasure",
            mapOf(
                "lengthMm" to measure.lengthMeters * 1000.0,
                "quality" to measure.quality,
            ),
        )
    }

    /** One `footLock` event. Edges only: [FootPoseTracker] returns a change only on a flip. */
    private fun emitFootLock(change: FootPoseTracker.LockChange) {
        Log.i(TAG, "footLock locked=${change.locked} quality=${change.quality} side=${change.side}")
        // V4.9: the lock edges also go through the in-app relay, because the phone this session is
        // measured on cannot produce a logcat. Edges are rare (two or three per session), so the
        // relay's fsync-per-line cost is noise — and without this the exit criterion ("≥85% of
        // sessions lock within 10 s") would have no evidence at all on that phone.
        relay("footLock locked=${change.locked} quality=${fmt(change.quality)} side=${change.side}")
        listener.onEvent(
            "footLock",
            mapOf(
                "locked" to change.locked,
                "quality" to change.quality,
                "side" to change.side,
            ),
        )
    }

    /**
     * Rotation (degrees) that makes the sensor image upright — the scan's own formula and caveat.
     *
     * A rear camera captures in landscape (sensor orientation 90°), so portrait is 90°, not 0°.
     * It is used here only to decide which of the cached frame's dimensions are its *upright*
     * ones; the value never leaves this view.
     */
    private fun currentDisplayRotationDegrees(): Int {
        val displayDegrees = when (runCatching { display?.rotation }.getOrNull()) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        val sensorOrientation = 90
        return (sensorOrientation - displayDegrees + 360) % 360
    }

    /**
     * Convert a YUV_420_888 [Image] into one NV21 byte array — what ML Kit takes on Android.
     *
     * Handles arbitrary row/pixel strides by copying plane-by-plane (a vendor's camera can and
     * does hand back padded planes; assuming `width × height` here produces sheared images and
     * silent mis-detections). Copied from `ArFootSizingView` with the renderer duplication above;
     * the two must stay byte-compatible or the same detector will see two different images.
     */
    private fun yuv420ToNv21(image: Image): ByteArray {
        val width = image.width
        val height = image.height
        val ySize = width * height
        val nv21 = ByteArray(ySize + ySize / 2) // Y plane + interleaved VU

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        copyPlane(nv21, 0, yPlane, width, height)

        val chromaWidth = width / 2
        val chromaHeight = height / 2
        val vBuffer = vPlane.buffer
        val uBuffer = uPlane.buffer
        val vRowStride = vPlane.rowStride
        val uRowStride = uPlane.rowStride
        val vPixelStride = vPlane.pixelStride
        val uPixelStride = uPlane.pixelStride

        vBuffer.rewind()
        uBuffer.rewind()

        var dstPos = ySize
        for (row in 0 until chromaHeight) {
            val vRowStart = row * vRowStride
            val uRowStart = row * uRowStride
            for (col in 0 until chromaWidth) {
                // NV21 order: V first, then U.
                nv21[dstPos++] = vBuffer.get(vRowStart + col * vPixelStride)
                nv21[dstPos++] = uBuffer.get(uRowStart + col * uPixelStride)
            }
        }

        return nv21
    }

    /** Copy one [Image.Plane] into [dst] at [dstOffset], respecting row/pixel strides. */
    private fun copyPlane(
        dst: ByteArray,
        dstOffset: Int,
        plane: Image.Plane,
        width: Int,
        height: Int,
    ) {
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        buffer.rewind()

        var dstPos = dstOffset
        for (row in 0 until height) {
            val rowStart = row * rowStride
            for (col in 0 until width) {
                dst[dstPos++] = buffer.get(rowStart + col * pixelStride)
            }
        }
    }

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
        // ⚠️ **The asset is destroyed at the tail of this method, not here, and the move is a
        // revert.** One build set `asset = null` here and skipped `AssetLoader.destroyAsset` on the
        // theory that `engine.destroy()` a few statements later frees the same resources. It does
        // not free the *material instances* the asset owns, so `destroyMaterials()` then found them
        // alive and aborted the process — on a vivo V2022, on **every** teardown, on every device,
        // `PreconditionPanic: destroying material "base_lit_opaque" but 2 instances still alive`,
        // while the log line after it never printed. A guaranteed native abort is worse than the
        // P30 Pro's second-teardown stall that the skip was avoiding, so the asset keeps its
        // reference until the documented order can run below.
        pendingModel = null
        modelRoot = 0
        pendingFootPose = null
        pendingFootMask = null
        cachedFrameBytes = null
        footTracker.reset()
        runCatching { session?.close() }
        session = null
        sessionResumed = false
        pausedForSurfaceDetach = false
        destroySwapChain()
        engine?.let { created ->
            val flushed = runCatching { created.flushAndWait(TEARDOWN_FLUSH_TIMEOUT_NANOS) }
                .getOrDefault(false)
            relay("teardown: swap chain destroyed, flushAndWait=${if (flushed) "ok" else "timeout"}")
        }
        view?.let { engine?.destroyView(it) }
        scene?.let { engine?.destroyScene(it) }
        renderer?.let { engine?.destroyRenderer(it) }
        // V4.9: the grading object is engine-owned like the view above it — destroyed in the
        // same pass, after the renderer that drew with it.
        colorGrading?.let { engine?.destroyColorGrading(it) }
        colorGrading = null
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
        // ⚠️ **The asset goes before the loader and the provider, and that order is the fix for an
        // abort this file shipped, not decoration.** `AssetLoader`'s own javadoc states it — asset,
        // then loader, then the provider's materials — and `destroyMaterials()` **panics in native
        // code** if any instance is still alive: `destroying material "base_lit_opaque" but 2
        // instances still alive`. Those two instances are the loaded asset's, so the earlier
        // `destroyAsset` is what makes the drain below legal. The relay sits *before* the call on
        // purpose: it is a native call that a vendor driver may not return from (the P30 Pro's own
        // second-teardown stall), so a log that ends here names the call and one that reaches the
        // line after it proves the call returned.
        asset?.let { loaded ->
            assetLoader?.let { loader ->
                relay("teardown: destroying the asset — destroyMaterials needs its instances gone")
                runCatching { loader.destroyAsset(loaded) }
            }
        }
        asset = null
        assetLoader?.destroy()
        // `destroy()` does not free the materials it created (its own javadoc), and the asset that
        // used them is now gone, so the cache is drained explicitly here.
        materialProvider?.destroyMaterials()
        materialProvider?.destroy()
        // V4.4: the overlay samples the feed's texture, so it is destroyed first — before the feed
        // that owns the texture and the engine that owns them both. Its own material instance is
        // destroyed with it, in the one order native code does not panic over.
        footMaskOverlay?.destroy(engine)
        footMaskOverlay = null
        relay("teardown: foot mask overlay destroyed")
        // F20: the feed owns a material instance of its own, so it goes after the material drain
        // and before the engine it was built against — which is destroyed a few statements later.
        // Its EGL context dies here too; the engine's context shares that group but outlives it by
        // design, and nothing else references the feed afterwards.
        cameraFeed?.destroy(engine)
        cameraFeed = null
        relay("teardown: camera feed destroyed")
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

        /**
         * **V4.9 night-feed exposure gain, in EV stops, applied by [colorGrading].**
         *
         * +1.5 EV ≈ 2.8× brightness on top of undoing the default filmic tone mapping's
         * shadow crush (the switch to `Linear` alone lifts the dark end: ACES maps 0.18
         * linear to roughly a tenth of the range and takes the deep shadows toward black).
         * Chosen for a night room where the sensor is already maxed — the software gain
         * multiplies noise with the signal, so it is deliberately not higher; the torch
         * (see [setTorch]) is the real fix when the room is truly dark.
         */
        const val FEED_EXPOSURE_EV = 1.5f

        /**
         * **The stage with nothing sent — the near-black this view has cleared to since V3.2.**
         *
         * It is the same tone Dart's `#0E0F12` idle face paints, so the box does not flash
         * between tones as the engine starts, and it is what AR keeps permanently: the camera
         * feed is a dark surface in both brightnesses, and only the preview is ever sent a
         * customer's stage ([setBackground]).
         *
         * ⚠️ A `val`, not a `const`: Kotlin has no const `DoubleArray`, and this array is only
         * ever *read* — `Renderer.setClearOptions` copies it (`toFloatArray` on the native side),
         * so nothing can mutate it through the renderer.
         */
        val DEFAULT_CLEAR_COLOR = doubleArrayOf(0.055, 0.06, 0.07, 1.0)

        /** §2.6's grading step, mirrored from `fit_engine.dart`'s `sizeStepMm`. */
        const val SIZE_STEP_MM = 6.67
        const val MAX_SIZE_STEPS = 3.0

        const val KEY_LUX = 45_000f
        const val FILL_LUX = 9_000f

        const val PERF_WINDOW_NANOS = 5_000_000_000L
        const val LIGHT_SAMPLE_MS = 1_000L
        const val MAX_PLACEMENT_METERS = 12.0

        // ── V4.2 foot tracking ───────────────────────────────────────────────────────────────

        /**
         * How often the render loop converts a camera image to NV21 for the Dart detector.
         *
         * 150 ms, the scan plugin's own value: Dart reads at 5 Hz, so every tick finds a frame
         * that is at most ~150 ms old while the conversion is paid at two-thirds of the render
         * rate at most.
         */
        const val CAMERA_FRAME_INTERVAL_MS = 150L

        /**
         * How often the tracker's live measurement is published to Dart (V4.6).
         *
         * 500 ms — the verdict card is the consumer, and a sentence that redraws twice a second
         * is already more than a customer can read; the eased anchor changes slowly, so faster
         * events would repeat the same number more often rather than inform anyone. The edge
         * events (`footLock`) are unaffected: they stay edges-only.
         */
        const val FOOT_MEASURE_INTERVAL_MS = 500L

        /**
         * Below this, the heel and toe hit the same floor point and there is no axis to build.
         * 1 mm is two orders of magnitude under a real foot's length, so only a degenerate hit —
         * not a small foot — can trip it.
         */
        const val MIN_FOOT_AXIS_METERS = 1e-3

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
         * The bound on the drain before the load's transform tail (see its call site).
         *
         * ⚠️ **A stall needs a place to happen that can time out.** `setTransform` and the asset's
         * bounding-box read are the two natives the P30 Pro's log twice stopped on, and neither
         * takes a timeout; `flushAndWait` does. A second is long enough for a healthy driver to
         * finish the load's queued work (the whole load measures in tens of milliseconds on the
         * devices that do not stall) and short enough that a wedged one reports rather than hangs.
         */
        const val LOAD_TAIL_FLUSH_TIMEOUT_NANOS = 1_000_000_000L

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
