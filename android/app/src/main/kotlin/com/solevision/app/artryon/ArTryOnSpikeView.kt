package com.solevision.app.artryon

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import android.view.Choreographer
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import com.google.android.filament.Filament
import com.google.android.filament.gltfio.Gltfio
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import io.flutter.plugin.platform.PlatformView
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.math.Scale
import io.github.sceneview.rememberModelInstance

/**
 * The V0 spike's AR surface: a Flutter PlatformView whose content is a
 * `ComposeView` running SceneView's `ARSceneView` composable.
 *
 * Why Compose inside a View-based app: SceneView 4.x dropped the View-based
 * `ARSceneView` class — it is a Compose SDK now. SceneView's own Flutter bridge
 * uses exactly this shape (PlatformView → ComposeView), so this spike also
 * proves the integration route rather than a detour around it.
 *
 * What it does, deliberately little:
 *  1. starts an ARCore session through ARSceneView (camera feed + plane finding)
 *  2. waits for a horizontal plane, then anchors at its centre — no tap UI yet
 *  3. renders the model handed over by Dart once both exist
 *  4. reports session outcome, model load time and fps to Dart
 *
 * Lifecycle: ARSceneView follows the host activity's `Lifecycle`, so pausing
 * the app pauses the session and the camera. Session teardown happens when the
 * composition is disposed — the "PlatformView disposal owns teardown" rule the
 * shipped foot scan follows too.
 */
class ArTryOnSpikeView(
    context: Context,
    private val activity: Activity,
    private val plugin: ArTryOnSpikePlugin,
) : PlatformView {

    init {
        // Mandatory, and easy to miss: `filament-jni` and `gltfio-jni` are loaded from the
        // static initialisers of the `Filament` / `Gltfio` classes, and **nothing in SceneView
        // or ARSceneView calls them** — those two classes are the only `loadLibrary` sites in
        // the whole Filament + SceneView AAR set. Without this, the first model load dies with
        // `UnsatisfiedLinkError: No implementation found for Engine.nCreateBuilder`. Both calls
        // are idempotent. Found by `GltfioDecodeTest`; see docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md.
        Filament.init()
        Gltfio.init()
    }

    /** True once ARCore reports the session resumed — read by the plugin to
     *  answer a parked `startSession` immediately on re-entry. */
    var sessionResumed = false
        private set

    private var modelLoadStartedAt = 0L
    private var modelLoadedMs = -1L

    // Compose state. All writes happen on the main thread (channel handler,
    // composition callbacks), which is what Compose requires.
    private var modelPath by mutableStateOf<String?>(null)

    // Named `modelScaleFactor`, not `modelScale`: a property named `modelScale`
    // generates a private `setModelScale(F)V` that clashes with the public
    // channel-facing `setModelScale()` below.
    private var modelScaleFactor by mutableStateOf(1f)
    private var phase by mutableStateOf("starting")

    /** The host activity's lifecycle, passed explicitly so ARSceneView does not
     *  depend on finding a ViewTreeLifecycleOwner through the Flutter view tree. */
    private val hostLifecycle = (activity as ComponentActivity).lifecycle

    private val perfProbe = PerfProbe { avgFps, frameMs ->
        plugin.emit("perf", mapOf("avgFps" to avgFps, "frameMs" to frameMs))
    }

    private val composeView = ComposeView(context).apply {
        setContent { SpikeScene() }
    }

    init {
        perfProbe.start()
    }

    override fun getView(): View = composeView

    override fun dispose() {
        perfProbe.stop()
        plugin.clearView(this)
        composeView.disposeComposition()
    }

    // ── Called from the plugin's method channel (main thread) ───────────────

    fun setModel(path: String) {
        modelLoadStartedAt = SystemClock.elapsedRealtime()
        modelLoadedMs = -1L
        modelPath = path
    }

    fun setModelScale(scale: Float) {
        modelScaleFactor = scale
    }

    fun statusMap(): Map<String, Any?> = mapOf(
        "phase" to phase,
        "sessionResumed" to sessionResumed,
        "modelLoadedMs" to modelLoadedMs,
        "modelPath" to modelPath,
    )

    // ── The scene ───────────────────────────────────────────────────────────

    @Composable
    private fun SpikeScene() {
        var anchor by remember { mutableStateOf<Anchor?>(null) }

        ARSceneView(
            modifier = Modifier.fillMaxSize(),
            planeRenderer = true,
            // The spike only needs a floor to stand the shoe on.
            planeFindingMode = Config.PlaneFindingMode.HORIZONTAL,
            lifecycle = hostLifecycle,
            onSessionResumed = {
                sessionResumed = true
                phase = "searching"
                plugin.onSessionResumed()
            },
            onSessionFailed = { exception -> plugin.onSessionFailed(exception) },
            onSessionUpdated = { session, frame ->
                // Anchor on the first tracked horizontal plane. A real try-on
                // replaces this with the foot-pose anchor (architecture §2.4);
                // for V0 it only has to prove that a model can be placed in
                // world space and stay there while the camera moves.
                //
                // Note the API shape: on ARCore 1.54 (the version this app
                // pins) planes come from Session.getAllTrackables() and the
                // anchor from Session.createAnchor() — Frame.getUpdatedPlanes()
                // / Frame.createAnchorOrNull() shown in SceneView's README were
                // dropped from the SDK. See AR_TRY_ON_SPIKE_FINDINGS.md.
                if (anchor == null && frame.camera.trackingState == TrackingState.TRACKING) {
                    val floor = session.getAllTrackables(Plane::class.java).firstOrNull {
                        it.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                            it.trackingState == TrackingState.TRACKING
                    }
                    if (floor != null) {
                        anchor = session.createAnchor(floor.centerPose)
                        phase = "placed"
                        plugin.emit("status", mapOf("phase" to "placed"))
                    }
                }
            },
        ) {
            val path = modelPath
            if (path != null) {
                // rememberModelInstance handles the scheme itself: plain paths
                // are read from the APK's assets, file:// from the filesystem
                // (which is how a downloaded model will arrive), https from the
                // network. Dart-side spike sends a file:// URI on purpose.
                val instance = rememberModelInstance(modelLoader, path)
                val factor = modelScaleFactor
                val currentAnchor = anchor

                LaunchedEffect(instance) {
                    if (instance != null && modelLoadStartedAt > 0L && modelLoadedMs < 0L) {
                        modelLoadedMs = SystemClock.elapsedRealtime() - modelLoadStartedAt
                        plugin.emit(
                            "modelLoaded",
                            mapOf("loadMs" to modelLoadedMs, "source" to path),
                        )
                    }
                }

                if (instance != null && currentAnchor != null) {
                    AnchorNode(anchor = currentAnchor) {
                        // Authored at true scale, so `scale` starts at 1.0 and
                        // is the seam the size chart will drive (architecture
                        // §2.5.2) — exercised from Dart by setModelScale.
                        ModelNode(modelInstance = instance, scale = Scale(factor))
                    }
                }
            }
        }
    }
}

/**
 * Rolling fps / frame-time probe, sampled over the display's vsync through
 * [Choreographer]. It measures what the user experiences (frames presented
 * while the AR view is on screen) rather than Filament's internal draw calls —
 * good enough for the V0 numbers, and it needs no renderer APIs.
 *
 * Samples every 5 s and reports nothing for a window with no frames.
 */
private class PerfProbe(private val onSample: (avgFps: Double, frameMs: Double) -> Unit) :
    Choreographer.FrameCallback {

    private val choreographer = Choreographer.getInstance()
    private var running = false
    private var frames = 0
    private var windowStartNanos = 0L

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        if (windowStartNanos == 0L) windowStartNanos = frameTimeNanos
        frames++
        val elapsed = frameTimeNanos - windowStartNanos
        if (elapsed >= SAMPLE_WINDOW_NANOS) {
            if (frames > 1) {
                onSample(frames * 1e9 / elapsed, elapsed / 1e6 / frames)
            }
            frames = 0
            windowStartNanos = frameTimeNanos
        }
        choreographer.postFrameCallback(this)
    }

    fun start() {
        if (running) return
        running = true
        frames = 0
        windowStartNanos = 0L
        choreographer.postFrameCallback(this)
    }

    fun stop() {
        running = false
        choreographer.removeFrameCallback(this)
    }

    private companion object {
        const val SAMPLE_WINDOW_NANOS = 5_000_000_000L
    }
}
