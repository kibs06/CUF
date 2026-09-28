package com.solevision.app.tryon

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
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
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.atan2
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
) : FrameLayout(context), SurfaceHolder.Callback {

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
    )

    /** `setSize` input, mirroring `lastLengthMm(size)` in `lib/utils/fit_engine.dart`. */
    data class SizeSpec(
        val sizeEu: Double?,
        val refSizeEu: Double?,
        val lastLengthMm: Double?,
    )

    private val surfaceView = SurfaceView(context).apply {
        holder.addCallback(this@ArTryOnView)
        // ARCore owns the camera and nothing is drawn behind this surface yet, so opaque is
        // correct until the feed becomes a Filament draw call (class header, gap 1).
        holder.setFormat(PixelFormat.OPAQUE)
        holder.setKeepScreenOn(true)
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

    init {
        addView(surfaceView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
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
    fun setModel(spec: ModelSpec) {
        renderHandler.post {
            pendingModel = spec
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
        val width = surfaceView.width
        val height = surfaceView.height
        if (width <= 0 || height <= 0) {
            onResult(null)
            return
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        // PixelCopy rather than Filament's readPixels: it copies the *composited* surface, so the
        // day the camera feed is a real layer in this view the screenshot picks it up for free —
        // §2.8's share-sheet image is "what the customer saw", not "what Filament drew".
        PixelCopy.request(
            surfaceView,
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
        renderHandler.post {
            teardown()
            renderThread.quitSafely()
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
        renderHandler.post {
            runCatching { session?.pause() }
            sessionResumed = false
            destroySwapChain()
            surface = null
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Engine / renderer
    // ════════════════════════════════════════════════════════════════════════════════════════

    private fun createEngineIfNeeded() {
        if (engine != null) return
        // Findings: these two are not optional and nothing else calls them. Without them the first
        // Engine.create() dies with UnsatisfiedLinkError (GltfioDecodeTest, finding 1).
        Filament.init()
        Gltfio.init()

        val created = Engine.create()
        engine = created
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
        // F18: the model may have arrived before the engine existed.
        applyPendingModel()
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
     */
    private fun createLights(created: Engine) {
        keyLight = EntityManager.get().create()
        // `Builder` is a nested class, so it is `LightManager.Builder(...)` — not a member of the
        // manager *instance*.
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f)
            .intensity(KEY_LUX)
            .direction(-0.35f, -1.0f, -0.45f)
            .castShadows(false)
            .build(created, keyLight)
        fillLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.85f, 0.9f, 1.0f)
            .intensity(FILL_LUX)
            .direction(0.5f, -0.35f, 0.55f)
            .castShadows(false)
            .build(created, fillLight)
        scene?.addEntity(keyLight)
        scene?.addEntity(fillLight)
    }

    private fun createSwapChain() {
        val created = engine ?: return
        val target = surface ?: return
        destroySwapChain()
        swapChain = runCatching { created.createSwapChain(target) }
            .onFailure { Log.w(TAG, "createSwapChain failed", it) }
            .getOrNull()
    }

    private fun destroySwapChain() {
        swapChain?.let { engine?.destroySwapChain(it) }
        swapChain = null
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    // Frame loop
    // ════════════════════════════════════════════════════════════════════════════════════════

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!frameLoopRunning) return
            renderFrame(frameTimeNanos)
            choreographer.postFrameCallback(this)
        }
    }

    private fun startFrameLoop() {
        if (frameLoopRunning) return
        frameLoopRunning = true
        choreographer.postFrameCallback(frameCallback)
    }

    /**
     * One frame: ARCore first, then Filament.
     *
     * `Session.update()` is here rather than on another thread on purpose (class header): the pose
     * read and the frame drawn from it must be the same [Frame].
     */
    private fun renderFrame(frameTimeNanos: Long) {
        val created = engine ?: return
        val activeRenderer = renderer ?: return
        val activeView = view ?: return
        val chain = swapChain ?: return

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
        }

        if (!activeRenderer.beginFrame(chain, frameTimeNanos)) {
            // Nothing presented (swapchain not ready). Sleeping a millisecond beats spinning a
            // core at vsync when this repeats.
            Thread.sleep(1L)
            return
        }
        activeRenderer.render(activeView)
        activeRenderer.endFrame()
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
        val loader = assetLoader ?: return
        val spec = pendingModel ?: return
        pendingModel = null

        val file = File(spec.path)
        if (!file.isFile) {
            listener.onError("model_parse_failed", "local model missing at ${spec.path}")
            return
        }
        val startedAt = System.currentTimeMillis()
        asset?.let { previous -> runCatching { loader.destroyAsset(previous) } }
        asset = null

        var loaded: FilamentAsset? = null
        var lastFailure: String? = null
        repeat(LOAD_ATTEMPTS) { attempt ->
            created.flushAndWait()
            val bytes = runCatching { file.readBytes() }.getOrElse { t ->
                listener.onError("model_parse_failed", "cannot read ${spec.path}: ${t.message}")
                return
            }
            loaded = runCatching { loader.createAsset(directBuffer(bytes)) }.getOrElse { t ->
                // An undecodable required extension surfaces here. Finding 3's PreconditionPanic
                // (material/mesh mismatch) is a process abort and is *not* catchable — which is
                // why the authoring checklist is a rule and not advice.
                lastFailure = t.message
                null
            }
            if (loaded != null) return@repeat
            lastFailure = lastFailure ?: "loader returned null (unsupported required extension?)"
            Thread.sleep(200L * (attempt + 1))
        }

        val createdAsset = loaded
        if (createdAsset == null) {
            Log.w(TAG, "createAsset failed after $LOAD_ATTEMPTS attempts: $lastFailure")
            listener.onError("model_parse_failed", lastFailure)
            return
        }
        asset = createdAsset
        runCatching { ResourceLoader(created).loadResources(createdAsset) }
            .onFailure { t -> Log.w(TAG, "loadResources failed", t) }
        scene?.addEntities(createdAsset.renderableEntities)
        modelRoot = createdAsset.root
        runCatching { created.transformManager.create(modelRoot) }

        pendingAuthoredLengthMm = spec.authoredLengthMm
        yawOffsetDeg = spec.yawOffsetDeg ?: 0.0
        sizeScale = 1.0f
        placed = false
        Matrix.setIdentityM(placement, 0)
        applyTransform()

        val loadMs = (System.currentTimeMillis() - startedAt).toInt()
        val halfExtent = createdAsset.boundingBox.halfExtent
        Log.i(
            TAG,
            "model ${spec.modelId} loaded in ${loadMs}ms: renderables=" +
                "${createdAsset.renderableEntities.size}, bbox(m)=${halfExtent.joinToString()}, " +
                "authoredLengthMm=${spec.authoredLengthMm}",
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
    }

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

    private fun teardown() {
        frameLoopRunning = false
        asset?.let { loaded -> assetLoader?.let { runCatching { it.destroyAsset(loaded) } } }
        asset = null
        pendingModel = null
        modelRoot = 0
        runCatching { session?.close() }
        session = null
        sessionResumed = false
        destroySwapChain()
        view?.let { engine?.destroyView(it) }
        scene?.let { engine?.destroyScene(it) }
        renderer?.let { engine?.destroyRenderer(it) }
        if (cameraEntity != 0) engine?.destroyCameraComponent(cameraEntity)
        if (keyLight != 0) engine?.destroyEntity(keyLight)
        if (fillLight != 0) engine?.destroyEntity(fillLight)
        assetLoader?.destroy()
        materialProvider?.destroy()
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
    }
}
