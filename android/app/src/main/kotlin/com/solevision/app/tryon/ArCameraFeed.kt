package com.solevision.app.tryon

import android.content.Context
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES30
import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndexBuffer
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.VertexBuffer
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.Session
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * **The AR camera feed: ARCore's frames, drawn by Filament — finding F20's repair.**
 *
 * ## Why this file exists at all
 *
 * V0.7 measured the Filament-direct route as the one that fits the size budget (findings §5.5) and
 * V3.2 was written against it. What that route gave up was SceneView's packaged assets, and the
 * consequence was recorded rather than papered over: `filament-android`, `gltfio-android` and
 * `filament-utils-android` ship **zero** assets (F20), so there is no material that samples
 * ARCore's camera texture and nothing that can draw the room. The AR screen therefore came up with
 * a live ARCore session — tracking, placement and the shoe all working — over a **flat clear
 * colour**, which on a phone reads as *the camera is black*. It was not a broken session; it was a
 * session with nothing drawing the feed.
 *
 * This class is the three things SceneView used to supply, written here and measured on hardware:
 *
 *  1. an **OES texture** ARCore writes camera frames into (`Session.setCameraTextureName`);
 *  2. a **shared EGL context**, so that texture id is valid inside Filament's own GL context;
 *  3. a **full-screen quad** with the vendored `camera_stream_flat.filamat`, whose UVs are the
 *     *view-normalized* corners transformed per frame by `Frame.transformCoordinates2d`.
 *
 * ## The recipe, and where each step comes from
 *
 * Every line below is taken from a working implementation rather than from documentation, because
 * the failure mode of getting one of them wrong is a black screen with no error:
 *
 * | Step | Source |
 * | --- | --- |
 * | gen OES texture, `setCameraTextureName` | the app's own shipped foot scan (`ArFootSizingView`) |
 * | shared EGL context + `importTexture` | SceneView 4.34.0 `utils/OpenGL` + `ARCameraStream` (disassembled) |
 * | quad corners, UVs, draw order, priority | SceneView 4.34.0 `ARCameraStream` (disassembled) |
 * | `uvTransform` / `cameraTexture` parameter names | the vendored `.filamat`'s own reflection blob |
 *
 * The material is the one piece we cannot compile ourselves yet: a `.filamat` is version-locked to
 * the `matc` that produced it, so the vendored file is **checked against the live engine** in
 * [attach] before it is trusted, and a mismatch is reported as a reason instead of drawing nothing.
 * Compiling our own with `matc` in CI is the documented follow-up (F20).
 *
 * ## Threading
 *
 * Everything here is render-thread state: [attach] is called from `createEngineIfNeeded`, [update]
 * from the frame loop, [destroy] from `teardown`, all on the same `HandlerThread` the rest of the
 * view lives on. Nothing is synchronised because nothing is shared.
 */
internal class ArCameraFeed(private val context: Context) {

    /** The GL context ARCore's texture was created in; shared with Filament's engine. */
    private var eglContext: EGLContext? = null
    private var eglDisplay: EGLDisplay? = null
    private var eglSurface: EGLSurface? = null

    /** The OES texture ARCore writes into. Created by us, sampled by Filament. */
    private var cameraTextureId = 0

    /**
     * The OES texture ARCore writes camera frames into.
     *
     * Read-only outside this class, and read by exactly one thing: **V4.4's mask overlay**, which
     * samples the camera through this object rather than importing a second texture for the same
     * GL name — an imported `Texture` is only meaningful inside the EGL context that created it,
     * and that context is this feed's. Null until [attach] has built it; invalid after [destroy],
     * which is why `ArTryOnView` destroys the overlay before it destroys this feed.
     */
    var cameraTexture: Texture? = null
        private set
    private var material: Material? = null
    private var materialInstance: MaterialInstance? = null
    private var vertexBuffer: VertexBuffer? = null
    private var indexBuffer: IndexBuffer? = null
    private var entity = 0

    /** The quad's UVs in `VIEW_NORMALIZED` space — ARCore rewrites these each frame. */
    private var viewUvs: FloatBuffer? = null
    private var transformedUvs: FloatBuffer? = null

    private var ready = false

    /**
     * **Why the feed could not be built, or null when it was.** Carried into the view's diagnostic
     * line rather than only logged: the phone this feature is developed against has no readable
     * logcat, so a reason that never reaches the screen cannot be acted on.
     */
    var failureReason: String? = null
        private set

    val isReady: Boolean get() = ready

    /** The context Filament's engine must be built with, or null if the feed could not start. */
    fun prepareSharedContext(): EGLContext? {
        if (eglContext != null) return eglContext
        return try {
            val context = createEglContext(null)
            eglContext = context
            context
        } catch (t: Throwable) {
            failureReason = "egl_context_failed: ${t.message}"
            Log.w(TAG, "camera feed: could not create the shared EGL context", t)
            null
        }
    }

    /**
     * Builds the quad and its material against a live engine.
     *
     * Must run **after** `Engine.create(sharedContext)` — the imported texture is only meaningful
     * inside that context.
     */
    fun attach(engine: Engine, scene: com.google.android.filament.Scene) {
        if (ready) return
        val shared = eglContext
        if (shared == null) {
            failureReason = "egl_context_missing"
            return
        }
        try {
            makeCurrent(shared)

            // ── 1. The OES texture ARCore writes into ────────────────────────────────────────
            val ids = IntArray(1)
            GLES30.glGenTextures(1, ids, 0)
            cameraTextureId = ids[0]
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
            GLES30.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES30.GL_TEXTURE_MIN_FILTER,
                GLES30.GL_LINEAR,
            )
            GLES30.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES30.GL_TEXTURE_MAG_FILTER,
                GLES30.GL_LINEAR,
            )
            GLES30.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES30.GL_TEXTURE_WRAP_S,
                GLES30.GL_CLAMP_TO_EDGE,
            )
            GLES30.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES30.GL_TEXTURE_WRAP_T,
                GLES30.GL_CLAMP_TO_EDGE,
            )

            // ── 2. Hand it to Filament as an imported external texture ──────────────────────
            // `importTexture` (rather than `setExternalImage`) is the route that works with an
            // *OES* texture: `setExternalImage(Object)` accepts only an AHardwareBuffer.
            cameraTexture = Texture.Builder()
                .sampler(Texture.Sampler.SAMPLER_EXTERNAL)
                .format(Texture.InternalFormat.RGB16F)
                .importTexture(cameraTextureId.toLong())
                .build(engine)

            // ── 3. The vendored material, verified against this engine ──────────────────────
            val bytes = readAsset(ASSET_PATH)
            if (bytes == null) {
                failureReason = "material_missing: $ASSET_PATH"
                return
            }
            val built = Material.Builder()
                .payload(ByteBuffer.wrap(bytes), bytes.size)
                .build(engine)
            // ⚠️ **Verified against the engine rather than trusted.** A `.filamat` is
            // version-locked to the `matc` that produced it, so a Filament upgrade can turn this
            // file into a material that binds nothing — and the failure mode is a silently black
            // backdrop, not an error. Checking the two parameters this code sets and the two
            // attributes the quad provides is what turns that into a reason on screen.
            val required = built.requiredAttributes
            if (!built.hasParameter("cameraTexture") ||
                !built.hasParameter("uvTransform") ||
                !required.contains(VertexBuffer.VertexAttribute.POSITION) ||
                !required.contains(VertexBuffer.VertexAttribute.UV0)
            ) {
                failureReason =
                    "material_mismatch: $ASSET_PATH wants " +
                        "params=${built.hasParameter("cameraTexture")}/" +
                        "${built.hasParameter("uvTransform")} " +
                        "attrs=$required (not built for Filament 1.72.1)"
                engine.destroyMaterial(built)
                return
            }
            material = built
            // An instance we own, rather than the material's default one: teardown then has an
            // unambiguous destroy order, which is the mistake that cost a native abort here before
            // (`destroyMaterials` panicking over live instances — see [ArTryOnView.teardown]).
            val instance = built.createInstance()
            // `MaterialInstance.setParameter(String, FloatArray, int, int)` is the only matrix
            // setter Filament exposes from Java; the column-major `float[16]` is passed as four
            // `FLOAT4` columns (SceneView's `setParameter(…, Mat4)` does exactly this).
            instance.setParameter(
                "uvTransform",
                MaterialInstance.FloatElement.FLOAT4,
                UV_TRANSFORM,
                0,
                UV_TRANSFORM.size / 4,
            )
            instance.setParameter("cameraTexture", cameraTexture!!, EXTERNAL_SAMPLER)
            materialInstance = instance

            // ── 4. The quad ─────────────────────────────────────────────────────────────────
            // NDC corners in TRIANGLE_STRIP order, and UVs that are the *view-normalized*
            // coordinates of those same corners. ARCore rewrites the UVs every time the display
            // geometry changes, which is how a 16:9 sensor image is centre-cropped into a portrait
            // viewport without a shader-side scale of our own.
            val vertices = VertexBuffer.Builder()
                .vertexCount(4)
                .bufferCount(2)
                .attribute(
                    VertexBuffer.VertexAttribute.POSITION,
                    0,
                    VertexBuffer.AttributeType.FLOAT3,
                    0,
                    VERTEX_STRIDE,
                )
                .attribute(
                    VertexBuffer.VertexAttribute.UV0,
                    1,
                    VertexBuffer.AttributeType.FLOAT2,
                    0,
                    UV_STRIDE,
                )
                .build(engine)
            vertices.setBufferAt(engine, 0, FloatBuffer.wrap(CAMERA_VERTICES))
            // ⚠️ A **direct** buffer, not `FloatBuffer.wrap`: the wrapped one is heap-backed, and
            // `VertexBuffer.setBufferAt` reads it from native code after this method has returned.
            // A direct buffer is the only one whose contents are guaranteed to still be where the
            // native side left them.
            val uvBytes = ByteBuffer.allocateDirect(CAMERA_UVS.size * Float.SIZE_BYTES)
                .order(ByteOrder.nativeOrder())
            uvBytes.asFloatBuffer().put(CAMERA_UVS)
            uvBytes.rewind()
            vertices.setBufferAt(engine, 1, uvBytes)
            viewUvs = uvBytes.asFloatBuffer()
            vertexBuffer = vertices

            val indices = IndexBuffer.Builder()
                .indexCount(4)
                .bufferType(IndexBuffer.Builder.IndexType.USHORT)
                .build(engine)
            val indexBytes = ByteBuffer.allocateDirect(INDICES.size * Short.SIZE_BYTES)
                .order(ByteOrder.nativeOrder())
            indexBytes.asShortBuffer().put(INDICES)
            indexBytes.rewind()
            indices.setBuffer(engine, indexBytes)
            indexBuffer = indices

            entity = EntityManager.get().create()
            RenderableManager.Builder(1)
                // The feed is a backdrop: no shadows, never culled (it is a full-screen quad and
                // its bounds are not a mesh box), and drawn *before* the shoe.
                .castShadows(false)
                .receiveShadows(false)
                .culling(false)
                // ⚠️ `priority(7)` is SceneView's own value, and it is what puts the feed behind
                // everything else. Default priority renders it over the shoe.
                .priority(CAMERA_PRIORITY)
                // ⚠️ **TRIANGLE_STRIP, not TRIANGLES, and the indices are why.** The quad
                // provides four vertices in strip order (`INDICES`); as TRIANGLES that is one
                // triangle plus a dangling index — half a screen of camera, or no primitive at
                // all once Filament rejects a non-multiple-of-three index count.
                .geometry(
                    0,
                    RenderableManager.PrimitiveType.TRIANGLE_STRIP,
                    vertices,
                    indices,
                )
                .material(0, instance)
                .build(engine, entity)
            scene.addEntity(entity)

            // ⚠️ Hidden until ARCore has actually produced a frame. A visible-but-unbound
            // external texture samples as opaque black, which is exactly the picture this class
            // exists to remove — so the first frame of the session stays on the clear colour for a
            // beat rather than flashing black over it.
            setVisible(engine, false)

            releaseCurrent()
            ready = true
            Log.i(TAG, "camera feed ready: texture=$cameraTextureId")
        } catch (t: Throwable) {
            failureReason = "feed_setup_failed: ${t.message}"
            Log.w(TAG, "camera feed: setup failed", t)
        }
    }

    /**
     * **Points ARCore at this feed's texture, and returns the texture name it bound (or null).**
     *
     * Called before `Session.resume()`: ARCore starts writing frames as soon as the session is
     * live, and a texture bound afterwards leaves the first frames — and any frame after a
     * session restart — unrendered.
     *
     * ⚠️ The call is `runCatching`-guarded because a session that is already resumed rejects it,
     * and because the failure is survivable: without it the feed simply never gets pixels, which
     * [update] cannot reveal, and the reason is what the screen reports.
     */
    fun bindToSession(session: Session): Int? {
        val id = cameraTextureId
        if (id == 0 || !ready) {
            if (failureReason == null) failureReason = "texture_not_created"
            return null
        }
        return runCatching {
            session.setCameraTextureName(id)
            id
        }.onFailure { t ->
            failureReason = "set_camera_texture_failed: ${t.message}"
            Log.w(TAG, "camera feed: setCameraTextureName failed", t)
        }.getOrNull()
    }

    /**
     * Per-frame: bind the texture ARCore wrote into, and re-derive the quad's UVs when the display
     * geometry changed (rotation, viewport resize — and once at the start).
     */
    fun update(engine: Engine, session: Session, frame: Frame) {
        if (!ready) return
        val instance = materialInstance ?: return
        val texture = cameraTexture ?: return

        // ARCore owns the texture's contents; `getCameraTextureName` is the id it actually used,
        // and it is compared rather than assumed because a second session in the same process can
        // legitimately choose a different one.
        if (frame.cameraTextureName != cameraTextureId) {
            Log.w(
                TAG,
                "camera feed: ARCore is writing texture ${frame.cameraTextureName}, " +
                    "this feed owns $cameraTextureId",
            )
        }
        instance.setParameter("cameraTexture", texture, EXTERNAL_SAMPLER)

        if (transformedUvs == null || frame.hasDisplayGeometryChanged()) {
            val source = viewUvs ?: return
            val target = transformedUvs ?: clone(source).also { transformedUvs = it }
            source.rewind()
            target.rewind()
            frame.transformCoordinates2d(
                Coordinates2d.VIEW_NORMALIZED,
                source,
                Coordinates2d.TEXTURE_NORMALIZED,
                target,
            )
            // ⚠️ **This flip is one half of a pair, and the device proved it (2026-10-05).** It is
            // SceneView's own line — `ARCameraStream` flips the transform's output V with the
            // comment "Adjust Camera Uvs for OpenGL" — and its other half is the *input*
            // convention in [CAMERA_UVS]: `VIEW_NORMALIZED` is top-left origin, v down. The run
            // that had this flip but the old bottom-left/y-up input (the display geometry was
            // already correct by then, so the quad showed a real image for the first time) drew
            // the room **upside down**; restoring the pair exactly as `ARCameraStream` ships it is
            // what makes the two cancel.
            target.rewind()
            for (i in 0 until target.capacity() step 2) {
                target.put(i + 1, 1f - target.get(i + 1))
            }
            target.rewind()
            vertexBuffer?.setBufferAt(engine, 1, target)
        }

        // First frame with real pixels: reveal the feed. Until this runs the quad is hidden, so a
        // session that never produces a frame keeps the clear colour instead of a black rectangle.
        setVisible(engine, true)
    }

    /** The one-line state a device log is read from: is the room being drawn, and if not, why. */
    fun describe(): String {
        val reason = failureReason
        return if (ready) "ready (texture=$cameraTextureId)" else "not ready: ${reason ?: "unknown"}"
    }

    /** Called when the session stops tracking badly enough that the last frame is stale. */
    fun hide(engine: Engine) {
        if (ready) setVisible(engine, false)
    }

    /** Render-thread teardown, in the reverse order of [attach]. */
    fun destroy(engine: Engine?) {
        if (entity != 0 && engine != null) {
            engine.destroyEntity(entity)
            runCatching { EntityManager.get().destroy(entity) }
        }
        entity = 0
        vertexBuffer?.let { engine?.destroyVertexBuffer(it) }
        indexBuffer?.let { engine?.destroyIndexBuffer(it) }
        cameraTexture?.let { engine?.destroyTexture(it) }
        // ⚠️ Instance **before** material, and explicitly: `destroyMaterial` panics in native code
        // when instances are still alive (`destroying material "flat" but 1 instance still alive`),
        // which is the same `PreconditionPanic` class that aborted this view's teardown once
        // already. The instance is ours (see [attach]), so this order is unambiguous.
        materialInstance?.let { engine?.destroyMaterialInstance(it) }
        material?.let { engine?.destroyMaterial(it) }
        materialInstance = null
        vertexBuffer = null
        indexBuffer = null
        cameraTexture = null
        material = null
        ready = false
        destroyEglContext()
        if (cameraTextureId != 0) {
            // The texture was created in a context that is now gone; GL handles are per-context, so
            // there is nothing left to delete it in. Dropped, and recreated on the next attach.
            cameraTextureId = 0
        }
    }

    private fun setVisible(engine: Engine, visible: Boolean) {
        if (entity == 0) return
        val manager = engine.renderableManager
        if (manager.hasComponent(entity)) {
            manager.setLayerMask(entity, 0x1, if (visible) 0x1 else 0x0)
        }
    }

    // ── EGL ─────────────────────────────────────────────────────────────────────────────────

    /**
     * A minimal ES3 context with a 1×1 pbuffer, which is all an off-screen texture producer needs.
     *
     * Taken from SceneView's `utils/OpenGL` so the context Filament is handed is the same shape as
     * the one its own AR view has always used — a context the engine demonstrably shares with.
     */
    private fun createEglContext(shared: EGLContext?): EGLContext {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }
        eglDisplay = display

        val attributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        check(
            EGL14.eglChooseConfig(display, attributes, 0, configs, 0, configs.size, numConfigs, 0) &&
                numConfigs[0] > 0,
        ) { "eglChooseConfig failed" }
        val config = configs[0] ?: error("eglChooseConfig returned no config")

        val context = EGL14.eglCreateContext(
            display,
            config,
            shared ?: EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
            0,
        )
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        val surface = EGL14.eglCreatePbufferSurface(
            display,
            config,
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0,
        )
        check(surface != EGL14.EGL_NO_SURFACE) { "eglCreatePbufferSurface failed" }
        eglSurface = surface
        return context
    }

    /**
     * **ARCore's GL-context contract, made callable (V4.9, 2026-10-05).**
     *
     * `Session` binds itself to the GL context that is **current on the thread that constructs
     * it**, and `update()` requires that same context to be current on the thread that calls it. The
     * view's render thread had no context current — the feed releases it at the end of [attach] and
     * Filament binds its own only while it draws — so a started session threw
     * `MissingGlContextException` on **every** frame (`session.update threw; keeping the last pose`,
     * measured on the Redmi 24094RAD4G, QA 1.0.45) and the camera never drew a pixel.
     *
     * The context this binds is the feed's own: the one the camera texture was created in, and the
     * one Filament's engine was built to share (`prepareSharedContext` → `sharedContext`). So the
     * texture ARCore writes and the session that writes it belong to one context, and the same
     * context is current for construction and for every `update()`.
     *
     * Pair it with [releaseArContext]. The return says whether the binding happened; a `false` is
     * reported on the diagnostics line rather than thrown, because losing the room must not cost
     * the shoe, and must never take the process down with it.
     */
    fun makeArContextCurrent(): Boolean {
        val display = eglDisplay ?: return false
        val context = eglContext ?: return false
        val surface = eglSurface ?: return false
        return runCatching { EGL14.eglMakeCurrent(display, surface, surface, context) }
            .getOrDefault(false)
    }

    /** Unbinds what [makeArContextCurrent] bound, restoring the render thread's prior state. */
    fun releaseArContext() = releaseCurrent()

    private fun makeCurrent(shared: EGLContext) {
        val display = eglDisplay ?: return
        check(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, shared)) {
            "eglMakeCurrent failed"
        }
    }

    private fun releaseCurrent() {
        val display = eglDisplay ?: return
        runCatching {
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
        }
    }

    private fun destroyEglContext() {
        val display = eglDisplay
        if (display != null) {
            eglSurface?.let { runCatching { EGL14.eglDestroySurface(display, it) } }
            eglContext?.let { runCatching { EGL14.eglDestroyContext(display, it) } }
            runCatching { EGL14.eglTerminate(display) }
        }
        eglSurface = null
        eglContext = null
        eglDisplay = null
    }

    // ── Small helpers ───────────────────────────────────────────────────────────────────────

    private fun readAsset(path: String): ByteArray? = try {
        context.assets.open(path).use(InputStream::readBytes)
    } catch (t: Throwable) {
        Log.w(TAG, "camera feed: could not read $path", t)
        null
    }

    private fun clone(source: FloatBuffer): FloatBuffer {
        val copy = ByteBuffer.allocateDirect(source.capacity() * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        source.rewind()
        copy.put(source)
        copy.rewind()
        return copy
    }

    private companion object {
        const val TAG = "ArCameraFeed"

        /**
         * The vendored material — Apache-2.0, from SceneView 4.34.0's `arsceneview` artifact,
         * whose license and provenance are recorded in the roadmap (findings F20). Kept at the
         * same asset path it had there so the two can be diffed.
         */
        const val ASSET_PATH = "materials/camera_stream_flat.filamat"

        /**
         * SceneView's own camera-stream value. `priority` is the one that matters: at the default
         * priority the full-screen quad draws over the shoe and the room hides the model.
         */
        const val CAMERA_PRIORITY = 7

        const val VERTEX_STRIDE = 3 * 4
        const val UV_STRIDE = 2 * 4

        /** NDC corners in `TRIANGLE_STRIP` order (SceneView's `CAMERA_VERTICES`). */
        val CAMERA_VERTICES = floatArrayOf(
            -1f, -1f, 0f,
            1f, -1f, 0f,
            -1f, 1f, 0f,
            1f, 1f, 0f,
        )

        /**
         * The same corners in `VIEW_NORMALIZED` space — **top-left origin, v down**, which is the
         * convention ARCore documents for a view ("Android view, display-rotated") and the one
         * SceneView's `ARCameraStream` — where this quad, its UVs and the material all come from —
         * feeds to `Frame.transformCoordinates2d`.
         *
         * ⚠️ **These were seeded bottom-left/y-up until 2026-10-05, and it put the room upside
         * down on the device.** The v flip in [update] (SceneView's "Adjust Camera Uvs for
         * OpenGL") only corrects the texture's own bottom-up convention; it cannot also undo an
         * input expressed in the wrong view convention — the two together are the recipe, and
         * they were verified as a pair on device.
         */
        val CAMERA_UVS = floatArrayOf(
            0f, 1f, // bottom-left
            1f, 1f, // bottom-right
            0f, 0f, // top-left
            1f, 0f, // top-right
        )

        val INDICES = shortArrayOf(0, 1, 2, 3)

        /** Identity: the UV mapping is ARCore's transform, not a matrix of ours. */
        val UV_TRANSFORM = floatArrayOf(
            1f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0f, 0f, 0f, 1f,
        )

        /**
         * LINEAR/LINEAR/CLAMP_TO_EDGE — what an OES camera texture can legally be sampled with,
         * and what SceneView's own `TextureSamplerExternal` passes.
         */
        val EXTERNAL_SAMPLER = TextureSampler(
            TextureSampler.MinFilter.LINEAR,
            TextureSampler.MagFilter.LINEAR,
            TextureSampler.WrapMode.CLAMP_TO_EDGE,
        )

        const val EGL_OPENGL_ES3_BIT = 0x40
    }
}
