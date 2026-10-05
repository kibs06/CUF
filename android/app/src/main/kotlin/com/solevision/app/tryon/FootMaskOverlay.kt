package com.solevision.app.tryon

import android.content.Context
import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndexBuffer
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.Scene
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.VertexBuffer
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * **V4.4's occlusion draw: [FootMaskMesh]'s quads, painted with the camera's own material.**
 *
 * The mask is drawn *after* the shoe (priority 0 against the shoe's 1 and the camera feed's 7)
 * with `camera_stream_flat.filamat` — the very material the full-screen feed uses — so the pixels
 * it puts over the shoe are the pixels the feed is already showing there. That equivalence is what
 * makes the foot read as **inside** the shoe, and it is exact rather than approximate: same
 * texture, same shader, same frame.
 *
 * ## Why not a stencil buffer
 *
 * Filament 1.72.1 does expose per-instance stencil state, and a stencil design is writable: the
 * mask pass marks the foot's pixels, the shoe's material instances test the mark and discard. Both
 * halves are outside a desk's reach here — the stencil attachment has to be configured on the
 * swap chain (a change to how this view's surface is created, with a black screen as the failure
 * mode), and the shoe's instances belong to glTF's material provider rather than to this plugin.
 * The repaint ends in the same pixels with neither, and its worst case is *no occlusion*, not no
 * shoe. §2.10's contract (`setFootMask`) is unchanged either way: a mask-shaped draw is what the
 * feature was specified as.
 *
 * ## Depth, draw order, and the belt-and-braces
 *
 * Two independent things make the shoe yield to the mask, because either one alone can be undone
 * by a driver or an ordering surprise:
 *
 *  1. **Draw order.** The instance is built at [FOOT_MASK_PRIORITY] (0), the shoe is pushed to 1 by
 *     [ArTryOnView]'s load path, and Filament draws higher priorities first — the feed's `priority(7)`
 *     is the same rule, from SceneView.
 *  2. **Depth.** The instance clears depth *testing* (`setDepthCulling(false)`) so no earlier pass
 *     can reject it, and *writes* near depth so a shoe drawn afterwards fails the test inside the
 *     mask instead of painting over it. The near value comes from the vendored material's own
 *     vertex stage, which remaps `z → 0.5 − 0.5z` before the backend's clip-space conversion:
 *     [MASK_NDC_Z] = 3.0 lands at NDC −1 (depth 0, nearest) on both the GL and Vulkan conventions.
 *
 * Vertex data is rebuilt per accepted mask (≥5 Hz, 32×32 → up to [FootMaskMesh.MAX_QUADS] quads).
 * The vertex and index buffers are sized once for the worst case and re-uploaded per submission —
 * Filament's `setGeometryAt` then narrows the draw count, so no Filament object is created or
 * destroyed per frame.
 */
internal class FootMaskOverlay(private val context: Context) {

    private var material: Material? = null
    private var instance: MaterialInstance? = null
    private var vertexBuffer: VertexBuffer? = null
    private var indexBuffer: IndexBuffer? = null
    private var entity = 0
    private var ready = false
    private var visible = false

    /** Diagnostics for the QA heartbeat: what the last accepted mask contained. */
    private var lastMaskMs = 0L
    private var lastConfidence = 0.0
    private var lastQuads = 0

    var failureReason: String? = null
        private set

    val isReady: Boolean get() = ready

    /**
     * Builds the material instance, the worst-case buffers and the (hidden) renderable.
     *
     * Runs on the render thread, after the engine and scene exist, and **after [ArCameraFeed.attach
     * has succeeded** — the overlay samples the feed's own imported texture rather than importing a
     * second one, because an imported `Texture` is only meaningful inside the EGL context that
     * created it and that context belongs to the feed. [cameraTexture] null means the feed is not
     * ready, and the honest answer is no overlay: an unbound external texture samples black, and
     * painting black over the shoe is worse than not occluding it.
     */
    fun attach(engine: Engine, scene: Scene, cameraTexture: Texture?) {
        if (ready) return
        if (cameraTexture == null) {
            failureReason = "no_camera_texture"
            return
        }
        try {
            val bytes = readAsset(ASSET_PATH)
            if (bytes == null) {
                failureReason = "material_missing: $ASSET_PATH"
                return
            }
            val built = Material.Builder()
                .payload(ByteBuffer.wrap(bytes), bytes.size)
                .build(engine)
            // The same version check [ArCameraFeed] does, for the same reason: a `.filamat` is
            // locked to the Filament that compiled it, and a mismatch here would draw nothing
            // rather than error. The overlay loads its own Material object — sharing the feed's
            // would couple two lifecycles for one 42 KB asset, and the teardown order that keeps
            // `destroyMaterial` from panicking over live instances is only unambiguous when each
            // owner destroys its own.
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

            val created = built.createInstance()
            // Identity: the coordinate work is ARCore's `transformCoordinates2d` (below), exactly
            // as it is for the feed.
            created.setParameter(
                "uvTransform",
                MaterialInstance.FloatElement.FLOAT4,
                UV_TRANSFORM,
                0,
                UV_TRANSFORM.size / 4,
            )
            created.setParameter("cameraTexture", cameraTexture, EXTERNAL_SAMPLER)
            // V4.4's depth contract — see the class doc. All three are per-instance overrides, so
            // the feed's use of the same material is untouched.
            created.setDepthCulling(false)
            created.setDepthWrite(true)
            // Insurance against a winding or culling default we cannot read out of the compiled
            // material: the quads below are wound counter-clockwise (front), and this makes the
            // material indifferent to it either way.
            created.setDoubleSided(true)
            instance = created

            val vertices = VertexBuffer.Builder()
                .vertexCount(MAX_VERTICES)
                .bufferCount(2)
                .attribute(
                    VertexBuffer.VertexAttribute.POSITION,
                    0,
                    VertexBuffer.AttributeType.FLOAT3,
                    0,
                    POSITION_STRIDE,
                )
                .attribute(
                    VertexBuffer.VertexAttribute.UV0,
                    1,
                    VertexBuffer.AttributeType.FLOAT2,
                    0,
                    UV_STRIDE,
                )
                .build(engine)
            val indices = IndexBuffer.Builder()
                .indexCount(MAX_INDICES)
                .bufferType(IndexBuffer.Builder.IndexType.USHORT)
                .build(engine)
            vertexBuffer = vertices
            indexBuffer = indices

            entity = EntityManager.get().create()
            RenderableManager.Builder(1)
                .castShadows(false)
                .receiveShadows(false)
                // Bounding-box culling, not backface: a mask quad is a screen-space shape and has
                // no meaningful bounds, and the arm's buffers are re-uploaded per frame.
                .culling(false)
                .priority(FOOT_MASK_PRIORITY)
                .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, vertices, indices)
                .material(0, created)
                .build(engine, entity)
            scene.addEntity(entity)
            // Hidden until a real mask is uploaded: the buffers are uninitialised at this point
            // and the default geometry count is the whole capacity.
            setVisible(engine, false)
            ready = true
            Log.i(TAG, "overlay ready")
        } catch (t: Throwable) {
            failureReason = "overlay_setup_failed: ${t.message}"
            Log.w(TAG, "overlay: setup failed", t)
        }
    }

    /**
     * Uploads one accepted frame's mask and draws it.
     *
     * [mapUv] maps a normalized upright-image point to viewport pixels — the *same* mapping
     * [ArTryOnView.hitTestFloorPoint] casts the heel and toe rays through, so the occlusion lands
     * exactly where the pose landed. It writes `[px, py]` into the array it is handed and answers
     * false while the frame geometry is unknown (an object, not a fresh array, because a mask is
     * up to 16 K corners at ≥5 Hz and this runs on the render thread).
     *
     * Returns the number of quads drawn, 0 when nothing was drawn this frame.
     */
    fun submit(
        engine: Engine,
        frame: Frame,
        quads: FootMaskMesh.Quads,
        viewportWidth: Int,
        viewportHeight: Int,
        confidence: Double,
        nowMs: Long,
        mapUv: (Double, Double, FloatArray) -> Boolean,
    ): Int {
        if (!ready || viewportWidth <= 0 || viewportHeight <= 0) return 0
        if (quads.isEmpty || confidence < MIN_FOOT_MASK_CONFIDENCE) {
            hide(engine)
            return 0
        }

        val corners = quads.count * 4
        val positions = FloatArray(corners * 3)
        val uvs = FloatArray(corners * 2)
        val indices = ShortArray(quads.count * 6)
        // Direct buffers, like the feed's: `setBufferAt` reads from native code after this method
        // returns, and a heap-backed buffer's contents are not guaranteed to still be there.
        val viewPoints = directFloats(corners * 2)
        val texturePoints = directFloats(corners * 2)
        val pixels = FloatArray(2)

        for (q in 0 until quads.count) {
            val b = q * 4
            val u0 = quads.bounds[b]
            val v0 = quads.bounds[b + 1]
            val u1 = quads.bounds[b + 2]
            val v1 = quads.bounds[b + 3]

            // Corners A(u0,v0) B(u1,v0) C(u0,v1) D(u1,v1). Triangles (A,C,B) and (C,D,B) are
            // counter-clockwise once v is flipped into NDC's y-up frame, which is the winding the
            // feed's own quad uses.
            for (corner in 0 until 4) {
                val u = if (corner == 1 || corner == 3) u1 else u0
                val v = if (corner == 2 || corner == 3) v1 else v0
                if (!mapUv(u.toDouble(), v.toDouble(), pixels)) return 0
                val px = pixels[0]
                val py = pixels[1]
                val vertex = q * 4 + corner

                positions[vertex * 3] = px * 2f / viewportWidth - 1f
                positions[vertex * 3 + 1] = 1f - py * 2f / viewportHeight
                positions[vertex * 3 + 2] = MASK_NDC_Z

                // ARCore's view space is bottom-left origin; pixels are top-down.
                viewPoints.put(vertex * 2, px / viewportWidth)
                viewPoints.put(vertex * 2 + 1, 1f - py / viewportHeight)
            }

            val base = q * 4
            indices[q * 6] = base.toShort()
            indices[q * 6 + 1] = (base + 2).toShort()
            indices[q * 6 + 2] = (base + 1).toShort()
            indices[q * 6 + 3] = (base + 2).toShort()
            indices[q * 6 + 4] = (base + 3).toShort()
            indices[q * 6 + 5] = (base + 1).toShort()
        }

        // The sampling coordinates, straight from ARCore — the same call the feed makes for its
        // full-screen quad — and inverted in V for the same reason the feed inverts its own: the
        // vendored material's vertex stage samples at `1 - mesh_uv0.y` (see [ArCameraFeed.update]),
        // so an un-inverted transform output would paint the wrong pixels over the shoe.
        viewPoints.rewind()
        texturePoints.rewind()
        frame.transformCoordinates2d(
            Coordinates2d.VIEW_NORMALIZED,
            viewPoints,
            Coordinates2d.TEXTURE_NORMALIZED,
            texturePoints,
        )
        texturePoints.rewind()
        texturePoints.get(uvs)
        for (i in uvs.indices step 2) {
            uvs[i + 1] = 1f - uvs[i + 1]
        }

        val positionBytes = directBytes(positions.size * Float.SIZE_BYTES)
        positionBytes.asFloatBuffer().put(positions)
        positionBytes.rewind()
        val uvBytes = directBytes(uvs.size * Float.SIZE_BYTES)
        uvBytes.asFloatBuffer().put(uvs)
        uvBytes.rewind()
        val indexBytes = directBytes(indices.size * Short.SIZE_BYTES)
        indexBytes.asShortBuffer().put(indices)
        indexBytes.rewind()

        val vertices = vertexBuffer
        val indicesBuffer = indexBuffer
        if (vertices == null || indicesBuffer == null) return 0
        vertices.setBufferAt(engine, 0, positionBytes)
        vertices.setBufferAt(engine, 1, uvBytes)
        indicesBuffer.setBuffer(engine, indexBytes)

        val manager = engine.renderableManager
        val renderable = manager.getInstance(entity)
        manager.setGeometryAt(
            renderable,
            0,
            RenderableManager.PrimitiveType.TRIANGLES,
            vertices,
            indicesBuffer,
            0,
            indices.size,
        )

        lastQuads = quads.count
        lastConfidence = confidence
        lastMaskMs = nowMs
        setVisible(engine, true)
        return quads.count
    }

    /**
     * Per frame: hide the mask once it is stale.
     *
     * [STALE_MS] is deliberately the same 700 ms [FootPoseTracker] keeps an anchor through: a mask
     * outliving its frame by longer than the anchor outlives its pose would paint an old foot over
     * a shoe that has already moved.
     */
    fun update(engine: Engine, nowMs: Long) {
        if (!ready || !visible) return
        if (nowMs - lastMaskMs > STALE_MS) hide(engine)
    }

    /** The one line the QA heartbeat reads: is the foot being cut out, and out of what. */
    fun describe(): String {
        if (!ready) return "not ready: ${failureReason ?: "unknown"}"
        if (!visible) {
            return if (lastQuads == 0) "ready (no mask yet)" else "ready (stale)"
        }
        return "ready (${lastQuads}q, ${(lastConfidence * 100).toInt()}%)"
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
        // Instance before material, explicitly: `destroyMaterial` panics in native code when
        // instances are still alive (the same trap [ArCameraFeed.destroy] documents).
        instance?.let { engine?.destroyMaterialInstance(it) }
        material?.let { engine?.destroyMaterial(it) }
        instance = null
        material = null
        vertexBuffer = null
        indexBuffer = null
        ready = false
        visible = false
        lastQuads = 0
    }

    // ── Internals ───────────────────────────────────────────────────────────────────────────

    private fun setVisible(engine: Engine, show: Boolean) {
        if (entity == 0) return
        val manager = engine.renderableManager
        if (manager.hasComponent(entity)) {
            manager.setLayerMask(entity, 0x1, if (show) 0x1 else 0x0)
        }
        visible = show
    }

    /** Hides the mask now — a mode switch or a fresh session, ahead of [STALE_MS]. */
    fun hide(engine: Engine) {
        if (visible) setVisible(engine, false)
    }

    private fun directFloats(count: Int): FloatBuffer =
        directBytes(count * Float.SIZE_BYTES).asFloatBuffer()

    private fun directBytes(bytes: Int): ByteBuffer =
        ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())

    private fun readAsset(path: String): ByteArray? = try {
        context.assets.open(path).use(InputStream::readBytes)
    } catch (t: Throwable) {
        Log.w(TAG, "overlay: could not read $path", t)
        null
    }

    companion object {
        private const val TAG = "FootMaskOverlay"

        /** The feed's own vendored material — one shader, two instances' worth of pixels. */
        private const val ASSET_PATH = "materials/camera_stream_flat.filamat"

        /** Drawn after the shoe at [SHOE_PRIORITY] (see the class doc). */
        private const val FOOT_MASK_PRIORITY = 0

        /** The shoe's priority, written by [ArTryOnView] at load: after the feed, before the mask. */
        const val SHOE_PRIORITY = 1

        private const val MAX_VERTICES = FootMaskMesh.MAX_QUADS * 4
        private const val MAX_INDICES = FootMaskMesh.MAX_QUADS * 6
        private const val POSITION_STRIDE = 3 * 4
        private const val UV_STRIDE = 2 * 4

        /**
         * The z that lands nearest after the material's `z → 0.5 − 0.5z` remap — see the class doc.
         * (3.0 → NDC −1 in GL's clip convention; the Vulkan conversion maps that to depth 0 too.)
         */
        private const val MASK_NDC_Z = 3.0f

        /** How long a mask keeps drawing without a new one. */
        private const val STALE_MS = 700L

        /**
         * Floor against a malformed sender. Accepted detections carry `qualityScore ≥ 0.7` — the
         * Dart gate's own threshold — so nothing the loop sends is affected by this.
         */
        private const val MIN_FOOT_MASK_CONFIDENCE = 0.2

        /** Identity — the coordinate work is ARCore's, exactly as in [ArCameraFeed]. */
        private val UV_TRANSFORM = floatArrayOf(
            1f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0f, 0f, 0f, 1f,
        )

        private val EXTERNAL_SAMPLER = TextureSampler(
            TextureSampler.MinFilter.LINEAR,
            TextureSampler.MagFilter.LINEAR,
            TextureSampler.WrapMode.CLAMP_TO_EDGE,
        )
    }
}
