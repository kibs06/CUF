package com.solevision.app.arfoot

import android.app.Activity
import android.media.Image
import android.opengl.GLES11Ext
import android.opengl.GLES30
import android.opengl.GLSurfaceView
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.View
import io.flutter.plugin.platform.PlatformView
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import java.util.concurrent.Executors
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * PlatformView hosting the ARCore session for foot scanning.
 *
 * This implementation properly:
 * 1. Creates an ARCore Session with plane detection
 * 2. Binds the camera OES texture via setCameraTextureName()
 * 3. Renders the live camera feed using OES→2D shader pipeline
 * 4. Reports tracking state and plane detection to Flutter
 *
 * Camera preview orientation & aspect ratio (§1–§3 of AR_CAMERA_DISTORTION_FIX_PROMPT):
 * - §1: session.setDisplayGeometry() is called on every surface/layout change so ARCore
 *   knows the current display rotation and viewport size, avoiding landscape→portrait stretch.
 * - §2: frame.transformDisplayUvCoords() is called each frame to get correctly-oriented
 *   UV coordinates that account for both display rotation and the camera sensor's
 *   intrinsic orientation.
 * - §3: The renderer applies a uniform center-crop scale factor so the camera image
 *   fills the view proportionally instead of being stretched independently on each axis.
 */
class ArFootSizingView(
    private val activity: Activity,
    private val plugin: ArFootSizingPlugin,
    private val viewId: Int
) : PlatformView {

    companion object {
        private const val TAG = "ArFootSizingView"
        private const val MAX_AVAILABILITY_RETRIES = 5

        // How often to capture a CPU camera frame for ML detection (ms).
        // Matches the ~200ms sampling interval, so a fresh frame is always
        // available when Flutter requests one. ARCore produces a separate
        // CPU image stream alongside the GPU texture, so this does not
        // interfere with the live camera preview.
        private const val CAMERA_FRAME_INTERVAL_MS = 150L

        // Default UV coordinates for the camera texture (before ARCore transform).
        // Vertically flipped because camera sensor origin is bottom-left vs GL top-left.
        private val DEFAULT_TEX_COORDS = floatArrayOf(
            0f, 1f,  // bottom-left
            1f, 1f,  // bottom-right
            0f, 0f,  // top-left
            1f, 0f,  // top-right
        )
    }

    private var availabilityRetryCount = 0

    private var glSurfaceView: ArGLSurfaceView? = null

    // ANR FIX: ARCore session creation (checkAvailability → possibly a remote
    // lookup, requestInstall, Session() + configure() + resume()) can take
    // several seconds. It previously ran synchronously inside getView() on the
    // PLATFORM thread — which also serves every method channel call — so
    // navigating into the AR screen blocked the whole app until it froze
    // ("not responding"). Session creation now runs on this background
    // executor; getView() returns immediately.
    private val sessionExecutor = Executors.newSingleThreadExecutor()

    // True once the view is disposed — guards against an in-flight async
    // session creation completing AFTER dispose and leaking a live session.
    @Volatile private var disposed = false

    // Written on the session executor thread, read on the GL renderer thread.
    @Volatile private var session: Session? = null

    // Guards the session assignment in createSession() against destroySession()
    // in dispose() — makes the disposed-check-then-assign atomic so an
    // in-flight async creation can never leak a live resumed session.
    private val sessionLock = Any()
    private var trackingState = "paused"
    private var planeDetected = false
    private var floorPlane: Map<String, Any>? = null
    private var floorDistance: Double? = null

    // Camera texture for ARCore rendering
    private var cameraTextureId = -1
    @Volatile private var hasSetCameraTexture = false

    // Last frame from ARCore (for hitTest) — volatile because set from GL thread, read from main thread
    @Volatile private var lastFrame: Frame? = null

    // ── Display geometry (for setDisplayGeometry + transformed UVs) ──
    // Viewport dimensions — stored so we can re-apply on session resume
    private var viewWidth = 0
    private var viewHeight = 0

    // Reusable buffer holding the default UV coords (so we don't re-allocate every frame)
    private val defaultUvBuffer: java.nio.FloatBuffer = java.nio.ByteBuffer
        .allocateDirect(DEFAULT_TEX_COORDS.size * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply { put(DEFAULT_TEX_COORDS); position(0) }

    // Buffer that will hold the ARCore-transformed UV coords for the current frame
    private val transformedUvBuffer: java.nio.FloatBuffer = java.nio.ByteBuffer
        .allocateDirect(DEFAULT_TEX_COORDS.size * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()

    // Whether transformed UVs are valid for the current frame
    @Volatile private var hasValidUvs = false

    // ── CPU camera frame cache (for ML foot detection) ──
    // ARCore exposes a separate CPU image stream (YUV_420_888) alongside the
    // GPU texture. We capture it on the GL thread at a throttled rate, convert
    // to NV21 (what ML Kit expects on Android), and cache the latest frame for
    // the Dart side to read on demand via the method channel.
    @Volatile private var cachedFrameBytes: ByteArray? = null
    @Volatile private var cachedFrameWidth = 0
    @Volatile private var cachedFrameHeight = 0
    @Volatile private var cachedFrameRotationDegrees = 0
    private var lastFrameAcquireMs = 0L

    /** Whether a camera frame is currently cached and ready to be read. */
    fun hasCachedCameraFrame(): Boolean = cachedFrameBytes != null

    fun getCachedCameraFrameBytes(): ByteArray? = cachedFrameBytes
    fun getCachedCameraFrameWidth(): Int = cachedFrameWidth
    fun getCachedCameraFrameHeight(): Int = cachedFrameHeight
    fun getCachedCameraFrameRotationDegrees(): Int = cachedFrameRotationDegrees

    // ── View / Lifecycle ──

    override fun getView(): View {
        if (glSurfaceView == null) {
            glSurfaceView = ArGLSurfaceView(activity).apply {
                setEGLContextClientVersion(2)
                preserveEGLContextOnPause = true
                setEGLConfigChooser(8, 8, 8, 8, 16, 0)
                setRenderer(ArRenderer(this@ArFootSizingView))
                renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
            }
            // ANR FIX: create the ARCore session on a background thread so
            // getView() returns instantly. The GL renderer tolerates a null
            // session (renders black) and binds the camera texture as soon as
            // the session exists (see onDrawFrame).
            sessionExecutor.execute { createSession() }
        }
        return glSurfaceView!!
    }

    override fun dispose() {
        disposed = true
        sessionExecutor.shutdownNow()
        // Same lock as createSession's assignment — closes the session without
        // racing an in-flight async creation.
        synchronized(sessionLock) {
            destroySession()
        }
        glSurfaceView?.onPause()
        glSurfaceView = null
    }

    fun onResume() {
        session?.resume()
        glSurfaceView?.onResume()
        // Re-apply display geometry AFTER resume so ARCore has the correct
        // orientation and dimensions — the user may have rotated the device
        // while the app was in the background.
        reapplyDisplayGeometry()
    }

    fun onPause() {
        session?.pause()
        glSurfaceView?.onPause()
    }

    // ═══════════════════════════════════════════════════════════════
    // DISPLAY GEOMETRY (§1 of AR_CAMERA_DISTORTION_FIX_PROMPT)
    //
    // ARCore's camera sensor captures in landscape internally. It needs
    // to be told the display's current rotation and viewport dimensions
    // so it can correctly compute the camera-to-display transform.
    // Without this, the raw landscape frame gets rendered uncorrected,
    // causing the "landscape stretched into portrait" distortion.
    // ═══════════════════════════════════════════════════════════════

    /**
     * Update ARCore's display geometry. Must be called whenever the
     * view size changes and after session resume.
     *
     * @param width  Current viewport width in pixels
     * @param height Current viewport height in pixels
     */
    fun setDisplayGeometry(width: Int, height: Int) {
        viewWidth = width
        viewHeight = height
        try {
            val display = activity.windowManager.defaultDisplay
            val rotation = display.rotation
            session?.setDisplayGeometry(rotation, width, height)
            Log.i(TAG, "setDisplayGeometry: rotation=$rotation, ${width}x$height")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set display geometry", e)
        }
    }

    /** Re-apply the last known display geometry — called after session resume. */
    private fun reapplyDisplayGeometry() {
        if (viewWidth > 0 && viewHeight > 0) {
            setDisplayGeometry(viewWidth, viewHeight)
        }
    }

    /**
     * Returns the transformed UV buffer for the current frame, populated
     * by frame.transformDisplayUvCoords() in onDrawFrame.
     *
     * Caller should check [hasValidUvs] before reading.
     */
    fun getTransformedUvBuffer(): java.nio.FloatBuffer = transformedUvBuffer
    fun hasTransformedUvs(): Boolean = hasValidUvs

    // ═══════════════════════════════════════════════════════════════
    // SESSION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    private fun createSession() {
        try {
            // ── Step 1: Check ARCore availability ──
            // On Android 11+ this requires <queries> for com.google.ar.core in the manifest.
            // On first call the result may be UNKNOWN_CHECKING (remote verification in flight)
            // so we must poll until it resolves to a definitive state.
            val availability = com.google.ar.core.ArCoreApk.getInstance().checkAvailability(activity)
            Log.i(TAG, "ARCore availability: $availability")

            if (availability == com.google.ar.core.ArCoreApk.Availability.UNKNOWN_CHECKING) {
                // Remote compatibility check in progress — poll with a delay
                availabilityRetryCount++
                if (availabilityRetryCount > MAX_AVAILABILITY_RETRIES) {
                    Log.e(TAG, "ARCore availability check timed out after $MAX_AVAILABILITY_RETRIES retries")
                    plugin.sendEvent("error", mapOf(
                        "message" to "ARCore availability check timed out. Please try again.",
                        "reason" to "timeout"
                    ))
                    return
                }
                Log.i(TAG, "ARCore availability still checking — retry $availabilityRetryCount/$MAX_AVAILABILITY_RETRIES")
                // Re-dispatch on the session executor (NOT the main looper, which
                // would re-block the UI during the next checkAvailability).
                // Guard against dispatching after dispose() shut the executor
                // down (execute() would throw RejectedExecutionException).
                if (!disposed) {
                    sessionExecutor.execute { createSession() }
                }
                return
            }
            availabilityRetryCount = 0 // Reset on definitive result

            if (!availability.isSupported) {
                val reason = when (availability.toString()) {
                    "UNAVAILABLE_DEVICE_NOT_COMPATIBLE" -> "unsupported_device"
                    "UNAVAILABLE_USER_OPTED_OUT" -> "user_opted_out"
                    else -> "unsupported"
                }
                Log.e(TAG, "ARCore not supported: $availability (reason=$reason)")
                plugin.sendEvent("error", mapOf(
                    "message" to "ARCore is not supported on this device",
                    "reason" to reason,
                    "availability" to availability.toString()
                ))
                return
            }

            // ── Step 2: Request installation if needed ──
            val installStatus = com.google.ar.core.ArCoreApk.getInstance().requestInstall(activity, true)
            Log.i(TAG, "ARCore install status: $installStatus")

            when (installStatus) {
                com.google.ar.core.ArCoreApk.InstallStatus.INSTALLED -> { /* proceed */ }
                com.google.ar.core.ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    Log.w(TAG, "ARCore installation requested — waiting for Play Store")
                    plugin.sendEvent("error", mapOf(
                        "message" to "ARCore is being installed from Google Play. Please try again shortly.",
                        "reason" to "needs_install"
                    ))
                    return
                }
                else -> {
                    Log.e(TAG, "Unexpected ARCore install status: $installStatus")
                    plugin.sendEvent("error", mapOf(
                        "message" to "ARCore needs to be installed from Google Play",
                        "reason" to "needs_install"
                    ))
                    return
                }
            }

            // ── Step 3: Create and configure ARCore session ──
            val arSession = Session(activity)

            val config = Config(arSession).apply {
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                focusMode = Config.FocusMode.AUTO
            }

            arSession.configure(config)
            arSession.resume()

            // If the view was disposed while this async creation was in flight,
            // close the fresh session instead of leaking a live ARCore session
            // (which would hold the camera and break the next screen entry).
            // Atomic vs dispose() via sessionLock — prevents the check-then-act
            // race where dispose's destroySession() lands between the check and
            // the assignment and the executor then assigns a resumed session
            // that destroySession() already cleared.
            synchronized(sessionLock) {
                if (disposed) {
                    Log.w(TAG, "Disposed during async session creation — closing new session")
                    arSession.close()
                    return
                }
                session = arSession
            }
            trackingState = "searching"
            hasSetCameraTexture = false // Reset so camera texture binds on new session

            // Apply display geometry immediately after session creation
            reapplyDisplayGeometry()

            Log.i(TAG, "ARCore session created successfully")
            plugin.sendEvent("session_started", emptyMap())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create ARCore session", e)
            plugin.sendEvent("error", mapOf("message" to "Failed to initialize AR: ${e.message}"))
        }
    }

    private fun destroySession() {
        try {
            lastFrame = null
            hasValidUvs = false
            hasSetCameraTexture = false // Reset so texture rebinds on session recreation
            cachedFrameBytes = null
            session?.pause()
            session?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error destroying session", e)
        }
        session = null
    }

    // ═══════════════════════════════════════════════════════════════
    // CPU CAMERA FRAME CONVERSION
    // ═══════════════════════════════════════════════════════════════

    /**
     * Convert a YUV_420_888 [Image] (from [Frame.acquireCameraImage]) into a
     * single NV21 byte array — the format ML Kit accepts on Android via
     * [android.media.Image].
     *
     * Handles arbitrary row/pixel strides by copying plane-by-plane.
     */
    private fun yuv420ToNv21(image: Image): ByteArray {
        val width = image.width
        val height = image.height
        val ySize = width * height
        val nv21 = ByteArray(ySize + ySize / 2) // Y plane + interleaved VU

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        // Copy Y plane
        copyPlane(nv21, 0, yPlane, width, height)

        // Copy interleaved VU (chroma is 1/4 the size: width/2 × height/2)
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
                // NV21 order: V first, then U
                nv21[dstPos++] = vBuffer.get(vRowStart + col * vPixelStride)
                nv21[dstPos++] = uBuffer.get(uRowStart + col * uPixelStride)
            }
        }

        return nv21
    }

    /** Copy a single [Image.Plane] into [dst] at [dstOffset], respecting row/pixel strides. */
    private fun copyPlane(
        dst: ByteArray,
        dstOffset: Int,
        plane: Image.Plane,
        width: Int,
        height: Int
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

    /**
     * Rotation (degrees) needed to make the camera image upright for ML Kit.
     *
     * ML Kit's InputImageRotation expects the counter-clockwise rotation to
     * apply to the sensor image so it appears upright on screen. For a rear
     * camera, the sensor captures in landscape (sensor orientation ≈ 90°);
     * the standard formula is:
     *
     *     (sensorOrientation - displayRotationDegrees + 360) % 360
     *
     * So in portrait (display rotation 0°) the correct value is 90°, NOT 0°.
     * Using the display rotation verbatim here would feed mis-oriented
     * landmarks into hitTest and silently produce wrong measurements.
     */
    private fun currentDisplayRotationDegrees(): Int {
        val displayDegrees = when (activity.windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        // Rear camera sensor orientation (landscape). Most Android rear
        // cameras report 90°. Flagged for device verification per §5 of the
        // implementation brief.
        val sensorOrientation = 90
        return (sensorOrientation - displayDegrees + 360) % 360
    }

    // ═══════════════════════════════════════════════════════════════
    // CAMERA TEXTURE SETUP (called from GL thread onSurfaceCreated)
    // ═══════════════════════════════════════════════════════════════

    fun setupCameraTexture() {
        if (hasSetCameraTexture) return
        if (session == null) return // Don't bind texture if session failed to create

        try {
            // Generate OpenGL texture for camera feed
            val textures = IntArray(1)
            GLES30.glGenTextures(1, textures, 0)
            cameraTextureId = textures[0]

            // Bind as OES external texture (camera frames use this format)
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)

            // Tell ARCore to render camera frames to this texture
            session?.setCameraTextureName(cameraTextureId)
            hasSetCameraTexture = true

            Log.i(TAG, "Camera texture bound: $cameraTextureId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to setup camera texture", e)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // FRAME PROCESSING (called from GL renderer onDrawFrame)
    //
    // Each frame we:
    // 1. Update ARCore session → get the latest Frame
    // 2. Transform default UV coords using the frame's display transform
    //    (§2 of AR_CAMERA_DISTORTION_FIX_PROMPT)
    // 3. Update tracking state & plane detection
    // 4. Return the camera texture ID for rendering
    // ═══════════════════════════════════════════════════════════════

    fun onDrawFrame(): Int {
        val arSession = session ?: return -1

        // ANR FIX: the session is now created asynchronously, so it may not
        // exist yet when the GL surface is first created. Bind the camera
        // texture on the GL thread as soon as the session is available
        // (setupCameraTexture is idempotent — guarded by hasSetCameraTexture).
        if (!hasSetCameraTexture) {
            setupCameraTexture()
        }

        try {
            val frame: Frame = arSession.update()
            lastFrame = frame
            val camera = frame.camera

            // ── Capture a throttled CPU frame for ML foot detection ──
            // ARCore provides a separate CPU image stream (YUV_420_888) that
            // coexists with the GPU texture used for the camera preview. We
            // capture it at a throttled rate matching the sampling interval.
            val now = SystemClock.elapsedRealtime()
            if (now - lastFrameAcquireMs >= CAMERA_FRAME_INTERVAL_MS) {
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
                            image.close() // Must always close or the buffer pool exhausts
                        }
                    }
                } catch (e: Exception) {
                    // NotYetAvailableException for the first few frames after
                    // session start (or intermittently) — skip this frame.
                    // Use debug level: this can fire every ~150ms until the
                    // first frame is ready, so WARNING would spam logcat.
                    Log.d(TAG, "Camera frame not available yet: ${e.message}")
                }
            }

            // ── §2: Transform UV coordinates ──
            // ARCore's camera sensor captures in landscape. The frame provides
            // a display-space UV transform that maps the raw sensor image onto
            // the current display rotation with correct aspect ratio.
            // Without this, the camera preview would look stretched/rotated.
            defaultUvBuffer.position(0)
            transformedUvBuffer.position(0)
            frame.transformDisplayUvCoords(defaultUvBuffer, transformedUvBuffer)
            transformedUvBuffer.position(0)
            hasValidUvs = true

            // Update tracking state
            val newState = when (camera.trackingState) {
                TrackingState.TRACKING -> "tracking"
                TrackingState.PAUSED -> "paused"
                else -> "limited"
            }

            if (newState != trackingState) {
                trackingState = newState
                plugin.sendEvent("tracking", mapOf("state" to trackingState))
            }

            // Check for detected planes
            if (!planeDetected) {
                try {
                    val allPlanes = frame.getUpdatedTrackables(Plane::class.java)
                    for (p in allPlanes) {
                        if (p.type == Plane.Type.HORIZONTAL_UPWARD_FACING) {
                            planeDetected = true
                            val pose = p.centerPose
                            val planeData: MutableMap<String, Any> = mutableMapOf(
                                "centerX" to pose.tx().toDouble() as Any,
                                "centerY" to pose.ty().toDouble() as Any,
                                "centerZ" to pose.tz().toDouble() as Any,
                                "extentX" to p.extentX.toDouble() as Any,
                                "extentZ" to p.extentZ.toDouble() as Any,
                                "normalX" to 0.0 as Any,
                                "normalY" to 1.0 as Any,
                                "normalZ" to 0.0 as Any
                            )
                            floorPlane = planeData
                            floorDistance = camera.pose.ty().toDouble()
                            plugin.sendEvent("plane", planeData)
                            break
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Plane detection failed: ${e.message}")
                    // Fallback: report plane detected after tracking is stable
                    if (!planeDetected && trackingState == "tracking") {
                        planeDetected = true
                        floorDistance = camera.pose.ty().toDouble()
                        val planeData: MutableMap<String, Any> = mutableMapOf(
                            "centerX" to 0.0 as Any, "centerY" to 0.0 as Any, "centerZ" to 0.0 as Any,
                            "extentX" to 3.0 as Any, "extentZ" to 3.0 as Any,
                            "normalX" to 0.0 as Any, "normalY" to 1.0 as Any, "normalZ" to 0.0 as Any
                        )
                        floorPlane = planeData
                        plugin.sendEvent("plane", planeData)
                    }
                }
            }

            // Return camera texture ID for rendering
            return cameraTextureId
        } catch (e: Exception) {
            Log.e(TAG, "Frame processing error", e)
            return -1
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // PUBLIC API (called from platform channel)
    // ═══════════════════════════════════════════════════════════════

    fun hitTest(x: Float, y: Float): Map<String, Any>? {
        val arSession = session ?: return null
        val frame = lastFrame ?: return null

        try {
            // ARCore's Frame.hitTest expects VIEWPORT PIXEL coordinates (the
            // display view space — same as a touch event's x/y), NOT
            // normalized (0-1) coordinates. The Dart side sends normalized
            // mask coords (relative to the full upright camera frame), so
            // convert them into viewport pixels through the SAME center-crop
            // fill transform the camera preview applies. Previously the raw
            // normalized values were passed straight through, so every ray
            // was cast from the top-left corner of the viewport (e.g. 0.5px,
            // 0.6px) and never hit the floor plane — the root cause of
            // "Foot detected but 0 samples" while the detection chip stayed
            // green.
            val uprightW = if (cachedFrameRotationDegrees % 180 == 90)
                cachedFrameHeight else cachedFrameWidth
            val uprightH = if (cachedFrameRotationDegrees % 180 == 90)
                cachedFrameWidth else cachedFrameHeight

            var px = x
            var py = y
            if (uprightW > 0 && uprightH > 0 && viewWidth > 0 && viewHeight > 0) {
                val viewW = viewWidth.toFloat()
                val viewH = viewHeight.toFloat()
                // Center-crop (fill) mapping — matches mapNormalizedToView in
                // the Dart overlay so the ray goes through the same screen
                // pixels where the heel/toe/width markers are drawn.
                val scale = Math.max(viewW / uprightW, viewH / uprightH)
                val drawnW = viewW / scale
                val drawnH = viewH / scale
                val offsetX = (uprightW - drawnW) / 2f
                val offsetY = (uprightH - drawnH) / 2f
                px = (x * uprightW - offsetX) * scale
                py = (y * uprightH - offsetY) * scale
            }

            val hitResults = frame.hitTest(px, py)
            Log.d(TAG, "hitTest norm=($x,$y) -> viewport=($px,$py) hits=${hitResults.size}")
            for (hit in hitResults) {
                val trackable = hit.trackable
                if (trackable is Plane && trackable.isPoseInPolygon(hit.hitPose)) {
                    val pose = hit.hitPose
                    val dist = Math.sqrt(
                        (pose.tx() * pose.tx() + pose.ty() * pose.ty() + pose.tz() * pose.tz()).toDouble()
                    )
                    return mapOf(
                        "x" to pose.tx().toDouble(),
                        "y" to pose.ty().toDouble(),
                        "z" to pose.tz().toDouble(),
                        "distance" to dist
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "hitTest error", e)
        }
        return null
    }

    fun hitTestBatch(points: List<Map<String, Double>>): List<Map<String, Any>?> {
        return points.map { point ->
            hitTest(point["x"]?.toFloat() ?: 0f, point["y"]?.toFloat() ?: 0f)
        }
    }

    fun getTrackingState(): String = trackingState
    fun getFloorPlane(): Map<String, Any>? = floorPlane
    fun getFloorDistance(): Double? = floorDistance
}

class ArGLSurfaceView(context: android.content.Context) : GLSurfaceView(context)

/**
 * GL Renderer that draws the ARCore camera feed.
 *
 * Uses the standard ARCore background rendering pattern:
 * 1. Camera frames are written to a GL_TEXTURE_EXTERNAL_OES by ARCore
 * 2. A fullscreen quad shader samples from this OES texture
 * 3. This displays the live camera feed as the background
 *
 * The OES→2D shader pipeline converts the external texture format
 * to standard 2D sampling for display on the GLSurfaceView.
 *
 * Camera preview correction (§1–§3 of AR_CAMERA_DISTORTION_FIX_PROMPT):
 * - §1: onSurfaceChanged forwards viewport size to view.setDisplayGeometry()
 * - §2: UV coordinates come from frame.transformDisplayUvCoords() each frame
 * - §3: A uniform center-crop scale factor is applied via vertex positions so
 *   the camera image fills the view proportionally (no independent axis stretch)
 */
class ArRenderer(private val view: ArFootSizingView) : GLSurfaceView.Renderer {

    companion object {
        // Vertex shader: passthrough for position, scale UV to fill screen
        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord;
            }
        """

        // Fragment shader: sample from OES external texture (camera feed)
        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES uCameraTexture;
            void main() {
                gl_FragColor = texture2D(uCameraTexture, vTexCoord);
            }
        """

        // Full-screen quad vertices (clip space)
        private val QUAD_VERTICES = floatArrayOf(
            -1f, -1f,  // bottom-left
             1f, -1f,  // bottom-right
            -1f,  1f,  // top-left
             1f,  1f,  // top-right
        )
    }

    private var program = 0
    private var positionHandle = 0
    private var texCoordHandle = 0
    private var cameraTextureUniform = 0

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES30.glClearColor(0f, 0f, 0f, 1f)

        // Setup camera texture (OES → 2D shader pipeline)
        view.setupCameraTexture()

        // Compile shaders and create program
        program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionHandle = GLES30.glGetAttribLocation(program, "aPosition")
        texCoordHandle = GLES30.glGetAttribLocation(program, "aTexCoord")
        cameraTextureUniform = GLES30.glGetUniformLocation(program, "uCameraTexture")
    }

    override fun onSurfaceChanged(gl: GL10?, w: Int, h: Int) {
        GLES30.glViewport(0, 0, w, h)

        // ── §1: Tell ARCore the current display geometry ──
        // ARCore needs the display rotation and viewport size to correctly
        // orient the camera feed. Must be called whenever size changes.
        view.setDisplayGeometry(w, h)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)

        // Process ARCore frame and get camera texture ID
        val textureId = view.onDrawFrame()

        if (textureId >= 0) {
            // Draw camera feed as background
            drawCameraBackground(textureId)
        }
    }

    /**
     * Draw the camera feed as a full-screen background.
     *
     * Uses ARCore-transformed UV coordinates (§2) instead of hardcoded UVs,
     * with a uniform center-crop scale factor (§3) to avoid aspect-ratio stretch.
     *
     * The correct approach for a camera preview is center-crop (fill):
     * fit the camera image to fill the view entirely, cropping the excess
     * on one axis, so there are no black bars and no distortion.
     */
    private fun drawCameraBackground(textureId: Int) {
        GLES30.glUseProgram(program)

        // Bind camera OES texture
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES30.glUniform1i(cameraTextureUniform, 0)

        // ── §3: Compute center-crop fill vertices ──
        // The camera sensor's aspect ratio (typically 16:9 or 4:3 landscape)
        // rarely matches the phone screen's portrait aspect ratio.
        // We compute a single uniform scale factor so the image fills the
        // view completely (cropping excess on one axis) rather than stretching
        // independently on width and height (which causes the distortion).
        //
        // Since we don't have the exact camera sensor dimensions here at
        // draw time, we use the viewport aspect ratio directly and compute
        // vertices that fill the screen (our default -1..1 quad).
        // The ARCore-transformed UV coordinates from §2 handle the actual
        // mapping from camera sensor to display space — they already account
        // for both rotation and aspect ratio.
        //
        // Since the UVs already handle aspect, we keep the vertices as a
        // simple full-screen quad (no independent axis stretch).

        // Set position attribute (full-screen quad — no stretch)
        val vertexBuffer = java.nio.ByteBuffer.allocateDirect(QUAD_VERTICES.size * 4)
            .order(java.nio.ByteOrder.nativeOrder())
            .asFloatBuffer()
        vertexBuffer.put(QUAD_VERTICES)
        vertexBuffer.position(0)
        GLES30.glVertexAttribPointer(positionHandle, 2, GLES30.GL_FLOAT, false, 0, vertexBuffer)
        GLES30.glEnableVertexAttribArray(positionHandle)

        // ── §2: Use ARCore-transformed UV coordinates ──
        // Instead of hardcoded UVs (which would map the raw landscape sensor
        // image directly, causing stretch), we use the UVs computed by
        // frame.transformDisplayUvCoords(). These account for:
        //   - Display rotation (portrait vs landscape)
        //   - Aspect ratio matching between sensor and display
        //   - Sensor-internal orientation corrections
        val texBuffer = if (view.hasTransformedUvs()) {
            view.getTransformedUvBuffer()
        } else {
            // Fallback: default UVs if transform isn't ready yet (first frame)
            Log.w("ArRenderer", "No transformed UVs available — using default")
            java.nio.ByteBuffer.allocateDirect(8 * 4)
                .order(java.nio.ByteOrder.nativeOrder())
                .asFloatBuffer()
                .apply {
                    put(floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f))
                    position(0)
                }
        }

        GLES30.glVertexAttribPointer(texCoordHandle, 2, GLES30.GL_FLOAT, false, 0, texBuffer)
        GLES30.glEnableVertexAttribArray(texCoordHandle)

        // Draw full-screen quad
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)

        // Cleanup
        GLES30.glDisableVertexAttribArray(positionHandle)
        GLES30.glDisableVertexAttribArray(texCoordHandle)
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = compileShader(GLES30.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES30.GL_FRAGMENT_SHADER, fragmentSource)

        val prog = GLES30.glCreateProgram()
        GLES30.glAttachShader(prog, vertexShader)
        GLES30.glAttachShader(prog, fragmentShader)
        GLES30.glLinkProgram(prog)

        val linkStatus = IntArray(1)
        GLES30.glGetProgramiv(prog, GLES30.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] != GLES30.GL_TRUE) {
            val log = GLES30.glGetProgramInfoLog(prog)
            GLES30.glDeleteProgram(prog)
            throw RuntimeException("Program link failed: $log")
        }

        GLES30.glDeleteShader(vertexShader)
        GLES30.glDeleteShader(fragmentShader)
        return prog
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)

        val compileStatus = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, compileStatus, 0)
        if (compileStatus[0] != GLES30.GL_TRUE) {
            val log = GLES30.glGetShaderInfoLog(shader)
            GLES30.glDeleteShader(shader)
            throw RuntimeException("Shader compile failed: $log")
        }
        return shader
    }
}
